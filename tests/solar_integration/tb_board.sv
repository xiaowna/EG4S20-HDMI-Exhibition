`timescale 1ns/1ps
// Real scanner/debounce/encoder/menu/mode/home/solar controls; peripheral models
// isolate the command ownership checks from card and HDMI algorithms.
module tb_solar_board_controls;
 reg clk50=0,rst_n=1,sd_miso=1,mode_sw7=1;
 reg encoder_a=1,encoder_b=1,encoder_press_n=1,infrared_n=1;
 always #10 clk50=~clk50;
 reg [15:0] pressed=0;
 tri [3:0] key_col_n,key_row_n;wire rtc_scl,rtc_ce;tri0 rtc_sda;
 wire [3:0] led;wire sd_sck,sd_mosi,sd_cs,hdmi_clk_p,hdmi_d0_p,hdmi_d1_p,hdmi_d2_p;
 dmz_keyboard_model model(.*,.row_n(key_row_n),.col_n(key_col_n));
 hdmi_media_board_top dut(.*);
 defparam dut.keyboard.SCAN_CYCLES=4,dut.keys.COUNT=8,dut.mode_control.DEBOUNCE_CYCLES=8;
 task cycles(input integer n);begin repeat(n)@(negedge dut.sys_clk);#2;end endtask
 task tap(input integer k);begin pressed=1<<k;cycles(160);pressed=0;cycles(160);end endtask
 task frame_tick;begin dut.u_player.mock_vsync=0;cycles(10);dut.u_player.mock_vsync=1;cycles(10);end endtask
 reg [6:0] old_rate,old_pitch;integer plays=0;
 always @(posedge dut.sys_clk)if(dut.home_play)plays=plays+1;
 initial begin
  dut.u_pll.lock_enable=1;#1;rst_n=0;dut.u_pll.lock_enable=0;
  cycles(8);rst_n=1;cycles(8);dut.u_pll.lock_enable=1;cycles(500);
  dut.u_player.mock_catalog_ready=1;dut.u_player.mock_image_count=24;
  if(!dut.home_visible||dut.home_word[13])$fatal(1,"production themed home should be the welcome screen");
  tap(5);tap(7);tap(8);
  if(dut.scene_mode||dut.scene_zoom!=1)$fatal(1,"scene keys acted on home");
  tap(4);if(!dut.setting_active)$fatal(1,"home settings should open directly");
  tap(4);if(dut.setting_active||dut.home_index!=0||plays!=0)$fatal(1,"home settings close");
  tap(3);repeat(19)frame_tick();cycles(2);
  if(dut.home_index!=4||dut.u_player.next_events||dut.u_player.prev_events)$fatal(1,"solar navigation leaked to media");
  tap(2);cycles(100);repeat(19)frame_tick();cycles(3);
  if(!dut.view_active||dut.home_visible||dut.home_starting||plays!=1||dut.paused)$fatal(1,"solar entry failed");
  tap(7);tap(8);if(dut.scene_zoom!=1)$fatal(1,"solar zoom should remain at default");
  tap(5);if(!dut.scene_mode||dut.scene_zoom!=1)$fatal(1,"KEY5 Earth-Moon entry");
  tap(7);tap(7);if(dut.scene_zoom!=0)$fatal(1,"KEY7 minimum zoom clamp");
  tap(8);tap(8);tap(8);if(dut.scene_zoom!=2)$fatal(1,"KEY8 maximum zoom clamp");
  tap(9);tap(14);tap(10);
  if(!dut.scene_mode||dut.scene_zoom!=1||dut.view_yaw!=0||dut.view_pitch!=27)$fatal(1,"KEY10 should reset view and zoom, retaining Earth-Moon");
  old_rate=dut.view_pitch[2:0];tap(1);
  if(dut.view_pitch[2:0]!=old_rate+1||dut.u_player.next_events||dut.paused)$fatal(1,"solar KEY1 leaked or did not increase speed");
  old_pitch=dut.view_pitch;tap(2);
  if(dut.view_pitch[6:3]==old_pitch[6:3]||dut.paused||dut.pause_press)$fatal(1,"solar KEY2 should toggle view without pausing audio");
  old_rate=dut.view_pitch[2:0];tap(3);
  if(dut.view_pitch[2:0]!=old_rate-1||dut.u_player.prev_events||dut.paused)$fatal(1,"solar KEY3 leaked or did not decrease speed");
  old_rate=dut.view_yaw;tap(9);if(dut.view_yaw!=old_rate+1)$fatal(1,"KEY9 camera right");
  tap(11);if(dut.view_yaw!=old_rate)$fatal(1,"KEY11 camera left");
  old_pitch=dut.view_pitch;tap(14);if(dut.view_pitch[6:3]!=old_pitch[6:3]+1)$fatal(1,"KEY14 camera up");
  tap(6);if(dut.view_pitch!=old_pitch)$fatal(1,"KEY6 camera down");
  old_rate=dut.view_yaw;old_pitch=dut.view_pitch;tap(4);
  if(!dut.setting_active||!dut.view_active)$fatal(1,"solar KEY4 did not open settings");
  tap(5);tap(7);tap(8);
  if(!dut.scene_mode||dut.scene_zoom!=1)$fatal(1,"settings leaked scene controls");
  tap(1);
  if(dut.brightness_value!=1||dut.view_yaw!=old_rate||dut.view_pitch!=old_pitch)$fatal(1,"settings event leaked into solar controls");
  tap(4);repeat(20)frame_tick();cycles(3);
  if(dut.setting_active||!dut.view_active||dut.home_visible||dut.view_yaw!=old_rate||dut.view_pitch!=old_pitch||plays!=1)
   $fatal(1,"KEY4 closing settings lost solar page or state");
  tap(5);if(dut.scene_mode||dut.scene_zoom!=1)$fatal(1,"KEY5 return to solar");
  tap(0);
  if(!dut.home_visible||dut.view_active||dut.home_word[13]||dut.av.scene_enable||dut.home_index!=4)
   $fatal(1,"KEY0 did not return to carousel without cover");
  mode_sw7=0;cycles(700);
  if(dut.home_visible||dut.view_active||dut.product_mode)$fatal(1,"solar content survived demo mode exit");
  mode_sw7=1;cycles(700);
  if(!dut.home_visible||dut.home_word[13]||dut.home_index!=4||plays!=1)$fatal(1,"product return reopened cover or scene");
  $display("PASS solar/Earth-Moon production controls: KEY5 mode, KEY7/8 clamp, KEY10 reset; home/settings isolation, original directions/speed/view, KEY0 and SW7");$finish;
 end
 initial begin #3000000;$fatal(1,"solar board control timeout");end
endmodule
