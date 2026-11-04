"""Both complete gallery slides through actual SDRAM/refresh and VGA raster."""
from pathlib import Path
import argparse,hashlib,json,subprocess,tempfile,importlib.util
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
def main():
 p=argparse.ArgumentParser();p.add_argument('--tool-dir',type=Path,required=True);a=p.parse_args()
 oracle=ROOT/'tests/gallery_motion/oracle.py'
 spec=importlib.util.spec_from_file_location('gallery_slide_oracle',oracle);ref=importlib.util.module_from_spec(spec);spec.loader.exec_module(ref)
 metadata=json.loads((ROOT/'assets/intro_assets.json').read_text(encoding='utf-8'))
 src=[ROOT/'rtl'/n for n in ['frame_stream_display.v','frame_burst_prefetch.v','frame_intro_prefetch.v','intro_line_store.v','intro_text_layer.v','intro_assets_rom.v','pixel_async_fifo.v','video_pixel_sink.v','video_raster_timing.v','eg4s20_stream_memory.v','em638325_stream_controller.v']]
 src +=[ROOT/'tests/clock_buffer_model.v',ROOT/'tests/em638325_model.sv',HERE/'tb_slide_raster.sv']
 hs={x.relative_to(ROOT).as_posix():hashlib.sha256(x.read_bytes()).hexdigest() for x in src+[oracle,ROOT/'tests/intro_animation/verify_producer.py',ROOT/'assets/intro_assets.json',Path(__file__)]};logs=[]
 try:
  with tempfile.TemporaryDirectory(prefix='gallery_slide_raster_') as t:
   t=Path(t)
   for bank in range(2):
    for phase in range(13):
     frame=ref.expected_frame(metadata,0,phase,bank,captions=True,intro=False)
     (t/f'entry_{bank}_{phase}.hex').write_text(''.join(f'{int(x):06x}\n' for x in frame),encoding='ascii')
   for style in range(3):
    bank=style%2
    for phase in range(9):
     fraction=ref.fraction(phase,9)
     frame=ref.expected_frame(metadata,0,18,bank,style=style,captions=True,intro=False,slide_offset=640*fraction//256,slide_right=bool(bank),slide_alpha=32-(fraction>>3))
     (t/f'slide_{style}_{bank}_{phase}.hex').write_text(''.join(f'{int(x):06x}\n' for x in frame),encoding='ascii')
   for cmd in [[a.tool_dir/'iverilog.exe','-g2012','-s','tb_gallery_slide_raster','-o',t/'slide.vvp',*src],[a.tool_dir/'vvp.exe',t/'slide.vvp']]:
    r=subprocess.run(list(map(str,cmd)),cwd=t,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=2400)
    logs.append(r.stdout+r.stderr);print(logs[-1],end='',flush=True)
    assert r.returncode==0 and 'FATAL' not in logs[-1],logs[-1]
  assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in hs.items())
  (HERE/'slide_raster_summary.json').write_text(json.dumps(dict(status='passed',both_directions=True,styles=3,phases_each=9,real_sdram_refresh_arbitration=True,concurrent_writes_outside_both_source_banks=True,hardware_tested=False,inputs_sha256=hs),indent=2),encoding='utf-8')
 finally:(HERE/'slide_raster.log').write_text(''.join(logs),encoding='utf-8')
if __name__=='__main__':main()
