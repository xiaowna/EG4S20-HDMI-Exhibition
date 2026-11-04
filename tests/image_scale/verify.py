"""Bounded runtime BMP scaling with independent address/color/coverage oracles."""
import argparse,hashlib,json,re,subprocess,tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
FROZEN=ROOT/'reports/image_scale_20261018/before/worktree/rtl/bmp_stream_decoder.v'

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--tool-dir',type=Path,required=True)
 tools=p.parse_args().tool_dir.resolve();rtl=ROOT/'rtl/bmp_stream_decoder.v'
 core=[ROOT/'rtl'/n.strip() for n in (ROOT/'sources.txt').read_text().splitlines() if n.strip()]
 sources=[*core,FROZEN,HERE/'tb_decoder.sv',HERE/'tb_loader.sv',ROOT/'tests/bmp_counters/tb_bmp_counters.sv'];hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
 logs=[];runs=[]
 def run(command,cwd=HERE):
  r=subprocess.run(list(map(str,command)),cwd=cwd,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=600)
  out=r.stdout+r.stderr;logs.append(out);print(out,end='',flush=True)
  if r.returncode or 'FATAL' in out:raise RuntimeError('runtime scaler regression failed')
  return out
 try:
  with tempfile.TemporaryDirectory(prefix='image_scale_') as temp:
   temp=Path(temp);image=temp/'check.vvp'
   for w,h in [(2,2),(4,4),(6,4),(640,480)]:
    run([tools/'iverilog.exe','-g2012','-s','tb_bmp_scale',f'-Ptb_bmp_scale.W={w}',f'-Ptb_bmp_scale.H={h}',
         '-o',image,rtl,HERE/'tb_decoder.sv'])
    out=run([tools/'vvp.exe',image]);assert 'PASS runtime scale decoder' in out
    runs.append({'case':'decoder','width':w,'height':h,'metrics':dict(re.findall(r'(\w+)=(\d+)',out))})
   reference=temp/'reference.v';reference.write_text(FROZEN.read_text(encoding='utf-8-sig').replace('module bmp_stream_decoder #','module bmp_stream_decoder_baseline #'),encoding='utf-8')
   original_bench=ROOT/'tests/bmp_counters/tb_bmp_counters.sv'
   bench=temp/'tb_native.sv';s=original_bench.read_text(encoding='utf-8-sig')
   anchor='bmp_stream_decoder #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT)) dut'
   assert s.count(anchor)==1
   bench.write_text(s.replace(anchor,'bmp_stream_decoder #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT),.ALLOW_HALF(1)) dut'),encoding='utf-8')
   for w,h in [(6,4),(640,480)]:
    run([tools/'iverilog.exe','-g2012','-DCOMPARE_BASELINE','-s','tb_bmp_counters',
         f'-Ptb_bmp_counters.FRAME_WIDTH={w}',f'-Ptb_bmp_counters.FRAME_HEIGHT={h}',
         '-o',image,rtl,reference,bench])
    out=run([tools/'vvp.exe',image]);assert 'PASS BMP counters' in out
    runs.append({'case':'native_61bit_equivalence','width':w,'height':h,'metrics':dict(re.findall(r'(\w+)=(\d+)',out))})
   run([tools/'iverilog.exe','-g2012','-s','tb_scale_loader','-o',image,*core,HERE/'tb_loader.sv'])
   out=run([tools/'vvp.exe',image],ROOT/'tests');assert 'PASS runtime scale loader:' in out
   runs.append({'case':'mixed_size_fat_cache_loader','metrics':dict(re.findall(r'(\w+)=(\d+)',out))})
  for p,h in hashes.items():assert hashlib.sha256(Path(p).read_bytes()).hexdigest()==h,p
  (HERE/'summary.json').write_text(json.dumps({'passed':True,'runs':runs,'source_sha256':hashes},indent=2),encoding='utf-8')
  print('PASS runtime scale acceptance: independent pixels/coverage and legacy public equivalence; source hashes unchanged')
 finally:(HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')

if __name__=='__main__':main()
