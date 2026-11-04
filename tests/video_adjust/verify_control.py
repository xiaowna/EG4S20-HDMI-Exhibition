"""Four-key runtime settings check using the production shared debounce."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir', type=Path)
    parser.add_argument('--count', type=int, nargs='+', default=[1, 2, 7, 28, 29, 32])
    parser.add_argument('--rtl', type=Path)
    parser.add_argument('--log-name', default='control_regression.log')
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    root = here.parents[1]
    control = (args.rtl or root / 'rtl/media_adjust_control.v').resolve()
    sources = [root / 'rtl/board_key.v', control, here / 'tb_media_adjust_control.sv']
    hashes = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    iverilog = args.tool_dir / 'iverilog.exe' if args.tool_dir else shutil.which('iverilog')
    vvp = args.tool_dir / 'vvp.exe' if args.tool_dir else shutil.which('vvp')
    if not iverilog or not vvp:
        parser.error('Icarus not found; provide --tool-dir')
    if any(count < 1 for count in args.count):
        parser.error('COUNT must be positive')
    logs = [f'Source: {p}\nSHA256: {v}\n' for p, v in hashes.items()]
    print(''.join(logs), end='', flush=True)
    try:
        with tempfile.TemporaryDirectory(prefix='wave_control_') as temporary:
            simulation = Path(temporary) / 'control.vvp'
            for count in args.count:
                commands = [
                    [iverilog, '-g2012', '-s', 'tb_media_wave_control',
                     f'-Ptb_media_wave_control.COUNT={count}', '-o', simulation, *sources],
                    [vvp, simulation],
                ]
                for command in commands:
                    result = subprocess.run(list(map(str, command)), capture_output=True,
                                            text=True, encoding='utf-8', errors='replace', timeout=180)
                    combined = result.stdout + result.stderr
                    logs.append(combined)
                    print(combined, end='', flush=True)
                    if result.returncode or 'FATAL' in combined:
                        raise RuntimeError(f'Wave control regression failed: COUNT={count}')
                if 'PASS media_wave_control' not in combined:
                    raise RuntimeError('Control success marker missing')
        for path, digest in hashes.items():
            if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                raise RuntimeError(f'Source changed during test: {path}')
        logs.append(f'PASS: four-key settings control, {len(args.count)} COUNT configurations\n')
        print(logs[-1], end='', flush=True)
    finally:
        (here / args.log_name).write_text(''.join(logs), encoding='utf-8')


if __name__ == '__main__':
    main()
