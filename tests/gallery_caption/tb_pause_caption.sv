`timescale 1ns/1ps
// Exercise the production player boundary. The card and frame pipeline are
// inert here; the real raster/producer have independent full-pixel tests.
module tb_gallery_pause_caption;
 reg clk=0,rst_n=0,pause=1,intro_pause=0;
 always #5 clk=~clk;
 sd_media_player #(.MODE_CONTROL(1),.INTRO_ANIMATION(1)) dut(
  .clk(clk),.pix_clk(clk),.rst_n(rst_n),.sd_miso(1'b1),
  .next_pulse(1'b0),.prev_pulse(1'b0),.pause(pause),.audio_urgent(1'b0),
  .wav_ready(1'b0),.transition_ready(1'b0),.auto_enable(1'b0),.wav_enable(1'b0),
  .album_request(1'b0),.album_enable(1'b0),.album_first(2'd0),.album_limit(3'd4),
  .intro_enable(1'b1),.intro_pause(intro_pause));
 task tick;begin @(negedge clk);#1;end endtask
 initial begin
  repeat(3)tick;rst_n=1;repeat(3)tick;
  if(dut.u_media.intro_pause!==0)$fatal(1,"paused playback freezes a new caption until KEY2 resumes");
  if(dut.u_control.pause!==1)$fatal(1,"autoplay pause lost while fixing caption");
  intro_pause=1;tick;if(dut.u_media.intro_pause!==1)$fatal(1,"settings/mode pause ignored");
  intro_pause=0;pause=0;tick;if(dut.u_media.intro_pause!==0)$fatal(1,"unpaused UI blocked");
  pause=1;tick;if(dut.u_media.intro_pause!==0)$fatal(1,"second playback pause blocks caption");
  force dut.transition_active=1'b1;tick;
  if(dut.u_media.intro_pause!==1)$fatal(1,"transition snapshot fence removed");
  release dut.transition_active;
  $display("PASS captions independent of KEY2 playback pause; autoplay pause, settings/mode pause and transition fence retained");$finish;
 end
endmodule
