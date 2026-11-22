// =============================================================================
// File: audio_fir_filter.v
// Module: audio_fir_filter
// Project: Active Noise Cancellation (ANC) Audio DSP SoC Core
// Description: 16-Tap Parallel Fixed-Point Audio FIR Filter Core.
//              Used for Secondary Acoustic Path Modeling S(z).
//              Inputs/Outputs: 24-bit Signed Audio (Q1.23 format)
//              Coefficients: 16-bit Signed (Q1.15 format)
// =============================================================================

`timescale 1ns / 1ps

module audio_fir_filter #(
    parameter TAPS = 16
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 sample_valid,
    input  wire signed [23:0]   sample_in,
    output reg                  out_valid,
    output reg  signed [23:0]   sample_out
);

    // Pre-calculated acoustic secondary path model S(z) coefficients (low-pass acoustic delay)
    reg signed [15:0] coeffs [0:TAPS-1];
    reg signed [23:0] delay_line [0:TAPS-1];

    integer i;
    initial begin
        coeffs[0]  = 16'sd120;
        coeffs[1]  = 16'sd350;
        coeffs[2]  = 16'sd850;
        coeffs[3]  = 16'sd1650;
        coeffs[4]  = 16'sd2800;
        coeffs[5]  = 16'sd4200;
        coeffs[6]  = 16'sd5500;
        coeffs[7]  = 16'sd6200; // Peak group delay
        coeffs[8]  = 16'sd5500;
        coeffs[9]  = 16'sd4200;
        coeffs[10] = 16'sd2800;
        coeffs[11] = 16'sd1650;
        coeffs[12] = 16'sd850;
        coeffs[13] = 16'sd350;
        coeffs[14] = 16'sd120;
        coeffs[15] = 16'sd40;
    end

    reg signed [47:0] accum;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid  <= 1'b0;
            sample_out <= 24'sd0;
            accum      <= 48'sd0;
            for (i = 0; i < TAPS; i = i + 1) begin
                delay_line[i] <= 24'sd0;
            end
        end else begin
            out_valid <= 1'b0;

            if (sample_valid) begin
                // Shift delay line
                delay_line[0] <= sample_in;
                for (i = 1; i < TAPS; i = i + 1) begin
                    delay_line[i] <= delay_line[i-1];
                end

                // Multiply-accumulate sum = sum(delay[i] * coeffs[i])
                accum <= (sample_in * coeffs[0]) +
                         (delay_line[0]  * coeffs[1])  +
                         (delay_line[1]  * coeffs[2])  +
                         (delay_line[2]  * coeffs[3])  +
                         (delay_line[3]  * coeffs[4])  +
                         (delay_line[4]  * coeffs[5])  +
                         (delay_line[5]  * coeffs[6])  +
                         (delay_line[6]  * coeffs[7])  +
                         (delay_line[7]  * coeffs[8])  +
                         (delay_line[8]  * coeffs[9])  +
                         (delay_line[9]  * coeffs[10]) +
                         (delay_line[10] * coeffs[11]) +
                         (delay_line[11] * coeffs[12]) +
                         (delay_line[12] * coeffs[13]) +
                         (delay_line[13] * coeffs[14]) +
                         (delay_line[14] * coeffs[15]);

                out_valid <= 1'b1;
            end else if (out_valid) begin
                // Normalize from Q1.23 * Q1.15 = Q2.38 back to Q1.23 with saturation
                if (accum[47:38] == 10'd0 || accum[47:38] == 10'h3FF) begin
                    sample_out <= accum[38:15];
                end else if (accum[47]) begin
                    sample_out <= -24'sd8388607; // -2^23
                end else begin
                    sample_out <= 24'sd8388607;  // +2^23 - 1
                end
            end
        end
    end

endmodule
