`timescale 1ns/1ps
module tb_hdmi_audio_packetizer;
 reg clk=0,rst_n=0,start=0,valid=0;reg signed [23:0] l=0,r=0;always #5 clk=~clk;
 wire ready,pvalid,last,busy;wire [1:0] idx;wire [31:0] word;wire [23:0] n;wire [19:0] cts;
 hdmi_audio_packetizer dut(clk,rst_n,start,valid,l,r,ready,pvalid,last,idx,word,n,cts,busy);
 integer seen=0;reg [31:0] words[0:3];
 always @(negedge clk)if(pvalid)begin #1;words[idx]=word;seen=seen+1;end
 initial begin
  repeat(2)@(negedge clk);rst_n=1;l=24'sh123456;r=-24'sh234567;valid=1;start=1;@(negedge clk);start=0;
  wait(seen==4);#1;if(words[0][31:8]!==24'h123456||words[1][31:8]!==24'hdcba99)$fatal(1,"sample pack mismatch");
  if(n!==24'd6144||cts!==20'd25000)$fatal(1,"N/CTS mismatch");
  if(busy||ready)$fatal(1,"packet not released");$display("PASS HDMI audio subpacket words=4 N=%0d CTS=%0d",n,cts);$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule



