// reflex_servo: converts the predicted x into a hobby-servo pulse width and
// drives the PWM. Pulse = 100000 + (x * 10240000) >> 16 cycles (1.0 to 2.0 ms
// at 100 MHz), period 2,000,000 cycles (20 ms).
`timescale 1ns/1ps
(* keep_hierarchy = "yes" *)
module reflex_servo #(
    parameter SENSOR_W     = 640,
    parameter SERVO_MIN    = 100000,
    parameter SERVO_SCALE  = 10240000,   // (100000 << 16) / 640
    parameter SERVO_PERIOD = 2000000
)(
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET rst" *)
    input  wire        clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    input  wire        rst,
    input  wire        cmd_fire,
    input  wire [9:0]  xi,
    output reg  [31:0] servo_pulse,
    output reg         servo_pwm
);
    wire [39:0] servo_prod = {30'd0, xi} * SERVO_SCALE;   // up to 6.5e9, needs 33 bits
    reg  [31:0] pwm_cnt;

    always @(posedge clk) begin
        if (rst) begin
            servo_pulse <= SERVO_MIN + 50000;
            pwm_cnt <= 0; servo_pwm <= 1'b0;
        end else begin
            if (cmd_fire) servo_pulse <= SERVO_MIN + servo_prod[39:16];
            pwm_cnt   <= (pwm_cnt == SERVO_PERIOD - 1) ? 32'd0 : pwm_cnt + 32'd1;
            servo_pwm <= pwm_cnt < servo_pulse;
        end
    end
endmodule
