"""Separate caption drawer, mixed-bank photo slides and intro composition."""
from pathlib import Path
import argparse,hashlib,json,subprocess,tempfile,importlib.util
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('independent_intro_oracle',ROOT/'tests/intro_animation/verify_producer.py')
reference=importlib.util.module_from_spec(spec);spec.loader.exec_module(reference)

def cases():
 out=[]
 for n in range(12):
  c=dict(topic=n%4,phase=18,bank=n%2,captions=True,intro=False)
  if n<3:c['phase']=[0,6,12][n]
  elif n<9:
   i=(n-3)//2;c.update(slide_offset=[1,319,639][i],slide_right=bool((n-3)%2),slide_alpha=[32,16,1][i])
  elif n==9:c.update(phase=9,slide_offset=319,slide_right=True,slide_alpha=16)
  else:c.update(topic=0 if n==10 else 3,phase=49 if n==10 else 63,intro=True)
  out.append(c)
 return out

def main():
 p=argparse.ArgumentParser();p.add_argument('--tool-dir',type=Path,required=True);a=p.parse_args()
 m=json.loads((ROOT/'assets/intro_assets.json').read_text(encoding='utf-8'));logs=[]
 sources=[ROOT/'rtl'/n for n in ['intro_assets_rom.v','intro_text_layer.v','intro_line_store.v','frame_intro_prefetch.v']]+[HERE/'tb_gallery.sv']
 entry_sources=[ROOT/'rtl'/n for n in ['media_prefetch_control.v','media_home_control.v']]+[HERE/'tb_entry.sv']
 spectrum_sources=[ROOT/'rtl/video_audio_spectrum.v',HERE/'tb_spectrum.sv']
 pause_sources=[ROOT/'rtl'/n for n in ['sd_media_player.v','sd_sector_arbiter.v','fat32_wav_player.v','fat32_file_reader.v','wav_pcm_decoder.v','media_prefetch_control.v']]+[HERE/'pause_pipeline_stubs.sv',HERE/'tb_pause_caption.sv']
 files=sources+entry_sources+spectrum_sources+pause_sources+[ROOT/'tests/intro_animation/verify_producer.py',ROOT/'assets/intro_assets.json',Path(__file__)]
 hs={x.relative_to(ROOT).as_posix():hashlib.sha256(x.read_bytes()).hexdigest() for x in files}
 def run(cmd,cwd):
  r=subprocess.run(list(map(str,cmd)),cwd=cwd,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=1800)
  logs.append(r.stdout+r.stderr);print(logs[-1],end='',flush=True)
  assert r.returncode==0 and 'FATAL' not in logs[-1],logs[-1]
 try:
  with tempfile.TemporaryDirectory(prefix='gallery_caption_') as t:
   t=Path(t)
   for top,src in [('tb_gallery_pause_caption',pause_sources),('tb_gallery_cache_entry',entry_sources),('tb_gallery_home_speed',entry_sources),('tb_gallery_spectrum',spectrum_sources)]:
    run([a.tool_dir/'iverilog.exe','-g2012','-s',top,'-o',t/'control.vvp']+src,t)
    run([a.tool_dir/'vvp.exe',t/'control.vvp'],t)
   for n,c in enumerate(cases()):
    frame=reference.expected_frame(m,**c);(t/f'golden_{n}.hex').write_text(''.join(f'{int(x):06x}\n' for x in frame),encoding='ascii')
   for native in [False,True]:
    cmd=[a.tool_dir/'iverilog.exe','-g2012','-s','tb_gallery_producer','-o',t/'test.vvp']
    if native:cmd+=['-DINTRO_NATIVE_RAM',ROOT/'tests/intro_animation/line_bram32k_model.sv']
    run(cmd+sources,t);run([a.tool_dir/'vvp.exe',t/'test.vvp','+CASES=12'],t)
  assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==v for n,v in hs.items())
  (HERE/'summary.json').write_text(json.dumps(dict(status='passed',cases=cases(),pixels=12*307200*2,native_scanline_branch=True,inputs_sha256=hs),indent=2),encoding='utf-8')
 finally:(HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')
if __name__=='__main__':main()
