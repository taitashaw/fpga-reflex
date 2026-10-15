#!/usr/bin/env python3
"""Reference model, stimulus generator and checker for the FPGA reflex design.

The model follows SPEC.md (timing contract and arithmetic) and does not mirror
the RTL's structure: it schedules each decision's visible effects at the tick
the spec names, and simulates the ball physics independently for the truth.

  reflex.py gen     <outdir>                 write stimulus + config per scenario
  reflex.py model   <stim> <cfg> <out>       expected log for one run
  reflex.py compare <expected> <got>         exact line-by-line comparison
  reflex.py report  <outdir>                 prediction error vs physics truth
"""
import json
import math
import random
import sys
from pathlib import Path

SENSOR_W, SENSOR_H = 640, 480
MAX_STEPS = 255
COAST_MAX = 2         # spec: missed windows the guard coasts through while locked
BASE_LAT = 43          # spec: command visible at T + 43 + steps
SERVO_MIN, SERVO_SCALE = 100000, 10240000

# Ball: x0, y0 px, vx, vy px/window, g px/window^2, enters at window `start`.
BALL = dict(x0=150.0, y0=20.0, vx=3.0, vy=4.0, g=0.6, start=2, n=120, r=4.0)
SCENARIOS = {
    # name: (guard_en, noise windows, noise events per window, window cycles, end window, ball events)
    "s1_clean":       dict(guard=1, noise=(0, 0), n_noise=0, W=2000, end_win=40, n_ball=120, seed=1),
    "s2_burst_guard": dict(guard=1, noise=(12, 22), n_noise=900, W=2000, end_win=40, n_ball=120, seed=2),
    "s3_burst_noguard": dict(guard=0, noise=(12, 22), n_noise=900, W=2000, end_win=40, n_ball=120, seed=2),
    # object hidden for windows 15 and 16 inside the burst: the guard must coast
    "s5_occlusion_burst": dict(guard=1, noise=(12, 22), n_noise=900, W=2000, end_win=40, n_ball=120, seed=5,
                               occlude=(15, 17)),
    # AXI-Lite inject path through reflex_top: fewer events so writes keep up.
    "s4_axi_top":     dict(guard=1, noise=(0, 0), n_noise=0, W=2000, end_win=40, n_ball=100, seed=4),
}
CFG_COMMON = dict(PY=440, MINEV=20, R=24, G=round(BALL["g"] * 256))


def ball_pos(tau):
    b = BALL
    t = tau - b["start"]
    return b["x0"] + b["vx"] * t, b["y0"] + b["vy"] * t + 0.5 * b["g"] * t * t


def truth_intercept(py):
    """Continuous-time x where the ball centre crosses y = py."""
    b = BALL
    a, bb, c = 0.5 * b["g"], b["vy"], b["y0"] - py
    t = (-bb + math.sqrt(bb * bb - 4 * a * c)) / (2 * a)
    return b["x0"] + b["vx"] * t


def gen(outdir):
    out = Path(outdir)
    out.mkdir(parents=True, exist_ok=True)
    for name, sc in SCENARIOS.items():
        rng = random.Random(sc["seed"])
        W = sc["W"]
        events = {}
        for k in range(sc["end_win"]):
            pool = list(range(k * W, (k + 1) * W))
            want = []
            occ = sc.get("occlude", (0, 0))
            if k >= BALL["start"] and not (occ[0] <= k < occ[1]):
                want += ["ball"] * sc["n_ball"]
            if sc["noise"][0] <= k < sc["noise"][1]:
                want += ["noise"] * sc["n_noise"]
            ticks = rng.sample(pool, len(want))
            for kind, t in zip(want, ticks):
                if kind == "ball":
                    x, y = ball_pos(t / W)
                    ang, rad = rng.uniform(0, 2 * math.pi), BALL["r"] * math.sqrt(rng.random())
                    x, y = round(x + rad * math.cos(ang)), round(y + rad * math.sin(ang))
                    if not (0 <= x < SENSOR_W and 0 <= y < SENSOR_H):
                        continue
                else:
                    x, y = rng.randrange(SENSOR_W), rng.randrange(SENSOR_H)
                pol = rng.randrange(2)
                events[t] = (pol << 20) | (y << 10) | x
        with open(out / f"{name}.stim", "w") as f:
            for t in sorted(events):
                f.write(f"{t} {events[t]:06x}\n")
        cfg = dict(W=W, GUARD=sc["guard"], END=sc["end_win"] * W, **CFG_COMMON)
        with open(out / f"{name}.cfg", "w") as f:
            f.write("{W} {PY} {MINEV} {R} {GUARD} {END} {G}\n".format(**cfg))
        (out / f"{name}.json").write_text(json.dumps(dict(sc, **cfg, events=len(events))))
    print(f"wrote {len(SCENARIOS)} scenarios to {out}")


def read_stim(path):
    ev = {}
    for line in Path(path).read_text().split("\n"):
        if line.strip():
            t, d = line.split()
            ev[int(t)] = int(d, 16)
    return ev


def model(stim, cfgfile):
    W, PY, MINEV, R, GUARD, END, G = map(int, Path(cfgfile).read_text().split())
    W, MINEV = max(W, 512), max(MINEV, 1)
    PY256, R256 = PY * 256, R * 256
    events = read_stim(stim)

    st = dict(armed=False, locked=False, coast=0, roi=(0, 0), ein=0, edrop=0, cmd=0, miss=0, noi=0, maxlat=0)
    hist = []
    pending = {}     # tick -> list of callables
    log = []

    def at(tv, fn):
        pending.setdefault(tv, []).append(fn)

    def decide(T, cnt, sx, sy):
        if cnt < MINEV:
            if st["locked"] and st["coast"] < COAST_MAX:
                # coast: the predicted centroid stands in for this window; guard stays on
                p = st["roi"]
                c2 = hist[-1]
                hist.append(p)
                del hist[:-2]
                st["coast"] += 1
                roi = (p[0] + (p[0] - c2[0]), p[1] + (p[1] - c2[1]) + G)

                def coast():
                    st["roi"] = roi
                    st["miss"] += 1
                    log.append((T + 2, f"MISS {T + 2}"))
                at(T + 2, coast)
                return
            hist.clear()
            st.update(locked=False, coast=0)

            def miss():
                st.update(armed=False)
                st["miss"] += 1
                log.append((T + 2, f"MISS {T + 2}"))
            at(T + 2, miss)
            return
        hist.append(((sx * 256) // cnt, (sy * 256) // cnt))
        del hist[:-2]
        st["coast"] = 0
        if len(hist) < 2:
            return
        (c1x, c1y), (c2x, c2y) = hist
        vx, vy = c2x - c1x, c2y - c1y + G
        x, y, v, s = c2x, c2y, vy, 0
        while y < PY256 and s < MAX_STEPS:
            y, v, x, s = y + v, v + G, x + vx, s + 1
        if y >= PY256:
            tv, lat = T + BASE_LAT + s, BASE_LAT + s
            xi = min(max(x >> 8, 0), SENSOR_W - 1)
            pulse = SERVO_MIN + ((xi * SERVO_SCALE) >> 16)
            roi = (c2x + vx, c2y + vy)
            st["locked"] = True

            def cmd():
                st.update(armed=True, roi=roi)
                st["cmd"] += 1
                st["maxlat"] = max(st["maxlat"], lat)
                log.append((tv, f"CMD {tv} {xi} {lat} {s} {pulse}"))
            at(tv, cmd)
        else:
            tv = T + BASE_LAT + MAX_STEPS
            st["locked"] = False

            def noi():
                st.update(armed=False)
                st["noi"] += 1
                log.append((tv, f"NOI {tv}"))
            at(tv, noi)

    cnt = sx = sy = 0
    wt = 0
    for t in range(END):
        for fn in pending.pop(t, []):
            fn()
        d = events.get(t)
        if d is not None:
            st["ein"] += 1
            ex, ey = d & 1023, (d >> 10) & 1023
            rx, ry = st["roi"]
            if (st["armed"] and GUARD) and not (abs(ex * 256 - rx) <= R256 and abs(ey * 256 - ry) <= R256):
                st["edrop"] += 1
            else:
                cnt, sx, sy = cnt + 1, sx + ex, sy + ey
        if wt >= W - 1:
            log.append((t + 1, f"WIN {t + 1} {cnt} {sx} {sy}"))
            decide(t, cnt, sx, sy)
            cnt = sx = sy = 0
            wt = 0
        else:
            wt += 1
    # TB logs events on ticks < END and reads the counters during tick END.
    for tv in sorted(pending):
        if tv <= END:
            for fn in pending[tv]:
                fn()
    lines = [s for (tv, s) in sorted(log, key=lambda e: e[0]) if tv < END]
    lines.append("END {ein} {edrop} {cmd} {miss} {noi} {maxlat}".format(**st))
    return lines


def compare(exp, got):
    e = Path(exp).read_text().split("\n")
    g = Path(got).read_text().split("\n")
    e = [l for l in e if l.strip()]
    g = [l for l in g if l.strip() and not l.startswith("#")]
    bad = 0
    for i in range(max(len(e), len(g))):
        a = e[i] if i < len(e) else "<missing>"
        b = g[i] if i < len(g) else "<missing>"
        if a != b:
            bad += 1
            if bad <= 10:
                print(f"  line {i + 1}: expected '{a}' got '{b}'")
    kinds = {}
    for l in e:
        kinds[l.split()[0]] = kinds.get(l.split()[0], 0) + 1
    if bad:
        print(f"MISMATCH {bad} of {max(len(e), len(g))} lines ({exp} vs {got})")
        return 1
    print(f"MATCH {len(e)} lines {kinds} ({Path(got).name})")
    return 0


def report(outdir):
    out = Path(outdir)
    xt = truth_intercept(CFG_COMMON["PY"])
    print(f"physics truth: ball centre crosses y={CFG_COMMON['PY']} at x = {xt:.1f} px")
    for name in SCENARIOS:
        got = out / f"{name}.got"
        if not got.exists():
            continue
        sc = json.loads((out / f"{name}.json").read_text())
        W = sc["W"]
        cmds = [l.split() for l in got.read_text().split("\n") if l.startswith("CMD")]
        endl = [l.split() for l in got.read_text().split("\n") if l.startswith("END")][0]
        errs = [(int(c[1]) // W, int(c[2]) - xt, int(c[3])) for c in cmds]
        burst = [abs(e) for (k, e, _) in errs if sc["noise"][0] < k <= sc["noise"][1]]
        lats = [l for (_, _, l) in errs]
        print(f"{name}: {len(cmds)} commands, events in {endl[1]}, dropped {endl[2]}, "
              f"misses {endl[4]}; latency {min(lats)} to {max(lats)} cycles; "
              f"worst |error| {max(abs(e) for _, e, _ in errs):.1f} px"
              + (f"; during burst worst |error| {max(burst):.1f} px" if burst else ""))
        print(f"   last command x_pred = {cmds[-1][2]} (error {int(cmds[-1][2]) - xt:+.1f} px)")


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "gen":
        gen(sys.argv[2])
    elif cmd == "model":
        Path(sys.argv[4]).write_text("\n".join(model(sys.argv[2], sys.argv[3])) + "\n")
    elif cmd == "compare":
        sys.exit(compare(sys.argv[2], sys.argv[3]))
    elif cmd == "report":
        report(sys.argv[2])
