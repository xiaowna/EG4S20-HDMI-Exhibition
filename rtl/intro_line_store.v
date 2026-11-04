// Two RGB888 scanlines. A bank is immutable until its final RAM read has
// entered the compositor. Explicit 32K primitives avoid consuming RAM9K.
module intro_line_store(
 input wire clk,write_enable,write_bank,input wire [9:0] write_addr,
 input wire [23:0] write_rgb,input wire read_enable,read_bank,
 input wire [9:0] read_addr,output wire [23:0] read_rgb);
`ifdef __ICARUS__
`ifndef INTRO_NATIVE_RAM
`define INTRO_BEHAVIORAL_RAM
`endif
`endif
`ifdef INTRO_BEHAVIORAL_RAM
 reg [15:0] low_memory[0:2047],high_memory[0:2047];
 reg [15:0] low_q,high_q;
 always @(posedge clk)begin
  if(write_enable)begin
   low_memory[{write_bank,write_addr}]<=write_rgb[15:0];
   high_memory[{write_bank,write_addr}]<={8'd0,write_rgb[23:16]};
  end
  if(read_enable)begin
   low_q<=low_memory[{read_bank,read_addr}];
   high_q<=high_memory[{read_bank,read_addr}];
  end
 end
 assign read_rgb={high_q[7:0],low_q};
`undef INTRO_BEHAVIORAL_RAM
`else
 wire [15:0] low_q,high_q;
 EG_PHY_BRAM32K #(.MODE("DP16K"),.DATA_WIDTH_A("16"),.DATA_WIDTH_B("16"),
  .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL")) low_storage(
  .doa(),.dia(write_rgb[15:0]),.addra({write_bank,write_addr}),
  .bytea(1'b0),.bytewea(1'b0),.csa(write_enable),.wea(write_enable),.clka(clk),.rsta(1'b0),.ocea(1'b1),
  .dob(low_q),.dib(16'd0),.addrb({read_bank,read_addr}),
  .byteb(1'b0),.byteweb(1'b0),.csb(read_enable),.web(1'b0),.clkb(clk),.rstb(1'b0),.oceb(1'b1));
 EG_PHY_BRAM32K #(.MODE("DP16K"),.DATA_WIDTH_A("16"),.DATA_WIDTH_B("16"),
  .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL")) high_storage(
  .doa(),.dia({8'd0,write_rgb[23:16]}),.addra({write_bank,write_addr}),
  .bytea(1'b0),.bytewea(1'b0),.csa(write_enable),.wea(write_enable),.clka(clk),.rsta(1'b0),.ocea(1'b1),
  .dob(high_q),.dib(16'd0),.addrb({read_bank,read_addr}),
  .byteb(1'b0),.byteweb(1'b0),.csb(read_enable),.web(1'b0),.clkb(clk),.rstb(1'b0),.oceb(1'b1));
 assign read_rgb={high_q[7:0],low_q};
`endif
endmodule
