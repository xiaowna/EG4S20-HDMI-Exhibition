`timescale 1ns/1ps
// Black-box FIFO contract checks. The reference queue never uses DUT pointers,
// RAM, prefetch state, or implementation-specific latency.
module tb_pixel_fifo;
 parameter WIDTH=57, ADDR_BITS=8, W_HALF=5, R_HALF=7, R_PHASE=1, RANDOM_SEED=1;
 localparam DEPTH=1<<ADDR_BITS, MAX_ITEMS=100000;
 localparam OFF=0, ALWAYS=1, RANDOM=2;
 reg rst_n=1, wc=0, rc=0, run_read=1;
 always #(W_HALF) wc=~wc;
 initial begin #(R_PHASE); forever begin #(R_HALF); if(run_read)rc=~rc;end end
 reg wvalid=0,rready=0;
 reg [WIDTH-1:0] wdata=0;
 wire wready,wempty,rvalid;
 wire [WIDTH-1:0] rdata;
 wire [ADDR_BITS:0] w_free;
 pixel_async_fifo #(.WIDTH(WIDTH),.ADDR_BITS(ADDR_BITS)) dut(
  .rst_n(rst_n),.wclk(wc),.rclk(rc),.wvalid(wvalid),.wdata(wdata),
  .wready(wready),.wempty(wempty),.rvalid(rvalid),.rdata(rdata),
  .rready(rready),.w_free(w_free));
 reg [WIDTH-1:0] reference_queue[0:MAX_ITEMS-1];
 integer head=0,tail=0,total_reads=0,epoch=0;
 integer write_mode=OFF,read_mode=OFF,write_limit=0;
 reg [31:0] write_random=32'h64d763e1^RANDOM_SEED;
 reg [31:0] read_random=32'ha43972f3^RANDOM_SEED;
 reg stalled=0,require_continuous=0;
 reg [WIDTH-1:0] held_data;
 function [31:0] next_random(input [31:0] value);
  reg [31:0] x;
  begin x=value^(value<<13);x=x^(x>>17);next_random=x^(x<<5);end
 endfunction
 function [WIDTH-1:0] item_data(input integer index,input integer generation);
  integer bit_index; reg [31:0] x;
  begin
   x=32'h197b35d1^(index*32'h9e3779b9)^(generation*32'h45d9f3b);
   for(bit_index=0;bit_index<WIDTH;bit_index=bit_index+1)begin
    if(bit_index%32==0)x=next_random(x);
    item_data[bit_index]=x[bit_index%32];
   end
  end
 endfunction
 // Drive only on falling edges. Queue operations use accepted handshakes;
 // clock-domain assertions wait one picosecond for both edges and NBA updates.
 always @(negedge wc)begin
  write_random=next_random(write_random);
  if(!rst_n || write_mode==OFF || tail>=write_limit)wvalid=0;
  else if(!wvalid || wready)begin
   wvalid=write_mode==ALWAYS || write_random[2:0]!=0;
   wdata=item_data(tail,epoch);
  end
 end
 always @(negedge rc)begin
  read_random=next_random(read_random);
  rready=rst_n && (read_mode==ALWAYS || (read_mode==RANDOM && read_random[2:0]<5));
 end
 always @(posedge wc)begin
  if(rst_n && wvalid && wready)begin
   if(tail-head>=DEPTH)$fatal(1,"accepted beyond advertised capacity: %0d",tail-head);
   if(tail>=MAX_ITEMS)$fatal(1,"reference queue too small");
   reference_queue[tail]=wdata;tail=tail+1;
  end
  #0.001;
  if(rst_n)begin
   if(w_free>DEPTH || w_free>DEPTH-(tail-head))
    $fatal(1,"nonconservative free count: reported=%0d real=%0d",w_free,DEPTH-(tail-head));
   if(wempty && tail!=head)$fatal(1,"wempty asserted before external consumption: queued=%0d",tail-head);
  end else if(wready || rvalid || wempty || w_free!=0)$fatal(1,"reset did not block interfaces");
 end
 always @(posedge rc)begin
  if(!rst_n)stalled=0;
  else begin
   if(stalled && (!rvalid || rdata!==held_data))$fatal(1,"output changed while backpressured");
   if(require_continuous && head<tail && !rvalid)$fatal(1,"bubble during prefilled continuous drain");
   if(rvalid && rready)begin
    if(head>=tail)$fatal(1,"unexpected or duplicate output");
    if(rdata!==reference_queue[head])$fatal(1,"order/data mismatch item=%0d expected=%h got=%h",head,reference_queue[head],rdata);
    head=head+1;total_reads=total_reads+1;
   end
   stalled=rvalid&&!rready;held_data=rdata;
  end
 end
 task settle;
  begin repeat(12)@(negedge wc);repeat(12)@(negedge rc);#0.001;end
 endtask
 task reset_fifo;
  begin
   write_mode=OFF;read_mode=OFF;require_continuous=0;
   @(negedge wc);rst_n=0;wvalid=0;rready=0;
   #0.001;
   if(wready || rvalid || wempty || w_free!=0)$fatal(1,"asynchronous reset contract");
   head=0;tail=0;epoch=epoch+1;stalled=0;
   repeat(4)@(negedge wc);rst_n=1;settle;
   if(!wready || !wempty || rvalid || w_free!=DEPTH)$fatal(1,"empty reset state");
  end
 endtask
 task push_count(input integer count);
  begin
   write_limit=tail+count;write_mode=ALWAYS;
   wait(tail==write_limit);@(negedge wc);write_mode=OFF;wvalid=0;
  end
 endtask
 task drain_all;
  begin
   read_mode=ALWAYS;wait(head==tail);@(negedge rc);read_mode=OFF;rready=0;
   require_continuous=0;settle;
   if(rvalid || !wempty || !wready || w_free!=DEPTH)$fatal(1,"drain did not retire all words");
  end
 endtask
 integer target;
 initial begin
  // Explicit falling reset edge avoids time-zero initialization assumptions.
  #2;reset_fifo;
  // Empty reads must be ignored. Exact capacity stays DEPTH, even with prefetch.
  read_mode=ALWAYS;settle;read_mode=OFF;@(negedge rc);rready=0;
  if(head!=0)$fatal(1,"read from empty accepted");
  push_count(DEPTH);settle;
  if(wready || w_free!=0 || !rvalid || wempty)$fatal(1,"full boundary contract");
  write_limit=tail+1;write_mode=ALWAYS;settle;
  if(tail!=DEPTH)$fatal(1,"overflow write accepted");
  write_mode=OFF;@(negedge wc);wvalid=0;
  require_continuous=1;drain_all;
  // A final prefetched word may be held arbitrarily long, and must still occupy
  // capacity and prevent producer-side empty / end-of-frame acknowledgement.
  push_count(1);settle;
  if(!rvalid || wempty || w_free!=DEPTH-1)$fatal(1,"single held word not counted");
  repeat(30)@(negedge wc);
  if(wempty || w_free!=DEPTH-1)$fatal(1,"held last word retired too early");
  drain_all;
  // Independently randomized asynchronous producer and consumer, many wraps.
  target=tail+DEPTH*30+173;write_limit=target;
  write_mode=RANDOM;read_mode=RANDOM;
  wait(tail==target);@(negedge wc);write_mode=OFF;wvalid=0;drain_all;
  // Reset discards buffered data; following generations must never leak stale RAM.
  push_count(DEPTH/2);settle;reset_fifo;push_count(DEPTH);settle;
  require_continuous=1;drain_all;
  // Common reset while the read clock is stopped must not expose stale output.
  push_count(DEPTH/2);settle;
  @(negedge rc);run_read=0;read_mode=OFF;rready=0;
  @(negedge wc);rst_n=0;wvalid=0;write_mode=OFF;
  #0.001;if(wready || rvalid || wempty || w_free!=0)$fatal(1,"stopped read clock reset");
  head=0;tail=0;epoch=epoch+1;stalled=0;
  repeat(4)@(negedge wc);rst_n=1;
  repeat(12)@(negedge wc);
  if(rvalid)$fatal(1,"read interface released without read clock");
  push_count(DEPTH/2);
  run_read=1;settle;drain_all;
  $display("PASS pixel FIFO WIDTH=%0d DEPTH=%0d clocks=%0d/%0d read_phase=%0d seed=%0d reads=%0d: exact capacity, conservative free, last-word stall, stability, full-rate drain, randomized wrap, reset/stopped clock",WIDTH,DEPTH,2*W_HALF,2*R_HALF,R_PHASE,RANDOM_SEED,total_reads);
  $finish;
 end
 initial begin #20000000;$fatal(1,"timeout head=%0d tail=%0d free=%0d",head,tail,w_free);end
endmodule
