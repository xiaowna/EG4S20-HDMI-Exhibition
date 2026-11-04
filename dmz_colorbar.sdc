# Same PLL clock relationship as the player; no SDRAM/FIFO in this test.
create_clock -name ref_clk -period 20 [get_ports clk50]
create_generated_clock -name pixel -source [get_ports clk50] -divide_by 2 [get_pins {u_pll/pll_inst.clkc[0]}]
create_generated_clock -name serial -source [get_ports clk50] -multiply_by 2.5 [get_pins {u_pll/pll_inst.clkc[1]}]
create_generated_clock -name system -source [get_ports clk50] -divide_by 1 [get_pins {u_pll/pll_inst.clkc[2]}]
set_false_path -from [get_ports rst_n]
