# XSim waveform view of the occlusion + burst scenario (s5). Every signal in the
# design is logged before the run, then the saved view is loaded: one group per
# sub-module (same names as the block design), zoomed on the burst, markers set.
# The run stops at 800 us, just before the testbench's $finish, so the simulator
# does not jump to the source file and cover the waveform.
set here [file normalize [file dirname [info script]]]
log_wave /tb_core/clk
log_wave -recursive [get_objects -r /tb_core/dut/*]
run 800000ns
# Load the view after the window has its full size, so the saved zoom range holds.
# REFLEX_WCFG picks another view (scripts/wave_views/*.wcfg); REFLEX_DONE is touched when loaded.
set view $here/reflex_s5_view.wcfg
if {[info exists ::env(REFLEX_WCFG)]} { set view $::env(REFLEX_WCFG) }
after 6000 [list apply {{view} {
    open_wave_config $view
    if {[info exists ::env(REFLEX_DONE)]} { close [open $::env(REFLEX_DONE) w] }
    puts "WAVES_VIEW_OK"
}} $view]
