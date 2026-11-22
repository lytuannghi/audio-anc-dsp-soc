// =============================================================================
// File: i2s_rx.v
// Module: i2s_rx
// Project: Active Noise Cancellation (ANC) Audio DSP SoC Core
// Description: Industrial Philips I2S Stereo Audio Receiver (24-bit Audio in 32-bit Frame).
//              Samples serial data on SCK rising edge with 1-bit delay after WS transition.
// =============================================================================

`timescale 1ns / 1ps

module i2s_rx (
    input  wire        clk,           // High-Speed System Clock (e.g. 50-100 MHz)
    input  wire        rst_n,

    // I2S Bus Physical Signals
    input  wire        sck,           // Bit Clock (typically 3.072 MHz for 48 kHz 32-bit stereo)
    input  wire        ws,            // Word Select / Frame Sync (0: Left Channel, 1: Right Channel)
    input  wire        sd,            // Serial Audio Data Input

    // Parallel Decoded Audio Samples
    output reg         sample_valid,  // Pulsed high for 1 cycle when new stereo frame is ready
    output reg  [23:0] left_data,     // Signed 24-bit Left Audio Sample
    output reg  [23:0] right_data     // Signed 24-bit Right Audio Sample
);

    // Edge detectors for SCK and WS
    reg [2:0] sck_sync;
    reg [2:0] ws_sync;
    reg [1:0] sd_sync;

    wire sck_rising  = (sck_sync[2:1] == 2'b01);
    wire sck_falling = (sck_sync[2:1] == 2'b10);
    wire ws_edge     = (ws_sync[2] != ws_sync[1]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sck_sync <= 3'b000;
            ws_sync  <= 3'b000;
            sd_sync  <= 2'b00;
        end else begin
            sck_sync <= {sck_sync[1:0], sck};
            ws_sync  <= {ws_sync[1:0], ws};
            sd_sync  <= {sd_sync[0], sd};
        end
    end

    reg [31:0] shift_reg;
    reg [5:0]  bit_count;
    reg        ws_prev;
    reg        ch_select; // 0: Left, 1: Right

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_valid <= 1'b0;
            left_data    <= 24'sd0;
            right_data   <= 24'sd0;
            shift_reg    <= 32'd0;
            bit_count    <= 6'd0;
            ws_prev      <= 1'b0;
            ch_select    <= 1'b0;
        end else begin
            sample_valid <= 1'b0;

            if (sck_rising) begin
                shift_reg <= {shift_reg[30:0], sd_sync[1]};

                if (ws_sync[1] != ws_prev) begin
                    // WS transitioned (Philips I2S standard: 1st bit is dummy bit)
                    ws_prev   <= ws_sync[1];
                    ch_select <= ws_sync[1]; // Next channel
                    bit_count <= 6'd0;

                    // Latch completed channel
                    if (ws_prev == 1'b0) begin
                        left_data <= shift_reg[31:8]; // Upper 24 bits
                    end else begin
                        right_data   <= shift_reg[31:8];
                        sample_valid <= 1'b1; // Complete stereo pair ready
                    end
                end else begin
                    bit_count <= bit_count + 6'd1;
                end
            end
        end
    end

endmodule
