// reflex_window: time base and per-window accumulation (count, sum x, sum y).
// The window closes on the cycle its position reaches W-1; the snapshot,
// including an event accepted on that cycle, is visible one cycle later.
`timescale 1ns/1ps
(* keep_hierarchy = "yes" *)
module reflex_window (
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET rst" *)
    input  wire        clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    input  wire        rst,
    input  wire        enable,
    input  wire [19:0] window_cycles,
    input  wire        accept,
    input  wire [9:0]  ex,
    input  wire [9:0]  ey,
    output reg  [31:0] tick,
    output reg         snap_valid,
    output reg  [19:0] snap_cnt,
    output reg  [29:0] snap_sx,
    output reg  [29:0] snap_sy,
    output reg  [31:0] close_tick
);
    wire [19:0] w_eff = (window_cycles < 20'd512) ? 20'd512 : window_cycles;
    reg  [19:0] wt;
    reg  [19:0] acc_cnt;
    reg  [29:0] acc_sx, acc_sy;
    wire close = enable & (wt >= w_eff - 20'd1);

    wire [19:0] cnt_n = acc_cnt + {19'd0, accept};
    wire [29:0] sx_n  = acc_sx + (accept ? {20'd0, ex} : 30'd0);
    wire [29:0] sy_n  = acc_sy + (accept ? {20'd0, ey} : 30'd0);

    always @(posedge clk) begin
        if (rst || !enable) begin
            tick <= 32'd0; wt <= 20'd0;
            acc_cnt <= 20'd0; acc_sx <= 30'd0; acc_sy <= 30'd0;
            snap_valid <= 1'b0;
        end else begin
            tick <= tick + 32'd1;
            snap_valid <= close;
            if (close) begin
                snap_cnt <= cnt_n; snap_sx <= sx_n; snap_sy <= sy_n;
                close_tick <= tick;
                acc_cnt <= 20'd0; acc_sx <= 30'd0; acc_sy <= 30'd0;
                wt <= 20'd0;
            end else begin
                acc_cnt <= cnt_n; acc_sx <= sx_n; acc_sy <= sy_n;
                wt <= wt + 20'd1;
            end
        end
    end
endmodule
