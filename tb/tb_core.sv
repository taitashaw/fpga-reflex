// tb_core: drives reflex_core at sensor rate (up to one event per cycle) from a
// stimulus file and logs every window, command, miss and no-intercept for the
// Python checker. Plusargs: +STIM=<file> +CFG=<file> +OUT=<file>
`timescale 1ns/1ps
module tb_core;
    reg clk = 0;
    always #5 clk = ~clk;                 // 100 MHz

    reg         rst = 1, enable = 0, guard_en = 0;
    reg  [19:0] window_cycles, min_events;
    reg  [9:0]  paddle_y, roi_radius;
    reg  [15:0] gravity;
    reg         s_valid = 0;
    reg  [20:0] s_data = 0;
    wire        s_ready, cmd_valid, locked, guard_active, servo_pwm;
    wire [9:0]  x_pred;
    wire [15:0] latency, max_latency;
    wire [8:0]  steps_out;
    wire [31:0] events_in, events_dropped, cmd_count, miss_count, nointercept_count, servo_pulse, tick;

    reflex_core dut (
        .clk(clk), .rst(rst), .enable(enable), .guard_en(guard_en),
        .window_cycles(window_cycles), .paddle_y(paddle_y),
        .min_events(min_events), .roi_radius(roi_radius), .gravity(gravity),
        .s_valid(s_valid), .s_data(s_data), .s_ready(s_ready),
        .cmd_valid(cmd_valid), .x_pred(x_pred), .latency(latency),
        .max_latency(max_latency), .steps_out(steps_out),
        .locked(locked), .guard_active(guard_active),
        .events_in(events_in), .events_dropped(events_dropped),
        .cmd_count(cmd_count), .miss_count(miss_count),
        .nointercept_count(nointercept_count), .servo_pulse(servo_pulse),
        .servo_pwm(servo_pwm), .tick(tick)
    );

    integer ev_tick [0:262143];
    reg [20:0] ev_data [0:262143];
    integer n_ev, idx, fd, fo, rc, t, d;
    integer W, PY, MINEV, R, GUARD, END_T, G;
    string stim, cfg, outf;
    reg [31:0] miss_prev, noi_prev;

    initial begin
        if (!$value$plusargs("STIM=%s", stim)) $fatal(1, "no +STIM");
        if (!$value$plusargs("CFG=%s", cfg))   $fatal(1, "no +CFG");
        if (!$value$plusargs("OUT=%s", outf))  $fatal(1, "no +OUT");
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
        $display("tb_core: %0d events, W=%0d guard=%0d end=%0d", n_ev, W, GUARD, END_T);

        window_cycles = W; paddle_y = PY; min_events = MINEV; roi_radius = R; guard_en = GUARD; gravity = G;
        repeat (4) @(posedge clk);
        rst <= 0;
        repeat (2) @(posedge clk);
        enable <= 1;                       // tick 0 is the first cycle with enable high
        idx = 0;
        miss_prev = 0; noi_prev = 0;
        forever begin
            @(negedge clk);
            if (tick == END_T) begin
                $fdisplay(fo, "END %0d %0d %0d %0d %0d %0d", events_in, events_dropped,
                          cmd_count, miss_count, nointercept_count, max_latency);
                $fclose(fo);
                $display("tb_core: done at tick %0d, %0d commands", tick, cmd_count);
                $finish;
            end
            // log what is visible this cycle (registered outputs), before driving inputs
            if (dut.window.snap_valid)
                $fdisplay(fo, "WIN %0d %0d %0d %0d", tick, dut.window.snap_cnt, dut.window.snap_sx, dut.window.snap_sy);
            if (cmd_valid)
                $fdisplay(fo, "CMD %0d %0d %0d %0d %0d", tick, x_pred, latency, steps_out, servo_pulse);
            if (miss_count != miss_prev) $fdisplay(fo, "MISS %0d", tick);
            if (nointercept_count != noi_prev) $fdisplay(fo, "NOI %0d", tick);
            miss_prev = miss_count; noi_prev = nointercept_count;
            // drive the event (if any) for this tick
            if (idx < n_ev && ev_tick[idx] == tick) begin
                s_valid <= 1; s_data <= ev_data[idx]; idx = idx + 1;
            end else begin
                s_valid <= 0;
            end
        end
    end
endmodule
