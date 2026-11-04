# The default action requires complete hardware evidence. Logic-only actions
# intentionally do not read the draft ADC or produce physical results/bitstreams.
source [file join [file dirname [file normalize [info script]]] tools project_setup.tcl]
source [file join $hdmi_project_root tools dmz_media_setup.tcl]
cd $hdmi_project_root
if {![info exists dmz_media_action]} { set dmz_media_action build }
if {$dmz_media_action ni {check synthesize build}} { error "Unknown DMZ media action" }
if {[info exists ::env(DMZ_MEDIA_PYTHON)]} {
    set dmz_python $::env(DMZ_MEDIA_PYTHON)
} else {
    set dmz_python [lindex [auto_execok python] 0]
}
if {$dmz_python eq ""} { error "Python is needed to validate the DMZ project" }
set check_args [list $dmz_python [file join $hdmi_project_root tools check_dmz_media.py]]
if {$dmz_media_action eq "build"} { lappend check_args --require-hardware }
puts [exec {*}$check_args]
file mkdir reports
import_device eagle_s20.db -package EG4S20BG256
set dmz_project_file [file join $hdmi_project_root DMZ_HDMI_MEDIA.al]
if {![file isfile $dmz_project_file]} { error "DMZ project file is missing: $dmz_project_file" }
puts "DMZ_PROJECT_FILE $dmz_project_file"
open_project $dmz_project_file
elaborate -top dmz_hdmi_media_top
if {$dmz_media_action eq "check"} {
    puts {DMZ_MEDIA_ELABORATION_FINISHED_NO_BITSTREAM}
    exit
}
if {$dmz_media_action eq "build"} {
    read_adc dmz_media.adc
    read_sdc dmz_media.sdc
}
optimize_rtl
optimize_gate -packarea reports/dmz_media_gate.area
export_db reports/dmz_media_gate.db
if {$dmz_media_action eq "synthesize"} {
    puts {DMZ_MEDIA_SYNTHESIS_FINISHED_NO_BITSTREAM}
    exit
}
place
route
fix_hold
report_area -io_info -file reports/dmz_media_phy.area
hdmi_report_checked_timing reports/dmz_media_timing.rpt dmz_hdmi_media_top
dmz_report_checked_cdc reports/dmz_media_cdc_exceptions.rpt
export_db reports/dmz_media_pr.db
if {[info exists ::env(DMZ_MEDIA_RUN_ID)]} {
    set dmz_run_id $::env(DMZ_MEDIA_RUN_ID)
} else {
    set dmz_run_id "[pid]_[clock clicks]"
}
if {![regexp {^[A-Za-z0-9_]+$} $dmz_run_id]} { error "Invalid DMZ build run ID" }
set pending_bit "DMZ_HDMI_MEDIA.pending.${dmz_run_id}.bit"
if {[file exists $pending_bit]} { error "Current DMZ pending bitstream already exists" }
bitgen -bit $pending_bit
if {![file isfile $pending_bit] || [file size $pending_bit] == 0} {
    error "TD did not generate the current DMZ media bitstream"
}
puts "DMZ_MEDIA_BITSTREAM_GENERATED $dmz_run_id [file size $pending_bit]"
# The Python runner checks source integrity and publishes this unique pending bit.
puts {DMZ_MEDIA_BUILD_FINISHED}
exit
