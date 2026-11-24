"""Captured remote codes must stay distinct, address-bound and in sync with RTL."""
from pathlib import Path
import json, re, sys, tempfile, unittest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from tools.configure_ir_remote import apply_profile, build_profile, check_profile, parse_code


class FixedRemoteConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='fixed ir config ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root/'rtl').mkdir();(self.root/'interfaces').mkdir()
        source=(Path(__file__).resolve().parents[1]/'rtl/hdmi_media_board_top.v').read_text(encoding='utf-8')
        source=re.sub(r'parameter IR_FIXED_ENABLE=\d','parameter IR_FIXED_ENABLE=0',source)
        source=re.sub(r"IR_FIXED_KEYS=48'h[0-9a-fA-F]{12}","IR_FIXED_KEYS=48'h000000000000",source)
        (self.root/'rtl/hdmi_media_board_top.v').write_text(source,encoding='utf-8')
        (self.root/'interfaces/infrared_fixed_keys.json').write_text('{"configured":false}',encoding='utf-8')
        self.codes=dict(right='425A',ok='421C',left='4208',settings='4215',home='4245')

    def test_four_digit_hex_and_separator_allowed(self):
        self.assertEqual(parse_code(' 0x00.5a '),(0,0x5a))
        self.assertEqual(parse_code('4200'),(0x42,0))

    def test_rejects_invalid_hex_and_length(self):
        for value in ['5A','00005A','00GG','-05A','00/5A']:
            with self.subTest(value=value),self.assertRaises(ValueError):parse_code(value)

    def test_rejects_mixed_addresses(self):
        with self.assertRaisesRegex(ValueError,'one NEC address'):
            build_profile(dict(self.codes,home='0045'))

    def test_rejects_duplicate_commands(self):
        with self.assertRaisesRegex(ValueError,'different command'):
            build_profile(dict(self.codes,home='4215'))

    def test_unconfigured_is_not_ready(self):
        self.assertFalse(check_profile(self.root)['fixed_remote_ready'])

    def test_fixed_config_round_trip(self):
        apply_profile(self.root,build_profile(self.codes))
        result=check_profile(self.root)
        self.assertTrue(result['fixed_remote_ready']);self.assertEqual(result['commands']['home'],'45')

    def test_rejects_rtl_manifest_disagreement(self):
        apply_profile(self.root,build_profile(self.codes))
        path=self.root/'interfaces/infrared_fixed_keys.json';data=json.loads(path.read_text())
        data['home']='46';path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError,'do not match'):check_profile(self.root)

    def test_extra_keys_round_trip(self):
        extras=dict(back='420D',zoom='4246',model='4244')
        apply_profile(self.root,build_profile(self.codes,extras))
        self.assertEqual(check_profile(self.root)['extras'],dict(back='0D',zoom='46',model='44'))

    def test_extra_keys_reject_wrong_address(self):
        with self.assertRaisesRegex(ValueError,'same NEC address'):
            build_profile(self.codes,dict(back='000D',zoom='4246',model='4244'))

    def test_extra_keys_reject_navigation_collision(self):
        with self.assertRaisesRegex(ValueError,'different commands'):
            build_profile(self.codes,dict(back='420D',zoom='4246',model='4245'))

    def test_direction_keys_round_trip(self):
        apply_profile(self.root,build_profile(self.codes,direction_codes=dict(up='4240',down='4219')))
        self.assertEqual(check_profile(self.root)['directions'],dict(up='40',down='19'))

    def test_direction_keys_reject_wrong_address_and_collisions(self):
        for directions in [dict(up='0040',down='4219'),dict(up='4240',down='4240'),dict(up='4215',down='4219')]:
            with self.subTest(directions=directions),self.assertRaises(ValueError):
                build_profile(self.codes,direction_codes=directions)
        with self.assertRaisesRegex(ValueError,'different commands'):
            build_profile(self.codes,dict(back='420D',zoom='4246',model='4244'),dict(up='4246',down='4219'))

    def test_direction_manifest_detects_rtl_disagreement(self):
        apply_profile(self.root,build_profile(self.codes,direction_codes=dict(up='4240',down='4219')))
        path=self.root/'interfaces/infrared_fixed_keys.json';data=json.loads(path.read_text())
        data['directions']['up']='41';path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError,'direction keys do not match'):check_profile(self.root)

    def test_legacy_profile_disables_direction_keys(self):
        apply_profile(self.root,build_profile(self.codes))
        self.assertEqual(check_profile(self.root)['directions'],{})
        self.assertIn('parameter IR_DIRECTION_ENABLE=0',(self.root/'rtl/hdmi_media_board_top.v').read_text(encoding='utf-8'))


if __name__=='__main__':unittest.main()
