"""Black-box FAT32 directory sector buffering and cycle-equivalence checks."""
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
    parser.add_argument('--rtl', type=Path, help='Optional fat32_dir_scan.v to test')
    parser.add_argument('--compare-rtl', type=Path,
                        help='Compare every public output cycle against this RTL')
    parser.add_argument('--log-name', default='regression.log')
    args = parser.parse_args()
    directory = Path(__file__).resolve().parent
    rtl = (args.rtl or directory.parents[1] / 'rtl/fat32_dir_scan.v').resolve()
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
        with tempfile.TemporaryDirectory(prefix='dir_bram_', dir=directory) as temporary:
            output = Path(temporary) / 'check.vvp'
            options, extra_sources = [], []
            if args.compare_rtl:
                comparison = Path(temporary) / 'baseline.v'
                text, count = re.subn(r'\bmodule\s+fat32_dir_scan\b',
                                     'module fat32_dir_scan_baseline',
                                     sources[-1].read_text(encoding='utf-8-sig'), count=1)
                if count != 1:
                    raise RuntimeError('Comparison RTL does not declare fat32_dir_scan')
                comparison.write_text(text, encoding='utf-8')
                options = ['-DCOMPARE_BASELINE']
                extra_sources = [comparison]
            cases = [(4, 1), (1, 1), (4, 0), (1, 0)]
            for max_files, find_wav in cases:
                commands = [
                    [iverilog, '-g2012', *options, '-s', 'tb_dir_bram',
                     f'-Ptb_dir_bram.MAX_FILES={max_files}',
                     f'-Ptb_dir_bram.FIND_WAV={find_wav}', '-o', output,
                     rtl, *extra_sources, directory / 'tb_dir_bram.sv'],
                    [vvp, output],
                ]
                for command in commands:
                    result = subprocess.run(list(map(str, command)), capture_output=True,
                                            text=True, timeout=90, cwd=directory)
                    combined = result.stdout + result.stderr
                    logs.append(combined)
                    print(combined, end='', flush=True)
                    if result.returncode or 'FATAL' in combined:
                        raise RuntimeError(f'Directory regression failed: {max_files}/{find_wav}')
        for source, digest in hashes.items():
            if hashlib.sha256(source.read_bytes()).hexdigest() != digest:
                raise RuntimeError(f'RTL changed during the test: {source}')
        logs.append(f'PASS: {len(cases)} directory configurations\n')
        print(logs[-1], end='', flush=True)
    finally:
        (directory / args.log_name).write_text(''.join(logs), encoding='utf-8')


if __name__ == '__main__':
    main()
