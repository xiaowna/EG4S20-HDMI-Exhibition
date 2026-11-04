`timescale 1ns/1ps
module tb_prepare_count;
 reg clk=0,rst_n=0,frame_start=0,frame_done=0,frame_error=0,pixel_valid=0;
 reg [31:0] pixel_addr=0;reg wr_ready=1,wr_drained=0,swap_window=0;
 wire frame_ready,pixel_ready,wr_valid,front_valid,front_bank,frame_committed,frame_rejected,swap_pending;
 wire [31:0] wr_addr,wr_data;wire [6:0] prepare_pixels;
 frame_buffer_manager dut(.clk(clk),.rst_n(rst_n),.frame_start(frame_start),.frame_done(frame_done),.frame_error(frame_error),.frame_ready(frame_ready),
 .pixel_valid(pixel_valid),.pixel_addr(pixel_addr),.pixel_rgb(24'h123456),.pixel_ready(pixel_ready),.wr_valid(wr_valid),.wr_addr(wr_addr),.wr_data(wr_data),
 .wr_ready(wr_ready),.wr_drained(wr_drained),.swap_window(swap_window),.front_valid(front_valid),.front_bank(front_bank),.frame_committed(frame_committed),.frame_rejected(frame_rejected),.swap_pending(swap_pending),
 .read_valid(1'b0),.read_addr(32'd0),.rgb_ready(1'b1),.mem_read_ready(1'b0),.mem_response_valid(1'b0),.mem_response_data(32'd0),.discard_frame(1'b0),.prepare_pixels(prepare_pixels));
 integer accepted=0,cycle=0,i;reg take;
 always #5 clk=~clk;
 task tick;begin @(posedge clk);take=pixel_valid&&pixel_ready;if(take)accepted=accepted+1;#1;
  if(rst_n&&prepare_pixels!==(frame_ready?0:accepted/4096))$fatal(1,"accepted-write progress expected=%0d got=%0d",accepted/4096,prepare_pixels);
  @(negedge clk);#1;
 end endtask
 initial begin
  repeat(3)tick;rst_n=1;frame_start=1;tick;frame_start=0;
  while(accepted<307200)begin
   pixel_addr=307199-accepted;pixel_valid=cycle%5!=0;wr_ready=cycle%3!=0;tick;cycle=cycle+1;
  end
  pixel_valid=0;frame_done=1;tick;frame_done=0;repeat(5)tick;
  if(swap_pending||front_valid||prepare_pixels!=75)$fatal(1,"drain safety changed");
  wr_drained=1;tick;tick;if(!swap_pending||front_valid)$fatal(1,"unsafe early commit");
  swap_window=1;tick;if(!frame_committed||!front_valid||prepare_pixels!=0)$fatal(1,"safe commit missing");
  swap_window=0;accepted=0;frame_start=1;tick;frame_start=0;
  pixel_valid=1;pixel_addr=0;wr_ready=1;tick;pixel_valid=0;frame_done=1;frame_error=1;tick;frame_done=0;tick;
  if(!frame_rejected||!front_valid||front_bank!=1)$fatal(1,"bad frame replaced front");
  rst_n=0;#1;if(prepare_pixels!=0)$fatal(1,"reset did not clear progress");
  $display("PASS progress count: 307200 backwards-address pixels, independent valid/ready stalls, drain, commit, reject, reset");$finish;
 end
 initial begin #20000000;$fatal(1,"timeout");end
endmodule
