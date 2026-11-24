"""Fine controls, exact Q8 mapping and independent Chinese menu pixels."""
from pathlib import Path
import argparse,json,subprocess,sys,tempfile
from PIL import Image
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'tests/home'))
from menu_oracle import reference_frame
def main():
 p=argparse.ArgumentParser();p.add_argument('--tool-dir',type=Path,required=True);a=p.parse_args();logs=[];cases=[]
 glyphs={g['character']:g['rows'] for g in json.loads((ROOT/'assets/settings_v04.json').read_text(encoding='utf-8'))['glyphs']}
 with tempfile.TemporaryDirectory(prefix='fine_adjust_') as folder:
  tmp=Path(folder);count=0
  with (tmp/'menu_vectors.txt').open('w',encoding='ascii') as f:
   for b,percent,page in [(-64,50,0),(64,150,1),(1,101,0),(-1,99,1),(0,100,0)]:
    values,_=reference_frame((1,page,0,0,0,0,1,0,0),glyphs,fine=(b,percent))
    f.write(f'{b} {percent} {page} 307200\n')
    for y in range(480):
     for x in range(640):f.write(f'{x} {y} {values[y*640+x]:07x}\n')
    count+=307200
   settings=[(b,100,0) for b in range(-64,65)]+[(0,percent,1) for percent in range(50,151)]
   for b,percent,page in settings:
    # Numeric fields and every progress-bar pixel at all legal settings.
    pixels=[]
    for row in [0,1]:
     top=160+row*32
     text=(f'{b:+4d}' if b else '   0') if row==0 else f'{percent:3d}%'
     for y in range(top+4,top+20):
      for x in range(416,480):
       ch=text[(x-416)//16];ink=glyphs[ch][y-top-4][(x-416)%16]=='1'
       color=0xe7efec if ink else (0x203f47 if page==row else 0x162737)
       pixels.append((x,y,0x1000000|color))
     fill=b+64 if row==0 else (percent-50)*41//32
     for y in range(top+26,top+30):
      for x in range(344,472):pixels.append((x,y,0x1000000|(0x70d6bc if x-344<fill else 0x405865)))
    f.write(f'{b} {percent} {page} {len(pixels)}\n')
    for x,y,c in pixels:f.write(f'{x} {y} {c:07x}\n')
    count+=len(pixels)
  board_sources=['rtc_ds1302.v','rtc_set_control.v','hdmi_media_board_top.v','board_key.v','media_control_events.v','media_rotary_encoder.v','media_nec_receiver.v','media_infrared_control.v','media_mode_control.v','media_adjust_control.v','board_matrix_keys.v','media_home_control.v','media_help_control.v','home_album_config.v','media_3d_control.v']
  for top,names,benches in [
   ('tb_fine_control',['media_adjust_control.v'],[HERE/'tb_control.sv']),
   ('tb_fine_lut',['video_brightness_lut.v'],[HERE/'tb_lut.sv']),
   ('tb_fine_board',board_sources,[HERE/'tb_board.sv',ROOT/'tests/dmz_media/tb_hdmi_media_board_top.sv',ROOT/'tests/dmz_media/dmz_keyboard_model.sv']),
   ('tb_fine_menu',['video_chinese_settings.v','settings_font_rom.v'],[HERE/'tb_menu.sv'])]:
   output=''
   for cmd in [[a.tool_dir/'iverilog.exe','-g2012','-s',top,'-o',tmp/'test.vvp',*[ROOT/'rtl'/n for n in names],*benches],[a.tool_dir/'vvp.exe',tmp/'test.vvp']]:
    r=subprocess.run(list(map(str,cmd)),cwd=tmp,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=240)
    output+=r.stdout+r.stderr
    assert r.returncode==0 and 'FATAL' not in output,output
   assert 'PASS' in output;print(output,end='',flush=True);logs.append(output);cases.append(top)
  with Image.open(tmp/'fine_menu.ppm') as im:im.save(HERE/'fine_menu_preview.png')
 (HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')
 (HERE/'summary.json').write_text(json.dumps({'status':'passed','cases':cases,'menu_pixels':count,'brightness_levels':129,'contrast_levels':101,'all_512_q8_gains_tested':True,'hardware_tested':False},indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':main()
