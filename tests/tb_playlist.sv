`timescale 1ns/1ps
module tb_playlist;
 reg clk=0,rst=0,card=0,lr=0,sd=0,id=0,err=0,next=0,pause=0;reg [2:0] count=0;
 wire ss,ls;wire [1:0] index;integer cycles=0;
 always #5 clk=~clk;
 media_playlist_control #(.INTERVAL_CYCLES(12)) dut(clk,rst,card,lr,sd,id,err,count,next,pause,ss,ls,index,1'b0);
 task scanned(input bad,input [2:0] n);begin wait(ss);@(negedge clk);err=bad;count=n;sd=1;@(negedge clk);sd=0;err=0;end endtask
 task finish_image;begin @(negedge clk);id=1;@(negedge clk);id=0;end endtask
 initial begin
  #12;rst=1;repeat(3)@(negedge clk);if(ss||ls)$fatal(1,"started without card");card=1;
  scanned(1,0);scanned(0,2);repeat(3)@(negedge clk);if(ls)$fatal(1,"ignored load readiness");lr=1;wait(ls);#1;if(index!=0)$fatal(1,"first index");
  pause=1;finish_image;repeat(20)begin @(negedge clk);if(ls)$fatal(1,"pause ignored");end
  next=1;@(negedge clk);next=0;wait(ls);#1;if(index!=1)$fatal(1,"manual next");
  // Next while loading is remembered and wraps after image completion.
  @(negedge clk);next=1;@(negedge clk);next=0;finish_image;wait(ls);#1;if(index!=0)$fatal(1,"pending next lost/wrap");
  finish_image;pause=0;wait(ls);#1;if(index!=1)$fatal(1,"auto advance");
  $display("PASS playlist: card wait, scan retry, load backpressure, pause, manual/pending next, wrap and autoplay");$finish;
 end
 initial begin #10000;$fatal(1,"timeout");end
endmodule
