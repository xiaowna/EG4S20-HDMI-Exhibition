"""1.3x gallery timing and independent full-raster source/style validation."""
from pathlib import Path
import argparse,hashlib,json,subprocess,tempfile
from oracle import cases,expected_frame,fraction

ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent

def main():
    p=argparse.ArgumentParser();p.add_argument('--tool-dir',type=Path,required=True);a=p.parse_args()
    producer=[ROOT/'rtl'/n for n in ['intro_assets_rom.v','intro_text_layer.v','intro_line_store.v','frame_intro_prefetch.v']]
    wrapper=producer+[ROOT/'rtl/frame_burst_prefetch.v',ROOT/'rtl/pixel_async_fifo.v']
    paths=set(producer+wrapper+[ROOT/'rtl/frame_stream_display.v',ROOT/'rtl/media_prefetch_control.v',ROOT/'rtl/sd_media_player.v',ROOT/'rtl/sd_sector_arbiter.v',ROOT/'assets/intro_assets.json',ROOT/'tests/intro_animation/verify_producer.py',ROOT/'tests/intro_animation/line_bram32k_model.sv',ROOT/'tests/gallery_caption/pause_pipeline_stubs.sv'])
    paths.update(HERE.glob('*.sv'));paths.update(HERE.glob('*.py'))
    hashes={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    logs=[];configs=cases()
    def run(cmd,cwd):
        r=subprocess.run(list(map(str,cmd)),cwd=cwd,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=1200)
        output=r.stdout+r.stderr;logs.append(output);print(output,end='',flush=True)
        assert r.returncode==0 and 'FATAL' not in output,output
    try:
        with tempfile.TemporaryDirectory(prefix='gallery_motion_') as directory:
            t=Path(directory)
            for frames,name in [(9,'short_curve'),(10,'long_curve')]:
                (t/(name+'.hex')).write_text(''.join(f'{fraction(n,frames):x}\n' for n in range(frames)),encoding='ascii')
            for top,rtl,bench in [('tb_gallery_tempo',[ROOT/'rtl/frame_stream_display.v'],'tb_tempo.sv'),
                                  ('tb_gallery_autoplay',[ROOT/'rtl/media_prefetch_control.v'],'tb_autoplay.sv'),
                                  ('tb_gallery_descriptor',wrapper,'tb_descriptor.sv'),
                                  ('tb_gallery_interval_constants',[ROOT/'rtl/sd_media_player.v',ROOT/'rtl/media_prefetch_control.v',ROOT/'rtl/sd_sector_arbiter.v',ROOT/'tests/gallery_caption/pause_pipeline_stubs.sv'],'tb_interval_constants.sv')]:
                run([a.tool_dir/'iverilog.exe','-g2012','-s',top,'-o',t/'unit.vvp',*rtl,HERE/bench],t)
                run([a.tool_dir/'vvp.exe',t/'unit.vvp'],t)
            metadata=json.loads((ROOT/'assets/intro_assets.json').read_text(encoding='utf-8'))
            encoded=[]
            for n,case in enumerate(configs):
                frame=expected_frame(metadata,**case)
                (t/f'golden_{n}.hex').write_text(''.join(f'{int(x):06x}\n' for x in frame),encoding='ascii')
                encoded.append((case['topic']<<20)|(case['bank']<<19)|(int(case['slide_right'])<<18)|(case['style']<<16)|(case['slide_offset']<<6)|case['slide_alpha'])
            (t/'cases.hex').write_text(''.join(f'{x:x}\n' for x in encoded)+''.join('0\n' for _ in range(32-len(encoded))),encoding='ascii')
            for native in [False,True]:
                cmd=[a.tool_dir/'iverilog.exe','-g2012','-s','tb_gallery_motion_producer','-o',t/'producer.vvp']
                if native:cmd+=['-DINTRO_NATIVE_RAM',ROOT/'tests/intro_animation/line_bram32k_model.sv']
                run(cmd+producer+[HERE/'tb_producer.sv'],t)
                run([a.tool_dir/'vvp.exe',t/'producer.vvp',f'+CASES={len(configs)}'],t)
        assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==v for n,v in hashes.items()),'test sources changed during run'
        (HERE/'summary.json').write_text(json.dumps(dict(status='passed',styles=['push','reveal','banded_reveal'],
            slide_frames_per_13=120,baseline_frames_per_13=156,average_speed_ratio=1.3,
            default_autoplay_cycles=192307692,original_retry_cycles=250000000,
            producer_cases=configs,pixels_checked=len(configs)*307200*2,native_scanline_ports=True,
            hardware_tested=False,inputs_sha256=hashes),indent=2)+'\n',encoding='utf-8')
    finally:(HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')

if __name__=='__main__':main()
