source [file join [file dirname [file dirname [file dirname [file normalize [info script]]]]] tools project_setup.tcl]
set hdmi_project_file [hdmi_prepare_project 1]
import_device eagle_s20.db -package EG4S20BG256
open_project $hdmi_project_file
elaborate -top hdmi_media_board_top
puts {BOARD_LOGIC_ONLY: pin mapping, electrical checks and physical timing are not validated}
puts {BOARD_AUDIO_SOURCE_ELABORATION_FINISHED}
exit
