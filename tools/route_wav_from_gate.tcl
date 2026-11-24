# Reuse the checked gate database when a placement seed cannot route.
source [file join [file dirname [file normalize [info script]]] project_setup.tcl]
set hdmi_project_file [hdmi_prepare_project]
if {![info exists ::env(HDMI_ROUTE_SEED)] || ![string is integer -strict $::env(HDMI_ROUTE_SEED)]} {
    error {Set HDMI_ROUTE_SEED to an integer before routing}
}
set hdmi_seed $::env(HDMI_ROUTE_SEED)
import_device eagle_s20.db -package EG4S20BG256
open_project $hdmi_project_file
import_db board_wav_gate.db
set_param place seed $hdmi_seed
set_param place pr_strategy 5
set_param place effort high
set_param place hfn_opt_effort high
set_param place opt_timing high
set_param place post_place_opt high
set_param place cn_opt_effort high
set_param place critical_hfn_opt on
set_param place ce_weight on
set_param place enhanced_beeline_opt 3
set_param route post_route_opt high
set_param route effort routability
place
route
fix_hold
set hdmi_prefix [file join reports seed$hdmi_seed]
report_area -io_info -file ${hdmi_prefix}_phy.area
hdmi_report_checked_timing ${hdmi_prefix}_timing.rpt
report_timing_exception -file ${hdmi_prefix}_cdc_exceptions.rpt
export_db ${hdmi_prefix}_pr.db
bitgen -bit HDMI_FAST_8PLANETS_SEED${hdmi_seed}.bit
puts {ROUTE_FROM_GATE_FINISHED}
exit
