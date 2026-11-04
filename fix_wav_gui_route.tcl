# 对 TD 图形界面已布线数据库补做保持时间修复。
# 当前 MultiSeed 流程已执行 fix_hold；仅在最终报告仍有保持时间违例时补做。
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
fix_hold
update_timing -mode final
hdmi_report_checked_timing reports/gui_holdfixed_timing.rpt
report_timing_exception -file reports/gui_holdfixed_cdc.rpt
export_db reports/gui_holdfixed_pr.db
bitgen -bit reports/HDMI_media_board_WAV_GUI_holdfixed.bit
report_area -io_info -file [file join $hdmi_gui_directory HDMI_media_board_WAV_phy.area]
report_timing_status -file [file join $hdmi_gui_directory HDMI_media_board_WAV_phy.ts]
report_timing_summary -file [file join $hdmi_gui_directory HDMI_media_board_WAV_pr.timing]
report_timing_exception -file [file join $hdmi_gui_directory HDMI_media_board_WAV_exception.timing]
flow_status -file [file join $hdmi_gui_directory route_flow.status]
report_qor -step route -file [file join $hdmi_gui_directory route.qor]
export_db $hdmi_gui_database
bitgen -bit [file join $hdmi_gui_directory HDMI_media_board_WAV.bit]
puts {GUI_HOLD_FIX_FINISHED}
exit
