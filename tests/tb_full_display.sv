`timescale 1ns/1ps
module tb_full_display;
 parameter FULL=1;
 localparam W=FULL?640:8,H=FULL?480:3,N=W*H;
 reg sc=0,pc=0,rst=0;always #10 sc=~sc;always #20 pc=~pc;
 reg front=0,bank=0,wv=0;reg [31:0] wa=0,wd=0;
 wire window,bv,br,dv,last,berr,init,memfault,pe,de,hs,vs,under,busy,wr,dr,video_started;
 wire [31:0] ba,data;wire [8:0] words;wire [23:0] rgb;
 integer i,seen=0,lit=0,frames=0,blackframes=0,base=0;reg swapped=0,first_arm_seen=0;
 eg4s20_stream_memory memory(sc,rst,wv,wa,wd,wr,dr,bv,ba,words,br,dv,last,data,berr,memfault,init);
 frame_stream_display #(.H_ACTIVE(W),.V_ACTIVE(H),.FIFO_ADDR_BITS(8)) display(
 .rst_n(rst),.sys_clk(sc),.pix_clk(pc),.front_valid(front),.front_bank(bank),.swap_window(window),
 .burst_valid(bv),.burst_addr(ba),.burst_words(words),.burst_ready(br),.burst_data_valid(dv),.burst_last(last),.burst_error(berr),.burst_data(data),.prefetch_error(pe),
 .de(de),.hsync(hs),.vsync(vs),.rgb(rgb),.frame_underflow(under),.fetch_busy(busy),.video_started(video_started));
 always @(posedge sc)begin
  if(init)front<=1;
  if(window && frames>=1 && !swapped)begin bank<=1;swapped<=1;end
  if(rst&&(memfault||pe))$fatal(1,"memory/prefetch error");
 end
 always @(posedge pc)begin
  if(rst && display.arm)first_arm_seen=1;
  #1;
  if(rst)begin
   if(video_started!==first_arm_seen)
    $fatal(1,"video_started must latch on the first prefetch-ready raster arm");
   if(under)$fatal(1,"full-size display underflow at pixel %d",seen);
   if(de)begin
    if(seen==0)base=rgb;
    if(rgb!=0)begin
     lit=lit+1;
     if(rgb!==base+seen || (base!=1 && base!=N+1))$fatal(1,"bad frame address/data %d %h base=%h",seen,rgb,base);
    end
    seen=seen+1;
    if(seen==N)begin
     if(lit==N)frames=frames+1;else if(lit!=0)$fatal(1,"partial frame");else blackframes=blackframes+1;
     lit=0;seen=0;
     if(frames==3)begin
      if(!swapped||base!=N+1)$fatal(1,"swap missing");
      $display("PASS display %0dx%0d 50MHz sys / 25MHz pixels: 3 full frames, safe bank swap, background writes, no underflow",W,H);$finish;
     end
    end
   end
  end
 end
 initial begin
  for(i=0;i<2*N;i=i+1)memory.u_memory.memory[i]=i+1;
  // Hold reset across both clocks so every clock domain observes it.
  repeat(4)@(negedge pc);rst=1;wait(init);
  // Continuous competing writes in a scratch region, so pixel data is unchanged.
  forever begin
   @(negedge sc);wv=1;wa=2*N;wd=32'h12345678;
   @(posedge sc);while(!wr)@(posedge sc);@(negedge sc);wv=0;
  end
 end
 initial begin #100000000;$fatal(1,"timeout frames=%d",frames);end
endmodule
