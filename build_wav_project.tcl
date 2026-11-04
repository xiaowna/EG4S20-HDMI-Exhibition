source [file join [file dirname [file normalize [info script]]] tools project_setup.tcl]
set hdmi_project_file [hdmi_prepare_project]
import_device eagle_s20.db -package EG4S20BG256
open_project $hdmi_project_file
elaborate -top hdmi_media_board_top
read_adc board.adc
read_sdc board.sdc
# Preserve the fixed Chinese font contents in the configured block RAM.
set_param gate eram_init on
# Measured solar profile: use area optimization and stronger gate packing.
set_param gate opt_area high
set_param gate pack_effort high
optimize_rtl
optimize_gate -packarea board_wav_gate.area
export_db board_wav_gate.db
# TD's official MultiSeed.tcl uses this parameter. Keep the chosen placement
# reproducible for the animated gallery build; all timing gates remain active.
set_param place seed 13
set_param place pr_strategy 5
# Match the routed animated gallery profile; keep seed 13 and strategy 5.
set_param place effort high
set_param place hfn_opt_effort high
set_param place opt_timing high
set_param place post_place_opt high
set_param route post_route_opt high
set_param route effort routability
place
route
fix_hold
report_area -io_info -file board_wav_phy.area
hdmi_report_checked_timing board_wav_timing.rpt
report_timing_exception -file reports/board_wav_cdc_exceptions.rpt
export_db board_wav_pr.db
bitgen -bit HDMI_media_board_WAV.bit
puts {BOARD_BUILD_FINISHED}
exit

