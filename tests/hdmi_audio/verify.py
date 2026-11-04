"""48 kHz 测试音到三路 TMDS 符号的三帧端到端仿真。"""
from pathlib import Path
import argparse
import subprocess
p=argparse.ArgumentParser()
p.add_argument('--tool-dir',type=Path,required=True)
a=p.parse_args()
d=Path(__file__).resolve().parent
b=d.parents[1]
t=a.tool_dir.resolve()
rtl=['audio_tone_bank.v','audio_async_fifo.v','hdmi_audio_packets.v',
     'hdmi_av_output.v','video_brightness_lut.v','video_audio_waveform.v','video_scroll_osd.v','hdmi_bch8.v','hdmi_terc4.v',
     'hdmi_data_island_encoder.v','tmds_encoder.v','tmds_channels.v']
commands=[[t/'iverilog.exe','-g2012','-s','tb_hdmi_audio_pacing','-o',d/'pacing.vvp',
           b/'rtl/hdmi_audio_packets.v',d/'tb_hdmi_audio_pacing.sv'],
          [t/'vvp.exe',d/'pacing.vvp'],
          [t/'iverilog.exe','-g2012','-s','tb_wav_pause','-o',d/'pause.vvp',
           *[b/'rtl'/x for x in rtl],d/'tb_wav_pause.sv'],
          [t/'vvp.exe',d/'pause.vvp'],
          [t/'iverilog.exe','-g2012','-s','tb_video_boundary','-o',d/'video.vvp',
           *[b/'rtl'/x for x in rtl],d/'tb_video_boundary.sv'],
          [t/'vvp.exe',d/'video.vvp'],
          [t/'iverilog.exe','-g2012','-s','tb_av_first_frame','-o',d/'first_frame.vvp',
           *[b/'rtl'/x for x in rtl],d/'tb_av_first_frame.sv'],
          [t/'vvp.exe',d/'first_frame.vvp'],
          [t/'iverilog.exe','-g2012','-s','tb_hdmi_av_output','-o',d/'av.vvp',
           *[b/'rtl'/x for x in rtl],d/'tb_hdmi_av_output.sv'],
          [t/'vvp.exe',d/'av.vvp'],
          [t/'iverilog.exe','-g2012','-s','tb_av_status_fallback','-o',d/'status.vvp',
           *[b/'rtl'/x for x in rtl],d/'tb_av_status_fallback.sv'],
          [t/'vvp.exe',d/'status.vvp']]
logs=[]
try:
    for cmd in commands:
        r=subprocess.run(list(map(str,cmd)),cwd=d,capture_output=True,text=True,timeout=600)
        out=r.stdout+r.stderr
        print(out,end='',flush=True)
        logs.append(out)
        if r.returncode or 'FATAL' in out:
            raise RuntimeError('AV simulation failed')
finally:
    (b/'reports/hdmi_av_simulation.txt').write_text(''.join(logs),encoding='utf-8')
    for name in ('pacing.vvp','pause.vvp','video.vvp','first_frame.vvp','av.vvp','status.vvp'):
        (d/name).unlink(missing_ok=True)
