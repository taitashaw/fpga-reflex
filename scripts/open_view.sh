#!/usr/bin/env bash
# Opens two windows: Vivado with the block design (reflex expanded), then the XSim waveform.
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PATH=/tools/Xilinx/2025.2/Vivado/bin:$PATH
(cd "$ROOT/build" && vivado -mode gui -nojournal -log open_bd.log -source "$ROOT/scripts/open_bd.tcl") &
"$ROOT/scripts/open_waves.sh"
wait
