"""Prove the shared-BPB oracle detects four relevant temporary RTL faults."""
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
    args = p.parse_args()
    originals = {n: (ROOT / 'rtl' / (n + '.v')).read_text(encoding='utf-8-sig') for n in MODULES}
    paths = [ROOT / 'rtl' / (n + '.v') for n in MODULES]
    paths += [HERE / 'tb_bpb_share.sv', HERE / 'fault_injection.py']
    hashes = {str(x.resolve()): hashlib.sha256(x.read_bytes()).hexdigest() for x in paths}
    mutants = [
        ('wrong_shared_owner', 'fat32_card_catalog',
         '.bpb_fields(cat_active?cat_bpb_fields:loc_bpb_fields)', '.bpb_fields(loc_bpb_fields)'),
        ('missing_partition_offset', 'fat32_boot_parser',
         'data_start<={2\'b0,partition}+overhead;', 'data_start<=overhead;'),
        ('missing_active_fat', 'fat32_boot_parser',
         "((flags[7] && flags[3:0]!=0)?{2'b0,fat_size}:34'd0)", "34'd0"),
        ('missing_fat_capacity_check', 'fat32_boot_parser',
         "({32'b0,fat_size}<<7)>=({1'b0,clusters}+33'd2) && ", ''),
    ]
    results, logs = [], []
    with tempfile.TemporaryDirectory(prefix='bpb_share_fault_') as temporary:
        temporary = Path(temporary)
        refs = []
        for n in MODULES:
            s = (FROZEN / (n + '.v')).read_text(encoding='utf-8-sig')
            for other in MODULES:
                s = re.sub(r'\b' + other + r'\b', other + '_baseline', s)
            refs.append(s)
        reference = temporary / 'baseline.v'
        reference.write_text('\n'.join(refs), encoding='utf-8')
        for label, module, before, after in mutants:
            if originals[module].count(before) != 1:
                raise RuntimeError('Mutation anchor is not unique: ' + label)
            rtl = []
            for n in MODULES:
                q = temporary / (n + '.v')
                q.write_text(originals[n].replace(before, after) if n == module else originals[n], encoding='utf-8')
                rtl.append(q)
            image = temporary / 'fault.vvp'
            compile_result = subprocess.run(list(map(str, [args.tool_dir / 'iverilog.exe', '-g2012',
                '-s', 'tb_bpb_share', '-Ptb_bpb_share.LIMIT=2048', '-Ptb_bpb_share.FOUR=0',
                '-o', image, *rtl, reference, HERE / 'tb_bpb_share.sv'])),
                capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=30)
            if compile_result.returncode:
                raise RuntimeError(compile_result.stdout + compile_result.stderr)
            result = subprocess.run([str(args.tool_dir / 'vvp.exe'), str(image)], capture_output=True,
                text=True, encoding='utf-8', errors='replace', timeout=60)
            output = result.stdout + result.stderr
            logs.append(label + '\n' + output)
            if result.returncode == 0 or 'FAIL BPB share' not in output:
                raise RuntimeError('Fault escaped the acceptance oracle: ' + label)
            print('PASS fault rejected: ' + label, flush=True)
            results.append({'fault': label, 'rejected': True, 'diagnostic': output.strip()})
    for name, digest in hashes.items():
        if hashlib.sha256(Path(name).read_bytes()).hexdigest() != digest:
            raise RuntimeError('Production source changed: ' + name)
    (HERE / 'fault_injection.log').write_text('\n'.join(logs), encoding='utf-8')
    (HERE / 'fault_injection.json').write_text(json.dumps({
        'passed': True, 'faults': results, 'source_sha256': hashes,
        'scope': 'Temporary copies only; no production source or config modified.'
    }, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
