"""24-image exhibition: bounded metadata, navigation, corruption and four-WAV scan."""
import argparse
from contextlib import redirect_stdout
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from tools.check_demo_media import check_directory


def check_media(temp):
    folder = temp / 'media'
    folder.mkdir()
    header = bytearray(54)
    header[:2] = b'BM'
    struct.pack_into('<II', header, 2, 921654, 0)
    struct.pack_into('<I', header, 10, 54)
    struct.pack_into('<IiiHHI', header, 14, 40, 640, 480, 1, 24, 0)
    wav = (b'RIFF' + struct.pack('<I', 40) + b'WAVEfmt '
           + struct.pack('<IHHIIHH', 16, 1, 2, 48000, 192000, 4, 16)
           + b'data' + struct.pack('<I', 4) + bytes(4))
    for n in range(24):
        with (folder / f'{n+1:02}.BMP').open('wb') as file:
            file.write(header)
            file.seek(921653)
            file.write(b'\0')
    for n in range(4):
        (folder / f'MUSIC{n+1}.WAV').write_bytes(wav)
    with redirect_stdout(io.StringIO()):
        assert check_directory(folder) == 0, '24 BMP + four WAV must be accepted'
        extra = folder / '25.BMP'
        extra.write_bytes((folder / '01.BMP').read_bytes())
        assert check_directory(folder) == 1, '25th BMP must fail current preflight'
        assert check_directory(folder, 32) == 0, 'historical 32-image profile must remain usable'
        extra.unlink()
        song = folder / 'MUSIC5.WAV'
        song.write_bytes(wav)
        assert check_directory(folder) == 1, 'fifth WAV must fail current preflight'
        song.unlink()
        assert check_directory(folder, max_wavs=1) == 1, 'legacy single-WAV profile must reject four songs'
    return 5


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir', type=Path, required=True)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location('gallery_fixture', ROOT / 'tests/gallery32/verify.py')
    gallery = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gallery)
    source_names = ['fat32_boot_parser.v', 'fat32_volume_locator.v', 'fat32_card_catalog.v',
                    'fat32_bmp_catalog.v', 'fat32_dir_scan.v', 'fat32_file_reader.v',
                    'bmp_stream_decoder.v', 'fat32_image_loader.v', 'fat32_frame_loader.v',
                    'frame_buffer_manager.v', 'media_prefetch_control.v', 'sd_sector_arbiter.v']
    sources = [ROOT / 'rtl' / n for n in source_names]
    benches = [ROOT / 'tests/gallery32/tb_gallery.sv', ROOT / 'tests/music_select/tb_catalog.sv']
    tracked = sources + benches + [ROOT / 'tools/check_demo_media.py', Path(__file__).resolve()]
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in tracked}
    logs, cases = [], []

    def run(cmd, cwd):
        result = subprocess.run(list(map(str, cmd)), cwd=cwd, capture_output=True,
                                text=True, encoding='utf-8', errors='replace', timeout=180)
        out = result.stdout + result.stderr
        print(out, end='', flush=True)
        logs.append(out)
        if result.returncode or 'FATAL' in out:
            raise RuntimeError('24-image exhibition verification failed')

    try:
        with tempfile.TemporaryDirectory(prefix='gallery24_') as name:
            temp = Path(name)
            for count in [0, 1, 6, 23, 24, 25, 32]:
                (temp / 'fixture.hex').write_text(''.join(f'{b:02x}\n' for b in gallery.fixture(count)), encoding='ascii')
                run([args.tool_dir / 'iverilog.exe', '-g2012', '-s', 'tb_gallery',
                     '-Ptb_gallery.CAP=24', f'-Ptb_gallery.COUNT={count}', '-o', temp / 'gallery.vvp',
                     *sources, benches[0]], temp)
                run([args.tool_dir / 'vvp.exe', temp / 'gallery.vvp'], temp)
                cases.append({'input_images': count, 'accepted': min(count, 24)})
            run([args.tool_dir / 'iverilog.exe', '-g2012', '-s', 'tb_music_catalog',
                 '-Ptb_music_catalog.CAP=24', '-o', temp / 'music.vvp',
                 ROOT / 'rtl/fat32_dir_scan.v', benches[1]], temp)
            run([args.tool_dir / 'vvp.exe', temp / 'music.vvp'], temp)
            media_cases = check_media(temp)
        assert all(hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == h for name, h in hashes.items())
        (HERE / 'summary.json').write_text(json.dumps({
            'status': 'passed', 'max_images': 24, 'index_bits': 5, 'count_bits': 5,
            'catalogue_cases': cases, 'four_wav_scenarios': 11,
            'media_checker_cases': media_cases, 'inputs_sha256': hashes}, indent=2) + '\n', encoding='utf-8')
        print('PASS gallery24: seven catalogue cases, all 24 slots and wrap/reverse/autoplay, corrupt frame guard, four-WAV scan and five media-preflight cases', flush=True)
    finally:
        (HERE / 'regression.log').write_text(''.join(logs), encoding='utf-8')


if __name__ == '__main__':
    main()
