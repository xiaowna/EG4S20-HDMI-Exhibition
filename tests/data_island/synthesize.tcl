cd [file dirname [file normalize [info script]]]
import_device eagle_s20.db -package EG4S20BG256
open_project data_island_check.al
elaborate -top hdmi_data_island_encoder
read_sdc core.sdc
optimize_rtl
optimize_gate -packarea ../../reports/data_island_gate.area
export_db data_island_gate.db
puts {DATA_ISLAND_SYNTHESIS_FINISHED}
exit
