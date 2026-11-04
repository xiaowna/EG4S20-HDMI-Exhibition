`timescale 1ns/1ps
// The FFT itself is exercised by audio_spectrum and fft_ram32k. This test
// isolates the gallery/3D layout boundary with a maximum published bar.
module audio_fft512(input clk,rst_n,capture_enable,sample_valid,
 input signed [23:0] sample_left,output bin_valid,output [7:0] bin_index,
 output signed [15:0] bin_real,bin_imag,output busy);
 assign bin_valid=0;assign bin_index=0;assign bin_real=0;assign bin_imag=0;assign busy=0;
endmodule
module tb_gallery_spectrum;
 reg pix_clk=0,rst_n=0,de=0,vsync=1,scene_valid=0;
 reg [9:0] x=0;reg [8:0] y=0;
 wire [23:0] rgb_out;
 integer count=0,painted=0;reg expected_bar;
 always #5 pix_clk=~pix_clk;
 video_audio_spectrum #(.SCENE_3D(1),.GALLERY_LAYOUT(1)) dut(
  .pix_clk(pix_clk),.rst_n(rst_n),.sample_rst_n(1'b1),.rgb_in(24'h123456),
  .rgb_background(24'h060c14),.de(de),.vsync(vsync),.x(x),.y(y),.wave_enable(1'b1),
  .sample_valid(1'b0),.sample_left(24'd0),.rgb_out(rgb_out),
  .scene_rgb(24'h112233),.scene_valid(scene_valid));
 initial begin
  repeat(3)@(negedge pix_clk);rst_n=1;
  force dut.display_enabled=1;force dut.active_valid=1;force dut.bar_read=7'd96;
  for(integer scene=0;scene<2;scene=scene+1)begin
   scene_valid=scene;
   for(integer row=0;row<480;row=row+1)begin
    @(negedge pix_clk);de=0;@(negedge pix_clk);de=1;y=row;
    for(integer col=0;col<640;col=col+1)begin
     x=col;@(posedge pix_clk);#1;
     expected_bar=row>=476||((col%20)>=1&&(col%20)<19&&row>=(scene?345:420));
     if(expected_bar)begin
      if(rgb_out!==dut.color_q)$fatal(1,"missing spectrum bar scene=%0d x=%0d y=%0d",scene,col,row);
      painted=painted+1;
     end else if(rgb_out!==(scene?24'h112233:(row>=416?24'h060c14:24'h123456)))
      $fatal(1,"spectrum damaged image/caption/background scene=%0d x=%0d y=%0d got=%h",scene,col,row,rgb_out);
     count=count+1;@(negedge pix_clk);
    end
   end
  end
  $display("PASS gallery spectrum: %0d pixels, %0d bars; caption rows352..415 untouched, full width baseline, compact60px gallery and original135px 3D",count,painted);$finish;
 end
endmodule
