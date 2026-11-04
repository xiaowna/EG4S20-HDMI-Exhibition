"""Verify the DMZ core-board four-digit 1234 scanning test."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--tool-dir', type=Path, required=True)
tools = parser.parse_args().tool_dir.resolve()

with tempfile.TemporaryDirectory(prefix='dmz_seg_') as temporary:
    image = Path(temporary) / 'dmz_seg.vvp'
    commands = [
        [tools / 'iverilog.exe', '-g2012', '-s', 'tb_dmz_seg_test_top', '-o', image,
         ROOT / 'rtl/dmz_seg_test_top.v', HERE / 'tb_dmz_seg_test_top.sv'],
        [tools / 'vvp.exe', image],
    ]
    for index, command in enumerate(commands):
        result = subprocess.run(list(map(str, command)), capture_output=True,
                                text=True, encoding='utf-8', errors='replace', timeout=120)
        output = result.stdout + result.stderr
        print(output, end='', flush=True)
        if result.returncode or 'FATAL' in output or (
                index == 1 and 'PASS DMZ seven-segment:' not in output):
            raise SystemExit(1)
