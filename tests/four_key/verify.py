"""Four-key integration: navigation, shared debounce and independent menu pixels."""
import argparse,hashlib,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--tool-dir',type=Path,required=True)
 tools=parser.parse_args().tool_dir.resolve();logs=[]
 sources=[ROOT/'rtl'/n for n in ['media_playlist_control.v','board_key.v','video_scroll_osd.v']]
 hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in (ROOT/'rtl').glob('*.v')}
 av=[ROOT/'rtl'/n for n in ['hdmi_av_output.v','video_scroll_osd.v','video_brightness_lut.v','video_audio_waveform.v','audio_tone_bank.v','audio_async_fifo.v','hdmi_audio_packets.v','hdmi_bch8.v','hdmi_terc4.v','hdmi_data_island_encoder.v','tmds_encoder.v','tmds_channels.v']]
 cases=[('tb_navigation',sources[:1],{}),*[( 'tb_shared_debounce',sources[1:2],{'COUNT':n}) for n in [1,2,3,7,8,9,32,1000000]],('tb_settings_osd',sources[2:],{}),('tb_menu_hdmi',av,{})]
 try:
  with tempfile.TemporaryDirectory(prefix='four_key_') as tmp:
   tmp=Path(tmp)
   for top,rtl,params in cases:
    image=tmp/'check.vvp'
    commands=[[tools/'iverilog.exe','-g2012','-s',top,*[f'-P{top}.{k}={v}' for k,v in params.items()],'-o',image,*rtl,HERE/(top+'.sv')],[tools/'vvp.exe',image]]
    for i,command in enumerate(commands):
     result=subprocess.run(list(map(str,command)),cwd=tmp,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
     log=result.stdout+result.stderr;logs.append(log);print(log,end='',flush=True)
     assert result.returncode==0 and 'FATAL' not in log,top
     if i==1:assert 'PASS' in log,top
   preview=tmp/'settings_preview.ppm'
   assert preview.is_file();(HERE/'settings_preview.ppm').write_bytes(preview.read_bytes())
  for p,d in hashes.items():assert hashlib.sha256(Path(p).read_bytes()).hexdigest()==d,p
  print(f'PASS four-key integration: {len(cases)} simulations; RTL unchanged during testing')
 finally:(HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')

if __name__=='__main__':main()
