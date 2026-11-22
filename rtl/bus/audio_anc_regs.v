// =============================================================================
// File: audio_anc_regs.v
// Module: audio_anc_regs
// Project: Active Noise Cancellation (ANC) Audio DSP SoC Core
// Description: AMBA 3 APB Slave Configuration and Telemetry Register Interface.
// =============================================================================

`timescale 1ns / 1ps

module audio_anc_regs (
    input  wire        pclk,
    input  wire        presetn,

    // APB3 Interface
    input  wire [7:0]  paddr,
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] pwdata,
    output reg  [31:0] prdata,
    output wire        pready,
    output wire        pslverr,

    // Control Outputs to DSP
    output reg         reg_anc_enable,
    output reg         reg_reset_weights,
    output reg  [1:0]  reg_anc_mode,     // 0: Bypass, 1: Feedforward, 2: Feedback, 3: Hybrid
    output reg  [15:0] reg_mu_step,      // Default: 16'h0400
    output reg  [15:0] reg_leak_factor,  // Default: 16'h0020
    output reg  [7:0]  reg_volume_gain,  // Master Volume (0-255)

    // Telemetry from DSP
    input  wire        status_divergence,
    input  wire [31:0] pwr_ref_noise,
    input  wire [31:0] pwr_err_noise
);

    assign pready  = 1'b1;
    assign pslverr = 1'b0;

    always @(posedge pclk or negedge presetn) begin
        if (!presetn) begin
            reg_anc_enable    <= 1'b1; // Default enabled
            reg_reset_weights <= 1'b0;
            reg_anc_mode      <= 2'd1; // Default feedforward
            reg_mu_step       <= 16'h0800; // Step size
            reg_leak_factor   <= 16'h0040;
            reg_volume_gain   <= 8'd255;
            prdata            <= 32'd0;
        end else begin
            reg_reset_weights <= 1'b0; // Auto-clearing strobe

            // APB Write Operation
            if (psel && penable && pwrite) begin
                case (paddr)
                    8'h00: begin
                        reg_anc_enable    <= pwdata[0];
                        reg_reset_weights <= pwdata[1];
                        reg_anc_mode      <= pwdata[3:2];
                    end
                    8'h08: reg_mu_step      <= pwdata[15:0];
                    8'h0C: reg_leak_factor  <= pwdata[15:0];
                    8'h10: reg_volume_gain  <= pwdata[7:0];
                    default: ;
                endcase
            end

            // APB Read Operation
            if (psel && !pwrite) begin
                case (paddr)
                    8'h00: prdata <= {28'd0, reg_anc_mode, 1'b0, reg_anc_enable};
                    8'h04: prdata <= {30'd0, status_divergence, reg_anc_enable};
                    8'h08: prdata <= {16'd0, reg_mu_step};
                    8'h0C: prdata <= {16'd0, reg_leak_factor};
                    8'h10: prdata <= {24'd0, reg_volume_gain};
                    8'h14: prdata <= pwr_ref_noise;
                    8'h18: prdata <= pwr_err_noise;
                    default: prdata <= 32'd0;
                endcase
            end
        end
    end

endmodule
