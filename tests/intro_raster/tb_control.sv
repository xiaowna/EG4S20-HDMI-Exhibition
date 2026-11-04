`timescale 1ns/1ps
// Fast control-only test. Only transaction mailboxes/readiness/completion are
// modeled; the production sys FSM and phase state are exercised unchanged.
module tb_intro_phase_control;
 reg sys_clk=0,pix_clk=0,rst_n=0;
 always #10 sys_clk=~sys_clk;
 reg front_bank=0,intro_enable=1,intro_pause=0;
 reg [4:0] intro_index=5;
 reg request=0,complete_frame=0;
 wire swap_window,burst_valid,prefetch_error,de,hsync,vsync,frame_underflow,fetch_busy,video_started,slide_ready,intro_animating;
 wire [31:0] burst_addr;wire [8:0] burst_words;wire [23:0] rgb;
 integer transactions=0;
 frame_stream_display #(.INTRO_ANIMATION(1)) display(
  .rst_n(rst_n),.sys_clk(sys_clk),.pix_clk(pix_clk),.front_valid(1'b1),.front_bank(front_bank),
  .swap_window(swap_window),.burst_valid(burst_valid),.burst_addr(burst_addr),.burst_words(burst_words),
  .burst_ready(1'b0),.burst_data_valid(1'b0),.burst_last(1'b0),.burst_error(1'b0),.burst_data(32'd0),
  .prefetch_error(prefetch_error),.de(de),.hsync(hsync),.vsync(vsync),.rgb(rgb),
  .frame_underflow(frame_underflow),.fetch_busy(fetch_busy),.video_started(video_started),
  .slide_request(1'b0),.slide_right(1'b0),.slide_prepared(1'b0),.slide_ready(slide_ready),
  .intro_enable(intro_enable),.intro_pause(intro_pause),.intro_index(intro_index),.intro_animating(intro_animating));
 task frame(input integer expected_phase,input integer expected_mode,input integer expected_topic);
  begin
   wait(display.sys_state==0);@(negedge sys_clk);request=!request;
   wait(display.sys_state==4);#1;
   if(display.intro_phase_q!==expected_phase||display.intro_mode_q!==expected_mode||
      (expected_mode&&display.intro_topic_q!==expected_topic))
    $fatal(1,"phase FSM mismatch transaction=%0d expected=%0d got=%0d mode=%b topic=%0d",transactions,expected_phase,display.intro_phase_q,display.intro_mode_q,display.intro_topic_q);
   repeat(7)begin
    @(negedge sys_clk);
    if(display.intro_phase_q!==expected_phase)$fatal(1,"phase advanced before transaction retired");
   end
   complete_frame=1;@(negedge sys_clk);complete_frame=0;
   wait(display.sys_state==0);transactions=transactions+1;
  end
 endtask
 initial begin
  force display.req2=request;
  force display.pre_ready=1'b1;
  force display.pre_done=complete_frame;
  force display.pre_start=1'b0;
  repeat(4)@(negedge sys_clk);rst_n=1;
  for(integer p=0;p<=12;p=p+2)frame(p,1,0);
  intro_pause=1;
  repeat(9)frame(12,1,0);
  intro_pause=0;
  for(integer p=14;p<64;p=p+2)frame(p,1,0);
  repeat(3)frame(63,1,0);
  if(intro_animating)$fatal(1,"settled introduction remains animating");
  intro_enable=0;frame(0,0,0);
  intro_enable=1;frame(0,1,0);
  front_bank=1;frame(0,1,0);
  intro_index=11;frame(0,1,1);
  intro_index=17;frame(0,1,2);
  intro_index=23;frame(0,1,3);
  intro_index=22;frame(0,0,0);
  for(integer p=1;p<=12;p=p+1)frame(p,0,0);
  repeat(9)frame(12,0,0);
  if(intro_animating)$fatal(1,"settled ordinary caption remains animating");
  intro_pause=1;repeat(3)frame(12,0,0);intro_pause=0;
  $display("PASS intro phase control transactions=%0d; step2 intro, 12-frame caption entrance, nine menu-paused frames, safe saturation, home disable/reentry, bank/index reset and all4topics",transactions);
  $finish;
 end
 initial begin #1000000;$fatal(1,"phase control timeout");end
endmodule
