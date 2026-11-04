from pathlib import Path
import argparse, subprocess, tempfile
p=argparse.ArgumentParser();p.add_argument('--tool-dir',type=Path,required=True);a=p.parse_args()
b=Path(__file__).resolve().parents[1];t=a.tool_dir
av=['audio_tone_bank.v','audio_async_fifo.v','hdmi_audio_packets.v','hdmi_av_output.v','video_brightness_lut.v','video_audio_waveform.v','video_scroll_osd.v','hdmi_bch8.v','hdmi_terc4.v','hdmi_data_island_encoder.v','tmds_encoder.v','tmds_channels.v']
core=[b/'rtl'/n for n in (b/'sources.txt').read_text().splitlines()]+[b/'tests/clock_buffer_model.v',b/'tests/em638325_model.sv']
checks=[('tb_av_audio_only',[b/'rtl'/n for n in av],b/'tests/hdmi_audio/tb_av_audio_only.sv'),('tb_av_status_fallback',[b/'rtl'/n for n in av],b/'tests/hdmi_audio/tb_av_status_fallback.sv'),('tb_display_status',core,b/'tests/tb_display_status.sv')]
logs=[]
with tempfile.TemporaryDirectory() as tmp:
 for top,rtl,tb in checks:
  v=Path(tmp)/'test.vvp'
  subprocess.run(list(map(str,[t/'iverilog.exe','-g2012','-s',top,'-o',v,*rtl,tb])),check=True,timeout=30)
  r=subprocess.run([str(t/'vvp.exe'),str(v)],capture_output=True,text=True,timeout=60)
  logs.append(r.stdout+r.stderr);print(logs[-1],end='');r.check_returncode()
(b/'reports/review_fixes_regression.txt').write_text(''.join(logs),encoding='utf-8')
