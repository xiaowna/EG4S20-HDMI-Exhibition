"""PCM packet oracle, encoder symbol oracle, and optional cycle equivalence."""
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
    parser.add_argument('--rtl', type=Path)
    parser.add_argument('--compare-rtl', type=Path)
    parser.add_argument('--log-name', default='regression.log')
    args = parser.parse_args()
    directory = Path(__file__).resolve().parent
    root = directory.parents[1]
    rtl = (args.rtl or root / 'rtl/hdmi_audio_packets.v').resolve()
    iverilog = args.tool_dir / 'iverilog.exe' if args.tool_dir else shutil.which('iverilog')
    vvp = args.tool_dir / 'vvp.exe' if args.tool_dir else shutil.which('vvp')
    if not iverilog or not vvp:
        parser.error('Icarus Verilog not found; provide --tool-dir')
    sources = [rtl, *(root / 'rtl' / name for name in
                     ['hdmi_data_island_encoder.v', 'hdmi_bch8.v', 'hdmi_terc4.v'])]
    if args.compare_rtl:
        sources.append(args.compare_rtl.resolve())
    hashes = {source: hashlib.sha256(source.read_bytes()).hexdigest() for source in sources}
    logs = [f'RTL: {source}\nSHA256: {digest}\n' for source, digest in hashes.items()]
    print(''.join(logs), end='', flush=True)
    try:
        with tempfile.TemporaryDirectory(prefix='audio_slots_', dir=directory) as temporary:
            output = Path(temporary) / 'check.vvp'
            options, extra_sources = [], []
            if args.compare_rtl:
                comparison = Path(temporary) / 'baseline.v'
                text, count = re.subn(r'\bmodule\s+hdmi_audio_packets\b',
                                     'module hdmi_audio_packets_baseline',
                                     args.compare_rtl.read_text(encoding='utf-8-sig'), count=1)
                if count != 1:
                    raise RuntimeError('Comparison RTL does not declare hdmi_audio_packets')
                comparison.write_text(text, encoding='utf-8')
                options = ['-DCOMPARE_BASELINE']
                extra_sources = [comparison]
            commands = [
                [iverilog, '-g2012', *options, '-s', 'tb_audio_slots', '-o', output,
                 *sources[:4], *extra_sources, directory / 'tb_audio_slots.sv'],
                [vvp, output],
            ]
            for command in commands:
                result = subprocess.run(list(map(str, command)), capture_output=True,
                                        text=True, timeout=240, cwd=directory)
                combined = result.stdout + result.stderr
                logs.append(combined)
                print(combined, end='', flush=True)
                if result.returncode or 'FATAL' in combined:
                    raise RuntimeError('Audio slot regression failed')
        for source, digest in hashes.items():
            if hashlib.sha256(source.read_bytes()).hexdigest() != digest:
                raise RuntimeError(f'RTL changed during the test: {source}')
        logs.append('PASS: independent PCM/auxiliary/encoder oracle and all requested checks\n')
        print(logs[-1], end='', flush=True)
    finally:
        (directory / args.log_name).write_text(''.join(logs), encoding='utf-8')


if __name__ == '__main__':
    main()
