`timescale 1ns/1ps
module tb_audio_async_fifo;
 reg wclk=0,rclk=0,wr_rst_n=0,rd_rst_n=0,wren=0,rden=0;always #5 wclk=~wclk;always #7 rclk=~rclk;
 reg [47:0] wd;wire full,empty;wire [47:0] rd;wire [8:0] rd_level,wr_level;
 audio_async_fifo dut(wclk,wr_rst_n,wren,wd,full,rclk,rd_rst_n,rden,rd,empty,rd_level,wr_level);
 integer i,wn=0,rn=0;reg [47:0] gold[0:99];
 always @(posedge wclk) if(wr_rst_n&&wren&&!full)begin gold[wn]={16'hA000+wn,16'hB000+wn,16'hC000+wn};wn=wn+1;end
 always @(posedge rclk) if(rd_rst_n&&rden&&!empty)begin #1;if(rd!==gold[rn])$fatal(1,"FIFO order mismatch %0d got=%h exp=%h",rn,rd,gold[rn]);rn=rn+1;end
 initial begin repeat(3)@(negedge wclk);wr_rst_n=1;repeat(2)@(negedge rclk);rd_rst_n=1;
  wait(!full);
  for(i=0;i<100;i=i+1)begin @(negedge wclk);wd={16'hA000+i,16'hB000+i,16'hC000+i};wren=1;end
  @(negedge wclk);wren=0;repeat(10)@(negedge rclk);rden=1;wait(rn==100);@(negedge rclk);rden=0;
  if(full||!empty)$fatal(1,"FIFO flags not empty");$display("PASS audio FIFO order=100");$finish;end
 initial begin #100000;$fatal(1,"timeout");end
endmodule

