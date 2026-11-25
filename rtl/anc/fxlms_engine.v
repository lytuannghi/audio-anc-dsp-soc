// =============================================================================
// File: fxlms_engine.v
// Module: fxlms_engine
// Project: Active Noise Cancellation (ANC) Audio DSP SoC Core
// Description: Filtered-X Least Mean Squares (FxLMS) Adaptive Acoustic Noise Cancellation.
//              - Adaptive Filter W(z) with 16 dynamically updating taps
//              - Secondary Path Model S(z) for filtered reference x'(n) computation
//              - Leaky Normalized LMS weight update:
//                W_k(n+1) = (1 - gamma)*W_k(n) + mu * e(n) * x'(n-k)
//              - Generates anti-noise y_anti(n) = -y(n) to cancel acoustic noise.
// =============================================================================

`timescale 1ns / 1ps

module fxlms_engine #(
    parameter TAPS = 16
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // Control & Configuration
    input  wire                 anc_enable,
    input  wire                 reset_weights,
    input  wire signed [15:0]   mu_step,      // Adaptation step size (Q1.15)
    input  wire signed [15:0]   leak_factor,  // Weight decay factor (Q1.15)

    // Real-Time Audio Samples (48 kHz)
    input  wire                 sample_valid,
    input  wire signed [23:0]   ref_noise_in, // x(n): Reference mic outside headphone
    input  wire signed [23:0]   err_noise_in, // e(n): Error mic inside ear canal

    // Anti-Noise Audio Output
    output reg                  anti_noise_valid,
    output reg  signed [23:0]   anti_noise_out, // -y(n): Driven to headphone speaker
    output reg  signed [23:0]   residual_err,   // Output monitoring signal
    output reg                  divergence_flag // Saturation / instability alert
);

    // Filtered Reference Signal x'(n) = x(n) * S(z)
    wire signed [23:0] filt_ref_x_prime;
    wire               filt_ref_valid;

    audio_fir_filter #(.TAPS(TAPS)) u_sec_path_model (
        .clk         (clk),
        .rst_n       (rst_n),
        .sample_valid(sample_valid),
        .sample_in   (ref_noise_in),
        .out_valid   (filt_ref_valid),
        .sample_out  (filt_ref_x_prime)
    );

    // Delay lines for raw reference x(n) and filtered reference x'(n)
    reg signed [23:0] x_delay  [0:TAPS-1];
    reg signed [23:0] xp_delay [0:TAPS-1];

    // Adaptive Filter Weights W_k (16-bit Q1.15)
    reg signed [23:0] weights [0:TAPS-1];

    integer i;

    // FIR Multiply-Accumulate Tree for y(n) = sum(W_k * x(n-k))
    reg signed [47:0] y_accum;
    reg               calc_pending;
    reg signed [39:0] grad_term;
    reg signed [39:0] new_w;
    reg signed [23:0] y_norm;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            anti_noise_valid <= 1'b0;
            anti_noise_out   <= 24'sd0;
            residual_err     <= 24'sd0;
            divergence_flag  <= 1'b0;
            y_accum          <= 48'sd0;
            calc_pending     <= 1'b0;
            for (i = 0; i < TAPS; i = i + 1) begin
                x_delay[i]  <= 24'sd0;
                xp_delay[i] <= 24'sd0;
                weights[i]  <= 24'sd0;
            end
        end else if (reset_weights) begin
            for (i = 0; i < TAPS; i = i + 1) begin
                weights[i] <= 24'sd0;
            end
            divergence_flag  <= 1'b0;
            calc_pending     <= 1'b0;
            anti_noise_valid <= 1'b0;
        end else begin
            anti_noise_valid <= 1'b0;

            if (sample_valid) begin
                // Shift input reference delay lines
                x_delay[0]  <= ref_noise_in;
                xp_delay[0] <= filt_ref_x_prime;
                for (i = 1; i < TAPS; i = i + 1) begin
                    x_delay[i]  <= x_delay[i-1];
                    xp_delay[i] <= xp_delay[i-1];
                end

                if (anc_enable && !divergence_flag) begin
                    // Step 1: Synthesize predicted acoustic noise y(n) = sum(w_k * x_k)
                    y_accum <= (ref_noise_in * weights[0])  +
                               (x_delay[0]   * weights[1])  +
                               (x_delay[1]   * weights[2])  +
                               (x_delay[2]   * weights[3])  +
                               (x_delay[3]   * weights[4])  +
                               (x_delay[4]   * weights[5])  +
                               (x_delay[5]   * weights[6])  +
                               (x_delay[6]   * weights[7])  +
                               (x_delay[7]   * weights[8])  +
                               (x_delay[8]   * weights[9])  +
                               (x_delay[9]   * weights[10]) +
                               (x_delay[10]  * weights[11]) +
                               (x_delay[11]  * weights[12]) +
                               (x_delay[12]  * weights[13]) +
                               (x_delay[13]  * weights[14]) +
                               (x_delay[14]  * weights[15]);

                    // Step 2: Weight update: W_k = (1 - gamma)*W_k + mu * e * x'_k
                    for (i = 0; i < TAPS; i = i + 1) begin
                        grad_term = (err_noise_in * xp_delay[i]) >>> 20;
                        new_w     = weights[i] + ((grad_term * mu_step) >>> 15) - ((weights[i] * leak_factor) >>> 15);

                        if (new_w > 40'sd8388607) begin
                            weights[i]      <= 24'sd8388607;
                            divergence_flag <= 1'b1;
                        end else if (new_w < -40'sd8388608) begin
                            weights[i]      <= -24'sd8388608;
                            divergence_flag <= 1'b1;
                        end else begin
                            weights[i] <= new_w[23:0];
                        end
                    end

                    calc_pending <= 1'b1;
                end else begin
                    // Bypass mode: Anti-noise zeroed
                    anti_noise_out   <= 24'sd0;
                    residual_err     <= err_noise_in;
                    anti_noise_valid <= 1'b1;
                    calc_pending     <= 1'b0;
                end
            end else if (calc_pending) begin
                // Invert phase of predicted noise to emit anti-noise: y_anti = -y(n)
                y_norm           = y_accum[38:15];
                anti_noise_out   <= -y_norm;
                residual_err     <= err_noise_in + (-y_norm);
                anti_noise_valid <= 1'b1;
                calc_pending     <= 1'b0;
            end
        end
    end

endmodule
