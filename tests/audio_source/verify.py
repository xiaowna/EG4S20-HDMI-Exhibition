"""验证音频源的采样率、逐样本波形、背压、静音和复位。"""
from pathlib import Path
import argparse, subprocess
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--tool-dir',type=Path,required=True)
a=p.parse_args();t=a.tool_dir.resolve()
d=Path(__file__).resolve().parent;b=d.parents[1];log=[]
def run(args):
    result=subprocess.run([str(x) for x in args],cwd=d,capture_output=True,text=True,timeout=90)
    output=result.stdout+result.stderr;log.append(output);print(output,end='',flush=True)
    if result.returncode or 'FATAL' in output:raise RuntimeError('Audio test failed')
try:
    for hz in [50_000_000,25_000_000,49_152_000,96_000,48_000]:
        run([t/'iverilog.exe','-g2012','-s','tb_audio_source',f'-Ptb_audio_source.CLK_HZ={hz}',
             '-o','audio.vvp',b/'rtl/audio_test_tone.v',d/'tb_audio_source.sv'])
        run([t/'vvp.exe','audio.vvp'])
finally:
    (b/'reports/audio_source_regression.txt').write_text(''.join(log),encoding='utf-8')
