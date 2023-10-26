#*****************************************
# Setup Environment
#*****************************************
set project_path "$env(PWD)/../.."
set library_path "/home/tech_libs/ss28lpp/lib/db"

set design_name "bitmap_manager"
set design_path "${project_path}/rtl"
set report_path "${project_path}/dc/reports"
set output_path "${project_path}/dc/outputs"
set script_path "${project_path}/dc/scripts"
set work_path   "${project_path}/dc/work"

set search_path [concat "*" ${library_path} ${design_path} ${search_path}]
set target_library [list "sc9_cmos28lpp_base_rvt_ss_nominal_max_0p900v_125c_sadhm.db"]
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
analyze -format verilog -vcs "-f ${script_path}/filelist.f"
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
set clk_port_pin i_clk
set clk_name i_clk
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
ungroup -all -flatten
set_max_fanout 20 [current_design]
#compile_ultra
compile


#*****************************************
# Report
#*****************************************
report_area > ${report_path}/${design_name}_area.rpt
report_power > ${report_path}/${design_name}_power.rpt
report_timing -path full -delay max > ${report_path}/${design_name}_timing.rpt
report_design > ${report_path}/${design_name}_design.rpt
report_synthetic > ${report_path}/${design_name}_synthetic.rpt
report_constraint -all_violators > ${report_path}/${design_name}_constraint.rpt
report_qor > ${report_path}/${design_name}_qor.rpt


#*****************************************
# Export
#*****************************************
write_sdf -version 2.1 ${report_path}/${design_name}.sdf
write_sdc -version 2.0 ${report_path}/${design_name}.sdc

write_file -format verilog -output ${output_path}/${design_name}.v
write_file -format ddc -output ${output_path}/${design_name}.ddc


exit
