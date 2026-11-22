// =============================================================================
// File: i2s_tx.v
// Module: i2s_tx
// Project: Active Noise Cancellation (ANC) Audio DSP SoC Core
// Description: Industrial Philips I2S Stereo Audio Transmitter.
//              Serializes 24-bit Left/Right audio samples onto SD output.
// =============================================================================

`timescale 1ns / 1ps

module i2s_tx (
    input  wire        clk,
    input  wire        rst_n,

    // I2S Bit Timing Strobe (e.g. pulses at 3.072 MHz)
    input  wire        sck,
    input  wire        ws,
    output reg         sd,

    // Audio Input FIFO Interface
    input  wire        sample_load,
    input  wire [23:0] left_in,
    input  wire [23:0] right_in
);

    reg [2:0] sck_sync;
    reg [2:0] ws_sync;
    wire sck_falling = (sck_sync[2:1] == 2'b10);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sck_sync <= 3'b000;
            ws_sync  <= 3'b000;
        end else begin
            sck_sync <= {sck_sync[1:0], sck};
            ws_sync  <= {ws_sync[1:0], ws};
        end
    end

    reg [31:0] shift_reg;
    reg [23:0] latched_left;
    reg [23:0] latched_right;
    reg        ws_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sd            <= 1'b0;
            shift_reg     <= 32'd0;
            latched_left  <= 24'sd0;
            latched_right <= 24'sd0;
            ws_prev       <= 1'b0;
        end else begin
            if (sample_load) begin
                latched_left  <= left_in;
                latched_right <= right_in;
            end

            if (sck_falling) begin
                if (ws_sync[1] != ws_prev) begin
                    ws_prev <= ws_sync[1];
                    // Load shift register on channel transition
                    if (!ws_sync[1]) begin
                        shift_reg <= {latched_left, 8'd0};
                    end else begin
                        shift_reg <= {latched_right, 8'd0};
                    end
                    sd <= 1'b0; // 1-bit delay
                end else begin
                    sd        <= shift_reg[31];
                    shift_reg <= {shift_reg[30:0], 1'b0};
                end
            end
        end
    end

endmodule
