"""主链路回归；工具目录可用 --tool-dir、IVERILOG_BIN 或 PATH 指定。"""
from pathlib import Path
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

from tools.check_project import check_logic_project, check_project

ROOT = Path(__file__).resolve().parent


def find_tool(name, directory):
    executable = name + (".exe" if os.name == "nt" else "")
    path = (directory / executable) if directory else shutil.which(executable)
    if not path or not Path(path).is_file():
        raise FileNotFoundError(f"找不到 {executable}；请使用 --tool-dir 指定 Icarus Verilog 的 bin 目录")
    return str(Path(path).resolve())


def run_command(command, cwd, logs):
    result = subprocess.run(list(map(str, command)), cwd=cwd, capture_output=True,
                            text=True, errors="replace", timeout=600)
    output = result.stdout + result.stderr
    logs.append(output)
    print(output, end="", flush=True)
    if result.returncode != 0 or "FATAL" in output:
        raise RuntimeError(f"命令失败（退出码 {result.returncode}）：{command[0]}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--full", action="store_true", help="额外仿真三帧 640×480 图像，耗时数分钟")
    parser.add_argument("--tool-dir", type=Path, default=os.environ.get("IVERILOG_BIN"))
    parser.add_argument("--logic-only", action="store_true", help="逻辑仿真预检只允许 TF 四线映射待确认")
    args = parser.parse_args()
    logs = []
    try:
        checker = check_logic_project if args.logic_only else check_project
        logs.append(f"工程检查：{checker(ROOT)}\n")
        directory = args.tool_dir.resolve() if args.tool_dir else None
        compiler = find_tool("iverilog", directory)
        runtime = find_tool("vvp", directory)
        tests = ROOT / "tests"
        rtl = [ROOT / "rtl" / n.strip() for n in (ROOT / "sources.txt").read_text().splitlines() if n.strip()]
        rtl.append(tests / "clock_buffer_model.v")
        model = tests / "em638325_model.sv"
        with tempfile.TemporaryDirectory(prefix="hdmi_verify_") as temporary:
            work = Path(temporary)

            def run(command):
                run_command(command, tests, logs)

            for top, filename, modes in [
                ("tb_stream_memory", "tb_stream_memory.sv", [0]),
                ("tb_playlist", "tb_playlist.sv", [0]),
                ("tb_spc", "tb_spc.sv", [0]),
                ("tb_pipeline", "tb_pipeline.sv", range(8)),
            ]:
                image = work / (top + ".vvp")
                run([compiler, "-g2012", "-s", top, "-o", image, *rtl, model, tests / filename])
                for mode in modes:
                    run([runtime, image, f"+MODE={mode}"])
            for full in ([0, 1] if args.full else [0]):
                image = work / "display.vvp"
                run([compiler, "-g2012", "-s", "tb_full_display", "-P", f"tb_full_display.FULL={full}",
                     "-o", image, *rtl, model, tests / "tb_full_display.sv"])
                run([runtime, image])
            run([compiler, "-g2005", "-s", "sd_media_player", "-o", work / "core.vvp", *rtl, model])
        logs.append("PASS: 主链路回归全部通过\n")
        print(logs[-1], end="")
        return 0
    except (OSError, ValueError, KeyError, ET.ParseError, RuntimeError, subprocess.SubprocessError) as exc:
        logs.append(f"FAIL: {exc}\n")
        print(logs[-1], file=sys.stderr, end="")
        return 1
    finally:
        (ROOT / "reports").mkdir(exist_ok=True)
        (ROOT / "reports" / "verify_results.txt").write_text("\n".join(logs), encoding="utf-8")


if __name__ == "__main__":
    sys.exit(main())
