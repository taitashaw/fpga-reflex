#!/usr/bin/env python3
"""Reads the build and simulation logs and writes docs/facts.json: the only numbers the
README and the post may quote. Re-run after any rebuild."""
import hashlib, json, re, datetime
from pathlib import Path

R = Path(__file__).resolve().parent.parent
B = R / "build"
f = {}

def scen_reports(text, tag):
    out = {}
    for m in re.finditer(r"^(s\d_\w+): (\d+) commands, events in (\d+), dropped (\d+), misses (\d+); "
                         r"latency (\d+) to (\d+) cycles; worst \|error\| ([\d.]+) px"
                         r"(?:; during burst worst \|error\| ([\d.]+) px)?\n\s+last command x_pred = (\d+) "
                         r"\(error ([+-][\d.]+) px\)", text, re.M):
        out[m[1]] = dict(commands=int(m[2]), events_in=int(m[3]), dropped=int(m[4]), misses=int(m[5]),
                         latency_min=int(m[6]), latency_max=int(m[7]), worst_error_px=float(m[8]),
                         burst_worst_error_px=float(m[9]) if m[9] else None,
                         last_x_pred=int(m[10]), last_error_px=float(m[11]), source=tag)
    return out

sim = (B / "run_sim.log").read_text()
f["regression_pass"] = "REGRESSION PASS" in sim
f["regression_matches"] = {m[2]: int(m[1]) for m in re.finditer(r"MATCH (\d+) lines .*\((\w+)\.got\)", sim)}
f["truth_intercept_x"] = float(re.search(r"crosses y=440 at x = ([\d.]+) px", sim)[1])
f["scenarios"] = scen_reports(sim, "build/run_sim.log")
f["no_coast"] = scen_reports((B / "nocoast_run.log").read_text(), "build/nocoast_run.log")["s5_occlusion_burst"]
bd = (B / "run_bd_sim.log").read_text()
f["bd_netlist_pass"] = "BD NETLIST SIM PASS" in bd
f["bd_netlist_matches"] = {m[2]: int(m[1]) for m in re.finditer(r"MATCH (\d+) lines .*\((\w+)\.bd\.got\)", bd)}
mu = re.search(r"MUTANTS CAUGHT (\d+) of (\d+)", (B / "mutants.log").read_text())
f["mutants_caught"], f["mutants_total"] = int(mu[1]), int(mu[2])

ts = (B / "reports/timing_summary.rpt").read_text()
row = re.search(r"WNS\(ns\).*\n\s*-+.*\n\s*([-\d.]+)\s+([-\d.]+)\s+(\d+)\s+(\d+)\s+([-\d.]+)\s+([-\d.]+)\s+(\d+)", ts)
f["timing"] = dict(wns_ns=float(row[1]), failing_setup=int(row[3]), endpoints=int(row[4]),
                   whs_ns=float(row[5]), failing_hold=int(row[7]), clock_mhz=100)
ut = (B / "reports/utilization.rpt").read_text()
def util(name):
    # | name | Used | Fixed | Prohibited | Available | Util% |
    m = re.search(r"^\|\s*" + re.escape(name) + r"\s*\|\s*(\d+)\s*\|\s*\d+\s*\|\s*\d+\s*\|\s*(\d+)\s*\|\s*([\d.<]+)\s*\|", ut, re.M)
    return dict(used=int(m[1]), available=int(m[2]), percent=m[3])
f["device_util"] = {k: util(k) for k in ["CLB LUTs", "CLB Registers", "DSPs"]}
hier = (B / "reports/utilization_hier.rpt").read_text()
m = re.search(r"^\|\s+reflex\s+\|\s+reflex_imp_\w+\s+\|\s+(\d+)\s+\|\s+\d+\s+\|\s+\d+\s+\|\s+\d+\s+\|\s+(\d+)", hier, re.M)
f["reflex_hier"] = dict(luts=int(m[1]), ffs=int(m[2]))
sub = {}
for line in (B / "reports/utilization_per_submodule.rpt").read_text().splitlines()[2:]:
    p = line.split()
    sub[p[0]] = dict(lut_cells=int(p[1]), ffs=int(p[2]), dsps=int(p[3]))
f["submodules"] = sub
log = (B / "vivado_build.log").read_text()
f["critical_warnings"] = log.count("CRITICAL WARNING")
f["bd_validated"] = "BD_VALIDATED" in log
bit = next((B / "vivado/reflex_soc.runs/impl_1").glob("*.bit"))
f["bitstream"] = dict(file=str(bit.relative_to(R)), sha256_16=hashlib.sha256(bit.read_bytes()).hexdigest()[:16],
                      built_utc=datetime.datetime.fromtimestamp(bit.stat().st_mtime, datetime.timezone.utc).strftime("%Y-%m-%d %H:%M"))
f["design"] = dict(sensor="640x480", sim_window_cycles=2000, divider_cycles=38, max_steps=255,
                   coast_windows=2, base_latency_cycles=43, device="XCZU7EV (ZCU104)",
                   axi_base="0xA000_0000", submodules=7)
(R / "docs").mkdir(exist_ok=True)
(R / "docs/facts.json").write_text(json.dumps(f, indent=1))
print(json.dumps(f, indent=1))
