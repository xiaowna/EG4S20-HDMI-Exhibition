"""Independent full-frame intro pixel oracle and scanline producer regression."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import tempfile

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def expected_frame(metadata, topic, phase, bank, captions=False, intro=True, slide_offset=0, slide_right=False, slide_alpha=32):
    page=metadata['pages'][topic];ys,xs=np.indices((480,640),dtype=np.int64)
    addresses=bank*307200+ys*640+xs
    photo=ys<352
    if intro:
        sx,sy,sw,sh=page['source_photo_xywh'];g=page['phases'][phase]
        dx,dy,dw,dh=g['destination_xywh']
        photo=(xs>=dx)&(xs<dx+dw)&(ys>=dy)&(ys<dy+dh)
        addresses[photo]=bank*307200+(sy+(ys[photo]-dy)*sh//dh)*640+sx+(xs[photo]-dx)*sw//dw
    elif slide_offset:
        other=(1-bank)*307200
        if slide_right:
            first=photo&(xs<slide_offset);second=photo&~first
            addresses[first]=other+ys[first]*640+640-slide_offset+xs[first]
            addresses[second]=bank*307200+ys[second]*640+xs[second]-slide_offset
        else:
            first=photo&(xs<640-slide_offset);second=photo&~first
            addresses[first]=bank*307200+ys[first]*640+xs[first]+slide_offset
            addresses[second]=other+ys[second]*640+xs[second]-(640-slide_offset)
    colors=((addresses*37)^(addresses<<7)^0x5a39c7)&0xffffff
    colors[~photo]=0x060c14
    rgb=np.stack(((colors>>16)&255,(colors>>8)&255,colors&255),axis=-1)
    if captions:
        # Immediately visible, then cubic smoothstep over 12 retired frames.
        p=min(12,phase);step=(16*p*p*(36-2*p)+864)//1728
        a=32 if intro or slide_offset else 16+step
        top=352 if intro or slide_offset else 352+16-step
        effective=slide_alpha if slide_offset else a
        cap=(ys>=top)&(ys<416)&(xs>=18)&(xs<622)
        caddr=bank*307200+(384+ys[cap]-top)*640+xs[cap]
        crgb=((caddr*37)^(caddr<<7)^0x5a39c7)&0xffffff
        target=np.stack(((crgb>>16)&255,(crgb>>8)&255,crgb&255),axis=-1)
        rgb[cap]=(np.array([6,12,20])*(32-effective)+target*effective+16)//32
    words=metadata['glyph_words'];chars=metadata['character_words'];weights=[0,11,21,32]
    g=page['phases'][phase];alpha=g['text_alpha'] if intro else 0;left=352+g['text_offset']
    for y in range(101,272):
        ly=y-101
        for x in range(left,min(640,left+240)):
            lx=x-left;coverage=0;fg=page['accent']
            if lx<128 and ly<24:coverage=(words[7680+ly*16+lx//8]>>((lx%8)*2))&3
            elif lx<100 and 26<=ly<28:coverage=3
            elif ly>=36:
                row,gy=divmod(ly-36,23)
                if row<6 and gy<20:
                    glyph=chars[topic*128+row*15+lx//16]
                    coverage=(words[glyph*40+gy*2+(lx%16)//8]>>((lx%8)*2))&3;fg=(218,227,233)
            a=(weights[coverage]*alpha+16)//32
            rgb[y,x]=(rgb[y,x]*(32-a)+np.array(fg)*a+16)//32
    return ((rgb[:,:,0]<<16)|(rgb[:,:,1]<<8)|rgb[:,:,2]).reshape(-1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir', type=Path, required=True)
    parser.add_argument('--cases', type=int, default=16, choices=range(1, 17))
    args = parser.parse_args()
    metadata = json.loads((ROOT/'assets/intro_assets.json').read_text(encoding='utf-8'))
    sources = [ROOT/'rtl'/name for name in ('intro_assets_rom.v', 'intro_text_layer.v',
                'intro_line_store.v', 'frame_intro_prefetch.v')]
    sources += [HERE/'tb_producer.sv']
    inputs = {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in sources+[ROOT/'assets/intro_assets.json', HERE/'line_bram32k_model.sv', Path(__file__)]}
    logs = []
    def run(command, cwd):
        result = subprocess.run(list(map(str, command)), cwd=cwd, capture_output=True,
                                text=True, encoding='utf-8', errors='replace', timeout=1800)
        output = result.stdout+result.stderr
        logs.append(output)
        print(output, end='', flush=True)
        if result.returncode or 'FATAL' in output:
            raise RuntimeError('intro producer regression failed')
    try:
        with tempfile.TemporaryDirectory(prefix='intro_producer_') as temporary:
            temporary = Path(temporary)
            for number in range(args.cases):
                topic = number//4
                phase = [0, 37, 49, 63][number % 4]
                bank = (number//4+number % 4) % 2
                pixels = expected_frame(metadata, topic, phase, bank)
                (temporary/f'golden_{number}.hex').write_text(''.join(f'{int(pixel):06x}\n' for pixel in pixels), encoding='ascii')
            for native in (False, True):
                executable = temporary/f'producer_{int(native)}.vvp'
                command = [args.tool_dir/'iverilog.exe', '-g2012', '-s', 'tb_intro_producer', '-o', executable]
                if native:
                    command += ['-DINTRO_NATIVE_RAM', HERE/'line_bram32k_model.sv']
                run(command+sources, temporary)
                run([args.tool_dir/'vvp.exe', executable, f'+CASES={args.cases}'], temporary)
            for filename, original in inputs.items():
                assert hashlib.sha256((ROOT/filename).read_bytes()).hexdigest() == original, filename+' changed during test'
        (HERE/'producer_summary.json').write_text(json.dumps({
            'status': 'passed', 'frames_per_branch': args.cases,
            'pixels': args.cases*307200*2,
            'native_scanline_ports_tested': True,
            'malformed_last_backend_error_issue_receive_timeouts_and_reset_tested': True,
            'input_sha256': inputs}, indent=2)+'\n', encoding='utf-8')
    finally:
        (HERE/'producer_regression.log').write_text(''.join(logs), encoding='utf-8')


if __name__ == '__main__':
    main()
