"""Run the real exhibition RTL testbenches using the local Icarus installation."""
from pathlib import Path
import argparse,hashlib,json,os,shutil,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--tool-dir',type=Path)
 p.add_argument('--scope',choices=['quick','3d','all'],default='quick')
 a=p.parse_args();directory=a.tool_dir
 if directory is None and os.environ.get('IVERILOG_BIN'):directory=Path(os.environ['IVERILOG_BIN'])
 if directory is None:
  found=shutil.which('iverilog.exe' if os.name=='nt' else 'iverilog')
  directory=Path(found).parent if found else Path.home()/'.codex/toolchains/iverilog-iccoder-2.0.10/bin'
 if not all((directory/(n+('.exe' if os.name=='nt' else ''))).is_file() for n in ['iverilog','vvp']):
  raise FileNotFoundError('Icarus Verilog was not found; pass --tool-dir with its bin directory')
 jobs=[]
 if a.scope in ['quick','all']:jobs+=['tests/chinese_subtitle/verify.py','tests/topic_folders/verify.py','tests/home/verify_controls.py']
 if a.scope in ['3d','all']:jobs+=['tests/solar_scene/verify.py','tests/earth_moon/verify.py','tests/infrared/verify.py']
 output=ROOT/'reports/display_sim';output.mkdir(parents=True,exist_ok=True)
 sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 inputs={p.relative_to(ROOT).as_posix():sha(p) for p in (ROOT/'rtl').glob('*.v')}
 env=dict(os.environ,PYTHONUTF8='1',PYTHONUNBUFFERED='1')
 results=[]
 with (output/'latest.log').open('w',encoding='utf-8') as log:
  for script in jobs:
   print('Running '+script,flush=True);log.write('Running '+script+'\n');log.flush()
   child=subprocess.Popen([sys.executable,'-B',script,'--tool-dir',str(directory)],cwd=ROOT,
    stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',env=env)
   for line in child.stdout:
    print(line,end='',flush=True);log.write(line);log.flush()
   code=child.wait();results.append(dict(script=script,exit_code=code))
   if code:break
 if any(sha(ROOT/n)!=v for n,v in inputs.items()):raise RuntimeError('RTL changed during simulation; rerun')
 passed=len(results)==len(jobs) and all(r['exit_code']==0 for r in results)
 (output/'latest.json').write_text(json.dumps(dict(status='passed' if passed else 'failed',scope=a.scope,
  checks=results,rtl_sha256=inputs,hardware_tested=False),indent=2)+'\n',encoding='utf-8')
 print('PASS: display simulation completed' if passed else 'FAIL: see reports/display_sim/latest.log',flush=True)
 return 0 if passed else 1

if __name__=='__main__':
 try:sys.exit(main())
 except Exception as e:print('FAIL: '+str(e),file=sys.stderr);sys.exit(1)
