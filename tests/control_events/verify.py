"""Check command arbitration and cycle-equivalence with the frozen O12 controller."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-dir', type=Path, required=True)
    args = parser.parse_args()
    here = Path(__file__).resolve().parent
    root = here.parents[1]
    reference = here / 'reference/media_adjust_control_o12.v'
    metadata = json.loads((here / 'reference/source.json').read_text(encoding='utf-8'))
    assert hashlib.sha256(reference.read_bytes()).hexdigest() == metadata['reference_sha256']
    unit_sources = [root / 'rtl/media_control_events.v', here / 'tb_control_events.sv']
    equivalence_sources = [root / 'rtl/media_control_events.v', root / 'rtl/media_adjust_control.v',
                           reference, here / 'tb_control_equivalence.sv']
    sources = set(unit_sources + equivalence_sources)
    hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
    logs = [json.dumps({'sources': hashes, 'reference': metadata}, ensure_ascii=False, indent=2) + '\n']
    try:
        with tempfile.TemporaryDirectory(prefix='hdmi_control_events_') as temporary:
            for top, files, marker in [
                ('tb_control_events', unit_sources, 'PASS control_events: 8192'),
                ('tb_control_equivalence', equivalence_sources, 'PASS control_equivalence: 8000'),
            ]:
                simulation = Path(temporary) / (top + '.vvp')
                commands = [
                    [args.tool_dir / 'iverilog.exe', '-g2012', '-s', top, '-o', simulation, *files],
                    [args.tool_dir / 'vvp.exe', simulation],
                ]
                for index, command in enumerate(commands):
                    result = subprocess.run(list(map(str, command)), cwd=root, capture_output=True,
                                            text=True, encoding='utf-8', errors='replace', timeout=180)
                    output = result.stdout + result.stderr
                    logs.append(output)
                    print(output, end='', flush=True)
                    if result.returncode or 'FATAL' in output or (index == 1 and marker not in output):
                        raise RuntimeError(f'Control-event verification failed: {top}')
        assert all(hashlib.sha256(Path(path).read_bytes()).hexdigest() == value
                   for path, value in hashes.items()), 'Source changed during verification'
        logs.append('PASS: control-event arbitration and frozen-baseline equivalence\n')
        print(logs[-1], end='', flush=True)
    finally:
        (here / 'regression.log').write_text(''.join(logs), encoding='utf-8')


if __name__ == '__main__':
    main()
