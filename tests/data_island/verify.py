"""只验证当前新增的数据岛编码核心。"""
from pathlib import Path
import argparse,subprocess
p=argparse.ArgumentParser();p.add_argument('--tool-dir',type=Path,required=True);a=p.parse_args()
d=Path(__file__).resolve().parent;b=d.parents[1];t=a.tool_dir.resolve();logs=[]
commands=[[t/'iverilog.exe','-g2012','-s','tb_data_island','-o',d/'check.vvp',*[b/'rtl'/n for n in ['hdmi_bch8.v','hdmi_terc4.v','hdmi_data_island_encoder.v']],d/'tb_data_island.sv'],[t/'vvp.exe',d/'check.vvp']]
try:
 for cmd in commands:
  r=subprocess.run(list(map(str,cmd)),cwd=d,capture_output=True,text=True,timeout=30)
  output=r.stdout+r.stderr;logs.append(output);print(output,end='')
  if r.returncode or 'FATAL' in output:raise RuntimeError('Verification failed')
finally:(b/'reports/data_island_regression.txt').write_text(''.join(logs),encoding='utf-8')
