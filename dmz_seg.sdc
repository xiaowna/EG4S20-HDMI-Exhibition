create_clock -name ref_clk -period 20 [get_ports clk50]
set_false_path -from [get_ports rst_n]
