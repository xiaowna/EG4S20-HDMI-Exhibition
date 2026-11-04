"""验证板级帧尺寸和小帧尺寸的双缓冲地址边界。"""
from pathlib import Path
import argparse
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--tool-dir', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
logs = []
with tempfile.TemporaryDirectory() as tmp:
    for pixels in (24, 640 * 480):
        image = Path(tmp) / 'address.vvp'
        subprocess.run([str(args.tool_dir / 'iverilog.exe'), '-g2012', '-s',
                        'tb_frame_address_bounds', '-P', f'tb_frame_address_bounds.PIXELS={pixels}',
                        '-o', str(image), str(root / 'rtl/frame_buffer_manager.v'),
                        str(root / 'tests/tb_frame_address_bounds.sv')], check=True, timeout=30)
        result = subprocess.run([str(args.tool_dir / 'vvp.exe'), str(image)],
                                capture_output=True, text=True, timeout=60)
        logs.append(result.stdout + result.stderr)
        print(logs[-1], end='')
        result.check_returncode()
(root / 'reports/frame_address_regression.txt').write_text(''.join(logs), encoding='utf-8')
