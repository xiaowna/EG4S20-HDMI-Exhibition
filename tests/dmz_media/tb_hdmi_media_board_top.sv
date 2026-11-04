`timescale 1ns/1ps
// Behavior models isolate board-level wiring and controls from media algorithms.
// Compile the production top with the real matrix scanner/debounce/control RTL.
module board_pll(input wire refclk,reset,output wire extlock,
 output reg clk0_out,clk1_out,clk2_out);
 reg lock_enable=0;
 initial begin clk0_out=0;clk1_out=0;clk2_out=0;end
 assign extlock=lock_enable&&!reset;
 always #20 clk0_out=~clk0_out;
 always #4 clk1_out=~clk1_out;
 always #10 clk2_out=~clk2_out;
endmodule
module sd_media_player #(parameter MODE_CONTROL=0,ALBUMS=0,MAX_IMAGES=4,
 parameter INDEX_BITS=(MAX_IMAGES>1)?$clog2(MAX_IMAGES):1,COUNT_BITS=$clog2(MAX_IMAGES+1),SLIDE_TRANSITIONS=0,MAX_WAVS=1,INTRO_ANIMATION=0)(
 input wire clk,pix_clk,rst_n,sd_miso,next_pulse,prev_pulse,pause,audio_urgent,wav_ready,
 output wire sd_sck,sd_mosi,sd_cs,de,hsync,vsync,
 output wire [23:0] rgb,
 output wire card_ready,card_error,sdram_ready,memory_fault,prefetch_error,
 output wire frame_underflow,loading,image_error,
 output wire [COUNT_BITS-1:0] image_count,
 output wire [INDEX_BITS-1:0] image_index,display_index,
 output wire wav_valid,wav_playing,wav_error,video_started,catalog_ready,wav_found,
 output wire [47:0] wav_data,
 output wire display_valid,audio_only,transition_active,input wire transition_ready,
 input wire auto_enable,wav_enable,output wire wav_idle,slide_transition,
 input wire [1:0] wav_index,output wire [2:0] wav_count,
 input wire album_request,album_enable,input wire [INDEX_BITS-1:0] album_first,
 input wire [COUNT_BITS-1:0] album_limit,output wire album_ready,album_error,preparing,output wire [6:0] prepare_pixels,
 input wire intro_enable,intro_pause,output wire [24:0] folder_info);
 assign folder_info=0;
 reg mock_preparing=0;reg [6:0] mock_prepare_pixels=0;
 assign preparing=mock_preparing;assign prepare_pixels=mock_prepare_pixels;
 reg mock_album_ready=0,mock_album_error=0,mock_vsync=1,mock_catalog_ready=0;
 reg [COUNT_BITS-1:0] mock_image_count=0;
 assign album_ready=ALBUMS&&mock_album_ready;assign album_error=ALBUMS&&mock_album_error;
 assign wav_count=4;
 assign wav_idle=1'b1;
 reg [2:0] mock_status=0;
 reg [5:0] mock_faults=0;
 reg mock_transition=0;
 reg mock_slide=0;
 reg [31:0] next_events,prev_events;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin next_events<=0;prev_events<=0;end else begin
   if(next_pulse)next_events<=next_events+1;
   if(prev_pulse)prev_events<=prev_events+1;
  end
 assign {loading,card_ready,sdram_ready}=rst_n?mock_status:3'b000;
 assign {card_error,wav_error,image_error,frame_underflow,prefetch_error,memory_fault}=
  rst_n?mock_faults:6'b000000;
 assign {sd_cs,sd_mosi,sd_sck}=3'b110;
 assign {de,hsync}=2'b01;assign vsync=ALBUMS?mock_vsync:1'b1;
 assign rgb=0;
 assign image_count=ALBUMS?mock_image_count:0;
 assign image_index=0;
 assign display_index=0;
 assign {wav_valid,wav_playing,video_started,wav_found,display_valid,audio_only}=0;
 assign catalog_ready=ALBUMS&&mock_catalog_ready;
 assign wav_data=0;
 assign transition_active=mock_transition;
 assign slide_transition=SLIDE_TRANSITIONS&&mock_slide;
endmodule
module hdmi_av_output #(parameter SETTINGS_UI=0,parameter MODE_CONTROL=0,parameter CHINESE_SUBTITLE=0,parameter CHINESE_SETTINGS=0,parameter SPECTRUM_FFT=0,parameter MUSIC_MENU=0,parameter RTC_OVERLAY=0,parameter RTC_SETTING=0,parameter HOME_UI=0,parameter VIEW_3D=0,parameter FINE_ADJUST=0,parameter PREPARE_UI=0,parameter MUSIC_TOAST=0,
 parameter MAX_IMAGES=4,INDEX_BITS=(MAX_IMAGES>1)?$clog2(MAX_IMAGES):1,COUNT_BITS=$clog2(MAX_IMAGES+1))(
 input wire sys_clk,pix_clk,rst_n,audio_enable,
 input wire [2:0] tone_sel,input wire [COUNT_BITS-1:0] image_count,
 input wire [INDEX_BITS-1:0] image_index,
 input wire image_valid,audio_only,wav_valid,wav_playing,video_started,catalog_ready,wav_found,wav_error,
 input wire [47:0] wav_data,
 input wire de,hsync,vsync,
 input wire [23:0] rgb,
 input wire signed [8:0] brightness,
 input wire [8:0] gain_q8,
 input wire loading,fade_enabled,wave_enabled,
 input wire [10:0] settings_word,output wire transition_ready,
 output wire wav_ready,audio_fault,audio_urgent,
 output wire [9:0] red,green,blue,
 input wire force_tone,audio_flush_request,input wire [3:0] mode_status,
 output wire audio_flush_done,input wire [7:0] music_status,input wire [48:0] rtc_word,input wire [53:0] rtc_edit_word,input wire [14:0] home_word,input wire scene_enable,input wire [6:0] scene_yaw,scene_pitch,output wire scene_ready,input wire [14:0] fine_adjust_word,input wire [9:0] prepare_word,input wire easter_toggle,input wire scene_mode,input wire [1:0] scene_zoom);
 assign scene_ready=1;
 reg [1:0] mock_flush=0;
 always @(posedge sys_clk or negedge rst_n)
  if(!rst_n)mock_flush<=0;else mock_flush<={mock_flush[0],audio_flush_request};
 assign audio_flush_done=mock_flush[1];
 reg mock_audio_fault=0;
 assign audio_fault=rst_n&&mock_audio_fault;
 assign audio_urgent=0;
 assign transition_ready=loading;
 assign wav_ready=rst_n&&audio_enable;
 assign {red,green,blue}=0;
endmodule
module tmds_ddr_tx(input wire pix_clk,ser_clk,rst_n,
 input wire [9:0] red,green,blue,
 output wire clk_p,d0_p,d1_p,d2_p);
 assign clk_p=rst_n&&pix_clk;
 assign {d2_p,d1_p,d0_p}=rst_n?{red[0],green[0],blue[0]}:3'b000;
endmodule
module tb_hdmi_media_board_top;
 parameter integer COUNT=32;
 localparam integer SCAN_CYCLES=4,SETTLE=COUNT+12+8*SCAN_CYCLES;
 reg clk50=0,rst_n=1,sd_miso=1,mode_sw7=0;
 reg encoder_a=1,encoder_b=1,encoder_press_n=1;
 reg infrared_n=1;
 reg [15:0] pressed=0;
 always #10 clk50=~clk50;
 tri [3:0] key_row_n,key_col_n;
 wire sd_sck,sd_mosi,sd_cs,hdmi_clk_p,hdmi_d0_p,hdmi_d1_p,hdmi_d2_p;
 wire [3:0] led;
 dmz_keyboard_model keyboard_model(.*,.row_n(key_row_n),.col_n(key_col_n));
 wire rtc_scl,rtc_ce;tri0 rtc_sda;
 hdmi_media_board_top #(.FINE_ADJUST(0),.HOME_UI(0)) dut(.*);
 defparam dut.keys.COUNT=COUNT;
 defparam dut.mode_control.DEBOUNCE_CYCLES=COUNT;
 defparam dut.keyboard.SCAN_CYCLES=SCAN_CYCLES;
 integer pause_events=0,config_events=0,i;
 always @(negedge dut.sys_clk)if(dut.core_rst_n)begin
  if(dut.pause_press)pause_events=pause_events+1;
  if(dut.adjust_controls.cfg_update)config_events=config_events+1;
 end
 task cycles(input integer n);begin repeat(n)@(negedge dut.sys_clk);#1;end endtask
 task tap(input integer n);begin pressed=16'b1<<n;cycles(SETTLE);pressed=0;cycles(SETTLE);end endtask
 task check_stopped;begin #1;
  if(dut.core_rst_n!==0 || dut.paused!==0 || led!==0 || dut.miso1!==1 || dut.miso2!==1 ||
     dut.brightness_value!==0 || dut.gain_q8_value!==256 || dut.fade_enabled_value!==0 || dut.wave_enabled_value!==0)
   $fatal(1,"reset/PLL lock loss changed defaults");
 end endtask
 task release_core;integer n;begin
  for(n=0;n<4;n=n+1)begin @(negedge dut.pix_clk);#1;
   if(dut.core_rst_n!==(n==3))$fatal(1,"reset release must take four falling pixel edges");
  end
 end endtask
 task check_play(input integer n,p,q,input bit paused);begin
  if(dut.u_player.next_events!=n || dut.u_player.prev_events!=p || pause_events!=q ||
     dut.paused!==paused || dut.u_player.pause!==paused || dut.av.audio_enable!==!paused)
   $fatal(1,"board event wiring next=%0d prev=%0d pause=%0d paused=%b",dut.u_player.next_events,dut.u_player.prev_events,pause_events,dut.paused);
 end endtask
 initial begin
  dut.u_pll.lock_enable=1;#1;rst_n=0;dut.u_pll.lock_enable=0;check_stopped;
  #25;@(posedge dut.pix_clk);#3;rst_n=1;cycles(16);check_stopped;
  @(posedge dut.pix_clk);#3;dut.u_pll.lock_enable=1;release_core;cycles(SETTLE);
  check_play(0,0,0,0);
  if(dut.av.tone_sel!==2 || dut.av.SETTINGS_UI!=1)$fatal(1,"tone or UI not enabled");
  @(negedge dut.sys_clk);sd_miso=0;
  @(posedge dut.sys_clk);#1;if(dut.miso1!==0 || dut.miso2!==1 || dut.u_player.sd_miso!==1)$fatal(1,"MISO first stage");
  @(posedge dut.sys_clk);#1;if(dut.miso2!==0 || dut.u_player.sd_miso!==0)$fatal(1,"MISO second stage");
  @(negedge dut.sys_clk);sd_miso=1;
  dut.u_player.mock_status=7;#1;if(led!==7)$fatal(1,"status LED mapping");
  if(dut.av.loading!==0)$fatal(1,"background reads incorrectly drive fade");
  @(negedge dut.sys_clk);dut.u_player.mock_transition=1;#1;
  if(dut.av.loading!==1)$fatal(1,"prepared transition not wired to fade");
  @(posedge dut.sys_clk);#1;if(dut.u_player.transition_ready!==0)$fatal(1,"fade ack bypassed first CDC stage");
  @(posedge dut.sys_clk);#1;if(dut.u_player.transition_ready!==1)$fatal(1,"fade ack missing second CDC stage");
  @(negedge dut.sys_clk);dut.u_player.mock_transition=0;cycles(3);
  if(dut.u_player.transition_ready!==0)$fatal(1,"fade ack did not clear");
  for(i=0;i<6;i=i+1)begin dut.u_player.mock_faults=1<<i;#1;if(led!==15)$fatal(1,"fault LED mapping");end
  dut.u_player.mock_faults=0;dut.av.mock_audio_fault=1;#1;if(led!==15)$fatal(1,"audio fault LED");
  dut.av.mock_audio_fault=0;dut.u_player.mock_status=0;
  tap(0);check_play(0,0,0,0); // KEY0 is unused.
  tap(1);tap(3);tap(2);check_play(1,1,1,1);
  pressed=2;cycles(SETTLE*3);check_play(2,1,1,1);pressed=0;cycles(SETTLE);
  // Any two-key chord is blocked until every physical contact is released.
  pressed=16'h0012;cycles(SETTLE);pressed=2;cycles(SETTLE);check_play(2,1,1,1);
  pressed=0;cycles(SETTLE);
  tap(4);if(!dut.setting_active || dut.setting_page!=0 || !dut.av.settings_word[10])$fatal(1,"KEY4/UI menu entry");
  tap(1);if(dut.av.brightness!==32 || dut.av.settings_word[7:5]!==3)$fatal(1,"brightness menu/wiring");
  tap(3);if(dut.av.brightness!==0)$fatal(1,"left brightness");
  tap(2);tap(1);if(dut.av.gain_q8!==320 || dut.av.settings_word[4:2]!==3)$fatal(1,"contrast menu/wiring");
  tap(2);tap(1);if(!dut.av.fade_enabled)$fatal(1,"fade wiring");
  // A manual slide keeps the image bright; AUTO still uses the menu fade.
  dut.u_player.mock_transition=1;dut.u_player.mock_slide=1;#1;
  if(dut.av.loading || dut.av.fade_enabled || dut.av.audio_enable!==!dut.paused)
   $fatal(1,"manual slide must mask fade without changing pause/audio");
  dut.u_player.mock_slide=0;#1;
  if(!dut.av.loading || !dut.av.fade_enabled)$fatal(1,"automatic fade was disabled by slide wiring");
  dut.u_player.mock_transition=0;
  tap(2);tap(1);if(!dut.av.wave_enabled)$fatal(1,"wave wiring");
  check_play(2,1,1,1);
  tap(4);if(dut.setting_active)$fatal(1,"KEY4 menu exit");
  tap(2);check_play(2,1,2,0);
  if(dut.av.gain_q8!==320 || !dut.av.fade_enabled || !dut.av.wave_enabled)$fatal(1,"settings persistence");
  // A key held across reset produces exactly one action after a full scan/debounce.
  @(posedge dut.pix_clk);#3;rst_n=0;pressed=16'h0010;check_stopped;
  #25;@(posedge dut.pix_clk);#3;rst_n=1;release_core;cycles(SETTLE*2);
  if(!dut.setting_active || dut.setting_page!=0)$fatal(1,"held KEY4 reset");
  pressed=0;cycles(SETTLE);tap(4);
  #3;dut.u_pll.lock_enable=0;check_stopped;
  cycles(8);@(posedge dut.pix_clk);#3;dut.u_pll.lock_enable=1;release_core;cycles(SETTLE);
  if(dut.setting_active || dut.av.settings_word[10])$fatal(1,"PLL recovery left menu active");
  mode_sw7=1;cycles(SETTLE*3);
  if(!dut.product_mode || dut.mode_switching || dut.av.force_tone || !dut.u_player.wav_enable || dut.u_player.auto_enable)
   $fatal(1,"SW7 product wiring/default manual");
  tap(4);repeat(4)tap(2);
  if(!dut.autoplay_page)$fatal(1,"physical keys cannot reach AUTO menu");
  tap(1);if(!dut.u_player.auto_enable || !dut.av.mode_status[0])$fatal(1,"AUTO on did not reach player/status");
  tap(3);if(dut.u_player.auto_enable)$fatal(1,"AUTO off did not reach player");
  tap(2);if(!dut.music_page || !dut.av.music_status[7])$fatal(1,"music item/status unreachable");
  tap(1);if(dut.u_player.wav_index!=1 || dut.cfg_music_index!=1 || !dut.music_page || dut.paused)
   $fatal(1,"music selection/focus/pause index=%0d cfg=%0d page=%b paused=%b switching=%b request=%b",dut.u_player.wav_index,dut.cfg_music_index,dut.music_page,dut.paused,dut.mode_switching,dut.cfg_music_request);
  tap(3);tap(3);if(dut.u_player.wav_index!=3)$fatal(1,"music previous wrap wiring");
  tap(2);if(!dut.rtc_page)$fatal(1,"physical KEY2 cannot reach clock page");
  tap(1);if(dut.rtc_draft!=48'h010101000000)$fatal(1,"physical KEY1 clock year");
  tap(2);tap(3);if(dut.rtc_draft!=48'h011201000000)$fatal(1,"physical KEY3 clock month");
  tap(4);if(dut.setting_active||dut.rtc_request)$fatal(1,"physical clock cancel wrote RTC");
  tap(2);if(!dut.paused || dut.av.audio_enable)$fatal(1,"product pause wiring");
  mode_sw7=0;cycles(SETTLE*3);
  if(dut.product_mode || dut.mode_switching || !dut.av.force_tone || dut.u_player.wav_enable || !dut.u_player.auto_enable || dut.paused)
   $fatal(1,"SW7 demo wiring/forced tone/auto/unpause");
  $display("PASS KEY1234 board top COUNT=%0d: passive physical matrix, LEDs/reset/MISO, next/previous/pause, runtime settings, interlock and AV/UI wiring",COUNT);$finish;
 end
 initial begin #3000000;$fatal(1,"board four-key test timeout");end
endmodule
