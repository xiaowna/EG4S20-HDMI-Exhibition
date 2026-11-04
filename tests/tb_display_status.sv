`timescale 1ns/1ps
module tb_display_status;
 reg clk=0,rst_n=0,launch=0,commit=0,done=0,err=0,catalog=0;
 reg [1:0] target=0;reg [2:0] count=3;
 wire [1:0] shown;wire audio_only;
 always #10 clk=~clk;
 sd_media_player dut(.clk(clk),.pix_clk(clk),.rst_n(rst_n),.sd_miso(1'b1),.prev_pulse(1'b0),
  .next_pulse(1'b0),.pause(1'b0),.audio_urgent(1'b0),.wav_ready(1'b0),
  .display_index(shown),.audio_only(audio_only));
 initial begin
  force dut.load_start=launch;force dut.load_ready=1'b1;
  force dut.image_index=target;force dut.frame_committed=commit;
  force dut.image_done=done;force dut.image_error=err;
  force dut.catalog_ready=catalog;force dut.image_count=count;
  repeat(3)@(negedge clk);rst_n=1;
  target=2;launch=1;@(negedge clk);launch=0;
  repeat(3)@(negedge clk);
  if(shown!=0)$fatal(1,"pending target leaked into display index");
  commit=1;@(negedge clk);commit=0;
  if(shown!=2)$fatal(1,"committed index missing");
  target=1;launch=1;@(negedge clk);launch=0;done=1;err=1;
  @(negedge clk);done=0;err=0;
  if(shown!=2 || !audio_only)$fatal(1,"failed image changed index or blocked audio fallback");
  rst_n=0;@(negedge clk);rst_n=1;catalog=1;count=0;
  @(negedge clk);
  if(!audio_only)$fatal(1,"WAV-only card did not allow audio");
  $display("PASS committed image status, failed-image and empty-catalog audio fallback");$finish;
 end
 initial begin #10000;$fatal(1,"status timeout");end
endmodule
