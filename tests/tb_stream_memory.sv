`timescale 1ns/1ps
module tb_stream_memory;
 reg clk=0,rst=0,wv=0,bv=0;always #10 clk=~clk;
 reg [31:0] wa=0,wd=0,ba=0;reg [8:0] n=0;
 wire wr,dr,br,dv,last,err,fault,init;wire [31:0] data;
 integer i,k,count=0;reg checking=0;realtime began;
 eg4s20_stream_memory dut(clk,rst,wv,wa,wd,wr,dr,bv,ba,n,br,dv,last,data,err,fault,init);
 always @(posedge clk)if(checking&&dv)begin
  if(data!==32'h100000+ba+count || last!==(count==n-1))$fatal(1,"bad stream %h addr=%d count=%d",data,ba,count);
  count=count+1;
 end
 task read_block(input integer a,input integer len);
 begin
  @(negedge clk);ba=a;n=len;bv=1;count=0;checking=1;
  @(posedge clk);while(!br)@(posedge clk);@(negedge clk);bv=0;
  wait(count==len);@(negedge clk);checking=0;
 end endtask
 initial begin
  #13;rst=1;wait(init);
  for(i=0;i<256;i=i+1)begin
   @(negedge clk);wv=1;wa=i;wd=32'h100000+i;@(posedge clk);while(!wr)@(posedge clk);@(negedge clk);wv=0;
  end
  wait(dr);began=$realtime;
  for(k=0;k<8;k=k+1)read_block(k*32,32);
  $display("MEASURE pipelined SDRAM %0f Mword/s",256000.0/($realtime-began));
  if(256000.0/($realtime-began)<25)$fatal(1,"read bandwidth regression");
  read_block(251,5);read_block(255,1);
  @(negedge clk);ba=255;n=2;bv=1;@(posedge clk);while(!br)@(posedge clk);@(negedge clk);bv=0;wait(fault);
  $display("PASS stream memory: writes, 32-word reads, short tail, row rejection, bandwidth");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
