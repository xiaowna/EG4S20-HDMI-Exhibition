"""Real rotary decoding, 50 MHz default timing and six-row board integration."""
from pathlib import Path
import argparse,hashlib,json,subprocess,tempfile

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--tool-dir',type=Path,required=True)
 p.add_argument('--quick',action='store_true',help='Skip default wall-time threshold case during development')
 args=p.parse_args();logs=[];records=[]
 rtl=['rtc_ds1302.v','rtc_set_control.v','media_rotary_encoder.v','hdmi_media_board_top.v','board_key.v','media_control_events.v',
      'media_mode_control.v','media_adjust_control.v','board_matrix_keys.v',
      'media_nec_receiver.v','media_infrared_control.v']
 files=[ROOT/'rtl'/n for n in rtl]+list(HERE.glob('*.sv'))+[HERE/'verify.py',
  ROOT/'tests/dmz_media/tb_hdmi_media_board_top.sv',ROOT/'tests/dmz_media/dmz_keyboard_model.sv']
 inputs={f.relative_to(ROOT).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
 def run(top,sources,tmp,params=None):
  exe=tmp/(top+'.vvp')
  commands=[[args.tool_dir/'iverilog.exe','-g2012','-s',top,
             *[f'-P{top}.{k}={v}' for k,v in (params or {}).items()],'-o',exe,*sources],
            [args.tool_dir/'vvp.exe',exe]]
  for i,cmd in enumerate(commands):
   r=subprocess.run(list(map(str,cmd)),cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=300)
   output=r.stdout+r.stderr;logs.append(output);print(output,end='',flush=True)
   assert r.returncode==0 and 'FATAL' not in output and (i==0 or 'PASS ' in output),output
  records.append({'top':top,'parameters':params or {},'passed':True})
 try:
  with tempfile.TemporaryDirectory(prefix='rotary_acceptance_') as tmp:
   tmp=Path(tmp)
   for params in [{'SAMPLE':1,'FILTER':1,'BUTTON':1,'LONG':80},
                  {'SAMPLE':3,'FILTER':3,'BUTTON':5,'LONG':80},
                  {'SAMPLE':17,'FILTER':3,'BUTTON':5,'LONG':80},
                  {'SAMPLE':1,'FILTER':3,'BUTTON':200,'LONG':6000}]:
    run('tb_encoder',[ROOT/'rtl/media_rotary_encoder.v',HERE/'tb_encoder.sv'],tmp,params)
   run('tb_encoder_board',[*[ROOT/'rtl'/n for n in rtl],
       ROOT/'tests/dmz_media/tb_hdmi_media_board_top.sv',
       ROOT/'tests/dmz_media/dmz_keyboard_model.sv',HERE/'tb_board.sv'],tmp)
   if not args.quick:
    run('tb_default_timing',[ROOT/'rtl/media_rotary_encoder.v',HERE/'tb_default_timing.sv'],tmp)
  assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==v for n,v in inputs.items())
  (HERE/'summary.json').write_text(json.dumps({'status':'passed','default_timing_tested':not args.quick,
      'cases':records,'inputs_sha256':inputs},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 finally:
  (HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')

if __name__=='__main__':main()
