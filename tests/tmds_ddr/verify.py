"""当前 TMDS DDR 串行器的转发时钟和连续符号位序回归。"""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--tool-dir', type=Path, required=True)
tools = parser.parse_args().tool_dir.resolve()
with tempfile.TemporaryDirectory(prefix='hdmi_tmds_') as temporary:
    image = Path(temporary) / 'tmds.vvp'
    for command in [
        [tools / 'iverilog.exe', '-g2012', '-s', 'tb_tmds_ddr_tx', '-o', image,
         ROOT / 'rtl/tmds_ddr_tx.v', Path(__file__).resolve().with_name('tb_tmds_ddr_tx.sv')],
        [tools / 'vvp.exe', image],
    ]:
        result = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=30)
        output = result.stdout + result.stderr
        print(output, end='')
        if result.returncode or 'FATAL' in output:
            raise SystemExit(1)
