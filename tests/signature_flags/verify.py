"""Signature compression: frozen complete-module equivalence + independent oracles."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,tempfile
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
DEFAULT_BASE=ROOT/'reports/o22_signature_flags_20261023/before/worktree/rtl'
NAMES=['fat32_boot_parser','fat32_volume_locator','fat32_bpb_math']

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--tool-dir',type=Path,default=(Path.home()/'.codex/toolchains/iverilog-iccoder-2.0.10/bin'))
 p.add_argument('--rtl-dir',type=Path,default=ROOT/'rtl');p.add_argument('--baseline-dir',type=Path,default=DEFAULT_BASE)
 p.add_argument('--timeouts',type=int,nargs='+',default=[800,2048]);p.add_argument('--shared',type=int,nargs='+',default=[0,1])
 p.add_argument('--tag',default='regression');a=p.parse_args()
 paths=[a.rtl_dir/(n+'.v') for n in NAMES[:2]]+[a.baseline_dir/(n+'.v') for n in NAMES[:2]]
 paths += [HERE/'tb_signature_boot.sv',HERE/'tb_signature_locator.sv',Path(__file__).resolve()]
 hashes={str(x.resolve()):hashlib.sha256(x.read_bytes()).hexdigest() for x in paths}
 logs=[];runs=[]
 (HERE/(a.tag+'_summary.json')).write_text(json.dumps(dict(status='running')),encoding='utf-8')
 with tempfile.TemporaryDirectory(prefix='signature_flags_') as d:
  tmp=Path(d);s='\n'.join((a.baseline_dir/(n+'.v')).read_text(encoding='utf-8-sig') for n in NAMES[:2])
  for n in NAMES:s=re.sub(r'\b'+n+r'\b',n+'_baseline',s)
  frozen=tmp/'baseline.v';frozen.write_text(s,encoding='utf-8')
  assert 'fat32_boot_parser_baseline #(' in s and 'fat32_bpb_math_baseline u_math' in s
  for timeout in a.timeouts:
   for shared in a.shared:
    for top in ['tb_signature_boot','tb_signature_locator']:
     print(f'START {top} SHARED={shared} TIMEOUT={timeout}',flush=True)
     out=''
     commands=[[a.tool_dir/'iverilog.exe','-g2012','-DCOMPARE_BASELINE','-s',top,f'-P{top}.SHARED={shared}',f'-P{top}.TIMEOUT_CYCLES={timeout}','-o',tmp/'check.vvp',*[a.rtl_dir/(n+'.v') for n in NAMES[:2]],frozen,HERE/(top+'.sv')],[a.tool_dir/'vvp.exe',tmp/'check.vvp']]
     for command in commands:
      r=subprocess.run(list(map(str,command)),cwd=HERE,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=240)
      out+=r.stdout+r.stderr
      if r.returncode or 'FATAL' in out:
       (HERE/(a.tag+'.log')).write_text('\n'.join(logs)+out,encoding='utf-8')
       (HERE/(a.tag+'_summary.json')).write_text(json.dumps(dict(status='failed',case=top,shared=shared,timeout=timeout)),encoding='utf-8')
       raise RuntimeError(out)
     assert 'PASS signature ' in out,out
     logs.append(out);print(out,end='',flush=True)
     runs.append(dict(case=top,shared_bpb=shared,timeout=timeout,metrics=dict(re.findall(r'(\w+)=(\d+)',out.split('PASS signature ')[-1]))))
 for x,digest in hashes.items():assert hashlib.sha256(Path(x).read_bytes()).hexdigest()==digest,x
 (HERE/(a.tag+'.log')).write_text('\n'.join(logs),encoding='utf-8')
 summary=dict(status='passed',runs=runs,source_sha256=hashes,frozen_modules_independently_renamed=NAMES,
  oracle='Inherited independent integer sector classifiers and transport models; compare every public port, including 256-bit bpb_fields, on every clock. No candidate signature/state internal signal is inspected.',
  modified_production_rtl=False,hardware_tested=False)
 (HERE/(a.tag+'_summary.json')).write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
 print(f'PASS signature acceptance: {len(runs)} configurations; source hashes unchanged',flush=True)
if __name__=='__main__':main()
