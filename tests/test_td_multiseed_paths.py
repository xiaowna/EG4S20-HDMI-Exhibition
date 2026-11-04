"""Reproduce TD's settings.cfg failure using a real Tcl interpreter."""
import os
from pathlib import Path
import sys
import tempfile
import tkinter
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.fix_td_multiseed import PATCH, SOURCE, patched_script


class MultiSeedPathTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="td-path-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        previous = Path.cwd()
        self.addCleanup(os.chdir, previous)
        os.chdir(self.root)
        self.interp = tkinter.Tcl()

    def config(self, path, quoted=False):
        value = self.interp.call("list", str(path.as_posix())) if quoted else path.as_posix()
        if quoted:
            # tkinter may convert a one-element Tcl list to a Python tuple.
            value = self.interp.call("format", "%s", value)
        text = f"set seed 4\nset phyPath {value}\nset drHoldFix on\nset end_step bitgen\n"
        (self.root / "settings.cfg").write_text(text, encoding="utf-8")
        return text

    def verify(self, name, quoted=False):
        path = self.root / name
        path.mkdir()
        self.config(path, quoted)
        self.interp.eval(PATCH.decode("ascii"))
        self.assertEqual(self.interp.getvar("phyPath"), path.as_posix())
        self.assertEqual(self.interp.getvar("seed"), "4")
        self.assertEqual(self.interp.getvar("drHoldFix"), "on")
        self.assertEqual(self.interp.getvar("end_step"), "bitgen")
        first = (self.root / "settings.cfg").read_bytes()
        self.interp.eval(PATCH.decode("ascii"))
        self.assertEqual((self.root / "settings.cfg").read_bytes(), first)

    def test_original_spaced_path_fails_then_repair_passes(self):
        path = self.root / "HDMI v1.0" / "phy_1"
        path.mkdir(parents=True)
        self.config(path)
        with self.assertRaisesRegex(tkinter.TclError, "wrong # args"):
            self.interp.eval(SOURCE.decode("ascii"))
        self.interp.eval(PATCH.decode("ascii"))
        self.assertEqual(self.interp.getvar("phyPath"), path.as_posix())

    def test_no_space_path(self):
        self.verify("HDMI_M0_GUI")

    def test_already_quoted_spaced_path(self):
        self.verify("HDMI v1.0", quoted=True)

    def test_tcl_special_characters_are_literal(self):
        self.verify("HDMI [missing_command] $missing_var ; demo")

    def test_normal_non_phy_config_unchanged(self):
        content = b"set seed 4\nset drHoldFix on\n"
        (self.root / "settings.cfg").write_bytes(content)
        self.interp.eval(PATCH.decode("ascii"))
        self.assertEqual((self.root / "settings.cfg").read_bytes(), content)

    def test_unknown_vendor_version_is_not_patched(self):
        with self.assertRaisesRegex(ValueError, "Unknown"):
            patched_script(b"# different vendor version\n" + SOURCE)

    def test_marker_does_not_bypass_vendor_version_check(self):
        with self.assertRaisesRegex(ValueError, "Unknown modified"):
            patched_script(b"# different vendor version\n" + PATCH)


if __name__ == "__main__":
    unittest.main()
