# Opens the project with the block design, the "reflex" hierarchy expanded so its
# seven sub-modules are visible. The layout file only sets the drawing; the
# design (.bd) is not changed.
set root [file normalize [file dirname [info script]]/..]
open_project $root/build/vivado/reflex_soc.xpr
open_bd_design [get_files reflex_bd.bd]
regenerate_bd_layout -layout_file $root/scripts/reflex_bd_layout.native
puts "OPEN_BD_OK"
