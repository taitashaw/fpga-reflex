#!/usr/bin/env python3
"""Writes the XSim view files (.wcfg) used for the README and post figures.
Times: tick t of the testbench starts at 55 + 10*t ns (100 MHz, enable at 55 ns)."""
from pathlib import Path

D = "/tb_core/dut"
U, S = "UNSIGNEDDECRADIX", "SIGNEDDECRADIX"
LOGIC = {"clk", "s_valid", "accept", "drop", "guard_active", "in_roi", "close", "snap_valid",
         "start", "busy", "done", "locked", "armed", "cmd_valid", "cmd_fire", "servo_pwm"}
WIDTH = {"ex": 10, "ey": 10, "tick": 32, "wt": 20, "acc_cnt": 20, "snap_cnt": 20, "snap_sx": 30,
         "snap_sy": 30, "div_i": 6, "qx": 38, "qy": 38, "state": 2, "coast": 2, "c2x": 40, "c2y": 40,
         "py": 40, "vy": 40, "steps": 9, "x_pred": 10, "latency": 16, "roi_x": 40, "roi_y": 40,
         "servo_pulse": 32, "events_in": 32, "events_dropped": 32, "cmd_count": 32, "miss_count": 32}
SIGNED = {"c2x", "c2y", "py", "vy", "roi_x", "roi_y"}


def t(tick):
    return 55 + 10 * tick                       # ns


def sig(mod, name):
    path = "/tb_core/clk" if name == "clk" else f"{D}/{mod}/{name}"
    if name in LOGIC:
        return (f'      <wvobject type="logic" fp_name="{path}">\n'
                f'         <obj_property name="ElementShortName">{name}</obj_property>\n'
                f'         <obj_property name="ObjectShortName">{name}</obj_property>\n      </wvobject>\n')
    w = f"{name}[{WIDTH[name] - 1}:0]"
    return (f'      <wvobject type="array" fp_name="{path}">\n'
            f'         <obj_property name="ElementShortName">{w}</obj_property>\n'
            f'         <obj_property name="ObjectShortName">{w}</obj_property>\n'
            f'         <obj_property name="Radix">{S if name in SIGNED else U}</obj_property>\n      </wvobject>\n')


def wcfg(groups, start_ns, end_ns, cursor_ns, markers):
    out = ['<?xml version="1.0" encoding="UTF-8"?>\n<wave_config>\n   <wave_state>\n   </wave_state>\n',
           '   <db_ref_list>\n      <db_ref path="tb_core.wdb" id="1">\n         <top_modules>\n'
           '            <top_module name="tb_core" />\n         </top_modules>\n      </db_ref>\n   </db_ref_list>\n',
           f'   <zoom_setting>\n      <ZoomStartTime time="{start_ns * 1000:,} ps"></ZoomStartTime>\n'
           f'      <ZoomEndTime time="{end_ns * 1000:,} ps"></ZoomEndTime>\n'
           f'      <Cursor1Time time="{cursor_ns * 1000:,} ps"></Cursor1Time>\n   </zoom_setting>\n',
           '   <column_width_setting>\n      <NameColumnWidth column_width="230"></NameColumnWidth>\n'
           '      <ValueColumnWidth column_width="90"></ValueColumnWidth>\n   </column_width_setting>\n',
           f'   <WVObjectSize size="{len(groups)}" />\n   <wave_markers>\n']
    out += [f'      <marker label="{lab}" time="{ns * 1000}" />\n' for lab, ns in markers]
    out.append('   </wave_markers>\n')
    for i, (label, mod, names) in enumerate(groups):
        out.append(f'   <wvobject type="group" fp_name="group{i + 1}">\n'
                   f'      <obj_property name="label">{label}</obj_property>\n'
                   f'      <obj_property name="DisplayName">label</obj_property>\n'
                   f'      <obj_property name="isExpanded"></obj_property>\n')
        out += [sig(m, n) for (m, n) in ([(mod, n) for n in names] if isinstance(mod, str) else mod)]
        out.append('   </wvobject>\n')
    out.append('</wave_config>\n')
    return "".join(out)


S5_MARKS = [("burst", t(24000)), ("hidden", t(30000)), ("back", t(34000)), ("burst_end", t(44000))]
VIEWS = {
    # guard on (s2) and off (s3): same stimulus, same view
    "compare": (
        [("gate", "gate", ["accept", "drop", "guard_active"]),
         ("window", "window", ["snap_cnt"]),
         ("tracker", "tracker", ["locked", "x_pred"]),
         ("servo", "servo", ["servo_pulse"]),
         ("counters", [("gate", "events_in"), ("gate", "events_dropped")], None)],
        t(20000), t(48000), t(24000),
        [("burst_starts_w12", t(24000)), ("burst_ends_w22", t(44000))]),
    "overview": (
        [("gate", "gate", ["s_valid", "accept", "drop", "guard_active"]),
         ("window", "window", ["snap_valid", "snap_cnt"]),
         ("divider", "divider", ["done"]),
         ("tracker", "tracker", ["state", "coast", "locked", "steps", "cmd_valid", "x_pred", "latency"]),
         ("servo", "servo", ["servo_pulse", "servo_pwm"]),
         ("counters", [("gate", "events_in"), ("gate", "events_dropped"),
                       ("tracker", "cmd_count"), ("tracker", "miss_count")], None)],
        t(0), t(76000), t(24000), S5_MARKS),
    "decision": (
        [("clock", [("", "clk")], None),
         ("window", "window", ["wt", "close", "snap_valid", "snap_cnt", "snap_sx", "snap_sy"]),
         ("divider", "divider", ["start", "busy", "div_i", "done", "qx", "qy"]),
         ("tracker", "tracker", ["state", "steps", "py", "vy", "cmd_valid", "x_pred", "latency"]),
         ("servo", "servo", ["cmd_fire", "servo_pulse"])],
        t(25994), t(26070), t(25999),
        [("window_closes", t(25999)), ("divider_done", t(26039)), ("command_out", t(26064))]),
    "guard_onset": (
        [("gate", "gate", ["s_valid", "ex", "ey", "guard_active", "in_roi", "accept", "drop"]),
         ("tracker", "tracker", ["roi_x", "roi_y"]),
         ("window", "window", ["acc_cnt"]),
         ("counters", [("gate", "events_in"), ("gate", "events_dropped")], None)],
        t(23960), t(24160), t(24000), [("burst_starts_w12", t(24000))]),
    "coast": (
        [("window", "window", ["snap_valid", "snap_cnt"]),
         ("tracker", "tracker", ["locked", "armed", "coast", "c2x", "c2y", "roi_x", "roi_y", "cmd_valid", "x_pred"]),
         ("gate", "gate", ["guard_active", "drop"]),
         ("counters", [("tracker", "miss_count")], None)],
        t(29600), t(36600), t(30000),
        [("object_hidden_w15", t(30000)), ("object_back_w17", t(34000)), ("reacquired", t(36058))]),
}

out = Path(__file__).resolve().parent / "wave_views"
out.mkdir(exist_ok=True)
for name, (groups, a, b, c, marks) in VIEWS.items():
    (out / f"{name}.wcfg").write_text(wcfg(groups, a, b, c, marks))
print("wrote", ", ".join(VIEWS), "to", out)
