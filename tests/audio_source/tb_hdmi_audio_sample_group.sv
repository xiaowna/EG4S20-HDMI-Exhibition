`timescale 1ns/1ps
module tb_hdmi_audio_sample_group;
 reg clk=0,rst_n=0,v=0,ready=0;reg signed [23:0] l=0,r=0;always #5 clk=~clk;
 wire in_ready,gv;wire [1:0] count;wire signed [23:0] l0,r0,l1,r1,l2,r2;
 hdmi_audio_sample_group dut(clk,rst_n,v,l,r,in_ready,gv,ready,l0,r0,l1,r1,l2,r2,count);
 initial begin repeat(2)@(negedge clk);rst_n=1;@(negedge clk);v=1;l=1;r=11;@(negedge clk);l=2;r=12;@(negedge clk);l=3;r=13;@(negedge clk);v=0;#1;
  if(!gv||l0!=1||r0!=11||l1!=2||r1!=12||l2!=3||r2!=13)$fatal(1,"audio group mismatch");
  ready=1;@(negedge clk);#1;if(gv||count!=0)$fatal(1,"audio group not released");$display("PASS audio sample group 3 stereo frames");$finish;end
 initial begin #10000;$fatal(1,"timeout");end
endmodule
