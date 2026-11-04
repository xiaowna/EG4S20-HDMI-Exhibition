`timescale 1ns/1ps
module tb_dmz_colorbar_video;
 reg clk=0,rst_n=0;
 always #20 clk=~clk;
 wire de,hsync,vsync;
 wire [23:0] rgb;
 dmz_colorbar_video dut(.pix_clk(clk),.rst_n(rst_n),
  .de(de),.hsync(hsync),.vsync(vsync),.rgb(rgb));
 integer px,py,n,active_pixels=0,hs_pixels=0,vs_pixels=0;
 integer bar_pixels[0:7];
 reg expected_de;
 reg [23:0] expected_rgb;
 function [23:0] color(input integer column);
  case(column/80)
   0:color=24'hffffff;
   1:color=24'hffff00;
   2:color=24'h00ffff;
   3:color=24'h00ff00;
   4:color=24'hff00ff;
   5:color=24'hff0000;
   6:color=24'h0000ff;
   default:color=24'h000000;
  endcase
 endfunction
 task check_pixel(input integer column,input integer row);
  begin
   expected_de=column<640 && row<480;
   expected_rgb=expected_de?color(column):24'h000000;
   if(de!==expected_de || rgb!==expected_rgb ||
      hsync!==!(column>=656 && column<752) ||
      vsync!==!(row>=490 && row<492))
    $fatal(1,"pixel (%0d,%0d): de=%b hs=%b vs=%b rgb=%h expected=%h",
     column,row,de,hsync,vsync,rgb,expected_rgb);
  end
 endtask
 task check_reset;
  begin
   #1;
   if(de!==0 || rgb!==24'h000000 || hsync!==1 || vsync!==1)
    $fatal(1,"reset must blank video and deassert sync");
  end
 endtask
 initial begin
  for(n=0;n<8;n=n+1)bar_pixels[n]=0;
  check_reset();
  #80;rst_n=1;
  // Synchronize from the first visible pixel, independent of DUT counters.
  wait(de===1'b1);
  @(negedge clk);
  px=0;py=0;
  for(n=0;n<2*800*525;n=n+1)begin
   check_pixel(px,py);
   if(de)begin
    active_pixels=active_pixels+1;
    bar_pixels[px/80]=bar_pixels[px/80]+1;
   end
   if(!hsync)hs_pixels=hs_pixels+1;
   if(!vsync)vs_pixels=vs_pixels+1;
   if(px==799)begin px=0;if(py==524)py=0;else py=py+1;end
   else px=px+1;
   @(negedge clk);
  end
  if(active_pixels!=614400 || hs_pixels!=100800 || vs_pixels!=3200)
   $fatal(1,"frame counts: active=%0d hs=%0d vs=%0d",
    active_pixels,hs_pixels,vs_pixels);
  for(n=0;n<8;n=n+1)
   if(bar_pixels[n]!=76800)$fatal(1,"bar %0d pixel count=%0d",n,bar_pixels[n]);
  // Interrupt an active line, then verify clean restart through a full line.
  repeat(103)@(negedge clk);
  rst_n=0;
  check_reset();
  repeat(3)@(negedge clk);
  #1;rst_n=1;
  wait(de===1'b1);
  @(negedge clk);
  for(n=0;n<800;n=n+1)begin
   check_pixel(n,0);
   @(negedge clk);
  end
  check_pixel(0,1);
  $display("PASS DMZ colorbar: two complete frames, 614400 active pixels, eight bars, reset recovery");
  $finish;
 end
 initial begin #100000000;$fatal(1,"video test timeout");end
endmodule
