"""Independent H01 pixels and behavioral contracts; real controllers/ROM."""
from pathlib import Path
import argparse,hashlib,json,random,subprocess,tempfile
from PIL import Image
from menu_oracle import reference_frame
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
EASE=[0,2,9,19,32,48,66,86,107,128,149,170,190,208,224,237,247,254,256]

def reference(x,y,word,bits,branding=False):
 visible=bool(word&0x4000);state=(word>>11)&7;index=(word>>1)&7
 moving=bool(word&0x400);reverse=moving and bool(word&0x200);phase=(word>>4)&31
 f=EASE[min(phase,18)];d=f if moving else 0
 world=(x+64+(256-d if reverse else d))%1024
 base=(index-2)%5 if reverse else (index-1)%5
 tile=(base+world//256)%5;lx=world%256
 card=16<=lx<240 and 144<=y<352 and (24<=lx<232 or 152<=y<344)
 rgb=0x122431 if y%64==0 else 0x0b1420
 if card:
  rgb=[0x193c3c,0x213a4c,0x343a4f,0x453d37,0x263f40][tile]
  if lx<19 or lx>=237 or y<147 or y>=349:rgb=0x3b5363
 if 204<=x<436 and 140<=y<356 and (x<208 or x>=432 or y<144 or y>=352):rgb=0x70d6bc
 if 328<=y<332 and 280<=x<360 and (x-280)%16<8:rgb=0xb6e7d7 if (x-280)//16==index else 0x405865
 text=0xe7efec if 208<=x<432 else 0x93a9b4
 page=tile;u=lx-64;v=y-176;window=64<=lx<192 and 176<=y<304
 title=(320<=x<544 and 32<=y<96) if branding else (192<=x<448 and 48<=y<112)
 if title:page,u,v,window,text=5,(x-(320 if branding else 192))//2,(y-(32 if branding else 48))//2,True,0xb6e7d7
 elif 256<=x<384 and 400<=y<432:page,u,v,window,text=5,x-256,y-336,True,0x93a9b4
 elif 256<=x<384 and 364<=y<380 and (state==1 or word&1):
  page,u,v,window,text=5,x-256,y-364+(48 if state==1 else 32),True,0xe5a89b if word&1 else 0xb6e7d7
 if window and bits[page*16384+v*128+u]:rgb=text
 if branding:
  if 544<=x<632 and 68<=y<132:rgb=0xf5f7fa
  if 8<=x<312 and 16<=y<120:
   u,v=(x-8)//2,(y-16)//2
   if bits[98304+v*152+u]:rgb=0x3b91d8
  if 552<=x<624 and 76<=y<124:
   u,v=(x-552)//2,(y-76)//2
   if bits[5*16384+(96+v)*128+92+u]:rgb=0xe51b2b if 2*u>25+v else 0x1d2d50
 reveal=f*640//256
 covered=visible and (x>=reveal if state==2 else (x<reveal if state==4 else True))
 return rgb,int(covered)

def main():
 p=argparse.ArgumentParser();p.add_argument('--tool-dir',type=Path,required=True);a=p.parse_args()
 logs=[];records=[]
 with tempfile.TemporaryDirectory(prefix='h01_') as folder:
  tmp=Path(folder);asset=json.loads((ROOT/'assets/home_assets.json').read_text(encoding='utf-8'))
  assert asset['config_sha256']==hashlib.sha256((ROOT/'assets/home_config.json').read_bytes()).hexdigest()
  bits=asset['bits'];assert len(bits)==asset['native_banks']*8192
  glyphs={g['character']:g['rows'] for g in json.loads((ROOT/'assets/settings_v04.json').read_text(encoding='utf-8'))['glyphs']}
  menus=[((1,0,2,2,0,1,1,0,0),(0,2,4,2)),((1,2,0,4,1,1,1,1,1),(1,3,4,2)),((1,3,4,0,1,0,0,0,1),(0,0,0,0))]
  from_menu=lambda s:((s[0]<<10)|(s[1]<<8)|(s[2]<<5)|(s[3]<<2)|(s[4]<<1)|s[5],(s[6]<<2)|(s[7]<<1)|s[8])
  (tmp/'ui_states.hex').write_text(''.join(f'{(from_menu(s)[1]<<11)|from_menu(s)[0]:x}\n' for s,m in menus),encoding='ascii')
  (tmp/'ui_musics.hex').write_text(''.join(f'{(m[0]<<7)|(m[1]<<5)|(m[2]<<2)|m[3]:x}\n' for s,m in menus),encoding='ascii')
  for i,(state,music) in enumerate(menus):
   values,_=reference_frame(state,glyphs,music=music)
   (tmp/f'menu_golden_{i}.hex').write_text(''.join(f'{v:07x}\n' for v in values),encoding='ascii')
  words=[0x4000]+[0x4000|(i<<1) for i in range(1,5)]
  words += [0x4000|0x400|(i<<1)|(p<<4)|(0x200 if b else 0) for i,b,p in [(0,0,9),(0,1,9),(4,0,17),(1,1,1)]]
  words += [0x4000|(s<<11)|(p<<4) for s,p in [(1,0),(2,0),(2,9),(2,18),(4,9),(4,18)]]+[0x4001,0]
  rng=random.Random(45830);count=0
  with (tmp/'home_pixels.txt').open('w',encoding='ascii') as f:
   for word in words:
    points=((x,y) for y in range(480) for x in range(640)) if word==0x4000 else [(rng.randrange(640),rng.randrange(480)) for _ in range(8000)]
    for x,y in points:
     rgb,mask=reference(x,y,word,bits);f.write(f'{x} {y} {word:x} {rgb:06x} {mask}\n');count+=1
  for top,names,bench in [
   ('tb_home_album',['media_prefetch_control.v','frame_buffer_manager.v'],'tb_album.sv'),
   ('tb_home_board',['rtc_ds1302.v','rtc_set_control.v','hdmi_media_board_top.v','board_key.v','media_control_events.v','media_rotary_encoder.v','media_nec_receiver.v','media_infrared_control.v','media_mode_control.v','media_adjust_control.v','board_matrix_keys.v','media_home_control.v','home_album_config.v'],'tb_board.sv'),
   ('tb_home_control',['media_home_control.v','home_album_config.v'],'tb_control.sv'),
   ('tb_home_restart',['media_mode_control.v'],'tb_restart.sv'),
   ('tb_home_menu',['video_chinese_settings.v','settings_font_rom.v'],'tb_menu.sv'),
   ('tb_home_pixels',['video_home.v','home_assets_rom.v'],'tb_pixels.sv')]:
   output=''
   for cmd in [[a.tool_dir/'iverilog.exe','-g2012','-s',top,'-o',tmp/'test.vvp',*[ROOT/'rtl'/n for n in names],HERE/bench,*([ROOT/'tests/dmz_media/tb_hdmi_media_board_top.sv',ROOT/'tests/dmz_media/dmz_keyboard_model.sv'] if top=='tb_home_board' else [])],[a.tool_dir/'vvp.exe',tmp/'test.vvp']]:
    r=subprocess.run(list(map(str,cmd)),cwd=tmp,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=900)
    output+=r.stdout+r.stderr
    if r.returncode or 'FATAL' in output:raise AssertionError(output)
   assert 'PASS ' in output;print(output,end='',flush=True);logs.append(output);records.append(top)
  with Image.open(tmp/'home.ppm') as im:im.save(HERE/'home_preview.png')
  with Image.open(tmp/'compact_menu.ppm') as im:im.save(HERE/'compact_menu_preview.png')
 (HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')
 (HERE/'summary.json').write_text(json.dumps({'status':'passed','cases':records,'pixels':count,'hardware_tested':False},indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':main()
