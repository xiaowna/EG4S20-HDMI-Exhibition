# All three clocks share the PLL reference; keep their phase relationship.
create_clock -name ref_clk -period 20 [get_ports clk50]
create_generated_clock -name pixel -source [get_ports clk50] -divide_by 2 [get_pins {u_pll/pll_inst.clkc[0]}]
create_generated_clock -name serial -source [get_ports clk50] -multiply_by 2.5 [get_pins {u_pll/pll_inst.clkc[1]}]
create_generated_clock -name system -source [get_ports clk50] -divide_by 1 [get_pins {u_pll/pll_inst.clkc[2]}]
# SDRAM captures commands half a system cycle after they are registered.
create_generated_clock -name sdram -source [get_pins {u_pll/pll_inst.clkc[2]}] -divide_by 1 -invert [get_pins {u_player/u_media/u_memory/u_memory.clk}]
# 两个跨时钟 FIFO 的格雷码指针必须在最短时钟周期内到达首级同步器。
# 50 MHz 系统时钟周期为 20 ns；按 TD 自带 soft_fifo 的写法留 0.3 ns 裕量。
# 仅约束指针到首级同步器，不屏蔽其他系统/像素跨域路径的时序检查。
set_max_delay -from [get_regs -hier {u_player/u_media/u_display/u_prefetch/u_fifo/wg[*]}] -to [get_regs -hier {u_player/u_media/u_display/u_prefetch/u_fifo/wg1[*]}] 19.7 -datapath_only
set_max_delay -from [get_regs -hier {u_player/u_media/u_display/u_prefetch/u_fifo/rg[*]}] -to [get_regs -hier {u_player/u_media/u_display/u_prefetch/u_fifo/rg1[*]}] 19.7 -datapath_only
set_max_delay -from [get_regs -hier {av/fifo/wr_gray[*]}] -to [get_regs -hier {av/fifo/wr_gray_r1[*]}] 19.7 -datapath_only
set_max_delay -from [get_regs -hier {av/fifo/rd_gray[*]}] -to [get_regs -hier {av/fifo/rd_gray_w1[*]}] 19.7 -datapath_only
# Asynchronous board inputs terminate at two-stage synchronizers.
set_false_path -from [get_ports {key_col_n[0] key_col_n[1] key_col_n[2] key_col_n[3] sd_miso mode_sw7}]
# IR receiver output terminates at its two-stage system-clock synchronizer.
set_false_path -from [get_ports infrared_n]
# DS1302 DAT terminates at its two-stage system-clock synchronizer.
# CLK/CE outputs and all internal RTC/overlay paths remain timed.
set_false_path -from [get_ports rtc_sda]
# User reset assertion is asynchronous. Internal release remains timed.
set_false_path -from [get_ports rst_n]
