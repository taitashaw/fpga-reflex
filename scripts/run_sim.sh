#!/usr/bin/env bash
# Regression: generate stimulus, run every scenario in XSim, compare each log
# exactly against the Python model, then print the physics error report.
# Usage: scripts/run_sim.sh [rtl_dir]   (rtl_dir lets a mutant run from a copy)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RTL=${1:-$ROOT/rtl}
export PATH=/tools/Xilinx/2025.2/Vivado/bin:$PATH
OUT=${2:-$ROOT/build/sim}
mkdir -p "$OUT"
cd "$OUT"
python3 -I "$ROOT/model/reflex.py" gen "$OUT/vec"
xvlog -sv "$RTL"/reflex_*.v "$ROOT/tb/tb_core.sv" "$ROOT/tb/tb_top.sv" > xvlog.log
xelab -debug typical -timescale 1ns/1ps tb_core -s tb_core > xelab_core.log
xelab -debug typical -timescale 1ns/1ps tb_top -s tb_top > xelab_top.log
fail=0
for s in s1_clean s2_burst_guard s3_burst_noguard s5_occlusion_burst; do
  xsim tb_core -R -testplusarg STIM=vec/$s.stim -testplusarg CFG=vec/$s.cfg \
       -testplusarg OUT=vec/$s.got > "xsim_$s.log"
  python3 -I "$ROOT/model/reflex.py" model vec/$s.stim vec/$s.cfg vec/$s.exp
  python3 -I "$ROOT/model/reflex.py" compare vec/$s.exp vec/$s.got || fail=1
done
# AXI path: the TB records the ticks the core actually saw; the model runs on that record.
s=s4_axi_top
xsim tb_top -R -testplusarg STIM=vec/$s.stim -testplusarg CFG=vec/$s.cfg \
     -testplusarg OUT=vec/$s.got -testplusarg SEEN=vec/$s.seen > "xsim_$s.log"
grep -q "AXI READBACK PASS" "xsim_$s.log" || { echo "AXI readback FAILED"; grep -E "FAIL|ERROR" "xsim_$s.log" | head; fail=1; }
python3 -I "$ROOT/model/reflex.py" model vec/$s.seen vec/$s.cfg vec/$s.exp
python3 -I "$ROOT/model/reflex.py" compare vec/$s.exp vec/$s.got || fail=1
python3 -I "$ROOT/model/reflex.py" report "$OUT/vec"
if [ $fail -ne 0 ]; then echo "REGRESSION FAIL"; exit 1; fi
echo "REGRESSION PASS"
