`timescale 1ns/1ps
module tb_encoder_board;
 reg clk50=0,rst_n=1,sd_miso=1,mode_sw7=1;
 reg encoder_a=1,encoder_b=1,encoder_press_n=1;
 reg infrared_n=1;
 always #10 clk50=~clk50;
 reg [15:0] pressed=0;
 tri [3:0] key_col_n,key_row_n;
 wire [3:0] led;
 wire sd_sck,sd_mosi,sd_cs,hdmi_clk_p,hdmi_d0_p,hdmi_d1_p,hdmi_d2_p;
 dmz_keyboard_model keyboard_model(.*,.row_n(key_row_n),.col_n(key_col_n));
 wire rtc_scl,rtc_ce;tri0 rtc_sda;
 hdmi_media_board_top #(.FINE_ADJUST(0),.HOME_UI(0)) dut(.*);
 defparam dut.encoder.SAMPLE_CYCLES=2,dut.encoder.AB_SAMPLES=3;
 defparam dut.encoder.BUTTON_SAMPLES=4,dut.encoder.LONG_SAMPLES=200;
 defparam dut.keyboard.SCAN_CYCLES=4,dut.keys.COUNT=8,dut.mode_control.DEBOUNCE_CYCLES=8;
 task cycles(input integer n);begin repeat(n)@(negedge dut.sys_clk);#2;end endtask
 task phase(input [1:0] v);begin {encoder_a,encoder_b}=v;cycles(20);end endtask
 task cw;begin phase(2'b10);phase(2'b00);phase(2'b01);phase(2'b11);end endtask
 task ccw;begin phase(2'b01);phase(2'b00);phase(2'b10);phase(2'b11);end endtask
 task click;begin encoder_press_n=0;cycles(40);encoder_press_n=1;cycles(40);end endtask
 task long_press;begin encoder_press_n=0;cycles(450);encoder_press_n=1;cycles(40);end endtask
 integer before_next,before_prev;
 initial begin
  dut.u_pll.lock_enable=1;#1;rst_n=0;dut.u_pll.lock_enable=0;
  cycles(8);rst_n=1;cycles(8);dut.u_pll.lock_enable=1;cycles(500);
  if(!dut.product_mode||dut.mode_switching||dut.setting_active)$fatal(1,"board boot product=%b switching=%b setting=%b reset=%b flush=%b idle=%b state=%d",dut.product_mode,dut.mode_switching,dut.setting_active,dut.core_rst_n,dut.audio_flush_done,dut.wav_idle,dut.mode_control.state);
  before_next=dut.u_player.next_events;before_prev=dut.u_player.prev_events;
  cw;ccw;
  if(dut.u_player.next_events!=before_next+1 || dut.u_player.prev_events!=before_prev+1)
   $fatal(1,"encoder gallery directions");
  click;if(!dut.paused)$fatal(1,"encoder short pause");click;if(dut.paused)$fatal(1,"encoder short resume");
  long_press;if(!dut.setting_active||dut.setting_page!=0)$fatal(1,"long settings entry or release also OK");
  cw;if(dut.brightness_value!=32)$fatal(1,"brightness right");ccw;if(dut.brightness_value!=0)$fatal(1,"brightness left");
  click;cw;if(dut.gain_q8_value!=320)$fatal(1,"contrast");
  click;cw;if(!dut.fade_enabled_value)$fatal(1,"fade");
  click;cw;if(!dut.wave_enabled_value)$fatal(1,"FFT toggle");
  click;cw;if(!dut.u_player.auto_enable)$fatal(1,"AUTO on");ccw;if(dut.u_player.auto_enable)$fatal(1,"AUTO off");
  click;if(!dut.music_page)$fatal(1,"music row unreachable");
  ccw;cycles(80);if(dut.active_music_index!=3||!dut.music_page)$fatal(1,"previous song wrap/focus");
  cw;cycles(80);if(dut.active_music_index!=0||!dut.music_page)$fatal(1,"next song wrap/focus");
  click;if(!dut.rtc_page)$fatal(1,"clock page unreachable after music");
  cw;if(dut.rtc_draft!=48'h010101000000)$fatal(1,"encoder clock year adjustment");
  click;ccw;if(dut.rtc_draft!=48'h011201000000)$fatal(1,"encoder clock month adjustment");
  long_press;if(dut.setting_active||dut.rtc_request)$fatal(1,"clock cancel wrote RTC or failed to exit");
  if(dut.u_player.next_events!=before_next+1 || dut.u_player.prev_events!=before_prev+1)
   $fatal(1,"menu rotation leaked into gallery");
  long_press;if(!dut.setting_active)$fatal(1,"reopen");
  long_press;if(dut.setting_active||dut.paused)$fatal(1,"long return or stray release pause");
  // Physical keys keep their original paths with the new input connected.
  pressed=16'h0010;cycles(160);pressed=0;cycles(160);
  if(!dut.setting_active)$fatal(1,"KEY4 regression");
  pressed=16'h0004;cycles(160);pressed=0;cycles(160);
  if(dut.setting_page!=1)$fatal(1,"KEY2 regression");
  // Held press across a real SW7 mode change must be cancelled until release.
  encoder_press_n=0;cycles(30);mode_sw7=0;cycles(500);
  encoder_press_n=1;cycles(80);
  if(dut.setting_active||dut.paused||dut.product_mode||!dut.u_player.auto_enable)$fatal(1,"mode-switch held gesture");
  mode_sw7=1;cycles(500);
  if(dut.setting_active||dut.paused||!dut.product_mode||dut.u_player.auto_enable)$fatal(1,"product recovery");
  click;if(!dut.paused)$fatal(1,"short press did not rearm");
  $display("PASS encoder board: real decoder/matrix/keys/mode/menu; gallery, pause, six settings, four-song wrap, long return, physical-key preservation, SW7 held gesture");$finish;
 end
 initial begin #10000000;$fatal(1,"encoder board timeout");end
endmodule
