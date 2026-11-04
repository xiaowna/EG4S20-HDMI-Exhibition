# Validate the full-player FIFO constraints before generating a DMZ bitstream.
proc dmz_require_cdc {report_file} {
    set channel [open $report_file r]
    set text [read $channel]
    close $channel
    foreach {from expected} {
        {u_player/u_media/u_display/u_prefetch/u_fifo/wg[*]} 9
        {u_player/u_media/u_display/u_prefetch/u_fifo/rg[*]} 9
        {av/fifo/wr_gray[*]} 12
        {av/fifo/rd_gray[*]} 12
    } {
        set matched 0
        foreach line [split $text "\n"] {
            if {[string first $from $line] >= 0 &&
                [regexp {^\s*([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+set_max_delay\s} $line match total dominated shadowed ignored]} {
                incr matched
                if {$total != $expected || $dominated != $expected || $shadowed != 0 || $ignored != 0} {
                    error "DMZ CDC constraint is not fully effective: $from"
                }
            }
        }
        if {$matched != 1} { error "DMZ CDC constraint summary is missing or duplicated: $from" }
    }
    set metrics [regexp -all -inline {(?:SWNS|HWNS)\s*:?\s*([-+]?[0-9]+(?:\.[0-9]+)?)ns} $text]
    if {[llength $metrics] < 16 ||
        [llength $metrics] != 2 * [regexp -all {SWNS|HWNS} $text]} {
        error "DMZ CDC timing metrics are missing or invalid"
    }
    foreach {match value} $metrics {
        if {$value < 0.0} { error "DMZ CDC timing failed: ${value}ns" }
    }
    puts {DMZ_CDC_CONSTRAINTS_PASSED 9 9 12 12}
}

proc dmz_report_checked_cdc {report_file} {
    set pending_file "${report_file}.pending.[pid].[clock clicks]"
    if {[file exists $pending_file]} { error "DMZ CDC pending report already exists" }
    report_timing_exception -file $pending_file
    if {![file isfile $pending_file]} { error "TD did not produce a new DMZ CDC report" }
    file rename -force $pending_file $report_file
    dmz_require_cdc $report_file
}
