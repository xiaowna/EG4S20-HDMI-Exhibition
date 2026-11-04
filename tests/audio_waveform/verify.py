"""Isolated F4 waveform oracle; optional five fault-injection checks."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


SUCCESS = 'PASS: independent waveform stream oracle'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_case(iverilog, vvp, rtl, bench, directory, label):
    simulation = directory / f'{label}.vvp'
    compiled = subprocess.run(
        list(map(str, [iverilog, '-g2012', '-Wall', '-s', 'tb_video_audio_waveform',
                       '-o', simulation, rtl, bench])),
        capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=120)
    compilation = compiled.stdout + compiled.stderr
    if compiled.returncode:
        raise RuntimeError(f'{label}: compilation failed\n{compilation}')
    result = subprocess.run([str(vvp), str(simulation)], capture_output=True,
                            text=True, encoding='utf-8', errors='replace', timeout=120)
    output = compilation + result.stdout + result.stderr
    passed = result.returncode == 0 and SUCCESS in output and 'FATAL' not in output
    return passed, output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir', type=Path)
    parser.add_argument('--rtl', type=Path)
    parser.add_argument('--mutations', action='store_true')
    parser.add_argument('--log-name', default='regression.log')
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    rtl = (args.rtl or here.parents[1] / 'rtl/video_audio_waveform.v').resolve()
    bench = here / 'tb.sv'
    iverilog = args.tool_dir / 'iverilog.exe' if args.tool_dir else shutil.which('iverilog')
    vvp = args.tool_dir / 'vvp.exe' if args.tool_dir else shutil.which('vvp')
    if not iverilog or not vvp:
        parser.error('Icarus not found; provide --tool-dir')
    hashes = {str(p): digest(p) for p in (rtl, bench)}
    logs = [f'Source: {p}\nSHA256: {value}\n' for p, value in hashes.items()]
    summary = {'sources': hashes, 'baseline_pass': False, 'mutations': []}
    print(''.join(logs), end='', flush=True)
    try:
        with tempfile.TemporaryDirectory(prefix='waveform_') as temporary:
            directory = Path(temporary)
            passed, output = run_case(iverilog, vvp, rtl, bench, directory, 'baseline')
            logs.append(output)
            print(output, end='', flush=True)
            if not passed:
                raise RuntimeError('Waveform baseline oracle failed')
            summary['baseline_pass'] = True
            metrics = re.search(r'^SUMMARY (.+)$', output, re.MULTILINE)
            if not metrics:
                raise RuntimeError('Coverage summary missing')
            summary['coverage'] = {key: int(value) for key, value in
                                   re.findall(r'(\w+)=(\d+)', metrics.group(1))}
            if args.mutations:
                text = rtl.read_text(encoding='utf-8-sig')
                mutations = [
                    ('advance_on_invalid', '!capture_pending && sample_valid',
                     "!capture_pending && 1'b1", 2),
                    ('sample_every_third', "decimation==2'd3", "decimation==2'd2", 2),
                    ('publish_on_last_write', 'if(capture_pending)begin',
                     "if(capture_pending || (take_sample && capture_index==8'd255))begin", 1),
                    ('combinational_bypass',
                     'assign rgb_out=window_q?window_rgb:bypass_pixel;',
                     "assign rgb_out=window_q?window_rgb:(!rst_n?24'd0:rgb_in);", 1),
                    ('write_active_bank', 'sample_mem[{capture_bank,capture_index}]',
                     'sample_mem[{active_bank,capture_index}]', 1),
                ]
                for name, old, new, occurrences in mutations:
                    if text.count(old) != occurrences:
                        raise RuntimeError(f'{name}: mutation anchor count changed')
                    mutant = directory / f'{name}.v'
                    mutant.write_text(text.replace(old, new), encoding='utf-8')
                    mutant_pass, mutant_output = run_case(
                        iverilog, vvp, mutant, bench, directory, name)
                    caught = not mutant_pass and 'FATAL' in mutant_output
                    logs.append(f'\nMUTATION {name}\n{mutant_output}')
                    summary['mutations'].append({'name': name, 'caught': caught,
                                                 'failure': next((line for line in
                                                  mutant_output.splitlines() if 'FATAL' in line), '')})
                    print(f'MUTATION {name}: {"caught" if caught else "NOT CAUGHT"}', flush=True)
                    if not caught:
                        raise RuntimeError(f'Mutation was not caught: {name}')
        for path, value in hashes.items():
            if digest(Path(path)) != value:
                raise RuntimeError(f'Source changed during test: {path}')
        summary['pass'] = True
        logs.append(f'PASS: {len(summary["mutations"])} requested fault injections caught\n')
    finally:
        (here / args.log_name).write_text(''.join(logs), encoding='utf-8')
        (here / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2),
                                         encoding='utf-8')


if __name__ == '__main__':
    main()
