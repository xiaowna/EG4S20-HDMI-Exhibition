`timescale 1ns/1ps
module tb_subtitle;
 reg clk=0,rst_n=0,de=0,vsync=1;
 reg [9:0] x=0,y=0;
 reg [23:0] rgb_in=0;
 wire [23:0] rgb_out;
 reg [1:0] golden[0:4095];
 integer i,j,frame,travel=0,checks=0,lit_count=0,outline_count=0,fd;
 reg [23:0] expected;
 integer tx,address;
 always #5 clk=~clk;
 video_chinese_subtitle dut(.*);
 task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 task advance_frame;
  begin
   de=0;vsync=0;tick;vsync=1;tick;
   travel=(travel==512)?0:travel+1;
   if(dut.scroll!==travel)$fatal(1,"scroll step/wrap expected=%0d actual=%0d",travel,dut.scroll);
  end
 endtask
 task scan;
  begin
   for(j=0;j<480;j=j+1)begin
    for(i=0;i<640;i=i+1)begin
     de=1;x=i;y=j;rgb_in={x[7:0],y[7:0],x[7:0]^y[7:0]};expected=rgb_in;
     tx=i+travel-304;
     if(i>=16&&i<304&&j>=8&&j<24&&tx>=0&&tx<224)begin
      address=(tx/16)*256+(j-8)*16+tx%16;
      if(golden[address]==2)begin expected=24'he7efec;lit_count=lit_count+1;end
      else if(golden[address]==1)begin expected=24'h0b1420;outline_count=outline_count+1;end
     end
     @(posedge clk);#1;
     if(rgb_out!==expected)$fatal(1,"subtitle pixel scroll=%0d xy=%0d,%0d expected=%h actual=%h",travel,i,j,expected,rgb_out);
     if(dut.scroll!==travel)$fatal(1,"scroll changed during active video");
     if(frame==1)$fwrite(fd,"%0d %0d %0d\n",rgb_out[23:16],rgb_out[15:8],rgb_out[7:0]);
     checks=checks+1;@(negedge clk);
    end
    de=0;rgb_in=24'hbbaacc;tick;
    if(rgb_out!==24'hbbaacc)$fatal(1,"blanking bypass changed RGB");
   end
  end
 endtask
 initial begin
  $readmemh("font_golden.hex",golden);
  tick;rst_n=1;tick;
  fd=$fopen("subtitle_frame.ppm","w");$fwrite(fd,"P3\n640 480\n255\n");
  frame=0;scan;
  repeat(224)advance_frame;
  frame=1;scan;
  advance_frame;frame=2;scan;
  repeat(63)advance_frame;frame=3;scan;
  repeat(224)advance_frame;frame=4;scan;
  if(lit_count<1000||outline_count<1000)$fatal(1,"missing font/outline pixels");
  advance_frame;
  if(dut.scroll!==0)$fatal(1,"scroll wrap failed");
  rst_n=0;tick;
  if(dut.scroll!==0||rgb_out!==0)$fatal(1,"reset did not clear metadata");
  $fclose(fd);
  $display("PASS Chinese subtitle: %0d exact RGB pixels, 16px glyphs, 1px/frame, 513-step wrap, clipping/transparent/outline/reset",checks);$finish;
 end
 initial begin #100000000;$fatal(1,"subtitle timeout");end
endmodule

module tb_subtitle_rom;
 reg clk=0;reg [11:0] address=0;wire [1:0] pixel;
 reg [1:0] golden[0:4095];integer i;
 always #5 clk=~clk;
 subtitle_font_rom dut(.*);
 initial begin
  $readmemh("font_golden.hex",golden);
  for(i=0;i<4096;i=i+1)begin
   @(negedge clk);address=i;@(posedge clk);#1;
   if(pixel!==golden[i])$fatal(1,"font ROM address=%0d expected=%d actual=%d",i,golden[i],pixel);
  end
  $display("PASS font ROM: all 8192 bits match independent glyph/outline oracle");$finish;
 end
endmodule
