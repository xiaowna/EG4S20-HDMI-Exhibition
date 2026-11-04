`timescale 1ns/1ps
// ODDR 在上升沿取两个输入，分别在上、下半周期输出。
module EG_LOGIC_ODDR(output wire q,input wire clk,d1,d0,rst);
 reg rise_bit,fall_bit;
 always @(posedge clk or posedge rst)
  if(rst)begin rise_bit<=0;fall_bit<=0;end
  else begin rise_bit<=d0;fall_bit<=d1;end
 assign q=clk?rise_bit:fall_bit;
endmodule

module tb_tmds_ddr_tx;
 reg pix_clk=0,ser_clk=0,rst_n=0;
 always #20 pix_clk=~pix_clk;
 always #4 ser_clk=~ser_clk;
 reg [9:0] red=0,green=0,blue=0;
 wire clk_p,d0_p,d1_p,d2_p;
 tmds_ddr_tx dut(.pix_clk(pix_clk),.ser_clk(ser_clk),.rst_n(rst_n),
  .red(red),.green(green),.blue(blue),.clk_p(clk_p),
  .d0_p(d0_p),.d1_p(d1_p),.d2_p(d2_p));
 reg [9:0] er[0:127],eg[0:127],eb[0:127];
 reg [9:0] cr,cg,cb;
 integer written=0,matched=0,next_index=-1,bit_index=-1,j;
 reg previous_clock=0;
 function [9:0] pattern_r(input integer n);
  pattern_r=(n*73)^(n>>1)^10'h12f;
 endfunction
 function [9:0] pattern_g(input integer n);
  pattern_g=(n*151)^(n>>2)^10'h293;
 endfunction
 function [9:0] pattern_b(input integer n);
  pattern_b=(n*211)^(n>>3)^10'h3a5;
 endfunction
 always @(negedge pix_clk)if(rst_n && written<128)begin
  red=pattern_r(written);green=pattern_g(written);blue=pattern_b(written);
  er[written]=red;eg[written]=green;eb[written]=blue;
  written=written+1;
 end
 task check_symbol;
  begin
   if(next_index<0)begin
    for(j=3;j<written;j=j+1)
     if(next_index<0 && cr===er[j] && cg===eg[j] && cb===eb[j])
      next_index=j+1;
   end else begin
    if(next_index>=written || cr!==er[next_index] ||
       cg!==eg[next_index] || cb!==eb[next_index])
     $fatal(1,"TMDS symbol %0d mismatch: got %h/%h/%h expected %h/%h/%h",
      next_index,cr,cg,cb,er[next_index],eg[next_index],eb[next_index]);
    matched=matched+1;
    next_index=next_index+1;
   end
  end
 endtask
 always @(posedge ser_clk or negedge ser_clk)begin
  #1;
  if(rst_n)begin
   if(previous_clock && !clk_p)bit_index=0;
   if(bit_index>=0 && bit_index<10)begin
    if(clk_p!==(bit_index>=5))$fatal(1,"forwarded clock bit %0d",bit_index);
    cr[bit_index]=d2_p;cg[bit_index]=d1_p;cb[bit_index]=d0_p;
    bit_index=bit_index+1;
    if(bit_index==10)check_symbol();
   end
   previous_clock=clk_p;
  end
 end
 initial begin
  #25;rst_n=1;
  #4000;
  if(matched<50)$fatal(1,"too few aligned TMDS symbols: %0d",matched);
  $display("PASS TMDS DDR: forwarded clock and %0d consecutive RGB symbols",matched);
  $finish;
 end
endmodule
