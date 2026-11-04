`timescale 1ns/1ps
// Actual 50/25MHz SDRAM/raster path. Both source banks are immutable during
// slides; competing writes target a third SDRAM region, with normal refresh.
module tb_gallery_slide_raster;
 localparam N=307200;
 reg sc=0,pc=0,rst=0,front=0,bank=0,wv=0;
 reg request=0,right=0,prepared=0;
 wire window,bv,br,dv,last,berr,init,memfault,pe,de,hs,vs,under,busy,wr,dr,started,ready;
 wire [31:0] ba,data;wire [8:0] words;wire [23:0] rgb;
 integer frames=0,pixels=0,commits=0,writes=0,reads=0,serial=0;
 integer phase=0,entry_phase=0,direction=0,source=0,distance=0,alpha=32,style=0;
 integer pos=0,frame_serial=0,slide_frames=0,completed=0;
 reg active=0;reg [23:0] golden[0:N-1];string path;
 function automatic [23:0] color(input integer address);
  color=(address*37)^(address<<7)^24'h5a39c7;
 endfunction
 always #10 sc=~sc;always #20 pc=~pc;
 eg4s20_stream_memory memory(sc,rst,wv,32'd614400,32'h12345678,wr,dr,bv,ba,words,br,dv,last,data,berr,memfault,init);
 frame_stream_display #(.FIFO_ADDR_BITS(8),.SLIDE_TRANSITIONS(1),.INTRO_ANIMATION(1)) display(
  .rst_n(rst),.sys_clk(sc),.pix_clk(pc),.front_valid(front),.front_bank(bank),.swap_window(window),
  .burst_valid(bv),.burst_addr(ba),.burst_words(words),.burst_ready(br),.burst_data_valid(dv),
  .burst_last(last),.burst_error(berr),.burst_data(data),.prefetch_error(pe),
  .de(de),.hsync(hs),.vsync(vs),.rgb(rgb),.frame_underflow(under),.fetch_busy(busy),.video_started(started),
  .slide_request(request),.slide_right(right),.slide_prepared(prepared),.slide_ready(ready),
  .intro_enable(1'b1),.intro_pause(1'b1),.intro_index(5'd0),.intro_animating());
 always @(posedge sc)if(rst)begin
  if(init)front<=1;
  if(memfault||pe||under)$fatal(1,"gallery slide memory/raster fault");
  if(wv&&wr)writes=writes+1;
  if(bv&&br)begin
   reads=reads+1;
   if(ba>=2*N||ba+words>2*N)$fatal(1,"slide read outside validated source banks");
  end
  if(display.pre_start)begin
   serial=serial+1;source=bank;
   phase=display.slide_running?display.slide_phase:-1;
   entry_phase=display.intro_phase_q;
   direction=display.slide_direction;distance=display.slide_distance;
   style=display.slide_style;
   alpha=32-display.slide_fraction_value[8:3];
  end
  if(window&&(busy||!display.u_prefetch.fifo_empty||display.u_prefetch.intro_busy||bv||dv))
   $fatal(1,"unsafe slide swap before producer/FIFO retirement");
  if(ready&&request&&window)begin
   if(slide_frames!=9||style!=commits%3)$fatal(1,"slide acknowledged without9retired phases/correct style: %0d style=%0d",slide_frames,style);
   bank<=!bank;request<=0;commits=commits+1;completed=completed+1;slide_frames=0;
  end
 end
 always @(posedge pc)begin
  if(rst&&display.arm)begin
   if(active)$fatal(1,"overlapping frame");
   active=1;pos=0;frame_serial=serial;
   if(phase<0)path=$sformatf("entry_%0d_%0d.hex",source,entry_phase);
   else path=$sformatf("slide_%0d_%0d_%0d.hex",style,source,phase);
   $readmemh(path,golden);
  end
  #1;
  if(rst&&de&&active)begin
   if(frame_serial!=serial||rgb!==golden[pos])
    $fatal(1,"gallery full slide pixel bank=%0d phase=%0d d=%0d a=%0d pos=%0d got=%h expected=%h",source,phase,distance,alpha,pos,rgb,golden[pos]);
   pos=pos+1;pixels=pixels+1;
   if(pos==N)begin
    active=0;frames=frames+1;
    if(phase>=0)slide_frames=slide_frames+1;
    if(frames%6==0)$display("PROGRESS gallery slide frames=%0d phase=%0d writes=%0d",frames,phase,writes);
   end
  end
 end
 initial begin
  for(integer i=0;i<2*N;i=i+1)memory.u_memory.memory[i]={8'd0,color(i)};
  repeat(4)@(negedge pc);rst=1;wait(init);
  forever begin
   @(negedge sc);wv=1;@(posedge sc);while(!wr)@(posedge sc);@(negedge sc);wv=0;
  end
 end
 initial begin
  wait(frames>=2);@(negedge sc);request=1;right=0;
  wait(frames>=4);if(ready||commits||display.slide_running)$fatal(1,"unvalidated bank used");
  @(negedge sc);prepared=1;
  wait(slide_frames==5);@(negedge sc);right=1; // Active direction must stay latched.
  wait(completed==1);wait(frames>=18);@(negedge sc);request=1;right=1;
  wait(completed==2);wait(frames>=33);@(negedge sc);request=1;right=0;
  wait(completed==3);wait(frames>=48);
  if(!bank||writes==0||memory.u_memory.run_refreshes==0)$fatal(1,"missing three-style/arbitration coverage");
  $display("PASS gallery real SDRAM slide: frames=%0d pixels=%0d reads=%0d writes=%0d refreshes=%0d;3styles,both9phase directions,first-frame caption,old-caption fade,delayed-ready,safe swap",frames,pixels,reads,writes,memory.u_memory.run_refreshes);$finish;
 end
 initial begin #1100000000;$fatal(1,"gallery slide timeout frames=%0d commits=%0d",frames,commits);end
endmodule
