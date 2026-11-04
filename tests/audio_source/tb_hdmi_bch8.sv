`timescale 1ns/1ps
module tb_hdmi_bch8;
 reg clk=0,rst_n=0,start=0;wire busy,done;wire [7:0] ecc;
 always #5 clk=~clk;
 hdmi_bch8 dut(clk,rst_n,start,24'h123456,busy,done,ecc);
 initial begin
  repeat(2)@(negedge clk);rst_n=1;start=1;@(negedge clk);start=0;
  wait(done);#1;if(ecc!==8'h75)$fatal(1,"HDMI BCH mismatch");
  $display("PASS HDMI BCH");$finish;
 end
 initial begin #10000;$fatal(1,"timeout");end
endmodule
