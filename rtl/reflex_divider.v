// reflex_divider: two restoring dividers in parallel giving the Q8 centroid,
// cx = floor(sx*256/cnt) and cy = floor(sy*256/cnt). One quotient bit per cycle,
// 38 cycles; done is a one-cycle pulse with the quotients valid.
`timescale 1ns/1ps
(* keep_hierarchy = "yes" *)
module reflex_divider #(
    parameter DIV_BITS = 38
)(
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET rst" *)
    input  wire        clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    input  wire        rst,
    input  wire        enable,
    input  wire        start,
    input  wire [29:0] sx,
    input  wire [29:0] sy,
    input  wire [19:0] cnt,
    output reg         done,
    output reg  [37:0] qx,
    output reg  [37:0] qy
);
    reg        busy;
    reg [5:0]  div_i;
    reg [20:0] rx, ry;           // partial remainders
    reg [19:0] divisor;

    wire [20:0] rx_sh = {rx[19:0], qx[37]};
    wire [20:0] ry_sh = {ry[19:0], qy[37]};
    wire        gx = rx_sh >= {1'b0, divisor};
    wire        gy = ry_sh >= {1'b0, divisor};

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst || !enable) begin
            busy <= 1'b0;
        end else if (start) begin
            qx <= {sx, 8'd0}; qy <= {sy, 8'd0};       // dividend, becomes quotient
            rx <= 21'd0; ry <= 21'd0;
            divisor <= cnt; div_i <= 6'd0;
            busy <= 1'b1;
        end else if (busy) begin
            rx <= gx ? rx_sh - {1'b0, divisor} : rx_sh;
            ry <= gy ? ry_sh - {1'b0, divisor} : ry_sh;
            qx <= {qx[36:0], gx};
            qy <= {qy[36:0], gy};
            div_i <= div_i + 6'd1;
            if (div_i == DIV_BITS - 1) begin busy <= 1'b0; done <= 1'b1; end
        end
    end
endmodule
