`timescale 1ns/1ps
module tb_mode_menu;
 reg clk=0,rst_n=1,product_mode=1,mode_change=0;
 reg [3:0] key_press=0;
 wire signed [8:0] cfg_value;wire [8:0] cfg_gain_q8;
 wire cfg_fade_enabled,cfg_wave_enabled,cfg_update,setting_active,next_event,prev_event,pause_event;
 wire cfg_autoplay,autoplay_page;wire [1:0] setting_page;
 integer i,updates=0;
 always #5 clk=~clk;
 media_adjust_control #(.AUTOPLAY_MENU(1)) dut(.home_play(1'b0),.home_music_index(2'd0),.music_count(3'd0),.music_page(),.cfg_music_index(),.cfg_music_request(),.rtc_page(),.rtc_exit(1'b0),.frame_tick(1'b0),.held_key_n(4'hf),.contrast_index(),.autoplay_interval(),.*);
 task tick;begin @(negedge clk);#1;end endtask
 task press(input [3:0] key);begin key_press=key;tick;key_press=0;tick;end endtask
 always @(posedge clk)if(rst_n&&cfg_update)updates=updates+1;
 initial begin
  #1;rst_n=0;tick;rst_n=1;tick;
  if(cfg_autoplay)$fatal(1,"product default must be manual");
  press(8);press(1);press(2);press(1);press(2);press(1);press(2);press(1);press(2);
  if(!setting_active || !autoplay_page || cfg_value!=32 || cfg_gain_q8!=320 || !cfg_fade_enabled || !cfg_wave_enabled)$fatal(1,"fifth menu page/config persistence");
  press(1);if(!cfg_autoplay)$fatal(1,"AUTO on");
  press(4);if(cfg_autoplay)$fatal(1,"AUTO off");
  press(1);press(2);if(setting_active||!cfg_autoplay)$fatal(1,"OK exits AUTO retaining value");
  mode_change=1;product_mode=0;tick;mode_change=0;tick;
  if(cfg_autoplay || setting_active || cfg_value!=32 || cfg_gain_q8!=320 || !cfg_fade_enabled || !cfg_wave_enabled)$fatal(1,"mode entry reset unrelated picture settings");
  press(8);for(i=0;i<4;i=i+1)press(2);
  if(setting_active||autoplay_page)$fatal(1,"demo allowed editable autoplay page");
  mode_change=1;product_mode=1;tick;mode_change=0;tick;
  if(cfg_autoplay)$fatal(1,"re-entering product retained old autoplay");
  $display("PASS mode_menu: product defaults manual, fifth AUTO page, demo lock, mode entry resets only navigation/autoplay; updates=%0d",updates);$finish;
 end
endmodule
