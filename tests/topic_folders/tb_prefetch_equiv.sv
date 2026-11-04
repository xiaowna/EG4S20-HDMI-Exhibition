`timescale 1ns/1ps
module tb_topic_prefetch_equiv;
 reg sys_clk=0,pix_clk=0,rst_n=0,start=0,slide_active=0,slide_right=0,intro_active=0;
 reg [15:0] slide_offset=0;reg [5:0] slide_alpha=32,intro_phase=0;reg [1:0] intro_topic=0;
 reg [31:0] frame_base=0,burst_data=0;reg burst_data_valid=0,burst_last=0,burst_error=0;
 wire start_ready,busy,done,error,burst_valid,pixel_valid,pixel_last;
 wire r_start_ready,r_busy,r_done,r_error,r_burst_valid,r_pixel_valid,r_pixel_last;
 wire [31:0] burst_addr,pixel_addr,r_burst_addr,r_pixel_addr;
 wire [8:0] burst_words,r_burst_words;wire [23:0] pixel_rgb,r_pixel_rgb;
 integer cycles=0,pixels=0,response=0,length=0,commands=0,checks=0;reg [31:0] address=0;reg responding=0;
 wire burst_ready=!responding&&cycles%7!=0,pixel_ready=cycles%11!=0;
 always #10 sys_clk=~sys_clk;always #20 pix_clk=~pix_clk;
 frame_burst_prefetch #(.FRAME_PIXELS(307200),.SLIDE_TRANSITIONS(1),.INTRO_ANIMATION(1)) dut(.*);
 frame_burst_prefetch_reference #(.FRAME_PIXELS(307200),.SLIDE_TRANSITIONS(1),.INTRO_ANIMATION(1)) old(
  .start_ready(r_start_ready),.busy(r_busy),.done(r_done),.error(r_error),.burst_valid(r_burst_valid),
  .pixel_valid(r_pixel_valid),.pixel_last(r_pixel_last),.burst_addr(r_burst_addr),.pixel_addr(r_pixel_addr),
  .burst_words(r_burst_words),.pixel_rgb(r_pixel_rgb),.*);
 always @(posedge sys_clk)begin
  cycles<=cycles+1;
  if(rst_n)begin
   if({start_ready,busy,done,error,burst_valid}!=={r_start_ready,r_busy,r_done,r_error,r_burst_valid})$fatal(1,"pruning changed control at%0d",cycles);
   if(burst_valid&&{burst_addr,burst_words}!=={r_burst_addr,r_burst_words})$fatal(1,"pruning changed SDRAM command");
   if(burst_valid&&burst_ready)begin address=burst_addr;length=burst_words;response=0;responding=1;commands=commands+1;end
   checks=checks+1;
  end
 end
 always @(negedge sys_clk)begin
  burst_data_valid=0;burst_last=0;
  if(responding&&cycles%5!=0)begin
   burst_data_valid=1;burst_data=((address+response)*37)^((address+response)<<7)^24'h5a39c7;
   burst_last=response==length-1;response=response+1;if(response==length)responding=0;
  end
 end
 always @(posedge pix_clk)if(rst_n)begin
  if(pixel_valid!==r_pixel_valid)$fatal(1,"pruning changed pixel valid");
  if(pixel_valid&&{pixel_addr,pixel_rgb,pixel_last}!=={r_pixel_addr,r_pixel_rgb,r_pixel_last})$fatal(1,"pruning changed FIFO output pixel%0d",pixels);
  if(pixel_valid&&pixel_ready)pixels=pixels+1;
 end
 task frame(input integer id);
  begin wait(start_ready);@(negedge sys_clk);pixels=0;frame_base=(id==1)?307200:0;
   slide_active=id==1;slide_right=id==1;slide_offset=(id==1)?319:0;slide_alpha=(id==1)?16:32;
   intro_active=id==2;intro_topic=3;intro_phase=(id==2)?63:18;
   start=1;@(negedge sys_clk);start=0;wait(done);@(negedge sys_clk);
   if(error||pixels!=307200)$fatal(1,"equivalence frame incomplete %0d %0d",id,pixels);
  end
 endtask
 initial begin
  repeat(4)@(negedge sys_clk);rst_n=1;
  for(integer i=0;i<3;i=i+1)frame(i);
  wait(start_ready);@(negedge sys_clk);burst_error=1;@(negedge sys_clk);burst_error=0;
  repeat(5)@(negedge sys_clk);if(!error||!r_error)$fatal(1,"backend error protection lost");
  $display("PASS legacy-engine pruning cycle equivalence:3 full gallery/slide/intro frames,921600 pixels, %0d control cycles, %0d commands, backend error fence",checks,commands);$finish;
 end
 initial begin #500000000;$fatal(1,"prefetch equivalence timeout");end
endmodule
