cd [file dirname [file normalize [info script]]]
import_device eagle_s20.db -package EG4S20BG256
open_project audio_source_check.al
elaborate -top audio_test_tone
create_clock -name system -period 20 [get_ports clk]
optimize_rtl
optimize_gate -packarea ../../reports/audio_source_gate.area
export_db audio_source_gate.db
puts {AUDIO_SOURCE_SYNTHESIS_FINISHED}
exit
