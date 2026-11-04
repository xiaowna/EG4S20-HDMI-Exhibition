// Burst prefetch interface, independent of the physical SDRAM controller.
// MAX_BURST <= FIFO depth and <=256. Each command stays within a 256-word row.
// Backend may return one word per sys_clk with no backpressure: reserve space
// BEFORE issue. First response must be after command handshake, not on it.
// burst_last marks exactly the last response. Any fault requires common reset.
module frame_burst_prefetch #(parameter FRAME_PIXELS=640*480,MAX_BURST=32,
 FIFO_ADDR_BITS=6,TIMEOUT_CYCLES=1000000)(
 input wire rst_n,sys_clk,pix_clk,start,input wire [31:0] frame_base,
 output wire start_ready,output reg busy,done,error,
 output wire burst_valid,output wire [31:0] burst_addr,output wire [8:0] burst_words,input wire burst_ready,
 input wire burst_data_valid,burst_last,burst_error,input wire [31:0] burst_data,
 output wire pixel_valid,output wire [31:0] pixel_addr,output wire [23:0] pixel_rgb,
 output wire pixel_last,input wire pixel_ready);
 localparam IDLE=0,PREP=1,ISSUE=2,RECEIVE=3,DRAIN=4;
 reg [2:0] state;reg [31:0] base,offset,timer,request_addr;reg [8:0] reserved,received;
 wire [FIFO_ADDR_BITS:0] free_words;wire fifo_ready,fifo_empty;wire [56:0] fifo_data;
 wire [31:0] absolute_addr=base+offset;
 wire [31:0] remain=FRAME_PIXELS-offset;
 wire [31:0] row_left=256-{24'b0,absolute_addr[7:0]};
 wire [31:0] limit1=(remain<MAX_BURST)?remain:MAX_BURST;
 wire [31:0] planned=(limit1<row_left)?limit1:row_left;
 wire bad_data=burst_data_valid && (state!=RECEIVE || !fifo_ready || burst_last!=(received==reserved-1));
 wire put=burst_data_valid && state==RECEIVE && !bad_data && !burst_error && !error;
 assign start_ready=state==IDLE && fifo_empty && !error;
 assign burst_valid=state==ISSUE && !error;
 // Hold the address from PREP through the ISSUE handshake. This also removes
 // the base+offset carry chain from the SDRAM half-cycle output path.
 assign burst_addr=request_addr;
 assign burst_words=reserved;
 assign {pixel_last,pixel_addr,pixel_rgb}=fifo_data;
 pixel_async_fifo #(.WIDTH(57),.ADDR_BITS(FIFO_ADDR_BITS)) u_fifo(
 .rst_n(rst_n),.wclk(sys_clk),.rclk(pix_clk),.wvalid(put),
 .wdata({(offset+received==FRAME_PIXELS-1),(offset+{23'b0,received}),burst_data[23:0]}),
 .wready(fifo_ready),.wempty(fifo_empty),.w_free(free_words),.rvalid(pixel_valid),.rdata(fifo_data),.rready(pixel_ready));
 always @(posedge sys_clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;base<=0;offset<=0;request_addr<=0;reserved<=0;received<=0;timer<=0;busy<=0;done<=0;error<=0;end
  else begin
   done<=0;
   if(!error)begin
    if(burst_error||bad_data)begin error<=1;busy<=0;end
    else case(state)
     IDLE:if(start&&start_ready)begin
      if({32'b0,frame_base}+FRAME_PIXELS>64'd2097152)error<=1;
      else begin base<=frame_base;offset<=0;busy<=1;state<=PREP;end
     end
     PREP:if(free_words>=planned)begin request_addr<=absolute_addr;reserved<=planned;received<=0;timer<=0;state<=ISSUE;end
     ISSUE:if(burst_ready)begin timer<=0;state<=RECEIVE;end
           else if(timer>=TIMEOUT_CYCLES-1)begin error<=1;busy<=0;end else timer<=timer+1'b1;
     RECEIVE:if(put)begin
      timer<=0;
      if(burst_last)begin offset<=offset+reserved;state<=(offset+reserved==FRAME_PIXELS)?DRAIN:PREP;end
      else received<=received+1'b1;
     end else if(timer>=TIMEOUT_CYCLES-1)begin error<=1;busy<=0;end else timer<=timer+1'b1;
     DRAIN:if(fifo_empty)begin done<=1;busy<=0;state<=IDLE;end
     default:begin error<=1;busy<=0;end
    endcase
   end
  end
 end
endmodule
