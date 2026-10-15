# FPGA reflex: falling-object intercept on the ZCU104

Requirement: a ZCU104 design that takes camera events, tracks one
falling object, predicts where it crosses a paddle line and commands a servo with a
measured, fixed latency. Delivered as passing simulation waveforms, a validated block
design and a bitstream. Out of scope for this pass: camera interface, DMA, Linux software,
ILA, a real servo on a PMOD pin (no PMOD pins are in the installed board files).

## Event format (21 bits)
`[9:0]` x pixel, `[19:10]` y pixel, `[20]` polarity (counted, not used). Sensor 640 x 480.

## Timing contract (all in clock cycles; 100 MHz in the block design)
- `tick` counts enabled cycles from 0. Window length `W = max(WINDOW, 512)`.
- Window closes on the cycle where its position counter reaches `W-1` (tick `T`). An event
  accepted on tick `T` belongs to the closing window.
- Snapshot `(cnt, sx, sy)` is visible at `T+1`.
- If `cnt < max(MIN_EVENTS, 1)`: miss. If locked and fewer than 2 windows have been coasted,
  the tracker coasts: the ROI centre is taken as this window's centroid, history shifts, the
  ROI moves on by the same step plus gravity, and the guard stays armed. Otherwise history is
  cleared and lock and guard are dropped, visible at `T+2`. A measured window resets the
  coast count.
- Else centroids `cx = floor(sx*256/cnt)`, `cy = floor(sy*256/cnt)` (Q8) by a 38-cycle
  divider; history shifts (keeps the last 2 centroids).
- With 2 centroids: `vx = c2x-c1x`, `vy = c2y-c1y+G`, where `G` is the GRAVITY register
  (Q8 pixels per window squared, set by calibration; x has no acceleration).
  The predictor steps one window per cycle: check `y >= PADDLE_Y*256`; if not, and fewer than
  255 steps taken, `y += vy; vy += G; x += vx`.
- Crossing after `s` steps: command visible at `T+43+s`. Latency register = `43+s` cycles,
  measured by the hardware from the close tick, not computed from this formula.
- No crossing within 255 steps: no command, lock and guard dropped, visible at `T+298`.
- On a command: `x_pred = clamp(floor(x/256), 0, 639)`, lock set, guard armed, ROI centre =
  predicted next centroid `(c2x+vx, c2y+(c2y-c1y)+G)` from the measured velocity.
- Servo pulse = `100000 + (x_pred * 10240000) >> 16` cycles (1.0 to 2.0 ms at 100 MHz),
  period 2,000,000 cycles (20 ms).

## Guard (the overload rule under test)
When the guard is enabled and armed, an event is accepted only if
`|x*256 - roi_x| <= R*256` and `|y*256 - roi_y| <= R*256`. Rejected events are counted as
dropped. Purpose: a burst of background events (flicker, other motion) must not drag the
tracked centroid off the object.

## Register map (AXI4-Lite, byte offsets)
| off | name | access |
|---|---|---|
| 0x00 | CTRL: [0] enable, [1] guard_en, [2] soft reset (self clearing) | rw |
| 0x04 | WINDOW cycles (20 bits, min 512) | rw |
| 0x08 | PADDLE_Y | rw |
| 0x0C | MIN_EVENTS | rw |
| 0x10 | ROI_RADIUS | rw |
| 0x14 | EVT_INJECT (write pushes one event) | wo |
| 0x18 | STATUS: [0] locked [1] guard active [2] enable | ro |
| 0x1C | X_PRED | ro |
| 0x20 | LATENCY (last, cycles) | ro |
| 0x24 | MAX_LATENCY | ro |
| 0x28 | STEPS (last) | ro |
| 0x2C | CMD_COUNT | ro |
| 0x30 | EVENTS_IN | ro |
| 0x34 | EVENTS_DROPPED | ro |
| 0x38 | MISS_COUNT | ro |
| 0x3C | NOINTERCEPT_COUNT | ro |
| 0x40 | SERVO_PULSE (cycles) | ro |
| 0x44 | TICK | ro |
| 0x48 | VERSION 0x52464C01 | ro |
| 0x4C | GRAVITY (Q8 px per window squared, reset 154) | rw |

LEDs: LED0 servo PWM, LED1 command (stretched to 0.1 s), LED2 locked, LED3 guard active.

## Sub-modules (each a Verilog module with keep_hierarchy)
`regs` (AXI4-Lite), `gate` (event input, guard), `window` (time base, sums), `divider`
(Q8 centroid), `tracker` (history, predictor, lock, coasting), `servo` (pulse width, PWM),
`leds`. `reflex_core` wires gate to servo; `reflex_top` adds regs and leds.
