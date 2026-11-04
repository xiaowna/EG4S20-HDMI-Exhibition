"""Verify the DMZ colorbar raster and top-level reset/LED integration."""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--tool-dir', type=Path, required=True)
tools = parser.parse_args().tool_dir.resolve()

with tempfile.TemporaryDirectory(prefix='dmz_colorbar_') as temporary:
    for top, filenames, marker in [
        ('tb_dmz_colorbar_video', ['dmz_colorbar_video.v'], 'PASS DMZ colorbar:'),
        ('tb_dmz_hdmi_colorbar_top', ['dmz_colorbar_video.v', 'dmz_hdmi_colorbar_top.v',
                                    'tmds_channels.v', 'tmds_encoder.v', 'tmds_ddr_tx.v'],
         'PASS DMZ top:'),
    ]:
        image = Path(temporary) / (top + '.vvp')
        commands = [
            [tools / 'iverilog.exe', '-g2012', '-s', top, '-o', image,
             *[ROOT / 'rtl' / name for name in filenames], HERE / (top + '.sv')],
            [tools / 'vvp.exe', image],
        ]
        for index, command in enumerate(commands):
            result = subprocess.run(list(map(str, command)), capture_output=True,
                                    text=True, encoding='utf-8', errors='replace', timeout=180)
            output = result.stdout + result.stderr
            print(output, end='', flush=True)
            if result.returncode or 'FATAL' in output or (index == 1 and marker not in output):
                raise SystemExit(1)
