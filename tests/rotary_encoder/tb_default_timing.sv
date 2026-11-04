`timescale 1ns/1ps
module tb_default_timing;
 reg clk=0,rst_n=0,enable=1,encoder_a=1,encoder_b=1,encoder_press_n=1;
 always #10 clk=~clk;
 wire [3:0] encoder_event;
 media_rotary_encoder dut(.*);
 integer ticks=0,previous_tick=0,clocks=0,ok=0,back=0;
 always @(posedge clk)begin
  clocks=clocks+1;
  if(rst_n&&dut.tick)begin
   if(ticks>0 && clocks-previous_tick!=5000)$fatal(1,"default sample period");
   previous_tick=clocks;ticks=ticks+1;
  end
  #1;
  if(encoder_event[1])ok=ok+1;
  if(encoder_event[3])back=back+1;
  if(encoder_event[0]||encoder_event[2])$fatal(1,"idle rotation");
 end
 task cycles(input integer n);begin repeat(n)@(negedge clk);#2;end endtask
 initial begin
  cycles(4);rst_n=1;cycles(220*5000);
  encoder_press_n=0;cycles(1000*5000);
  if(ok||back)$fatal(1,"short gesture fired before release");
  encoder_press_n=1;cycles(220*5000);
  if(ok!=1||back)$fatal(1,"100ms short press");
  encoder_press_n=0;cycles(6199*5000);
  if(ok!=1||back)$fatal(1,"long press fired early");
  cycles(8*5000);if(ok!=1||back!=1)$fatal(1,"600ms long threshold after 20ms debounce");
  cycles(300*5000);if(back!=1)$fatal(1,"long repeat");
  encoder_press_n=1;cycles(220*5000);
  if(ok!=1||back!=1)$fatal(1,"long release emitted short OK");
  $display("PASS default 50MHz timing: 5000-cycle sampling, 20ms debounce, 100ms short, 600ms long, no repeat or release OK");$finish;
 end
 initial begin #900000000;$fatal(1,"default timing timeout");end
endmodule
