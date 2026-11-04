"""Check long FAT chains with the file-size bound and no fixed cluster cap."""

import argparse
from pathlib import Path
import subprocess
import tempfile


base = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--tool-dir", type=Path, required=True)
tool_dir = parser.parse_args().tool_dir.resolve()
rtl = base.parents[1] / "rtl" / "fat32_file_reader.v"

with tempfile.TemporaryDirectory(prefix="cluster_limit_") as work:
    image = Path(work) / "cluster_limit.vvp"
    compile_result = subprocess.run(
        [str(tool_dir / "iverilog.exe"), "-g2012", "-s", "tb_cluster_limit",
         "-o", str(image), str(rtl), str(base / "tb_cluster_limit.sv")],
        cwd=base, capture_output=True, text=True,
    )
    if compile_result.returncode:
        raise SystemExit(compile_result.stdout + compile_result.stderr)
    for mode in range(3):
        result = subprocess.run(
            [str(tool_dir / "vvp.exe"), str(image), f"+MODE={mode}"],
            cwd=base, capture_output=True, text=True,
        )
        print(result.stdout + result.stderr, end="")
        if result.returncode or "FATAL:" in result.stdout:
            raise SystemExit(f"Cluster-limit mode {mode} failed")
