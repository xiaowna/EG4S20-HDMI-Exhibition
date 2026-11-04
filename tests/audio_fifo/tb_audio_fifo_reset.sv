`timescale 1ns/1ps
module tb_audio_fifo_reset;
 parameter ADDR_BITS=3;
 localparam DEPTH=1<<ADDR_BITS;
 reg wc=0,rc=0,run_read=1;
 always #5 wc=~wc;
 always #7 if(run_read) rc=~rc;
 reg wn=0,rn=0,we=0,re=0;
 reg [47:0] wd=0;
 wire full,empty;wire [47:0] rd;wire [ADDR_BITS:0] rd_level,wr_level;
 audio_async_fifo #(.ADDR_BITS(ADDR_BITS)) dut(wc,wn,we,wd,full,rc,rn,re,rd,empty,rd_level,wr_level);
 reg [47:0] expected[0:20000];integer head=0,tail=0,total=0;
 always @(posedge wc) if(wn&&rn&&we&&!full)begin
  expected[tail]=wd;tail=tail+1;
 end
 always @(posedge rc) if(wn&&rn&&re&&!empty)begin
  if(head>=tail)$fatal(1,"unexpected read");
  #1;if(rd!==expected[head])$fatal(1,"order mismatch index=%0d",head);
  head=head+1;total=total+1;
 end
 task settle;begin repeat(6)@(negedge wc);repeat(6)@(negedge rc);end endtask
 task push(input integer count);integer k;begin
  for(k=0;k<count;k=k+1)begin
   @(negedge wc);while(full)@(negedge wc);
   wd=48'hA12300000000+tail;we=1;
  end
  @(negedge wc);we=0;
 end endtask
 task drain;begin
  @(negedge rc);re=1;wait(head==tail);
  @(negedge rc);re=0;settle;
  if(!empty)$fatal(1,"not empty after drain");
 end endtask
 task flush(input integer side);begin
  @(negedge wc);we=0;re=0;
  if(side==0)wn=0;else rn=0;
  #2;if(!full||!empty)$fatal(1,"reset must block both interfaces");
  head=0;tail=0;
  repeat(4)@(negedge wc);
  wn=1;rn=1;settle;
  if(full||!empty)$fatal(1,"reset did not clear FIFO");
 end endtask
 initial begin
  // Hold reset until both clock domains have observed it.
  repeat(4)@(negedge wc);repeat(4)@(negedge rc);wn=1;rn=1;settle;
  // Full/overflow rejection and empty/underflow rejection.
  push(DEPTH);settle;if(!full||rd_level!=DEPTH||wr_level!=DEPTH)
   $fatal(1,"full occupancy mismatch");
  @(negedge wc);we=1;wd=48'hBAD;repeat(8)@(negedge wc);we=0;
  if(tail!=DEPTH)$fatal(1,"overflow accepted");drain;
  @(negedge rc);re=1;repeat(8)@(negedge rc);re=0;
  if(head!=DEPTH||rd_level!=0)$fatal(1,"underflow accepted or occupancy nonzero");
  // Concurrent traffic crosses pointer wrap repeatedly.
  @(negedge rc);re=1;push(DEPTH*6);drain;
  // Either reset input clears buffered samples, then new traffic works.
  push(DEPTH/2);flush(0);push(3);drain;
  push(DEPTH/2);flush(1);push(3);drain;
  // Reset while read clock is stopped; never accept reads on restart early.
  @(negedge rc);run_read=0;rn=0;#2;
  if(!empty||!full)$fatal(1,"stopped clock reset");
  head=0;tail=0;repeat(4)@(negedge wc);rn=1;
  repeat(6)@(negedge wc);if(!empty)$fatal(1,"early read release");
  push(3);run_read=1;settle;drain;
  $display("PASS FIFO depth=%0d: full/empty, wrap, concurrent transfers, either-side reset, stopped read clock; reads=%0d",DEPTH,total);
  $finish;
 end
 initial begin #2000000;$fatal(1,"timeout");end
endmodule
