"""独立验证视频滚动字幕，不依赖板级顶层。"""
from pathlib import Path
import argparse
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--tool-dir", type=Path, help="包含 iverilog.exe 和 vvp.exe 的目录")
args = parser.parse_args()

test_dir = Path(__file__).resolve().parent
root = test_dir.parents[1]
iverilog = args.tool_dir / "iverilog.exe" if args.tool_dir else shutil.which("iverilog")
vvp = args.tool_dir / "vvp.exe" if args.tool_dir else shutil.which("vvp")
if not iverilog or not vvp:
    parser.error("找不到 Icarus Verilog；请传入 --tool-dir")

output = test_dir / "check.vvp"
try:
    subprocess.run(
        [str(iverilog), "-g2012", "-s", "tb_video_scroll_osd", "-o", str(output),
         str(root / "rtl/video_scroll_osd.v"), str(test_dir / "tb_video_scroll_osd.sv")],
        cwd=test_dir, check=True, timeout=30,
    )
    subprocess.run([str(vvp), str(output)], cwd=test_dir, check=True, timeout=60)
finally:
    output.unlink(missing_ok=True)
