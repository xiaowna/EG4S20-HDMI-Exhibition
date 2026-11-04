"""Isolated F3 affine/fade LUT test with an independent signed integer oracle."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir', type=Path)
    parser.add_argument('--rtl', type=Path)
    parser.add_argument('--log-name', default='lut_regression.log')
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    rtl = (args.rtl or here.parents[1] / 'rtl/video_brightness_lut.v').resolve()
    sources = [rtl, here / 'tb_video_brightness_lut.sv']
    iverilog = args.tool_dir / 'iverilog.exe' if args.tool_dir else shutil.which('iverilog')
    vvp = args.tool_dir / 'vvp.exe' if args.tool_dir else shutil.which('vvp')
    if not iverilog or not vvp:
        parser.error('Icarus not found; provide --tool-dir')
    hashes = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    logs = [f'Source: {p}\nSHA256: {v}\n' for p, v in hashes.items()]
    print(''.join(logs), end='', flush=True)
    try:
        with tempfile.TemporaryDirectory(prefix='fade_lut_') as temporary:
            simulation = Path(temporary) / 'lut.vvp'
            commands = [
                [iverilog, '-g2012', '-Wall', '-s', 'tb_video_fade_lut',
                 '-o', simulation, *sources],
                [vvp, simulation],
            ]
            for command in commands:
                result = subprocess.run(list(map(str, command)), capture_output=True,
                                        text=True, encoding='utf-8', errors='replace', timeout=120)
                combined = result.stdout + result.stderr
                logs.append(combined)
                print(combined, end='', flush=True)
                if result.returncode or 'FATAL' in combined:
                    raise RuntimeError('Fade LUT regression failed')
            if 'PASS: independent affine/fade LUT' not in combined:
                raise RuntimeError('Success marker missing')
        for path, digest in hashes.items():
            if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                raise RuntimeError(f'Source changed during test: {path}')
    finally:
        (here / args.log_name).write_text(''.join(logs), encoding='utf-8')


if __name__ == '__main__':
    main()
