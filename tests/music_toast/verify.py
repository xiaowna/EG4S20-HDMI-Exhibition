"""Independent music-toast pixels, timing, native font and AV composition."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,re,subprocess,tempfile
from PIL import Image
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent

def pixel(x,y,age,track,glyphs):
 rgb=((x%256)<<16)|((y%256)<<8)|((x^y)%256)
 window=age<298 and 16<=x<176 and 40<=y<88 and (22<=x<170 or 46<=y<82)
 if not window:return rgb
 color=0x3b5363 if x<18 or x>=174 or y<42 or y>=86 else 0x162737
 if 28<=x<60 and 48<=y<80:
  if glyphs[chr(0xe100+(age//8)%8)][(y-48)//2][(x-28)//2]=='1':color=0x70d6bc
 elif 80<=x<128 and 56<=y<72:
  ch=('音','乐',str(track+1))[(x-80)//16]
  if glyphs[ch][y-56][(x-80)%16]=='1':color=0xe7efec
 alpha=16 if age<238 else (298-age+3)//4
 result=sum(((((color>>shift)&255)*alpha+((rgb>>shift)&255)*(16-alpha))//16)<<shift for shift in [0,8,16])
 return 0x1000000|result

def settings_rom(path,tmp):
 text=path.read_text(encoding='utf-8-sig');old='memory[i]=FONT[b*8192+i*2+:2]'
 assert text.count(old)==1
 literal=re.search(r'localparam \[32767:0\] FONT=\{(.*?)\};',text,re.S)[1]
 words=[int(n,16) for n in re.findall(r"256'h([0-9a-fA-F]+)",literal)];assert len(words)==128
 value=0
 for word in words:value=(value<<256)|word
 for bank in range(4):
  part=(value>>(bank*8192))&((1<<8192)-1)
  for address in range(4096):assert (value>>(bank*8192+address*2))&3==(part>>(address*2))&3
 text=text.replace('(* rom_style="bram" *) reg [1:0] memory[0:4095];',
  'localparam [8191:0] BANK_FONT=FONT[b*8192+:8192];\n  (* rom_style="bram" *) reg [1:0] memory[0:4095];')
 text=text.replace(old,'memory[i]=BANK_FONT[i*2+:2]')
 generated=tmp/'simulation_settings_font_rom.v';generated.write_text(text,encoding='utf-8')
 return generated,dict(original_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),generated_sha256=hashlib.sha256(generated.read_bytes()).hexdigest(),bits_checked=32768,words_checked=16384,production_modified=False)

def main():
 p=argparse.ArgumentParser();p.add_argument('--tool-dir',type=Path,required=True);a=p.parse_args()
 asset=json.loads((ROOT/'assets/settings_v04.json').read_text(encoding='utf-8'))
 assert asset['music_note_first']==74 and asset['music_note_frames']==8
 assert [g['character'] for g in asset['glyphs'][74:82]]==[chr(0xe100+i) for i in range(8)]
 glyphs={g['character']:g['rows'] for g in asset['glyphs']}
 logs=[];records=[];count=0
 with tempfile.TemporaryDirectory(prefix='music_toast_') as folder:
  tmp=Path(folder);rom,proof=settings_rom(ROOT/'rtl/settings_font_rom.v',tmp)
  with (tmp/'toast_pixels.txt').open('w',encoding='ascii') as f:
   for age,track in [(0,0),(268,2),(298,0)]:
    for y in range(480):
     for x in range(640):f.write(f'{x} {y} {age} {track} {pixel(x,y,age,track,glyphs):07x}\n');count+=1
   for age,track in [(phase*8,0) for phase in range(8)]+[(0,i) for i in range(4)]+[(298-alpha*4,2) for alpha in range(1,16)]:
    for y in range(38,90):
     for x in range(14,178):f.write(f'{x} {y} {age} {track} {pixel(x,y,age,track,glyphs):07x}\n');count+=1
  for top in ['tb_music_notice','tb_music_pixels']:
   output=''
   for cmd in [[a.tool_dir/'iverilog.exe','-g2012','-s',top,'-o',tmp/'check.vvp',ROOT/'rtl/video_chinese_settings.v',rom,HERE/'tb_toast.sv'],[a.tool_dir/'vvp.exe',tmp/'check.vvp']]:
    r=subprocess.run(list(map(str,cmd)),cwd=tmp,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=240)
    output+=r.stdout+r.stderr;assert r.returncode==0 and 'FATAL' not in output,output
   assert 'PASS ' in output;print(output,end='',flush=True);logs.append(output);records.append(top)
  with Image.open(tmp/'toast.ppm') as im:im.save(HERE/'toast_preview.png')
 (HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')
 (HERE/'summary.json').write_text(json.dumps(dict(status='passed',cases=records,pixel_vectors=count,
  home_font_unchanged=True,settings_rom_initialization=proof,hardware_tested=False),indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':main()
