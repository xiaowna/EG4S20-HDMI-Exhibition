"""The upload copy can relocate without weakening normal project checks."""
from pathlib import Path
import re,shutil,tempfile,unittest
from tools.prepare_td_project import prepare
from tools.check_project import check_project

ROOT=Path(__file__).resolve().parents[1]
PROJECT='HDMI_media_board_WAV.al'


class RelocateProjectTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='TD 上传包 migration ')
        self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)/'中文目录 with spaces'
        self.root.mkdir()
        for name in [PROJECT,'board.adc','board.sdc','sources.txt','build_wav_project.tcl']:
            shutil.copy2(ROOT/name,self.root/name)
        shutil.copytree(ROOT/'rtl',self.root/'rtl')
        (self.root/'tools').mkdir()
        for name in ['td_gui_profile.py','td_gui_profile.tcl']:
            shutil.copy2(ROOT/'tools'/name,self.root/'tools'/name)
        self.path=self.root/PROJECT
        text=self.path.read_text(encoding='utf-8-sig')
        self.original=re.sub(r'(<Project\b[^>]*\bPath=")[^"]*',r'\g<1>C:/old/extracted project',text,count=1)
        self.path.write_bytes(self.original.encode('utf-8'))

    def test_relocation_keeps_settings_rtl_constraints_and_exact_backup(self):
        originals={str(p.relative_to(self.root)):p.read_bytes() for p in (self.root/'rtl').glob('*.v')}
        originals.update({n:(self.root/n).read_bytes() for n in ['board.adc','board.sdc']})
        before=self.path.read_bytes()
        result=prepare(self.root,relocate=True)
        self.assertTrue(result['relocated'])
        self.assertEqual(result['restored_options'],[])
        self.assertEqual(Path(result['backup']).read_bytes(),before)
        expected=self.original.replace('C:/old/extracted project',self.root.as_posix(),1)
        self.assertEqual(self.path.read_bytes(),expected.encode('utf-8'))
        self.assertEqual(check_project(self.root)['top_ports'],27)
        self.assertTrue(all((self.root/n).read_bytes()==data for n,data in originals.items()))

    def test_relocation_is_idempotent(self):
        prepare(self.root,relocate=True)
        before=self.path.read_bytes()
        result=prepare(self.root,relocate=True)
        self.assertFalse(result['relocated'])
        self.assertNotIn('backup',result)
        self.assertEqual(before,self.path.read_bytes())

    def test_default_still_rejects_an_old_root(self):
        before=self.path.read_bytes()
        with self.assertRaisesRegex(ValueError,'unrelated'):
            prepare(self.root)
        self.assertEqual(before,self.path.read_bytes())

    def test_unrelated_project_device_and_top_are_rejected_unchanged(self):
        mutations=[('<Name>HDMI_media_board_WAV</Name>','<Name>other_project</Name>'),
                   ('EG4S20BG256','EG4S10BG256'),
                   ('<MODULE>hdmi_media_board_top</MODULE>','<MODULE>other_top</MODULE>')]
        for old,new in mutations:
            with self.subTest(field=old):
                self.path.write_text(self.original.replace(old,new),encoding='utf-8')
                before=self.path.read_bytes()
                with self.assertRaisesRegex(ValueError,'unrelated'):
                    prepare(self.root,relocate=True)
                self.assertEqual(before,self.path.read_bytes())

    def test_relative_sources_must_exist_inside_this_package(self):
        for name in ['../outside.v','C:/outside.v','/outside.v','missing.v']:
            with self.subTest(path=name):
                text=re.sub(r'(<File\s+Path=")[^"]*',lambda m:m[1]+name,self.original,count=1)
                self.path.write_text(text,encoding='utf-8');before=self.path.read_bytes()
                with self.assertRaisesRegex(ValueError,'Relocation'):
                    prepare(self.root,relocate=True)
                self.assertEqual(before,self.path.read_bytes())

    def test_final_checker_failure_restores_original_old_path(self):
        with (self.root/'sources.txt').open('a',encoding='utf-8') as stream:
            stream.write('\nnonexistent.v\n')
        before=self.path.read_bytes()
        with self.assertRaisesRegex(ValueError,'仿真源未登记到工程'):
            prepare(self.root,relocate=True)
        self.assertEqual(before,self.path.read_bytes())
        backups=list((self.root/'reports/td_gui_reopen_backups').glob('*/'+PROJECT))
        self.assertEqual(len(backups),1)
        self.assertEqual(backups[0].read_bytes(),before)

    def test_relocation_also_restores_only_known_missing_options(self):
        text=self.original.replace('                <param>set_param gate opt_area high</param>\n','')
        self.path.write_text(text,encoding='utf-8')
        result=prepare(self.root,relocate=True)
        self.assertTrue(result['relocated'])
        self.assertEqual(result['restored_options'],['set_param gate opt_area high'])
        self.assertEqual(check_project(self.root)['rtl_files'],check_project(ROOT)['rtl_files'])


if __name__=='__main__':
    unittest.main()
