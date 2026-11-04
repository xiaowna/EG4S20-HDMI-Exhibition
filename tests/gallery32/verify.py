"""32-image catalogue, real loaders, guarded RAM, navigation and audio concurrency."""
import argparse
from contextlib import redirect_stdout
import hashlib
import io
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import sys

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT))
from tools.check_demo_media import check_directory


def fixture(count):
    data=bytearray(39*512)
    put16=lambda a,v:struct.pack_into('<H',data,a,v)
    put32=lambda a,v:struct.pack_into('<I',data,a,v&0xffffffff)
    data[446+4]=12;put32(446+8,2048);put32(446+12,70632);data[510:512]=b'\x55\xaa'
    b=512;put16(b+11,512);data[b+13]=1;put16(b+14,32);data[b+16]=1
    put32(b+32,70632);put32(b+36,600);put32(b+44,2);data[b+510:b+512]=b'\x55\xaa'
    for cluster in range(128):put32(2*512+cluster*4,3 if cluster==2 else 4 if cluster==3 else 0x0fffffff)
    for i in range(count):
        a=3*512+i*32;data[a:a+11]=f'PIC{i+1:05d}BMP'.encode('ascii');data[a+11]=32
        put16(a+26,10+2*i);put32(a+28,78+i%7)
        image=bytearray(78+i%7);image[:2]=b'BM'
        struct.pack_into('<I',image,2,78);struct.pack_into('<I',image,10,54)
        struct.pack_into('<IiiHHI',image,14,40,4,-2 if i%2 else 2,1,24,0)
        for row in range(2):
            y=row if i%2 else 1-row
            for x in range(4):
                image[54+row*12+x*3:54+row*12+x*3+3]=bytes(((29+i*7+x+y)&255,(31+i*5+y)&255,(17+i*3+x)&255))
        data[(6+i)*512:(6+i)*512+len(image)]=image
    a=3*512+count*32;data[a:a+11]=b'MUSIC   WAV';data[a+11]=32;put16(a+26,100);put32(a+28,52)
    return data


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir',type=Path,required=True)
    parser.add_argument('--case',type=int,choices=[0,1,5,8,16,31,32,33])
    args=parser.parse_args();logs=[];records=[]
    sources=[ROOT/'rtl'/n for n in ['fat32_boot_parser.v','fat32_volume_locator.v','fat32_card_catalog.v',
        'fat32_bmp_catalog.v','fat32_dir_scan.v','fat32_file_reader.v','bmp_stream_decoder.v',
        'fat32_image_loader.v','fat32_frame_loader.v','frame_buffer_manager.v','media_prefetch_control.v','sd_sector_arbiter.v']]
    status_sources=[ROOT/'rtl'/n for n in ['audio_tone_bank.v','audio_async_fifo.v','audio_source_flush.v',
        'hdmi_audio_packets.v','hdmi_av_output.v','video_brightness_lut.v','video_audio_waveform.v',
        'video_scroll_osd.v','hdmi_bch8.v','hdmi_terc4.v','hdmi_data_island_encoder.v','tmds_encoder.v','tmds_channels.v']]
    inputs={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+status_sources+[HERE/'tb_gallery.sv',HERE/'tb_status.sv']}
    try:
        with tempfile.TemporaryDirectory(prefix='gallery32_') as name:
            temp=Path(name)
            for count in ([args.case] if args.case is not None else [0,1,5,8,16,31,32,33]):
                (temp/'fixture.hex').write_text(''.join(f'{v:02x}\n' for v in fixture(count)),encoding='ascii')
                for command in [[args.tool_dir/'iverilog.exe','-g2012','-s','tb_gallery',f'-Ptb_gallery.COUNT={count}',
                                 '-o',temp/'check.vvp',*sources,HERE/'tb_gallery.sv'],[args.tool_dir/'vvp.exe',temp/'check.vvp']]:
                    result=subprocess.run(list(map(str,command)),cwd=temp,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
                    output=result.stdout+result.stderr;logs.append(output);print(output,end='',flush=True)
                    if result.returncode or 'FATAL' in output:raise RuntimeError(f'gallery count={count} failed')
                records.append({'count':count,'status':'passed'})
            for command in [[args.tool_dir/'iverilog.exe','-g2012','-s','tb_status','-o',temp/'status.vvp',
                             *status_sources,HERE/'tb_status.sv'],[args.tool_dir/'vvp.exe',temp/'status.vvp']]:
                result=subprocess.run(list(map(str,command)),cwd=temp,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
                output=result.stdout+result.stderr;logs.append(output);print(output,end='',flush=True)
                if result.returncode or 'FATAL' in output:raise RuntimeError('gallery status failed')
            media=temp/'media';media.mkdir()
            header=bytearray(54);header[:2]=b'BM'
            struct.pack_into('<I',header,2,921654);struct.pack_into('<I',header,10,54)
            struct.pack_into('<IiiHHI',header,14,40,640,480,1,24,0)
            for n in range(32):
                with (media/f'PIC{n+1:05d}.BMP').open('wb') as file:
                    file.write(header);file.seek(921653);file.write(b'\0')
            (media/'MUSIC.WAV').write_bytes(b'RIFF'+struct.pack('<I',40)+b'WAVEfmt '+struct.pack('<IHHIIHH',16,1,2,48000,192000,4,16)+b'data'+struct.pack('<I',4)+bytes(4))
            with redirect_stdout(io.StringIO()):
                assert check_directory(media,32)==0
                assert check_directory(media,4)==1
                (media/'PIC00033.BMP').write_bytes((media/'PIC00001.BMP').read_bytes())
                assert check_directory(media,32)==1
            print('PASS media checker: 32 BMP accepted; 33 and old four-image profile rejected',flush=True)
        assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in inputs.items())
        (HERE/'summary.json').write_text(json.dumps({'status':'passed','cases':records,'inputs_sha256':inputs},indent=2)+'\n',encoding='utf-8')
        print(f'PASS gallery32 integration: {len(records)} catalogue configurations',flush=True)
    finally:(HERE/'regression.log').write_text(''.join(logs),encoding='utf-8')


if __name__=='__main__':main()
