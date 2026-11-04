"""Cycle-accurate black-box regression of SPI byte timing and handshaking."""
from pathlib import Path
import argparse
import hashlib
import re
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir', type=Path, help='Directory containing iverilog.exe and vvp.exe')
    parser.add_argument('--rtl', type=Path, help='Optional baseline sd_spi_master.v')
    parser.add_argument('--compare-rtl', type=Path,
                        help='Compare every output cycle against this additional RTL')
    parser.add_argument('--log-name', default='regression.log')
    args = parser.parse_args()
    directory = Path(__file__).resolve().parent
    rtl = (args.rtl or directory.parents[1] / 'rtl/sd_spi_master.v').resolve()
    iverilog = args.tool_dir / 'iverilog.exe' if args.tool_dir else shutil.which('iverilog')
    vvp = args.tool_dir / 'vvp.exe' if args.tool_dir else shutil.which('vvp')
    if not iverilog or not vvp:
        parser.error('Icarus Verilog not found; provide --tool-dir')
    digest = hashlib.sha256(rtl.read_bytes()).hexdigest()
    logs = [f'RTL: {rtl}\nRTL SHA256: {digest}\n']
    baseline = args.compare_rtl.resolve() if args.compare_rtl else None
    baseline_digest = hashlib.sha256(baseline.read_bytes()).hexdigest() if baseline else None
    if baseline:
        logs.append(f'Comparison RTL: {baseline}\nComparison SHA256: {baseline_digest}\n')
    print(''.join(logs), end='', flush=True)
    # Minimum, non-powers of two, exact powers of two, production values,
    # and fast-mode divisors greater than the nominal slow divisor.
    cases = [(1, 1), (1, 2), (2, 1), (2, 3), (3, 2), (4, 3),
             (63, 4), (64, 4), (65, 4), (128, 65), (3, 64), (65, 128)]
    try:
        with tempfile.TemporaryDirectory(prefix='spi_divider_', dir=directory) as temporary:
            output_path = Path(temporary) / 'check.vvp'
            comparison_sources = []
            comparison_options = []
            if baseline:
                comparison_path = Path(temporary) / 'baseline.v'
                renamed, count = re.subn(r'\bmodule\s+sd_spi_master\b',
                                         'module sd_spi_master_baseline',
                                         baseline.read_text(encoding='utf-8-sig'), count=1)
                if count != 1:
                    raise RuntimeError('Comparison RTL does not declare sd_spi_master')
                comparison_path.write_text(renamed, encoding='utf-8')
                comparison_sources = [comparison_path]
                comparison_options = ['-DCOMPARE_BASELINE']
            for slow, fast in cases:
                commands = [
                    [iverilog, '-g2012', *comparison_options, '-s', 'tb_spi_divider',
                     f'-Ptb_spi_divider.CLK_DIV={slow}',
                     f'-Ptb_spi_divider.READ_CLK_DIV={fast}',
                     '-o', output_path, rtl, *comparison_sources, directory / 'tb_spi_divider.sv'],
                    [vvp, output_path],
                ]
                for command in commands:
                    result = subprocess.run(list(map(str, command)), capture_output=True,
                                            text=True, timeout=60, cwd=directory)
                    output = result.stdout + result.stderr
                    logs.append(output)
                    print(output, end='', flush=True)
                    if result.returncode or 'FATAL' in output:
                        raise RuntimeError(f'SPI regression failed: slow={slow}, fast={fast}')
        if hashlib.sha256(rtl.read_bytes()).hexdigest() != digest:
            raise RuntimeError('RTL changed during the test; result rejected')
        if baseline and hashlib.sha256(baseline.read_bytes()).hexdigest() != baseline_digest:
            raise RuntimeError('Comparison RTL changed during the test; result rejected')
        logs.append(f'PASS: {len(cases)} SPI divider configurations\n')
        print(logs[-1], end='', flush=True)
    finally:
        (directory / args.log_name).write_text(''.join(logs), encoding='utf-8')


if __name__ == '__main__':
    main()
