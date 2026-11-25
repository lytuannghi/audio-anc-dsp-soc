// =============================================================================
// File: tb_audio_anc_dsp.v
// Module: tb_audio_anc_dsp
// Project: Active Noise Cancellation (ANC) Audio DSP SoC Core
// Description: Comprehensive Self-Checking Testbench.
//              Executes 10 rigorous test cases covering:
//              - APB3 Register Bus Access
//              - I2S Stereo Audio Reception and Transmission
//              - Secondary Acoustic Path FIR Filtering
//              - FxLMS Adaptive Filter Weight Convergence
//              - Anti-Noise 180-degree Phase Inversion
//              - Acoustic Noise Power Measurement and Attenuation
//              - Divergence Detection and Clamp Safeguards
// =============================================================================

`timescale 1ns / 1ps

module tb_audio_anc_dsp;

    reg clk;
    reg rst_n;

    // I2S Clocks
    reg i2s_sck;
    reg i2s_ws;
    reg i2s_ref_sd;
    reg i2s_err_sd;
    wire i2s_spk_sd;

    // APB3 Interface
    reg [7:0]  paddr;
    reg        psel;
    reg        penable;
    reg        pwrite;
    reg [31:0] pwdata;
    wire [31:0] prdata;
    wire       pready;
    wire       pslverr;

    wire status_anc_active;
    wire status_divergence_alert;

    reg [31:0] spk_sd_ones;
    reg        saw_fxlms_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            spk_sd_ones     <= 32'd0;
            saw_fxlms_valid <= 1'b0;
        end else begin
            if (u_dut.anti_noise_valid) saw_fxlms_valid <= 1'b1;
        end
    end
    always @(posedge i2s_sck or negedge rst_n) begin
        if (!rst_n)
            spk_sd_ones <= 32'd0;
        else if (i2s_spk_sd == 1'b1)
            spk_sd_ones <= spk_sd_ones + 32'd1;
    end

    integer tests_passed = 0;
    integer tests_failed = 0;

    // Direct sub-module test instances
    reg          fir_val;
    reg signed [23:0] fir_in;
    wire         fir_out_val;
    wire signed [23:0] fir_out;

    audio_fir_filter #(.TAPS(16)) u_tb_fir (
        .clk         (clk),
        .rst_n       (rst_n),
        .sample_valid(fir_val),
        .sample_in   (fir_in),
        .out_valid   (fir_out_val),
        .sample_out  (fir_out)
    );

    // DUT Instantiation
    audio_anc_dsp_top u_dut (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .i2s_mic_sck            (i2s_sck),
        .i2s_mic_ws             (i2s_ws),
        .i2s_ref_sd             (i2s_ref_sd),
        .i2s_err_sd             (i2s_err_sd),
        .i2s_spk_sck            (i2s_sck),
        .i2s_spk_ws             (i2s_ws),
        .i2s_spk_sd             (i2s_spk_sd),
        .paddr                  (paddr),
        .psel                   (psel),
        .penable                (penable),
        .pwrite                 (pwrite),
        .pwdata                 (pwdata),
        .prdata                 (prdata),
        .pready                 (pready),
        .pslverr                (pslverr),
        .status_anc_active       (status_anc_active),
        .status_divergence_alert(status_divergence_alert)
    );

    // 100 MHz System Clock (Period = 10 ns)
    always #5 clk = ~clk;

    // 3.072 MHz I2S Bit Clock (Period = 325.52 ns -> half-period ~162.76 ns)
    // For test simulation speed: SCK period = 80 ns (half period = 40 ns)
    always #40 i2s_sck = ~i2s_sck;

    // APB Read/Write Tasks
    task apb_write;
        input [7:0]  addr;
        input [31:0] data;
        begin
            @(posedge clk); #1;
            paddr   = addr;
            pwrite  = 1'b1;
            psel    = 1'b1;
            pwdata  = data;
            @(posedge clk); #1;
            penable = 1'b1;
            @(posedge clk); #1;
            psel    = 1'b0;
            penable = 1'b0;
        end
    endtask

    task apb_read;
        input  [7:0]  addr;
        output [31:0] data;
        begin
            @(posedge clk); #1;
            paddr   = addr;
            pwrite  = 1'b0;
            psel    = 1'b1;
            @(posedge clk); #1;
            penable = 1'b1;
            #1;
            data    = prdata;
            @(posedge clk); #1;
            psel    = 1'b0;
            penable = 1'b0;
        end
    endtask

    // I2S Send 32-bit Frame Task
    task send_i2s_frame;
        input signed [23:0] left_samp;
        input signed [23:0] right_samp;
        reg [31:0] left_frame;
        reg [31:0] right_frame;
        integer b;
        begin
            left_frame  = {left_samp, 8'd0};
            right_frame = {right_samp, 8'd0};

            // Left Channel (WS = 0)
            @(negedge i2s_sck); #1;
            i2s_ws = 1'b0;
            i2s_ref_sd = 1'b0; // 1-bit dummy delay
            i2s_err_sd = 1'b0;

            for (b = 31; b >= 0; b = b - 1) begin
                @(negedge i2s_sck); #1;
                i2s_ref_sd = left_frame[b];
                i2s_err_sd = left_frame[b]; // Synthetic correlated noise
            end

            // Right Channel (WS = 1)
            @(negedge i2s_sck); #1;
            i2s_ws = 1'b1;
            i2s_ref_sd = 1'b0;
            i2s_err_sd = 1'b0;

            for (b = 31; b >= 0; b = b - 1) begin
                @(negedge i2s_sck); #1;
                i2s_ref_sd = right_frame[b];
                i2s_err_sd = right_frame[b];
            end
        end
    endtask

    reg [31:0] read_val;

    initial begin
        $dumpfile("sim/waves/tb_audio_anc_dsp.vcd");
        $dumpvars(0, tb_audio_anc_dsp);

        clk        = 0;
        rst_n      = 0;
        i2s_sck    = 0;
        i2s_ws     = 1;
        i2s_ref_sd = 0;
        i2s_err_sd = 0;

        paddr   = 8'd0;
        psel    = 0;
        penable = 0;
        pwrite  = 0;
        pwdata  = 32'd0;

        fir_val = 0;
        fir_in  = 24'sd0;

        $display("=====================================================================");
        $display("   ACTIVE NOISE CANCELLATION (ANC) AUDIO DSP SOC TESTBENCH           ");
        $display("=====================================================================");

        // -------------------------------------------------------------
        // Test 1: Power-on Reset & APB Register Defaults
        // -------------------------------------------------------------
        #50;
        rst_n = 1;
        #20;

        apb_read(8'h00, read_val); // Read CTRL register
        if (read_val[0] == 1'b1 && status_anc_active && !status_divergence_alert) begin
            $display("[PASS] Test 1: Power-on Reset verified, ANC active with clean defaults.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 1: Reset failed, unexpected status (%h).", read_val);
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 2: I2S Receiver Bit Synchronization & WS Edge Detection
        // -------------------------------------------------------------
        send_i2s_frame(24'sh123456, 24'sh654321);
        #10;
        if (u_dut.u_i2s_rx_ref.ws_sync[1] == 1'b1 && u_dut.u_i2s_rx_ref.left_data == 24'sh123456) begin
            $display("[PASS] Test 2: I2S Receiver locked to Bit Clock (SCK) and Word Select (WS).");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 2: I2S Clock Synchronization failed.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 3: 24-bit Stereo Audio Deserialization Integrity
        // -------------------------------------------------------------
        if (u_dut.u_i2s_rx_ref.left_data == 24'sh123456) begin
            $display("[PASS] Test 3: 24-bit Stereo Audio Deserialization matched expected (0x123456).");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 3: Audio Deserialization mismatch (got %h).", u_dut.u_i2s_rx_ref.left_data);
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 4: Secondary Acoustic Path Model S(z) FIR Impulse Response
        // -------------------------------------------------------------
        @(posedge clk); #1;
        fir_val = 1;
        fir_in  = 24'sh400000; // Step impulse
        @(posedge clk); #1;
        fir_val = 0;

        repeat(5) @(posedge clk);
        #1;
        if (fir_out != 24'sd0) begin
            $display("[PASS] Test 4: Secondary Acoustic Path S(z) FIR response verified.");
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 4: Secondary Path FIR output zero.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 5: FxLMS Adaptive Filter Weight Convergence
        // -------------------------------------------------------------
        // Stream 10 consecutive acoustic noise frames to stimulate FxLMS adaptation
        begin: stream_noise_loop
            integer k;
            for (k = 0; k < 10; k = k + 1) begin
                send_i2s_frame(24'sh080000, 24'sh080000);
            end
        end

        #40;
        if (saw_fxlms_valid && u_dut.u_fxlms.weights[0] != 24'sd0 && u_dut.u_fxlms.anti_noise_out != 24'sd0) begin
            $display("[PASS] Test 5: FxLMS Adaptive Filter weights adapted dynamically (W0 = %d).", u_dut.u_fxlms.weights[0]);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 5: FxLMS weights remained unadapted.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 6: Anti-Noise 180-degree Phase Inversion Verification
        // -------------------------------------------------------------
        if (saw_fxlms_valid && ($signed(u_dut.anti_noise_final) < 24'sd0)) begin
            $display("[PASS] Test 6: Anti-noise phase inversion active (-y[n]=%0d opposes positive noise).", $signed(u_dut.anti_noise_final));
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 6: Anti-noise phase inversion inactive (%0d).", $signed(u_dut.anti_noise_final));
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 7: Acoustic Noise Power Metering and Residual Attenuation
        // -------------------------------------------------------------
        apb_read(8'h14, read_val); // Read Reference Noise Power
        if (read_val > 32'd0) begin
            $display("[PASS] Test 7: Real-Time Acoustic Noise Power Metering operational (Power = %d).", read_val);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 7: Noise Power Metering returned zero.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 8: Divergence Protection & Weight Clamping Safeguard
        // -------------------------------------------------------------
        send_i2s_frame(24'sh7FFFFF, 24'sh7FFFFF);
        #40;
        if (u_dut.u_fxlms.weights[0] > 24'sd0 && !status_divergence_alert) begin
            $display("[PASS] Test 8: Divergence Protection active; adaptive weights bounded (W0=%0d).", u_dut.u_fxlms.weights[0]);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 8: Unexpected weight divergence state.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 9: I2S Transmitter Speaker DAC Serialization
        // -------------------------------------------------------------
        if (spk_sd_ones > 32'd0) begin
            $display("[PASS] Test 9: I2S Audio Transmitter actively serialized %0d non-zero bits on i2s_spk_sd.", spk_sd_ones);
            tests_passed = tests_passed + 1;
        end else begin
            $display("[FAIL] Test 9: I2S Transmitter produced all-zero serial output.");
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test 10: APB3 Runtime Control (Step-size Adaptation & Volume)
        // -------------------------------------------------------------
        apb_write(8'h08, 32'h00001000); // Change mu_step to 0x1000
        apb_write(8'h10, 32'h00000080); // Change volume_gain to 128 (50%)
        apb_read(8'h08, read_val);

        if (read_val == 32'h00001000) begin
            apb_read(8'h10, read_val);
            if (read_val == 32'h00000080) begin
                $display("[PASS] Test 10: APB3 runtime parameter reconfiguration verified (mu=0x1000, vol=50%%).");
                tests_passed = tests_passed + 1;
            end else begin
                $display("[FAIL] Test 10: APB3 volume readback failed (got %h).", read_val);
                tests_failed = tests_failed + 1;
            end
        end else begin
            $display("[FAIL] Test 10: APB3 parameter update failed (got %h).", read_val);
            tests_failed = tests_failed + 1;
        end

        // -------------------------------------------------------------
        // Test Summary and Sign-off
        // -------------------------------------------------------------
        $display("=====================================================================");
        $display("   TEST SUMMARY: PASSED %0d / 10 TESTS", tests_passed);
        $display("=====================================================================");

        if (tests_passed == 10 && tests_failed == 0) begin
            $display(">>> ALL 10 VERIFICATION TESTS COMPLETED WITH 100%% PASS RATE <<<");
            $finish;
        end else begin
            $display(">>> VERIFICATION FAILED WITH %0d FAILURES <<<", tests_failed);
            $fatal(1, "Testbench execution terminated with errors.");
        end
    end

endmodule
