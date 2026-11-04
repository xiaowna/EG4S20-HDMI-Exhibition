`timescale 1ns/1ps
module tb_home_board;
 parameter FINE_ADJUST=0;
 localparam EXPECT_BRIGHT=FINE_ADJUST?1:32,EXPECT_GAIN=FINE_ADJUST?259:320;
 reg clk50=0,rst_n=1,sd_miso=1,mode_sw7=1;
 reg infrared_n=1;
 always #10 clk50=~clk50;
 reg [15:0] pressed=0;
 tri [3:0] key_col_n,key_row_n;wire rtc_scl,rtc_ce;tri0 rtc_sda;
 wire [3:0] led;
 wire sd_sck,sd_mosi,sd_cs,hdmi_clk_p,hdmi_d0_p,hdmi_d1_p,hdmi_d2_p;
 dmz_keyboard_model keyboard_model(.*,.row_n(key_row_n),.col_n(key_col_n));
 hdmi_media_board_top #(.FINE_ADJUST(FINE_ADJUST),.VIEW_3D(0)) dut(.*);
 defparam dut.keyboard.SCAN_CYCLES=4,dut.keys.COUNT=8,dut.mode_control.DEBOUNCE_CYCLES=8;
 task cycles(input integer n);begin repeat(n)@(negedge dut.sys_clk);#2;end endtask
 task tap(input integer k);begin pressed=1<<k;cycles(160);pressed=0;cycles(160);end endtask
 task frame_tick;begin dut.u_player.mock_vsync=0;cycles(10);dut.u_player.mock_vsync=1;cycles(10);end endtask
 integer plays=0,first=-1,lim=-1,song=-1;
 always @(posedge dut.sys_clk)if(dut.home_play)begin
  plays<=plays+1;first<=dut.u_player.album_first;lim<=dut.u_player.album_limit;song<=dut.requested_music;
 end
 initial begin
  dut.u_pll.lock_enable=1;#1;rst_n=0;dut.u_pll.lock_enable=0;
  cycles(8);rst_n=1;cycles(8);dut.u_pll.lock_enable=1;cycles(500);
  dut.u_player.mock_catalog_ready=1;dut.u_player.mock_image_count=24;
  if(!dut.home_visible||dut.av.audio_enable||dut.u_player.auto_enable||dut.u_player.wav_enable)$fatal(1,"home startup source gates");
  tap(1);repeat(19)frame_tick();cycles(2);
  if(dut.home_index!=1||dut.u_player.next_events||dut.paused)$fatal(1,"KEY1 leaked into player");
  tap(1);repeat(19)frame_tick();cycles(2);
  if(dut.home_index!=2||dut.u_player.next_events)$fatal(1,"second physical KEY1 home navigation");
  tap(4);tap(1);tap(2);tap(1);
  if(!dut.setting_active||dut.brightness_value!=EXPECT_BRIGHT||dut.gain_q8_value!=EXPECT_GAIN)$fatal(1,"home settings control");
  tap(4);tap(2);cycles(100);
  if(plays!=1||first!=12||lim!=18||song!=2||dut.active_music_index!=2||!dut.home_starting||dut.av.audio_enable)$fatal(1,"selected column range/music/gates first=%0d lim=%0d music=%0d",first,lim,song);
  dut.u_player.mock_album_ready=1;cycles(20);repeat(19)frame_tick();cycles(4);
  if(dut.home_visible||!dut.u_player.auto_enable||!dut.av.audio_enable||dut.paused||!dut.u_player.wav_enable||dut.cfg_music_index!=2)$fatal(1,"album autoplay/audio release/menu song");
  tap(1);tap(3);tap(2);
  if(dut.u_player.next_events!=1||dut.u_player.prev_events!=1||!dut.paused||dut.av.audio_enable)$fatal(1,"album key controls");
  repeat(3)begin
   tap(4);if(!dut.setting_active)$fatal(1,"album settings did not open");
   tap(4);repeat(20)frame_tick();cycles(3);
   if(dut.setting_active||dut.home_visible||dut.home_starting||!dut.paused||dut.av.audio_enable||!dut.u_player.auto_enable)
    $fatal(1,"KEY4 menu exit must retain paused album instead of returning home");
   if(plays!=1||dut.home_index!=2||dut.active_music_index!=2||dut.cfg_music_index!=2||
      dut.brightness_value!=EXPECT_BRIGHT||dut.gain_q8_value!=EXPECT_GAIN||dut.u_player.next_events!=1||dut.u_player.prev_events!=1)
    $fatal(1,"menu exit restarted album/music or changed controls/settings");
  end
  tap(2);tap(1);
  if(dut.paused||!dut.av.audio_enable||dut.u_player.next_events!=2)$fatal(1,"album controls did not resume after menu exit");
  tap(4);repeat(6)tap(2);
  if(!dut.rtc_page||!dut.setting_active)$fatal(1,"RTC editor entry");
  tap(4);repeat(20)frame_tick();cycles(3);
  if(dut.setting_active||dut.home_visible||dut.home_starting||!dut.av.audio_enable||plays!=1)
   $fatal(1,"RTC cancel must return to playing album");
  mode_sw7=0;cycles(500);
  if(dut.home_visible||dut.product_mode||!dut.u_player.auto_enable||!dut.av.force_tone||!dut.av.audio_enable)$fatal(1,"demo mode changed");
  mode_sw7=1;cycles(500);
  if(!dut.home_visible||dut.home_index!=2||dut.av.force_tone)$fatal(1,"product home recovery");
  $display("PASS home production top: real KEY/mode/settings, repeated KEY4/RTC exits retain album, pause/music/settings preservation, player commands and SW7");$finish;
 end
 initial begin #3000000;$fatal(1,"home board timeout");end
endmodule
