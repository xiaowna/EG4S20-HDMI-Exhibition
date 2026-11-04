`timescale 1ns/1ps
module tb_cube_board;
 reg clk50=0,rst_n=1,sd_miso=1,mode_sw7=1;
 reg encoder_a=1,encoder_b=1,encoder_press_n=1,infrared_n=1;
 always #10 clk50=~clk50;
 reg [15:0] pressed=0;
 tri [3:0] key_col_n,key_row_n;wire rtc_scl,rtc_ce;tri0 rtc_sda;
 wire [3:0] led;wire sd_sck,sd_mosi,sd_cs,hdmi_clk_p,hdmi_d0_p,hdmi_d1_p,hdmi_d2_p;
 dmz_keyboard_model keyboard_model(.*,.row_n(key_row_n),.col_n(key_col_n));
 hdmi_media_board_top #(.FINE_ADJUST(0)) dut(.*);
 defparam dut.keyboard.SCAN_CYCLES=4,dut.keys.COUNT=8,dut.mode_control.DEBOUNCE_CYCLES=8;
 task cycles(input integer n);begin repeat(n)@(negedge dut.sys_clk);#2;end endtask
 task tap(input integer k);begin pressed=1<<k;cycles(160);pressed=0;cycles(160);end endtask
 task frame_tick;begin dut.u_player.mock_vsync=0;cycles(10);dut.u_player.mock_vsync=1;cycles(10);end endtask
 integer album_requests=0;reg [6:0] saved_yaw,saved_pitch;
 always @(posedge dut.sys_clk)if(dut.u_player.album_request)album_requests++;
 initial begin
  dut.u_pll.lock_enable=1;#1;rst_n=0;dut.u_pll.lock_enable=0;
  cycles(8);rst_n=1;cycles(8);dut.u_pll.lock_enable=1;cycles(500);
  dut.u_player.mock_catalog_ready=0;dut.u_player.mock_image_count=0;dut.u_player.mock_album_error=1;
  tap(3);repeat(19)frame_tick();cycles(2);
  if(dut.home_index!=4)$fatal(1,"fifth home card");
  tap(2);cycles(300);repeat(19)frame_tick();cycles(4);
  if(dut.home_visible||!dut.view_active||!dut.av.scene_enable||!dut.av.audio_only||album_requests||dut.u_player.auto_enable)
   $fatal(1,"3D must open without TF/BMP and bypass album errors/autoplay");
  if(dut.view_yaw!=12||dut.view_pitch!=10)$fatal(1,"initial cube pose");
  tap(9);if(dut.view_yaw!=13)$fatal(1,"physical KEY9 right");
  tap(11);if(dut.view_yaw!=12)$fatal(1,"physical KEY11 left");
  tap(14);if(dut.view_pitch!=11)$fatal(1,"physical KEY14 up");
  tap(6);if(dut.view_pitch!=10)$fatal(1,"physical KEY6 down");
  pressed=1<<9;cycles(160);repeat(18)frame_tick();pressed=0;cycles(160);
  if(dut.view_yaw<15)$fatal(1,"direction hold repeat");
  saved_yaw=dut.view_yaw;saved_pitch=dut.view_pitch;
  tap(4);if(!dut.setting_active)$fatal(1,"settings opens on cube");
  tap(14);tap(10);repeat(16)frame_tick();
  if(dut.view_yaw!=saved_yaw||dut.view_pitch!=saved_pitch)$fatal(1,"menu must preserve cube pose and block rotation/reset");
  tap(4);repeat(20)frame_tick();cycles(4);
  if(dut.setting_active||dut.home_visible||!dut.view_active||!dut.av.scene_enable)
   $fatal(1,"closing settings must return to cube instead of home");
  if(dut.view_yaw!=saved_yaw||dut.view_pitch!=saved_pitch)$fatal(1,"menu exit changed cube pose");
  tap(9);tap(14);tap(10);
  if(dut.view_yaw!=12||dut.view_pitch!=10)$fatal(1,"KEY10 reset pose");
  tap(1);tap(3);
  if(dut.u_player.next_events||dut.u_player.prev_events||album_requests)$fatal(1,"3D controls leaked to image player");
  mode_sw7=0;cycles(1000);
  if(dut.view_active||dut.av.scene_enable||!dut.u_player.auto_enable)$fatal(1,"SW7 demo source unchanged");
  $display("PASS cube board: fifth card without TF, five physical keys, held rotation, menu pose preservation, image isolation, SW7");$finish;
 end
 initial begin #3000000;$fatal(1,"cube board timeout");end
endmodule
