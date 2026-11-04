"""Shared BPB arithmetic: frozen card-port equivalence plus independent sector oracle."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
FROZEN = ROOT / 'reports/bpb_share_20261019/before/worktree/rtl'
MODULES = ['fat32_boot_parser', 'fat32_volume_locator', 'fat32_bmp_catalog',
           'fat32_dir_scan', 'fat32_card_catalog']


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--tool-dir', type=Path, required=True)
    p.add_argument('--rtl-dir', type=Path, default=ROOT / 'rtl')
    p.add_argument('--limits', type=int, nargs='+', default=[2048, 8192, 50000000])
    p.add_argument('--log-name', default='regression.log')
    p.add_argument('--summary-name', default='summary.json')
    args = p.parse_args()
    paths = [args.rtl_dir / (n + '.v') for n in MODULES]
    paths += [FROZEN / (n + '.v') for n in MODULES]
    paths += [HERE / 'tb_bpb_share.sv', HERE / 'verify.py']
    hashes = {str(x.resolve()): hashlib.sha256(x.read_bytes()).hexdigest() for x in paths}
    logs, runs = [], []

    def run(command):
        result = subprocess.run(list(map(str, command)), cwd=HERE, capture_output=True,
                                text=True, encoding='utf-8', errors='replace', timeout=180)
        output = result.stdout + result.stderr
        logs.append(output)
        print(output, end='', flush=True)
        if result.returncode or 'FATAL' in output:
            raise RuntimeError('BPB share verification failed')
        return output

    try:
        with tempfile.TemporaryDirectory(prefix='bpb_share_') as temporary:
            temporary = Path(temporary)
            texts = []
            for name in MODULES:
                s = (FROZEN / (name + '.v')).read_text(encoding='utf-8-sig')
                for other in MODULES:
                    s = re.sub(r'\b' + other + r'\b', other + '_baseline', s)
                texts.append(s)
            baseline = temporary / 'baseline.v'
            baseline.write_text('\n'.join(texts), encoding='utf-8')
            for limit in args.limits:
                for four in [0, 1]:
                    print(f'RUN BPB share LIMIT={limit} FOUR={four}', flush=True)
                    image = temporary / 'check.vvp'
                    run([args.tool_dir / 'iverilog.exe', '-g2012', '-s', 'tb_bpb_share',
                         f'-Ptb_bpb_share.LIMIT={limit}', f'-Ptb_bpb_share.FOUR={four}',
                         '-o', image, *[args.rtl_dir / (n + '.v') for n in MODULES],
                         baseline, HERE / 'tb_bpb_share.sv'])
                    out = run([args.tool_dir / 'vvp.exe', image])
                    if 'PASS BPB share' not in out:
                        raise RuntimeError('Missing completion marker')
                    runs.append({'limit': limit, 'four_files': four,
                                 'metrics': dict(re.findall(r'(\w+)=(\d+)', out.split('PASS BPB share')[-1]))})
        for name, digest in hashes.items():
            if hashlib.sha256(Path(name).read_bytes()).hexdigest() != digest:
                raise RuntimeError('Source changed during verification: ' + name)
        (HERE / args.summary_name).write_text(json.dumps({
            'passed': True, 'runs': runs, 'source_sha256': hashes,
            'large_timeout_method': 'Only deliberately empty timeout waits at 50M use identical timer deposits in DUT and reference; all ordinary 512-byte sectors run in full. 2048 and 8192 timeout cases run naturally.',
            'oracle': 'All card_catalog public outputs compared every clock including reset, provisional metadata and idle. Independently constructed 512-byte sectors, ordered LBA requests, BMP events and terminal volume/WAV metadata are checked.'
        }, indent=2), encoding='utf-8')
        print(f'PASS BPB share acceptance: {len(runs)} configurations; source hashes unchanged', flush=True)
    finally:
        (HERE / args.log_name).write_text(''.join(logs), encoding='utf-8')


if __name__ == '__main__':
    main()
