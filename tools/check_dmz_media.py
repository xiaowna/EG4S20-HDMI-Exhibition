"""Check DMZ media project structure and the evidence required for a bitstream."""
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.check_project import check_project, require

TF_PORTS = {"sd_sck", "sd_mosi", "sd_miso", "sd_cs"}


def check_dmz_media(root=ROOT, *, require_hardware=False):
    root = Path(root).resolve()
    result = check_project(root, project="DMZ_HDMI_MEDIA.al", top="dmz_hdmi_media_top",
                           adc_file="dmz_media.adc", sdc_file="dmz_media.sdc",
                           allowed_missing_ports=TF_PORTS)
    hardware = json.loads((root / "dmz_media_hardware.json").read_text(encoding="utf-8-sig"))
    pending = [name for name in ("mapping_reviewed", "electrical_reviewed", "sd_timing_reviewed")
               if hardware.get(name) is not True]
    if not isinstance(hardware.get("expansion_model"), str) or not hardware["expansion_model"].strip():
        pending.append("expansion_model")
    if result["unassigned_ports"]:
        pending.append("TF pins: " + ", ".join(result["unassigned_ports"]))
    adc = (root / "dmz_media.adc").read_text(encoding="utf-8-sig")
    if "DMZ_MEDIA_HARDWARE_INCOMPLETE" in adc:
        pending.append("ADC hardware guard")
    result["hardware_pending"] = pending
    require(not require_hardware or not pending,
            "DMZ hardware is incomplete; bitstream build is blocked: " + "; ".join(pending))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--require-hardware", action="store_true")
    args = parser.parse_args()
    try:
        result = check_dmz_media(args.root, require_hardware=args.require_hardware)
    except (OSError, ValueError, KeyError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    print(f"DMZ_PROJECT_STRUCTURE_PASSED: {result}")
    if result["hardware_pending"]:
        print("Logic validation only; this project is not ready to generate or download a bitstream.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
