"""DS3231 pin transactions, independent calendar oracle and transparent pixels."""
from pathlib import Path
import argparse, calendar, hashlib, json, subprocess, tempfile
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent

def valid(values):
    second,minute,hour,weekday,day,month,year,status=values
    def bcd(v):
        return v//16*10+v%16 if v//16<10 and v%16<10 else -1
    numbers=list(map(bcd,[second,minute,hour,day,month,year]))
    s,m,h,d,mo,y=numbers
    if not (0<=s<60 and 0<=m<60 and 0<=h<24 and 1<=weekday<=7 and
            1<=mo<=12 and 0<=y<=99 and 1<=d<=31 and status&128==0):
        return False
    return d<=calendar.monthrange(2000+y,mo)[1]

def row(values):
    s,m,h,w,d,mo,y,flags=values
    return f'{y:02x}{mo:02x}{d:02x}{h:02x}{m:02x}{s:02x} {w:02x} {flags:02x} {int(valid(values))}\n'

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--tool-dir',type=Path,required=True)
    args=p.parse_args();logs=[];records=[]
    files=[ROOT/'rtl'/n for n in ['rtc_ds3231.v','rtc_set_control.v','video_chinese_settings.v','settings_font_rom.v']]
    board_names=['rtc_set_control.v','hdmi_media_board_top.v','board_key.v','media_control_events.v','media_rotary_encoder.v',
                 'media_nec_receiver.v','media_infrared_control.v','media_mode_control.v','media_adjust_control.v','board_matrix_keys.v']
    board_sources=[ROOT/'rtl'/n for n in board_names]+[ROOT/'tests/dmz_media/tb_hdmi_media_board_top.sv',ROOT/'tests/dmz_media/dmz_keyboard_model.sv']
    av_sources=[p for p in (ROOT/'rtl').glob('*.v') if p.name!='board_pll.v']
    files+=list(HERE.glob('*.sv'))+[HERE/'verify.py',ROOT/'assets/settings_v03.json']+board_sources+av_sources
    inputs={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    def run(top,sources,tmp,params=None):
        output=''
        for cmd in [[args.tool_dir/'iverilog.exe','-g2012','-s',top,
                    *[f'-P{top}.{k}={v}' for k,v in (params or {}).items()],'-o',tmp/'test.vvp',*sources],
                    [args.tool_dir/'vvp.exe',tmp/'test.vvp']]:
            r=subprocess.run(list(map(str,cmd)),cwd=tmp,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=300)
            output+=r.stdout+r.stderr
            assert r.returncode==0 and 'FATAL' not in output,output
        assert 'PASS ' in output,output
        print(output,end='',flush=True);logs.append(output)
        records.append({'top':top,'parameters':params or {},'passed':True})
    try:
        with tempfile.TemporaryDirectory(prefix='rtc_acceptance_') as folder:
            tmp=Path(folder);base=[0x56,0x34,0x12,3,0x21,0x10,0x26,0]
            vectors=[base[:]]
            for field in range(8):
                for value in range(256):
                    v=base[:];v[field]=value;vectors.append(v)
            for year in range(100):
                for day in [28,29,30,31]:
                    v=base[:];v[6]=int(str(year),16);v[5]=2;v[4]=int(str(day),16);vectors.append(v)
            for month in range(1,13):
                for day in [0,28,29,30,31,32]:
                    v=base[:];v[5]=int(str(month),16);v[4]=int(str(day),16);vectors.append(v)
            (tmp/'vectors.txt').write_text(''.join(map(row,vectors)),encoding='ascii')
            run('tb_rtc',[ROOT/'rtl/rtc_ds3231.v',HERE/'ds3231_model.sv',HERE/'tb_rtc.sv'],tmp,{'QUARTER':5})
            records[-1]['calendar_vectors']=len(vectors)
            (tmp/'vectors.txt').write_text(''.join(map(row,[base,[0,0,0,1,0x29,2,0x24,0],
                [0x59,0x59,0x23,7,0x31,0x12,0x99,0],[0,0,0,1,0x29,2,0x25,0],
                [0,0,0,1,1,1,0,0x80]])),encoding='ascii')
            run('tb_rtc',[ROOT/'rtl/rtc_ds3231.v',HERE/'ds3231_model.sv',HERE/'tb_rtc.sv'],tmp,{'QUARTER':125})
            run('tb_rtc_defaults',[ROOT/'rtl/rtc_ds3231.v',HERE/'ds3231_model.sv',HERE/'tb_defaults.sv'],tmp)
            run('tb_rtc_recovery',[ROOT/'rtl/rtc_ds3231.v',HERE/'ds3231_model.sv',HERE/'tb_recovery.sv'],tmp)
            run('tb_rtc_board',[ROOT/'rtl/rtc_ds1302.v',ROOT/'tests/rtc_ds1302/ds1302_model.sv',HERE/'tb_board.sv',*board_sources],tmp)
            asset=json.loads((ROOT/'assets/settings_v03.json').read_text(encoding='utf-8'))
            bits=[c for g in asset['glyphs'] for row_ in g['rows'] for c in row_]
            bits+=['0']*(16384-len(bits))
            (tmp/'font.hex').write_text('\n'.join(bits)+'\n',encoding='ascii')
            run('tb_rtc_overlay',[ROOT/'rtl/video_chinese_settings.v',ROOT/'rtl/settings_font_rom.v',HERE/'tb_overlay.sv'],tmp)
            with Image.open(tmp/'rtc_overlay.ppm') as im:im.save(HERE/'rtc_overlay.png')
            ids={g['character']:i for i,g in enumerate(asset['glyphs'])}
            (tmp/'timestamp_glyphs.hex').write_text(''.join(f'{ids[c]:x}\n' for c in '2026-10-21 23:59:59'),encoding='ascii')
            run('tb_rtc_av',[*av_sources,HERE/'tb_av.sv'],tmp)
        assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in inputs.items())
        (HERE/'summary.json').write_text(json.dumps({'status':'passed','cases':records,'inputs_sha256':inputs,
             'hardware_tested':False},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    finally:(HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')

if __name__=='__main__':main()
