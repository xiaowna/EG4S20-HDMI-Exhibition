"""Absolute source-coordinate mapping; color/text remain the existing oracle."""
from pathlib import Path
import importlib.util
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('intro_pixel_reference',ROOT/'tests/intro_animation/verify_producer.py')
reference=importlib.util.module_from_spec(spec);spec.loader.exec_module(reference)

def fraction(phase,frames):
    # round(256 * (6t^5 - 15t^4 + 10t^3)), using exact integer arithmetic
    return (256*(6*phase**5-15*phase**4*frames+10*phase**3*frames**2)+frames**5//2)//frames**5

def expected_frame(metadata,topic,phase,bank,style=0,**options):
    pixels=reference.expected_frame(metadata,topic,phase,bank,**options)
    distance=options.get('slide_offset',0)
    if style==0 or distance==0:return pixels
    assert style in [1,2] and 0<distance<640
    ys,xs=np.indices((352,640),dtype=np.int64)
    direction=np.full((352,640),options.get('slide_right',False),dtype=bool)
    if style==2:direction^=((ys//32)&1)!=0
    new=np.where(direction,xs<distance,xs>=640-distance)
    addresses=np.where(new,1-bank,bank)*307200+ys*640+xs
    pixels[:352*640]=(((addresses*37)^(addresses<<7)^0x5a39c7)&0xffffff).reshape(-1)
    return pixels

def cases():
    result=[]
    for style in range(3):
        for direction in [False,True]:
            result.append(dict(style=style,slide_right=direction,slide_offset=319,slide_alpha=16))
    result += [dict(style=1,slide_right=False,slide_offset=0,slide_alpha=32),
               dict(style=2,slide_right=True,slide_offset=0,slide_alpha=32),
               dict(style=2,slide_right=True,slide_offset=639,slide_alpha=1),
               dict(style=1,slide_right=False,slide_offset=1,slide_alpha=32)]
    for n,case in enumerate(result):case.update(topic=n%4,phase=18,bank=n%2,captions=True,intro=False)
    return result
