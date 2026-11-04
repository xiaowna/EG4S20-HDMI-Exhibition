"""Validate or synthesize the DMZ player; build a bit only after hardware review."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.check_dmz_media import check_dmz_media

MARKERS = {
    "check": "DMZ_MEDIA_ELABORATION_FINISHED_NO_BITSTREAM",
    "synthesize": "DMZ_MEDIA_SYNTHESIS_FINISHED_NO_BITSTREAM",
    "build": "DMZ_MEDIA_BUILD_FINISHED",
}


def source_hashes(root=ROOT):
    names = {"DMZ_HDMI_MEDIA.al", "dmz_media_hardware.json", "build_dmz_media.tcl",
             "tools/check_project.py", "tools/check_dmz_media.py", "tools/project_setup.tcl",
             "tools/dmz_media_setup.tcl", "tools/run_dmz_media.py"}
    names.update(re.findall(r'<File\s+Path="([^"]+)"',
                           (root / "DMZ_HDMI_MEDIA.al").read_text(encoding="utf-8-sig")))
    return {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in sorted(names)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--action", choices=MARKERS, default="build")
    parser.add_argument("--td-executable", type=Path)
    args = parser.parse_args()
    reports = ROOT / "reports"
    reports.mkdir(exist_ok=True)
    log_path = reports / f"dmz_media_{args.action}_latest.log"
    manifest_path = reports / f"dmz_media_{args.action}_manifest.json"
    manifest = {"action": args.action, "root": str(ROOT), "status": "failed", "bitstream": None}
    run_id = uuid.uuid4().hex
    manifest["run_id"] = run_id
    try:
        initial = source_hashes()
        manifest["source_sha256"] = initial
        structure = check_dmz_media(require_hardware=args.action == "build")
        manifest["project_check"] = structure
        executable = args.td_executable or Path(
            shutil.which("td_commands_prompt.exe")
            or r"C:\Anlogic\TD_6.2.1_Engineer_6.2.168.116\bin\td_commands_prompt.exe"
        )
        if not executable.is_file():
            raise FileNotFoundError("TD executable was not found; use --td-executable")
        script = (ROOT / "build_dmz_media.tcl").as_posix()
        if any(character in script for character in "{}\r\n"):
            raise ValueError("The project path cannot contain braces or newlines")
        command = (f"set dmz_media_action {args.action}\n"
                   "if {[catch {source {" + script + "}} dmz_media_error]} "
                   '{puts stderr "DMZ_MEDIA_FAILED: $dmz_media_error"; exit 1}\n')
        environment = os.environ.copy()
        environment["DMZ_MEDIA_PYTHON"] = sys.executable
        environment["DMZ_MEDIA_RUN_ID"] = run_id
        with log_path.open("w", encoding="utf-8") as log:
            process = subprocess.Popen([str(executable)], cwd=ROOT, env=environment,
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, text=True,
                                       encoding="utf-8", errors="replace")
            process.stdin.write(command)
            process.stdin.close()
            for line in process.stdout:
                print(line, end="", flush=True)
                log.write(line)
                log.flush()
            result = process.wait()
        output = log_path.read_text(encoding="utf-8")
        if (result or re.search(r"DMZ_MEDIA_FAILED:|(?im:^\s*(?:[A-Z]+-\d+\s*:?\s*)?ERROR\b)", output)
                or not re.search(r"(?m)^" + MARKERS[args.action] + r"\s*$", output)):
            raise RuntimeError(f"TD did not complete {args.action}; see {log_path}")
        if source_hashes() != initial:
            raise RuntimeError("Project sources changed during TD validation; results are not accepted")
        if args.action == "build":
            if (not re.search(r"(?m)^HDMI_TIMING_PASSED ", output)
                    or not re.search(r"(?m)^DMZ_CDC_CONSTRAINTS_PASSED 9 9 12 12\s*$", output)):
                raise RuntimeError("TD did not provide routed timing and CDC pass markers")
            pending_bit = ROOT / f"DMZ_HDMI_MEDIA.pending.{run_id}.bit"
            generated = re.search(r"(?m)^DMZ_MEDIA_BITSTREAM_GENERATED " + run_id + r" ([0-9]+)\s*$", output)
            if (generated is None or not pending_bit.is_file() or not pending_bit.stat().st_size
                    or pending_bit.stat().st_size != int(generated[1])):
                raise RuntimeError("TD did not produce the current run's bitstream; an old bit is not accepted")
            bit = ROOT / "DMZ_HDMI_MEDIA.bit"
            pending_bit.replace(bit)
            manifest["bitstream"] = {"path": str(bit), "bytes": bit.stat().st_size,
                                     "sha256": hashlib.sha256(bit.read_bytes()).hexdigest()}
        manifest["status"] = "passed"
        print(f"DMZ_MEDIA_{args.action.upper()}_PASSED")
        if args.action != "build":
            print("Logic validation passed; no ADC/physical timing/bitstream validation is implied.")
        return 0
    except (OSError, ValueError, KeyError, ET.ParseError, RuntimeError, subprocess.SubprocessError) as exc:
        manifest["error"] = str(exc)
        message = f"DMZ_MEDIA_FAILED: {exc}"
        print(message, file=sys.stderr)
        if "TD did not complete" not in str(exc):
            with log_path.open("a", encoding="utf-8") as log:
                log.write(message + "\n")
        return 1
    finally:
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
