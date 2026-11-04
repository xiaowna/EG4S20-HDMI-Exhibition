"""Independent exhibit control, six-page ROM and removed-sidebar checks."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import random
import shutil
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'tests/home'))


def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--tool-dir',type=Path,required=True);a=p.parse_args()
 asset=json.loads((ROOT/'assets/home_assets.json').read_text(encoding='utf-8'))
 assert asset['pages']==6 and asset['native_banks']==13 and len(asset['bits'])==106496
 bits=asset['bits']
 spec=importlib.util.spec_from_file_location('legacy_home',ROOT/'tests/home/verify.py')
 legacy=importlib.util.module_from_spec(spec);spec.loader.exec_module(legacy)
 files=[ROOT/'rtl'/n for n in ['media_home_control.v','home_album_config.v','video_home.v','home_assets_rom.v','hdmi_media_board_top.v','media_3d_control.v']]
 files+=list((ROOT/'assets/branding').glob('*.jpg'))+list(HERE.glob('*.sv'))+[ROOT/'assets/home_assets.json',ROOT/'assets/home_config.json',ROOT/'tools/generate_home_assets.py',ROOT/'tests/home/verify.py',Path(__file__).resolve()]
 # The board test also instantiates the RTC, IR and matrix-key controllers.
 files+=list((ROOT/'rtl').glob('*.v'))+[ROOT/'tests/dmz_media/tb_hdmi_media_board_top.sv',ROOT/'tests/dmz_media/dmz_keyboard_model.sv']
 hashes={f.relative_to(ROOT).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
 logs=[];checks=[];rng=random.Random(45830)

 def reference(x,y,word,scene,rate,side):
  if word&0x2000:
   rgb=0x779ca8 if (x&511)^(((y&15)<<5)|((y>>4)&31))==0x12d and (x&7)==(y>>7) else 0x0d1825
   if 392<=y<394 and 224<=x<416:rgb=0x5ba99f
   if 192<=x<448 and 112<=y<368:
    u,v=(x-192)//2,(y-112)//2
    if bits[7*16384+v*128+u]:rgb=0xdcebe7
   return rgb,1
  return legacy.reference(x,y,word,bits,branding=True)

 def run(cmd,cwd):
  r=subprocess.run(list(map(str,cmd)),cwd=cwd,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=240)
  out=r.stdout+r.stderr;logs.append(out);print(out,end='',flush=True)
  if r.returncode or 'FATAL' in out:raise RuntimeError('solar exhibit integration check failed')
 try:
  with tempfile.TemporaryDirectory(prefix='solar_integration_') as name:
   tmp=Path(name)
   # Regeneration must preserve the working TOPIC1..4 descriptor interface.
   generated=tmp/'generated';(generated/'assets').mkdir(parents=True);(generated/'rtl').mkdir()
   shutil.copy2(ROOT/'assets/home_config.json',generated/'assets/home_config.json')
   shutil.copytree(ROOT/'assets/branding',generated/'assets/branding')
   generator_spec=importlib.util.spec_from_file_location('home_generator',ROOT/'tools/generate_home_assets.py')
   generator=importlib.util.module_from_spec(generator_spec);generator_spec.loader.exec_module(generator)
   generator.ROOT=generated;generator.main()
   assert json.loads((generated/'assets/home_assets.json').read_text(encoding='utf-8'))==asset
   for name in ['home_assets_rom.v','home_album_config.v']:
    assert (generated/'rtl'/name).read_text(encoding='utf-8').split()==(ROOT/'rtl'/name).read_text(encoding='utf-8').split(),name
   checks.append('asset_regeneration_preserves_topic_folder_interface')
   (tmp/'home_bits.hex').write_text(''.join(f'{b}\n' for b in bits),encoding='ascii')
   # Full rasters prove coverage boundaries; sparse states cover all speeds and views.
   states=[(0x4008,0,3,0),(0x4000,0,3,0),(0,1,3,0),(0,0,3,0)]
   states += [(0,1,r,r%2) for r in range(8)]
   pixels=0
   for i,(word,scene,rate,side) in enumerate(states):
    with (tmp/f'pixels_{i}.txt').open('w',encoding='ascii') as f:
     f.write(f'{word:x} {scene} {rate} {side}\n')
     points=((x,y) for y in range(480) for x in range(640)) if i<4 else [(rng.randrange(640),rng.randrange(480)) for _ in range(12000)]
     for x,y in points:
      rgb,mask=reference(x,y,word,scene,rate,side);f.write(f'{x} {y} {rgb:06x} {mask}\n');pixels+=1
   for top,names,bench in [
    ('tb_solar_home_control',['media_home_control.v','home_album_config.v'],'tb_control.sv'),
    ('tb_solar_home_rom',['home_assets_rom.v'],'tb_rom.sv'),
    ('tb_solar_home_pixels',['video_home.v','home_assets_rom.v'],'tb_pixels.sv'),
    ('tb_solar_board_controls',['rtc_ds1302.v','rtc_set_control.v','hdmi_media_board_top.v','board_key.v','media_control_events.v','media_rotary_encoder.v','media_nec_receiver.v','media_infrared_control.v','media_mode_control.v','media_adjust_control.v','board_matrix_keys.v','media_home_control.v','home_album_config.v','media_3d_control.v'],'tb_board.sv')]:
    extra=[ROOT/'tests/dmz_media/tb_hdmi_media_board_top.sv',ROOT/'tests/dmz_media/dmz_keyboard_model.sv'] if top=='tb_solar_board_controls' else []
    run([a.tool_dir/'iverilog.exe','-g2012','-s',top,'-o',tmp/'check.vvp',*[ROOT/'rtl'/n for n in names],HERE/bench,*extra],tmp)
    run([a.tool_dir/'vvp.exe',tmp/'check.vvp'],tmp);checks.append(top)
  assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in hashes.items()),'inputs changed during audit; rerun after integration'
  (HERE/'summary.json').write_text(json.dumps({'status':'passed','checks':checks,'rom_bits':106496,'pixels':pixels,'inputs_sha256':hashes,'hardware_tested':False},indent=2)+'\n',encoding='utf-8')
 finally:(HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')

if __name__=='__main__':main()
