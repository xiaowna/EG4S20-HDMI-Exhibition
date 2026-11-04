`timescale 1ns/1ps
module tb_audio_flush;
 reg sys_clk=0,pix_clk=0,rst_n=1,request=0,safe_to_flush=0;
 reg run_write=0,run_read=0;
 wire flush_done,fifo_rst_n,block_reads,flush_hold_pix;
 wire full,empty;wire [47:0] data;
 wire [3:0] wr_level,rd_level;
 integer generation=0,sequence_id=0,head=0,tail=0,reads=0,writes=0,cases=0,k;
 reg [47:0] expected[0:65535];
 wire [47:0] write_data={generation[15:0],sequence_id[31:0]};
 wire write_en=run_write&&!request&&!flush_done;
 wire read_en=run_read&&!block_reads;
 always #5 sys_clk=~sys_clk;
 always #7 pix_clk=~pix_clk;
 audio_source_flush dut(.*);
 audio_async_fifo #(.ADDR_BITS(3)) fifo(.wr_clk(sys_clk),.wr_rst_n(fifo_rst_n),
  .wr_en(write_en),.wr_data(write_data),.wr_full(full),.rd_clk(pix_clk),.rd_rst_n(fifo_rst_n),
  .rd_en(read_en),.rd_data(data),.rd_empty(empty),.rd_level(rd_level),.wr_level(wr_level));
 always @(negedge fifo_rst_n)begin head=0;tail=0;end
 always @(posedge sys_clk)if(fifo_rst_n&&write_en&&!full)begin
  expected[tail]=write_data;tail=tail+1;sequence_id<=sequence_id+1;writes=writes+1;
 end
 always @(posedge pix_clk)if(fifo_rst_n&&read_en&&!empty)begin
  if(head>=tail)$fatal(1,"unexpected FIFO read");
  #1;if(data!==expected[head] || data[47:32]!==generation[15:0])$fatal(1,"source FIFO mismatch expected=%h actual=%h generation=%0d",expected[head],data,generation);
  head=head+1;reads=reads+1;
 end
 task sys_ticks(input integer n);begin repeat(n)@(negedge sys_clk);#1;end endtask
 initial begin
  #1;rst_n=0;sys_ticks(4);rst_n=1;sys_ticks(20);run_write=1;
  for(k=0;k<17;k=k+1)begin
   run_read=1;sys_ticks(20);run_read=0;sys_ticks(30);
   #(k%4+1);request=1;safe_to_flush=0;sys_ticks(20);
   if(flush_done || !fifo_rst_n || !block_reads)$fatal(1,"flush ignored safe packet boundary");
   safe_to_flush=1;wait(flush_done);#1;
   if(fifo_rst_n || !full || !empty || wr_level!=0 || rd_level!=0)$fatal(1,"FIFO not reset at acknowledgement");
   generation=generation+1;sys_ticks(4);request=0;
   wait(!flush_done);#1;
   if(!fifo_rst_n || full || !empty)$fatal(1,"FIFO release did not complete");
   sys_ticks(10);
   cases=cases+1;
  end
  run_read=1;sys_ticks(40);run_write=0;sys_ticks(50);
  if(!empty || reads<100)$fatal(1,"post-flush stream did not drain");
  $display("PASS audio_flush: %0d asynchronous phases, safe-boundary hold, both FIFO domains, source tags, writes=%0d reads=%0d",cases,writes,reads);$finish;
 end
 initial begin #1000000;$fatal(1,"audio flush timeout");end
endmodule
