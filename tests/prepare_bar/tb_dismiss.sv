`timescale 1ns/1ps
module tb_prepare_dismiss;
 reg clk=0,rst_n=0,de=1,vsync=1;reg [9:0] x=200,y=456,prepare_word=0;
 wire [23:0] rgb_out;wire overlay_valid;integer s,i,checks=0;
 always #5 clk=~clk;video_prepare_overlay dut(.*);
 task tick;begin @(negedge clk);#1;end endtask
 task frame;begin vsync=0;tick;vsync=1;tick;end endtask
 initial begin
  repeat(3)tick;rst_n=1;tick;
  for(s=1;s<=6;s=s+1)begin
   prepare_word={s[2:0],7'd37};frame;if(!overlay_valid)$fatal(1,"wait panel absent");
   prepare_word=0;repeat(9)frame;
   if(dut.frame_word!=0||overlay_valid||dut.done_frames!=0)$fatal(1,"3D exit retained stale panel stage=%0d",s);
   for(i=0;i<12;i=i+1)begin frame;if(overlay_valid)$fatal(1,"dismiss redisplayed panel");checks=checks+1;end
  end
  prepare_word={3'd3,7'd37};frame;prepare_word=0;frame;
  if(dut.frame_word[9:7]!=7)$fatal(1,"normal completion removed");
  prepare_word=0;repeat(9)frame;if(overlay_valid)$fatal(1,"completion retained in 3D");
  $display("PASS prepare exit: %0d checks, all waits/error/completion retire within nine frame latches",checks);$finish;
 end
endmodule
