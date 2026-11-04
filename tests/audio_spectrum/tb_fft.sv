`timescale 1ns/1ps
module tb_fft;
 reg clk=0,rst_n=0,capture_enable=1,sample_valid=0;
 reg signed [23:0] sample_left=0;
 always #5 clk=~clk;
 wire bin_valid,busy;wire [7:0] bin_index;wire signed [15:0] bin_real,bin_imag;
 reg [15:0] samples[0:4095];reg [31:0] golden[0:2047];
 integer n,k,scenario,seen=0,total=0;
 audio_fft512 dut(.*);
 always @(posedge clk)begin #1;
  if(rst_n&&bin_valid)begin
   if(bin_index!==seen[7:0]||{bin_real,bin_imag}!==golden[scenario*256+seen])
    $fatal(1,"FFT scenario=%0d bin=%0d expected=%h actual=%h",scenario,seen,golden[scenario*256+seen],{bin_real,bin_imag});
   seen=seen+1;total=total+1;
  end
 end
 initial begin
  $readmemh("samples.hex",samples);$readmemh("bins.hex",golden);
  repeat(4)@(negedge clk);rst_n=1;
  // Capture gating must not silently count samples while a result is pending.
  capture_enable=0;sample_valid=1;repeat(20)@(negedge clk);
  if(dut.capture_index!=0)$fatal(1,"disabled capture advanced");sample_valid=0;capture_enable=1;
  // Reset a partial window; no stale RAM may leak into the accepted window.
  sample_valid=1;repeat(123)@(negedge clk);sample_valid=0;rst_n=0;
  repeat(3)@(negedge clk);rst_n=1;
  // SW7 may flush the audio FIFO while a transform is in progress.
  sample_valid=1;repeat(512)@(negedge clk);sample_valid=0;
  wait(busy);repeat(100)@(negedge clk);rst_n=0;
  repeat(3)@(negedge clk);rst_n=1;
  for(scenario=0;scenario<8;scenario=scenario+1)begin
   seen=0;
   for(n=0;n<512;n=n+1)begin
    sample_left={samples[scenario*512+n],8'd0};sample_valid=1;
    @(negedge clk);sample_valid=0;
    if(n%7==0)repeat(3)@(negedge clk);
   end
   // Bursts arriving during processing are observational and must be ignored.
   sample_left=24'h7fff00;sample_valid=1;
   wait(seen==256);@(negedge clk);sample_valid=0;
   wait(!busy);repeat(3)@(negedge clk);
  end
  if(total!=2048)$fatal(1,"incomplete FFT coverage");
  $display("PASS FFT512: 2048 exact complex bins; eight independent numeric vectors, capture gating, busy bursts, partial and processing resets");$finish;
 end
 initial begin #10000000;$fatal(1,"FFT timeout");end
endmodule
