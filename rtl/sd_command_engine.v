// R1 command transaction; optional 0..4 trailing response bytes (R7/R3).
// Each byte request is followed by an explicit completion wait. No block-data phase.
module sd_command_engine #(parameter integer BYTE_TIMEOUT_CYCLES=100_000, R1_BYTES=8)(
 input wire clk,input wire rst_n,input wire start,input wire [5:0] cmd,
 input wire [31:0] arg,input wire [7:0] crc,input wire [2:0] extra_bytes,
 input wire spi_busy,input wire spi_done,input wire [7:0] spi_rx,
 output reg spi_start,output reg [7:0] spi_tx,output reg busy,output reg done,
 output reg [7:0] response,output reg timeout,
 output reg [31:0] response_data,output reg sd_cs);
 localparam IDLE=0,ISSUE=1,WAIT_BYTE=2;
 localparam GAP=0,SELECTED=1,COMMAND=2,R1=3,EXTRA=4,RELEASE=5;
 reg [1:0] state;
 reg [2:0] phase,index,remaining;
 reg [47:0] frame;
 localparam integer TIMER_BITS=(BYTE_TIMEOUT_CYCLES>1)?$clog2(BYTE_TIMEOUT_CYCLES):1;
 localparam integer POLL_BITS=(R1_BYTES>1)?$clog2(R1_BYTES):1;
 reg [TIMER_BITS-1:0] timer;
 reg [POLL_BITS-1:0] polls;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE; phase<=GAP; index<=0; remaining<=0; frame<=0;
   timer<=0; polls<=0; spi_start<=0; spi_tx<=8'hff; busy<=0; done<=0;
   response<=8'hff; response_data<=0; timeout<=0; sd_cs<=1;
  end else begin
   spi_start<=0; done<=0;
   if(state!=IDLE && timer>=BYTE_TIMEOUT_CYCLES-1) begin
    state<=IDLE; sd_cs<=1; busy<=0; done<=1; timeout<=1;
   end else begin
    if(state!=IDLE) timer<=timer+1;
    case(state)
     IDLE: if(start) begin
      frame<={2'b01,cmd,arg,crc}; remaining<=extra_bytes;
      response<=8'hff; response_data<=0; timeout<=0;
      index<=0; polls<=0; timer<=0; sd_cs<=1; busy<=1; phase<=GAP; state<=ISSUE;
     end
     ISSUE: if(!spi_busy) begin
      spi_tx<=(phase==COMMAND)?frame[47:40]:8'hff;
      spi_start<=1; timer<=0; state<=WAIT_BYTE;
     end
     WAIT_BYTE: if(spi_done) begin
      timer<=0; state<=ISSUE;
      case(phase)
       GAP: begin sd_cs<=0; phase<=SELECTED; end
       SELECTED: phase<=COMMAND;
       COMMAND: if(index==5) phase<=R1;
                else begin index<=index+1'b1; frame<={frame[39:0],8'hff}; end
       R1: if(!spi_rx[7]) begin
        response<=spi_rx;
        if(remaining!=0 && spi_rx[6:1]==0) phase<=EXTRA;
        else begin sd_cs<=1; phase<=RELEASE; end
       end else if(polls==R1_BYTES-1) begin timeout<=1; sd_cs<=1; phase<=RELEASE; end
       else polls<=polls+1;
       EXTRA: begin
        response_data<={response_data[23:0],spi_rx}; remaining<=remaining-1'b1;
        if(remaining==1) begin sd_cs<=1; phase<=RELEASE; end
       end
       RELEASE: begin state<=IDLE; busy<=0; done<=1; end
       default: begin state<=IDLE; sd_cs<=1; busy<=0; done<=1; timeout<=1; end
      endcase
     end
     default: begin state<=IDLE; sd_cs<=1; busy<=0; done<=1; timeout<=1; end
    endcase
   end
  end
 end
endmodule
