"""Wire-level board control and full raster oracles for the embedded manual."""
from pathlib import Path
import argparse, hashlib, json, subprocess, tempfile
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir', type=Path, required=True)
    args = parser.parse_args()
    assets = json.loads((ROOT / 'assets/help_assets.json').read_text(encoding='utf-8'))
    output = ROOT / 'reports/onscreen_help_20261111'
    output.mkdir(parents=True, exist_ok=True)
    logs = []
    records = []
    files = list((ROOT / 'rtl').glob('*.v')) + list(HERE.glob('*.*')) + [ROOT / 'assets/help_pages.json', ROOT / 'assets/help_assets.json']
    hashes = {str(f.relative_to(ROOT)): hashlib.sha256(f.read_bytes()).hexdigest() for f in files if f.is_file()}
    def run(top, sources, temp, name):
        exe = temp / (name + '.vvp')
        for command in [[args.tool_dir/'iverilog.exe', '-g2012', '-s', top, '-o', exe, *sources], [args.tool_dir/'vvp.exe', exe]]:
            result = subprocess.run(list(map(str, command)), cwd=temp, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=300)
            log = result.stdout + result.stderr
            logs.append(log)
            print(log, end='', flush=True)
            assert result.returncode == 0 and 'FATAL' not in log, log
        records.append(name)
    try:
        with tempfile.TemporaryDirectory(prefix='hdmi_help_') as work:
            temp = Path(work)
            for scene in range(6):
                pixels, expected = [], []
                for y in range(480):
                    for x in range(640):
                        cover = scene < 4 or (scene == 4 and 64 <= x < 576 and 448 <= y < 464)
                        ink = False
                        accent = False
                        if scene < 4 and 64 <= x < 576 and 48 <= y < 432:
                            column, row = (x-64)//16, (y-48)//16
                            char = assets['character_ids'][scene*1024+row*32+column]
                            ink = bool(assets['glyph_rows'][char][(y-48)%16] & (1 << ((x-64)%16)))
                            accent = row in (0, 23)
                        elif scene == 4 and cover:
                            char = assets['character_ids'][3*1024+31*32+(x-64)//16]
                            ink = bool(assets['glyph_rows'][char][y%16] & (1 << ((x-64)%16)))
                            accent = True
                        rgb = (0x70d6bc if accent else 0xe7efec) if ink else 0x0b1420
                        pixels.append(((rgb>>16)&255, (rgb>>8)&255, rgb&255))
                        expected.append((int(cover)<<24)|rgb)
                (temp/f'expected_{scene}.hex').write_text(''.join(f'{v:07x}\n' for v in expected), encoding='ascii')
                if scene < 5:
                    image = Image.new('RGB', (640, 480)); image.putdata(pixels)
                    image.save(output/f'help_{scene+1}.png')
            for native in [False, True]:
                bench = temp / 'pixels.sv'
                bench.write_text(('`undef __ICARUS__\n' if native else '') + (HERE/'tb_help_pixels.sv').read_text(), encoding='utf-8')
                files = [bench, ROOT/'rtl/video_help.v', ROOT/'rtl/help_assets_rom.v']
                if native: files.append(ROOT/'tests/solar_scene/bram32k_contract.sv')
                run('tb_help_pixels', files, temp, 'native' if native else 'behavioral')
            names = ['rtc_ds1302.v','rtc_set_control.v','hdmi_media_board_top.v','board_key.v','board_matrix_keys.v',
                     'media_nec_receiver.v','media_infrared_control.v','media_control_events.v','media_mode_control.v',
                     'media_adjust_control.v','media_home_control.v','media_help_control.v','home_album_config.v','media_3d_control.v']
            run('tb_help_board', [*[ROOT/'rtl'/n for n in names], HERE/'tb_help_board.sv',
                ROOT/'tests/dmz_media/tb_hdmi_media_board_top.sv',ROOT/'tests/dmz_media/dmz_keyboard_model.sv'], temp, 'board')
        assert all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==sha for n,sha in hashes.items())
        (output/'verification.json').write_text(json.dumps(dict(status='passed',cases=records,
            pixel_checks=2*6*640*480,hardware_tested=False,source_sha256=hashes),indent=2),encoding='utf-8')
    finally:
        (output/'verification.log').write_text(''.join(logs),encoding='utf-8')


if __name__ == '__main__':
    main()
