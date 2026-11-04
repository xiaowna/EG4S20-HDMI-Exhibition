"""Check the unregistered product-peripheral pin plan against the current project."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

from check_project import check_project


def require(condition, message):
    if not condition:
        raise ValueError(message)


def assignments(path):
    text = re.sub(r"#[^\n]*", "", path.read_text(encoding="utf-8-sig"))
    ports = {}
    for port, body in re.findall(r"set_pin_assignment\s*\{\s*([^}]+?)\s*\}\s*\{([^}]+)\}", text):
        ball = re.search(r"\bLOCATION\s*=\s*(\w+)\s*;", body)
        standard = re.search(r"\bIOSTANDARD\s*=\s*(\w+)\s*;", body)
        require(ball is not None and standard is not None, f"Incomplete assignment: {port}")
        require(port not in ports, f"Duplicate port: {port}")
        ports[port] = (ball[1].upper(), standard[1])
    require(len({v[0] for v in ports.values()}) == len(ports), "Duplicate package ball")
    return ports


def check_plan(root):
    root = root.resolve()
    project_result = check_project(root)
    plan = json.loads((root / "interfaces/product_io_pins.json").read_text(encoding="utf-8"))
    applied = set(plan.get("active_ports", []))
    require(plan["stage"] in ("pin_definition_only", "sw7_active_peripherals_planned", "encoder_active_peripherals_planned", "infrared_active_rtc_planned", "rtc_active")
            and plan["applied_to_active_project"] == bool(applied), "Inconsistent pin-plan stage")
    left40 = plan.get("rtc_device") == "DS1302"
    require(plan["power"] == ({"3v3": "CORE_LEFT40.1", "ground": "CORE_LEFT40.2"} if left40 else
                             {"3v3": "P5.1", "ground": "P5.3"}), "Unexpected supply pins")
    active = assignments(root / "board.adc")
    planned = {s["port"]: (s["ball"], s["io_standard"]) for s in plan["signals"]}
    signal_count = (8 if plan.get("rtc_device") == "DS1302" else 7) - (0 if plan.get("encoder_enabled", True) else 3)
    if not plan.get("encoder_enabled", True):
        require(not any(port.startswith("encoder_") for port in set(active) | set(planned)),
                "Removed encoder still has active ports or assignments")
    require(len(planned) == len(plan["signals"]) == signal_count, "Unexpected peripheral signal count")
    require(len({v[0] for v in planned.values()}) == signal_count, "Duplicate planned ball")
    require(all(v[1] == "LVCMOS33" for v in planned.values()), "All new IO must use 3.3V")
    require(active.keys() & planned.keys() == applied, "Active ports disagree with the stage contract")
    if plan["stage"] == "encoder_active_peripherals_planned":
        require(applied == {"mode_sw7", "encoder_a", "encoder_b", "encoder_press_n"},
                "Encoder stage must not activate IR or RTC early")
    if plan["stage"] == "infrared_active_rtc_planned":
        require(applied == {"mode_sw7", "encoder_a", "encoder_b", "encoder_press_n", "infrared_n"},
                "Infrared stage must keep RTC pins inactive")
    require(all(active[port] == planned[port] for port in applied), "Active peripheral mapping changed")
    if plan["stage"] == "rtc_active":
        require(applied == set(planned), "RTC stage must activate all planned signals")
    fragment = root / plan["constraint_fragment"]
    require(assignments(fragment) == planned, "ADC example disagrees with the pin manifest")
    project_text = (root / "HDMI_media_board_WAV.al").read_text(encoding="utf-8-sig")
    require(fragment.name not in project_text, "Stage-0 example must remain unregistered")

    report = root / plan["baseline_area_report"]
    area = report.read_text(encoding="utf-8-sig")
    rows = re.findall(r"^\s*(\S+)\s+(?:INPUT|OUTPUT|INOUT)\s+([A-Z]\d+)\s+\w+", area, re.M)
    routed = {name: ball for name, ball in rows}
    require(len(routed) == len(rows), "Duplicate IO names in the routed report")
    require(all(routed.get(port) == ball for port, (ball, _) in active.items() if port not in applied),
            "Routed IO report does not match current board.adc")
    paired = set(plan["reserved_hdmi_negative_balls"])
    require(paired == {"R1", "M1", "N4", "J4"}, "Unexpected HDMI negative pairs")
    require(paired <= set(routed.values()), "Routed report is missing HDMI negative pads")
    occupied = set(routed.values()) | {v[0] for v in active.values()} | paired
    conflicts = {port: ball for port, (ball, _) in planned.items() if ball in occupied and port not in applied}
    require(not conflicts, f"Existing IO conflict: {conflicts}")
    header = [s for s in plan["signals"] if s["connector"] == ("CORE_LEFT40" if left40 else "P5")]
    require(len(header) == signal_count-1 and len({s["header_pin"] for s in header}) == signal_count-1, "Duplicate header pin")
    if left40:
        physical_map = json.loads((root / "interfaces/core_left40_pin_map.json").read_text(encoding="utf-8"))
        require(set(physical_map["pins"]) == {str(n) for n in range(1,41)}, "Incomplete front header map")
        require(all(physical_map["pins"].get(str(s["header_pin"])) == s["ball"] for s in header),
                "Header number does not match the core schematic package ball")
        require([physical_map["pins"][str(n)] for n in [1,2,39,40]] == ["3V3","GND","VBUS","GND"],
                "Wrong header supply/ground mapping")
    left_layout = {"encoder_a":(3,"T4"), "encoder_b":(4,"R5"), "encoder_press_n":(5,"T5"),
                   "infrared_n":(38,"R16"), "rtc_scl":(7,"T7"), "rtc_sda":(8,"T8"), "rtc_ce":(9,"T9")}
    require(all((s["header_pin"],s["ball"]) == left_layout.get(s["port"]) and s["bank"] == 2 for s in header) if left40 else
            all(1 <= s["header_pin"] <= 24 and s["header_pin"] not in (1, 3) and s["bank"] == 3 for s in header),
            "Invalid peripheral header signal allocation")
    if plan.get("rtc_device") == "DS1302":
        rtc = {s["port"]: s for s in plan["signals"] if s["port"].startswith("rtc_")}
        expected = {"rtc_scl": (7,"T7","output","push_pull"),
                    "rtc_sda": (8,"T8","inout","push_pull_or_Z"),
                    "rtc_ce": (9,"T9","output","push_pull")}
        require(set(rtc) == set(expected), "DS1302 needs CLK/DAT/CE")
        for name, values in expected.items():
            require(tuple(rtc[name][k] for k in ("header_pin","ball","direction","drive")) == values,
                    "DS1302 RTC pin/direction mismatch: " + name)
        require(rtc["rtc_sda"].get("pull_type") == "PULLDOWN", "Unplugged DAT must read invalid zero calendar")
    else:
        require(all(s.get("drive") == "open_drain_0_or_Z" for s in plan["signals"]
                    if s["port"] in ("rtc_scl", "rtc_sda")), "I2C RTC must use open-drain IO")
    sources = {}
    for source in plan["sources"]:
        path = Path(source["path"])
        sources[str(path)] = {"sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                              "pages": source["pages"]}
    return {"passed": True, "project": project_result, "planned_signals": len(planned),
            "existing_explicit_ports": len(active), "routed_pads_including_internal_sdram": len(rows),
            "hdmi_negative_pads_checked": sorted(paired), "conflicts": conflicts,
            "example_matches_manifest": True, "example_registered": False, "active_peripheral_ports": sorted(applied),
            "source_pdfs": sources, "hardware_tested": False,
            "limit": "Static consistency and occupancy only; schematic mappings reviewed separately"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        result = check_plan(args.root)
    except (OSError, ValueError, KeyError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
