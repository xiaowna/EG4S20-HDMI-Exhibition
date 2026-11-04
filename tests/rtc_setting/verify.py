from pathlib import Path
import argparse,calendar,hashlib,json,random,subprocess,tempfile
from PIL import Image
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent

def main():
 p=argparse.ArgumentParser();p.add_argument('--tool-dir',type=Path,required=True);a=p.parse_args()
 records=[];logs=[]
 files=list(HERE.glob('*.sv'))+[HERE/'verify.py']+list((ROOT/'rtl').glob('*.v'))+[ROOT/'assets/settings_v04.json',
  ROOT/'assets/settings_v03.json',ROOT/'tests/dmz_media/tb_hdmi_media_board_top.sv',ROOT/'tests/dmz_media/dmz_keyboard_model.sv']
 hashes={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
 cases=[('tb_rtc_write',['rtc_ds3231.v'],['ds3231_write_model.sv','tb_write.sv'],{'QUARTER':5}),
        ('tb_rtc_write',['rtc_ds3231.v'],['ds3231_write_model.sv','tb_write.sv'],{'QUARTER':125}),
        ('tb_rtc_editor',['rtc_set_control.v'],['tb_editor.sv'],{}),
        ('tb_rtc_set_menu',['video_chinese_settings.v','settings_font_rom.v'],['tb_menu.sv'],{}),
        ('tb_rtc_setting_board',['rtc_ds1302.v','rtc_set_control.v','hdmi_media_board_top.v','board_key.v',
          'media_control_events.v','media_rotary_encoder.v','media_nec_receiver.v','media_infrared_control.v',
          'media_mode_control.v','media_adjust_control.v','board_matrix_keys.v'],
         ['../rtc_ds1302/ds1302_model.sv','tb_board.sv'],{})]
 try:
  with tempfile.TemporaryDirectory(prefix='rtc_setting_') as folder:
   tmp=Path(folder)
   rows=[]
   def encoded(v):return ''.join(f'{n:02d}' for n in v)
   for year in range(100):
    for month in range(1,13):
     for day in [1,calendar.monthrange(2000+year,month)[1]]:
      for field in range(6):
       for direction in range(2):
        base=[year,month,day,23 if direction else 0,59 if direction else 0,59 if direction else 0]
        expect=base[:];low=[0,1,1,0,0,0][field]
        high=[99,12,calendar.monthrange(2000+year,month)[1],23,59,59][field]
        expect[field]=low if direction and base[field]==high else (high if not direction and base[field]==low else base[field]+(1 if direction else -1))
        expect[2]=min(expect[2],calendar.monthrange(2000+expect[0],expect[1])[1])
        rows.append(f'{encoded(base)} {field} {direction} {encoded(expect)}\n')
   rng=random.Random(45830)
   for _ in range(4096):
    year=rng.randrange(100);month=rng.randrange(1,13)
    base=[year,month,rng.randrange(1,calendar.monthrange(2000+year,month)[1]+1),rng.randrange(24),rng.randrange(60),rng.randrange(60)]
    field=rng.randrange(6);direction=rng.randrange(2);expect=base[:]
    low=[0,1,1,0,0,0][field]
    high=[99,12,calendar.monthrange(2000+year,month)[1],23,59,59][field]
    expect[field]=low if direction and base[field]==high else (high if not direction and base[field]==low else base[field]+(1 if direction else -1))
    expect[2]=min(expect[2],calendar.monthrange(2000+expect[0],expect[1])[1])
    rows.append(f'{encoded(base)} {field} {direction} {encoded(expect)}\n')
   (tmp/'edit_vectors.txt').write_text(''.join(rows),encoding='ascii')
   font=json.loads((ROOT/'assets/settings_v04.json').read_text(encoding='utf-8'))
   old=json.loads((ROOT/'assets/settings_v03.json').read_text(encoding='utf-8'))
   assert font['glyphs'][:63]==old['glyphs'] and not any('1' in r for r in font['glyphs'][63]['rows'])
   bits=[c for g in font['glyphs'] for row in g['rows'] for c in row];bits+=['0']*(32768-len(bits))
   (tmp/'clock_font.hex').write_text('\n'.join(bits)+'\n',encoding='ascii')
   ids={g['character']:i for i,g in enumerate(font['glyphs'])}
   labels='时间设置2026-10-2112:34:56保存返回写入成功失败'
   (tmp/'clock_labels.hex').write_text(''.join(f'{ids[c]:x}\n' for c in labels)+'0\n'*(48-len(labels)),encoding='ascii')
   for top,rtl,benches,params in cases:
    output=''
    extra=[ROOT/'tests/dmz_media/tb_hdmi_media_board_top.sv',ROOT/'tests/dmz_media/dmz_keyboard_model.sv'] if top=='tb_rtc_setting_board' else []
    for cmd in [[a.tool_dir/'iverilog.exe','-g2012','-s',top,*[f'-P{top}.{k}={v}' for k,v in params.items()],
                 '-o',tmp/'test.vvp',*[ROOT/'rtl'/n for n in rtl],*[HERE/n for n in benches],*extra],
                [a.tool_dir/'vvp.exe',tmp/'test.vvp']]:
     r=subprocess.run(list(map(str,cmd)),cwd=tmp,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=300)
     output+=r.stdout+r.stderr
     assert r.returncode==0 and 'FATAL' not in output,output
    assert 'PASS ' in output,output
    print(output,end='',flush=True);logs.append(output);records.append({'top':top,'parameters':params,'passed':True})
   with Image.open(tmp/'clock_menu.ppm') as image:image.save(HERE/'clock_menu.png')
  assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in hashes.items())
  (HERE/'summary.json').write_text(json.dumps({'status':'passed','cases':records,'inputs_sha256':hashes,'hardware_tested':False},indent=2)+'\n',encoding='utf-8')
 finally:(HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')
if __name__=='__main__':main()
