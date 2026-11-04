`timescale 1ns/1ps
module tb_solar_home_rom;
 reg clk=0;reg [16:0] address=0;wire pixel;
 reg bits[0:106495];integer n;
 always #5 clk=~clk;
 home_assets_rom dut(.*);
 initial begin
  $readmemb("home_bits.hex",bits);
  for(n=0;n<106496;n=n+1)begin
   @(negedge clk);address=n;@(posedge clk);#1;
   if(pixel!==bits[n])$fatal(1,"ROM page/bank/bit mismatch address=%0d got=%b expected=%b",n,pixel,bits[n]);
  end
  $display("PASS solar home ROM: all 106496 bits across 6 UI pages and a packed logo in 13 native banks, one-clock read");$finish;
 end
endmodule
