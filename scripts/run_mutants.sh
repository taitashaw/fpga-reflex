#!/usr/bin/env bash
# Six deliberate RTL breaks; each must make the regression fail. Log: build/mutants.log
ROOT=$(cd "$(dirname "$0")/.." && pwd)
M=/dev/shm/reflex_mut; rm -rf $M; mkdir -p $M
python3 -I - "$ROOT" <<'PY'
import shutil, os, glob, sys
root=sys.argv[1]; M='/dev/shm/reflex_mut'
muts = {
 'm1_guard_off': ('reflex_event_gate.v', "wire in_roi = (adx <= rlim) && (ady <= rlim);", "wire in_roi = 1'b1;"),
 'm2_no_gravity_step': ('reflex_tracker.v', "vy <= vy + g_q8;", "vy <= vy;"),
 'm3_divider_cmp': ('reflex_divider.v', "wire        gx = rx_sh >= {1'b0, divisor};", "wire        gx = rx_sh > {1'b0, divisor};"),
 'm4_latency_off_by_one': ('reflex_tracker.v', "tick - close_tick + 32'd1", "tick - close_tick"),
 'm5_no_coast': ('reflex_tracker.v', "parameter COAST_MAX = 2", "parameter COAST_MAX = 0"),
 'm6_axi_read_swap': ('reflex_regs.v', "5'h07: s_axi_rdata <= {22'd0, x_pred};", "5'h07: s_axi_rdata <= {16'd0, latency};"),
}
for name,(f,a,b) in muts.items():
    d=f'{M}/{name}/rtl'; os.makedirs(d)
    for g in glob.glob(f'{root}/rtl/reflex_*.v'): shutil.copy(g, d)
    s=open(f'{d}/{f}').read(); assert s.count(a)==1, (name, s.count(a)); open(f'{d}/{f}','w').write(s.replace(a,b))
PY
caught=0; total=0
for m in $(ls $M); do
  total=$((total+1))
  if "$ROOT/scripts/run_sim.sh" $M/$m/rtl $M/$m/out > $M/$m.log 2>&1; then echo "$m: NOT CAUGHT"
  else caught=$((caught+1)); echo "$m: CAUGHT ($(grep -cE 'MISMATCH|AXI readback FAILED' $M/$m.log) failing checks)"; fi
done
echo "MUTANTS CAUGHT $caught of $total"
