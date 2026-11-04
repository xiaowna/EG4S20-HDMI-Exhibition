"""验证 SDRAM 忙事务跨刷新期限时的优先级。"""
from pathlib import Path
import argparse
import subprocess
import tempfile

p = argparse.ArgumentParser()
p.add_argument('--tool-dir', type=Path, required=True)
a = p.parse_args()
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
    image = Path(tmp) / 'refresh.vvp'
    subprocess.run([str(a.tool_dir / 'iverilog.exe'), '-g2012', '-s',
                    'tb_sdram_refresh_deadline', '-o', str(image),
                    str(root / 'rtl/em638325_stream_controller.v'),
                    str(root / 'tests/tb_sdram_refresh_deadline.sv')], check=True)
    subprocess.run([str(a.tool_dir / 'vvp.exe'), str(image)], check=True)
