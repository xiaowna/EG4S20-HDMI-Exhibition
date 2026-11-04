`timescale 1ns/1ps
module tb_gallery_descriptor;
 reg rst_n=0,sys_clk=0,pix_clk=0,start=0;
 reg [15:0] slide_offset=0;
 always #5 sys_clk=~sys_clk;always #10 pix_clk=~pix_clk;
 wire ready_gallery,ready_legacy,error_gallery,error_legacy,burst_gallery,burst_legacy;
 wire [31:0] address_gallery;
 frame_burst_prefetch #(.INTRO_ANIMATION(1),.SLIDE_TRANSITIONS(1),.FIFO_ADDR_BITS(8)) gallery(
  .rst_n(rst_n),.sys_clk(sys_clk),.pix_clk(pix_clk),.start(start),.frame_base(32'd0),
  .start_ready(ready_gallery),.error(error_gallery),.burst_valid(burst_gallery),.burst_addr(address_gallery),
  .burst_ready(1'b0),.burst_data_valid(1'b0),.burst_last(1'b0),.burst_error(1'b0),.burst_data(32'd0),
  .pixel_ready(1'b0),.slide_active(1'b1),.slide_right(1'b0),.slide_offset(slide_offset),
  .intro_active(1'b0),.intro_topic(2'd0),.intro_phase(6'd18),.slide_alpha(6'd16));
 frame_burst_prefetch #(.INTRO_ANIMATION(0),.SLIDE_TRANSITIONS(1),.FIFO_ADDR_BITS(8)) legacy(
  .rst_n(rst_n),.sys_clk(sys_clk),.pix_clk(pix_clk),.start(start),.frame_base(32'd0),
  .start_ready(ready_legacy),.error(error_legacy),.burst_valid(burst_legacy),
  .burst_ready(1'b0),.burst_data_valid(1'b0),.burst_last(1'b0),.burst_error(1'b0),.burst_data(32'd0),
  .pixel_ready(1'b0),.slide_active(1'b1),.slide_right(1'b0),.slide_offset(slide_offset),
  .intro_active(1'b0),.intro_topic(2'd0),.intro_phase(6'd18),.slide_alpha(6'd16));
 task tick;begin @(negedge sys_clk);#1;end endtask
 task reset;begin rst_n=0;start=0;repeat(5)tick;rst_n=1;wait(ready_gallery&&ready_legacy);tick;end endtask
 task launch(input [15:0] descriptor);begin slide_offset=descriptor;start=1;tick;start=0;end endtask
 initial begin
  for(integer n=0;n<3;n=n+1)begin
   reset;
   case(n)0:launch(16'h0c01);1:launch(16'h1001);2:launch(16'h0280);endcase
   repeat(12)tick;
   if(!error_gallery||!error_legacy||burst_gallery||burst_legacy)$fatal(1,"invalid descriptor reached either memory engine");
  end
  reset;launch(16'h093f); // style2, distance319
  repeat(12)tick;
  if(error_gallery||!burst_gallery||address_gallery!=0)$fatal(1,"style bits leaked into valid gallery memory address");
  if(!error_legacy||burst_legacy)$fatal(1,"gallery descriptor silently accepted as legacy distance");
  $display("PASS gallery descriptor:style3/reservedbits/distance640 reject before bursts; valid style2 address stays in frame; legacy16bit guard retained");$finish;
 end
 initial begin #1000000;$fatal(1,"descriptor timeout");end
endmodule
