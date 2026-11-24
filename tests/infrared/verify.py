"""NEC vectors, learned/fixed keys and context-bound four-direction 3D control."""
from pathlib import Path
import argparse, hashlib, json, subprocess, tempfile
from runpy import run_path

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent

class Vectors:
 def __init__(self):
  self.rows=[];self.count=0;self.last=(0,0,0)
 def segment(self,level,ticks,check=False,enable=1):
  self.rows.append((enable,level,ticks,self.count if check else -1,*self.last))
 def quiet(self,ticks=600):self.segment(1,ticks,True)
 def frame(self,address,command,valid=True,leader=900,gap=450,mark=56,zero=56,one=169,
           inv_address=None,inv_command=None,bits=32,stop=56,noise=False):
  self.quiet();self.segment(0,leader);self.segment(1,gap)
  value=address|((address^255 if inv_address is None else inv_address)<<8)|command<<16|((command^255 if inv_command is None else inv_command)<<24)
  for i in range(bits):
   if noise and i==7:
    self.segment(0,20);self.segment(1,1);self.segment(0,mark-21)
   else:self.segment(0,mark)
   self.segment(1,one if (value>>i)&1 else zero)
  if bits<32:
   self.segment(1,2000,True);return
  self.segment(0,stop,True)
  if valid:self.count+=1;self.last=(address,command,0)
  self.segment(1,100,True)
 def repeat(self,valid=True,gap=4000):
  self.quiet(gap);self.segment(0,900);self.segment(1,225);self.segment(0,56,True)
  if valid:self.count+=1;self.last=(*self.last[:2],1)
  self.segment(1,100,True)
 def write(self,path):path.write_text(''.join(' '.join(map(str,r))+'\n' for r in self.rows),encoding='ascii')

def vectors(full):
 v=Vectors();v.repeat(False)
 v.frame(0x96,0x69);v.repeat();v.repeat(gap=9600)
 v.quiet(18500);v.repeat(False)
 v.frame(0,0,False,inv_address=0);v.frame(0x42,0xa1,False,inv_command=0xa1)
 if not full:return v
 v.frame(0x34,0x91,False,inv_address=0x12) # Extended NEC is outside this standard-address stage.
 v.frame(0x42,0x81,False,bits=17);v.repeat(False)
 for kwargs in [{'leader':749},{'leader':1051},{'gap':300},{'mark':34},{'mark':81},{'zero':100},{'stop':34},{'stop':81},{'stop':1400}]:
  v.frame(0x27,0xb5,False,**kwargs);v.repeat(False)
 for kwargs in [{'leader':750,'gap':350,'mark':35,'zero':35,'one':120},
                {'leader':1050,'gap':550,'mark':80,'zero':85,'one':210},{'noise':True}]:
  v.frame(0xa5,0x5a,**kwargs)
 # A 10 us spike cannot become a new leader or invalidate the last frame.
 v.segment(0,1);v.segment(1,100,True);v.repeat()
 # Disable partway through a real frame, then recover from an independent full frame.
 v.quiet();v.segment(0,900);v.segment(1,450);v.segment(0,56);v.segment(1,56)
 v.segment(0,200,True,0);v.segment(1,100,True,0);v.segment(0,1500,True)
 v.quiet(2000);v.repeat(False);v.frame(0xff,0);v.frame(0,0xff);v.frame(0x13,0x82)
 return v

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--tool-dir',type=Path,required=True)
 args=p.parse_args();logs=[];records=[]
 names=['rtc_ds1302.v','rtc_set_control.v','media_nec_receiver.v','media_infrared_control.v','hdmi_media_board_top.v','board_key.v',
        'board_matrix_keys.v','media_rotary_encoder.v','media_control_events.v','media_mode_control.v','media_adjust_control.v','media_home_control.v','media_help_control.v','home_album_config.v','media_3d_control.v']
 files=[ROOT/'rtl'/n for n in names]+list(HERE.glob('*.sv'))+[HERE/'verify.py',
  ROOT/'tests/dmz_media/tb_hdmi_media_board_top.sv',ROOT/'tests/dmz_media/dmz_keyboard_model.sv']
 fixture_script=ROOT/'tests/topic_folders/verify.py'
 board_model=ROOT/'tests/dmz_media/tb_hdmi_media_board_top.sv'
 files += list((ROOT/'rtl').glob('*.v'))+[fixture_script,
  ROOT/'tests/clock_buffer_model.v',ROOT/'tests/em638325_model.sv']
 hashes={f.relative_to(ROOT).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
 def run(top,sources,tmp,params=None):
  exe=tmp/(top+'.vvp')
  commands=[[args.tool_dir/'iverilog.exe','-g2012','-s',top,*[f'-P{top}.{k}={v}' for k,v in (params or {}).items()],'-o',exe,*sources],
            [args.tool_dir/'vvp.exe',exe]]
  for i,cmd in enumerate(commands):
   result=subprocess.run(list(map(str,cmd)),cwd=tmp,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=300)
   output=result.stdout+result.stderr;logs.append(output);print(output,end='',flush=True)
   assert result.returncode==0 and 'FATAL' not in output and (i==0 or 'PASS ' in output),output
  records.append({'top':top,'parameters':params or {},'passed':True})
 try:
  with tempfile.TemporaryDirectory(prefix='nec_acceptance_') as tmp:
   tmp=Path(tmp)
   for sample in [1,7,500]:
    v=vectors(sample!=500);v.write(tmp/'stimulus.txt')
    run('tb_ir_receiver',[ROOT/'rtl/media_nec_receiver.v',HERE/'tb_receiver.sv'],tmp,{'SAMPLE':sample})
    records[-1].update(stimulus_sha256=hashlib.sha256((tmp/'stimulus.txt').read_bytes()).hexdigest(),expected_frames=v.count)
   run('tb_ir_control',[ROOT/'rtl/media_infrared_control.v',HERE/'tb_control.sv'],tmp)
   run('tb_ir_fixed',[ROOT/'rtl/media_infrared_control.v',HERE/'tb_control.sv',HERE/'tb_fixed.sv'],tmp)
   run('tb_ir_extra',[ROOT/'rtl/media_infrared_control.v',HERE/'tb_control.sv',HERE/'tb_extra.sv'],tmp)
   run('tb_ir_model_toggle',[ROOT/'rtl/media_infrared_control.v',HERE/'tb_control.sv',HERE/'tb_model_toggle.sv'],tmp)
   run('tb_ir_directions',[ROOT/'rtl/media_infrared_control.v',HERE/'tb_control.sv',HERE/'tb_directions.sv'],tmp)
   # Keep actual HDMI composition for the homepage sequence. Only the board
   # clocks, media storage, and physical outputs need the board stubs here.
   model_text=board_model.read_text(encoding='utf-8')
   tmds_model=model_text[model_text.index('module tmds_ddr_tx'):model_text.index('module tb_hdmi_media_board_top')]
   (tmp/'home_pins.sv').write_text(model_text[:model_text.index('module hdmi_av_output')]+tmds_model,encoding='utf-8')
   run('tb_ir_fixed_board',[
    *[p for p in sorted((ROOT/'rtl').glob('*.v')) if p.name not in ('board_pll.v','sd_media_player.v','tmds_ddr_tx.v')],
    tmp/'home_pins.sv',ROOT/'tests/dmz_media/dmz_keyboard_model.sv',HERE/'tb_fixed_board.sv'],tmp)
   run('tb_ir_direction_board',[*[ROOT/'rtl'/n for n in names],ROOT/'tests/dmz_media/tb_hdmi_media_board_top.sv',ROOT/'tests/dmz_media/dmz_keyboard_model.sv',HERE/'tb_direction_board.sv'],tmp)
   fixture=run_path(str(fixture_script))['fixture']
   # Reuse the existing PLL and HDMI models; keep the real player and raster.
   pins=model_text[:model_text.index('module sd_media_player')]
   pins+=model_text[model_text.index('module hdmi_av_output'):model_text.index('module tb_hdmi_media_board_top')]
   (tmp/'gallery_pins.sv').write_text(pins,encoding='utf-8')
   gallery_sources=[
    *[p for p in sorted((ROOT/'rtl').glob('*.v')) if p.name not in ('board_pll.v','hdmi_av_output.v','tmds_ddr_tx.v','sd_subsystem.v')],
    ROOT/'tests/clock_buffer_model.v',ROOT/'tests/em638325_model.sv',tmp/'gallery_pins.sv',
    ROOT/'tests/dmz_media/dmz_keyboard_model.sv',HERE/'tb_gallery_card.sv']
   for pages in (2,6):
    card=fixture(0,first_count=pages)
    (tmp/'ir_gallery_card.hex').write_text(''.join(f'{b:02x}\n' for b in card),encoding='ascii')
    run('tb_ir_gallery_card',gallery_sources,tmp,{'PAGES':pages})
   run('tb_ir_thresholds',[ROOT/'rtl/media_infrared_control.v',HERE/'tb_control.sv',HERE/'tb_thresholds.sv'],tmp)
   run('tb_ir_board',[*[ROOT/'rtl'/n for n in names],
       ROOT/'tests/dmz_media/tb_hdmi_media_board_top.sv',ROOT/'tests/dmz_media/dmz_keyboard_model.sv',HERE/'tb_board.sv'],tmp)
  assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in hashes.items())
  (HERE/'summary.json').write_text(json.dumps({'status':'passed','cases':records,'inputs_sha256':hashes},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 finally:(HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')

if __name__=='__main__':main()
