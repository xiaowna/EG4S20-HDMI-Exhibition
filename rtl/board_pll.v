// Device PLL wrapper: 50 MHz reference; 25/125/50 MHz outputs.
`timescale 1 ns / 100 fs

module board_pll (
  refclk,
  reset,
  extlock,
  clk0_out,
  clk1_out,
  clk2_out 
);

  input refclk;
  input reset;
  output extlock;
  output clk0_out;
  output clk1_out;
  output clk2_out;
  wire clk1_buf,clk2_buf;
  EG_LOGIC_BUFG b1(.i(clk1_buf),.o(clk1_out));
  EG_LOGIC_BUFG b2(.i(clk2_buf),.o(clk2_out));

  wire clk0_buf;
  // Explicit sinks for unused PLL dynamic/status ports.
  wire board_pll_open0, board_pll_open1, board_pll_open2, board_pll_open3;
  wire board_pll_open4, board_pll_open5, board_pll_open6, board_pll_open7;
  wire board_pll_open8, board_pll_open9, board_pll_open10, board_pll_open11;

  EG_LOGIC_BUFG bufg_feedback (
    .i(clk0_buf),
    .o(clk0_out) 
  );

  EG_PHY_PLL #(
    .DPHASE_SOURCE("DISABLE"),
    .DYNCFG("DISABLE"),
    .FIN("50.000000"),
    .FEEDBK_MODE("NORMAL"),
    .FEEDBK_PATH("CLKC0_EXT"),
    .STDBY_ENABLE("DISABLE"),
    .PLLRST_ENA("ENABLE"),
    .SYNC_ENABLE("DISABLE"),
    .GMC_GAIN(2),
    .ICP_CURRENT(9),
    .KVCO(2),
    .LPF_CAPACITOR(1),
    .LPF_RESISTOR(8),
    .REFCLK_DIV(2),
    .FBCLK_DIV(1),
    .CLKC0_ENABLE("ENABLE"),
    .CLKC0_DIV(40),
    .CLKC0_CPHASE(39),
    .CLKC0_FPHASE(0),
    .CLKC1_ENABLE("ENABLE"),
    .CLKC1_DIV(8),
    .CLKC1_CPHASE(7),
    .CLKC1_FPHASE(0),
    .CLKC2_ENABLE("ENABLE"), .CLKC2_DIV(20), .CLKC2_CPHASE(19), .CLKC2_FPHASE(0) 
  ) pll_inst (
    .refclk(refclk),
    .reset(reset),
    .stdby(1'b0),
    .extlock(extlock),
    .load_reg(1'b0),
    .psclk(1'b0),
    .psdown(1'b0),
    .psstep(1'b0),
    .psclksel(3'b000),
    .psdone(board_pll_open0),
    .dclk(1'b0),
    .dcs(1'b0),
    .dwe(1'b0),
    .di(8'b00000000),
    .daddr(6'b000000),
    .do({board_pll_open8, board_pll_open7, board_pll_open6, board_pll_open5, board_pll_open4, board_pll_open3, board_pll_open2, board_pll_open1}),
    // Feed back the PLL output before the global pixel-clock buffer.
    .fbclk(clk0_buf),
    .clkc({board_pll_open11, board_pll_open10, clk2_buf, clk1_buf, clk0_buf}) 
  );

endmodule

