`timescale 1ns/1ps
module tb_fine_control;
 reg clk=0,rst_n=0,frame_tick=0,mode_change=0,home_play=0;
 reg [3:0] key_press=0,held_key_n=15;
 wire signed [8:0] cfg_value;wire [8:0] cfg_gain_q8;
 wire [6:0] contrast_index;wire cfg_update,setting_active,next_event,prev_event,pause_event;
 wire [1:0] setting_page;integer b=0,p=100,i,n,checks=0;
 reg [31:0] rng=32'h45830abc;
 always #5 clk=~clk;
 media_adjust_control #(.FINE_ADJUST(1),.AUTOPLAY_MENU(1),.MUSIC_MENU(1),.RTC_MENU(1),.HOME_UI(1)) dut(
  .clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.held_key_n(held_key_n),.contrast_index(contrast_index),
  .key_press(key_press),.cfg_value(cfg_value),.cfg_gain_q8(cfg_gain_q8),.cfg_update(cfg_update),
  .setting_active(setting_active),.setting_page(setting_page),.next_event(next_event),.prev_event(prev_event),.pause_event(pause_event),
  .product_mode(1'b1),.mode_change(mode_change),.home_play(home_play),.home_music_index(2'd0),
  .music_count(3'd4),.rtc_exit(1'b0));
 task ticks(input integer n);repeat(n)begin @(negedge clk);#1;end endtask
 task check;
 begin
  checks++;
  if($signed(cfg_value)!=b||cfg_gain_q8!=(p*256+50)/100||contrast_index!=p-50)
   $fatal(1,"fine setting b=%0d/%0d percent=%0d gain=%0d/%0d index=%0d",$signed(cfg_value),b,p,cfg_gain_q8,(p*256+50)/100,contrast_index);
  if(setting_active&&(next_event||prev_event||pause_event))$fatal(1,"numeric key leaked to player");
 end endtask
 task press(input [3:0] mask);begin key_press=mask;ticks(1);key_press=0;ticks(2);end endtask
 task frame;begin frame_tick=1;ticks(1);frame_tick=0;ticks(1);end endtask
 task adjust(input bit contrast,input bit right);
 integer old,delta;
 begin
  old=contrast?p:b;
  if(contrast)p=right?((p<150)?p+1:150):((p>50)?p-1:50);
  else b=right?((b<64)?b+1:64):((b>-64)?b-1:-64);
  key_press=right?1:4;ticks(1);
  if(cfg_update!==((contrast?p:b)!=old))$fatal(1,"update/clamp notification");
  check;key_press=0;ticks(2);
 end endtask
 initial begin
  ticks(3);rst_n=1;ticks(3);check;press(8);check;
  for(i=0;i<70;i++)adjust(0,1);
  for(i=0;i<135;i++)adjust(0,0);
  for(i=0;i<128;i++)adjust(0,1);
  press(2);if(setting_page!=1)$fatal(1,"contrast page");
  for(i=0;i<55;i++)adjust(1,1);
  for(i=0;i<106;i++)adjust(1,0);
  for(i=0;i<100;i++)adjust(1,1);
  for(i=0;i<4000;i++)begin rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);adjust(1,rng[0]);end
  press(5);check;press(8);press(8); // back, reopen brightness
  // Reach a known neutral setting, then check initial hold/repeat timing.
  for(i=0;i<64;i++)adjust(0,0);
  held_key_n=14;key_press=1;b++;ticks(1);key_press=0;ticks(2);check;
  repeat(20)frame();check;frame();b++;check;
  frame();check;frame();b++;check;
  // Stable direction changes without an all-released state cannot bypass
  // the physical debouncer's one-shot release interlock through repetition.
  held_key_n=11;repeat(50)frame();check;
  held_key_n=15;ticks(2);repeat(10)frame();check;
  // A held LEFT at a page transition must release before repeating.
  held_key_n=11;press(2);repeat(40)frame();check;
  held_key_n=15;ticks(2);held_key_n=11;key_press=4;if(p>50)p--;ticks(1);key_press=0;ticks(2);check;
  held_key_n=15;ticks(2);press(8);repeat(40)frame();check;
  if(setting_active)$fatal(1,"close settings");
  mode_change=1;ticks(1);mode_change=0;check;
  $display("PASS fine control: %0d independent checks, all 129 brightness/101 contrast values, 4000 reversals, clamps, key hold/release/page interlock and player isolation",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"fine control timeout");end
endmodule
