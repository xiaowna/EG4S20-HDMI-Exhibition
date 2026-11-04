# 以此文件的位置定位工程，避免从其他工作目录启动时构建到旧工程。
set hdmi_project_root [file dirname [file dirname [file normalize [info script]]]]
proc hdmi_prepare_project {{logic_only 0}} {
    global hdmi_project_root
    cd $hdmi_project_root
    set project_file [file join $hdmi_project_root HDMI_media_board_WAV.al]
    set channel [open $project_file r]
    set project_text [read $channel]
    close $channel
    if {![regexp {<Project[^>]*\sPath="([^"]+)"} $project_text match stored_root] ||
        ![string equal -nocase [file normalize $stored_root] $hdmi_project_root]} {
        error "TD project Path points to another directory; update the project path first"
    }
    if {![regexp {<Device>EG4S20BG256</Device>} $project_text]} {
        error "HDMI project device is not EG4S20BG256"
    }
    if {![regexp {<MODULE>hdmi_media_board_top</MODULE>} $project_text]} {
        error "HDMI project top module is missing or incorrect"
    }
    set file_refs [regexp -all -inline {<File\s+Path="([^"]+)"} $project_text]
    if {[llength $file_refs] == 0} { error "HDMI project has no source files" }
    foreach {match relative_path} $file_refs {
        if {![file isfile [file join $hdmi_project_root $relative_path]]} {
            error "Missing project file: $relative_path"
        }
    }
    if {[info exists ::env(HDMI_PROJECT_PYTHON)]} {
        set hdmi_python $::env(HDMI_PROJECT_PYTHON)
    } else {
        set hdmi_python [lindex [auto_execok python] 0]
    }
    if {$hdmi_python eq ""} { error "Python is needed to validate the HDMI project" }
    set check_args [list $hdmi_python [file join $hdmi_project_root tools check_project.py] --root $hdmi_project_root]
    if {$logic_only} { lappend check_args --logic-only }
    puts [exec {*}$check_args]
    file mkdir [file join $hdmi_project_root reports]
    return $project_file
}

proc hdmi_gui_run_directory {} {
    # The public MultiSeed configuration runs only seed 13. Never fall back to
    # phy_1's old normal-flow DB, which may contain the failed seed-0 layout.
    return [file join HDMI_media_board_WAV_Runs phy_1 seed_13]
}

# 仅接受当前器件布线后的时序报告。微小负值仍是违例，不取整放行。
proc hdmi_require_timing {report_file {top_module hdmi_media_board_top}} {
    set channel [open $report_file r]
    set timing_text [read $channel]
    close $channel
    foreach {pattern description} [list \
        [format {Top Model\s*:\s*%s\s} $top_module] {top module} \
        {Device\s*:\s*EG4S20BG256\s} {device} \
        {Confidence\s*:\s*Routed\s} {routed timing}] {
        if {![regexp $pattern $timing_text]} {
            error "Unrecognized $description in timing report: $report_file"
        }
    }
    set result [dict create]
    foreach metric {SWNS HWNS STNS HTNS {Period Check WNS}} {
        set pattern [format {\m%s:\s*([-+]?[0-9]+(?:\.[0-9]+)?)\s*ns\M} $metric]
        set values [regexp -all -inline $pattern $timing_text]
        if {[llength $values] != 2} {
            error "Missing, duplicate or invalid $metric in timing report: $report_file"
        }
        set value [lindex $values 1]
        if {$value < 0.0} {
            error "Timing failed: $metric=${value}ns; bitstream generation is blocked"
        }
        dict set result $metric $value
    }
    puts "HDMI_TIMING_PASSED SWNS=[dict get $result SWNS]ns HWNS=[dict get $result HWNS]ns"
    return $result
}

# 使用本次独有的报告名，防止 TD 未写出新报告时误读上次的正余量。
proc hdmi_report_checked_timing {report_file {top_module hdmi_media_board_top}} {
    set pending_file "${report_file}.pending.[pid].[clock clicks]"
    report_timing_summary -file $pending_file
    if {![file isfile $pending_file]} {
        error "TD did not produce a new timing report: $pending_file"
    }
    file rename -force $pending_file $report_file
    return [hdmi_require_timing $report_file $top_module]
}
