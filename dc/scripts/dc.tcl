#*****************************************
# Setup Environment
#*****************************************
set current_path [pwd]
set project_path "${current_path}/../.."

# tech 32nm
set library_path "/home/tech_libs/SAED32_EDK/lib"
set rvt_path  "${library_path}/stdcell_rvt/db_nldm"
set lvt_path  "${library_path}/stdcell_lvt/db_nldm"
set hvt_path  "${library_path}/stdcell_hvt/db_nldm"

set design_name "top"
set design_path "${project_path}/rtl"
set report_path "${project_path}/dc/reports"
set output_path "${project_path}/dc/outputs"
set script_path "${project_path}/dc/scripts"
set work_path   "${project_path}/dc/work"
set sram_path   "${project_path}/sram"

set search_path [concat "*" ${rvt_path} ${lvt_path} ${hvt_path} ${design_path} ${search_path}]
# LVT, RVT, HVT
#set target_library [list "saed32rvt_ss0p95v125c.db" "saed32lvt_ss0p95v125c.db" "saed32hvt_ss0p95v125c.db" "${sram_path}/db/SRAM_1024x16_2P.db" "${sram_path}/db/SRAM_512x16_2P.db" "${sram_path}/db/SRAM_128x16_2P.db"]
# RVT
#set target_library [list "saed32rvt_ss0p95v125c.db" "${sram_path}/db/SRAM_1024x16_2P.db" "${sram_path}/db/SRAM_512x16_2P.db" "${sram_path}/db/SRAM_128x16_2P.db"]
set target_library [list "saed32rvt_ss0p95v125c.db" "${sram_path}/SRAM_64x1024_2P/SRAM_64x1024_2P.db" "${sram_path}/SRAM_32x1024_2P/SRAM_32x1024_2P.db" "${sram_path}/SRAM_32x32_2P/SRAM_32x32_2P.db" "${sram_path}/SRAM_10x1024_2P/SRAM_10x1024_2P.db" "${sram_path}/SRAM_128x1024_2P/SRAM_128x1024_2P.db"]
set synthetic_library "dw_foundation.sldb"
set link_library [concat "*" ${synthetic_library} ${target_library}]


#*****************************************
# Synthesis Settings
#*****************************************
set hdlin_enable_vpp true
set hdlin_auto_save_templates false
set verilogout_single_bit false
set hdlout_internal_busses true
set bus_naming_style {%s[%d]}
set bus_inference_style $bus_naming_style
set compile_enhanced_resource_sharing true
set hdlin_unsigned_integers true

define_design_lib WORK -path ${work_path}


#*****************************************
# Load Veilog Files
#*****************************************
analyze -format sverilog -vcs "-f ${script_path}/rtl.f"
elaborate ${design_name}
current_design ${design_name}
link


#*****************************************
# Select design and Check
#*****************************************
check_design > "${report_path}/${design_name}_chk_design"
check_timing > "${report_path}/${design_name}_chk_timing"


#*****************************************
# Clock Environment
#*****************************************
set clk_port_pin clk
set clk_name clk
set clock_transition 0.04
# MHz
set clk_freq 250
set clk_period [expr 1000.0 / $clk_freq ]
set high_time [expr $clk_period / 2.0]
set setup_skew 0.1
set hold_skew 0.1

create_clock $clk_port_pin -period $clk_period -waveform [list 0 $high_time] -name $clk_name
set_clock_uncertainty -setup $setup_skew [get_clocks $clk_name]
set_clock_uncertainty -hold $hold_skew [get_clocks $clk_name]
set_clock_transition $clock_transition [get_clocks $clk_name]


#*****************************************
# Compile
#*****************************************
#ungroup -all -flatten
set_max_fanout 20 [current_design]

#compile_ultra
compile_ultra -no_autoungroup -no_boundary_optimization
# -no_autoungroup : disables automatic ungrouping for the entire design

change_names -rules verilog -verbose -hier

#*****************************************
# Report
#*****************************************
report_area -h                      > ${report_path}/${design_name}_area.rpt
report_power                        > ${report_path}/${design_name}_power.rpt
report_timing -path full -delay max > ${report_path}/${design_name}_timing.rpt
report_design                       > ${report_path}/${design_name}_design.rpt
report_synthetic                    > ${report_path}/${design_name}_synthetic.rpt
report_constraint -all_violators    > ${report_path}/${design_name}_constraint.rpt
report_qor                          > ${report_path}/${design_name}_qor.rpt


#*****************************************
# Export
#*****************************************
write_sdf -version 2.1 ${report_path}/${design_name}.sdf
write_sdc -version 2.0 ${report_path}/${design_name}.sdc

write_file -format verilog -h -output ${output_path}/${design_name}.v
write_file -format ddc -output ${output_path}/${design_name}.ddc


exit
