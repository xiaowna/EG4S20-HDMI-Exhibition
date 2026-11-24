"""GUI save/reopen recovery retains strict source and timing-profile checks."""
from pathlib import Path
import shutil,tempfile,unittest
from tools.prepare_td_project import prepare,restored_text
from tools.check_project import GUI_SEED,check_project

ROOT=Path(__file__).resolve().parents[1]

class PrepareProjectTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory(prefix='td GUI reopen ');self.addCleanup(self.tmp.cleanup)
  self.root=Path(self.tmp.name)
  for name in ['HDMI_media_board_WAV.al','board.adc','board.sdc','sources.txt','build_wav_project.tcl']:
   shutil.copy2(ROOT/name,self.root/name)
  shutil.copytree(ROOT/'rtl',self.root/'rtl')
  (self.root/'tools').mkdir()
  for name in ['td_gui_profile.py','td_gui_profile.tcl']:shutil.copy2(ROOT/'tools'/name,self.root/'tools'/name)
  self.path=self.root/'HDMI_media_board_WAV.al'
  self.path.write_text(self.path.read_text(encoding='utf-8-sig').replace(ROOT.as_posix(),self.root.as_posix()),encoding='utf-8')

 def saved_by_gui(self):
  text=self.path.read_text(encoding='utf-8-sig')
  for command in ['set_param gate opt_area high','set_param place pr_strategy 5']:
   text=text.replace('                <param>'+command+'</param>\n','')
  self.path.write_text(text,encoding='utf-8');return self.path.read_bytes()

 def test_gui_save_then_prepare_passes_and_keeps_original_backup(self):
  before=self.saved_by_gui()
  with self.assertRaisesRegex(ValueError,'opt_area'):check_project(self.root)
  result=prepare(self.root)
  self.assertEqual(result['restored_options'],['set_param gate opt_area high','set_param place pr_strategy 5'])
  self.assertEqual(Path(result['backup']).read_bytes(),before)
  self.assertEqual(check_project(self.root)['top_ports'],27)
  current=self.path.read_bytes();self.assertEqual(prepare(self.root)['restored_options'],[])
  self.assertEqual(current,self.path.read_bytes())

 def test_gui_last_selected_seed_is_restored(self):
  self.saved_by_gui()
  text=self.path.read_text(encoding='utf-8-sig')
  text=text.replace(f'Init="{GUI_SEED}"','Init="26"')
  for seed_tag in ('<Seeds select="26">','<Seeds>'):
   with self.subTest(seed_tag=seed_tag):
    old=f'<Seeds select="{GUI_SEED}">{GUI_SEED} </Seeds>'
    self.assertIn(old,text)
    self.path.write_text(text.replace(old,seed_tag+'26 </Seeds>'),encoding='utf-8')
    before=self.path.read_bytes()
    with self.assertRaisesRegex(ValueError,f'seed {GUI_SEED}'):check_project(self.root)
    result=prepare(self.root)
    self.assertIn(f'MultiSeed seed {GUI_SEED}',result['restored_options'])
    self.assertEqual(Path(result['backup']).read_bytes(),before)
    self.assertEqual(check_project(self.root)['top_ports'],27)
    self.assertEqual(prepare(self.root)['restored_options'],[])

 def test_explicit_conflict_and_duplicates_are_not_overwritten(self):
  original=self.path.read_text(encoding='utf-8-sig')
  for value in ['set_param gate opt_area medium','set_param gate opt_area high</param><param>set_param gate opt_area high']:
   with self.subTest(value=value):
    self.path.write_text(original.replace('set_param gate opt_area high',value),encoding='utf-8')
    before=self.path.read_bytes()
    with self.assertRaisesRegex(ValueError,'Conflicting TD option'):prepare(self.root)
    self.assertEqual(self.path.read_bytes(),before)

 def test_other_source_error_restores_original_gui_file(self):
  before=self.saved_by_gui();(self.root/'rtl/video_scene3d.v').unlink()
  with self.assertRaisesRegex(ValueError,'工程缺少文件'):prepare(self.root)
  self.assertEqual(self.path.read_bytes(),before)

 def test_wrong_device_top_and_path_are_not_repaired(self):
  original=self.path.read_text(encoding='utf-8-sig')
  for old,new in [('EG4S20BG256','EG4S10BG256'),('<MODULE>hdmi_media_board_top</MODULE>','<MODULE>wrong</MODULE>'),(self.root.as_posix(),(self.root/'other').as_posix())]:
   with self.subTest(field=old):
    self.path.write_text(original.replace(old,new),encoding='utf-8');before=self.path.read_bytes()
    with self.assertRaisesRegex(ValueError,'unrelated'):prepare(self.root)
    self.assertEqual(self.path.read_bytes(),before)

 def test_missing_user_params_section_is_restored_without_touching_constraints(self):
  import re
  before={n:(self.root/n).read_bytes() for n in ['board.adc','board.sdc']}
  text=self.path.read_text(encoding='utf-8-sig')
  text=re.sub(r'\s*<UserParams>.*?</UserParams>','',text,flags=re.S)
  self.path.write_text(text,encoding='utf-8');result=prepare(self.root)
  self.assertEqual(len(result['restored_options']),5)
  self.assertTrue(all((self.root/n).read_bytes()==v for n,v in before.items()))

if __name__=='__main__':unittest.main()
