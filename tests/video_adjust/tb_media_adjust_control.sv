`timescale 1ns/1ps
module tb_media_wave_control;
 parameter integer COUNT=7;
 reg clk=0,rst_n=1;
 reg [3:0] key_n=15;
 always #5 clk=~clk;
 wire [3:0] key_press,stable_n;
 wire signed [8:0] cfg_value;
 wire [8:0] cfg_gain_q8;
 wire cfg_update,setting_active,next_event,prev_event,pause_event,cfg_fade_enabled,cfg_wave_enabled;
 wire [1:0] setting_page;
 board_key #(.COUNT(COUNT),.WIDTH(4)) keys(.*,.press(key_press));
 media_adjust_control dut(.home_play(1'b0),.home_music_index(2'd0),.product_mode(1'b0),.mode_change(1'b0),.cfg_autoplay(),.autoplay_page(),.music_count(3'd0),.music_page(),.cfg_music_index(),.cfg_music_request(),.rtc_page(),.rtc_exit(1'b0),.frame_tick(1'b0),.held_key_n(4'hf),.contrast_index(),.*);
 integer next_events=0,prev_events=0,pause_events=0,updates=0,cases=0,i,before_updates;
 always @(negedge clk)if(rst_n)begin
  if(next_event)next_events=next_events+1;
  if(prev_event)prev_events=prev_events+1;
  if(pause_event)pause_events=pause_events+1;
  if(cfg_update)updates=updates+1;
  if(setting_active && (next_event||prev_event||pause_event))$fatal(1,"playback event escaped menu");
  if((^{cfg_value,cfg_gain_q8,cfg_update,setting_active,next_event,prev_event,pause_event})===1'bx)$fatal(1,"unknown control output");
 end
 task ticks(input integer n);begin repeat(n)begin @(negedge clk);#1;end end endtask
 task settled;begin ticks(COUNT+5);end endtask
 task release_keys;begin key_n=15;settled;end endtask
 task tap(input integer k);begin key_n=15^(1<<k);settled;release_keys;cases=cases+1;end endtask
 task check_config(input integer b,g,input bit f,w);begin
  if($signed(cfg_value)!=b || cfg_gain_q8!=g || cfg_fade_enabled!==f || cfg_wave_enabled!==w)
   $fatal(1,"config expected %0d/%0d/%b/%b actual %0d/%0d/%b/%b",b,g,f,w,$signed(cfg_value),cfg_gain_q8,cfg_fade_enabled,cfg_wave_enabled);
 end endtask
 initial begin
  #1;rst_n=0;ticks(3);rst_n=1;settled;
  tap(0);tap(2);tap(1);
  if(next_events!=1 || prev_events!=1 || pause_events!=1)$fatal(1,"normal mapping");
  // A held key emits once; switching directly to another held key emits none.
  key_n=14;settled;ticks(COUNT*2+5);
  key_n=11;settled;
  if(next_events!=2 || prev_events!=1)$fatal(1,"held key repeated or bypassed release");
  release_keys;tap(2);
  if(prev_events!=2)$fatal(1,"stable release failed to rearm");
  tap(3);if(!setting_active || setting_page!=0)$fatal(1,"runtime KEY4 menu entry");
  check_config(0,256,0,0);
  tap(0);check_config(32,256,0,0);tap(0);check_config(64,256,0,0);
  before_updates=updates;tap(0);if(updates!=before_updates)$fatal(1,"brightness upper clamp");
  for(i=1;i<=4;i=i+1)begin tap(2);check_config(64-32*i,256,0,0);end
  before_updates=updates;tap(2);if(updates!=before_updates)$fatal(1,"brightness lower clamp");
  tap(1);if(setting_page!=1)$fatal(1,"OK contrast page");
  tap(0);check_config(-64,320,0,0);tap(0);check_config(-64,384,0,0);
  before_updates=updates;tap(0);if(updates!=before_updates)$fatal(1,"contrast upper clamp");
  for(i=1;i<=4;i=i+1)begin tap(2);check_config(-64,384-64*i,0,0);end
  before_updates=updates;tap(2);if(updates!=before_updates)$fatal(1,"contrast lower clamp");
  tap(1);if(setting_page!=2)$fatal(1,"OK fade page");
  tap(0);check_config(-64,128,1,0);tap(0);check_config(-64,128,1,0);
  tap(2);check_config(-64,128,0,0);tap(0);
  tap(1);if(setting_page!=3)$fatal(1,"OK wave page");
  tap(0);check_config(-64,128,1,1);tap(2);check_config(-64,128,1,0);tap(0);
  tap(1);if(setting_active)$fatal(1,"last OK exits menu");
  check_config(-64,128,1,1);
  for(i=0;i<4;i=i+1)begin
   tap(3);repeat(i)tap(1);
   if(!setting_active || setting_page!=i)$fatal(1,"menu reentry/page");
   tap(3);if(setting_active)$fatal(1,"KEY4 back from page %0d",i);
   check_config(-64,128,1,1);
  end
  if(next_events!=2 || prev_events!=2 || pause_events!=1)$fatal(1,"menu actions leaked playback events");
  tap(0);tap(2);tap(1);
  if(next_events!=3 || prev_events!=3 || pause_events!=2)$fatal(1,"normal mode after menu");
  rst_n=0;ticks(3);check_config(0,256,0,0);if(setting_active)$fatal(1,"reset did not exit settings");
  $display("PASS media_wave_control COUNT=%0d cases=%0d: four keys, shared debounce, held-key/release interlock, runtime settings, both bounds and all four features",COUNT,cases);$finish;
 end
 initial begin #300000000;$fatal(1,"four key control timeout");end
endmodule
