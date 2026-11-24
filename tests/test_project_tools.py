"""工程防错回归：在临时副本中注入错误，不修改真实源码和约束。"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile
import tkinter
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.check_project import TF_PORTS, check_logic_project, check_project

TIMING_REPORT = """Top Model : hdmi_media_board_top
Device : EG4S20BG256
Confidence : Routed
SWNS: 0.817ns, STNS: 0.000ns
HWNS: 0.060ns, HTNS: 0.000ns
Period Check WNS: 0.000ns
"""


class ProjectChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="hdmi project test ")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for filename in ("HDMI_media_board_WAV.al", "board.adc", "board.sdc", "sources.txt", "build_wav_project.tcl", "fix_wav_gui_route.tcl", "refresh_wav_gui_reports.tcl"):
            shutil.copy2(ROOT / filename, self.root / filename)
        shutil.copytree(ROOT / "rtl", self.root / "rtl")
        shutil.copytree(ROOT / "tools", self.root / "tools", ignore=shutil.ignore_patterns("__pycache__"))
        self.edit("HDMI_media_board_WAV.al", ROOT.as_posix(), self.root.as_posix())
        check_directory = self.root / "tests/audio_source"
        check_directory.mkdir(parents=True)
        shutil.copy2(ROOT / "tests/audio_source/check_board.tcl", check_directory)
        fixture_adc = (self.root / "board.adc").read_text(encoding="utf-8-sig")
        fixture_adc = re.sub(r"^error \{HDMI_BOARD_HARDWARE_INCOMPLETE[^\n]*\}\s*\n", "",
                             fixture_adc, flags=re.M)
        # Build the draft explicitly; the real ADC may already map every TF pin.
        for port in TF_PORTS:
            fixture_adc = re.sub(r"^set_pin_assignment\s*\{\s*" + re.escape(port)
                                 + r"\s*\}[^\n]*(?:\n|$)", "", fixture_adc, flags=re.M)
        self.draft_adc = fixture_adc + (
            "error {HDMI_BOARD_HARDWARE_INCOMPLETE: test fixture with unmapped TF pins.}\n")
        # These locations are fictitious and used only by static/Tcl mock tests.
        self.synthetic_tf = "\n" + "\n".join(
            f"set_pin_assignment {{ {port} }} {{ LOCATION = TEST_PAD_{index}; IOSTANDARD = LVCMOS33; }}"
            for index, port in enumerate(sorted(TF_PORTS))) + "\n"
        completed_adc = fixture_adc + self.synthetic_tf
        (self.root / "board.adc").write_text(completed_adc, encoding="utf-8")

    def edit(self, filename, old, new):
        path = self.root / filename
        text = path.read_text(encoding="utf-8-sig")
        self.assertIn(old, text)
        path.write_text(text.replace(old, new), encoding="utf-8")

    def test_valid_project_in_directory_with_spaces(self):
        self.assertEqual(check_project(self.root)["top_ports"], 27)

    def test_solar_area_strategy_survives_gui_reopen(self):
        for key in ("opt_area", "pack_effort"):
            original = (self.root / "HDMI_media_board_WAV.al").read_text(encoding="utf-8-sig")
            for old, new in ((f"set_param gate {key} high", f"set_param gate {key} medium"),
                             (f"<{key}>high</{key}>" if key == "pack_effort" else "<GateProperty>",
                              f"<{key}>low</{key}>" if key == "pack_effort" else "<GateProperty><opt_area>low</opt_area>")):
                with self.subTest(key=key, field=old):
                    self.edit("HDMI_media_board_WAV.al", old, new)
                    with self.assertRaises(ValueError):
                        check_project(self.root)
                    (self.root / "HDMI_media_board_WAV.al").write_text(original, encoding="utf-8")
        original = (self.root / "HDMI_media_board_WAV.al").read_text(encoding="utf-8-sig")
        for old, new in (("<pr_strategy>5</pr_strategy>", "<pr_strategy>0</pr_strategy>"),
                         ("set_param place pr_strategy 5", "set_param place pr_strategy 0")):
            with self.subTest(physical_profile=old):
                self.edit("HDMI_media_board_WAV.al", old, new)
                with self.assertRaisesRegex(ValueError, "pr_strategy=5"):
                    check_project(self.root)
                (self.root / "HDMI_media_board_WAV.al").write_text(original, encoding="utf-8")

        for name, old, new in [
                ("HDMI_media_board_WAV.al", "<effort>routability</effort>", "<effort>normal</effort>"),
                ("HDMI_media_board_WAV.al", "<param>set_param route effort routability</param>", "<param>set_param route effort normal</param>"),
                ("build_wav_project.tcl", "set_param route effort routability", "set_param route effort normal")]:
            original = (self.root / name).read_text(encoding="utf-8-sig")
            with self.subTest(route_profile=name):
                self.edit(name, old, new)
                with self.assertRaisesRegex(ValueError, "route effort routability"):
                    check_project(self.root)
                (self.root / name).write_text(original, encoding="utf-8")

    def test_duplicate_verilog_compile_order_is_rejected(self):
        self.edit("HDMI_media_board_WAV.al", '<Attr Name="CompileOrder" Val="79"/>',
                  '<Attr Name="CompileOrder" Val="78"/>')
        with self.assertRaisesRegex(ValueError, "CompileOrder"):
            check_project(self.root)

    def test_gui_saved_private_fields_can_reflect_the_checked_database(self):
        self.edit("HDMI_media_board_WAV.al", '<GateProperty>', '<GateProperty><opt_area>high</opt_area>')
        self.edit("HDMI_media_board_WAV.al", '<RouteProperty>', '<RouteProperty><post_route_opt>high</post_route_opt>')
        # TD omits its default strategy field and removes the unsupported
        # runtime strategy GUI annotation when saving; the flow helper enforces it.
        self.edit("HDMI_media_board_WAV.al", '<pr_strategy>5</pr_strategy>', '')
        self.edit("HDMI_media_board_WAV.al", '<param>set_param place pr_strategy 5</param>', '')
        self.assertEqual(check_project(self.root)["top_ports"], 27)

    def test_key01_schematic_pin_mapping(self):
        adc = (self.root / "board.adc").read_text(encoding="utf-8-sig")
        pins = dict(re.findall(r"set_pin_assignment\s*\{\s*(key_\w+\[\d\])\s*\}"
                               r"\s*\{[^}]*LOCATION\s*=\s*(\w+)", adc))
        # Logical row numbers follow the core schematic, not the reversed
        # software indices in the vendor LCD example.
        self.assertEqual(pins, {
            "key_row_n[0]": "E10", "key_row_n[1]": "C10",
            "key_row_n[2]": "F9", "key_row_n[3]": "D9",
            "key_col_n[0]": "E11", "key_col_n[1]": "D11",
            "key_col_n[2]": "C11", "key_col_n[3]": "F10"})
        sdc = (self.root / "board.sdc").read_text(encoding="utf-8-sig")
        self.assertIn("get_ports {key_col_n[0] key_col_n[1] key_col_n[2] key_col_n[3] sd_miso mode_sw7}", sdc)
        self.assertNotRegex(sdc, r"\bkey_(?:next|pause)_n\b")
        self.assertRegex(adc, r"set_pin_assignment\s*\{\s*mode_sw7\s*\}\s*\{\s*LOCATION\s*=\s*A14;\s*IOSTANDARD\s*=\s*LVCMOS33;")

    def test_infrared_pin_pullup_and_async_input_scope(self):
        adc = (self.root / "board.adc").read_text(encoding="utf-8-sig")
        self.assertRegex(adc, r"set_pin_assignment\s*\{\s*infrared_n\s*\}\s*\{\s*LOCATION\s*=\s*R16;\s*IOSTANDARD\s*=\s*LVCMOS33;\s*PULLTYPE\s*=\s*PULLUP;")
        sdc = (self.root / "board.sdc").read_text(encoding="utf-8-sig")
        self.assertIn("set_false_path -from [get_ports infrared_n]", sdc)
        self.assertNotRegex(sdc, r"set_false_path[^\n]*infrared/")
        self.assertEqual(check_project(self.root)["top_ports"], 27)

    def test_encoder_removed_from_board_and_constraints(self):
        for n in ("board.adc", "board.sdc", "rtl/hdmi_media_board_top.v"):
            self.assertNotRegex((self.root / n).read_text(encoding="utf-8-sig"),
                                r"\bencoder_(?:a|b|press_n)\b")
        self.assertNotIn("rtl/media_rotary_encoder.v",
                         (self.root / "HDMI_media_board_WAV.al").read_text(encoding="utf-8-sig"))
        self.assertEqual(check_project(self.root)["top_ports"], 27)

    def test_gui_disabled_multiseed_is_rejected(self):
        self.edit("HDMI_media_board_WAV.al", 'Enable="true"', 'Enable="false"')
        with self.assertRaisesRegex(ValueError, "seed 19"):
            check_project(self.root)

    def test_ds1302_left40_clock_data_enable_pins(self):
        adc = (self.root / "board.adc").read_text(encoding="utf-8-sig")
        for port, ball in {"rtc_scl":"T7", "rtc_sda":"T8", "rtc_ce":"T9"}.items():
            self.assertRegex(adc, r"set_pin_assignment\s*\{\s*"+port+r"\s*\}\s*\{\s*LOCATION\s*=\s*"+ball+r";\s*IOSTANDARD\s*=\s*LVCMOS33;")
        self.assertRegex(adc, r"rtc_sda\s*\}[^\n]*PULLTYPE\s*=\s*PULLDOWN;")
        sdc = (self.root / "board.sdc").read_text(encoding="utf-8-sig")
        self.assertIn("set_false_path -from [get_ports rtc_sda]", sdc)
        self.assertNotRegex(sdc, r"set_false_path[^\n]*(?:rtc_scl|rtc_ce)")
        top = (self.root / "rtl/hdmi_media_board_top.v").read_text(encoding="utf-8-sig")
        self.assertIn("output wire rtc_scl,rtc_ce,inout wire rtc_sda", top)
        self.assertIn("rtc_ds1302 #(.WRITE_ENABLE(1)) rtc", top)

    def test_chinese_font_gui_override_survives_default_strategy_reset(self):
        project = self.root / "HDMI_media_board_WAV.al"
        original = project.read_text(encoding="utf-8-sig")
        for replacement in ('<eram_init>off</eram_init>', ''):
            project.write_text(original.replace('<eram_init>on</eram_init>', replacement),
                               encoding="utf-8")
            with self.subTest(setting=replacement):
                self.assertEqual(check_project(self.root)["top_ports"], 27)

    def test_gui_wrong_seed_is_rejected(self):
        self.edit("HDMI_media_board_WAV.al", 'Init="19"', 'Init="0"')
        with self.assertRaisesRegex(ValueError, "seed 19"):
            check_project(self.root)

    def test_chinese_font_gui_reload_override_is_required(self):
        project = self.root / "HDMI_media_board_WAV.al"
        original = project.read_text(encoding="utf-8-sig")
        option = '<param>set_param gate eram_init on</param>'
        for replacement in ('', '<param>set_param gate eram_init off</param>',
                            option + '<param>set_param gate eram_init off</param>'):
            project.write_text(original.replace(option, replacement), encoding="utf-8")
            with self.subTest(setting=replacement):
                with self.assertRaisesRegex(ValueError, "more options"):
                    check_project(self.root)

    def test_gui_random_or_multiple_seeds_are_rejected(self):
        project = self.root / "HDMI_media_board_WAV.al"
        original = project.read_text(encoding="utf-8-sig")
        for old, new in (('Random="false"', 'Random="true"'),
                         ('Num="1"', 'Num="2"'),
                         ('Step="1"', 'Step="2"')):
            with self.subTest(setting=new):
                project.write_text(original.replace(old, new), encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "seed 19"):
                    check_project(self.root)

    def test_gui_seed_list_must_match_fixed_seed(self):
        project = self.root / "HDMI_media_board_WAV.al"
        original = project.read_text(encoding="utf-8-sig")
        for seeds in ("", "0", "4 5"):
            with self.subTest(seeds=seeds):
                mutated, count = re.subn(r"(<Seeds\b[^>]*>).*?(</Seeds>)",
                                         lambda match: match[1] + seeds + match[2], original, flags=re.S)
                self.assertEqual(count, 1)
                self.assertNotEqual(mutated, original)
                project.write_text(mutated, encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "seed 19"):
                    check_project(self.root)

    def test_missing_rtl(self):
        (self.root / "rtl/sd_sector_arbiter.v").unlink()
        with self.assertRaisesRegex(ValueError, "缺少文件"):
            check_project(self.root)

    def test_fft_reload_accepts_only_automatically_excluded_legacy_waveform(self):
        project = self.root / "HDMI_media_board_WAV.al"
        text = project.read_text(encoding="utf-8-sig")
        pattern = r'<File\s+Path="rtl/video_audio_waveform\.v">.*?</File>'
        text, count = re.subn(pattern, lambda m: m[0].replace('<FileInfo>',
                             '<FileInfo><Attr Name="AutoExcluded" Val="true"/>'), text, flags=re.S)
        self.assertEqual(count, 1)
        project.write_text(text, encoding="utf-8")
        self.assertEqual(check_project(self.root)["top_ports"], 27)
        # An explicit synthesis exclusion is not an automatic unused branch.
        excluded = re.sub(pattern, lambda m: m[0].replace('Name="UsedInSyn" Val="true"',
                          'Name="UsedInSyn" Val="false"'), text, flags=re.S)
        project.write_text(excluded, encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "依赖未参与综合.*video_audio_waveform"):
            check_project(self.root)
        project.write_text(text, encoding="utf-8")
        self.edit("rtl/hdmi_media_board_top.v", ".SPECTRUM_FFT(1)", ".SPECTRUM_FFT(0)")
        with self.assertRaisesRegex(ValueError, "依赖未参与综合.*video_audio_waveform"):
            check_project(self.root)

    def test_unregistered_instantiated_helper_is_rejected(self):
        self.assertRegex((self.root / "rtl/hdmi_media_board_top.v").read_text(encoding="utf-8-sig"),
                         r"\bmedia_adjust_control\s+#\(.*?\)\s+adjust_controls\s*\(")
        project = self.root / "HDMI_media_board_WAV.al"
        original = project.read_text(encoding="utf-8-sig")
        for helper, excluded in (("media_nec_receiver", False),
                                 ("media_nec_receiver", True),
                                 ("media_infrared_control", False),
                                 ("media_infrared_control", True),
                                 ("media_adjust_control", False),
                                 ("media_adjust_control", True),
                                 ("rtc_ds1302", False),
                                 ("rtc_ds1302", True),
                                 ("rtc_set_control", False),
                                 ("rtc_set_control", True),
                                 ("audio_async_fifo", False),
                                 ("video_chinese_subtitle", False),
                                 ("video_chinese_subtitle", True),
                                 ("subtitle_font_rom", False),
                                 ("subtitle_font_rom", True),
                                 ("video_chinese_settings", False),
                                 ("settings_font_rom", False),
                                 ("video_audio_waveform", False),
                                 ("video_audio_spectrum", False),
                                 ("video_audio_spectrum", True),
                                 ("audio_fft512", False),
                                 ("audio_fft512", True),
                                 ("audio_fft_coeff_rom", False),
                                 ("audio_fft_coeff_rom", True)):
            source = f"rtl/{helper}.v"
            self.assertTrue((self.root / source).is_file())
            pattern = r'<File\s+Path="' + re.escape(source) + r'">.*?</File>'
            replacement = (lambda match: match[0].replace('<FileInfo>',
                           '<FileInfo><Attr Name="AutoExcluded" Val="true"/>')) if excluded else ""
            text, changed = re.subn(pattern, replacement, original, flags=re.S)
            self.assertEqual(changed, 1)
            project.write_text(text, encoding="utf-8")
            for check in (check_project, check_logic_project):
                with self.subTest(helper=helper, excluded=excluded, check=check.__name__):
                    with self.assertRaisesRegex(ValueError, "依赖未参与综合.*" + helper):
                        check(self.root)

    @unittest.skipUnless(os.name == "nt", "Windows GUI launcher")
    def test_gui_launcher_blocks_unregistered_subtitle_before_starting_td(self):
        project = self.root / "HDMI_media_board_WAV.al"
        text = project.read_text(encoding="utf-8-sig")
        text, changed = re.subn(r'<File Path="rtl/video_chinese_subtitle\.v">.*?</File>',
                               "", text, flags=re.S)
        self.assertEqual(changed, 1)
        project.write_text(text, encoding="utf-8")
        invoked = self.root / "td_was_started.txt"
        fake_td = self.root / "fake_td.cmd"
        fake_td.write_text('@echo off\necho unexpected > "%~dp0td_was_started.txt"\n',
                           encoding="ascii")
        launcher = self.root / "打开TD工程.cmd"
        text = (ROOT / launcher.name).read_text(encoding="utf-8-sig")
        text = re.sub(r'^set "hdmiTd=.*?"$',
                      lambda _: f'set "hdmiTd={fake_td}"', text, flags=re.M)
        launcher.write_text(text, encoding="utf-8")
        # A failed precheck must not even reach the installed-TD compatibility helper.
        helper = self.root / "tools/fix_td_multiseed.py"
        helper.write_text("raise SystemExit('PRECHECK_WAS_BYPASSED')\n", encoding="ascii")
        result = subprocess.run(["cmd.exe", "/d", "/c", str(launcher)], input=b"\n",
                                capture_output=True, timeout=30)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 1, output)
        self.assertIn(b"video_chinese_subtitle", output)
        self.assertIn(b"No project was opened", output)
        self.assertNotIn(b"PRECHECK_WAS_BYPASSED", output)
        self.assertFalse(invoked.exists())

    def test_wrong_top(self):
        self.edit("HDMI_media_board_WAV.al", "<MODULE>hdmi_media_board_top</MODULE>", "<MODULE>tb_pipeline</MODULE>")
        with self.assertRaisesRegex(ValueError, "顶层必须"):
            check_project(self.root)

    def test_unconstrained_port(self):
        self.edit("board.adc", "{ sd_sck }", "{ unknown_port }")
        with self.assertRaisesRegex(ValueError, "未约束=.*sd_sck"):
            check_project(self.root)

    def test_conflicting_pin(self):
        self.edit("board.adc", "LOCATION = A9", "LOCATION = R7")
        with self.assertRaisesRegex(ValueError, "物理管脚冲突"):
            check_project(self.root)

    def test_old_project_path(self):
        self.edit("HDMI_media_board_WAV.al", self.root.as_posix(), ROOT.as_posix())
        with self.assertRaisesRegex(ValueError, "指向其他目录"):
            check_project(self.root)

    def test_draft_requires_explicit_logic_check_and_only_allows_tf_missing(self):
        (self.root / "board.adc").write_text(self.draft_adc, encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "未约束=.*sd_cs"):
            check_project(self.root)
        self.assertEqual(set(check_logic_project(self.root)["unassigned_ports"]), TF_PORTS)
        command = [sys.executable, str(self.root / "tools/check_project.py")]
        for options, expected in (([], 1), (["--logic-only"], 0)):
            child = subprocess.run(command + options, capture_output=True, text=True, timeout=30)
            self.assertEqual(child.returncode, expected, child.stdout + child.stderr)
        self.edit("board.adc", "set_pin_assignment { rst_n }", "# set_pin_assignment { rst_n }")
        with self.assertRaisesRegex(ValueError, "未约束=.*rst_n"):
            check_logic_project(self.root)

    def test_mapped_tf_does_not_bypass_pending_hardware_guard(self):
        (self.root / "board.adc").write_text(self.draft_adc + self.synthetic_tf, encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "HDMI_BOARD_HARDWARE_INCOMPLETE"):
            check_project(self.root)

    def test_tcl_check_draft_does_not_read_physical_constraints(self):
        (self.root / "board.adc").write_text(self.draft_adc, encoding="utf-8")
        before = Path.cwd()
        self.addCleanup(os.chdir, before)
        interp = tkinter.Tcl()
        calls = []
        for name in ("import_device", "open_project", "elaborate", "read_adc", "read_sdc", "bitgen", "exit"):
            interp.createcommand(name, lambda *args, command=name: calls.append(command) or "")
        interp.createcommand("puts", lambda *args: "")
        interp.call("source", str(self.root / "tests/audio_source/check_board.tcl"))
        self.assertIn("elaborate", calls)
        self.assertNotIn("read_adc", calls)
        self.assertNotIn("read_sdc", calls)
        self.assertNotIn("bitgen", calls)

    def test_draft_blocks_build_and_existing_gui_database_paths(self):
        (self.root / "board.adc").write_text(self.draft_adc, encoding="utf-8")
        old_bit = self.root / "HDMI_media_board_WAV.bit"
        old_bit.write_bytes(b"previous bitstream")
        database = self.root / "HDMI_media_board_WAV_Runs/phy_1/HDMI_media_board_WAV_pr.db"
        database.parent.mkdir(parents=True)
        database.write_bytes(b"previous routed database")
        before = Path.cwd()
        self.addCleanup(os.chdir, before)
        interp = tkinter.Tcl()
        calls = []
        for name in ("import_device", "open_project", "elaborate", "import_db", "bitgen"):
            interp.createcommand(name, lambda *args, command=name: calls.append(command) or "")
        interp.createcommand("puts", lambda *args: "")
        for script in ("build_wav_project.tcl", "fix_wav_gui_route.tcl", "refresh_wav_gui_reports.tcl"):
            with self.subTest(script=script):
                with self.assertRaises(tkinter.TclError):
                    interp.call("source", str(self.root / script))
                self.assertEqual(calls, [])
                self.assertEqual(old_bit.read_bytes(), b"previous bitstream")

    def test_tcl_build_resolves_its_own_path(self):
        before = Path.cwd()
        self.addCleanup(os.chdir, before)
        interp = tkinter.Tcl()
        calls = []
        self.timing_report = TIMING_REPORT
        self.generate_report = True
        for name in ("import_device", "open_project", "elaborate", "read_adc", "read_sdc",
                     "optimize_rtl", "optimize_gate", "export_db", "set_param", "place", "route", "fix_hold",
                     "report_area", "report_timing_summary", "report_timing_exception", "bitgen", "exit",
                     "import_db", "update_timing", "report_timing_status", "flow_status", "report_qor"):
            def record(*args, command=name):
                calls.append((command, args))
                if command == "report_timing_summary" and self.generate_report:
                    Path(args[args.index("-file") + 1]).write_text(self.timing_report)
                return ""
            interp.createcommand(name, record)
        interp.call("source", str(self.root / "build_wav_project.tcl"))
        opened = [args[0] for name, args in calls if name == "open_project"]
        self.assertEqual(Path(opened[0]).resolve(), self.root / "HDMI_media_board_WAV.al")
        commands = [name for name, _ in calls]
        self.assertIn(("set_param", ("place", "seed", "19")), calls[:commands.index("place")])
        self.assertIn(("set_param", ("place", "pr_strategy", "5")), calls[:commands.index("place")])
        for key, value in (("eram_init", "on"), ("opt_area", "high"), ("pack_effort", "high")):
            self.assertIn(("set_param", ("gate", key, value)), calls[:commands.index("optimize_rtl")])
        self.assertLess(commands.index("fix_hold"), commands.index("bitgen"))
        # 微小负保持时间也不能到达任一 bitgen；旧位流必须保持原样。
        old_bit = self.root / "HDMI_media_board_WAV.bit"
        old_bit.write_bytes(b"previous valid bitstream")
        gui_db = self.root / "HDMI_media_board_WAV_Runs/phy_1/seed_19/HDMI_media_board_WAV_pr.db"
        gui_db.parent.mkdir(parents=True)
        gui_db.write_bytes(b"mock routed database")
        self.timing_report = TIMING_REPORT.replace("HWNS: 0.060ns", "HWNS: -0.0012ns")
        for script in ("build_wav_project.tcl", "fix_wav_gui_route.tcl"):
            with self.subTest(script=script):
                calls.clear()
                with self.assertRaisesRegex(tkinter.TclError, "Timing failed"):
                    interp.call("source", str(self.root / script))
                self.assertNotIn("bitgen", [name for name, _ in calls])
                self.assertEqual(old_bit.read_bytes(), b"previous valid bitstream")
        # 本轮没产生报告，即使上轮报告全为正值也不能误放行。
        (self.root / "board_wav_timing.rpt").write_text(TIMING_REPORT)
        self.generate_report = False
        calls.clear()
        with self.assertRaisesRegex(tkinter.TclError, "did not produce a new timing report"):
            interp.call("source", str(self.root / "build_wav_project.tcl"))
        self.assertNotIn("bitgen", [name for name, _ in calls])
        calls.clear()
        (self.root / "rtl/sd_sector_arbiter.v").unlink()
        with self.assertRaises(tkinter.TclError):
            interp.call("source", str(self.root / "build_wav_project.tcl"))
        self.assertEqual(calls, [])

    def test_gui_reports_reject_old_normal_flow_database(self):
        old_db = self.root / "HDMI_media_board_WAV_Runs/phy_1/HDMI_media_board_WAV_pr.db"
        old_db.parent.mkdir(parents=True)
        old_db.write_bytes(b"old failed normal-flow database")
        previous_seed_db = old_db.parent / "seed_2/HDMI_media_board_WAV_pr.db"
        previous_seed_db.parent.mkdir()
        previous_seed_db.write_bytes(b"old caption seed-2 database")
        before = Path.cwd()
        self.addCleanup(os.chdir, before)
        interp = tkinter.Tcl()
        calls = []
        interp.createcommand("puts", lambda *args: "")
        interp.createcommand("import_db", lambda *args: calls.append(args) or "")
        for script in ("fix_wav_gui_route.tcl", "refresh_wav_gui_reports.tcl"):
            with self.subTest(script=script):
                with self.assertRaisesRegex(tkinter.TclError, "No routed seed-19"):
                    interp.call("source", str(self.root / script))
                self.assertEqual(calls, [])

    def test_runner_rejects_failures_under_python_optimization(self):
        code = """import sys
from verify import run_command
for child in ('import sys; sys.exit(2)', 'import sys; print("FATAL test", file=sys.stderr)'):
    try:
        run_command([sys.executable, '-c', child], '.', [])
    except RuntimeError:
        continue
    raise SystemExit('FAIL: failed command was accepted')
"""
        result = subprocess.run([sys.executable, "-O", "-c", code], cwd=ROOT, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @unittest.skipUnless(os.name == "nt", "Windows TD 启动器")
    def test_td_launcher_rejects_exit_zero_without_completion_marker(self):
        shell = shutil.which("powershell") or shutil.which("pwsh")
        self.assertIsNotNone(shell)
        # hostname 正常返回 0，但没有 TD 完成标记；必须判为失败。
        fake_td = Path(os.environ["SystemRoot"]) / "System32/hostname.exe"
        result = subprocess.run([shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                                 str(self.root / "tools/run_td.ps1"), "-Action", "Check",
                                 "-TdExecutable", str(fake_td)], capture_output=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)

    @unittest.skipUnless(os.name == "nt", "Windows TD 启动器")
    def test_td_launcher_blocks_physical_actions_before_starting_td(self):
        (self.root / "board.adc").write_text(self.draft_adc, encoding="utf-8")
        shell = shutil.which("powershell") or shutil.which("pwsh")
        self.assertIsNotNone(shell)
        fake_td = self.root / "fake_td.cmd"
        fake_td.write_text('@echo off\necho invoked > "%~dp0td.called"\nexit /b 0\n')
        for action in ("Build", "FixHold", "Reports"):
            with self.subTest(action=action):
                child = subprocess.run([shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                                        str(self.root / "tools/run_td.ps1"), "-Action", action,
                                        "-TdExecutable", str(fake_td)], capture_output=True, timeout=30)
                self.assertNotEqual(child.returncode, 0)
                self.assertFalse((self.root / "td.called").exists())

    @unittest.skipUnless(os.name == "nt", "Windows PowerShell 启动器解析")
    def test_td_launcher_parses_in_windows_powershell(self):
        shell = shutil.which("powershell")
        self.assertIsNotNone(shell)
        script = (self.root / "tools/run_td.ps1").as_posix().replace("'", "''")
        command = ("$parseTokens = $null\n$parseErrors = $null\n"
                   "[void][System.Management.Automation.Language.Parser]::ParseFile('" + script
                   + "', [ref]$parseTokens, [ref]$parseErrors)\n"
                   "if ($parseErrors.Count) { $parseErrors | Write-Output; exit 1 }")
        child = subprocess.run([shell, "-NoProfile", "-Command", command],
                               capture_output=True, timeout=30)
        self.assertEqual(child.returncode, 0, child.stdout + child.stderr)

    @unittest.skipUnless(os.name == "nt", "Windows TD 启动器")
    def test_td_launcher_check_accepts_draft_and_reaches_td(self):
        (self.root / "board.adc").write_text(self.draft_adc, encoding="utf-8")
        shell = shutil.which("powershell") or shutil.which("pwsh")
        self.assertIsNotNone(shell)
        fake_td = self.root / "fake_td.cmd"
        fake_td.write_text('@echo off\necho invoked > "%~dp0td.called"\n'
                           'echo BOARD_AUDIO_SOURCE_ELABORATION_FINISHED\nexit /b 0\n')
        child = subprocess.run([shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                                str(self.root / "tools/run_td.ps1"), "-Action", "Check",
                                "-TdExecutable", str(fake_td)], capture_output=True, timeout=30)
        self.assertEqual(child.returncode, 0, child.stdout + child.stderr)
        self.assertTrue((self.root / "td.called").is_file())


class TimingChecks(unittest.TestCase):
    def test_diagnostic_top_is_checked_explicitly(self):
        interp = tkinter.Tcl()
        interp.call("source", str(ROOT / "tools/project_setup.tcl"))
        with tempfile.TemporaryDirectory(prefix="dmz timing test ") as temporary:
            report = Path(temporary) / "timing.rpt"
            text = TIMING_REPORT.replace("hdmi_media_board_top", "dmz_hdmi_colorbar_top")
            report.write_text(text)
            interp.call("hdmi_require_timing", str(report), "dmz_hdmi_colorbar_top")
            with self.assertRaisesRegex(tkinter.TclError, "top module"):
                interp.call("hdmi_require_timing", str(report))
            report.write_text(text.replace("HWNS: 0.060ns", "HWNS: -0.0012ns"))
            with self.assertRaisesRegex(tkinter.TclError, "Timing failed"):
                interp.call("hdmi_require_timing", str(report), "dmz_hdmi_colorbar_top")

    def test_timing_gate_boundaries(self):
        interp = tkinter.Tcl()
        interp.call("source", str(ROOT / "tools/project_setup.tcl"))
        with tempfile.TemporaryDirectory(prefix="hdmi timing test ") as temporary:
            report = Path(temporary) / "timing.rpt"
            for text in (TIMING_REPORT, TIMING_REPORT.replace("0.817", "0.000").replace("0.060", "0.000")):
                report.write_text(text)
                interp.call("hdmi_require_timing", str(report))
            cases = {
                "negative_setup": TIMING_REPORT.replace("0.817", "-0.001"),
                "negative_hold": TIMING_REPORT.replace("0.060", "-0.0012"),
                "negative_total": TIMING_REPORT.replace("STNS: 0.000", "STNS: -0.100"),
                "negative_period": TIMING_REPORT.replace("Period Check WNS: 0.000", "Period Check WNS: -0.010"),
                "missing_metric": TIMING_REPORT.replace("HWNS:", "OTHER:"),
                "nan_metric": TIMING_REPORT.replace("0.060", "NaN"),
                "duplicate_metric": TIMING_REPORT + "HWNS: 0.060ns\n",
                "wrong_top": TIMING_REPORT.replace("hdmi_media_board_top", "test_top"),
                "wrong_device": TIMING_REPORT.replace("EG4S20BG256", "OTHER_DEVICE"),
                "not_routed": TIMING_REPORT.replace("Routed", "Estimated"),
            }
            for name, text in cases.items():
                with self.subTest(case=name):
                    report.write_text(text)
                    with self.assertRaises(tkinter.TclError):
                        interp.call("hdmi_require_timing", str(report))
            report.unlink()
            with self.assertRaises(tkinter.TclError):
                interp.call("hdmi_require_timing", str(report))


if __name__ == "__main__":
    unittest.main()
