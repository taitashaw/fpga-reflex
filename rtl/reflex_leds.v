// reflex_leds: board LEDs. LED0 servo PWM, LED1 command (stretched so it is
// visible), LED2 locked, LED3 guard active.
`timescale 1ns/1ps
(* keep_hierarchy = "yes" *)
module reflex_leds #(
    parameter LED_STRETCH = 10000000     // 0.1 s at 100 MHz
)(
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_RESET rst" *)
    input  wire       clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    input  wire       rst,
    input  wire       cmd_valid,
    input  wire       locked,
    input  wire       guard_active,
    input  wire       servo_pwm,
    output wire [3:0] led
);
    reg [31:0] stretch;
    always @(posedge clk) begin
        if (rst) stretch <= 32'd0;
        else if (cmd_valid) stretch <= LED_STRETCH;
        else if (stretch != 0) stretch <= stretch - 32'd1;
    end
    assign led = {guard_active, locked, (stretch != 0), servo_pwm};
endmodule
