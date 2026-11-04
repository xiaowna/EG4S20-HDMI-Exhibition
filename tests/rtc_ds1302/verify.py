"""DS1302 protocol model, independent BCD/calendar oracle and current board UI."""
from pathlib import Path
import argparse,calendar,hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
def valid(c,w,ctl):
 def bcd(v):return v//16*10+v%16 if v//16<10 and v%16<10 else -1
 s,m,h,d,mo,y=map(bcd,c)
 return ctl==128 and 1<=w<=7 and 0<=s<60 and 0<=m<60 and 0<=h<24 and 0<=y<=99 and 1<=mo<=12 and 1<=d<=calendar.monthrange(2000+y,mo)[1]
def vectors():
 base=[0x56,0x34,0x12,0x25,0x10,0x26];out=[(base[:],7,128)]
 for f in range(8):
  for v in range(256):
   c=base[:];w=7;ctl=128
   if f<6:c[f]=v
   elif f==6:w=v
   else:ctl=v
   out.append((c,w,ctl))
 for y in range(100):
  for d in [28,29,30,31]:out.append(([0,0,0,int(str(d),16),2,int(str(y),16)],1,128))
 return out
def main():
 p=argparse.ArgumentParser();p.add_argument('--tool-dir',type=Path,required=True);a=p.parse_args();logs=[];records=[]
 inputs={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in [*(ROOT/'rtl').glob('*.v'),*HERE.glob('*.sv'),Path(__file__)]}
 def run(cmd,t):
  r=subprocess.run(list(map(str,cmd)),cwd=t,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=300)
  output=r.stdout+r.stderr;logs.append(output);print(output,end='',flush=True)
  if r.returncode or 'FATAL' in output:raise RuntimeError('DS1302 acceptance failed')
 try:
  with tempfile.TemporaryDirectory(prefix='ds1302_') as t:
   t=Path(t)
   for q,strict,vs in [(5,0,vectors()),(125,1,vectors()[:1])]:
    (t/'vectors.txt').write_text(''.join(f'{bytes(reversed(c)).hex()} {w:02x} {ctl:02x} {int(valid(c,w,ctl))}\n' for c,w,ctl in vs),encoding='ascii')
    run([a.tool_dir/'iverilog.exe','-g2012','-s','tb_ds1302',f'-Ptb_ds1302.Q={q}',f'-Ptb_ds1302.STRICT={strict}','-o',t/'rtc.vvp',ROOT/'rtl/rtc_ds1302.v',HERE/'ds1302_model.sv',HERE/'tb_rtc.sv'],t)
    run([a.tool_dir/'vvp.exe',t/'rtc.vvp'],t);records.append(dict(q=q,strict=bool(strict),calendar_vectors=len(vs)))
  assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in inputs.items())
  (HERE/'summary.json').write_text(json.dumps(dict(status='passed',cases=records,inputs_sha256=inputs,hardware_tested=False),indent=2)+'\n',encoding='utf-8')
 finally:(HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')
if __name__=='__main__':main()
