from pathlib import Path
import argparse
import subprocess
base=Path(__file__).resolve().parent
p=argparse.ArgumentParser()
p.add_argument('--tool-dir',type=Path,required=True)
tools=p.parse_args().tool_dir.resolve()
rtl=base.parents[1]/'rtl/fat32_file_reader.v'
log=[]
def run(args):
 p=subprocess.run([str(a) for a in args],cwd=base,capture_output=True,text=True)
 log.append(p.stdout+p.stderr)
 if p.returncode or 'FATAL:' in p.stdout:
  print(p.stdout+p.stderr);(base/'results.txt').write_text('\n'.join(log));raise SystemExit(1)
 print(p.stdout.strip())
run([tools/'iverilog.exe','-g2012','-s','tb_file','-o','test.vvp',rtl,base/'tb_file.sv'])
for mode in range(18):run([tools/'vvp.exe','test.vvp',f'+MODE={mode}'])
run([tools/'iverilog.exe','-g2005','-s','fat32_file_reader','-o','design.vvp',rtl])
(base/'results.txt').write_text('\n'.join(log))
