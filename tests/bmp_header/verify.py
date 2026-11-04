"""Black-box BMP header validation, streaming, and cycle-equivalence regression."""
from pathlib import Path
import argparse
import hashlib
import re
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir', type=Path)
    parser.add_argument('--rtl', type=Path, help='Optional bmp_stream_decoder.v to test')
    parser.add_argument('--compare-rtl', type=Path,
                        help='Compare every public output cycle against this RTL')
    parser.add_argument('--log-name', default='regression.log')
    args = parser.parse_args()
    directory = Path(__file__).resolve().parent
    rtl = (args.rtl or directory.parents[1] / 'rtl/bmp_stream_decoder.v').resolve()
    iverilog = args.tool_dir / 'iverilog.exe' if args.tool_dir else shutil.which('iverilog')
    vvp = args.tool_dir / 'vvp.exe' if args.tool_dir else shutil.which('vvp')
    if not iverilog or not vvp:
        parser.error('Icarus Verilog not found; provide --tool-dir')
    sources = [rtl]
    if args.compare_rtl:
        sources.append(args.compare_rtl.resolve())
    hashes = {source: hashlib.sha256(source.read_bytes()).hexdigest() for source in sources}
    logs = [f'RTL: {source}\nSHA256: {digest}\n' for source, digest in hashes.items()]
    print(''.join(logs), end='', flush=True)
    try:
        with tempfile.TemporaryDirectory(prefix='bmp_header_', dir=directory) as temporary:
            output = Path(temporary) / 'check.vvp'
            options, extra_sources = [], []
            if args.compare_rtl:
                comparison = Path(temporary) / 'baseline.v'
                text, count = re.subn(r'\bmodule\s+bmp_stream_decoder\b',
                                     'module bmp_stream_decoder_baseline',
                                     sources[-1].read_text(encoding='utf-8-sig'), count=1)
                if count != 1:
                    raise RuntimeError('Comparison RTL does not declare bmp_stream_decoder')
                comparison.write_text(text, encoding='utf-8')
                options = ['-DCOMPARE_BASELINE']
                extra_sources = [comparison]
            cases = [(3, 2), (4, 2), (640, 480)]
            for width, height in cases:
                commands = [
                    [iverilog, '-g2012', *options, '-s', 'tb_bmp_header',
                     f'-Ptb_bmp_header.FRAME_WIDTH={width}',
                     f'-Ptb_bmp_header.FRAME_HEIGHT={height}', '-o', output,
                     rtl, *extra_sources, directory / 'tb_bmp_header.sv'],
                    [vvp, output],
                ]
                for command in commands:
                    result = subprocess.run(list(map(str, command)), capture_output=True,
                                            text=True, timeout=240, cwd=directory)
                    combined = result.stdout + result.stderr
                    logs.append(combined)
                    print(combined, end='', flush=True)
                    if result.returncode or 'FATAL' in combined:
                        raise RuntimeError(f'BMP header regression failed: {width}x{height}')
        for source, digest in hashes.items():
            if hashlib.sha256(source.read_bytes()).hexdigest() != digest:
                raise RuntimeError(f'RTL changed during the test: {source}')
        logs.append(f'PASS: {len(cases)} BMP header configurations\n')
        print(logs[-1], end='', flush=True)
    finally:
        (directory / args.log_name).write_text(''.join(logs), encoding='utf-8')


if __name__ == '__main__':
    main()
