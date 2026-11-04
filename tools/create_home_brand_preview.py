"""Render the FPGA homepage and secret celebration as software references."""
from pathlib import Path
import argparse,importlib.util,json,sys
import numpy as np
from PIL import Image,ImageDraw

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
  if index==0:base=np.asarray(image).copy()
 glyphs=Image.new('1',(144,16))
 for i in range(9):
  for y in range(16):
   for x in range(16):
    glyphs.putpixel((16*i+x,y),bits[81920+(96+(i//5)*16+y)*128+(i%5)*16+x])
 glyphs=glyphs.resize((288,32),Image.Resampling.NEAREST)
 yy,xx=np.indices((480,640));right=xx>=320;cx=np.where(right,480,160);cy=np.where(right,128,144)
 dx=np.abs(xx-cx);dy=np.abs(yy-cy);frames=[]
 for frame in range(0,240,5):
  age=(frame%64+np.where(right,32,0))%64;r=age*2+4;diagonal=r//2+r//4
  mask=(age<48)&(((dx<=1)&(dy+6>=r)&(dy<=r))|((dy<=1)&(dx+6>=r)&(dx<=r))|
                  ((np.abs(dx-dy)<=1)&(dx+4>=diagonal)&(dx<=diagonal)))
  palette=np.where(right,0xd9a8ff if frame&64 else 0x8ae7ff,0xff9ebc if frame&64 else 0xffd26a)
  color=np.where(age<16,0xfff0c2,np.where(age<32,palette,(palette>>1)&0x7f7f7f))
  rgb=np.stack(((color>>16)&255,(color>>8)&255,color&255),axis=-1).astype(np.uint8)
  pixels=base.copy();pixels[mask]=rgb[mask];image=Image.fromarray(pixels)
  draw=ImageDraw.Draw(image);draw.rectangle((152,192,487,255),fill='#162737',outline='#70d6bc',width=2)
  image.paste('#e7efec',(176,208),glyphs);frames.append(image)
 frames[3].save(a.output/'彩蛋画面.png')
 frames[0].save(a.output/'彩蛋烟花_软件参考.gif',save_all=True,append_images=frames[1:],duration=84,loop=0,disposal=2)
 print('Saved homepage PNGs and 4-second celebration GIF:',a.output)

if __name__=='__main__':main()
