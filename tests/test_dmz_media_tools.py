"""DMZ 构建防错回归；硬件映射与 TD 产物均在临时副本中模拟。"""
from contextlib import redirect_stderr, redirect_stdout
from functools import partial
from pathlib import Path
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import tkinter
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.check_dmz_media import TF_PORTS, check_dmz_media
from tools.check_project import check_project
from tools import run_dmz_media

TIMING_REPORT = """Top Model : dmz_hdmi_media_top
Device : EG4S20BG256
Confidence : Routed
SWNS: 0.817ns, STNS: 0.000ns
HWNS: 0.060ns, HTNS: 0.000ns
Period Check WNS: 0.000ns
"""
CDC_REPORT = """9 9 0 0 set_max_delay -from {u_player/u_media/u_display/u_prefetch/u_fifo/wg[*]}
9 9 0 0 set_max_delay -from {u_player/u_media/u_display/u_prefetch/u_fifo/rg[*]}
12 12 0 0 set_max_delay -from {av/fifo/wr_gray[*]}
12 12 0 0 set_max_delay -from {av/fifo/rd_gray[*]}
SWNS: 0.100ns HWNS: 0.100ns
SWNS: 0.100ns HWNS: 0.100ns
SWNS: 0.100ns HWNS: 0.100ns
SWNS: 0.100ns HWNS: 0.100ns
"""
BUILD_PASSES = ("HDMI_TIMING_PASSED SWNS=0.817ns HWNS=0.060ns\n"
                "DMZ_CDC_CONSTRAINTS_PASSED 9 9 12 12\n")


class FakeTD:
    """Only replace the process boundary; real project and manifest checks run."""
    def __init__(self, output, returncode=0):
        self.stdin = io.StringIO()
        self.stdout = io.StringIO(output)
        self.returncode = returncode

    def wait(self):
        return self.returncode


class DmzMediaChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="dmz media test ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in ("DMZ_HDMI_MEDIA.al", "dmz_media.adc", "dmz_media.sdc",
                     "dmz_media_hardware.json", "sources.txt", "build_dmz_media.tcl"):
            shutil.copy2(ROOT / name, self.root / name)
        shutil.copytree(ROOT / "rtl", self.root / "rtl")
        shutil.copytree(ROOT / "tools", self.root / "tools",
                        ignore=shutil.ignore_patterns("__pycache__"))
        self.edit("DMZ_HDMI_MEDIA.al", ROOT.as_posix(), self.root.as_posix())
        self.draft_adc = (self.root / "dmz_media.adc").read_text(encoding="utf-8-sig")
        self.draft_hardware = (self.root / "dmz_media_hardware.json").read_text(encoding="utf-8-sig")

    def edit(self, name, old, new):
        path = self.root / name
        text = path.read_text(encoding="utf-8-sig")
        self.assertIn(old, text)
        path.write_text(text.replace(old, new), encoding="utf-8")

    def prepare_hardware(self, *, pins=True, reviewed=True, guard=False):
        # TEST_PAD_* is deliberately fictitious: never infer real TF locations.
        adc = self.draft_adc
        if not guard:
            adc = re.sub(r"^error \{[^\n]*\}\s*\n", "", adc, flags=re.M)
        if pins:
            adc += "\n" + "\n".join(
                f"set_pin_assignment {{ {port} }} {{ LOCATION = TEST_PAD_{index}; IOSTANDARD = LVCMOS33; }}"
                for index, port in enumerate(sorted(TF_PORTS))) + "\n"
        (self.root / "dmz_media.adc").write_text(adc, encoding="utf-8")
        hardware = json.loads(self.draft_hardware)
        if reviewed:
            hardware.update(mapping_reviewed=True, electrical_reviewed=True,
                            sd_timing_reviewed=True, expansion_model="synthetic test fixture")
        (self.root / "dmz_media_hardware.json").write_text(json.dumps(hardware), encoding="utf-8")

    def run_launcher(self, action=None, *, output="", returncode=0, start=None):
        arguments = ["run_dmz_media.py", "--td-executable", sys.executable]
        if action is not None:
            arguments += ["--action", action]
        out, err = io.StringIO(), io.StringIO()

        def launch(*args, **kwargs):
            if start:
                return start(*args, **kwargs)
            return FakeTD(output, returncode)

        with patch.object(run_dmz_media, "ROOT", self.root), \
                patch.object(run_dmz_media, "source_hashes", partial(run_dmz_media.source_hashes, self.root)), \
                patch.object(run_dmz_media, "check_dmz_media", partial(check_dmz_media, self.root)), \
                patch.object(sys, "argv", arguments), \
                patch.object(run_dmz_media.subprocess, "Popen", side_effect=launch) as process, \
                redirect_stdout(out), redirect_stderr(err):
            result = run_dmz_media.main()
        manifest = json.loads((self.root / "reports" / f"dmz_media_{action or 'build'}_manifest.json").read_text(encoding="utf-8"))
        return result, process, manifest, out.getvalue() + err.getvalue()

    def tcl(self, *, action=None, generate_bit=False):
        before = Path.cwd()
        self.addCleanup(os.chdir, before)
        interp = tkinter.Tcl()
        self.set_tcl_env(interp, "DMZ_MEDIA_PYTHON", sys.executable)
        interp.createcommand("puts", lambda *args: "")
        if action is not None:
            interp.setvar("dmz_media_action", action)
        calls = []
        for name in ("import_device", "open_project", "elaborate", "read_adc", "read_sdc",
                     "optimize_rtl", "optimize_gate", "export_db", "place", "route", "fix_hold",
                     "report_area", "report_timing_summary", "report_timing_exception", "bitgen"):
            def record(*args, command=name):
                calls.append((command, args))
                if command == "report_timing_summary":
                    Path(args[args.index("-file") + 1]).write_text(TIMING_REPORT)
                if command == "report_timing_exception":
                    Path(args[args.index("-file") + 1]).write_text(CDC_REPORT)
                if command == "bitgen" and generate_bit:
                    Path(args[args.index("-bit") + 1]).write_bytes(b"current synthetic bitstream")
                return ""
            interp.createcommand(name, record)
        # A returning exit mock would accidentally continue into the next action.
        interp.eval("proc exit args { return -code error DMZ_TEST_EXIT }")
        return interp, calls

    def set_tcl_env(self, interp, name, value):
        variable = f"env({name})"
        if interp.call("info", "exists", variable):
            self.addCleanup(interp.setvar, variable, interp.getvar(variable))
        else:
            self.addCleanup(interp.call, "unset", "-nocomplain", variable)
        interp.setvar(variable, value)

    def test_draft_structure_reports_all_pending_hardware(self):
        result = check_dmz_media(self.root)
        self.assertEqual(result["top_ports"], 16)
        self.assertEqual(set(result["unassigned_ports"]), TF_PORTS)
        pending = result["hardware_pending"]
        for item in ("mapping_reviewed", "electrical_reviewed", "sd_timing_reviewed",
                     "expansion_model", "ADC hardware guard"):
            self.assertIn(item, pending)
        self.assertTrue(any(item.startswith("TF pins:") for item in pending))
        child = subprocess.run([sys.executable, str(self.root / "tools/check_dmz_media.py")],
                               capture_output=True, text=True, timeout=30)
        self.assertEqual(child.returncode, 0, child.stdout + child.stderr)
        self.assertIn("DMZ_PROJECT_STRUCTURE_PASSED", child.stdout)
        self.assertIn("not ready", child.stdout)

    def test_tf_exception_does_not_allow_missing_core_or_unknown_ports(self):
        self.edit("dmz_media.adc", "set_pin_assignment { rst_n }", "# set_pin_assignment { rst_n }")
        with self.assertRaisesRegex(ValueError, "未约束=.*rst_n"):
            check_dmz_media(self.root)
        (self.root / "dmz_media.adc").write_text(self.draft_adc, encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "端口不存在"):
            check_project(self.root, project="DMZ_HDMI_MEDIA.al", top="dmz_hdmi_media_top",
                          adc_file="dmz_media.adc", sdc_file="dmz_media.sdc",
                          allowed_missing_ports=TF_PORTS | {"unknown_signal"})

    def test_tf_exception_does_not_allow_pin_conflicts_or_extra_constraints(self):
        self.edit("dmz_media.adc", "LOCATION = B14", "LOCATION = R7")
        with self.assertRaisesRegex(ValueError, "物理管脚冲突"):
            check_dmz_media(self.root)
        (self.root / "dmz_media.adc").write_text(self.draft_adc, encoding="utf-8")
        self.edit("dmz_media.adc", "{ led[0] }", "{ unknown_signal }")
        with self.assertRaisesRegex(ValueError, "多余约束=.*unknown_signal"):
            check_dmz_media(self.root)

    def test_default_build_stops_before_td_when_any_hardware_gate_is_pending(self):
        cases = {"missing_tf": dict(pins=False), "unreviewed": dict(reviewed=False),
                 "adc_guard": dict(guard=True)}
        for name, options in cases.items():
            with self.subTest(gate=name):
                self.prepare_hardware(**options)
                result, process, manifest, output = self.run_launcher()
                self.assertEqual(result, 1, output)
                process.assert_not_called()
                self.assertEqual(manifest["status"], "failed")
                self.assertIsNone(manifest["bitstream"])
                self.assertIn("hardware is incomplete", manifest["error"])

    def test_adc_guard_prevents_gui_constraint_execution(self):
        interp = tkinter.Tcl()
        assignments = []
        interp.createcommand("set_pin_assignment", lambda *args: assignments.append(args))
        with self.assertRaisesRegex(tkinter.TclError, "DMZ_MEDIA_HARDWARE_INCOMPLETE"):
            interp.call("source", str(self.root / "dmz_media.adc"))
        self.assertEqual(assignments, [])

    def test_tcl_default_build_blocks_before_any_td_commands(self):
        interp, calls = self.tcl()
        with self.assertRaisesRegex(tkinter.TclError, "bitstream build is blocked"):
            interp.call("source", str(self.root / "build_dmz_media.tcl"))
        self.assertEqual(calls, [])

    def test_tcl_draft_logic_actions_never_reach_physical_build(self):
        for action in ("check", "synthesize"):
            with self.subTest(action=action):
                interp, calls = self.tcl(action=action)
                with self.assertRaisesRegex(tkinter.TclError, "DMZ_TEST_EXIT"):
                    interp.call("source", str(self.root / "build_dmz_media.tcl"))
                names = [name for name, _ in calls]
                self.assertIn("elaborate", names)
                self.assertEqual("optimize_gate" in names, action == "synthesize")
                for forbidden in ("read_adc", "read_sdc", "place", "route", "bitgen"):
                    self.assertNotIn(forbidden, names)
                opened = next(args[0] for name, args in calls if name == "open_project")
                self.assertEqual(Path(opened).resolve(), self.root / "DMZ_HDMI_MEDIA.al")

    def test_tcl_missing_current_bitstream_keeps_old_bit(self):
        self.prepare_hardware()
        old_bit = self.root / "DMZ_HDMI_MEDIA.bit"
        old_bit.write_bytes(b"previous bitstream")
        interp, calls = self.tcl()
        with self.assertRaisesRegex(tkinter.TclError, "did not generate"):
            interp.call("source", str(self.root / "build_dmz_media.tcl"))
        names = [name for name, _ in calls]
        self.assertIn("bitgen", names)
        self.assertLess(names.index("fix_hold"), names.index("bitgen"))
        self.assertEqual(old_bit.read_bytes(), b"previous bitstream")

        # Tcl generates a new pending artifact; only the verified runner publishes it.
        interp, calls = self.tcl(generate_bit=True)
        with self.assertRaisesRegex(tkinter.TclError, "DMZ_TEST_EXIT"):
            interp.call("source", str(self.root / "build_dmz_media.tcl"))
        generated = next(args[args.index("-bit") + 1] for name, args in calls if name == "bitgen")
        self.assertEqual((self.root / generated).read_bytes(), b"current synthetic bitstream")
        self.assertEqual(old_bit.read_bytes(), b"previous bitstream")

    def test_tcl_refuses_an_existing_pending_bit_before_bitgen(self):
        self.prepare_hardware()
        interp, calls = self.tcl(generate_bit=True)
        self.set_tcl_env(interp, "DMZ_MEDIA_RUN_ID", "test_current_run")
        pending = self.root / "DMZ_HDMI_MEDIA.pending.test_current_run.bit"
        pending.write_bytes(b"stale pending bitstream")
        with self.assertRaisesRegex(tkinter.TclError, "pending bitstream already exists"):
            interp.call("source", str(self.root / "build_dmz_media.tcl"))
        self.assertNotIn("bitgen", [name for name, _ in calls])
        self.assertEqual(pending.read_bytes(), b"stale pending bitstream")

    def test_launcher_rejects_zero_exit_without_correct_completion_or_with_td_error(self):
        marker = run_dmz_media.MARKERS["synthesize"]
        cases = (("ordinary output\n", 0),
                 (run_dmz_media.MARKERS["check"] + "\n", 0),
                 ("ERROR: synthesis failed\n" + marker + "\n", 0),
                 (marker + "\n", 2))
        for output, returncode in cases:
            with self.subTest(output=output, returncode=returncode):
                result, process, manifest, captured = self.run_launcher(
                    "synthesize", output=output, returncode=returncode)
                self.assertEqual(result, 1, captured)
                process.assert_called_once()
                self.assertEqual(manifest["status"], "failed")
                self.assertIsNone(manifest["bitstream"])

    def test_launcher_logic_success_still_reports_hardware_pending(self):
        result, _, manifest, output = self.run_launcher(
            "synthesize", output=run_dmz_media.MARKERS["synthesize"] + "\n")
        self.assertEqual(result, 0, output)
        self.assertEqual(manifest["status"], "passed")
        self.assertIsNone(manifest["bitstream"])
        self.assertEqual(set(manifest["project_check"]["unassigned_ports"]), TF_PORTS)
        self.assertTrue(manifest["project_check"]["hardware_pending"])

    def test_launcher_cannot_accept_old_bit_from_completion_and_timing_markers(self):
        self.prepare_hardware()
        old_bit = self.root / "DMZ_HDMI_MEDIA.bit"
        old_bit.write_bytes(b"previous bitstream")
        output = BUILD_PASSES + run_dmz_media.MARKERS["build"] + "\n"
        result, _, manifest, captured = self.run_launcher("build", output=output)
        self.assertEqual(result, 1, captured)
        self.assertEqual(manifest["status"], "failed")
        self.assertIsNone(manifest["bitstream"])
        self.assertIn("old bit is not accepted", manifest["error"])
        self.assertEqual(old_bit.read_bytes(), b"previous bitstream")

    def test_launcher_publishes_only_a_verified_current_run_bitstream(self):
        self.prepare_hardware()
        old_bit = self.root / "DMZ_HDMI_MEDIA.bit"
        contents = b"current synthetic bitstream"
        for case in ("wrong_run_id", "wrong_size", "valid"):
            with self.subTest(case=case):
                old_bit.write_bytes(b"previous bitstream")

                def start(*args, **kwargs):
                    run_id = kwargs["env"]["DMZ_MEDIA_RUN_ID"]
                    (self.root / f"DMZ_HDMI_MEDIA.pending.{run_id}.bit").write_bytes(contents)
                    marker_run = "previous_run" if case == "wrong_run_id" else run_id
                    marker_size = len(contents) + (1 if case == "wrong_size" else 0)
                    return FakeTD(BUILD_PASSES + f"DMZ_MEDIA_BITSTREAM_GENERATED {marker_run} {marker_size}\n"
                                  + run_dmz_media.MARKERS["build"] + "\n")

                result, _, manifest, captured = self.run_launcher("build", start=start)
                if case != "valid":
                    self.assertEqual(result, 1, captured)
                    self.assertEqual(manifest["status"], "failed")
                    self.assertIsNone(manifest["bitstream"])
                    self.assertEqual(old_bit.read_bytes(), b"previous bitstream")
                else:
                    self.assertEqual(result, 0, captured)
                    self.assertEqual(old_bit.read_bytes(), contents)
                    self.assertEqual(manifest["status"], "passed")
                    self.assertEqual(manifest["bitstream"]["bytes"], len(contents))
                    self.assertEqual(manifest["bitstream"]["sha256"], hashlib.sha256(contents).hexdigest())
                    self.assertFalse((self.root / f"DMZ_HDMI_MEDIA.pending.{manifest['run_id']}.bit").exists())


if __name__ == "__main__":
    unittest.main()
