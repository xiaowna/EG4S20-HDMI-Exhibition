"""Independent BPB arithmetic/transport oracle and full public cycle equivalence."""
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
    root = directory.parents[1]
    rtl = (args.rtl or root / 'rtl/fat32_boot_parser.v').resolve()
    sources = [rtl]
    if args.compare_rtl:
        sources.append(args.compare_rtl.resolve())
    hashes = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    iverilog = args.tool_dir / 'iverilog.exe' if args.tool_dir else shutil.which('iverilog')
    vvp = args.tool_dir / 'vvp.exe' if args.tool_dir else shutil.which('vvp')
    if not iverilog or not vvp:
        parser.error('Icarus Verilog not found; provide --tool-dir')
    logs = [f'RTL: {p}\nSHA256: {digest}\n' for p, digest in hashes.items()]
    print(''.join(logs), end='', flush=True)
    try:
        with tempfile.TemporaryDirectory(prefix='bpb_width_', dir=directory) as temporary:
            output = Path(temporary) / 'check.vvp'
            options, extra = [], []
            if args.compare_rtl:
                renamed, count = re.subn(r'\bmodule\s+fat32_boot_parser\b',
                                        'module fat32_boot_parser_baseline',
                                        sources[-1].read_text(encoding='utf-8-sig'), count=1)
                if count != 1:
                    raise RuntimeError('Comparison RTL does not declare fat32_boot_parser')
                comparison = Path(temporary) / 'baseline.v'
                comparison.write_text(renamed, encoding='utf-8')
                options = ['-DCOMPARE_BASELINE']
                extra = [comparison]
            for timeout in (800, 2048):
                commands = [
                    [iverilog, '-g2012', *options, '-s', 'tb_bpb_width',
                     f'-Ptb_bpb_width.TIMEOUT_CYCLES={timeout}', '-o', output,
                     rtl, *extra, directory / 'tb_bpb_width.sv'],
                    [vvp, output],
                ]
                for command in commands:
                    result = subprocess.run(list(map(str, command)), capture_output=True,
                                            text=True, encoding='utf-8', errors='replace',
                                            timeout=120, cwd=directory)
                    combined = result.stdout + result.stderr
                    logs.append(combined)
                    print(combined, end='', flush=True)
                    if result.returncode or 'FATAL' in combined:
                        raise RuntimeError(f'BPB width regression failed: timeout={timeout}')
            for p, digest in hashes.items():
                if hashlib.sha256(p.read_bytes()).hexdigest() != digest:
                    raise RuntimeError(f'RTL changed during test: {p}')
        logs.append('PASS: 2 BPB width timeout configurations\n')
        print(logs[-1], end='', flush=True)
    finally:
        (directory / args.log_name).write_text(''.join(logs), encoding='utf-8')


if __name__ == '__main__':
    main()
