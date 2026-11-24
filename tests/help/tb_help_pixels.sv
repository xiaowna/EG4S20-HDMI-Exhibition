`timescale 1ns/1ps
module tb_help_pixels;
 reg clk=0,rst_n=0,de=0,vsync=1,hint_enable=0;
 reg [9:0] x=0,y=0;
 reg [2:0] help_word=0;
 wire [23:0] rgb_out;wire overlay_valid;
 video_help dut(.*);
 always #5 clk=~clk;
 reg [24:0] expected[0:307199];
 integer n,scene,previous=-1,checks=0;
 reg [255:0] filename;
 task sample(input integer position,input bit valid);
  begin
   @(negedge clk);x=position%640;y=position/640;de=valid;
   @(posedge clk);#1;
   if(previous>=0)begin
    if(overlay_valid!==expected[previous][24]||
      (overlay_valid&&rgb_out!==expected[previous][23:0]))
     $fatal(1,"pixel scene=%0d pos=%0d got=%h/%b expected=%h",scene,previous,rgb_out,overlay_valid,expected[previous]);
    checks=checks+1;
   end
   previous=valid?position:-1;
  end
 endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  for(scene=0;scene<6;scene=scene+1)begin
   $sformat(filename,"expected_%0d.hex",scene);$readmemh(filename,expected);
   @(negedge clk);de=0;vsync=1;hint_enable=scene==4;help_word=scene<4?4+scene:0;
   repeat(3)@(negedge clk);vsync=0;
   repeat(3)@(negedge clk);vsync=1;
   for(n=0;n<307200;n=n+1)begin
    if(scene==0&&n==153600)help_word=7;
    sample(n,1);
   end
   sample(0,0);sample(0,0);
   if(overlay_valid)$fatal(1,"blanking cover leaked");
  end
  $display("PASS help pixels: %0d exact pixels, four pages, hint/hidden, frame-atomic updates, two-clock alignment",checks);$finish;
 end
 initial begin #50000000;$fatal(1,"help pixels timeout");end
endmodule
