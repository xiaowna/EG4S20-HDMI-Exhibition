`timescale 1ns/1ps
module tb_fixed_tone;
 parameter CLK_HZ=480000;
 reg clk=0,rst_n=0,enable=1,sample_ready=1;reg [2:0] tone_sel=2;
 wire sample_valid,sample_tick,overflow;wire signed [23:0] sample_left,sample_right;
 reg [15:0] golden[0:47];reg [23:0] held;
 integer accepted=0,cycles=0,i;
 always #10 clk=~clk;
 audio_tone_bank #(.CLK_HZ(CLK_HZ),.HOLD_ON_BACKPRESSURE(1),.FIXED_1KHZ(1)) dut(.*);
 always @(posedge clk)if(rst_n&&sample_valid&&sample_ready)begin
  if(sample_left!=={golden[accepted%48],8'd0}||sample_right!==sample_left)
   $fatal(1,"fixed 1kHz sample %0d got=%h",accepted,sample_left);
  accepted=accepted+1;
 end
 initial begin
  $readmemh("tone48.hex",golden);
  repeat(4)@(negedge clk);rst_n=1;
  while(accepted<192)begin
   @(negedge clk);cycles=cycles+1;
   // Sustained backpressure may freeze the next sample, never discard it.
   sample_ready=(cycles%31)<19;tone_sel=cycles%8;
  end
  sample_ready=0;while(!sample_valid)@(negedge clk);held=sample_left;
  repeat(5000)begin @(negedge clk);if(sample_valid&&sample_left!==held)$fatal(1,"stalled fixed tone changed");end
  if(overflow)$fatal(1,"backpressure reported overflow");
  rst_n=0;repeat(4)@(negedge clk);accepted=0;enable=1;sample_ready=1;rst_n=1;
  while(accepted<96)@(negedge clk);
  $display("PASS fixed 1kHz: exact 48 samples, stereo, unused tone selections, long stalls, reset, clock=%0d",CLK_HZ);$finish;
 end
 initial begin #50000000;$fatal(1,"fixed tone timeout");end
endmodule
