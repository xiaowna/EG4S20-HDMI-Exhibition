"""V02 independent menu pixels, font bits, frame snapshots and HDMI equivalence."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
STATES = [
    (1,0,2,2,0,0,1,0,0), (1,0,0,4,1,0,1,0,0),
    (1,1,1,3,0,1,1,0,1), (1,2,2,2,1,0,1,0,0),
    (1,3,3,1,0,1,1,0,1), (1,0,4,0,1,1,1,1,1),
    (1,3,2,2,0,1,0,0,1), (0,0,2,2,0,0,1,0,0),
    (1,0,2,2,0,0,1,1,0),
]


def words(state):
    active,page,bright,gain,fade,wave,product,auto_page,auto = state
    return (active<<10)|(page<<8)|(bright<<5)|(gain<<2)|(fade<<1)|wave, (product<<2)|(auto_page<<1)|auto


def reference_frame(state, glyphs, spectrum=False, music=None):
    active,page,bright,gain,fade,wave,product,auto_page,auto = state
    selected = 4 if auto_page else page
    if music and music[0]: selected=5
    bottom,footer=(464,424) if music is not None else (424,384)
    texts = [(144,104,2,'播放设置',0x70d6bc),
             (440,108,1,'产品' if product else '演示',0xb6e7d7),
             (192,footer,1,'←→调节  K2下项  K4返回',0x93a9b4)]
    labels=['亮度','对比度','切图渐变','彩色频谱' if spectrum else '音频波形','自动轮播']
    if music is not None: labels.append('背景音乐')
    for row,label in enumerate(labels):
        yy = 160+40*row
        color = 0x8298a4 if (row==4 and not product) or (row==5 and (not product or music[2]==0)) else 0xe7efec
        texts.append((152,yy,2,label,color))
        if row==0:
            value = [' -64',' -32','   0',' +32',' +64'][bright]
            texts.append((416,yy+4,1,value,color))
        elif row==1:
            texts.append((416,yy+4,1,[' 50%',' 75%','100%','125%','150%'][gain],color))
        elif row==5:
            _,choice,count,playing=music
            if choice!=playing:color=0xb6e7d7
            texts.append((416,yy+4,1,f'{choice+1 if count else 0}/{count} ',color))
        else:
            texts.append((416,yy,2,'开启' if [fade,wave,auto][row-2] else '关闭',color))
    text_pixels = {}
    for xx,yy,scale,text,color in texts:
        for i,ch in enumerate(text):
            bitmap = glyphs[ch]
            for gy,line in enumerate(bitmap):
                for gx,bit in enumerate(line):
                    if bit=='1':
                        for dy in range(scale):
                            for dx in range(scale):
                                text_pixels[(xx+i*16*scale+gx*scale+dx,yy+gy*scale+dy)] = color
    data = []
    image = Image.new('RGB',(640,480))
    pixels = []
    for y in range(480):
        for x in range(640):
            rgb = ((x&255)<<16)|((y&255)<<8)|((x^y)&255)
            panel = 112<=x<528 and 80<=y<bottom and (120<=x<520 or 88<=y<bottom-8)
            shadow = 120<=x<536 and 88<=y<bottom+8 and (128<=x<528 or 96<=y<bottom)
            visible = active and (panel or shadow)
            color = rgb
            if visible:
                color = (rgb&0xfefefe)>>1
                if panel:
                    inner = 114<=x<526 and 82<=y<bottom-2 and (122<=x<518 or 90<=y<bottom-10)
                    color = 0x162737
                    if not inner: color=0x3b5363
                    elif (148<=y<150 or footer-20<=y<footer-18) and 128<=x<512: color=0x3b5363
                    elif 416<=x<496 and 100<=y<132: color=0x203641
                    elif 128<=x<512 and 156+40*selected<=y<196+40*selected:
                        color=0x70d6bc if x<132 else 0x203f47
                    for row in range(5):
                        dy=y-(160+40*row)
                        if row<2 and 344<=x<464 and 26<=dy<30:
                            segment,offset=divmod(x-344,24)
                            color=(0x162737 if offset>=20 else
                                   (0x70d6bc if segment<=[bright,gain][row] else 0x405865))
                        if row>=2 and 344<=x<396 and 8<=dy<24:
                            enabled=[fade,wave,auto][row-2]
                            disabled=row==4 and not product
                            color=0x347e6c if enabled and not disabled else 0x405865
                            if 10<=dy<22 and ((380<=x<392) if enabled else (348<=x<360)):
                                color=0x8298a4 if disabled else 0xedf6ef
                    color=text_pixels.get((x,y),color)
            data.append((int(bool(visible))<<24)|color)
            pixels.append(((color>>16)&255,(color>>8)&255,color&255))
    image.putdata(pixels)
    return data,image


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir',type=Path,required=True)
    args=parser.parse_args()
    manifest=json.loads((ROOT/'assets/settings_v03.json').read_text(encoding='utf-8'))
    glyphs={g['character']:g['rows'] for g in manifest['glyphs']}
    golden=[int(bit) for g in manifest['glyphs'] for row in g['rows'] for bit in row]
    golden += [0]*(16384-len(golden))
    logs=[]
    try:
        with tempfile.TemporaryDirectory(prefix='chinese_settings_') as temporary:
            temp=Path(temporary)
            (temp/'ui_font_golden.hex').write_text('\n'.join(map(str,golden))+'\n',encoding='ascii')
            (temp/'ui_states.hex').write_text('\n'.join(f'{(words(s)[1]<<11)|words(s)[0]:04x}' for s in STATES)+'\n',encoding='ascii')
            for i,state in enumerate(STATES):
                values,preview=reference_frame(state,glyphs)
                (temp/f'menu_golden_{i}.hex').write_text(''.join(f'{value:07x}\n' for value in values),encoding='ascii')
            reference=ROOT/'reports/v02_settings_20261019/before/worktree/rtl/hdmi_av_output.v'
            old=temp/'reference.v'
            old.write_text(re.sub(r'\bhdmi_av_output\b','hdmi_av_output_v01',reference.read_text(encoding='utf-8-sig')),encoding='utf-8')
            sources=[p for p in (ROOT/'rtl').glob('*.v') if p.name!='board_pll.v']
            cases=[('tb_settings_rom',[],HERE/'tb_settings.sv',{}),
                   ('tb_chinese_settings',[],HERE/'tb_settings.sv',{}),
                   ('tb_settings_av',[old],HERE/'tb_settings_av.sv',{'DIM':0}),
                   ('tb_settings_av',[old],HERE/'tb_settings_av.sv',{'DIM':1})]
            for top,extra,bench,params in cases:
                for cmd in [[args.tool_dir/'iverilog.exe','-g2012','-s',top,
                             *[f'-P{top}.{k}={v}' for k,v in params.items()],'-o',temp/'check.vvp',*sources,*extra,bench],
                            [args.tool_dir/'vvp.exe',temp/'check.vvp']]:
                    result=subprocess.run(list(map(str,cmd)),cwd=temp,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=300)
                    output=result.stdout+result.stderr
                    print(output,end='',flush=True);logs.append(top+'\n'+output)
                    if result.returncode or 'FATAL' in output: raise RuntimeError(top+' failed')
            for name in ['menu_default','menu_auto','menu_demo']:
                with Image.open(temp/(name+'.ppm')) as picture: picture.save(HERE/(name+'.png'))
        print('PASS V02 Chinese settings software acceptance')
    finally:
        (HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')


if __name__=='__main__': main()
