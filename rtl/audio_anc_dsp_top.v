// =============================================================================
// File: audio_anc_dsp_top.v
// Module: audio_anc_dsp_top
// Project: Active Noise Cancellation (ANC) Audio DSP SoC Core
// Description: Full-Flow Synthesizable Top-Level ASIC Active Noise Cancellation SoC Core.
//              Integrates:
//              - Dual-Channel I2S Serial Audio Receivers (Reference & Error Mics)
//              - I2S Serial Audio Transmitter (Anti-Noise DAC Driver)
//              - Filtered-X Least Mean Squares (FxLMS) Adaptive Filter Subsystem
//              - Acoustic Noise Power Measurement & Divergence Safeguard
//              - AMBA 3 APB Slave Configuration and Diagnostic Bus
// =============================================================================

`timescale 1ns / 1ps

module audio_anc_dsp_top (
    input  wire        clk,           // Master System Clock (100 MHz)
    input  wire        rst_n,

    // I2S Microphone Input Interface (from Audio ADC / PDM-to-I2S Decimator)
    input  wire        i2s_mic_sck,   // 3.072 MHz Bit Clock
    input  wire        i2s_mic_ws,    // 48 kHz Word Select
    input  wire        i2s_ref_sd,    // Reference Mic Serial Audio Data (Left: Ref Mic)
    input  wire        i2s_err_sd,    // Error Mic Serial Audio Data (Left: Error Mic)

    // I2S Speaker Output Interface (to Audio DAC / Class-D Headphone Amp)
    input  wire        i2s_spk_sck,
    input  wire        i2s_spk_ws,
    output wire        i2s_spk_sd,    // Serial Anti-Noise Audio Output

    // AMBA 3 APB Slave Control Bus
    input  wire [7:0]  paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    output wire [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    // Status Flags
    output wire        status_anc_active,
    output wire        status_divergence_alert
);

    // =========================================================================
    // I2S Receivers for Reference and Error Microphones
    // =========================================================================
    wire        ref_valid;
    wire [23:0] ref_left, ref_right;

    i2s_rx u_i2s_rx_ref (
        .clk         (clk),
        .rst_n       (rst_n),
        .sck         (i2s_mic_sck),
        .ws          (i2s_mic_ws),
        .sd          (i2s_ref_sd),
        .sample_valid(ref_valid),
        .left_data   (ref_left),
        .right_data  (ref_right)
    );

    wire        err_valid;
    wire [23:0] err_left, err_right;

    i2s_rx u_i2s_rx_err (
        .clk         (clk),
        .rst_n       (rst_n),
        .sck         (i2s_mic_sck),
        .ws          (i2s_mic_ws),
        .sd          (i2s_err_sd),
        .sample_valid(err_valid),
        .left_data   (err_left),
        .right_data  (err_right)
    );

    // =========================================================================
    // APB3 Configuration Registers
    // =========================================================================
    wire        reg_anc_enable;
    wire        reg_reset_weights;
    wire [1:0]  reg_anc_mode;
    wire [15:0] reg_mu_step;
    wire [15:0] reg_leak_factor;
    wire [7:0]  reg_volume_gain;

    wire [31:0] pwr_ref_val;
    wire [31:0] pwr_err_val;
    wire        fxlms_divergence;

    audio_anc_regs u_regs (
        .pclk             (clk),
        .presetn          (rst_n),
        .paddr            (paddr),
        .psel             (psel),
        .penable          (penable),
        .pwrite           (pwrite),
        .pwdata           (pwdata),
        .prdata           (prdata),
        .pready           (pready),
        .pslverr          (pslverr),
        .reg_anc_enable   (reg_anc_enable),
        .reg_reset_weights(reg_reset_weights),
        .reg_anc_mode     (reg_anc_mode),
        .reg_mu_step      (reg_mu_step),
        .reg_leak_factor  (reg_leak_factor),
        .reg_volume_gain  (reg_volume_gain),
        .status_divergence(fxlms_divergence),
        .pwr_ref_noise    (pwr_ref_val),
        .pwr_err_noise    (pwr_err_val)
    );

    // =========================================================================
    // Filtered-X LMS Adaptive Noise Cancellation Engine
    // =========================================================================
    wire               anti_noise_valid;
    wire signed [23:0] anti_noise_raw;
    wire signed [23:0] residual_err_out;

    fxlms_engine #(.TAPS(16)) u_fxlms (
        .clk             (clk),
        .rst_n           (rst_n),
        .anc_enable      (reg_anc_enable),
        .reset_weights   (reg_reset_weights),
        .mu_step         (reg_mu_step),
        .leak_factor     (reg_leak_factor),
        .sample_valid    (ref_valid),
        .ref_noise_in    (ref_left),
        .err_noise_in    (err_left),
        .anti_noise_valid(anti_noise_valid),
        .anti_noise_out  (anti_noise_raw),
        .residual_err    (residual_err_out),
        .divergence_flag (fxlms_divergence)
    );

    // Volume Scaling: Scaled Output = (anti_noise_raw * volume_gain) >>> 8
    wire signed [31:0] scaled_anti = (anti_noise_raw * $signed({1'b0, reg_volume_gain})) >>> 8;
    wire signed [23:0] anti_noise_final = scaled_anti[23:0];

    // =========================================================================
    // I2S Transmitter to Speaker / Headphone Driver
    // =========================================================================
    i2s_tx u_i2s_tx_spk (
        .clk        (clk),
        .rst_n      (rst_n),
        .sck        (i2s_spk_sck),
        .ws         (i2s_spk_ws),
        .sd         (i2s_spk_sd),
        .sample_load(anti_noise_valid),
        .left_in    (anti_noise_final),
        .right_in   (anti_noise_final) // Duplicate mono anti-noise to stereo
    );

    // =========================================================================
    // Acoustic Noise Power Meters
    // =========================================================================
    noise_power_meter u_pwr_ref (
        .clk         (clk),
        .rst_n       (rst_n),
        .sample_valid(ref_valid),
        .sample_in   (ref_left),
        .rms_power   (pwr_ref_val),
        .peak_level  ()
    );

    noise_power_meter u_pwr_err (
        .clk         (clk),
        .rst_n       (rst_n),
        .sample_valid(ref_valid),
        .sample_in   (residual_err_out),
        .rms_power   (pwr_err_val),
        .peak_level  ()
    );

    assign status_anc_active        = reg_anc_enable;
    assign status_divergence_alert = fxlms_divergence;

endmodule
