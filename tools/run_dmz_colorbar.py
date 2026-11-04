"""Build the independent DMZ-EG4S20 colorbar test with the installed TD."""
import argparse
import hashlib
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--td-executable", type=Path)
    args = parser.parse_args()
    executable = args.td_executable or Path(
        shutil.which("td_commands_prompt.exe")
        or r"C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\td_commands_prompt.exe"
    )
    if not executable.is_file():
        parser.error("TD executable was not found; use --td-executable")
    script = (ROOT / "build_dmz_colorbar.tcl").as_posix()
    if any(character in script for character in "{}\r\n"):
        parser.error("The project path cannot contain braces or newlines")
    reports = ROOT / "reports"
    reports.mkdir(exist_ok=True)
    log_path = reports / "dmz_colorbar_build_latest.log"
    command = (
        "if {[catch {source {" + script + "}} dmz_build_error]} "
        '{puts stderr "DMZ_BUILD_FAILED: $dmz_build_error"; exit 1}\n'
    )
    with log_path.open("w", encoding="utf-8") as log:
        process = subprocess.Popen(
            [str(executable)], cwd=ROOT, stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, encoding="utf-8", errors="replace",
        )
        process.stdin.write(command)
        process.stdin.close()
        for line in process.stdout:
            print(line, end="", flush=True)
            log.write(line)
            log.flush()
        result = process.wait()
    output = log_path.read_text(encoding="utf-8")
    if (result or re.search(r"DMZ_BUILD_FAILED:|(?im:^\s*(?:[A-Z]+-\d+\s*:?\s*)?ERROR\b)", output)
            or not re.search(r"(?m)^DMZ_COLORBAR_BUILD_FINISHED\s*$", output)
            or not re.search(r"(?m)^HDMI_TIMING_PASSED ", output)):
        print(f"DMZ build failed. See {log_path}; an existing bit may be from an earlier run.")
        return 1
    bit = ROOT / "DMZ_HDMI_COLORBAR.bit"
    if not bit.is_file() or not bit.stat().st_size:
        print("DMZ build did not produce a bitstream")
        return 1
    digest = hashlib.sha256(bit.read_bytes()).hexdigest()
    print(f"DMZ_BUILD_PASSED {bit} bytes={bit.stat().st_size} sha256={digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
