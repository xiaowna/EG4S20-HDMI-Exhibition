`timescale 1ns/1ps
// Accelerated VSYNC edges; each frame still permits a full 256-entry LUT build.
// The independent observation is the actual mapped pixel, not fade_applied.
module tb_prefetch_fade;
 reg sys=0,pix=0,rst_n=0,vsync=1,loading=0,fade_enabled=1;
 reg [10:0] settings_word=0;
 wire transition_ready,wav_ready;
 reg [9:0] x=0;
 wire hsync=!(x>=656&&x<752);
 integer cycles=0,acks=0,table_waits=0,reads=0;
 always #10 sys=~sys;always #20 pix=~pix;
 always @(posedge pix)if(!rst_n)x<=0;else x<=(x==799)?0:x+1'b1;
 hdmi_av_output #(.SETTINGS_UI(1)) dut(.sys_clk(sys),.pix_clk(pix),.rst_n(rst_n),
  .audio_enable(1'b1),.tone_sel(3'd2),.video_started(1'b1),.catalog_ready(1'b1),
  .wav_found(1'b1),.wav_error(1'b0),.audio_only(1'b0),.image_valid(1'b1),
  .image_count(3'd4),.image_index(2'd0),.wav_valid(1'b1),.wav_playing(1'b1),
  .wav_data(48'h123456abcdef),.wav_ready(wav_ready),.de(1'b0),.hsync(hsync),.vsync(vsync),
  .rgb(24'hc08040),.brightness(9'sd0),.gain_q8(9'd256),.loading(loading),
  .fade_enabled(fade_enabled),.wave_enabled(1'b0),.settings_word(settings_word),.transition_ready(transition_ready));
 always @(posedge pix)if(rst_n)begin
  cycles<=cycles+1;
  if(dut.fifo_read)reads<=reads+1;
  if(dut.fade_level==0&&!transition_ready)table_waits<=table_waits+1;
 end
 task ticks(input integer n);begin repeat(n)@(negedge pix);#1;end endtask
 task frame;begin
  vsync=1;ticks(360);vsync=0;ticks(2);vsync=1;ticks(360);
 end endtask
 task black;begin
  if(!transition_ready || dut.adjusted_rgb!==24'h000000)$fatal(1,"fade acknowledged before complete black LUT was visible");
  acks=acks+1;
 end endtask
 initial begin
  ticks(6);rst_n=1;ticks(20);
  repeat(3)frame;
  if(transition_ready||dut.adjusted_rgb!==24'hc08040)$fatal(1,"idle background dimmed picture");
  loading=1;
  for(integer n=0;n<20;n=n+1)begin
   frame;
   if(transition_ready)black;
  end
  black;
  if(table_waits==0)$fatal(1,"never tested target-black versus published-black gap");
  loading=0;ticks(8);if(transition_ready)$fatal(1,"fade ack did not retire");
  repeat(20)frame;
  if(dut.adjusted_rgb!==24'hc08040)$fatal(1,"new image failed to brighten");
  fade_enabled=0;ticks(8);loading=1;ticks(8);
  if(!transition_ready)$fatal(1,"disabled fade blocked cache hit");
  loading=0;ticks(8);fade_enabled=1;ticks(8);loading=1;
  repeat(2)frame;if(transition_ready)$fatal(1,"fade completed before expected frames");
  settings_word[10]=1;ticks(40);
  if(!transition_ready)$fatal(1,"settings overlay deadlocked transition");
  loading=0;ticks(8);settings_word=0;ticks(40);
  loading=1;ticks(8);rst_n=0;ticks(4);
  if(transition_ready)$fatal(1,"reset retained fade acknowledgement");
  loading=0;rst_n=1;ticks(20);frame;
  if(transition_ready||dut.adjusted_rgb!==24'hc08040)$fatal(1,"reset failed to restore visible picture");
  if(reads==0)$fatal(1,"audio not exercised during transitions");
  $display("PASS next-cache fade: acks=%0d table_waits=%0d audio_reads=%0d cycles=%0d; published black, brighten, disabled, settings and reset",acks,table_waits,reads,cycles);$finish;
 end
 initial begin #3000000;$fatal(1,"fade handshake timeout");end
endmodule
