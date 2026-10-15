// reflex_top: AXI4-Lite registers + reflex pipeline + LEDs, wiring only.
// The block design builds the same netlist from the leaf modules inside a
// hierarchy named "reflex"; tb_top checks this wrapper, tb_bd the BD's version.
`timescale 1ns/1ps
module reflex_top #(
    parameter LED_STRETCH = 10000000     // 0.1 s at 100 MHz
)(
    input  wire        aclk,
    input  wire        aresetn,
    input  wire [6:0]  s_axi_awaddr,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [6:0]  s_axi_araddr,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,
    output wire [3:0]  led
);
    wire        core_rst, enable, guard_en, evt_valid, s_ready;
    wire [19:0] window_cycles, min_events;
    wire [9:0]  paddle_y, roi_radius, x_pred;
    wire [15:0] gravity, latency, max_latency;
    wire [20:0] evt_data;
    wire        cmd_valid, locked, guard_active, servo_pwm;
    wire [8:0]  steps_out;
    wire [31:0] events_in, events_dropped, cmd_count, miss_count, nointercept_count, servo_pulse, tick;

    reflex_regs regs (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awprot(s_axi_awprot), .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready), .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready), .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready), .s_axi_araddr(s_axi_araddr),
        .s_axi_arprot(s_axi_arprot), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .core_rst(core_rst), .enable(enable), .guard_en(guard_en),
        .window_cycles(window_cycles), .paddle_y(paddle_y), .min_events(min_events),
        .roi_radius(roi_radius), .gravity(gravity), .evt_valid(evt_valid), .evt_data(evt_data),
        .locked(locked), .guard_active(guard_active), .x_pred(x_pred), .latency(latency),
        .max_latency(max_latency), .steps_out(steps_out), .cmd_count(cmd_count),
        .events_in(events_in), .events_dropped(events_dropped), .miss_count(miss_count),
        .nointercept_count(nointercept_count), .servo_pulse(servo_pulse), .tick(tick));

    reflex_core core (
        .clk(aclk), .rst(core_rst), .enable(enable), .guard_en(guard_en),
        .window_cycles(window_cycles), .paddle_y(paddle_y), .min_events(min_events),
        .roi_radius(roi_radius), .gravity(gravity),
        .s_valid(evt_valid), .s_data(evt_data), .s_ready(s_ready),
        .cmd_valid(cmd_valid), .x_pred(x_pred), .latency(latency), .max_latency(max_latency),
        .steps_out(steps_out), .locked(locked), .guard_active(guard_active),
        .events_in(events_in), .events_dropped(events_dropped), .cmd_count(cmd_count),
        .miss_count(miss_count), .nointercept_count(nointercept_count),
        .servo_pulse(servo_pulse), .servo_pwm(servo_pwm), .tick(tick));

    reflex_leds #(.LED_STRETCH(LED_STRETCH)) leds (
        .clk(aclk), .rst(core_rst), .cmd_valid(cmd_valid), .locked(locked),
        .guard_active(guard_active), .servo_pwm(servo_pwm), .led(led));
endmodule
