"""Compare every shared public output to frozen RTL; verify declared additions separately."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
MODULES=['sd_data_block_reader','sd_init_controller','sd_command_engine',
 'frame_burst_prefetch','frame_buffer_manager','video_pixel_sink','video_raster_timing',
 'media_playlist_control','fat32_file_reader','fat32_dir_scan','fat32_volume_locator',
 'em638325_stream_controller']

# Exact interface deltas since the frozen safety-counter baseline. Unknown
# ports/parameters must fail adapter generation rather than silently vanish.
ADDED_PORTS={
 'frame_burst_prefetch':{'slide_active':('input',''),'slide_right':('input',''),'slide_offset':('input','[15:0]')},
 'frame_buffer_manager':{'discard_frame':('input',''),'prepare_pixels':('output','[6:0]')},
 'media_playlist_control':{'prev_pulse':('input','')},
 'fat32_dir_scan':{'wav_index':('input','[1:0]'),'wav_count':('output','[2:0]')},
 'fat32_volume_locator':{'bpb_fields':('output','[255:0]'),'bpb_result':('input','[128:0]')},
}
ADDED_PARAMETERS={
 'frame_burst_prefetch':{'SLIDE_TRANSITIONS','LINE_PIXELS'},
 'frame_buffer_manager':{'ALLOW_DISCARD'},
 'fat32_dir_scan':{'INDEX_BITS','COUNT_BITS','MAX_WAVS'},
 'fat32_volume_locator':{'SHARED_BPB'},
}
WIDTH_CHANGES={'fat32_dir_scan':{
 'found_index':('[INDEX_BITS-1:0]','[1:0]'),
 'found_count':('[COUNT_BITS-1:0]','[2:0]')}}
REFERENCE_OVERRIDES={
 'em638325_stream_controller':{
  'path':HERE/'reference_s01_em638325_stream_controller.v',
  'sha256':'27925c5c6af0bec2ee11031cf41eca6ba3b297fd212123313dca163fdc4dcb7c',
  'reason':'Accepted S01 inserts a CHECK command-validation stage, intentionally changing transaction latency. Compare to that frozen accepted stage and run independent command/refresh/SDRAM-model tests below; do not change the original 20261018 baseline.',
 },
}
ADDITION_ACCEPTANCE={
 'frame_buffer_manager.prepare_pixels':'tb_prepare_count runs in this suite: independent accepted-write scoreboard; valid/ready stalls, drain, commit, reject and reset',
 'frame_buffer_manager.discard_frame':'ALLOW_DISCARD=0 enforced here; enabled cache discard tested in tests/next_prefetch/verify.py',
 'frame_burst_prefetch.slide_active/slide_right/slide_offset':'SLIDE_TRANSITIONS=0 enforced here; enabled addressing tested in tests/slide/verify.py',
 'media_playlist_control.prev_pulse':'prev_pulse=0 enforced here; reverse/pending navigation tested in tests/four_key/verify.py and tests/gallery24/verify.py',
 'fat32_dir_scan.wav_index/wav_count':'MAX_WAVS=1 enforced; new wav_count checked here against wav_found every cycle; four-WAV catalog tested in tests/music_select/verify.py',
 'fat32_volume_locator.bpb_fields/bpb_result':'Shared arithmetic public results compared here to frozen independent private arithmetic; complete bus contract tested in tests/bpb_share/verify.py',
}


def interface(text,name):
    clean=re.sub(r'//[^\n]*|/\*.*?\*/',lambda m:' '*len(m[0]),text,flags=re.S)
    h=re.search(r'\bmodule\s+'+name+r'\s*#\s*\((.*?)\)\s*\((.*?)\)\s*;',clean,re.S)
    assert h,name
    parameters=re.findall(r'\b(\w+)\s*=',h[1])
    parts=re.split(r'\b(input|output|inout)\b',h[2]);ports=[]
    for i in range(1,len(parts),2):
        declaration=re.sub(r'\b(wire|reg|signed)\b','',parts[i+1]).strip().rstrip(',').strip()
        width=re.match(r'(\[[^]]+\])\s*(.*)',declaration,re.S)
        names=width[2] if width else declaration
        for p in names.split(','):ports.append((p.strip(),parts[i],re.sub(r'\s+','',width[1]) if width else ''))
    return clean,h,parameters,ports


def instrument(text,name,reference_text):
    # Keep source offsets so a helper module in the same file stays outside
    # the monitor inserted into the target module.
    clean,h,parameters,ports=interface(text,name)
    _,_,old_parameters,old_ports=interface(reference_text,name)
    current={p:(d,w) for p,d,w in ports};old={p:(d,w) for p,d,w in old_ports}
    assert not old.keys()-current.keys(),(name,'removed historical port',old.keys()-current.keys())
    assert {p:current[p] for p in current.keys()-old.keys()}==ADDED_PORTS.get(name,{}),(name,'unreviewed port additions')
    assert set(parameters)-set(old_parameters)==ADDED_PARAMETERS.get(name,set()),(name,'unreviewed parameter additions')
    assert not set(old_parameters)-set(parameters),(name,'removed historical parameter')
    for p in old:
        assert current[p][0]==old[p][0],(name,p,'port direction changed')
        if current[p][1]!=old[p][1]:
            assert WIDTH_CHANGES.get(name,{}).get(p)==(current[p][1],old[p][1]),(name,p,'unreviewed port width change')
    parameters=[p for p in parameters if p in old_parameters]
    ports=[p for p in ports if p[0] in old]
    outputs=[p for p,d,w in ports if d=='output']
    declarations='\n'.join('wire '+w+' __safety_'+p+';' for p,d,w in ports if d=='output')
    # Reverse navigation is tested separately. Keep the frozen oracle exact
    # for its original next-only domain and reject nonzero reverse input.
    args=',\n'.join('.'+p+'('+('__safety_'+p if d=='output' else p)+')' for p,d,w in ports)
    params=','.join('.'+p+'('+p+')' for p in parameters)
    clock={'frame_burst_prefetch':'sys_clk','video_pixel_sink':'pix_clk'}.get(name,'clk')
    extra='\n'+declarations+'\n'+name+'_safety_reference #('+params+') __safety_reference('+args+');\n'
    extra+='integer __safety_cycles=0;\nalways @(negedge '+clock+')begin\n #1;\n if(rst_n===1\'b1)begin\n'
    extra+='  __safety_cycles=__safety_cycles+1;\n  if({'+','.join(outputs)+'} !== {'+','.join('__safety_'+p for p in outputs)+'})\n'
    extra+='   $fatal(1,"public cycle mismatch '+name+' %m cycle=%0d",__safety_cycles);\n end\nend\n'
    if name=='fat32_dir_scan':
        extra+='initial if(MAX_WAVS!=1)$fatal(1,"Frozen directory oracle requires one WAV; music selection has an independent test");\n'
        extra+='always @(negedge clk)begin #1;if(rst_n===1\'b1 && wav_count !== (wav_found?3\'d1:3\'d0))$fatal(1,"New one-WAV count output disagrees with accepted catalog");end\n'
    if name=='media_playlist_control':
        extra+='always @(negedge clk)if(rst_n===1\'b1 && prev_pulse!==1\'b0)$fatal(1,"Next-only oracle requires prev_pulse=0; reverse navigation has its own regression");\n'
    if name=='frame_buffer_manager':
        extra+='initial if(ALLOW_DISCARD!=0)$fatal(1,"Legacy oracle requires ALLOW_DISCARD=0; cache discard has its own regression");\n'
    if name=='fat32_dir_scan':
        extra+='initial if(MAX_FILES>4)$fatal(1,"Frozen directory oracle supports up to 4 files; 32-file catalogue has its own regression");\n'
    if name=='frame_burst_prefetch':
        extra+='initial if(SLIDE_TRANSITIONS!=0)$fatal(1,"Frozen burst oracle is linear-only; slide addressing has its own regression");\n'
    extra+='final $display("EQUIV '+name+' %m cycles=%0d",__safety_cycles);\n'
    end=re.search(r'\bendmodule\b',clean[h.end():])
    assert end,name
    position=h.end()+end.start()
    return '`timescale 1ns/1ps\n'+text[:position]+extra+text[position:]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir',type=Path,required=True)
    parser.add_argument('--sd-only',action='store_true')
    args=parser.parse_args();tools=args.tool_dir.resolve()
    frozen=ROOT/'reports/safety_counters_20261018/before/worktree/rtl'
    references={m:REFERENCE_OVERRIDES[m]['path'] if m in REFERENCE_OVERRIDES else frozen/(m+'.v') for m in MODULES}
    for item in REFERENCE_OVERRIDES.values():
        assert hashlib.sha256(item['path'].read_bytes()).hexdigest()==item['sha256'],'Frozen S01 reference was modified'
    # Exercise the adapter's fail-closed interface contract before simulation.
    current=(ROOT/'rtl/frame_buffer_manager.v').read_text(encoding='utf-8-sig')
    historical=(frozen/'frame_buffer_manager.v').read_text(encoding='utf-8-sig')
    adapter_rejections=[]
    mutations={
        'unknown output':current.replace('output wire [6:0] prepare_pixels);','output wire [6:0] prepare_pixels,output wire mystery);',1),
        'missing reviewed output':current.replace('prepare_pixels);','renamed_progress);',1),
        'new output wrong direction':current.replace('output wire [6:0] prepare_pixels','input wire [6:0] prepare_pixels',1),
        'historical port width changed':current.replace('input wire [31:0] pixel_addr','input wire [30:0] pixel_addr',1),
        'unknown parameter':current.replace('module frame_buffer_manager #(','module frame_buffer_manager #(parameter integer UNREVIEWED=0,',1),
    }
    for label,mutant in mutations.items():
        assert mutant!=current,label
        try:instrument(mutant,'frame_buffer_manager',historical)
        except AssertionError:adapter_rejections.append(label)
        else:raise AssertionError('Adapter accepted unreviewed interface change: '+label)
    sources=[ROOT/'rtl'/x.strip() for x in (ROOT/'sources.txt').read_text().splitlines() if x.strip()]
    hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    hashes.update({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in references.values()})
    hashes.update({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__).resolve(),ROOT/'tests/prepare_bar/tb_count.sv',ROOT/'tests/tb_sdram_command_guard.sv',ROOT/'tests/tb_sdram_refresh_deadline.sv']})
    logs=[];runs=[]
    def emit(s):logs.append(s);print(s,end='',flush=True)
    try:
        with tempfile.TemporaryDirectory(prefix='safety_counters_') as temporary:
            temporary=Path(temporary);refs=[]
            for name in MODULES:
                before=references[name].read_text(encoding='utf-8-sig')
                current=(ROOT/'rtl'/(name+'.v')).read_text(encoding='utf-8-sig')
                (temporary/(name+'.v')).write_text(instrument(current,name,before),encoding='utf-8')
                for m in MODULES:before=re.sub(r'\b'+m+r'\b',m+'_safety_reference',before)
                refs.append(before)
            reference=temporary/'references.v';reference.write_text('\n'.join(refs),encoding='utf-8')
            rtl=[temporary/p.name if p.stem in MODULES else p for p in sources]
            rtl += [reference,ROOT/'tests/clock_buffer_model.v',ROOT/'tests/em638325_model.sv']
            cases=[('tb_sd_counters',HERE/'tb_sd_counters.sv',{'LIMIT':n},[0]) for n in [1,2,3,7,8,9,31,32,33,228,256,257]]
            if not args.sd_only:
                cases += [('tb_playlist',ROOT/'tests/tb_playlist.sv',{},[0]),
                          ('tb_pipeline',ROOT/'tests/tb_pipeline.sv',{},list(range(8))),
                          ('tb_stream_memory',ROOT/'tests/tb_stream_memory.sv',{},[0]),
                          ('tb_full_display',ROOT/'tests/tb_full_display.sv',{'FULL':0},[0])]
                cases += [('tb_prepare_count',ROOT/'tests/prepare_bar/tb_count.sv',{},[0])]
                cases += [('tb_sdram_command_guard',ROOT/'tests/tb_sdram_command_guard.sv',{'RESPONSE':n},[0]) for n in [3,4]]
                cases += [('tb_sdram_refresh_deadline',ROOT/'tests/tb_sdram_refresh_deadline.sv',{},[0])]
                cases += [('tb_frame_address_bounds',ROOT/'tests/tb_frame_address_bounds.sv',{'PIXELS':n},[0]) for n in [1,2,3,7,8,9,24,255,256,257,640*480]]
                cases += [('tb_dir_bram',ROOT/'tests/dir_bram/tb_dir_bram.sv',{'MAX_FILES':n,'FIND_WAV':w},[0]) for n,w in [(1,0),(1,1),(4,0),(4,1)]]
                cases += [('tb_mbr_stream',ROOT/'tests/mbr_stream/tb_mbr_stream.sv',{'TIMEOUT_CYCLES':n},[0]) for n in [800,2048]]
                cases += [('tb_reader_width',ROOT/'tests/reader_width/tb_reader_width.sv',{'TIMEOUT_CYCLES':n},[0]) for n in [800,2048]]
            for top,bench,params,modes in cases:
                emit('RUN safety equivalence '+top+' '+str(params)+'\n')
                image=temporary/'check.vvp'
                options=[f'-P{top}.{k}={v}' for k,v in params.items()]
                compile_result=subprocess.run(list(map(str,[tools/'iverilog.exe','-g2012','-s',top,*options,'-o',image,*rtl,bench])),capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=60)
                if compile_result.returncode:raise RuntimeError(compile_result.stdout+compile_result.stderr)
                for mode in modes:
                    result=subprocess.run([str(tools/'vvp.exe'),str(image),f'+MODE={mode}'],cwd=ROOT/'tests',capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
                    output=result.stdout+result.stderr;emit(output)
                    if result.returncode or 'FATAL' in output or 'PASS' not in output:raise RuntimeError(f'{top} failed, mode={mode}')
                    checked=re.findall(r'EQUIV (\w+) .* cycles=(\d+)',output)
                    assert checked and all(int(n)>0 for _,n in checked),'Equivalence monitor did not run'
                    runs.append({'top':top,'params':params,'mode':mode,'monitors':[(m,int(n)) for m,n in checked]})
        for p,digest in hashes.items():assert hashlib.sha256(Path(p).read_bytes()).hexdigest()==digest,p
        covered={m for run in runs for m,_ in run['monitors']}
        assert covered==set(MODULES if not args.sd_only else MODULES[:3]),covered
        emit(f'PASS safety counters: {len(runs)} simulations; {len(covered)} modules covered, all shared public outputs match frozen RTL; declared new progress/count outputs independently checked; source hashes unchanged\n')
        (HERE/'summary.json').write_text(json.dumps({'passed':True,'runs':runs,'source_sha256':hashes,'module_count':len(covered),'simulations':len(runs),'module_clock_comparisons':sum(n for run in runs for _,n in run['monitors']),'explicit_interface_additions':ADDED_PORTS,'new_interface_acceptance':ADDITION_ACCEPTANCE,'new_progress_output_tested':not args.sd_only,'unknown_interface_differences_rejected':True,'adapter_negative_cases_rejected':adapter_rejections,'reference_overrides':{m:{**v,'path':v['path'].relative_to(ROOT).as_posix()} for m,v in REFERENCE_OVERRIDES.items()},'independent_S01_functional_guards_tested':not args.sd_only},indent=2),encoding='utf-8')
    finally:(HERE/('sd_only.log' if args.sd_only else 'regression.log')).write_text(''.join(logs),encoding='utf-8')


if __name__=='__main__':main()
