"""Independent numerical and raster oracles for the V03 FFT spectrum."""
import argparse
import cmath
import importlib.util
import json
import math
from pathlib import Path
import random
import re
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
ENDS=[2,3,4,5,6,7,8,9,10,12,14,16,19,22,26,30,35,41,48,56,65,76,88,102,118,137,159,184,213,232,244,256]


def quantize(v):
    return min(32767,max(-32768,round(v*32768)))


WINDOW=[quantize((1-math.cos(2*math.pi*n/512))/2) for n in range(512)]
TWIDDLE=[(quantize(math.cos(2*math.pi*k/512)),quantize(-math.sin(2*math.pi*k/512))) for k in range(256)]


def transform(samples):
    values=[(0,0)]*512
    for n,s in enumerate(samples):
        reverse=int(f'{n:09b}'[::-1],2)
        values[reverse]=((s*WINDOW[n])>>15,0)
    clamp=lambda x:min(32767,max(-32768,x>>16))
    for stage in range(1,10):
        size=1<<stage
        for base in range(0,512,size):
            for offset in range(size//2):
                a,b=base+offset,base+offset+size//2
                ar,ai=values[a];br,bi=values[b];wr,wi=TWIDDLE[offset*512//size]
                rr,ii=br*wr-bi*wi,br*wi+bi*wr
                values[a]=(clamp((ar<<15)+rr),clamp((ai<<15)+ii))
                values[b]=(clamp((ar<<15)-rr),clamp((ai<<15)-ii))
    return values[:256]


def heights(bins):
    result=[];start=1
    for end in ENDS:
        peak=max(max(abs(r),abs(i))+min(abs(r),abs(i))//2 for r,i in bins[start:end])
        if peak<8:level=0
        else:
            exponent=peak.bit_length()-1
            level=min(96,exponent*8-24+((peak>>(exponent-3))&7))
        result.append(level);start=end
    return result


def vectors():
    sine=lambda k,a=24000:[round(a*math.sin(2*math.pi*k*n/512)) for n in range(512)]
    rng=random.Random(45830)
    return [[0]*512,[12000]*512,[-32768]*512,[32767]+[0]*511,
            sine(11),sine(101),[round(14000*math.sin(2*math.pi*5*n/512)+10000*math.sin(2*math.pi*61*n/512)) for n in range(512)],
            [rng.randint(-32768,32767) for _ in range(512)]]


def numerical_checks(cases):
    display_heights=[(level*45+16)//32 for level in range(97)]
    assert display_heights[0]==0 and display_heights[-1]==135
    assert all(a<=b for a,b in zip(display_heights,display_heights[1:]))
    assert all(abs(a*5-level*7)<=5 for level,a in enumerate(display_heights))
    print('PASS V03B display gain: all 97 levels within one pixel of +40%, maximum 135 pixels')
    max_error=0
    for samples in cases:
        actual=transform(samples)
        windowed=[s*w/32768 for s,w in zip(samples,WINDOW)]
        for k,(r,i) in enumerate(actual):
            step=cmath.exp(-2j*math.pi*k/512);factor=1+0j;ideal=0j
            for v in windowed:
                ideal+=v*factor;factor*=step
            max_error=max(max_error,abs(complex(r,i)-ideal/512))
    assert max_error<12,max_error
    for index,frequency in [(4,11),(5,101)]:
        bins=transform(cases[index]);peak=max(range(1,256),key=lambda k:sum(v*v for v in bins[k]))
        assert peak==frequency,(index,peak)
    print(f'PASS independent floating DFT reference: all 2048 bins, max fixed-point complex error={max_error:.3f}; 1031.25Hz and 9468.75Hz peaks correct')


def run(top,bench,sources,temp,tools,logs,params=None):
    commands=[[tools/'iverilog.exe','-g2012','-s',top,
               *[f'-P{top}.{k}={v}' for k,v in (params or {}).items()],
               '-o',temp/'check.vvp',*sources,HERE/bench],
              [tools/'vvp.exe',temp/'check.vvp']]
    for command in commands:
        result=subprocess.run(list(map(str,command)),cwd=temp,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=600)
        output=result.stdout+result.stderr;print(output,end='',flush=True);logs.append(output)
        if result.returncode or 'FATAL' in output:raise RuntimeError(top+' failed')


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--tool-dir',type=Path,required=True)
    parser.add_argument('--unit-only',action='store_true',help='Only FFT numerical and independent raster tests')
    args=parser.parse_args();logs=[]
    try:
        asset=json.loads((ROOT/'assets/fft512_q15.json').read_text())
        assert asset['window']==WINDOW and asset['twiddle']==list(map(list,TWIDDLE))
        cases=vectors();numerical_checks(cases)
        with tempfile.TemporaryDirectory(prefix='fft_spectrum_') as directory:
            temp=Path(directory)
            (temp/'samples.hex').write_text(''.join(f'{s&65535:04x}\n' for case in cases for s in case),encoding='ascii')
            (temp/'bins.hex').write_text(''.join(f'{r&65535:04x}{i&65535:04x}\n' for case in cases for r,i in transform(case)),encoding='ascii')
            history=[0]*32;frames=[]
            for case in cases:
                history=[max(level,max(0,old-2)) for level,old in zip(heights(transform(case)),history)]
                frames.extend(history)
            (temp/'heights.hex').write_text(''.join(f'{v:02x}\n' for v in frames),encoding='ascii')
            sources=[ROOT/'rtl/audio_fft_coeff_rom.v',ROOT/'rtl/audio_fft_memory.v',ROOT/'rtl/audio_fft512.v']
            run('tb_fft','tb_fft.sv',sources,temp,args.tool_dir,logs)
            run('tb_spectrum','tb_spectrum.sv',sources+[ROOT/'rtl/video_audio_spectrum.v'],temp,args.tool_dir,logs)
            with Image.open(temp/'spectrum.ppm') as preview:preview.save(HERE/'spectrum.png')
            if args.unit_only:
                print('PASS V03 FFT core and transparent-background raster units');return
            # Frozen V02 isolates changes to the new visual path and its latency.
            old=(ROOT/'reports/v03_spectrum_20261020/before/worktree/rtl/hdmi_av_output.v').read_text(encoding='utf-8-sig')
            reference=temp/'reference.v';reference.write_text(re.sub(r'\bhdmi_av_output\b','hdmi_av_output_v02',old),encoding='utf-8')
            all_sources=[p for p in (ROOT/'rtl').glob('*.v') if p.name!='board_pll.v']
            def av_case(params):
                directory=temp/f'av_{params["ENABLE"]}_{params["DIM"]}';directory.mkdir()
                run('tb_spectrum_av','tb_spectrum_av.sv',all_sources+[reference],directory,args.tool_dir,logs,params)
            with ThreadPoolExecutor(max_workers=3) as workers:
                list(workers.map(av_case,[{'ENABLE':0,'DIM':0},{'ENABLE':1,'DIM':0},{'ENABLE':1,'DIM':1}]))
            spec=importlib.util.spec_from_file_location('menu_oracle',ROOT/'tests/chinese_settings/verify.py')
            menu=importlib.util.module_from_spec(spec);spec.loader.exec_module(menu)
            glyphs={g['character']:g['rows'] for g in json.loads((ROOT/'assets/settings_v03.json').read_text(encoding='utf-8'))['glyphs']}
            (temp/'ui_states.hex').write_text('\n'.join(f'{(menu.words(s)[1]<<11)|menu.words(s)[0]:04x}' for s in menu.STATES)+'\n',encoding='ascii')
            for index,state in enumerate(menu.STATES):
                values,_=menu.reference_frame(state,glyphs,spectrum=True)
                (temp/f'menu_golden_{index}.hex').write_text(''.join(f'{v:07x}\n' for v in values),encoding='ascii')
            run('tb_chinese_settings',ROOT/'tests/chinese_settings/tb_settings.sv',all_sources,temp,args.tool_dir,logs,{'SPECTRUM':1})
            with Image.open(temp/'menu_default.ppm') as preview:preview.save(HERE/'menu_spectrum.png')
        print('PASS V03 FFT numerical and overlay acceptance')
    finally:
        (HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')


if __name__=='__main__':main()
