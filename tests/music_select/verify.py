"""Four-song catalogue, safe selection, audio source identity and menu pixels."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,subprocess,tempfile
from PIL import Image
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--tool-dir',type=Path,required=True)
 a=p.parse_args();logs=[];records=[]
 inputs=list((ROOT/'rtl').glob('*.v'))+list(HERE.glob('*.sv'))+[ROOT/'assets/settings_v03.json',ROOT/'tests/chinese_settings/verify.py',ROOT/'tests/chinese_settings/tb_settings.sv']
 hashes={f.relative_to(ROOT).as_posix():hashlib.sha256(f.read_bytes()).hexdigest() for f in inputs}
 cases=[('tb_music_catalog',['fat32_dir_scan.v']),('tb_music_control',['media_mode_control.v','media_adjust_control.v']),('tb_music_audio',None)]
 def run(cmd,cwd):
  result=subprocess.run(list(map(str,cmd)),cwd=cwd,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=1200)
  out=result.stdout+result.stderr;logs.append(out);print(out,end='',flush=True)
  if result.returncode or 'FATAL' in out:raise RuntimeError('four-song test failed')
 try:
  with tempfile.TemporaryDirectory(prefix='music_select_') as tmp:
   tmp=Path(tmp)
   for top,names in cases:
    sources=[ROOT/'rtl'/n for n in names] if names else [p for p in (ROOT/'rtl').glob('*.v') if p.name not in ['board_pll.v','sd_subsystem.v']]+[ROOT/'tests/clock_buffer_model.v',ROOT/'tests/em638325_model.sv']
    run([a.tool_dir/'iverilog.exe','-g2012','-s',top,'-o',tmp/'check.vvp',*sources,HERE/(top.replace('music_','')+'.sv')],tmp)
    run([a.tool_dir/'vvp.exe',tmp/'check.vvp'],ROOT/'tests' if names is None else tmp)
    records.append(top)
   spec=importlib.util.spec_from_file_location('menu',ROOT/'tests/chinese_settings/verify.py')
   menu=importlib.util.module_from_spec(spec);spec.loader.exec_module(menu)
   glyphs={g['character']:g['rows'] for g in json.loads((ROOT/'assets/settings_v03.json').read_text(encoding='utf-8'))['glyphs']}
   states=[((1,0,2,2,0,1,1,0,0),(1,0,4,0)),((1,0,2,2,0,1,1,0,0),(1,3,4,2)),
    ((1,0,2,2,0,1,1,0,0),(1,0,0,0)),((1,0,2,2,0,1,0,0,1),(0,0,4,0)),
    ((0,0,2,2,0,1,1,0,0),(0,0,1,0))]
   encoded=[]
   for i,(state,music) in enumerate(states):
    values,_=menu.reference_frame(state,glyphs,spectrum=True,music=music)
    (tmp/f'menu_golden_{i}.hex').write_text(''.join(f'{v:07x}\n' for v in values),encoding='ascii')
    page,choice,count,playing=music;settings,mode=menu.words(state)
    encoded.append((((page<<7)|(choice<<5)|(count<<2)|playing)<<15)|(mode<<11)|settings)
   (tmp/'ui_states.hex').write_text(''.join(f'{v:06x}\n' for v in encoded),encoding='ascii')
   bench=(ROOT/'tests/chinese_settings/tb_settings.sv').read_text(encoding='utf-8-sig')
   bench=bench.replace('reg [14:0] states[0:8];','reg [22:0] states[0:4];reg [7:0] music_status;')
   bench=bench.replace('f<9','f<5').replace('.SPECTRUM_FFT(SPECTRUM))','.SPECTRUM_FFT(SPECTRUM),.MUSIC_MENU(1))')
   bench=bench.replace('.mode_status(mode_status),','.mode_status(mode_status),.music_status(music_status),')
   bench=bench.replace('{mode_status,settings_word}=states[f]','{music_status,mode_status,settings_word}=states[f]')
   bench=bench.replace('settings_word=0;mode_status=~states[f][14:11];','settings_word=0;mode_status=~states[f][14:11];music_status=~states[f][22:15];')
   (tmp/'menu.sv').write_text(bench,encoding='utf-8')
   run([a.tool_dir/'iverilog.exe','-g2012','-s','tb_chinese_settings','-Ptb_chinese_settings.SPECTRUM=1','-o',tmp/'menu.vvp',ROOT/'rtl/video_chinese_settings.v',ROOT/'rtl/settings_font_rom.v',tmp/'menu.sv'],tmp)
   run([a.tool_dir/'vvp.exe',tmp/'menu.vvp'],tmp)
   with Image.open(tmp/'menu_default.ppm') as x:x.save(HERE/'music_menu.png')
   records.append('six_row_menu_1536000_independent_pixels_and_frame_atomicity')
  assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in hashes.items())
  (HERE/'summary.json').write_text(json.dumps({'status':'passed','cases':records,'inputs_sha256':hashes},indent=2)+'\n',encoding='utf-8')
 finally:(HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')

if __name__=='__main__':main()
