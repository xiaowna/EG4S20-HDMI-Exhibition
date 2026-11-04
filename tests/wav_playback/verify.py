"""WAV 解码、FAT32 文件循环和 SD 扇区仲裁回归。"""
from pathlib import Path
import argparse
import subprocess
p=argparse.ArgumentParser()
p.add_argument('--tool-dir',type=Path,required=True)
a=p.parse_args()
d=Path(__file__).resolve().parent
b=d.parents[1]
t=a.tool_dir.resolve()
checks={
 'tb_wav_pcm_decoder':['wav_pcm_decoder.v'],
 'tb_sd_sector_arbiter':['sd_sector_arbiter.v'],
 'tb_shared_wav_catalog':['fat32_card_catalog.v','fat32_bmp_catalog.v',
                             'fat32_dir_scan.v','fat32_volume_locator.v','fat32_boot_parser.v'],
 'tb_fat32_wav_player':['fat32_wav_player.v','wav_pcm_decoder.v',
                         'fat32_file_reader.v'],
 'tb_fat32_wav_invalid':['fat32_wav_player.v','wav_pcm_decoder.v',
                         'fat32_file_reader.v'],
 'tb_sd_audio_concurrent':['sd_sector_arbiter.v','fat32_wav_player.v',
                           'wav_pcm_decoder.v','fat32_file_reader.v',
                           'audio_async_fifo.v'],
}
log=[]
try:
    for top,rtl in checks.items():
        for cmd in (
            [t/'iverilog.exe','-g2012','-s',top,'-o',d/(top+'.vvp'),
             *[b/'rtl'/n for n in rtl],d/(top+'.sv')],
            [t/'vvp.exe',d/(top+'.vvp')]):
            r=subprocess.run(list(map(str,cmd)),cwd=d,capture_output=True,text=True,
                             timeout=120 if top=='tb_sd_audio_concurrent' else 30)
            out=r.stdout+r.stderr
            print(out,end='',flush=True)
            log.append(out)
            if r.returncode or 'FATAL' in out:
                raise RuntimeError(top+' regression failed')
        if top=='tb_shared_wav_catalog':
            r=subprocess.run([str(t/'vvp.exe'),str(d/(top+'.vvp')),'+MODE=1'],
                             cwd=d,capture_output=True,text=True,timeout=30)
            out=r.stdout+r.stderr
            print(out,end='',flush=True)
            log.append(out)
            if r.returncode or 'FATAL' in out:
                raise RuntimeError('four-BMP WAV catalogue regression failed')
finally:
    (b/'reports/wav_playback_regression.txt').write_text(''.join(log),encoding='utf-8')
