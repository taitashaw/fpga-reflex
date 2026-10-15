// reflex_core: the reflex pipeline, wiring only.
//   gate (guard) -> window (accumulate) -> divider (centroid) -> tracker (predict) -> servo
// Timing contract and arithmetic in SPEC.md; checked against model/reflex.py.
`timescale 1ns/1ps
module reflex_core (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,
    input  wire        guard_en,
    input  wire [19:0] window_cycles,
    input  wire [9:0]  paddle_y,
    input  wire [19:0] min_events,
    input  wire [9:0]  roi_radius,
    input  wire [15:0] gravity,
    input  wire        s_valid,
    input  wire [20:0] s_data,
    output wire        s_ready,
    output wire        cmd_valid,
    output wire [9:0]  x_pred,
    output wire [15:0] latency,
    output wire [15:0] max_latency,
    output wire [8:0]  steps_out,
    output wire        locked,
    output wire        guard_active,
    output wire [31:0] events_in,
    output wire [31:0] events_dropped,
    output wire [31:0] cmd_count,
    output wire [31:0] miss_count,
    output wire [31:0] nointercept_count,
    output wire [31:0] servo_pulse,
    output wire        servo_pwm,
    output wire [31:0] tick
);
    wire               accept, armed, snap_valid, div_start, div_done, cmd_fire;
    wire [9:0]         ex, ey, xi_next;
    wire signed [39:0] roi_x, roi_y;
    wire [19:0]        snap_cnt;
    wire [29:0]        snap_sx, snap_sy;
    wire [31:0]        close_tick;
    wire [37:0]        qx, qy;

    reflex_event_gate gate (
        .clk(clk), .rst(rst), .enable(enable), .guard_en(guard_en), .armed(armed),
        .roi_x(roi_x), .roi_y(roi_y), .roi_radius(roi_radius),
        .s_valid(s_valid), .s_data(s_data), .s_ready(s_ready),
        .accept(accept), .ex(ex), .ey(ey), .guard_active(guard_active),
        .events_in(events_in), .events_dropped(events_dropped));

    reflex_window window (
        .clk(clk), .rst(rst), .enable(enable), .window_cycles(window_cycles),
        .accept(accept), .ex(ex), .ey(ey), .tick(tick),
        .snap_valid(snap_valid), .snap_cnt(snap_cnt), .snap_sx(snap_sx), .snap_sy(snap_sy),
        .close_tick(close_tick));

    reflex_divider divider (
        .clk(clk), .rst(rst), .enable(enable), .start(div_start),
        .sx(snap_sx), .sy(snap_sy), .cnt(snap_cnt),
        .done(div_done), .qx(qx), .qy(qy));

    reflex_tracker tracker (
        .clk(clk), .rst(rst), .enable(enable),
        .paddle_y(paddle_y), .min_events(min_events), .gravity(gravity),
        .tick(tick), .snap_valid(snap_valid), .snap_cnt(snap_cnt), .close_tick(close_tick),
        .div_start(div_start), .div_done(div_done), .qx(qx), .qy(qy),
        .cmd_fire(cmd_fire), .xi_next(xi_next), .cmd_valid(cmd_valid), .x_pred(x_pred),
        .latency(latency), .max_latency(max_latency), .steps_out(steps_out),
        .locked(locked), .armed(armed), .roi_x(roi_x), .roi_y(roi_y),
        .cmd_count(cmd_count), .miss_count(miss_count), .nointercept_count(nointercept_count));

    reflex_servo servo (
        .clk(clk), .rst(rst), .cmd_fire(cmd_fire), .xi(xi_next),
        .servo_pulse(servo_pulse), .servo_pwm(servo_pwm));
endmodule
