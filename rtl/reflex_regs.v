// reflex_regs: AXI4-Lite register file. Configuration out to the pipeline,
// event injection from the PS, and read-back of every result. Map in SPEC.md.
`timescale 1ns/1ps
(* keep_hierarchy = "yes" *)
module reflex_regs (
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axi, ASSOCIATED_RESET aresetn:core_rst" *)
    input  wire        aclk,
    input  wire        aresetn,
    input  wire [6:0]  s_axi_awaddr,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [6:0]  s_axi_araddr,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,
    // to the pipeline
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 core_rst RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_HIGH" *)
    output wire        core_rst,
    output reg         enable,
    output reg         guard_en,
    output reg  [19:0] window_cycles,
    output reg  [9:0]  paddle_y,
    output reg  [19:0] min_events,
    output reg  [9:0]  roi_radius,
    output reg  [15:0] gravity,
    output reg         evt_valid,
    output reg  [20:0] evt_data,
    // read-back
    input  wire        locked,
    input  wire        guard_active,
    input  wire [9:0]  x_pred,
    input  wire [15:0] latency,
    input  wire [15:0] max_latency,
    input  wire [8:0]  steps_out,
    input  wire [31:0] cmd_count,
    input  wire [31:0] events_in,
    input  wire [31:0] events_dropped,
    input  wire [31:0] miss_count,
    input  wire [31:0] nointercept_count,
    input  wire [31:0] servo_pulse,
    input  wire [31:0] tick
);
    assign s_axi_bresp = 2'b00;
    assign s_axi_rresp = 2'b00;

    reg soft_rst;
    assign core_rst = !aresetn || soft_rst;

    wire wr = s_axi_awready & s_axi_awvalid & s_axi_wvalid;

    always @(posedge aclk) begin
        if (!aresetn) begin
            s_axi_awready <= 1'b0; s_axi_wready <= 1'b0; s_axi_bvalid <= 1'b0;
            enable <= 1'b0; guard_en <= 1'b1; soft_rst <= 1'b0;
            window_cycles <= 20'd100000; paddle_y <= 10'd440; min_events <= 20'd20;
            roi_radius <= 10'd24; gravity <= 16'd154;
            evt_valid <= 1'b0; evt_data <= 21'd0;
        end else begin
            s_axi_awready <= 1'b0; s_axi_wready <= 1'b0;
            soft_rst <= 1'b0; evt_valid <= 1'b0;
            if (!s_axi_bvalid && !s_axi_awready && s_axi_awvalid && s_axi_wvalid) begin
                s_axi_awready <= 1'b1; s_axi_wready <= 1'b1;
            end
            if (wr) begin
                s_axi_bvalid <= 1'b1;
                case (s_axi_awaddr[6:2])
                5'h00: begin enable <= s_axi_wdata[0]; guard_en <= s_axi_wdata[1]; soft_rst <= s_axi_wdata[2]; end
                5'h01: window_cycles <= s_axi_wdata[19:0];
                5'h02: paddle_y   <= s_axi_wdata[9:0];
                5'h03: min_events <= s_axi_wdata[19:0];
                5'h04: roi_radius <= s_axi_wdata[9:0];
                5'h05: begin evt_valid <= 1'b1; evt_data <= s_axi_wdata[20:0]; end
                5'h13: gravity    <= s_axi_wdata[15:0];
                default: ;
                endcase
            end
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            s_axi_arready <= 1'b0; s_axi_rvalid <= 1'b0; s_axi_rdata <= 32'd0;
        end else begin
            s_axi_arready <= 1'b0;
            if (!s_axi_rvalid && !s_axi_arready && s_axi_arvalid) s_axi_arready <= 1'b1;
            if (s_axi_arready && s_axi_arvalid) begin
                s_axi_rvalid <= 1'b1;
                case (s_axi_araddr[6:2])
                5'h00: s_axi_rdata <= {30'd0, guard_en, enable};
                5'h01: s_axi_rdata <= {12'd0, window_cycles};
                5'h02: s_axi_rdata <= {22'd0, paddle_y};
                5'h03: s_axi_rdata <= {12'd0, min_events};
                5'h04: s_axi_rdata <= {22'd0, roi_radius};
                5'h06: s_axi_rdata <= {29'd0, enable, guard_active, locked};
                5'h07: s_axi_rdata <= {22'd0, x_pred};
                5'h08: s_axi_rdata <= {16'd0, latency};
                5'h09: s_axi_rdata <= {16'd0, max_latency};
                5'h0A: s_axi_rdata <= {23'd0, steps_out};
                5'h0B: s_axi_rdata <= cmd_count;
                5'h0C: s_axi_rdata <= events_in;
                5'h0D: s_axi_rdata <= events_dropped;
                5'h0E: s_axi_rdata <= miss_count;
                5'h0F: s_axi_rdata <= nointercept_count;
                5'h10: s_axi_rdata <= servo_pulse;
                5'h11: s_axi_rdata <= tick;
                5'h12: s_axi_rdata <= 32'h52464C01;
                5'h13: s_axi_rdata <= {16'd0, gravity};
                default: s_axi_rdata <= 32'd0;
                endcase
            end
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
        end
    end
endmodule
