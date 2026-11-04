cd [file dirname [file normalize [info script]]]
import_device eagle_s20.db -package EG4S20BG256
open_project tone_bank_check.al
elaborate -top audio_tone_bank
read_sdc tone_bank.sdc
optimize_rtl
optimize_gate -packarea ../../reports/tone_bank_gate.area
export_db tone_bank_gate.db
puts {TONE_BANK_SYNTHESIS_FINISHED}
exit
