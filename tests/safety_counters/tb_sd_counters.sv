`timescale 1ns/1ps
// Byte-completion model; independent of DUT state/phase registers.
module safety_spi_model #(parameter KIND=0)(
 input wire clk,rst_n,start,cs,input wire [7:0] tx,input wire [3:0] mode,
 output reg busy,done,output reg [7:0] rx);
 initial begin busy=0;done=0;rx=8'hff;end
 integer index=0,delay_left=0,command_bytes=0,command=0,response_pos=0,acmds=0,cmd0s=0;
 reg [7:0] reply;
 function [15:0] crc512;
  integer i,b;reg [15:0] c;reg [7:0] d;
  begin
   c=0;
   for(i=0;i<512;i=i+1)begin
    d=(i*29+7)&255;
    for(b=7;b>=0;b=b-1)c=c[15]^d[b]?{c[14:0],1'b0}^16'h1021:{c[14:0],1'b0};
   end
   crc512=c;
  end
 endfunction
 localparam [15:0] CRC=crc512();
 always @(negedge clk)begin
  done=0;
  if(!rst_n)begin
   busy=0;rx=8'hff;index=0;delay_left=0;command_bytes=0;
   command=0;response_pos=0;acmds=0;cmd0s=0;
  end else if(busy)begin
   if(mode!=6)begin
    if(delay_left==0)begin busy=0;done=1;end
    else delay_left=delay_left-1;
   end
  end else if(start)begin
   busy=1;delay_left=1;reply=8'hff;
   if(KIND==0)begin
    if(index==8)reply=(mode==2)?8'h04:(mode==3)?8'hff:0;
    if(index>8 && mode==3)reply=8'hff;
    else if(index==9)reply=(mode==4)?8'hff:(mode==5)?8'h0b:8'hfe;
    else if(index>9 && mode==4)reply=8'hff;
    else if(index>=10 && index<522)reply=((index-10)*29+7)&255;
    else if(index==522)reply=CRC[15:8];
    else if(index==523)reply=CRC[7:0]^((mode==1)?8'h01:8'h00);
   end else if(KIND==1)begin
    if(index==8)reply=(mode==1)?8'hff:(mode==2)?8'h04:0;
    if(mode==1 && index>=8)reply=8'hff;
    else case(index)
     9:reply=8'h12;10:reply=8'h34;11:reply=8'h56;12:reply=8'h78;
    endcase
   end else begin
    if(cs)begin command_bytes=0;response_pos=0;end
    else if(command_bytes==0)begin
     if(tx[7:6]==2'b01)begin
      command=tx[5:0];command_bytes=1;response_pos=0;
      if(tx[5:0]==0)cmd0s=cmd0s+1;
      if(tx[5:0]==41)acmds=acmds+1;
     end
    end else if(command_bytes<6)command_bytes=command_bytes+1;
    else begin
     if(response_pos==0)begin
      case(command)
       0:reply=(mode==2 && cmd0s<=2)?8'hff:8'h01;
       8:reply=8'h01;
       55:reply=(mode==5)?8'h04:8'h01;
       41:reply=(mode==4 || acmds<=2)?8'h01:0;
       58:reply=0;
      endcase
      // Keep polling CMD0 until its configured retry transaction ends.
      if(!(command==0 && mode==2 && cmd0s<=2))response_pos=1;
     end else begin
      if(command==8)case(response_pos)
       1,2:reply=0;3:reply=1;4:reply=(mode==1)?8'hab:8'haa;
      endcase
      if(command==58)case(response_pos)
       1:reply=(mode==3)?8'h80:8'hc0;2:reply=8'h30;3,4:reply=0;
      endcase
      response_pos=response_pos+1;
     end
    end
   end
   rx=reply;index=index+1;
  end
 end
endmodule

module tb_sd_counters;
 parameter integer LIMIT=8;
 reg clk=0,rst_n=1,start=0;
 reg [3:0] mode=0;
 always #5 clk=~clk;
 wire [2:0] spi_start,cs,busy,spi_done;
 wire [7:0] tx[0:2],rx[0:2];
 wire data_done,data_error,command_done,command_timeout,init_ready,init_error;
 wire [3:0] data_error_code;
 wire [7:0] command_response;
 wire [31:0] response_data;
 integer i,ticks,cases=0;
 reg data_seen,command_seen;
 sd_data_block_reader #(.TIMEOUT_CYCLES(20000),.BYTE_TIMEOUT_CYCLES(LIMIT),
  .TOKEN_TIMEOUT_CYCLES(LIMIT),.R1_MAX_BYTES(LIMIT)) reader(
  .clk(clk),.rst_n(rst_n),.start(start),.lba(32'h87654321),
  .spi_busy(busy[0]),.spi_done(spi_done[0]),.spi_rx(rx[0]),
  .spi_start(spi_start[0]),.spi_tx(tx[0]),.sd_cs(cs[0]),.busy(),.done(data_done),
  .error(data_error),.data_addr(),.data_out(),.data_valid(),.error_code(data_error_code));
 sd_command_engine #(.BYTE_TIMEOUT_CYCLES(LIMIT),.R1_BYTES(LIMIT)) engine(
  .clk(clk),.rst_n(rst_n),.start(start),.cmd(6'd8),.arg(32'h12345678),.crc(8'h87),
  .extra_bytes(3'd4),.spi_busy(busy[1]),.spi_done(spi_done[1]),.spi_rx(rx[1]),
  .spi_start(spi_start[1]),.spi_tx(tx[1]),.busy(),.done(command_done),
  .response(command_response),.timeout(command_timeout),.response_data(response_data),.sd_cs(cs[1]));
 sd_init_controller #(.CLK_HZ(50000000),.POWER_WAIT_CYCLES(LIMIT),
  .RETRY_WAIT_CYCLES(LIMIT+1),.INIT_TIMEOUT_CYCLES(200000),
  .BYTE_TIMEOUT_CYCLES(LIMIT),.MAX_ACMD41(LIMIT)) initializer(
  .clk(clk),.rst_n(rst_n),.spi_busy(busy[2]),.spi_done(spi_done[2]),.spi_rx(rx[2]),
  .spi_start(spi_start[2]),.spi_tx(tx[2]),.sd_cs(cs[2]),.ready(init_ready),.error(init_error));
 genvar k;
 generate for(k=0;k<3;k=k+1)begin: models
  safety_spi_model #(.KIND(k)) spi(.clk(clk),.rst_n(rst_n),.start(spi_start[k]),
   .cs(cs[k]),.tx(tx[k]),.mode(mode),.busy(busy[k]),.done(spi_done[k]),.rx(rx[k]));
 end endgenerate
 initial begin
  for(i=0;i<8;i=i+1)begin
   #1;rst_n=0;start=0;mode=i;repeat(4)@(negedge clk);#2;rst_n=1;
   repeat(2)@(negedge clk);#2;start=1;@(negedge clk);#2;start=0;
   ticks=0;data_seen=0;command_seen=0;
   while((!data_seen || !command_seen || (!init_ready&&!init_error)) && ticks<220000)begin
    @(negedge clk);#2;ticks=ticks+1;
    if(data_done)data_seen=1;
    if(command_done)command_seen=1;
    if(i==7 && ticks==100)begin rst_n=0;repeat(3)@(negedge clk);#2;rst_n=1;data_seen=1;command_seen=1;end
   end
   if(ticks>=220000)$fatal(1,"SD completion bound LIMIT=%0d mode=%0d",LIMIT,i);
   if(LIMIT>=8 && i==0 && (data_error || command_timeout || command_response!=0 ||
      response_data!=32'h12345678 || !init_ready))
    $fatal(1,"independent successful SD transaction failed LIMIT=%0d",LIMIT);
   if(LIMIT>=8 && i==1 && (!data_error || data_error_code!=7 || !command_timeout || !init_error))
    $fatal(1,"CRC/R1/CMD8 corruption was not rejected");
   if(LIMIT>=8 && i==2 && (!data_error || data_error_code!=1 || !init_ready))
    $fatal(1,"R1 rejection or CMD0 retries failed");
   if(LIMIT>=8 && i==3 && (!data_error || data_error_code!=2 || !init_error))
    $fatal(1,"R1 polling or OCR voltage checks failed");
   if(LIMIT>=8 && i==4 && (!data_error || data_error_code!=3 || !init_error))
    $fatal(1,"token timeout or ACMD41 retry limit failed");
   if(LIMIT>=8 && i==5 && (!data_error || data_error_code!=4 || !init_error))
    $fatal(1,"invalid data token or CMD55 error failed");
   if(LIMIT>=8 && i==6 && (!data_error || data_error_code!=5 || !command_timeout || !init_error))
    $fatal(1,"byte/global watchdogs did not expire");
   cases=cases+1;
  end
  $display("PASS safety SD LIMIT=%0d cases=%0d: successful CRC/data/R7/OCR, bad CRC/R1/token/CMD8/OCR, CMD0/ACMD41 retry and watchdog/reset",LIMIT,cases);
  $finish;
 end
 initial begin #100000000;$fatal(1,"SD counter regression timeout");end
endmodule
