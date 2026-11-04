`timescale 1ns/1ps
// 覆盖双帧地址末端、换帧和高位越界，防止地址缩位后发生回绕写入。
module tb_frame_address_bounds;
 parameter integer PIXELS=640*480;
 reg clk=0,rst_n=0,start=0,done=0,pv=0,swap=0,rv=0,response=0;
 reg [31:0] pa=0,ra=0;
 wire ready,pr,wv,front_valid,front_bank,committed,rejected,read_ready,mrv;
 wire [31:0] wa,mra;
 always #5 clk=~clk;
 frame_buffer_manager #(.FRAME_PIXELS(PIXELS)) dut(
  .clk(clk),.rst_n(rst_n),.frame_start(start),.frame_done(done),.frame_error(1'b0),
  .frame_ready(ready),.pixel_valid(pv),.pixel_addr(pa),.pixel_rgb(24'h123456),
  .pixel_ready(pr),.wr_valid(wv),.wr_addr(wa),.wr_data(),.wr_ready(1'b1),.wr_drained(1'b1),
  .swap_window(swap),.front_valid(front_valid),.front_bank(front_bank),
  .frame_committed(committed),.frame_rejected(rejected),.swap_pending(),
  .read_valid(rv),.read_addr(ra),.read_ready(read_ready),.rgb_valid(),.rgb_data(),.rgb_ready(1'b1),
  .mem_read_valid(mrv),.mem_read_addr(mra),.mem_read_ready(1'b1),
  .mem_response_valid(response),.mem_response_data(32'h00123456));
 task begin_frame;
  begin
   wait(ready);@(negedge clk);start=1;
   @(negedge clk);start=0;
  end
 endtask
 task fill_frame(input integer bank);
  integer i;
  begin
   begin_frame();
   for(i=0;i<PIXELS;i=i+1)begin
    pv=1;pa=i;#1;
    if(!pr||!wv||wa!==bank*PIXELS+i)$fatal(1,"write address mismatch bank=%0d i=%0d",bank,i);
    @(negedge clk);
   end
   pv=0;done=1;@(negedge clk);done=0;swap=1;
   wait(committed);@(negedge clk);swap=0;
   if(!front_valid||front_bank!==bank[0]||rejected)$fatal(1,"bank commit failed");
   // 先检查两个越界地址都不会发起读请求，再检查最后一个有效地址。
   rv=1;ra=PIXELS;#1;
   if(mrv||read_ready)$fatal(1,"end boundary read accepted");
   ra=32'h80000000;#1;
   if(mrv||read_ready)$fatal(1,"high address wrapped into frame");
   ra=PIXELS-1;#1;
   if(!mrv||!read_ready||mra!==bank*PIXELS+PIXELS-1)$fatal(1,"last read address mismatch");
   @(negedge clk);rv=0;response=1;
   @(negedge clk);response=0;
   repeat(2)@(negedge clk);
  end
 endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;
  fill_frame(1);fill_frame(0);
  begin_frame();pv=1;pa=32'h80000000;#1;
  if(!pr||wv)$fatal(1,"high write address was not rejected");
  @(negedge clk);pv=0;done=1;
  @(negedge clk);done=0;
  wait(rejected);
  $display("PASS frame address bounds: pixels=%0d both banks, end/high rejection",PIXELS);
  $finish;
 end
 initial begin #20000000;$fatal(1,"frame address test timeout");end
endmodule
