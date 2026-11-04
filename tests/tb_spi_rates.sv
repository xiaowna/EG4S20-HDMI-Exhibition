`timescale 1ns/1ps
module tb_spi_rates;
 reg clk=0,rst=0,start=0,fast=0;reg [7:0] tx=0;
 wire [7:0] rx;wire busy,done,sck,mosi;
 always #10 clk=~clk;
 sd_spi_master #(.CLK_DIV(8),.READ_CLK_DIV(4)) dut(
  .clk(clk),.rst_n(rst),.start(start),.fast_mode(fast),.tx_data(tx),
  .rx_data(rx),.busy(busy),.done(done),.sd_sck(sck),.sd_mosi(mosi),.sd_miso(mosi));
 integer start_time,end_time,edges=0;
 always @(posedge sck) edges=edges+1;
 task send(input [7:0] value,input initial_fast,input switch_in_flight,input integer halfcycles);
 begin
  @(negedge clk);tx=value;fast=initial_fast;start=1;edges=0;
  @(posedge clk);start_time=$time;
  @(negedge clk);start=0;
  if(switch_in_flight)begin repeat(2)@(posedge sck);fast=!initial_fast;end
  wait(done);end_time=$time;#1;
  if(rx!==value || edges!=8 || busy || sck || end_time-start_time!=16*halfcycles*20)
   $fatal(1,"SPI mode=%b tx=%h rx=%h edges=%0d duration=%0d",initial_fast,value,rx,edges,end_time-start_time);
 end endtask
 initial begin
  #35;rst=1;
  send(8'h96,0,1,8);
  send(8'h5a,1,1,4);
  send(8'hff,0,0,8);
  send(8'h00,1,0,4);
  $display("PASS SPI: slow initialization, fast read, byte-boundary switching");$finish;
 end
 initial begin #200000;$fatal(1,"timeout");end
endmodule
