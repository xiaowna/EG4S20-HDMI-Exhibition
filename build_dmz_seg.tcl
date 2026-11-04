# Independent DMZ seven-segment display test. Keep the HX4S20 player pin map unchanged.
source [file join [file dirname [file normalize [info script]]] tools project_setup.tcl]
cd $hdmi_project_root
set project_file [file join $hdmi_project_root DMZ_SEG_TEST.al]
set channel [open $project_file r]
set project_text [read $channel]
close $channel
if {![regexp {<Project[^>]*\sPath="([^"]+)"} $project_text match stored_root] ||
    ![string equal -nocase [file normalize $stored_root] $hdmi_project_root]} {
    error "DMZ project Path points to another directory; update the project path first"
}
if {![regexp {<Device>EG4S20BG256</Device>} $project_text] ||
    ![regexp {<MODULE>dmz_seg_test_top</MODULE>} $project_text]} {
    error "DMZ project device or top module is incorrect"
}
set file_refs [regexp -all -inline {<File\s+Path="([^"]+)"} $project_text]
if {[llength $file_refs] == 0} { error "DMZ project has no source files" }
foreach {match relative_path} $file_refs {
    if {![file isfile [file join $hdmi_project_root $relative_path]]} {
        error "Missing DMZ project file: $relative_path"
    }
}
file mkdir reports
import_device eagle_s20.db -package EG4S20BG256
open_project $project_file
elaborate -top dmz_seg_test_top
read_adc dmz_seg.adc
read_sdc dmz_seg.sdc
optimize_rtl
optimize_gate -packarea reports/dmz_seg_gate.area
export_db reports/dmz_seg_gate.db
place
route
fix_hold
report_area -io_info -file reports/dmz_seg_phy.area
hdmi_report_checked_timing reports/dmz_seg_timing.rpt dmz_seg_test_top
export_db reports/dmz_seg_pr.db
set pending_bit "DMZ_SEG_TEST.pending.[pid].bit"
bitgen -bit $pending_bit
if {![file isfile $pending_bit] || [file size $pending_bit] == 0} {
    error "TD did not generate the current DMZ bitstream"
}
file rename -force $pending_bit [file join $hdmi_project_root DMZ_SEG_TEST.bit]
puts {DMZ_SEG_BUILD_FINISHED}
exit
