`timescale 1ns/1ps
module tb_return_home;
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
 task enter;begin tap(2);cycles(100);dut.u_player.mock_album_ready=1;cycles(50);repeat(19)frame_tick();cycles(4);end endtask
 integer plays=0;always @(posedge dut.sys_clk)if(dut.home_play)plays++;
 initial begin
  dut.u_pll.lock_enable=1;#1;rst_n=0;dut.u_pll.lock_enable=0;
  cycles(8);rst_n=1;cycles(8);dut.u_pll.lock_enable=1;cycles(500);
  dut.u_player.mock_catalog_ready=1;dut.u_player.mock_image_count=24;

  enter();if(dut.home_visible)$fatal(1,"album entry failed");
  tap(2);tap(4);tap(1);tap(4);
  if(!dut.paused||dut.brightness_value!=1||dut.home_visible)$fatal(1,"preconditions/KEY4 return changed");
  tap(0);
  if(!dut.home_visible||dut.home_starting||dut.view_active||dut.setting_active||dut.av.audio_enable||dut.u_player.auto_enable)
   $fatal(1,"KEY0 did not return to idle home from album");
  if(!dut.paused||dut.brightness_value!=1||plays!=1||dut.home_index!=0)$fatal(1,"return reset settings or restarted album");
  // Holding HOME must not confirm or advance the selected card.
  pressed=1;cycles(800);repeat(20)frame_tick();pressed=0;cycles(160);
  if(!dut.home_visible||plays!=1||dut.home_index!=0)$fatal(1,"held HOME leaked a command");
  enter();tap(4);repeat(6)tap(2);
  if(!dut.rtc_page)$fatal(1,"RTC entry failed");
  force dut.rtc_busy=1;tap(0);
  if(!dut.rtc_page||dut.home_visible)$fatal(1,"HOME cancelled a live RTC write");
  release dut.rtc_busy;
  tap(0);if(!dut.home_visible||dut.setting_active||dut.rtc_request)$fatal(1,"HOME must cancel unsaved RTC edit");
  // Reopen cube, then return even from an open settings overlay.
  tap(3);repeat(19)frame_tick();cycles(3);enter();
  if(!dut.view_active||dut.home_visible||dut.home_index!=4)$fatal(1,"cube entry failed");
  tap(9);tap(4);tap(0);
  if(!dut.home_visible||dut.view_active||dut.setting_active||dut.av.scene_enable||dut.home_index!=4)$fatal(1,"HOME from cube settings failed");
  // A still-loading album is cancellable, without another IO launch.
  tap(1);repeat(19)frame_tick();dut.u_player.mock_album_ready=0;tap(2);cycles(100);
  if(!dut.home_starting)$fatal(1,"WAIT setup failed");
  tap(0);if(!dut.home_visible||dut.home_starting||dut.home_word[10])$fatal(1,"HOME failed to cancel WAIT");
  // HOME and another key together remain rejected by the matrix guard.
  pressed=3;cycles(200);pressed=2;cycles(200);pressed=0;cycles(200);
  if(dut.home_index!=0||dut.home_word[10])$fatal(1,"HOME ghost pair rearmed a held direction");
  mode_sw7=0;cycles(700);tap(0);if(dut.home_visible||dut.product_mode)$fatal(1,"HOME changed demo mode");
  $display("PASS KEY0 return: physical matrix/debounce, album/pause/settings/RTC/cube/WAIT, held/ghost guards, preserved selection/settings and demo isolation");$finish;
 end
 initial begin #5000000;$fatal(1,"return home timeout");end
endmodule
