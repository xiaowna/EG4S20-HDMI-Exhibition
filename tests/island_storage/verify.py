"""Data-island public-interface oracle and optional all-cycle RTL equivalence."""
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
    parser.add_argument('--rtl', type=Path, help='Encoder RTL to test instead of the maintained RTL')
    parser.add_argument('--compare-rtl', type=Path,
                        help='Compare all 39 public output bits, including invalid cycles')
    parser.add_argument('--log-name', default='regression.log')
    args = parser.parse_args()
    directory = Path(__file__).resolve().parent
    root = directory.parents[1]
    rtl = (args.rtl or root / 'rtl/hdmi_data_island_encoder.v').resolve()
    iverilog = args.tool_dir / 'iverilog.exe' if args.tool_dir else shutil.which('iverilog')
    vvp = args.tool_dir / 'vvp.exe' if args.tool_dir else shutil.which('vvp')
    if not iverilog or not vvp:
        parser.error('Icarus Verilog not found; provide --tool-dir')
    sources = [rtl, root / 'rtl/hdmi_bch8.v', root / 'rtl/hdmi_terc4.v']
    comparison = args.compare_rtl.resolve() if args.compare_rtl else None
    hashed_sources = [*sources, *([comparison] if comparison else []),
                      directory / 'tb_island_storage.sv',
                      root / 'tests/data_island/input.hex',
                      root / 'tests/data_island/golden.hex']
    hashes = {source: hashlib.sha256(source.read_bytes()).hexdigest()
              for source in hashed_sources}
    logs = [f'SOURCE: {source}\nSHA256: {digest}\n'
            for source, digest in hashes.items()]
    print(''.join(logs), end='', flush=True)
    try:
        with tempfile.TemporaryDirectory(prefix='island_storage_', dir=directory) as temporary:
            output = Path(temporary) / 'check.vvp'
            options, extra_sources = [], []
            if comparison:
                renamed = Path(temporary) / 'baseline.v'
                text, count = re.subn(r'\bmodule\s+hdmi_data_island_encoder\b',
                                     'module hdmi_data_island_encoder_baseline',
                                     comparison.read_text(encoding='utf-8-sig'), count=1)
                if count != 1:
                    raise RuntimeError('Comparison RTL does not declare hdmi_data_island_encoder')
                renamed.write_text(text, encoding='utf-8')
                options = ['-DCOMPARE_BASELINE']
                extra_sources = [renamed]
            commands = [
                [iverilog, '-g2012', *options, '-s', 'tb_island_storage', '-o', output,
                 *sources, *extra_sources, directory / 'tb_island_storage.sv'],
                [vvp, output],
            ]
            for command in commands:
                result = subprocess.run(list(map(str, command)), capture_output=True,
                                        text=True, timeout=240, cwd=directory)
                combined = result.stdout + result.stderr
                logs.append(combined)
                print(combined, end='', flush=True)
                if result.returncode or 'FATAL' in combined:
                    raise RuntimeError('Data-island storage regression failed')
        for source, digest in hashes.items():
            if hashlib.sha256(source.read_bytes()).hexdigest() != digest:
                raise RuntimeError(f'Source changed during the test: {source}')
        logs.append('PASS: independent 39-bit public oracle and all requested checks\n')
        print(logs[-1], end='', flush=True)
    finally:
        (directory / args.log_name).write_text(''.join(logs), encoding='utf-8')


if __name__ == '__main__':
    main()
