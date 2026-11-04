"""Software reference for the FPGA's caption entrance and old-caption slide fade."""
from pathlib import Path
import argparse
import numpy as np
from PIL import Image


def still(source, phase):
    p=min(12,phase);amount=(16*p*p*(36-2*p)+864)//1728
    alpha=16+amount;top=368-amount
    out=np.empty((480,640,3),dtype=np.int32);out[:]=[6,12,20];out[:352]=source[:352]
    ink=source[384:384+416-top,18:622]
    out[top:416,18:622]=(np.array([6,12,20])*(32-alpha)+ink*alpha+16)//32
    return Image.fromarray(out.astype('uint8'))


def slide(before, after, phase, backward):
    fraction=(256*phase*phase*(36-2*phase)+864)//1728;distance=640*fraction//256
    alpha=32-(fraction>>3)
    out=np.empty((480,640,3),dtype=np.int32);out[:]=[6,12,20]
    if backward:
        out[:352,:distance]=after[:352,640-distance:]
        out[:352,distance:]=before[:352,:640-distance]
    else:
        out[:352,:640-distance]=before[:352,distance:]
        out[:352,640-distance:]=after[:352,:distance]
    out[352:416,18:622]=(np.array([6,12,20])*(32-alpha)+before[384:448,18:622]*alpha+16)//32
    return Image.fromarray(out.astype('uint8'))


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('first',type=Path);p.add_argument('second',type=Path);p.add_argument('output',type=Path)
    a=p.parse_args();sources=[np.asarray(Image.open(n).convert('RGB'),dtype=np.int32) for n in [a.first,a.second]]
    if any(s.shape!=(480,640,3) for s in sources):p.error('Requires two 640x480 board BMPs')
    frames=[];durations=[]
    for i in range(2):
        frames.extend(still(sources[i],phase) for phase in range(13))
        durations.extend([20,10,20]*4+[1000])
        frames.extend(slide(sources[i],sources[1-i],phase,bool(i)) for phase in range(12))
        durations.extend([20,10,20]*4)
    a.output.parent.mkdir(parents=True,exist_ok=True)
    frames[0].save(a.output,save_all=True,append_images=frames[1:],duration=durations,loop=0,disposal=2)
    print('Software reference saved:',a.output)


if __name__=='__main__':main()
