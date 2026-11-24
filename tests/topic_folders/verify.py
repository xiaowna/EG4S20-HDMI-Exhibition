"""Folder catalogue, mounted BMP commits, topic identity and soft subtitle oracles."""
from pathlib import Path
import argparse,hashlib,json,struct,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent

def fixture(variant, first_count=2):
    data=bytearray(64*512)
    def u16(a,v):struct.pack_into('<H',data,a,v)
    def u32(a,v):struct.pack_into('<I',data,a,v)
    data[450]=12;u32(454,2048);u32(458,70632);data[510:512]=b'\x55\xaa'
    b=512;u16(b+11,512);data[b+13]=1;u16(b+14,32);data[b+16]=1
    u32(b+32,70632);u32(b+36,600);u32(b+44,2);data[b+510:b+512]=b'\x55\xaa'
    for c in range(2,100):u32(1024+c*4,0x0fffffff)
    def entry(cluster,index,name,attr,first,size):
        a=(3+cluster-2)*512+index*32
        data[a:a+11]=name.encode('ascii');data[a+11]=attr
        u16(a+20,first>>16);u16(a+26,first&65535);u32(a+28,size)
    if variant==2:
        for i in range(2):entry(2,i,f'ROOT{i+1:04}BMP',32,30+i,78)
        base=2
    else:
        entry(2,0,'IGNORED BMP',32,20,78)
        # Deliberately discover groups in reverse order.
        groups=[(5,first_count),(7,0),(9,3),(11,1)] if variant==0 else [(9,1)]
        for n,(cluster,count) in enumerate(reversed(groups)):
            g=(cluster-5)//2
            entry(2,n+1,f'TOPIC{g+1}     ',16,cluster,0)
        slot=0
        for cluster,count in groups:
            entry(cluster,0,'.          ',16,cluster,0)
            entry(cluster,1,'..         ',16,2,0)
            entry(cluster,2,'PRIVATE WAV',32,60,9000)
            for i in range(count):
                entry(cluster,i+3,f'PIC{i+1:05}BMP',32,30+slot,78);slot+=1
        base=1+len(groups)
    for i in range(4):entry(2,base+i,f'MUSIC{i+1}  WAV',32,50+i,1000+i)
    for i in range(first_count+4):
        a=(3+30+i-2)*512
        image=bytearray(78);image[:2]=b'BM'
        struct.pack_into('<I',image,2,78);struct.pack_into('<I',image,10,54)
        struct.pack_into('<IiiHHI',image,14,40,4,2,1,24,0)
        for row in range(2):
            y=1-row
            for x in range(4):image[54+row*12+x*3:57+row*12+x*3]=bytes((29+i*7+x+y,31+i*5+y,17+i*3+x))
        data[a:a+78]=image
    return data

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--tool-dir',type=Path,required=True);a=p.parse_args()
    storage=['fat32_boot_parser.v','fat32_volume_locator.v','fat32_card_catalog.v','fat32_bmp_catalog.v','fat32_dir_scan.v','fat32_file_reader.v','bmp_stream_decoder.v','fat32_image_loader.v','fat32_frame_loader.v','frame_buffer_manager.v']
    player=['sd_media_player.v','sd_sector_arbiter.v','fat32_wav_player.v','fat32_file_reader.v','wav_pcm_decoder.v','media_prefetch_control.v']
    board=['rtc_ds1302.v','rtc_set_control.v','hdmi_media_board_top.v','board_key.v','media_control_events.v','media_rotary_encoder.v','media_nec_receiver.v','media_infrared_control.v','media_mode_control.v','media_adjust_control.v','board_matrix_keys.v','media_home_control.v','media_help_control.v','home_album_config.v','media_3d_control.v']
    cases=[('tb_topic_directory',['fat32_dir_scan.v','home_album_config.v'],[HERE/'tb_directory.sv']),
           ('tb_topic_loader',storage,[HERE/'tb_loader.sv']),
           ('tb_topic_intro_map',player,[ROOT/'tests/gallery_caption/pause_pipeline_stubs.sv',HERE/'tb_intro_map.sv']),
           ('tb_subtitle_soft',['video_chinese_subtitle.v','subtitle_font_rom.v'],[HERE/'tb_subtitle_soft.sv']),
           ('tb_topic_home_catalog',board,[ROOT/'tests/dmz_media/tb_hdmi_media_board_top.sv',HERE/'tb_home_catalog.sv'])]
    inputs={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in [*(ROOT/'rtl').glob('*.v'),*HERE.glob('*.sv'),Path(__file__),ROOT/'assets/subtitle_v01.json',ROOT/'tests/chinese_subtitle/tb_subtitle_av.sv']}
    logs=[]
    def run(cmd,cwd,*,timeout=240):
        try:
            r=subprocess.run(list(map(str,cmd)),cwd=cwd,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError(f'{Path(cmd[1]).name} exceeded {timeout} seconds') from exc
        output=r.stdout+r.stderr;logs.append(output);print(output,end='',flush=True)
        if r.returncode or 'FATAL' in output:raise RuntimeError('topic/soft-edge regression failed')
    try:
        with tempfile.TemporaryDirectory(prefix='topic_folders_') as tmp:
            t=Path(tmp)
            for v in range(3):(t/f'loader{v}.hex').write_text(''.join(f'{b:02x}\n' for b in fixture(v)),encoding='ascii')
            manifest=json.loads((ROOT/'assets/subtitle_v01.json').read_text(encoding='utf-8'));golden=[]
            for glyph in manifest['glyphs']:
                fill=[[int(c) for c in row] for row in glyph['rows']]
                for y in range(16):
                    for x in range(16):
                        outline=any(fill[yy][xx] for yy in range(max(0,y-1),min(16,y+2)) for xx in range(max(0,x-1),min(16,x+2)))
                        golden.append(2 if fill[y][x] else int(outline))
            golden += [0]*(4096-len(golden));(t/'font_golden.hex').write_text('\n'.join(map(str,golden))+'\n',encoding='ascii')
            for top,rtl,bench in cases:
                print(f'Running {top}',flush=True)
                run([a.tool_dir/'iverilog.exe','-g2012','-s',top,'-o',t/'test.vvp',*[ROOT/'rtl'/n for n in rtl],*bench],t)
                run([a.tool_dir/'vvp.exe',t/'test.vvp'],t)
            # Run the production 10-clock HDMI chain with HOME_UI enabled.
            # The comparison differs only in the edge feature; RGB is also
            # independently checked against glyph/gradient/alpha arithmetic.
            text=(ROOT/'rtl/hdmi_av_output.v').read_text(encoding='utf-8-sig')
            text=text.replace('module hdmi_av_output #','module hdmi_av_output_reference #').replace('.SOFT_EDGES(HOME_UI)', '.SOFT_EDGES(0)')
            (t/'reference_av.v').write_text(text,encoding='utf-8')
            text=(ROOT/'tests/chinese_subtitle/tb_subtitle_av.sv').read_text(encoding='utf-8')
            text=text.replace('.SETTINGS_UI(1),.MODE_CONTROL(1)', '.HOME_UI(1),.SETTINGS_UI(1),.MODE_CONTROL(1)')
            text=text.replace('hdmi_av_output_reference #(.HOME_UI(1),.SETTINGS_UI(1),.MODE_CONTROL(1))', 'hdmi_av_output_reference #(.CHINESE_SUBTITLE(1),.HOME_UI(1),.SETTINGS_UI(1),.MODE_CONTROL(1))')
            text=text.replace('.settings_word(11\'d0),', '.home_word(15\'d0),.settings_word(11\'d0),')
            text=text.replace('integer tx,addr;', 'integer tx,addr,dist,alpha;reg [23:0] ink;\n function automatic [7:0] blend(input integer b,f,a);integer v;begin v=b+(((f-b)*a+8)>>>4);blend=v[7:0];end endfunction')
            text=text.replace("if(golden[addr]==2)expected=24'he7efec;\n     else if(golden[addr]==1)expected=24'h0b1420;", "if(golden[addr]!=0)begin\n      ink=golden[addr]==2?24'he7efec:24'h0b1420;\n      dist=(xx[9]-16<303-xx[9])?xx[9]-16:303-xx[9];alpha=(dist>=32)?16:dist/2;\n      expected={blend(expected[23:16],ink[23:16],alpha),blend(expected[15:8],ink[15:8],alpha),blend(expected[7:0],ink[7:0],alpha)};\n     end")
            text=text.replace('dist,alpha','edge_distance,alpha').replace('dist=','edge_distance=').replace('(dist>=32)?16:dist/2','(edge_distance>=32)?16:edge_distance/2')
            assert 'blend(expected' in text
            (t/'tb_av.sv').write_text(text,encoding='utf-8')
            run([a.tool_dir/'iverilog.exe','-g2012','-s','tb_subtitle_av','-o',t/'av.vvp',*[p for p in (ROOT/'rtl').glob('*.v') if p.name!='board_pll.v'],t/'reference_av.v',t/'tb_av.sv'],t)
            print('Running tb_subtitle_av (full HDMI audio/video; may take several minutes)',flush=True)
            run([a.tool_dir/'vvp.exe',t/'av.vvp'],t,timeout=600)
        assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in inputs.items())
        (HERE/'summary.json').write_text(json.dumps(dict(status='passed',tops=[c[0] for c in cases],inputs_sha256=inputs),indent=2)+'\n',encoding='utf-8')
    finally:(HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')
if __name__=='__main__':main()
