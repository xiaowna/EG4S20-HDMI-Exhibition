"""Render the five FPGA homepage cards as software references."""
from pathlib import Path
import argparse,importlib.util,json,sys
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
 a.output.mkdir(parents=True,exist_ok=True)
 sys.path.insert(0,str(ROOT/'tests/home'))
 spec=importlib.util.spec_from_file_location('home_reference',ROOT/'tests/home/verify.py')
 home=importlib.util.module_from_spec(spec);spec.loader.exec_module(home)
 asset=json.loads((ROOT/'assets/home_assets.json').read_text(encoding='utf-8'));bits=asset['bits']
 for index in range(5):
  colors=[home.reference(x,y,0x4000|(index<<1),bits,branding=True)[0] for y in range(480) for x in range(640)]
  image=Image.new('RGB',(640,480));image.putdata([((c>>16)&255,(c>>8)&255,c&255) for c in colors])
  image.save(a.output/f'首页_{index+1}.png')
 print('Saved five homepage PNGs:',a.output)

if __name__=='__main__':main()
