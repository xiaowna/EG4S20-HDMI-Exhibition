"""Focused menu-return regressions, using real board/key/home/menu controllers."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BOARD = ['rtc_ds1302.v', 'rtc_set_control.v', 'hdmi_media_board_top.v',
         'board_key.v', 'media_control_events.v', 'media_rotary_encoder.v',
         'media_nec_receiver.v', 'media_infrared_control.v', 'media_mode_control.v',
         'media_adjust_control.v', 'board_matrix_keys.v', 'media_home_control.v','media_help_control.v',
         'home_album_config.v', 'media_3d_control.v']

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir', type=Path, required=True)
    args = parser.parse_args()
    models = [ROOT/'tests/dmz_media/tb_hdmi_media_board_top.sv',
              ROOT/'tests/dmz_media/dmz_keyboard_model.sv']
    jobs = [('tb_home_control', ['media_home_control.v','media_help_control.v', 'home_album_config.v'],
             [HERE/'tb_control.sv'], {}),
            ('tb_home_board', BOARD, [HERE/'tb_board.sv', *models], {'FINE_ADJUST': 0}),
            ('tb_home_board', BOARD, [HERE/'tb_board.sv', *models], {'FINE_ADJUST': 1}),
            ('tb_solar_board_controls', BOARD, [ROOT/'tests/solar_integration/tb_board.sv', *models], {})]
    sources = {ROOT/'rtl'/name for _, names, _, _ in jobs for name in names}
    sources.update(path for _, _, benches, _ in jobs for path in benches)
    sources.add(Path(__file__).resolve())
    digests = {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
               for path in sorted(sources)}
    logs = []
    cases = []
    try:
        with tempfile.TemporaryDirectory(prefix='key4_return_') as folder:
            temp = Path(folder)
            for top, names, benches, params in jobs:
                output = ''
                for command in [[args.tool_dir/'iverilog.exe', '-g2012', '-s', top,
                                 *[f'-P{top}.{name}={value}' for name, value in params.items()],
                                 '-o', temp/'test.vvp',
                                 *[ROOT/'rtl'/name for name in names], *benches],
                                [args.tool_dir/'vvp.exe', temp/'test.vvp']]:
                    result = subprocess.run(list(map(str, command)), cwd=temp,
                                            capture_output=True, text=True,
                                            encoding='utf-8', errors='replace', timeout=60)
                    output += result.stdout + result.stderr
                    if result.returncode or 'FATAL' in output:
                        logs.append(output)
                        raise AssertionError(output)
                assert 'PASS ' in output, output
                print(output, end='', flush=True)
                logs.append(output)
                cases.append({'top': top, 'parameters': params})
        for name, digest in digests.items():
            assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest() == digest, name
        (HERE/'controls_summary.json').write_text(json.dumps({
            'status': 'passed', 'cases': cases, 'source_sha256': digests,
            'hardware_tested': False}, indent=2)+'\n', encoding='utf-8')
    finally:
        (HERE/'controls_regression.log').write_text(''.join(logs), encoding='utf-8')

if __name__ == '__main__':
    main()
