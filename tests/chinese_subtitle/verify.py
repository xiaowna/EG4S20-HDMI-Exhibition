"""V01 pixel oracle, clipping/scroll wrap, and production HDMI timing comparison."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir',type=Path,required=True)
    args=parser.parse_args()
    manifest=json.loads((ROOT/'assets/subtitle_v01.json').read_text(encoding='utf-8'))
    if manifest['text']!='仰望星空，探索宇宙，逐梦星河': raise RuntimeError('Wrong subtitle text')
    golden=[]
    for glyph in manifest['glyphs']:
        fill=[[int(c) for c in row] for row in glyph['rows']]
        for y in range(16):
            for x in range(16):
                neighbours=[fill[yy][xx] for yy in range(max(0,y-1),min(16,y+2))
                            for xx in range(max(0,x-1),min(16,x+2))]
                golden.append(2 if fill[y][x] else int(any(neighbours)))
    golden += [0]*(4096-len(golden))
    logs=[]
    try:
        with tempfile.TemporaryDirectory(prefix='chinese_subtitle_') as temporary:
            temp=Path(temporary)
            (temp/'font_golden.hex').write_text('\n'.join(map(str,golden))+'\n',encoding='ascii')
            reference=ROOT/'reports/v01_subtitle_20261019/before/worktree/rtl/hdmi_av_output.v'
            if not reference.is_file(): raise RuntimeError('Missing frozen pre-V01 AV reference')
            old=temp/'reference.v'
            old.write_text(re.sub(r'\bhdmi_av_output\b','hdmi_av_output_reference',reference.read_text(encoding='utf-8-sig')),encoding='utf-8')
            for top in ['tb_subtitle_rom','tb_subtitle','tb_subtitle_av']:
                print('RUN '+top,flush=True)
                bench=HERE/('tb_subtitle_av.sv' if top=='tb_subtitle_av' else 'tb_subtitle.sv')
                sources=[p for p in (ROOT/'rtl').glob('*.v') if p.name!='board_pll.v']+[old,bench]
                for cmd in [[args.tool_dir/'iverilog.exe','-g2012','-s',top,'-o',temp/'check.vvp',*sources],
                            [args.tool_dir/'vvp.exe',temp/'check.vvp']]:
                    # The AV comparison advances both full implementations
                    # through real 48kHz prefill and a complete active frame.
                    # Allow slower Windows hosts without reducing coverage.
                    result=subprocess.run(list(map(str,cmd)),cwd=temp,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=600)
                    output=result.stdout+result.stderr
                    print(output,end='',flush=True);logs.append(top+'\n'+output)
                    if result.returncode or 'FATAL' in output: raise RuntimeError(top+' failed')
            with Image.open(temp/'subtitle_frame.ppm') as image:
                image.save(HERE/'subtitle_frame.png')
                image.crop((0,0,640,32)).save(HERE/'subtitle_crop.png')
        print('PASS V01 Chinese subtitle software acceptance')
    finally:
        (HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')


if __name__=='__main__': main()
