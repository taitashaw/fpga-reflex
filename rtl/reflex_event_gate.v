// reflex_event_gate: sensor event input and the guard (ROI gate).
// When the guard is enabled and armed, an event is accepted only inside the
// region around the predicted next centroid; others are counted as dropped.
`timescale 1ns/1ps
(* keep_hierarchy = "yes" *)
module reflex_event_gate (
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET rst" *)
    input  wire               clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    input  wire               rst,
    input  wire               enable,
    input  wire               guard_en,
    input  wire               armed,
    input  wire signed [39:0] roi_x,
    input  wire signed [39:0] roi_y,
    input  wire [9:0]         roi_radius,
    input  wire               s_valid,
    input  wire [20:0]        s_data,
    output wire               s_ready,
    output wire               accept,
    output wire [9:0]         ex,
    output wire [9:0]         ey,
    output wire               guard_active,
    output reg  [31:0]        events_in,
    output reg  [31:0]        events_dropped
);
    assign s_ready = 1'b1;
    assign guard_active = armed & guard_en;
    assign ex = s_data[9:0];
    assign ey = s_data[19:10];

    wire signed [40:0] dx = $signed({23'd0, ex, 8'd0}) - $signed({roi_x[39], roi_x});
    wire signed [40:0] dy = $signed({23'd0, ey, 8'd0}) - $signed({roi_y[39], roi_y});
    wire [40:0] adx  = dx[40] ? -dx : dx;
    wire [40:0] ady  = dy[40] ? -dy : dy;
    wire [40:0] rlim = {23'd0, roi_radius, 8'd0};
    wire in_roi = (adx <= rlim) && (ady <= rlim);

    wire seen = enable & s_valid;
    wire drop = seen & guard_active & ~in_roi;
    assign accept = seen & (~guard_active | in_roi);

    always @(posedge clk) begin
        if (rst) begin
            events_in <= 0; events_dropped <= 0;
        end else begin
            if (seen) events_in <= events_in + 1;
            if (drop) events_dropped <= events_dropped + 1;
        end
    end
endmodule
