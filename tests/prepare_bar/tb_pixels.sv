`timescale 1ns/1ps
module tb_prepare_pixels;
 reg clk=0,rst_n=0,de=0,vsync=1;always #5 clk=~clk;
 reg [9:0] x=0,y=0,prepare_word=0;wire [23:0] rgb_out;wire overlay_valid;
 video_prepare_overlay dut(.*);
 integer fd,n,xx,yy,word,phase,golden,checks=0,i;reg [9:0] held;
 task tick;begin @(negedge clk);#1;end endtask
 task frame;begin vsync=0;tick;vsync=1;tick;end endtask
 initial begin
  repeat(3)tick;rst_n=1;tick;de=1;
  fd=$fopen("pixels.txt","r");if(!fd)$fatal(1,"missing independent vectors");
  while(!$feof(fd))begin
   n=$fscanf(fd,"%d %d %h %d %h\n",xx,yy,word,phase,golden);
   if(n==5)begin
    // Pixel geometry is independent of the controller; latch each stage at VS.
    prepare_word=word;frame;dut.phase=phase;x=xx;y=yy;tick;
    if({overlay_valid,rgb_out}!==golden[24:0])$fatal(1,"pixel xy=%0d,%0d stage=%0d phase=%0d got=%h want=%h",xx,yy,word>>7,phase,{overlay_valid,rgb_out},golden);
    checks=checks+1;
   end
  end
  $fclose(fd);
  prepare_word={3'd3,7'd37};frame;held=dut.frame_word;
  prepare_word={3'd6,7'd0};repeat(30)tick;
  if(dut.frame_word!==held)$fatal(1,"status tore inside a frame");
  frame;if(dut.frame_word[9:7]!=6)$fatal(1,"error missing");
  prepare_word=0;frame;if(dut.frame_word!=0)$fatal(1,"error falsely completed");
  prepare_word={3'd3,7'd75};frame;prepare_word=0;frame;
  if(dut.frame_word[9:7]!=7)$fatal(1,"completion missing");
  for(i=0;i<7;i=i+1)begin frame;if(dut.frame_word[9:7]!=7)$fatal(1,"completion too short");end
  frame;if(dut.frame_word!=0)$fatal(1,"completion never hid");
  prepare_word={3'd2,7'd0};frame;de=0;tick;if(overlay_valid)$fatal(1,"overlay leaked into blanking");
  rst_n=0;#1;if(overlay_valid||rgb_out)$fatal(1,"async reset");
  $display("PASS progress pixels: %0d independent panel vectors; frame freeze, error, completion and blanking",checks);$finish;
 end
 initial begin #200000000;$fatal(1,"timeout");end
endmodule
