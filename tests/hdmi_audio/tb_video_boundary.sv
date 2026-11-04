`timescale 1ns/1ps
module tb_video_boundary;
 reg sc=0,pc=0,rn=0;always #10 sc=~sc;always #20 pc=~pc;
 reg [9:0] x=0;wire de=x<640,hs=!(x>=656&&x<752);
 wire [9:0] r,g,b;wire fault;
 hdmi_av_output dut(.brightness(9'sd0),.gain_q8(9'd256),.loading(1'b0),.fade_enabled(1'b0),.wave_enabled(1'b0),.audio_only(1'b0),.image_valid(1'b1),.sys_clk(sc),.pix_clk(pc),.rst_n(rn),.audio_enable(1'b1),
 .tone_sel(3'd2),.video_started(1'b1),.catalog_ready(1'b1),.wav_found(1'b0),
 .wav_error(1'b0),.image_count(3'd0),.image_index(2'd0),
 .wav_valid(1'b0),.wav_playing(1'b0),
 .wav_data(48'd0),.wav_ready(),.de(de),.hsync(hs),.vsync(1'b1),.rgb(24'h123456),
 .red(r),.green(g),.blue(b),.audio_fault(fault));
 always @(posedge pc)if(!rn)x<=0;else if(x==799)x<=0;else x<=x+1'b1;
 integer pre=0,guard=0,video=0;
 reg p,g0,v;
 always @(posedge pc)if(rn)begin
  p=dut.video_preamble;g0=dut.video_guard;v=dut.vd;
  #1;
  if(dut.locked && x<25)begin
   if(p)begin
    if(g!==10'b0010101011)$fatal(1,"video preamble green");pre=pre+1;
   end
   if(g0)begin
    if(b!==10'b1011001100||g!==10'b0100110011||r!==10'b1011001100)
     $fatal(1,"video leading guard");
    guard=guard+1;
   end
   if(v)video=video+1;
  end
 end
 initial begin
  repeat(8)@(negedge pc);rn=1;
  repeat(800*3)@(negedge pc);
  if(pre!=16||guard!=4||video<25)$fatal(1,"bad video boundary pre=%0d guard=%0d video=%0d",pre,guard,video);
  $display("PASS HDMI video boundary: two 8-symbol preambles, two 2-symbol guards, active video");
  $finish;
 end
endmodule
