# Block design for the ZCU104: Zynq UltraScale+ PS -> SmartConnect -> "reflex"
# hierarchy. The hierarchy holds the seven sub-modules as separate module
# references so the diagram shows how the reflex is built:
#   regs (AXI4-Lite) -> gate (guard) -> window -> divider -> tracker -> servo, leds
# Then validate, synthesise, implement and write the bitstream.
# Run: vivado -mode batch -source scripts/build_bd.tcl
set root [file normalize [file dirname [info script]]/..]
set proj $root/build/vivado
create_project reflex_soc $proj -part xczu7ev-ffvc1156-2-e -force
set_property board_part xilinx.com:zcu104:part0:1.1 [current_project]
add_files -norecurse [glob $root/rtl/reflex_*.v]
add_files -fileset constrs_1 -norecurse $root/constraints/zcu104_reflex.xdc
add_files -fileset sim_1 -norecurse [list $root/tb/tb_core.sv $root/tb/tb_top.sv]
update_compile_order -fileset sources_1

proc ipdef {name} { return [lindex [lsort [get_ipdefs -filter "NAME == $name"]] end] }

create_bd_design reflex_bd

# ---------------- processor, interconnect, reset ----------------
create_bd_cell -type ip -vlnv [ipdef zynq_ultra_ps_e] ps_0
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e -config {apply_board_preset "1"} [get_bd_cells ps_0]
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__USE__M_AXI_GP2 {0} \
    CONFIG.PSU__FPGA_PL0_ENABLE {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
] [get_bd_cells ps_0]
create_bd_cell -type ip -vlnv [ipdef smartconnect] axi_smc
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI {1}] [get_bd_cells axi_smc]
create_bd_cell -type ip -vlnv [ipdef proc_sys_reset] rst_ps_0_100M

# ---------------- reflex hierarchy ----------------
create_bd_cell -type hier reflex
create_bd_pin -dir I -type clk reflex/clk
create_bd_pin -dir I -type rst reflex/aresetn
create_bd_intf_pin -mode Slave -vlnv xilinx.com:interface:aximm_rtl:1.0 reflex/s_axi
create_bd_pin -dir O -from 3 -to 0 reflex/led
foreach {cell module} {regs reflex_regs gate reflex_event_gate window reflex_window \
                       divider reflex_divider tracker reflex_tracker servo reflex_servo leds reflex_leds} {
    create_bd_cell -type module -reference $module reflex/$cell
}

proc net {src args} {
    set pins [list [get_bd_pins reflex/$src]]
    foreach d $args { lappend pins [get_bd_pins reflex/$d] }
    connect_bd_net {*}$pins
}
connect_bd_intf_net [get_bd_intf_pins reflex/s_axi] [get_bd_intf_pins reflex/regs/s_axi]
net clk           regs/aclk gate/clk window/clk divider/clk tracker/clk servo/clk leds/clk
net aresetn       regs/aresetn
net regs/core_rst gate/rst window/rst divider/rst tracker/rst servo/rst leds/rst
net regs/enable   gate/enable window/enable divider/enable tracker/enable
net regs/guard_en gate/guard_en
net regs/window_cycles window/window_cycles
net regs/paddle_y      tracker/paddle_y
net regs/min_events    tracker/min_events
net regs/gravity       tracker/gravity
net regs/roi_radius    gate/roi_radius
net regs/evt_valid     gate/s_valid
net regs/evt_data      gate/s_data
net gate/accept        window/accept
net gate/ex            window/ex
net gate/ey            window/ey
net gate/guard_active  regs/guard_active leds/guard_active
net gate/events_in     regs/events_in
net gate/events_dropped regs/events_dropped
net window/tick        tracker/tick regs/tick
net window/snap_valid  tracker/snap_valid
net window/snap_cnt    tracker/snap_cnt divider/cnt
net window/snap_sx     divider/sx
net window/snap_sy     divider/sy
net window/close_tick  tracker/close_tick
net tracker/div_start  divider/start
net divider/done       tracker/div_done
net divider/qx         tracker/qx
net divider/qy         tracker/qy
net tracker/armed      gate/armed
net tracker/roi_x      gate/roi_x
net tracker/roi_y      gate/roi_y
net tracker/cmd_fire   servo/cmd_fire
net tracker/xi_next    servo/xi
net tracker/cmd_valid  leds/cmd_valid
net tracker/locked     regs/locked leds/locked
net tracker/x_pred     regs/x_pred
net tracker/latency    regs/latency
net tracker/max_latency regs/max_latency
net tracker/steps_out  regs/steps_out
net tracker/cmd_count  regs/cmd_count
net tracker/miss_count regs/miss_count
net tracker/nointercept_count regs/nointercept_count
net servo/servo_pulse  regs/servo_pulse
net servo/servo_pwm    leds/servo_pwm
net leds/led           led

# ---------------- top-level wiring ----------------
connect_bd_net [get_bd_pins ps_0/pl_clk0] [get_bd_pins ps_0/maxihpm0_fpd_aclk] \
    [get_bd_pins axi_smc/aclk] [get_bd_pins rst_ps_0_100M/slowest_sync_clk] [get_bd_pins reflex/clk]
connect_bd_net [get_bd_pins ps_0/pl_resetn0] [get_bd_pins rst_ps_0_100M/ext_reset_in]
connect_bd_net [get_bd_pins rst_ps_0_100M/peripheral_aresetn] [get_bd_pins axi_smc/aresetn] [get_bd_pins reflex/aresetn]
connect_bd_intf_net [get_bd_intf_pins ps_0/M_AXI_HPM0_FPD] [get_bd_intf_pins axi_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc/M00_AXI] [get_bd_intf_pins reflex/s_axi]
create_bd_port -dir O -from 3 -to 0 led
connect_bd_net [get_bd_pins reflex/led] [get_bd_ports led]

assign_bd_address
regenerate_bd_layout -hierarchy [get_bd_cells reflex]
regenerate_bd_layout
validate_bd_design
save_bd_design
puts "BD_VALIDATED"
foreach s [get_bd_addr_segs -of_objects [get_bd_addr_spaces ps_0/Data]] {
    puts "ADDR: [get_property NAME $s] offset [get_property OFFSET $s] range [get_property RANGE $s]"
}
puts "REFLEX_CELLS: [lsort [get_bd_cells reflex/*]]"
write_bd_tcl -force $root/build/reflex_bd_export.tcl

make_wrapper -files [get_files reflex_bd.bd] -top -import
set_property top reflex_bd_wrapper [current_fileset]
update_compile_order -fileset sources_1
# simulation netlist of the BD, so the "reflex" hierarchy itself can be simulated (scripts/run_bd_sim.sh)
generate_target simulation [get_files reflex_bd.bd]

# project simulation set: tb_core on the occlusion + burst scenario, for the waveform tab
set vec $root/build/sim/vec
set_property top tb_core [get_filesets sim_1]
set_property -name {xsim.simulate.xsim.more_options} -value \
    "-testplusarg STIM=$vec/s5_occlusion_burst.stim -testplusarg CFG=$vec/s5_occlusion_burst.cfg -testplusarg OUT=$vec/s5_occlusion_burst.prj.got" \
    -objects [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {0ns} -objects [get_filesets sim_1]

launch_runs synth_1 -jobs 8
wait_on_run synth_1
puts "SYNTH_STATUS: [get_property STATUS [get_runs synth_1]]"
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { error "synthesis failed" }
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
puts "IMPL_STATUS: [get_property STATUS [get_runs impl_1]]"

open_run impl_1
set rpt $root/build/reports
file mkdir $rpt
report_timing_summary -file $rpt/timing_summary.rpt
report_utilization -file $rpt/utilization.rpt
report_utilization -hierarchical -file $rpt/utilization_hier.rpt
report_drc -file $rpt/drc.rpt
source $root/scripts/report_submodules.tcl
submodule_table $rpt/utilization_per_submodule.rpt
puts "WNS: [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]"
puts "WHS: [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]"
set bit [glob -nocomplain [get_property DIRECTORY [get_runs impl_1]]/*.bit]
puts "BITSTREAM: $bit"
