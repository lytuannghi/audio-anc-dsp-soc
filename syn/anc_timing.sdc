# ==============================================================================
# Synopsys Design Constraints (SDC) - Active Noise Cancellation Audio DSP SoC
# Target Technology: SkyWater 130nm HD Standard Cell Library (1.80V, 25C)
# Operating Corner: SkyWater 130nm HD Typical Corner (1.80V, 25C)
# Target Frequency: 100.0 MHz (Period = 10.000 ns)
# ==============================================================================

# Master System Clock
create_clock -name clk -period 10.000 [get_ports clk]

# Clock Uncertainty & Jitter Modeling
set_clock_uncertainty -setup 0.250 [get_clocks clk]
set_clock_uncertainty -hold  0.100 [get_clocks clk]
set_clock_transition 0.080 [get_clocks clk]

# I2S Microphone Inputs & APB Interface
set_input_delay -clock clk -max 2.000 [get_ports {i2s_mic_sck i2s_mic_ws i2s_ref_sd i2s_err_sd i2s_spk_sck i2s_spk_ws}]
set_input_delay -clock clk -min 0.300 [get_ports {i2s_mic_sck i2s_mic_ws i2s_ref_sd i2s_err_sd i2s_spk_sck i2s_spk_ws}]
set_input_delay -clock clk -max 1.500 [get_ports {paddr[*] psel penable pwrite pwdata[*]}]
set_input_delay -clock clk -min 0.300 [get_ports {paddr[*] psel penable pwrite pwdata[*]}]

# I2S Speaker Output & APB Interface
set_output_delay -clock clk -max 2.000 [get_ports {i2s_spk_sd status_anc_active status_divergence_alert}]
set_output_delay -clock clk -min 0.300 [get_ports {i2s_spk_sd status_anc_active status_divergence_alert}]
set_output_delay -clock clk -max 1.500 [get_ports {prdata[*] pready pslverr}]
set_output_delay -clock clk -min 0.300 [get_ports {prdata[*] pready pslverr}]

# Drive Strength & Load
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_4 [get_ports {i2s_mic_sck i2s_mic_ws i2s_ref_sd i2s_err_sd i2s_spk_sck i2s_spk_ws paddr[*] psel penable pwrite pwdata[*]}]
set_load 0.025 [all_outputs]

# False Paths
set_false_path -from [get_ports rst_n]
