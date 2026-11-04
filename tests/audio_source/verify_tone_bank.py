from pathlib import Path
import argparse,subprocess
p=argparse.ArgumentParser();p.add_argument('--tool-dir',type=Path,required=True);a=p.parse_args()
t=a.tool_dir.resolve();d=Path(__file__).resolve().parent;b=d.parents[1];logs=[]
def run(cmd):
 r=subprocess.run(list(map(str,cmd)),cwd=d,capture_output=True,text=True,timeout=120)
 out=r.stdout+r.stderr;logs.append(out);print(out,end='',flush=True)
 if r.returncode or 'FATAL' in out:raise RuntimeError('Test failed')
try:
 for hz in [480000,50000000]:
  run([t/'iverilog.exe','-g2012','-s','tb_audio_tone_bank',f'-Ptb_audio_tone_bank.CLK_HZ={hz}','-o','tone_bank.vvp',b/'rtl/audio_tone_bank.v',d/'tb_audio_tone_bank.sv'])
  run([t/'vvp.exe','tone_bank.vvp'])
finally:(b/'reports/tone_bank_regression.txt').write_text(''.join(logs),encoding='utf-8')
