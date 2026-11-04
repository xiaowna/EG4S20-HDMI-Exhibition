"""Settings values must affect actual photo pixels before and after menu exit."""
from pathlib import Path
import argparse,hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--tool-dir',type=Path,required=True);a=p.parse_args()
 sources=[p for p in (ROOT/'rtl').glob('*.v') if p.name!='board_pll.v']+[HERE/'tb_pixel_path.sv']
 hashes={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
 logs=[]
 try:
  with tempfile.TemporaryDirectory(prefix='settings_photo_') as folder:
   exe=Path(folder)/'photo.vvp'
   for command in [[a.tool_dir/'iverilog.exe','-g2012','-s','tb_fine_pixel_path','-o',exe,*sources],
                   [a.tool_dir/'vvp.exe',exe]]:
    r=subprocess.run(list(map(str,command)),cwd=folder,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=300)
    logs.append(r.stdout+r.stderr);print(logs[-1],end='',flush=True)
    if r.returncode or 'FATAL' in logs[-1]:raise RuntimeError('Settings-to-photo path failed')
   if 'PASS settings-to-photo:' not in logs[-1]:raise RuntimeError('Pixel completion marker missing')
  if any(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()!=v for n,v in hashes.items()):raise RuntimeError('Inputs changed during simulation')
  (HERE/'pixel_path_summary.json').write_text(json.dumps(dict(status='passed',source_sha256=hashes,hardware_tested=False),indent=2)+'\n',encoding='utf-8')
 finally:(HERE/'pixel_path.log').write_text(''.join(logs),encoding='utf-8')
if __name__=='__main__':main()
