`timescale 1ns/1ps
module tb_gallery_autoplay;
 reg clk=0,rst_n=0,card_ready=1,load_ready=1,scan_done=0,image_done=0,error=0;
 reg [2:0] image_count=4;
 reg next_pulse=0,prev_pulse=0,pause=1,front_valid=0;
 reg [1:0] display_index=0;
 reg frame_prepared=0,frame_committed=0,transition_ready=0;
 wire scan_start,load_start,commit_enable,discard_cached,transition_active;
 wire transition_manual,transition_backward;wire [1:0] image_index;
 integer i,retries=0;
 always #5 clk=~clk;
 media_prefetch_control #(.INTERVAL_CYCLES(130),.AUTOPLAY_CYCLES(100),.CONTROLLED_AUTOPLAY(1)) dut(
  .clk(clk),.rst_n(rst_n),.card_ready(card_ready),.load_ready(load_ready),.scan_done(scan_done),
  .image_done(image_done),.error(error),.image_count(image_count),.next_pulse(next_pulse),.prev_pulse(prev_pulse),
  .pause(pause),.front_valid(front_valid),.display_index(display_index),.frame_prepared(frame_prepared),
  .frame_committed(frame_committed),.transition_ready(transition_ready),.scan_start(scan_start),.load_start(load_start),
  .image_index(image_index),.commit_enable(commit_enable),.discard_cached(discard_cached),.transition_active(transition_active),
  .auto_enable(1'b1),.transition_manual(transition_manual),.transition_backward(transition_backward),
  .album_request(1'b0),.album_enable(1'b0),.album_first(2'd0),.album_limit(3'd4),.prefetch_enable(1'b1));
 task tick;begin @(negedge clk);#1;end endtask
 task reset;begin rst_n=0;repeat(3)tick;rst_n=1;end endtask
 task loaded;
 begin load_ready=0;tick;image_done=1;frame_prepared=1;tick;image_done=0;end endtask
 initial begin
  reset;wait(scan_start);tick;scan_done=1;tick;scan_done=0;
  wait(load_start);loaded;wait(commit_enable);tick;
  frame_committed=1;front_valid=1;display_index=0;frame_prepared=0;load_ready=1;tick;frame_committed=0;
  wait(load_start);loaded;repeat(4)tick;
  if(dut.timer||dut.foreground)$fatal(1,"pause did not hold dwell at zero");
  pause=0;
  for(i=1;i<=99;i=i+1)begin tick;if(dut.foreground||transition_active)$fatal(1,"autoplay requested before100clocks i=%0d",i);end
  tick;if(!dut.foreground||dut.cursor!=1)$fatal(1,"autoplay did not request at scaled100clock dwell");
  tick;if(!transition_active||!frame_prepared||!front_valid)$fatal(1,"scaled request bypassed prepared/front fences");
  // The accelerated autoplay threshold must not shorten card retry timing.
  pause=1;scan_done=0;image_done=0;frame_prepared=0;front_valid=0;load_ready=1;
  reset;wait(scan_start);tick;error=1;scan_done=1;tick;scan_done=0;error=0;
  for(i=1;i<=129;i=i+1)begin tick;if(dut.state!=10)$fatal(1,"retry shorter than original130clock interval i=%0d state=%0d",i,dut.state);end
  tick;if(dut.state!=0)$fatal(1,"original retry threshold not retained");
  $display("PASS gallery autoplay:100clock dwell versus130clock baseline, original130clock retry, pause and prepared-bank commit protection");$finish;
 end
 initial begin #1000000;$fatal(1,"autoplay timeout state=%d",dut.state);end
endmodule
