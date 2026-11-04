"""测试向量：以完整多项式长除法独立计算 BCH 黄金结果。"""
from pathlib import Path
import random
p=Path(__file__).resolve().parent

def ecc(value,n):
    message=int(f'{value:0{n}b}'[::-1],2)<<8
    for bit in range(n+7,7,-1):
        if message&(1<<bit):message ^= 0x1c1<<(bit-8)
    return int(f'{message:08b}'[::-1],2)

r=random.Random(4813)
inputs=[0,(1<<248)-1]+[r.getrandbits(248) for _ in range(6)]
outputs=[]
for x in inputs:
    header=x&0xffffff;body=x>>24
    out=header|(ecc(header,24)<<24)
    for j in range(4):
        sub=(body>>(56*j))&((1<<56)-1)
        out|=(sub|(ecc(sub,56)<<56))<<(32+64*j)
    outputs.append(out)
(p/'input.hex').write_text(''.join(f'{x:062x}\n' for x in inputs))
(p/'golden.hex').write_text(''.join(f'{x:072x}\n' for x in outputs))
