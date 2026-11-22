// =============================================================================
// File: noise_power_meter.v
// Module: noise_power_meter
// Project: Active Noise Cancellation (ANC) Audio DSP SoC Core
// Description: Real-Time RMS Acoustic Noise Level and Power Meter.
//              Applies exponential moving average (EMA) energy estimation:
//              E(n) = (1 - alpha) * E(n-1) + alpha * |sample(n)|^2
// =============================================================================

`timescale 1ns / 1ps

module noise_power_meter (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 sample_valid,
    input  wire signed [23:0]   sample_in,
    output reg  [31:0]          rms_power,
    output reg  [23:0]          peak_level
);

    // Alpha smoothing factor = 1/256 (arithmetic shift >>> 8)
    reg [47:0] power_accum;
    reg [23:0] abs_val;

    always @(*) begin
        if (sample_in[23])
            abs_val = -sample_in;
        else
            abs_val = sample_in;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            power_accum <= 48'd0;
            rms_power   <= 32'd0;
            peak_level  <= 24'd0;
        end else if (sample_valid) begin
            // Track peak level with decay
            if (abs_val > peak_level)
                peak_level <= abs_val;
            else if (peak_level > 24'd10)
                peak_level <= peak_level - (peak_level >> 8);

            // EMA Power Accumulator: E = E - (E >> 8) + (abs_val * abs_val)
            power_accum <= power_accum - (power_accum >> 8) + (abs_val * abs_val);
            rms_power   <= power_accum[47:16];
        end
    end

endmodule
