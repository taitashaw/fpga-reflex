#!/usr/bin/env bash
# XSim waveform window: occlusion + burst scenario, one signal group per sub-module.
export PATH=/tools/Xilinx/2025.2/Vivado/bin:$PATH
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT/build/sim"
s=s5_occlusion_burst
exec xsim tb_core -gui -testplusarg STIM=vec/$s.stim -testplusarg CFG=vec/$s.cfg \
     -testplusarg OUT=vec/$s.gui.got -tclbatch "$ROOT/scripts/waves_view.tcl"
