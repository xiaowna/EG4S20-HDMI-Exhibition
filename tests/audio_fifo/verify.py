"""音频 FIFO 复位与边界回归；不修改板级顶层。"""
from pathlib import Path
import argparse
import subprocess
p=argparse.ArgumentParser()
p.add_argument('--tool-dir',type=Path,required=True)
a=p.parse_args()
d=Path(__file__).resolve().parent
b=d.parents[1]
t=a.tool_dir.resolve()
logs=[]
try:
    for bits in (3,8,11):
        for cmd in (
            [t/'iverilog.exe','-g2012','-s','tb_audio_fifo_reset',
             f'-Ptb_audio_fifo_reset.ADDR_BITS={bits}','-o',d/'check.vvp',
             b/'rtl/audio_async_fifo.v',d/'tb_audio_fifo_reset.sv'],
            [t/'vvp.exe',d/'check.vvp']):
            r=subprocess.run(list(map(str,cmd)),capture_output=True,text=True,timeout=30)
            output=r.stdout+r.stderr
            logs.append(output)
            print(output,end='')
            if r.returncode or 'FATAL' in output:
                raise RuntimeError('FIFO regression failed')
finally:
    (b/'reports/audio_fifo_regression.txt').write_text(''.join(logs),encoding='utf-8')
