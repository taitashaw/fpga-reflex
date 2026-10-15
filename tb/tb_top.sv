// tb_top: drives reflex_top through its AXI4-Lite port only, the way the PS will.
// Events go in through EVT_INJECT; the ticks the core actually saw are recorded
// (+SEEN) so the Python model can be run on exactly that stream. At the end every
// result register is read back over AXI and checked against the core's value.
`timescale 1ns/1ps
// BD_NETLIST: the DUT is the "reflex" hierarchy Vivado generated from the block
// design (module name passed as BD_HIER_MOD); otherwise it is rtl/reflex_top.v.
`ifdef BD_NETLIST
  `define W dut.window
  `define T dut.tracker
  `define G dut.gate
  `define S dut.servo
`else
  `define W dut.core.window
  `define T dut.core.tracker
  `define G dut.core.gate
  `define S dut.core.servo
`endif
module tb_top;
    reg clk = 0;
    always #5 clk = ~clk;
    reg aresetn = 0;

    reg  [6:0]  awaddr = 0, araddr = 0;
    reg         awvalid = 0, wvalid = 0, arvalid = 0;
    reg  [31:0] wdata = 0;
    wire        awready, wready, bvalid, arready, rvalid;
    wire [1:0]  bresp, rresp;
    wire [31:0] rdata;
    wire [3:0]  led;

`ifdef BD_NETLIST
    `BD_HIER_MOD dut (
        .clk(clk), .aresetn(aresetn),
`else
    reflex_top #(.LED_STRETCH(200)) dut (
        .aclk(clk), .aresetn(aresetn),
`endif
        .s_axi_awaddr(awaddr), .s_axi_awprot(3'd0), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(4'hF), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(1'b1),
        .s_axi_araddr(araddr), .s_axi_arprot(3'd0), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(1'b1),
        .led(led)
    );

    task automatic axi_write(input [6:0] a, input [31:0] v);
        begin
            @(posedge clk); #1; awaddr = a; wdata = v; awvalid = 1; wvalid = 1;
            forever begin @(negedge clk); if (awready) break; end
            @(posedge clk); #1; awvalid = 0; wvalid = 0;
            forever begin @(negedge clk); if (bvalid) break; end
            @(posedge clk);
        end
    endtask

    task automatic axi_read(input [6:0] a, output [31:0] v);
        begin
            @(posedge clk); #1; araddr = a; arvalid = 1;
            forever begin @(negedge clk); if (arready) break; end
            @(posedge clk); #1; arvalid = 0;
            forever begin @(negedge clk); if (rvalid) break; end
            v = rdata;
            @(posedge clk);
        end
    endtask

    integer ev_tick [0:262143];
    reg [20:0] ev_data [0:262143];
    integer n_ev, i, fd, fo, fs, rc, t, d, errors;
    integer W, PY, MINEV, R, GUARD, END_T, G;
    string stim, cfg, outf, seenf;
    reg [31:0] miss_prev, noi_prev, v;
    reg logging = 0, done = 0;

    // ---- logger: same format as tb_core, reading the core inside the wrapper ----
    always @(negedge clk) if (logging && !done) begin
        if (`W.tick == END_T) begin
            $fdisplay(fo, "END %0d %0d %0d %0d %0d %0d", `G.events_in, `G.events_dropped,
                      `T.cmd_count, `T.miss_count, `T.nointercept_count, `T.max_latency);
            $fclose(fo); $fclose(fs);
            done = 1;
        end else begin
            if (`W.snap_valid)
                $fdisplay(fo, "WIN %0d %0d %0d %0d", `W.tick, `W.snap_cnt, `W.snap_sx, `W.snap_sy);
            if (`T.cmd_valid)
                $fdisplay(fo, "CMD %0d %0d %0d %0d %0d", `W.tick, `T.x_pred, `T.latency,
                          `T.steps_out, `S.servo_pulse);
            if (`T.miss_count != miss_prev) $fdisplay(fo, "MISS %0d", `W.tick);
            if (`T.nointercept_count != noi_prev) $fdisplay(fo, "NOI %0d", `W.tick);
            miss_prev = `T.miss_count; noi_prev = `T.nointercept_count;
            if (`G.s_valid && `W.enable)
                $fdisplay(fs, "%0d %06x", `W.tick, `G.s_data);
        end
    end

    task automatic check(input [6:0] a, input [31:0] want, input string name);
        begin
            axi_read(a, v);
            if (v !== want) begin
                errors = errors + 1;
                $display("FAIL readback %s @0x%02h: got %0d want %0d", name, a, v, want);
            end else $display("ok   readback %s = %0d", name, v);
        end
    endtask

    initial begin
        if (!$value$plusargs("STIM=%s", stim)) $fatal(1, "no +STIM");
        if (!$value$plusargs("CFG=%s", cfg))   $fatal(1, "no +CFG");
        if (!$value$plusargs("OUT=%s", outf))  $fatal(1, "no +OUT");
        if (!$value$plusargs("SEEN=%s", seenf)) $fatal(1, "no +SEEN");
        fd = $fopen(cfg, "r");
        rc = $fscanf(fd, "%d %d %d %d %d %d %d", W, PY, MINEV, R, GUARD, END_T, G);
        $fclose(fd);
        fd = $fopen(stim, "r");
        n_ev = 0;
        while ($fscanf(fd, "%d %h", t, d) == 2) begin
            ev_tick[n_ev] = t; ev_data[n_ev] = d; n_ev = n_ev + 1;
        end
        $fclose(fd);
        fo = $fopen(outf, "w");
        fs = $fopen(seenf, "w");
        errors = 0; miss_prev = 0; noi_prev = 0;

        repeat (4) @(posedge clk);
        aresetn = 1;
        repeat (2) @(posedge clk);
        check(7'h48, 32'h52464C01, "VERSION");
        axi_write(7'h04, W);
        axi_write(7'h08, PY);
        axi_write(7'h0C, MINEV);
        axi_write(7'h10, R);
        axi_write(7'h4C, G);
        check(7'h4C, G, "GRAVITY");
        check(7'h04, W, "WINDOW");
        check(7'h08, PY, "PADDLE_Y");
        logging = 1;
        axi_write(7'h00, {30'd0, GUARD[0], 1'b1});      // enable (+ guard)
        for (i = 0; i < n_ev && ev_tick[i] < END_T - 8; i = i + 1) begin
            while (`W.tick < ev_tick[i]) @(negedge clk);
            axi_write(7'h14, ev_data[i]);
        end
        wait (done);
        $display("tb_top: %0d stimulus events, %0d commands", n_ev, `T.cmd_count);
        check(7'h1C, `T.x_pred, "X_PRED");
        check(7'h20, `T.latency, "LATENCY");
        check(7'h24, `T.max_latency, "MAX_LATENCY");
        check(7'h28, `T.steps_out, "STEPS");
        check(7'h2C, `T.cmd_count, "CMD_COUNT");
        check(7'h30, `G.events_in, "EVENTS_IN");
        check(7'h34, `G.events_dropped, "EVENTS_DROPPED");
        check(7'h38, `T.miss_count, "MISS_COUNT");
        check(7'h40, `S.servo_pulse, "SERVO_PULSE");
        check(7'h18, {29'd0, 1'b1, `G.guard_active, `T.locked}, "STATUS");
        if (`T.cmd_count == 0) begin errors = errors + 1; $display("FAIL no commands"); end
        if (errors == 0) $display("AXI READBACK PASS");
        else $display("AXI READBACK FAIL %0d", errors);
        $finish;
    end
endmodule
