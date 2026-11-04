"""Mount timers: frozen public-output equivalence, endpoint and ignored-phase wrap tests."""
import argparse,hashlib,json,re,runpy,subprocess,tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
FROZEN=ROOT/'reports/catalog_timers_20261019/before/worktree/rtl'
MODULES=['fat32_boot_parser','fat32_bmp_catalog']

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--tool-dir',type=Path,required=True)
 tools=p.parse_args().tool_dir.resolve();logs=[];runs=[]
 paths=[*[ROOT/'rtl'/n.strip() for n in (ROOT/'sources.txt').read_text().splitlines() if n.strip()],
  *[FROZEN/(n+'.v') for n in MODULES],HERE/'tb_bpb_timer.sv',HERE/'tb_catalog_timer.sv',
  ROOT/'tests/safety_counters/verify.py',ROOT/'tests/bpb_width/verify.py',ROOT/'tests/bpb_width/tb_bpb_width.sv',
  ROOT/'tests/wav_playback/card_fixture.hex',ROOT/'tests/wav_playback/card_fixture_4bmp.hex']
 hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
 def run(command,cwd=HERE):
  r=subprocess.run(list(map(str,command)),cwd=cwd,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
  out=r.stdout+r.stderr;logs.append(out);print(out,end='',flush=True)
  if r.returncode or 'FATAL' in out:raise RuntimeError('catalog timer verification failed')
  return out
 try:
  # Reuse the existing 204-bit arithmetic/transport oracle and compare to S1.
  out=run(['python',ROOT/'tests/bpb_width/verify.py','--tool-dir',tools,'--compare-rtl',FROZEN/'fat32_boot_parser.v','--log-name','catalog_timer_equivalence.log'])
  assert 'PASS: 2 BPB width timeout configurations' in out
  runs.append({'case':'bpb_full_arithmetic_and_transport','timeout_profiles':[800,2048]})
  instrument=runpy.run_path(str(ROOT/'tests/safety_counters/verify.py'))['instrument']
  with tempfile.TemporaryDirectory(prefix='catalog_timers_') as temp:
   temp=Path(temp);refs=[];rtl=[]
   for name in MODULES:
    s=(FROZEN/(name+'.v')).read_text(encoding='utf-8-sig')
    for n in MODULES:s=re.sub(r'\b'+n+r'\b',n+'_safety_reference',s)
    refs.append(s)
    q=temp/(name+'.v');q.write_text(instrument((ROOT/'rtl'/(name+'.v')).read_text(encoding='utf-8-sig'),name),encoding='utf-8');rtl.append(q)
   reference=temp/'reference.v';reference.write_text('\n'.join(refs),encoding='utf-8')
   for limit in [1,2,3,7,8,9,31,32,33,511,512,513,800,2048,50000000]:
    image=temp/'edge.vvp'
    run([tools/'iverilog.exe','-g2012','-s','tb_bpb_timer',f'-Ptb_bpb_timer.LIMIT={limit}','-o',image,rtl[0],reference,HERE/'tb_bpb_timer.sv'])
    out=run([tools/'vvp.exe',image]);assert 'PASS BPB timer' in out
    runs.append({'case':'bpb_endpoint','limit':limit,'metrics':dict(re.findall(r'(\w+)=(\d+)',out))})
   for limit,four in [(800,0),(2048,0),(2048,1),(50000000,1)]:
    image=temp/'catalog.vvp'
    run([tools/'iverilog.exe','-g2012','-s','tb_catalog_timer',f'-Ptb_catalog_timer.LIMIT={limit}',f'-Ptb_catalog_timer.FOUR_FILES={four}',
     '-o',image,*rtl,reference,ROOT/'rtl/fat32_dir_scan.v',HERE/'tb_catalog_timer.sv'])
    out=run([tools/'vvp.exe',image],ROOT/'tests/wav_playback');assert 'PASS catalog timer' in out
    runs.append({'case':'catalog_wrap_and_errors','limit':limit,'four_files':four,'metrics':dict(re.findall(r'(\w+)=(\d+)',out))})
  for p,h in hashes.items():assert hashlib.sha256(Path(p).read_bytes()).hexdigest()==h,p
  (HERE/'summary.json').write_text(json.dumps({'passed':True,'runs':runs,'source_sha256':hashes,
   'large_timeout_method':'Identical timer deposits skip elapsed idle clocks only; ordinary smaller limits run naturally. All public outputs compared every cycle.'},indent=2),encoding='utf-8')
  print('PASS catalog timer acceptance: 20 configurations, exact public equivalence, timeout/reset/restart/ignored-phase wrap; source hashes unchanged')
 finally:(HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')

if __name__=='__main__':main()
