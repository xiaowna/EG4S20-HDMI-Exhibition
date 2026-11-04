"""BMP dimension/counter oracle and exact 61-bit public cycle equivalence."""
import argparse
import hashlib
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir', type=Path)
    parser.add_argument('--rtl', type=Path)
    parser.add_argument('--compare-rtl', type=Path)
    parser.add_argument('--log-name', default='regression.log')
    args = parser.parse_args()
    directory = Path(__file__).resolve().parent
    rtl = (args.rtl or directory.parents[1] / 'rtl/bmp_stream_decoder.v').resolve()
    sources = [rtl]
    if args.compare_rtl:
        sources.append(args.compare_rtl.resolve())
    hashes = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    logs = [f'RTL: {p}\nSHA256: {digest}\n' for p, digest in hashes.items()]
    print(''.join(logs), end='', flush=True)
    iverilog = args.tool_dir / 'iverilog.exe' if args.tool_dir else shutil.which('iverilog')
    vvp = args.tool_dir / 'vvp.exe' if args.tool_dir else shutil.which('vvp')
    if not iverilog or not vvp:
        parser.error('Icarus Verilog not found; provide --tool-dir')
    dimensions = [(1, 1), (1, 2), (2, 1), (2, 2), (3, 2), (4, 2), (4, 4), (640, 480)]
    try:
        with tempfile.TemporaryDirectory(prefix='bmp_counters_', dir=directory) as temporary:
            output = Path(temporary) / 'check.vvp'
            options, extra = [], []
            if args.compare_rtl:
                comparison = Path(temporary) / 'baseline.v'
                renamed, count = re.subn(r'\bmodule\s+bmp_stream_decoder\b',
                                        'module bmp_stream_decoder_baseline',
                                        sources[-1].read_text(encoding='utf-8-sig'), count=1)
                if count != 1:
                    raise RuntimeError('Comparison RTL does not declare bmp_stream_decoder')
                comparison.write_text(renamed, encoding='utf-8')
                options = ['-DCOMPARE_BASELINE']
                extra = [comparison]
            for width, height in dimensions:
                commands = [
                    [iverilog, '-g2012', *options, '-s', 'tb_bmp_counters',
                     f'-Ptb_bmp_counters.FRAME_WIDTH={width}',
                     f'-Ptb_bmp_counters.FRAME_HEIGHT={height}', '-o', output,
                     rtl, *extra, directory / 'tb_bmp_counters.sv'],
                    [vvp, output],
                ]
                for command in commands:
                    result = subprocess.run(list(map(str, command)), capture_output=True,
                                            text=True, encoding='utf-8', errors='replace',
                                            timeout=240, cwd=directory)
                    combined = result.stdout + result.stderr
                    logs.append(combined)
                    print(combined, end='', flush=True)
                    if result.returncode or 'FATAL' in combined:
                        raise RuntimeError(f'BMP counter regression failed: {width}x{height}')
            for p, digest in hashes.items():
                if hashlib.sha256(p.read_bytes()).hexdigest() != digest:
                    raise RuntimeError(f'RTL changed during test: {p}')
        logs.append(f'PASS: {len(dimensions)} BMP dimension configurations\n')
        print(logs[-1], end='', flush=True)
    finally:
        (directory / args.log_name).write_text(''.join(logs), encoding='utf-8')


if __name__ == '__main__':
    main()
