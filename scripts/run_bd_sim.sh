#!/usr/bin/env bash
# Simulates the "reflex" hierarchy exactly as Vivado generated it from the block
# design (the BD's own wiring of the seven sub-modules), through the AXI4-Lite
# port, and compares against the Python model. Needs scripts/build_bd.tcl first.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PATH=/tools/Xilinx/2025.2/Vivado/bin:$PATH
GEN=$ROOT/build/vivado/reflex_soc.gen/sources_1/bd/reflex_bd
NET=$GEN/sim/reflex_bd.v
HIER=$(grep -oE "^module reflex_imp_\w+" "$NET" | awk '{print $2}')
echo "BD reflex hierarchy module: $HIER"
OUT=$ROOT/build/bdsim
mkdir -p "$OUT" && cd "$OUT"
python3 -I "$ROOT/model/reflex.py" gen "$OUT/vec" > /dev/null
xvlog "$ROOT"/rtl/reflex_{regs,event_gate,window,divider,tracker,servo,leds}.v \
      "$GEN"/ip/reflex_bd_{regs,gate,window,divider,tracker,servo,leds}_0/sim/*.v "$NET" > xvlog.log
xvlog -sv -d BD_NETLIST -d BD_HIER_MOD=$HIER "$ROOT/tb/tb_top.sv" > xvlog_tb.log
xelab -debug typical -timescale 1ns/1ps tb_top -s tb_bd > xelab.log
fail=0
for s in s4_axi_top s5_occlusion_burst; do
  xsim tb_bd -R -testplusarg STIM=vec/$s.stim -testplusarg CFG=vec/$s.cfg \
       -testplusarg OUT=vec/$s.bd.got -testplusarg SEEN=vec/$s.bd.seen > "xsim_$s.log"
  grep -q "AXI READBACK PASS" "xsim_$s.log" || { echo "$s: AXI readback FAILED"; fail=1; }
  python3 -I "$ROOT/model/reflex.py" model vec/$s.bd.seen vec/$s.cfg vec/$s.bd.exp
  python3 -I "$ROOT/model/reflex.py" compare vec/$s.bd.exp vec/$s.bd.got || fail=1
  grep -E "^END" vec/$s.bd.got
done
if [ $fail -ne 0 ]; then echo "BD NETLIST SIM FAIL"; exit 1; fi
echo "BD NETLIST SIM PASS"
