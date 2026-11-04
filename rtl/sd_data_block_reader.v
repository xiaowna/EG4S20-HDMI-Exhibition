// SDHC/SDXC CMD17 reader, sector addressing, one clock domain.
// start: one-cycle pulse while !busy and !spi_busy; lba is latched.
// data_valid is provisional: commit the block only after done && !error.
// No payload backpressure; receiver must accept every data_valid pulse.
module sd_data_block_reader #(
 parameter integer TIMEOUT_CYCLES=50_000_000,
 parameter integer BYTE_TIMEOUT_CYCLES=100_000,
 parameter integer TOKEN_TIMEOUT_CYCLES=12_500_000,
 parameter integer R1_MAX_BYTES=8)(
 input wire clk,input wire rst_n,input wire start,input wire [31:0] lba,
 input wire spi_busy,input wire spi_done,input wire [7:0] spi_rx,
 output reg spi_start,output reg [7:0] spi_tx,output reg sd_cs,
 output reg busy,output reg done,output reg error,
 output reg [8:0] data_addr,output reg [7:0] data_out,output reg data_valid,
 output reg [3:0] error_code);
 localparam IDLE=0,ISSUE=1,WAIT_BYTE=2;
 localparam GAP=0,SELECT_CARD=1,COMMAND=2,R1=3,TOKEN=4,
            PAYLOAD=5,CRC_HIGH=6,CRC_LOW=7,RELEASE=8;
 // error_code: 0 success, 1 R1 error, 2 R1 timeout, 3 token timeout,
 // 4 invalid/error token, 5 SPI stall, 6 transaction timeout, 7 CRC mismatch.
 reg [1:0] state;
 reg [3:0] phase;
 reg [2:0] command_index;
 reg [8:0] payload_index;
 reg [47:0] frame;
 reg [15:0] crc;
 reg [7:0] received_crc_high;
 // Include TOKEN_TIMEOUT_CYCLES itself: that counter saturates at the limit.
 localparam integer TOTAL_BITS=(TIMEOUT_CYCLES>1)?$clog2(TIMEOUT_CYCLES):1;
 localparam integer BYTE_BITS=(BYTE_TIMEOUT_CYCLES>1)?$clog2(BYTE_TIMEOUT_CYCLES):1;
 localparam integer TOKEN_BITS=(TOKEN_TIMEOUT_CYCLES>0)?$clog2(TOKEN_TIMEOUT_CYCLES+1):1;
 localparam integer R1_BITS=(R1_MAX_BYTES>1)?$clog2(R1_MAX_BYTES):1;
 reg [TOTAL_BITS-1:0] total_timer;
 reg [BYTE_BITS-1:0] byte_timer;
 reg [TOKEN_BITS-1:0] token_timer;
 reg [R1_BITS-1:0] r1_count;
 function [15:0] crc16_byte;
  input [15:0] prior;
  input [7:0] value;
  reg [15:0] c;
  integer b;
  begin
   c=prior;
   for(b=7;b>=0;b=b-1)
    if(c[15]^value[b]) c={c[14:0],1'b0}^16'h1021;
    else c={c[14:0],1'b0};
   crc16_byte=c;
  end
 endfunction
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE; phase<=GAP; command_index<=0; payload_index<=0; frame<=0;
   crc<=0; received_crc_high<=0; total_timer<=0; byte_timer<=0; token_timer<=0; r1_count<=0;
   spi_start<=0; spi_tx<=8'hff; sd_cs<=1; busy<=0; done<=0; error<=0; error_code<=0;
   data_addr<=0; data_out<=0; data_valid<=0;
  end else begin
   spi_start<=0; done<=0; data_valid<=0;
   // Watchdogs have priority over normal transitions, including SPI completion.
   if(state!=IDLE && (total_timer>=TIMEOUT_CYCLES-1 || byte_timer>=BYTE_TIMEOUT_CYCLES-1)) begin
    state<=IDLE; sd_cs<=1; busy<=0; done<=1; error<=1;
    error_code<=(byte_timer>=BYTE_TIMEOUT_CYCLES-1)?4'd5:4'd6;
   end else begin
    if(state!=IDLE) begin total_timer<=total_timer+1; byte_timer<=byte_timer+1; end
    if(phase==TOKEN && token_timer<TOKEN_TIMEOUT_CYCLES) token_timer<=token_timer+1;
    case(state)
     IDLE: if(start && !spi_busy) begin
      frame<={8'h51,lba,8'h01}; command_index<=0; payload_index<=0;
      crc<=0; total_timer<=0; byte_timer<=0; token_timer<=0; r1_count<=0;
      error<=0; error_code<=0; busy<=1; sd_cs<=1; phase<=GAP; state<=ISSUE;
     end
     ISSUE: if(!spi_busy) begin
      spi_start<=1; spi_tx<=(phase==COMMAND)?frame[47:40]:8'hff;
      byte_timer<=0; state<=WAIT_BYTE;
     end
     WAIT_BYTE: if(spi_done) begin
      byte_timer<=0; state<=ISSUE;
      case(phase)
       GAP: begin sd_cs<=0; phase<=SELECT_CARD; end
       SELECT_CARD: phase<=COMMAND;
       COMMAND: if(command_index==5) phase<=R1;
                else begin frame<={frame[39:0],8'hff}; command_index<=command_index+1'b1; end
       R1: if(!spi_rx[7]) begin
        if(spi_rx==0) begin phase<=TOKEN; token_timer<=0; end
        else begin error<=1; error_code<=1; sd_cs<=1; phase<=RELEASE; end
       end else if(r1_count==R1_MAX_BYTES-1) begin
        error<=1; error_code<=2; sd_cs<=1; phase<=RELEASE;
       end else r1_count<=r1_count+1;
       TOKEN: if(spi_rx==8'hfe) phase<=PAYLOAD;
              else if(spi_rx!=8'hff) begin error<=1; error_code<=4; sd_cs<=1; phase<=RELEASE; end
              else if(token_timer>=TOKEN_TIMEOUT_CYCLES-1) begin
               error<=1; error_code<=3; sd_cs<=1; phase<=RELEASE;
              end
       PAYLOAD: begin
        data_addr<=payload_index; data_out<=spi_rx; data_valid<=1;
        crc<=crc16_byte(crc,spi_rx);
        if(payload_index==511) phase<=CRC_HIGH;
        else payload_index<=payload_index+1'b1;
       end
       CRC_HIGH: begin received_crc_high<=spi_rx; phase<=CRC_LOW; end
       CRC_LOW: begin
        if({received_crc_high,spi_rx}!=crc) begin error<=1; error_code<=7; end
        sd_cs<=1; phase<=RELEASE;
       end
       RELEASE: begin busy<=0; done<=1; state<=IDLE; end
       default: begin error<=1; error_code<=6; sd_cs<=1; busy<=0; done<=1; state<=IDLE; end
      endcase
     end
     default: begin error<=1; error_code<=6; sd_cs<=1; busy<=0; done<=1; state<=IDLE; end
    endcase
   end
  end
 end
endmodule
