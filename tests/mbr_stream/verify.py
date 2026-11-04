"""Black-box MBR/superfloppy oracle and exact public cycle-equivalence checks."""
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
    parser.add_argument('--rtl', type=Path, help='Optional fat32_volume_locator.v')
    parser.add_argument('--compare-rtl', type=Path,
                        help='Compare all public outputs every clock against this RTL')
    parser.add_argument('--log-name', default='regression.log')
    args = parser.parse_args()
    directory = Path(__file__).resolve().parent
    root = directory.parents[1]
    rtl = (args.rtl or root / 'rtl/fat32_volume_locator.v').resolve()
    boot = root / 'rtl/fat32_boot_parser.v'
    iverilog = args.tool_dir / 'iverilog.exe' if args.tool_dir else shutil.which('iverilog')
    vvp = args.tool_dir / 'vvp.exe' if args.tool_dir else shutil.which('vvp')
    if not iverilog or not vvp:
        parser.error('Icarus Verilog not found; provide --tool-dir')
    sources = [rtl, boot.resolve()]
    if args.compare_rtl:
        sources.append(args.compare_rtl.resolve())
    hashes = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    logs = [f'RTL: {p}\nSHA256: {digest}\n' for p, digest in hashes.items()]
    print(''.join(logs), end='', flush=True)
    try:
        with tempfile.TemporaryDirectory(prefix='mbr_stream_', dir=directory) as temporary:
            output = Path(temporary) / 'check.vvp'
            options, extra = [], []
            if args.compare_rtl:
                comparison = Path(temporary) / 'baseline.v'
                renamed, count = re.subn(r'\bmodule\s+fat32_volume_locator\b',
                                        'module fat32_volume_locator_baseline',
                                        sources[-1].read_text(encoding='utf-8-sig'), count=1)
                if count != 1:
                    raise RuntimeError('Comparison RTL does not declare fat32_volume_locator')
                comparison.write_text(renamed, encoding='utf-8')
                options = ['-DCOMPARE_BASELINE']
                extra = [comparison]
            for timeout in (800, 2048):
                commands = [
                    [iverilog, '-g2012', *options, '-s', 'tb_mbr_stream',
                     f'-Ptb_mbr_stream.TIMEOUT_CYCLES={timeout}', '-o', output,
                     rtl, boot, *extra, directory / 'tb_mbr_stream.sv'],
                    [vvp, output],
                ]
                for command in commands:
                    result = subprocess.run(list(map(str, command)), capture_output=True,
                                            text=True, encoding='utf-8', errors='replace',
                                            timeout=90, cwd=directory)
                    combined = result.stdout + result.stderr
                    logs.append(combined)
                    print(combined, end='', flush=True)
                    if result.returncode or 'FATAL' in combined:
                        raise RuntimeError(f'MBR regression failed: timeout={timeout}')
            for p, digest in hashes.items():
                if hashlib.sha256(p.read_bytes()).hexdigest() != digest:
                    raise RuntimeError(f'RTL changed during test: {p}')
        logs.append('PASS: 2 MBR timeout configurations\n')
        print(logs[-1], end='', flush=True)
    finally:
        (directory / args.log_name).write_text(''.join(logs), encoding='utf-8')


if __name__ == '__main__':
    main()
