"""Palette-only source proof and independent RTL pixel acceptance.

Run the changed renderers in isolation so concurrent storage/geometry work does
not become part of this visual acceptance. PNGs are software raster previews.
"""
from pathlib import Path
import argparse, hashlib, importlib.util, json, random, re, subprocess, sys, tempfile
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
REPORT=ROOT/'reports/visual_palette_20261026'
sys.path.insert(0,str(ROOT/'tests/home'))


def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    item=importlib.util.module_from_spec(spec);spec.loader.exec_module(item)
    return item


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir',type=Path,required=True)
    args=parser.parse_args();logs=[];cases=[];vectors={}
    palette=json.loads((REPORT/'palette_change.json').read_text(encoding='utf-8'))
    sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
    normalized=lambda s:re.sub(r"24'h[0-9a-fA-F]{6}","24'h[COLOR]",s)
    for name in palette['production_files']:
        before=(REPORT/'before'/name).read_text(encoding='utf-8-sig')
        after=(ROOT/name).read_text(encoding='utf-8-sig')
        assert normalized(before)==normalized(after),name+' changed beyond constants'
        assert sha(ROOT/name)==palette['production_files'][name]['after_sha256']
    inputs={n:sha(ROOT/n) for n in palette['production_files']}
    home=module('palette_home',ROOT/'tests/home/verify.py')
    menu=module('palette_menu',ROOT/'tests/home/menu_oracle.py')
    progress=module('palette_progress',ROOT/'tests/prepare_bar/verify.py')
    toast=module('palette_toast',ROOT/'tests/music_toast/verify.py')
    home_asset=json.loads((ROOT/'assets/home_assets.json').read_text(encoding='utf-8'))
    settings=json.loads((ROOT/'assets/settings_v04.json').read_text(encoding='utf-8'))
    glyphs={g['character']:g['rows'] for g in settings['glyphs']}
    with tempfile.TemporaryDirectory(prefix='palette_pixels_') as temporary:
        tmp=Path(temporary)
        settings_rom,rom_proof=toast.settings_rom(ROOT/'rtl/settings_font_rom.v',tmp)
        home_rom,home_proof=progress.simulation_rom_source(ROOT/'rtl/home_assets_rom.v',tmp)

        def run(top,sources,bench):
            target=tmp/(top+'.vvp');output=''
            for cmd in [[args.tool_dir/'iverilog.exe','-g2012','-s',top,'-o',target,*sources,bench],
                        [args.tool_dir/'vvp.exe',target]]:
                result=subprocess.run(list(map(str,cmd)),cwd=tmp,capture_output=True,text=True,
                                      encoding='utf-8',errors='replace',timeout=300)
                output+=result.stdout+result.stderr
                if result.returncode or 'FATAL' in output:raise AssertionError(output)
            assert 'PASS ' in output,output
            print(output,end='',flush=True);logs.append(output);cases.append(top)

        # Full branded home plus all five choices and both carousel directions.
        words=[0x4000,0x4008,0x4002,0x4004,0x4006,
               0x4000|0x400|(9<<4),0x4000|0x600|(9<<4),0x5000|(9<<4)]
        rng=random.Random(45830);count=0
        with (tmp/'home_pixels.txt').open('w',encoding='ascii') as f:
            for word in words:
                points=((x,y) for y in range(480) for x in range(640)) if word==0x4000 else [(rng.randrange(640),rng.randrange(480)) for _ in range(12000)]
                for x,y in points:
                    color,mask=home.reference(x,y,word,home_asset['bits'],branding=True)
                    f.write(f'{x} {y} {word:x} {color:06x} {mask}\n');count+=1
        bench=tmp/'home.sv'
        bench.write_text((ROOT/'tests/home/tb_pixels.sv').read_text(encoding='utf-8').replace(
            'video_home dut(.*);','video_home #(.EXHIBIT(1)) dut(.*);'),encoding='utf-8')
        run('tb_home_pixels',[ROOT/'rtl/video_home.v',home_rom],bench)
        vectors['home']=count
        with Image.open(tmp/'home.ppm') as image:image.save(HERE/'home.png')

        menus=[((1,0,2,2,0,1,1,0,0),(0,2,4,2)),
               ((1,2,0,4,1,1,1,1,1),(1,3,4,2)),
               ((1,3,4,0,1,0,0,0,1),(0,0,0,0))]
        word=lambda s:(((s[6]<<2)|(s[7]<<1)|s[8])<<11)|((s[0]<<10)|(s[1]<<8)|(s[2]<<5)|(s[3]<<2)|(s[4]<<1)|s[5])
        (tmp/'ui_states.hex').write_text(''.join(f'{word(s):x}\n' for s,m in menus),encoding='ascii')
        (tmp/'ui_musics.hex').write_text(''.join(f'{(m[0]<<7)|(m[1]<<5)|(m[2]<<2)|m[3]:x}\n' for s,m in menus),encoding='ascii')
        for i,(state,music) in enumerate(menus):
            values,_=menu.reference_frame(state,glyphs,music=music)
            # A neutral exhibition background makes the captured palette easy
            # to judge; the ordinary oracle separately uses a gradient.
            for y in range(480):
                for x in range(640):
                    j=y*640+x
                    panel=112<=x<528 and 80<=y<432 and (120<=x<520 or 88<=y<424)
                    if not (values[j]>>24):values[j]=0x0b1420
                    elif not panel:values[j]=0x1000000|((0x0b1420&0xfefefe)>>1)
            (tmp/f'menu_golden_{i}.hex').write_text(''.join(f'{v:07x}\n' for v in values),encoding='ascii')
        bench=tmp/'menu.sv'
        bench.write_text((ROOT/'tests/home/tb_menu.sv').read_text(encoding='utf-8').replace(
            'rgb={xx[7:0],yy[7:0],xx[7:0]^yy[7:0]};',"rgb=24'h0b1420;"),encoding='utf-8')
        run('tb_home_menu',[ROOT/'rtl/video_chinese_settings.v',settings_rom],bench)
        vectors['menu']=3*640*480
        with Image.open(tmp/'compact_menu.ppm') as image:image.save(HERE/'settings.png')

        count=0
        with (tmp/'pixels.txt').open('w',encoding='ascii') as f:
            for stage in range(1,8):
                for phase in [4,64,128,252]:
                    for units in ([0,1,37,74,75,127] if stage==3 else [0]):
                        for y in range(438,474):
                            for x in range(158,482):
                                f.write(f'{x} {y} {stage*128+units:x} {phase} {progress.pixel(x,y,stage,units,phase):07x}\n');count+=1
        run('tb_prepare_pixels',[ROOT/'rtl/video_prepare_overlay.v'],ROOT/'tests/prepare_bar/tb_pixels.sv')
        vectors['progress']=count
        image=Image.new('RGB',(640,480),(11,20,32));pixels=image.load()
        for y in range(480):
            for x in range(640):
                c=progress.pixel(x,y,3,37,4)
                if c>>24:pixels[x,y]=((c>>16)&255,(c>>8)&255,c&255)
        image.save(HERE/'progress.png')

        subtitle=json.loads((ROOT/'assets/subtitle_v01.json').read_text(encoding='utf-8'))
        golden=[]
        for glyph in subtitle['glyphs']:
            fill=[[int(c) for c in row] for row in glyph['rows']]
            for y in range(16):
                for x in range(16):
                    outline=any(fill[yy][xx] for yy in range(max(0,y-1),min(16,y+2)) for xx in range(max(0,x-1),min(16,x+2)))
                    golden.append(2 if fill[y][x] else int(outline))
        golden += [0]*(4096-len(golden))
        (tmp/'font_golden.hex').write_text('\n'.join(map(str,golden))+'\n',encoding='ascii')
        run('tb_subtitle_soft',[ROOT/'rtl/video_chinese_subtitle.v',ROOT/'rtl/subtitle_font_rom.v'],ROOT/'tests/topic_folders/tb_subtitle_soft.sv')
        vectors['subtitle']=9*32*640+640*3

        # RTC editor uses the same foreground/focus/error colors as the menu.
        bits=[c for g in settings['glyphs'] for row in g['rows'] for c in row]
        bits+=['0']*(32768-len(bits))
        (tmp/'clock_font.hex').write_text('\n'.join(bits)+'\n',encoding='ascii')
        ids={g['character']:i for i,g in enumerate(settings['glyphs'])}
        labels='时间设置2026-10-2112:34:56保存返回写入成功失败'
        (tmp/'clock_labels.hex').write_text(''.join(f'{ids[c]:x}\n' for c in labels)+'0\n'*(48-len(labels)),encoding='ascii')
        run('tb_rtc_set_menu',[ROOT/'rtl/video_chinese_settings.v',settings_rom],ROOT/'tests/rtc_setting/tb_menu.sv')
        with Image.open(tmp/'clock_menu.ppm') as image:image.save(HERE/'clock_settings.png')
    assert all(sha(ROOT/n)==digest for n,digest in inputs.items()),'palette sources changed during tests'
    result=dict(status='passed',cases=cases,pixel_vectors=vectors,production_color_only=True,
                source_sha256=inputs,font_initialization_proof=rom_proof,home_initialization_proof=home_proof,
                logos_and_firework_color_constants_preserved=True,hardware_tested=False,
                limitations='Software RTL raster acceptance; resource packing and final board appearance require TD/hardware verification.')
    (HERE/'summary.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')
    print('PASS coherent palette: isolated home/menu/progress/subtitle/RTC pixel acceptance',flush=True)


if __name__=='__main__':main()
