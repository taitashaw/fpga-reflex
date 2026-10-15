// reflex_tracker: centroid history, ballistic intercept predictor, lock, coasting
// and the guard's region of interest. Steps the trajectory one window per cycle
// (y += vy, vy += g, x += vx) until it reaches the paddle line.
`timescale 1ns/1ps
(* keep_hierarchy = "yes" *)
module reflex_tracker #(
    parameter SENSOR_W  = 640,
    parameter MAX_STEPS = 255,
    parameter COAST_MAX = 2
)(
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET rst" *)
    input  wire               clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    input  wire               rst,
    input  wire               enable,
    input  wire [9:0]         paddle_y,
    input  wire [19:0]        min_events,
    input  wire [15:0]        gravity,       // Q8 pixels per window^2, set by calibration
    input  wire [31:0]        tick,
    input  wire               snap_valid,
    input  wire [19:0]        snap_cnt,
    input  wire [31:0]        close_tick,
    output wire               div_start,
    input  wire               div_done,
    input  wire [37:0]        qx,
    input  wire [37:0]        qy,
    output wire               cmd_fire,      // this cycle's edge issues a command
    output wire [9:0]         xi_next,       // the x_pred that command carries
    output reg                cmd_valid,
    output reg  [9:0]         x_pred,
    output reg  [15:0]        latency,
    output reg  [15:0]        max_latency,
    output reg  [8:0]         steps_out,
    output reg                locked,
    output reg                armed,
    output reg  signed [39:0] roi_x,
    output reg  signed [39:0] roi_y,
    output reg  [31:0]        cmd_count,
    output reg  [31:0]        miss_count,
    output reg  [31:0]        nointercept_count
);
    localparam S_IDLE = 2'd0, S_WAIT = 2'd1, S_PINIT = 2'd2, S_PRED = 2'd3;
    reg [1:0]  state;
    reg [1:0]  hist_n;
    reg [1:0]  coast;
    reg signed [39:0] c1x, c1y, c2x, c2y;
    reg signed [39:0] px, py, vx, vy;
    reg [8:0]  steps;

    wire [19:0] minev = (min_events == 20'd0) ? 20'd1 : min_events;
    wire signed [39:0] g_q8   = $signed({24'd0, gravity});
    wire signed [39:0] py_lim = $signed({22'd0, paddle_y, 8'd0});
    wire signed [31:0] xi     = px[39:8];
    assign xi_next = xi[31] ? 10'd0 : (xi > SENSOR_W - 1) ? SENSOR_W - 1 : xi[9:0];
    wire [31:0] lat_now = tick - close_tick + 32'd1;

    wire miss  = (state == S_IDLE) && snap_valid && (snap_cnt < minev);
    assign div_start = (state == S_IDLE) && snap_valid && (snap_cnt >= minev);
    assign cmd_fire  = (state == S_PRED) && (py >= py_lim);
    wire no_intercept = (state == S_PRED) && (py < py_lim) && (steps == MAX_STEPS);

    always @(posedge clk) begin
        if (rst) begin
            cmd_count <= 0; miss_count <= 0; nointercept_count <= 0; max_latency <= 0;
            latency <= 0; x_pred <= SENSOR_W / 2; steps_out <= 0;
        end else begin
            if (miss) miss_count <= miss_count + 1;
            if (no_intercept) nointercept_count <= nointercept_count + 1;
            if (cmd_fire) begin
                cmd_count <= cmd_count + 1;
                x_pred    <= xi_next;
                latency   <= lat_now[15:0];
                if (lat_now[15:0] > max_latency) max_latency <= lat_now[15:0];
                steps_out <= steps;
            end
        end
    end

    always @(posedge clk) begin
        cmd_valid <= 1'b0;
        if (rst || !enable) begin
            state <= S_IDLE; hist_n <= 2'd0; locked <= 1'b0; armed <= 1'b0; coast <= 2'd0;
            roi_x <= 40'sd0; roi_y <= 40'sd0;
        end else begin
            case (state)
            S_IDLE: if (miss) begin
                if (locked && coast < COAST_MAX) begin
                    // coast: take the predicted centroid as this window's, keep the guard
                    c1x <= c2x; c1y <= c2y; c2x <= roi_x; c2y <= roi_y;
                    roi_x <= roi_x + (roi_x - c2x);
                    roi_y <= roi_y + (roi_y - c2y) + g_q8;
                    coast <= coast + 2'd1;
                end else begin
                    hist_n <= 2'd0; locked <= 1'b0; armed <= 1'b0; coast <= 2'd0;
                end
            end else if (div_start) begin
                state <= S_WAIT;
            end
            S_WAIT: if (div_done) begin
                c1x <= c2x; c1y <= c2y;
                c2x <= $signed({2'd0, qx}); c2y <= $signed({2'd0, qy});
                coast <= 2'd0;
                if (hist_n >= 2'd1) begin hist_n <= 2'd2; state <= S_PINIT; end
                else begin hist_n <= hist_n + 2'd1; state <= S_IDLE; end
            end
            S_PINIT: begin
                px <= c2x; py <= c2y;
                vx <= c2x - c1x; vy <= c2y - c1y + g_q8;
                steps <= 9'd0;
                state <= S_PRED;
            end
            S_PRED: begin
                if (cmd_fire) begin
                    cmd_valid <= 1'b1;
                    locked <= 1'b1; armed <= 1'b1;
                    roi_x <= c2x + vx;
                    roi_y <= c2y + (c2y - c1y) + g_q8;  // measured velocity, not the stepped one
                    state <= S_IDLE;
                end else if (no_intercept) begin
                    locked <= 1'b0; armed <= 1'b0;
                    state <= S_IDLE;
                end else begin
                    py <= py + vy; vy <= vy + g_q8; px <= px + vx;
                    steps <= steps + 9'd1;
                end
            end
            endcase
        end
    end
endmodule
