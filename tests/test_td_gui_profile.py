"""Regression for GUI defaults overriding the measured gate/place profile."""
import tkinter
import unittest
import os
import tempfile
from pathlib import Path
from tools.td_gui_profile import (TD,STAGES,patch,dispatch,project_tcl,template_patch,remove_dispatch)

# Independent fixture of the installed block before the missing-pointer guard.
LEGACY_DISPATCH='''  # HDMI_GUI_DISPATCH_V1 STAGE BEGIN
  if {$prj_name eq "HDMI_media_board_WAV"} {
    set hdmi_scan [pwd]
    for {set hdmi_i 0} {$hdmi_i<8 && ![file isfile [file join $hdmi_scan .hdmi_gui_root.txt]]} {incr hdmi_i} {
      set hdmi_scan [file dirname $hdmi_scan]
    }
    if {[file isfile [file join $hdmi_scan .hdmi_gui_root.txt]]} {
      set hdmi_ch [open [file join $hdmi_scan .hdmi_gui_root.txt] r]
      set hdmi_root [string trim [read $hdmi_ch]]
      close $hdmi_ch
      if {![file isfile [file join $hdmi_root tools td_gui_profile.tcl]] || ![file isfile [file join $hdmi_root HDMI_media_board_WAV.al]]} {error "HDMI GUI profile root is stale; reopen with the project launcher"}
      source [file join $hdmi_root tools td_gui_profile.tcl]
      hdmi_gui_STAGE $prj_name $hdmi_root
    }
  }
  # HDMI_GUI_DISPATCH_V1 STAGE END
'''

FLOW='''proc read_design_fun {} {
 commit_param -step design
### Editable zone for read_design ###
 elaborate
###################################
}
proc opt_rtl_fun {} {
 commit_param -step rtl
### Editable zone for opt_rtl ###
 optimize_rtl
###################################
}
proc opt_gate_fun {} {
 commit_param -step gate
### Editable zone for opt_gate ###
 optimize_gate
###################################
}
proc opt_place_fun {} {
 commit_param -step place
### Editable zone for opt_place ###
 place
###################################
}
'''

class GuiProfileTests(unittest.TestCase):
 def test_native_defaults_are_replaced_at_each_operation(self):
  interp=tkinter.Tcl();params={};checked=[]
  def commit(*args):
   params.update({('gate','eram_init'):'off',('gate','opt_area'):'medium',
                  ('gate','pack_effort'):'medium',('place','pr_strategy'):'1'})
  def setter(stage,key,value):params[stage,key]=value
  def getter(stage,key):return params.get((stage,key),'')
  def operation(name):
   def run():
    if name=='place':self.assertEqual(params['place','pr_strategy'],'5')
    else:
     self.assertEqual(params['gate','eram_init'],'on')
     self.assertEqual(params['gate','opt_area'],'high')
     self.assertEqual(params['gate','pack_effort'],'high')
    checked.append(name);return ''
   return run
  interp.createcommand('commit_param',commit)
  interp.createcommand('set_param',setter);interp.createcommand('get_param',getter)
  for name in ['elaborate','optimize_rtl','optimize_gate','place']:interp.createcommand(name,operation(name))
  interp.eval(patch(FLOW))
  for name in ['read_design','opt_rtl','opt_gate']:interp.call(name+'_fun')
  # TD imports a qualified gate DB before placement; it must reject a stale DB.
  params['gate','eram_init']='off'
  with self.assertRaisesRegex(tkinter.TclError,'synthesis database'):interp.call('opt_place_fun')
  # The placement commit in the real flow changes place settings, not gate DB flags.
  def place_commit(*args):params['place','pr_strategy']='1'
  interp.createcommand('commit_param',place_commit)
  params.update({('gate','eram_init'):'on',('gate','opt_area'):'high',('gate','pack_effort'):'high'})
  interp.call('opt_place_fun')
  self.assertEqual(checked,['elaborate','optimize_rtl','optimize_gate','place'])

 def test_read_design_recovers_missing_native_rom_source(self):
  interp=tkinter.Tcl()
  calls=[]
  interp.createcommand('set_param',lambda *args: '')
  interp.createcommand('get_param',lambda *args: '')
  interp.createcommand('puts',lambda *args: '')
  interp.createcommand('reanalyze',lambda *args: calls.append(args) or '')
  interp.eval(project_tcl())
  old_cwd=Path.cwd()
  with tempfile.TemporaryDirectory(prefix='HDMI TD ROM ') as temp:
   root=Path(temp)
   run=root/'syn_1'
   run.mkdir()
   rom=root/'rtl/anlogic_initialized_rom.v'
   rom.parent.mkdir()
   rom.touch()
   prj=run/'HDMI_media_board_WAV.prj'
   interp.call('cd',run.as_posix())
   try:
    prj.write_text('<Project><File Path="../../rtl/help_assets_rom.v"/></Project>')
    interp.call('hdmi_gui_read_design','HDMI_media_board_WAV',root.as_posix())
    self.assertEqual(calls,[('-file',rom.as_posix())])
    prj.write_text('<Project><File Path="../../rtl/anlogic_initialized_rom.v"/></Project>')
    interp.call('hdmi_gui_read_design','HDMI_media_board_WAV',root.as_posix())
    self.assertEqual(calls,[('-file',rom.as_posix())])
   finally:
    interp.call('cd',old_cwd.as_posix())

 def test_idempotent_and_vendor_code_preserved(self):
  result=patch(FLOW)
  self.assertEqual(patch(result),result)
  self.assertIn('commit_param -step place',result)
  self.assertEqual(result.count(' optimize_gate\n'),1)

 def test_unknown_script_is_rejected(self):
  with self.assertRaises(ValueError):patch('place\nroute\n')

 def test_regenerated_template_preserves_vendor_and_is_idempotent(self):
  for name in ['DefaultFlow.tcl','MultiSeed.tcl']:
   raw=(TD/'doc/scripts'/name).read_bytes()
   updated=template_patch(raw,name)
   self.assertEqual(template_patch(updated,name),updated)
   if name=='DefaultFlow.tcl':self.assertEqual(remove_dispatch(updated),remove_dispatch(raw))
   self.assertIn(b'HDMI_GUI_DISPATCH_V1 opt_gate BEGIN' if name=='DefaultFlow.tcl'
                 else b'HDMI_GUI_DISPATCH_V1 opt_place BEGIN',updated)
  with self.assertRaisesRegex(ValueError,'Unknown TD'):template_patch(b'# unknown\n','DefaultFlow.tcl')

 def test_shared_template_only_dispatches_for_explicit_project_helper(self):
  interp=tkinter.Tcl();previous=Path.cwd();calls=[]
  with tempfile.TemporaryDirectory(prefix='hdmi gui profile ') as temp:
   root=Path(temp);(root/'tools').mkdir();run=root/'Runs/syn';run.mkdir(parents=True)
   (root/'Runs/.hdmi_gui_root.txt').write_text(root.as_posix())
   (root/'HDMI_media_board_WAV.al').write_text('fixture')
   (root/'tools/td_gui_profile.tcl').write_text(project_tcl())
   interp.createcommand('set_param',lambda *args:calls.append(args) or '')
   interp.createcommand('get_param',lambda *args:'on' if args[-1]=='eram_init' else 'high')
   try:
    os.chdir(run)
    interp.setvar('prj_name','AnotherProject');interp.eval(dispatch('opt_gate'))
    self.assertEqual(calls,[])
    interp.setvar('prj_name','HDMI_media_board_WAV');interp.eval(dispatch('opt_gate'))
    self.assertEqual(calls,[('gate','eram_init','on'),('gate','opt_area','high'),('gate','pack_effort','high')])
   finally:os.chdir(previous)

 def test_missing_pointer_blocks_each_project_stage_only(self):
  interp=tkinter.Tcl();previous=Path.cwd();calls=[]
  interp.createcommand('set_param',lambda *args:calls.append(args) or '')
  with tempfile.TemporaryDirectory(prefix='hdmi missing pointer ') as temp:
   try:
    os.chdir(temp)
    for stage,_ in STAGES:
     with self.subTest(stage=stage):
      interp.setvar('prj_name','AnotherProject');interp.eval(dispatch(stage))
      interp.setvar('prj_name','HDMI_media_board_WAV')
      with self.assertRaisesRegex(tkinter.TclError,'root pointer is missing'):
       interp.eval(dispatch(stage))
    self.assertEqual(calls,[])
   finally:os.chdir(previous)

 def test_stale_pointer_still_blocks_each_project_stage(self):
  interp=tkinter.Tcl();previous=Path.cwd();calls=[]
  interp.setvar('prj_name','HDMI_media_board_WAV')
  interp.createcommand('set_param',lambda *args:calls.append(args) or '')
  with tempfile.TemporaryDirectory(prefix='hdmi stale pointer ') as temp:
   root=Path(temp);run=root/'Runs/syn_1';run.mkdir(parents=True)
   (root/'Runs/.hdmi_gui_root.txt').write_text((root/'missing project').as_posix())
   try:
    os.chdir(run)
    for stage,_ in STAGES:
     with self.subTest(stage=stage):
      with self.assertRaisesRegex(tkinter.TclError,'root is stale'):
       interp.eval(dispatch(stage))
    self.assertEqual(calls,[])
   finally:os.chdir(previous)

 def test_external_runs_pointer_locates_project_from_syn_and_seed(self):
  interp=tkinter.Tcl();previous=Path.cwd();calls=[]
  interp.setvar('prj_name','HDMI_media_board_WAV')
  interp.createcommand('set_param',lambda *args:calls.append(args) or '')
  interp.createcommand('get_param',lambda *args:'on' if args[-1]=='eram_init' else 'high')
  with tempfile.TemporaryDirectory(prefix='hdmi junction layout ') as temp:
   # A Runs junction can place the real cwd outside the project ancestor tree.
   root=Path(temp)/'HDMI v1.0';(root/'tools').mkdir(parents=True)
   runs=Path(temp)/'HDMI_M0_GUI/HDMI_media_board_WAV_Runs';runs.mkdir(parents=True)
   (runs/'.hdmi_gui_root.txt').write_text(root.as_posix())
   (root/'HDMI_media_board_WAV.al').write_text('fixture')
   (root/'tools/td_gui_profile.tcl').write_text(project_tcl())
   try:
    for relative,stage in [('syn_1','opt_gate'),('phy_1/seed_17','opt_place')]:
     with self.subTest(run=relative):
      run=runs/relative;run.mkdir(parents=True);os.chdir(run);calls.clear()
      interp.eval(dispatch(stage))
      self.assertIn(('gate','opt_area','high') if stage=='opt_gate'
                    else ('place','pr_strategy','5'),calls)
      fields=interp.splitlist((run/('.hdmi_gui_'+stage+'.profile')).read_text())
      receipt=dict(zip(fields[::2],fields[1::2]))
      self.assertEqual(receipt['root'],root.as_posix())
      self.assertEqual(receipt['stage'],stage)
   finally:os.chdir(previous)

 def test_legacy_v1_templates_migrate_once_without_vendor_changes(self):
  for name in ['DefaultFlow.tcl','MultiSeed.tcl']:
   with self.subTest(template=name):
    base=remove_dispatch((TD/'doc/scripts'/name).read_bytes())
    legacy=base;newline=b'\r\n' if b'\r\n' in base else b'\n'
    for stage,_ in STAGES:
     anchor=('### Editable zone for '+stage+' ###').encode()+newline
     block=LEGACY_DISPATCH.replace('STAGE',stage).encode().replace(b'\n',newline)
     legacy=legacy.replace(anchor,anchor+block,1)
    self.assertEqual(remove_dispatch(legacy),base)
    updated=template_patch(legacy,name)
    self.assertNotEqual(updated,legacy)
    self.assertEqual(remove_dispatch(updated),base)
    self.assertEqual(template_patch(updated,name),updated)
    self.assertEqual(updated,template_patch(base,name))

 def test_unknown_or_duplicate_legacy_dispatch_is_rejected(self):
  old=LEGACY_DISPATCH.replace('STAGE','opt_gate').encode()
  for newline in [b'\n',b'\r\n']:
   block=old.replace(b'\n',newline);current=dispatch('opt_gate').encode().replace(b'\n',newline)
   with self.subTest(newline=newline):
    with self.assertRaisesRegex(ValueError,'Unknown modified'):
     remove_dispatch(block.replace(b'HDMI_media_board_WAV',b'UnexpectedProject'))
    with self.assertRaisesRegex(ValueError,'Duplicate'):
     remove_dispatch(block+current)

if __name__=='__main__':unittest.main()
