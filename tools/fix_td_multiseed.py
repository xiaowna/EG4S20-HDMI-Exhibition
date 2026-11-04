"""Repair TD 6.2.168116's unquoted MultiSeed phyPath; preserve the original."""
import argparse
import hashlib
from pathlib import Path
import sys


ORIGINAL_SHA256 = "7a34989a626419fa97b15e9e69fbb42db1232d0e757e799a85740adc96e899e2"
SOURCE = b"source ./settings.cfg"
MARKER = b"# HDMI_TD_MULTISEED_PATH_FIX_V1"
# TD generates an unquoted absolute phyPath in each seed's settings.cfg.
# Quote that existing directory as one Tcl value before the original source.
# Already quoted paths and every other setting retain their original meaning.
PATCH = r'''# HDMI_TD_MULTISEED_PATH_FIX_V1
set hdmi_cfg_channel [open ./settings.cfg r]
set hdmi_cfg_text [read $hdmi_cfg_channel]
close $hdmi_cfg_channel
if {[regexp -line {^set phyPath ([^\r\n]+)} $hdmi_cfg_text hdmi_cfg_line hdmi_cfg_path] &&
    [file isdirectory $hdmi_cfg_path]} {
  set hdmi_cfg_text [string map [list $hdmi_cfg_line [list set phyPath $hdmi_cfg_path]] $hdmi_cfg_text]
  set hdmi_cfg_channel [open ./settings.cfg w]
  puts -nonewline $hdmi_cfg_channel $hdmi_cfg_text
  close $hdmi_cfg_channel
}
unset hdmi_cfg_channel hdmi_cfg_text
unset -nocomplain hdmi_cfg_line hdmi_cfg_path
source ./settings.cfg'''.encode("ascii")


def patched_script(original):
    # A narrowly scoped GUI dispatcher may coexist in vendor editable zones.
    # Validate its exact blocks and the original vendor version independently.
    if b'HDMI_GUI_DISPATCH_V1' in original:
        if __package__:
            from .td_gui_profile import remove_dispatch
        else:
            from td_gui_profile import remove_dispatch
        stripped = remove_dispatch(original)
        patched_script(stripped)
        if MARKER not in stripped:
            raise ValueError('GUI dispatcher requires the existing path repair')
        return original
    newline = b"\r\n" if b"\r\n" in original else b"\n"
    patch = PATCH.replace(b"\n", newline)
    if MARKER in original:
        restored = original.replace(patch, SOURCE, 1)
        if original.count(patch) != 1 or hashlib.sha256(restored).hexdigest() != ORIGINAL_SHA256:
            raise ValueError("Unknown modified MultiSeed.tcl version; no file was changed")
        return original
    if hashlib.sha256(original).hexdigest() != ORIGINAL_SHA256:
        raise ValueError("Unknown MultiSeed.tcl version; no file was changed")
    if original.count(SOURCE) != 1:
        raise ValueError("Expected exactly one settings source; no file was changed")
    return original.replace(SOURCE, patch, 1)


def install(script):
    original = script.read_bytes()
    patched = patched_script(original)
    if patched == original:
        return "already installed"
    backup = script.with_name(script.name + ".before_hdmi_path_fix_20261019")
    if backup.exists():
        if backup.read_bytes() != original:
            raise ValueError("Existing backup differs; no file was changed")
    else:
        backup.write_bytes(original)
    script.write_bytes(patched)
    if script.read_bytes() != patched:
        raise OSError("Patched file readback mismatch")
    return f"installed; original saved at {backup}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--td-root", type=Path,
                        default=Path("C:/Anlogic/TD_6.2.1_Engineer_6.2.168.116"))
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    script = args.td_root / "doc/scripts/MultiSeed.tcl"
    try:
        if args.check:
            content = script.read_bytes()
            patched_script(content)
            if MARKER not in content:
                raise ValueError("MultiSeed path repair is not installed")
            print("TD_MULTISEED_PATH_FIX_PRESENT")
        else:
            print(install(script))
    except (OSError, ValueError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
