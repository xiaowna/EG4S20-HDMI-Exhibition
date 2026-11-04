# 从 GUI 已修复的布线数据库刷新最终时序与 QoR 报告。
source [file join [file dirname [file normalize [info script]]] tools project_setup.tcl]
set hdmi_project_file [hdmi_prepare_project]
set hdmi_gui_directory [hdmi_gui_run_directory]
set hdmi_gui_database [file join $hdmi_gui_directory HDMI_media_board_WAV_pr.db]
if {![file isfile $hdmi_gui_database]} {
    error "No routed seed-13 GUI database; run the full MultiSeed flow first"
}
import_device eagle_s20.db -package EG4S20BG256
open_project $hdmi_project_file
import_db $hdmi_gui_database
update_timing -mode final
report_timing_status -file [file join $hdmi_gui_directory HDMI_media_board_WAV_phy.ts]
hdmi_report_checked_timing [file join $hdmi_gui_directory final_timing.rpt]
report_qor -step route -file [file join $hdmi_gui_directory route.qor]
puts {GUI_TIMING_REPORTS_REFRESHED}
exit
