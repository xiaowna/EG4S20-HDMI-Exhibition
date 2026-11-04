`timescale 1ns/1ps
// Real SPI bytes, two input FFs, delayed Mode-0 card and independent CRC.
module fast_card_case #(parameter DIV=2)(output reg finished=0,
 output integer elapsed_cycles=0);
 reg clk=0,rst_n=0,read_start=0,card_miso=1;
 reg miso1=1,miso2=1;
 wire sd_sck,sd_mosi,sd_cs,ready,error,read_request_ready,read_busy,read_done,read_error,data_valid;
 wire [3:0] read_error_code;wire [8:0] data_addr;wire [7:0] data_out;
 always #10 clk=~clk;
 always @(posedge clk)begin miso1<=card_miso;miso2<=miso1;end
 sd_subsystem #(.READ_CLK_DIV(DIV)) dut(.clk(clk),.rst_n(rst_n),.sd_miso(miso2),
  .sd_sck(sd_sck),.sd_mosi(sd_mosi),.sd_cs(sd_cs),.ready(ready),.error(error),
  .read_start(read_start),.read_lba(32'h12345678),.read_request_ready(read_request_ready),
  .read_busy(read_busy),.read_done(read_done),.read_error(read_error),.read_error_code(read_error_code),
  .data_addr(data_addr),.data_out(data_out),.data_valid(data_valid));
 function [7:0] payload(input integer n);payload=(n^(n>>8)^8'ha5)&255;endfunction
 function [15:0] crc512;
  reg [15:0] c;reg [7:0] v;integer n,b;
  begin c=0;for(n=0;n<512;n=n+1)begin
   v=payload(n);for(b=7;b>=0;b=b-1)c=c[15]^v[b]?((c<<1)^16'h1021):(c<<1);
  end crc512=c;end
 endfunction
 localparam [15:0] GOLD_CRC=crc512();
 integer bit_count=0,command_count=0,phase=0,payload_index=0,delay_ns=14;
 integer received=0,clock_count=0,started_at=0,run;
 reg [7:0] tx_byte=255,rx_byte=0;reg corrupt_crc=0;
 reg [47:0] command_frame=0;
 always @(posedge clk)clock_count=clock_count+1;
 always @(negedge sd_cs)begin
  bit_count=0;command_count=0;phase=0;tx_byte=255;rx_byte=0;payload_index=0;command_frame=0;
 end
 always @(posedge sd_sck)if(!sd_cs)begin
  rx_byte={rx_byte[6:0],sd_mosi};
  if(bit_count==7)begin
   bit_count=0;
   case(phase)
    0:if(rx_byte==8'h51)begin command_frame=rx_byte;command_count=1;phase=1;end
    1:begin
     command_frame={command_frame[39:0],rx_byte};command_count=command_count+1;
     if(command_count==6)begin
      if(command_frame!==48'h511234567801)$fatal(1,"CMD17 frame/LBA mismatch %h",command_frame);
      tx_byte=0;phase=2;
     end
    end
    2:begin tx_byte=8'hfe;phase=3;end
    3:begin tx_byte=payload(0);phase=4;end
    4:if(payload_index==511)begin tx_byte=GOLD_CRC[15:8];phase=5;end
      else begin payload_index=payload_index+1;tx_byte=payload(payload_index);end
    5:begin tx_byte=GOLD_CRC[7:0]^(corrupt_crc?8'h01:8'h00);phase=6;end
    default:tx_byte=255;
   endcase
  end else bit_count=bit_count+1;
 end
 always @(negedge sd_sck)if(!sd_cs)begin
  #(delay_ns);card_miso=tx_byte[7-bit_count];
 end
 always @(posedge sd_cs)card_miso=1;
 always @(negedge clk)if(data_valid)begin
  if(data_addr!==received[8:0]||data_out!==payload(received))
   $fatal(1,"DIV=%0d delay=%0d payload address=%0d got=%h expected=%h",DIV,delay_ns,received,data_out,payload(received));
  received=received+1;
 end
 initial begin
  // Isolate data-transfer timing from initialization. Initialization is
  // covered separately; no card response or controller read is mocked here.
  force dut.ready=1'b1;force dut.init_error=1'b0;
  repeat(5)@(negedge clk);rst_n=1;repeat(5)@(negedge clk);
  for(run=0;run<4;run=run+1)begin
   delay_ns=(run==1)?25:((run==2)?39:14);corrupt_crc=(run==3);received=0;
   wait(read_request_ready);@(negedge clk);read_start=1;started_at=clock_count;
   @(negedge clk);read_start=0;wait(read_done);#1;
   if(received!=512||read_error!==corrupt_crc||read_error_code!==(corrupt_crc?4'd7:4'd0))
    $fatal(1,"DIV=%0d run=%0d bytes=%0d error=%b/%0d",DIV,run,received,read_error,read_error_code);
   if(run==0)elapsed_cycles=clock_count-started_at;
   repeat(10)@(negedge clk);
  end
  $display("PASS SPI sector DIV=%0d: 14/25/39 ns return delays, 1536 good payload bytes, bad CRC rejected; clocks=%0d",DIV,elapsed_cycles);
  finished=1;
 end
 initial begin #6000000;$fatal(1,"SPI sector timeout DIV=%0d",DIV);end
endmodule
module tb_fast_card;
 wire done2,done4;wire [31:0] cycles2,cycles4;
 fast_card_case #(.DIV(2)) fast(done2,cycles2);
 fast_card_case #(.DIV(4)) slow(done4,cycles4);
 initial begin
  wait(done2&&done4);
  if(cycles2*100>=cycles4*56)$fatal(1,"read speed improvement below 44 percent");
  $display("PASS sector benchmark: old6.25MHz=%0d new12.5MHz=%0d system clocks",cycles4,cycles2);
  $display("MODEL LIMIT: digital delays only, no analog IO/board/metastability model; hardware pending");
  $finish;
 end
endmodule
