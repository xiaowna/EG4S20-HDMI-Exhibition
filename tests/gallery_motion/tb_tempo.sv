`timescale 1ns/1ps
// Unit test for the actual display control. Memory/raster are deliberately
// inert; separate tests check the real producer, SDRAM and complete pixels.
module tb_gallery_tempo;
 reg rst_n=0,sys_clk=0,pix_clk=0,front_valid=1,front_bank=0;
 reg slide_request=0,slide_right=0,slide_prepared=0;
 always #5 sys_clk=~sys_clk;always #10 pix_clk=~pix_clk;
 frame_stream_display #(.SLIDE_TRANSITIONS(1),.INTRO_ANIMATION(1)) dut(
  .rst_n(rst_n),.sys_clk(sys_clk),.pix_clk(pix_clk),.front_valid(front_valid),.front_bank(front_bank),
  .burst_ready(1'b0),.burst_data_valid(1'b0),.burst_last(1'b0),.burst_error(1'b0),.burst_data(32'd0),
  .slide_request(slide_request),.slide_right(slide_right),.slide_prepared(slide_prepared),
  .intro_enable(1'b0),.intro_pause(1'b0),.intro_index(5'd0));
 reg [8:0] short_curve[0:8],long_curve[0:9];
 integer n,p,duration,frames=0,longs=0,expected;
 task tick;begin @(negedge sys_clk);#1;end endtask
 task boundary;begin force dut.sys_state=1;tick;release dut.sys_state;force dut.sys_state=0;tick;release dut.sys_state;end endtask
 task retire(input bit finished);
 begin
  force dut.sys_state=4;
  if(finished)force dut.pre_done=1'b1;else force dut.pre_done=1'b0;
  tick;release dut.pre_done;release dut.sys_state;
 end endtask
 initial begin
  $readmemh("short_curve.hex",short_curve);$readmemh("long_curve.hex",long_curve);
  repeat(3)tick;rst_n=1;repeat(3)tick;
  slide_request=1;boundary;
  if(dut.slide_running||dut.slide_style_next||dut.slide_tempo_error)$fatal(1,"unprepared back bank started animation");
  slide_prepared=1;front_valid=0;boundary;
  if(dut.slide_running)$fatal(1,"missing front bank started animation");
  front_valid=1;
  for(n=0;n<13;n=n+1)begin
   slide_request=1;slide_right=n%2;boundary;
   duration=9+(((n+1)*3/13)>(n*3/13));
   if(!dut.slide_running||dut.slide_phase!=0||dut.slide_long!==(duration==10)||dut.slide_style!=n%3)
    $fatal(1,"cadence/style selection n=%0d duration=%0d long=%b style=%d",n,duration,dut.slide_long,dut.slide_style);
   if(duration==10)longs=longs+1;
   for(p=0;p<duration;p=p+1)begin
    expected=(duration==10)?long_curve[p]:short_curve[p];
    if(dut.slide_phase!=p||dut.slide_fraction_value!=expected||dut.slide_distance!=(640*expected/256))
     $fatal(1,"frame curve n=%0d phase=%0d got=%0d expected=%0d",n,p,dut.slide_fraction_value,expected);
    if(dut.u_prefetch.slide_offset[15:12]!=0||dut.u_prefetch.slide_offset[11:10]!=n%3||dut.u_prefetch.slide_offset[9:0]!=640*expected/256)
     $fatal(1,"style descriptor corrupted");
    slide_right=!(n%2);retire(0);
    if(dut.slide_done||dut.slide_direction!==(n%2))$fatal(1,"early acknowledgement or live direction changed");
    retire(1);frames=frames+1;
    if(p==duration-1)begin
     if(!dut.slide_done||dut.slide_running)$fatal(1,"last retired frame did not complete transition");
    end else begin
     if(dut.slide_done||!dut.slide_running)$fatal(1,"animation finished early");
     boundary;
    end
   end
   slide_request=0;tick;
   if(dut.slide_done)$fatal(1,"acknowledgement did not retire");
  end
  if(frames!=120||longs!=3||dut.slide_tempo_error!=0)$fatal(1,"average cadence is not exactly 1.3x");
  $display("PASS gallery tempo:13 transitions/120 complete frames,9-10frame cadence,3styles,quintic easing,direction latch,prepared/retirement fences");$finish;
 end
 initial begin #1000000;$fatal(1,"tempo timeout");end
endmodule

module frame_burst_prefetch #(parameter FRAME_PIXELS=307200,FIFO_ADDR_BITS=8,SLIDE_TRANSITIONS=0,LINE_PIXELS=640,INTRO_ANIMATION=0,CACHE_FRAMES=0)(
 input wire rst_n,sys_clk,pix_clk,start,input wire [31:0] frame_base,
 output wire start_ready,busy,done,error,burst_valid,output wire [31:0] burst_addr,
 output wire [8:0] burst_words,input wire burst_ready,burst_data_valid,burst_last,burst_error,
 input wire [31:0] burst_data,output wire pixel_valid,output wire [31:0] pixel_addr,
 output wire [23:0] pixel_rgb,output wire pixel_last,input wire pixel_ready,
 input wire slide_active,slide_right,input wire [15:0] slide_offset,
 input wire intro_active,input wire [1:0] intro_topic,input wire [5:0] intro_phase,slide_alpha,input wire [20:0] back_base);
 assign start_ready=1;assign busy=0;assign done=0;assign error=0;
 assign burst_valid=0;assign burst_addr=0;assign burst_words=0;
 assign pixel_valid=0;assign pixel_addr=0;assign pixel_rgb=0;assign pixel_last=0;
endmodule
module video_raster_timing #(parameter H_ACTIVE=640,H_FP=16,H_SYNC=96,H_BP=48,V_ACTIVE=480,V_FP=10,V_SYNC=2,V_BP=33)(
 input wire clk,rst_n,output wire de,hsync,vsync,blank_start,raster_start);
 assign de=0;assign hsync=1;assign vsync=1;assign blank_start=0;assign raster_start=0;
endmodule
module video_pixel_sink #(parameter FRAME_PIXELS=307200)(
 input wire pix_clk,rst_n,raster_start,de,pixel_valid,input wire [31:0] pixel_addr,
 input wire [23:0] pixel_rgb,input wire pixel_last,output wire pixel_ready,out_de,
 output wire [23:0] out_rgb,output wire frame_underflow);
 assign pixel_ready=0;assign out_de=0;assign out_rgb=0;assign frame_underflow=0;
endmodule
