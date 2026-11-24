"""L01: independent pixels, accepted-write counts, board stages and HDMI alignment."""
from pathlib import Path
import argparse,hashlib,json,random,subprocess,tempfile,threading,re
from PIL import Image
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent

def pixel(x,y,stage,units,phase):
 card=160<=x<480 and 440<=y<472 and (164<=x<476 or 444<=y<468)
 color=0x162737;failed=stage==6;done=stage==7
 if card and (x<162 or x>=478 or y<442 or y>=470):color=0x86534f if failed else 0x3b5363
 if 446<=y<449 and 304<=x<336 and x%8<4:
  color=0xe5a89b if failed else (0xb6e7d7 if done or (x//8)%4==(phase//16)%4 else 0x3b5363)
 if 170<=x<470 and 454<=y<462:
  fill=300 if done else min(units,74)*4
  sweep=(127-phase%128 if phase>=128 else phase%128)*2
  lit=done or (x-170<fill if stage==3 else not failed and sweep<=x-170<sweep+48)
  color=0x86534f if failed else (0x70d6bc if lit else 0x243b47)
  if lit and y==454 and not failed:color=0xb6e7d7
 return (int(stage!=0 and card)<<24)|color

def simulation_rom_source(path,tmp):
 # Icarus repeatedly pushes the entire 98304-bit constant in the original
 # initialization loop. Fold the per-bank constant before that loop, keeping
 # every address, RAM word, clocked read and bank selector identical.
 source=path.read_text(encoding='utf-8-sig')
 old='initial for(i=0;i<4096;i=i+1)memory[i]=DATA[b*8192+i*2+:2];'
 match=re.search(r'localparam \[(\d+):0\] DATA=\{(.*?)\};',source,re.S)
 total=int(match[1])+1;literal=match[2];banks=total//8192
 value=0
 for width,digits in re.findall(r"(\d+)'h([0-9a-fA-F]+)",literal):
  width=int(width);chunk=int(digits,16);assert chunk.bit_length()<=width
  value=(value<<width)|chunk
 assert value.bit_length()<=total
 for bank in range(banks):
  bank_value=(value>>(bank*8192))&((1<<8192)-1)
  for address in range(4096):assert ((value>>(bank*8192+address*2))&3)==((bank_value>>(address*2))&3)
 if old in source:
  new='localparam [8191:0] BANK_DATA=DATA[b*8192+:8192];\n  initial for(i=0;i<4096;i=i+1)memory[i]=BANK_DATA[i*2+:2];'
  generated=tmp/'simulation_home_assets_rom.v';generated.write_text(source.replace(old,new),encoding='utf-8')
 else:
  assert 'memory[i]=BANK_DATA[i*2+:2]' in source
  generated=path
 return generated,{'kind':'native_or_equivalent_initialization','original_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'generated_sha256':hashlib.sha256(generated.read_bytes()).hexdigest(),'native_words_checked':banks*4096,'bits_checked':total,'production_rtl_modified':False}

def main():
 p=argparse.ArgumentParser();p.add_argument('--tool-dir',type=Path,required=True);p.add_argument('--compile-only',action='store_true');a=p.parse_args()
 board=['rtc_ds1302.v','rtc_set_control.v','hdmi_media_board_top.v','board_key.v','media_control_events.v','media_rotary_encoder.v','media_nec_receiver.v','media_infrared_control.v','media_mode_control.v','media_adjust_control.v','board_matrix_keys.v','media_home_control.v','media_help_control.v','home_album_config.v','media_3d_control.v']
 av=['hdmi_av_output.v','video_prepare_overlay.v','video_brightness_lut.v','video_scroll_osd.v','video_audio_waveform.v','video_chinese_subtitle.v','subtitle_font_rom.v','video_chinese_settings.v','settings_font_rom.v','video_home.v','home_assets_rom.v','audio_source_flush.v','audio_tone_bank.v','audio_async_fifo.v','hdmi_audio_packets.v','hdmi_bch8.v','hdmi_terc4.v','hdmi_data_island_encoder.v','tmds_encoder.v','tmds_channels.v']
 jobs=[('tb_prepare_pixels',['video_prepare_overlay.v'],['tb_pixels.sv']),('tb_prepare_count',['frame_buffer_manager.v'],['tb_count.sv']),('tb_prepare_board',board,['tb_board.sv',ROOT/'tests/dmz_media/tb_hdmi_media_board_top.sv',ROOT/'tests/dmz_media/dmz_keyboard_model.sv']),('tb_prepare_av',av,['tb_av.sv'])]
 logs=[];cases=[];inputs=set();vectors=0;rom_equivalence=None
 live=HERE/'regression.log'
 if not a.compile_only:
  live.write_text('L01 simulation running; only the final summary confirms success.\n',encoding='utf-8')
  (HERE/'regression_summary.json').write_text(json.dumps({'status':'running','simulation_run':True}),encoding='utf-8')
 with tempfile.TemporaryDirectory(prefix='l01_prepare_') as folder:
  tmp=Path(folder)
  if not a.compile_only:
   rng=random.Random(45830)
   with (tmp/'pixels.txt').open('w',encoding='ascii') as f:
    for stage in range(1,8):
     for phase in [4,64,128,252]:
      for units in ([0,1,37,74,75,127] if stage==3 else [0]):
       word=stage*128+units
       # Exhaust the entire panel plus its border and one random off-panel sample.
       for y in range(438,474):
        for x in range(158,482):
         f.write(f'{x} {y} {word:x} {phase} {pixel(x,y,stage,units,phase):07x}\n');vectors+=1
       x,y=rng.randrange(640),rng.randrange(440)
       f.write(f'{x} {y} {word:x} {phase} {pixel(x,y,stage,units,phase):07x}\n');vectors+=1
   (tmp/'av_pixels.hex').write_text(''.join(f'{pixel(x,y,3,37,4):07x}\n' for y in range(480) for x in range(640)),encoding='ascii')
   preview=Image.new('RGB',(640,480),(18,26,32));data=preview.load()
   for y in range(480):
    for x in range(640):
     v=pixel(x,y,3,37,4)
     if v>>24:data[x,y]=((v>>16)&255,(v>>8)&255,v&255)
   preview.save(HERE/'preview.png')
  for top,names,benches in jobs:
   sources=[ROOT/'rtl'/n for n in names]+[HERE/b if isinstance(b,str) else b for b in benches];inputs.update(sources)
   compiled=sources
   if top=='tb_prepare_av':
    rom_path,rom_equivalence=simulation_rom_source(ROOT/'rtl/home_assets_rom.v',tmp)
    compiled=[rom_path if p==ROOT/'rtl/home_assets_rom.v' else p for p in sources]
    print('PROGRESS ROM initialization equivalence:',rom_equivalence['bits_checked'],'bits checked',flush=True)
   cmd=[a.tool_dir/'iverilog.exe','-g2012','-s',top,'-o',tmp/(top+'.vvp'),*compiled]
   r=subprocess.run(list(map(str,cmd)),cwd=tmp,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=120)
   logs.append(r.stdout+r.stderr);assert r.returncode==0,logs[-1]
   if not a.compile_only:
    output=[]
    with subprocess.Popen([str(a.tool_dir/'vvp.exe'),'-i',str(tmp/(top+'.vvp'))],cwd=tmp,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',bufsize=1) as process:
     def read_output():
      for line in process.stdout:
       output.append(line);print(line,end='',flush=True)
       with live.open('a',encoding='utf-8') as f:f.write(line)
     reader=threading.Thread(target=read_output);reader.start()
     try:process.wait(timeout=900)
     except subprocess.TimeoutExpired:
      process.kill();process.wait();reader.join()
      (HERE/'regression_summary.json').write_text(json.dumps({'status':'failed_timeout','case':top,'simulation_run':True}),encoding='utf-8')
      raise
     reader.join()
    logs.append(''.join(output));assert process.returncode==0 and 'FATAL' not in logs[-1] and 'PASS ' in logs[-1],logs[-1]
   cases.append(top);print(('COMPILED ' if a.compile_only else 'CHECKED ')+top,flush=True)
 summary={'status':'compiled_only' if a.compile_only else 'passed','cases':cases,'pixel_vectors':vectors,'source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(inputs|{Path(__file__).resolve()})},'hardware_tested':False,'simulation_run':not a.compile_only,'home_rom_initialization':rom_equivalence}
 suffix='compile' if a.compile_only else 'regression'
 (HERE/(suffix+'.log')).write_text(''.join(logs),encoding='utf-8')
 (HERE/(suffix+'_summary.json')).write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':main()
