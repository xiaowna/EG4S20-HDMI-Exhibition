`timescale 1ns/1ps
// Real SDRAM command model, refresh/arbitration, 50/25MHz raster, full pixels.
module tb_slide_full #(parameter FULL=1);
 localparam W=FULL?640:8,H=FULL?480:3,N=W*H;
 localparam FRAME_NS=(W+160)*(H+45)*40;
 reg sc=0,pc=0,rst=0,front=0,bank=0,wv=0;
 reg [31:0] wa=0,wd=0;
 reg request=0,right=0,prepared=0;
 wire slide_ready,window,bv,br,dv,last,berr,init,memfault,pe,de,hs,vs,under,busy,wr,dr,video_started;
 wire [31:0] ba,data;wire [8:0] words;wire [23:0] rgb;
 integer frames=0,seen=0,lit=0,commits=0,animations=0;
 integer serial=0,serial_seen=0,animation_frames=0,phase=0,old_bank=0,source_bank=0,sx=0,sy=0,distance=0;
 integer expected=0,checked=0,commands=0,writes=0,frame_bank=0;
 reg armed=0,animating=0,direction=0;
 realtime start_time=0;
 always #10 sc=~sc;always #20 pc=~pc;
 eg4s20_stream_memory memory(sc,rst,wv,wa,wd,wr,dr,bv,ba,words,br,dv,last,data,berr,memfault,init);
 frame_stream_display #(.H_ACTIVE(W),.V_ACTIVE(H),.FIFO_ADDR_BITS(8),.SLIDE_TRANSITIONS(1)) display(
  .rst_n(rst),.sys_clk(sc),.pix_clk(pc),.front_valid(front),.front_bank(bank),.swap_window(window),
  .burst_valid(bv),.burst_addr(ba),.burst_words(words),.burst_ready(br),.burst_data_valid(dv),
  .burst_last(last),.burst_error(berr),.burst_data(data),.prefetch_error(pe),
  .de(de),.hsync(hs),.vsync(vs),.rgb(rgb),.frame_underflow(under),.fetch_busy(busy),.video_started(video_started),
  .slide_request(request),.slide_right(right),.slide_prepared(prepared),.slide_ready(slide_ready));
 always @(posedge sc)begin
  if(init)front<=1;
  if(rst&&(memfault||pe||under))$fatal(1,"full-size slide memory/raster fault");
  if(bv&&br)commands=commands+1;
  if(wv&&wr)writes=writes+1;
  if(!request)armed=0;
  if(window&&request&&prepared&&!armed)begin
   armed=1;serial=serial+1;animation_frames=0;
  end
  if(slide_ready)begin
   if(animation_frames!=18)$fatal(1,"full-size slide acknowledged early");
   if(window&&request)begin bank<=!bank;commits=commits+1;request<=0;end
  end
 end
 always @(posedge pc)begin
  #1;
  if(rst&&de)begin
   if(seen==0)begin
    frame_bank=bank;
    if(serial!=serial_seen)begin
     serial_seen=serial;animating=1;phase=0;old_bank=bank;direction=right;start_time=$realtime;
    end else if(!animating&&animations<commits)begin
     if($realtime-start_time!=18.0*FRAME_NS)$fatal(1,"wrong animation duration: %0t",$realtime-start_time);
     animations=animations+1;
    end
    distance=(W*((256*(3*phase*phase*18-2*phase*phase*phase)+2916)/5832))/256;
   end
   if(rgb!=0)begin
    source_bank=frame_bank;sx=seen%W;sy=seen/W;
    if(animating)begin
     source_bank=old_bank;
     if(direction)begin
      if(sx<distance)begin source_bank=1-old_bank;sx=sx+W-distance;end
      else sx=sx-distance;
     end else begin
      if(sx<W-distance)sx=sx+distance;
      else begin source_bank=1-old_bank;sx=sx-(W-distance);end
     end
    end
    expected=source_bank*N+sy*W+sx+1;
    if(rgb!==expected)$fatal(1,"full slide pixel bank=%0d phase=%0d dir=%b d=%0d ordinal=%0d expected=%h got=%h",frame_bank,phase,direction,distance,seen,expected,rgb);
    lit=lit+1;checked=checked+1;
   end
   seen=seen+1;
   if(seen==N)begin
    if(lit==N)begin
     frames=frames+1;
     if(FULL && frames%5==0)
      $display("PROGRESS full slide frames=%0d checked_pixels=%0d phase=%0d commits=%0d",frames,checked,phase,commits);
     if(animating)begin
      animation_frames=animation_frames+1;
      if(phase==17)animating=0;else phase=phase+1;
     end
    end else if(lit!=0)$fatal(1,"partial full-size sliding frame");
    lit=0;seen=0;
   end
  end
 end
 initial begin
  for(integer i=0;i<2*N;i=i+1)memory.u_memory.memory[i]=i+1;
  repeat(4)@(negedge pc);rst=1;wait(init);
  forever begin
   @(negedge sc);wv=1;wa=2*N;wd=32'h12345678;
   @(posedge sc);while(!wr)@(posedge sc);@(negedge sc);wv=0;
  end
 end
 integer before_frames;
 initial begin
  wait(frames>=2);@(negedge sc);request=1;right=0;prepared=0;
  before_frames=frames;wait(frames>=before_frames+2);
  if(slide_ready||commits!=0||serial!=0)$fatal(1,"unvalidated back bank participated in slide");
  @(negedge sc);prepared=1;
  wait(animation_frames==5);@(negedge sc);right=1; // latched direction must remain left
  wait(commits==1);wait(animations==1);before_frames=frames;wait(frames>=before_frames+2);
  @(negedge sc);request=1;right=1;
  wait(commits==2);wait(animations==2);before_frames=frames;wait(frames>=before_frames+1);
  if(bank!=0||writes==0)$fatal(1,"reverse/bandwidth coverage missing");
  $display("PASS full slide %0dx%0d: pixels=%0d frames=%0d commands=%0d competing_writes=%0d refreshes=%0d animations=%0d duration_ns=%0d; both directions, delayed-ready, direction latch, exact smoothstep, no underflow",W,H,checked,frames,commands,writes,memory.u_memory.run_refreshes,animations,18*FRAME_NS);$finish;
 end
 initial begin #1000000000;$fatal(1,"full-size slide timeout frames=%0d commits=%0d",frames,commits);end
endmodule
