"""Background cache acceptance: real buffer, sector/raster pipeline and fade acknowledgement."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir',type=Path,required=True)
    args=parser.parse_args();tools=args.tool_dir.resolve()
    rtl=[ROOT/'rtl'/p.strip() for p in (ROOT/'sources.txt').read_text().splitlines() if p.strip()]
    rtl += [ROOT/'tests/clock_buffer_model.v',ROOT/'tests/em638325_model.sv']
    hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in rtl}
    hashes.update({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in HERE.glob('*.sv')})
    logs=[];runs=[]
    def run(command,cwd):
        result=subprocess.run(list(map(str,command)),cwd=cwd,capture_output=True,
            text=True,encoding='utf-8',errors='replace',timeout=180)
        output=result.stdout+result.stderr;logs.append(output);print(output,end='',flush=True)
        if result.returncode or 'FATAL' in output:raise RuntimeError('cache regression failed')
        return output
    try:
        with tempfile.TemporaryDirectory(prefix='next_prefetch_') as directory:
            directory=Path(directory)
            for n in range(1,5):
                image=directory/'control.vvp'
                run([tools/'iverilog.exe','-g2012','-s','tb_prefetch_control',f'-Ptb_prefetch_control.COUNT={n}',
                     '-o',image,*rtl,HERE/'tb_control.sv'],ROOT/'tests')
                output=run([tools/'vvp.exe',image],ROOT/'tests')
                assert 'PASS next-cache control' in output
                runs.append({'case':'control','count':n,'metrics':dict(re.findall(r'(\w+)=(\d+)',output))})
            run([tools/'iverilog.exe','-g2012','-s','tb_prefetch_control','-Ptb_prefetch_control.FAST=1',
                 '-o',image,*rtl,HERE/'tb_control.sv'],ROOT/'tests')
            output=run([tools/'vvp.exe',image],ROOT/'tests')
            assert 'PASS fast gallery:' in output
            runs.append({'case':'fast_manual','output':output.strip()})
            for legacy,bad in [(1,0),(0,0),(0,1)]:
                image=directory/'pipeline.vvp'
                run([tools/'iverilog.exe','-g2012','-s','tb_prefetch_pipeline',
                     f'-Ptb_prefetch_pipeline.LEGACY={legacy}',f'-Ptb_prefetch_pipeline.BAD={bad}',
                     '-o',image,*rtl,HERE/'tb_pipeline.sv'],ROOT/'tests')
                output=run([tools/'vvp.exe',image],ROOT/'tests')
                assert 'PASS next-cache pipeline' in output
                runs.append({'case':'pipeline','legacy':legacy,'bad':bad,'metrics':dict(re.findall(r'(\w+)=(\d+)',output))})
            av=[ROOT/'rtl'/n for n in ['hdmi_av_output.v','audio_tone_bank.v','audio_async_fifo.v',
                'video_brightness_lut.v','video_audio_waveform.v','video_scroll_osd.v','hdmi_audio_packets.v',
                'hdmi_bch8.v','hdmi_terc4.v','hdmi_data_island_encoder.v','tmds_encoder.v','tmds_channels.v']]
            hashes.update({str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in av})
            image=directory/'fade.vvp'
            run([tools/'iverilog.exe','-g2012','-s','tb_prefetch_fade','-o',image,*av,HERE/'tb_fade.sv'],ROOT/'tests')
            output=run([tools/'vvp.exe',image],ROOT/'tests')
            assert 'PASS next-cache fade:' in output
            runs.append({'case':'fade','metrics':dict(re.findall(r'(\w+)=(\d+)',output))})
        for p,h in hashes.items():assert hashlib.sha256(Path(p).read_bytes()).hexdigest()==h,p
        summary={'passed':True,'runs':runs,'source_sha256':hashes}
        (HERE/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
        print('PASS next-cache acceptance: all requested cases passed; production source hashes unchanged')
    finally:(HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')

if __name__=='__main__':main()
