`timescale 1ns/1ps
module tb_prefetch_visibility;
 reg clk=0,rst_n=0,card_ready=0,load_ready=1,scan_done=0,image_done=0,error=0;
 reg [2:0] image_count=4;reg next_pulse=0,prev_pulse=0,pause=0,front_valid=0;
 reg [1:0] display_index=0;reg frame_prepared=0,frame_committed=0,transition_ready=0;
 wire scan_start,load_start,commit_enable,discard_cached,transition_active,transition_manual,transition_backward;
 wire [1:0] image_index;reg auto_enable=1,album_request=0,album_enable=1;
 reg [1:0] album_first=2;reg [2:0] album_limit=4;
 wire album_ready,album_error,preparing,prepare_progress_valid;integer checks=0;
 always #5 clk=~clk;
 media_prefetch_control #(.INTERVAL_CYCLES(17),.CONTROLLED_AUTOPLAY(1),.ALBUMS(1)) dut(.prefetch_enable(1'b1),.fast_pulse(1'b0),.cancel_load(),.fast_commit(),.autoplay_interval(3'd7),.retain_first(),.preserve_album(),.*);
 task tick;begin @(negedge clk);#1;end endtask
 task wait_load;integer i;begin i=0;while(!load_start&&i<100)begin tick;i=i+1;end
  if(!load_start)$fatal(1,"loader never launched");end endtask
 task check(input bit visible);begin
  if(preparing!==visible)$fatal(1,"automatic/manual loading visibility got=%b expected=%b",preparing,visible);
  checks=checks+1;
 end endtask
 initial begin
  repeat(3)tick;rst_n=1;card_ready=1;tick;scan_done=1;tick;scan_done=0;
  wait_load;check(1);load_ready=0;image_done=1;tick;image_done=0;frame_prepared=1;
  repeat(3)tick;if(!commit_enable)$fatal(1,"first frame not authorized");
  frame_committed=1;front_valid=1;tick;frame_committed=0;frame_prepared=0;load_ready=1;
  wait_load;load_ready=0;check(0);
  // Leave the next decode running beyond the auto interval: retain current image.
  repeat(30)begin tick;check(0);end
  image_done=1;tick;image_done=0;frame_prepared=1;repeat(4)tick;
  transition_ready=1;tick;if(!commit_enable)$fatal(1,"autoplay blocked by presentation policy");
  frame_committed=1;display_index=image_index;tick;frame_committed=0;frame_prepared=0;transition_ready=0;load_ready=1;
  wait_load;load_ready=0;auto_enable=0;prev_pulse=1;tick;prev_pulse=0;check(1);
  // Fresh album request still shows a genuine user wait even with an old frame.
  rst_n=0;load_ready=1;tick;rst_n=1;card_ready=1;tick;scan_done=1;tick;scan_done=0;
  wait_load;album_request=1;tick;album_request=0;check(1);
  $display("PASS prefetch visibility: %0d checks; cold load, automatic miss, commit, manual miss, album request",checks);$finish;
 end
 initial begin #100000;$fatal(1,"timeout");end
endmodule
