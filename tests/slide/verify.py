"""Sliding address geometry, real cached-frame composition, and frame ownership."""
from pathlib import Path
import argparse,hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--tool-dir',type=Path,required=True)
 args=p.parse_args();logs=[];records=[]
 sources=[ROOT/'rtl'/n for n in ['frame_burst_prefetch.v','pixel_async_fifo.v']]
 core=[ROOT/'rtl'/n.strip() for n in (ROOT/'sources.txt').read_text().splitlines() if n.strip()]
 core += [ROOT/'tests/clock_buffer_model.v',ROOT/'tests/em638325_model.sv']
 inputs={str(f.relative_to(ROOT)):hashlib.sha256(f.read_bytes()).hexdigest() for f in core+[HERE/'tb_burst.sv',HERE/'tb_pipeline.sv',HERE/'tb_full.sv']}
 def run(cmd,cwd):
  r=subprocess.run(list(map(str,cmd)),cwd=cwd,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=1800)
  text=r.stdout+r.stderr;logs.append(text);print(text,end='',flush=True)
  if r.returncode or 'FATAL' in text:raise RuntimeError('sliding test failed')
 try:
  with tempfile.TemporaryDirectory(prefix='slide_') as tmp:
   tmp=Path(tmp)
   for w,h,burst in [(3,2,1),(7,5,3),(32,9,32),(640,3,32)]:
    run([args.tool_dir/'iverilog.exe','-g2012','-s','tb_slide_burst',f'-Ptb_slide_burst.W={w}',f'-Ptb_slide_burst.H={h}',f'-Ptb_slide_burst.MAX_BURST={burst}','-o',tmp/'check.vvp',*sources,HERE/'tb_burst.sv'],tmp)
    run([args.tool_dir/'vvp.exe',tmp/'check.vvp'],tmp);records.append({'width':w,'height':h,'burst':burst})
   for fast,bad in [(0,0),(0,1),(1,0),(1,1)]:
    run([args.tool_dir/'iverilog.exe','-g2012','-s','tb_slide_pipeline',f'-Ptb_slide_pipeline.BAD={bad}',f'-Ptb_slide_pipeline.FAST={fast}','-o',tmp/'pipeline.vvp',*core,HERE/'tb_pipeline.sv'],tmp)
    run([args.tool_dir/'vvp.exe',tmp/'pipeline.vvp'],ROOT/'tests');records.append({'real_fat_sdram_pipeline':True,'bad_file':bad,'fast':bool(fast)})
   for full in [0,1]:
    run([args.tool_dir/'iverilog.exe','-g2012','-s','tb_slide_full',f'-Ptb_slide_full.FULL={full}','-o',tmp/'full.vvp',*core,HERE/'tb_full.sv'],tmp)
    run([args.tool_dir/'vvp.exe',tmp/'full.vvp'],tmp);records.append({'full_size_display':bool(full)})
  for n,h in inputs.items():assert hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h
  (HERE/'summary.json').write_text(json.dumps({'status':'passed','cases':records,'inputs_sha256':inputs},indent=2)+'\n',encoding='utf-8')
 finally:(HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')

if __name__=='__main__':main()
