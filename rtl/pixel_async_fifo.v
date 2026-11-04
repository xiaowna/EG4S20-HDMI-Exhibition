// Dual-clock ready/valid FIFO. ADDR_BITS >= 2, depth = 2**ADDR_BITS.
// Common asynchronous reset; release synchronized separately in each domain.
// Synchronous dual-port RAM with two read-side prefetch stages presents the
// same show-ahead interface without requiring distributed RAM. Physical
// Gray-bus skew constraints are required during TD timing.
module pixel_async_fifo #(parameter WIDTH=57, ADDR_BITS=4)(
 input wire rst_n,wclk,rclk,
 input wire wvalid,input wire [WIDTH-1:0] wdata,output wire wready,output wire wempty,
 output wire rvalid,output wire [WIDTH-1:0] rdata,input wire rready,
 output wire [ADDR_BITS:0] w_free);
 reg [WIDTH-1:0] mem[0:(1<<ADDR_BITS)-1];
 reg [ADDR_BITS:0] wp,wg,rp,rg;
 (* async_reg="true" *) reg [ADDR_BITS:0] rg1,rg2,wg1,wg2;
 (* async_reg="true" *) reg [1:0] wrst,rrst;
 reg full;
 reg [ADDR_BITS:0] fetch_ptr;
 reg memory_valid,output_valid;
 reg [WIDTH-1:0] memory_data,output_data;
 wire push=wvalid&&wready,pop=rvalid&&rready;
 wire [ADDR_BITS:0] wn=wp+push,rn=rp+pop;
 wire [ADDR_BITS:0] wgn=(wn>>1)^wn,rgn=(rn>>1)^rn;
 function [ADDR_BITS:0] gray_to_binary;
  input [ADDR_BITS:0] g;integer k;
  begin gray_to_binary[ADDR_BITS]=g[ADDR_BITS];
   for(k=ADDR_BITS-1;k>=0;k=k-1)gray_to_binary[k]=gray_to_binary[k+1]^g[k];
  end
 endfunction
 wire [ADDR_BITS:0] used_words=wp-gray_to_binary(rg2);
 // Conservative capacity: remote reads become visible after synchronization.
 assign w_free=wrst[1]?((1<<ADDR_BITS)-used_words):0;
 assign wready=wrst[1]&&!full;
 assign wempty=wrst[1]&&(wg==rg2);
 assign rvalid=rrst[1]&&output_valid;
 assign rdata=output_data;
 wire [ADDR_BITS:0] fetch_gray=(fetch_ptr>>1)^fetch_ptr;
 wire move_to_output=memory_valid&&(!output_valid||pop);
 wire read_issue=rrst[1]&&(fetch_gray!=wg2)&&(!memory_valid||move_to_output);
 // Prefetch only copies words. The public read pointer advances on pop,
 // so w_free and wempty include all words held in either output stage.
 // RAM output registers deliberately have no reset, enabling BRAM inference.
 always @(posedge wclk)
  if(push)mem[wp[ADDR_BITS-1:0]]<=wdata;
 always @(posedge rclk)
  if(read_issue)memory_data<=mem[fetch_ptr[ADDR_BITS-1:0]];
 always @(posedge rclk)
  if(move_to_output)output_data<=memory_data;
 always @(posedge wclk or negedge rst_n)
  if(!rst_n)wrst<=0;else wrst<={wrst[0],1'b1};
 always @(posedge rclk or negedge rst_n)
  if(!rst_n)rrst<=0;else rrst<={rrst[0],1'b1};
 always @(posedge wclk or negedge rst_n)begin
  if(!rst_n)begin wp<=0;wg<=0;rg1<=0;rg2<=0;full<=0;end
  else if(!wrst[1])begin wp<=0;wg<=0;rg1<=0;rg2<=0;full<=0;end
  else begin
   rg1<=rg;rg2<=rg1;wp<=wn;wg<=wgn;
   full<=(wgn=={~rg2[ADDR_BITS:ADDR_BITS-1],rg2[ADDR_BITS-2:0]});
  end
 end
 always @(posedge rclk or negedge rst_n)begin
  if(!rst_n)begin
   rp<=0;rg<=0;wg1<=0;wg2<=0;fetch_ptr<=0;memory_valid<=0;output_valid<=0;
  end else if(!rrst[1])begin
   rp<=0;rg<=0;wg1<=0;wg2<=0;fetch_ptr<=0;memory_valid<=0;output_valid<=0;
  end else begin
   wg1<=wg;wg2<=wg1;rp<=rn;rg<=rgn;
   if(read_issue)fetch_ptr<=fetch_ptr+1'b1;
   if(read_issue)memory_valid<=1;
   else if(move_to_output)memory_valid<=0;
   if(move_to_output)output_valid<=1;
   else if(pop)output_valid<=0;
  end
 end
endmodule
