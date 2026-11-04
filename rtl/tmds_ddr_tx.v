// Related PLL clocks: pixel=25 MHz, serial=125 MHz. DDR bit rate=250 Mbps.
// One shared load event keeps the forwarded clock and all data lanes aligned.
// Board-specific LVDS ADC constraints create the physical negative pads automatically.
module tmds_ddr_tx(
 input wire pix_clk,ser_clk,rst_n,
 input wire [9:0] red,green,blue,
 output wire clk_p,d0_p,d1_p,d2_p);
 reg toggle;
 (* async_reg="true" *) reg load1,load2;
 reg seen;
 reg [9:0] sr,sg,sb,sc;
 always @(posedge pix_clk or negedge rst_n)
  if(!rst_n) toggle<=0;else toggle<=~toggle;
 always @(posedge ser_clk or negedge rst_n)begin
  if(!rst_n)begin
   load1<=0;load2<=0;seen<=0;sr<=0;sg<=0;sb<=0;sc<=0;
  end else begin
   load1<=toggle;load2<=load1;
   if(load2!=seen)begin
    seen<=load2;sr<=red;sg<=green;sb<=blue;sc<=10'b1111100000;
   end else begin
    sr<={2'b0,sr[9:2]};sg<={2'b0,sg[9:2]};
    sb<={2'b0,sb[9:2]};sc<={2'b0,sc[9:2]};
   end
  end
 end
 EG_LOGIC_ODDR r(.clk(ser_clk),.rst(!rst_n),.d0(sr[0]),.d1(sr[1]),.q(d2_p));
 EG_LOGIC_ODDR g(.clk(ser_clk),.rst(!rst_n),.d0(sg[0]),.d1(sg[1]),.q(d1_p));
 EG_LOGIC_ODDR b(.clk(ser_clk),.rst(!rst_n),.d0(sb[0]),.d1(sb[1]),.q(d0_p));
 EG_LOGIC_ODDR c(.clk(ser_clk),.rst(!rst_n),.d0(sc[0]),.d1(sc[1]),.q(clk_p));
endmodule
