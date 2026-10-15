#!/usr/bin/env bash
# Captures the README/post waveform figures from real XSim runs on a hidden X display.
# Each figure: one scenario + one view file. Output: docs/waves/<name>.png (wave pane only).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PATH=/tools/Xilinx/2025.2/Vivado/bin:$PATH
DISP=:79
OUT=$ROOT/docs/waves; mkdir -p "$OUT"
if [ ! -e /tmp/.X11-unix/X79 ]; then
  Xvfb $DISP -screen 0 2600x1650x24 -nolisten tcp >/dev/null 2>&1 &
  timeout 20 bash -c 'until [ -e /tmp/.X11-unix/X79 ]; do sleep 1; done'
fi
cd "$ROOT/build/sim"
shoot() {   # name scenario view height(px of rows to keep)
  local name=$1 s=$2 view=$3 h=$4 done=/dev/shm/reflex_cap_$1.done
  rm -f "$done"
  DISPLAY=$DISP REFLEX_WCFG=$ROOT/scripts/wave_views/$view.wcfg REFLEX_DONE=$done \
    xsim tb_core -gui -testplusarg STIM=vec/$s.stim -testplusarg CFG=vec/$s.cfg \
    -testplusarg OUT=/dev/shm/reflex_cap_$1.got -tclbatch "$ROOT/scripts/waves_view.tcl" > /dev/shm/reflex_cap_$1.log 2>&1 &
  local pid=$!
  timeout 180 bash -c "until [ -e $done ]; do sleep 2; done"
  sleep 4
  import -display $DISP -window root "$OUT/${name}_full.png"
  convert "$OUT/${name}_full.png" -crop 1880x${h}+666+128 +repage "$OUT/$name.png"
  kill $pid 2>/dev/null; pkill -f "reflex_cap_$1.got" 2>/dev/null || true; sleep 2
  echo "captured $name ($s, $view)"
}
shoot guard_on       s2_burst_guard     compare     500
shoot guard_off      s3_burst_noguard   compare     500
shoot overview       s5_occlusion_burst overview    800
shoot decision       s5_occlusion_burst decision    800
shoot guard_onset    s5_occlusion_burst guard_onset 560
shoot coast          s5_occlusion_burst coast       600
