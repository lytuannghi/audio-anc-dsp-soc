# ==============================================================================
# Synthesis Script - Synopsys Design Compiler
# Module: audio_anc_dsp_top
# ==============================================================================

set DESIGN_NAME "audio_anc_dsp_top"
set RTL_DIR "../rtl"
set REPORT_DIR "./reports"
file mkdir $REPORT_DIR

set rtl_files [list \
    "$RTL_DIR/i2s/i2s_rx.v" \
    "$RTL_DIR/i2s/i2s_tx.v" \
    "$RTL_DIR/dsp/audio_fir_filter.v" \
    "$RTL_DIR/dsp/noise_power_meter.v" \
    "$RTL_DIR/anc/fxlms_engine.v" \
    "$RTL_DIR/bus/audio_anc_regs.v" \
    "$RTL_DIR/audio_anc_dsp_top.v" \
]

foreach file $rtl_files {
    analyze -format verilog $file
}

elaborate $DESIGN_NAME
current_design $DESIGN_NAME

read_sdc ./anc_timing.sdc
compile_ultra -gate_clock

report_timing -delay_type max -nworst 10 -max_paths 10 > $REPORT_DIR/timing_report.txt
report_area -hierarchy > $REPORT_DIR/area_report.txt
report_power -hierarchy > $REPORT_DIR/power_report.txt
report_qor > $REPORT_DIR/qor_report.txt

write_file -format verilog -hierarchy -output ./netlist/${DESIGN_NAME}_syn.v
write_file -format ddc -hierarchy -output ./netlist/${DESIGN_NAME}_syn.ddc
