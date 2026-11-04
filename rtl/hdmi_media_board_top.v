// 硬木课堂 DMZ-EG4S20：SD 图片 + 48 kHz 双声道 WAV/测试音（尚待上板确认）。
// SW0: DOWN reset / UP run. SW7: 0 demo / 1 product.
// KEY0 home; KEY1 right, KEY2 OK, KEY3 left, KEY4 settings.
// M0 HDMI/TF, core keyboard and left40 peripheral pins are in board.adc.
// The N pads are allocated by TD LVDS constraints; do not add inverted GPIOs.
module hdmi_media_board_top #(parameter HOME_UI=1,parameter VIEW_3D=1,parameter FINE_ADJUST=1,
 parameter IR_FIXED_ENABLE=1,parameter [47:0] IR_FIXED_KEYS=48'h000915074316,
 parameter IR_EXTRA_ENABLE=1,parameter [23:0] IR_EXTRA_KEYS=24'h0d4645,
 parameter IR_DIRECTION_ENABLE=1,parameter [15:0] IR_DIRECTION_KEYS=16'h4019)(
 input wire clk50,rst_n,sd_miso,mode_sw7,
 input wire infrared_n,
 output wire rtc_scl,rtc_ce,inout wire rtc_sda,
 input wire [3:0] key_col_n,
 output wire [3:0] key_row_n,
 output wire sd_sck,sd_mosi,sd_cs,
 output wire hdmi_clk_p,hdmi_d0_p,hdmi_d1_p,hdmi_d2_p,
 output wire [3:0] led);
 localparam integer MAX_IMAGES=24,INDEX_BITS=$clog2(MAX_IMAGES),COUNT_BITS=$clog2(MAX_IMAGES+1);
 wire sys_clk,pix_clk,ser_clk,locked;
 board_pll u_pll(.refclk(clk50),.reset(!rst_n),.extlock(locked),
  .clk0_out(pix_clk),.clk1_out(ser_clk),.clk2_out(sys_clk));
 wire reset_ok=rst_n&&locked;
 // Release on falling edges of the slowest clock. The related 50/125 MHz
 // clocks then have half a pixel period before the next pixel rising edge.
 reg [3:0] release_pipe;
 always @(negedge pix_clk or negedge reset_ok)
  if(!reset_ok)release_pipe<=0;else release_pipe<={release_pipe[2:0],1'b1};
 wire core_rst_n=release_pipe[3];
 wire [47:0] rtc_time;
 wire rtc_valid;
 wire rtc_page,rtc_exit,rtc_busy,rtc_done,rtc_error,rtc_request;
 wire [47:0] rtc_draft;wire [2:0] rtc_field;wire [1:0] rtc_status;
 wire [53:0] rtc_edit_word={rtc_page,rtc_status,rtc_field,rtc_draft};
 // Core left40 pins7/8/9 carry DS1302 CLK/DAT/CE. The legacy port
 // names rtc_scl/rtc_sda denote CLK/DAT; CE is not the FPGA reset signal.
 rtc_ds1302 #(.WRITE_ENABLE(1)) rtc(.clk(sys_clk),.rst_n(core_rst_n),.rtc_clk(rtc_scl),.rtc_dat(rtc_sda),.rtc_ce(rtc_ce),
  .time_bcd(rtc_time),.time_valid(rtc_valid),.set_request(rtc_request),.set_bcd(rtc_draft),
  .set_busy(rtc_busy),.set_done(rtc_done),.set_error(rtc_error));
 // MISO retains both synchronizer stages. The SPI receiver consumes the
 // delayed bit at falling SCK, preserving a 40 ns digital return window
 // at 12.5 MHz; real card/pad/board setup still needs hardware validation.
(* async_reg="true" *) reg miso1,miso2;
always @(posedge sys_clk or negedge core_rst_n)
 if(!core_rst_n)begin miso1<=1;miso2<=1;end
 else begin miso1<=sd_miso;miso2<=miso1;end
wire next_press,prev_press,pause_press;reg paused;
 wire product_mode,mode_switching,mode_change,wav_enable,wav_idle,controls_block;
 wire audio_flush_request,audio_flush_done;
 wire [2:0] music_count;wire [1:0] cfg_music_index,active_music_index;
 wire cfg_music_request,music_page;
 wire home_visible,home_starting,home_play,home_autoplay,album_ready,album_error;
 wire [14:0] home_word;wire [2:0] home_index;
 wire [4:0] album_first;wire [5:0] album_limit;wire [1:0] album_music;
 wire [24:0] folder_info;
 wire [1:0] requested_music=home_play?((album_music<music_count)?album_music:2'd0):cfg_music_index;
 wire [7:0] music_status={music_page,cfg_music_index,music_count,active_music_index};
 media_mode_control #(.MUSIC_SELECT(1),.HOME_UI(HOME_UI)) mode_control(.clk(sys_clk),.rst_n(core_rst_n),.mode_sw7(mode_sw7),
  .wav_idle(wav_idle),.audio_flush_done(audio_flush_done),.product_mode(product_mode),
  .switching(mode_switching),.wav_enable(wav_enable),.controls_block(controls_block),
  .restart_audio(home_play),.music_request(cfg_music_request|home_play),.music_index(requested_music),.active_music_index(active_music_index),
  .audio_flush_request(audio_flush_request),.mode_change(mode_change));
 wire [3:0] matrix_key_n;wire [4:0] matrix_view_n;wire matrix_home_n;
 wire [2:0] matrix_scene_n;wire scene_mode;wire [1:0] scene_zoom;
 wire view_active,view_ready;wire [6:0] view_yaw,view_pitch;
 wire matrix_ready;
 board_matrix_keys #(.VIEW_KEYS(HOME_UI&&VIEW_3D),.HOME_KEY(HOME_UI),.SCENE_KEYS(HOME_UI&&VIEW_3D)) keyboard(.clk(sys_clk),.rst_n(core_rst_n),
  .col_n(key_col_n),.row_n(key_row_n),.key_n(matrix_key_n),.view_key_n(matrix_view_n),.home_key_n(matrix_home_n),.scene_key_n(matrix_scene_n),.ready(matrix_ready));
 // Debounce a complete scan with one shared 20 ms timer.
 wire controls_rst_n=core_rst_n&&matrix_ready;
 wire keys_rst_n=controls_rst_n&&!controls_block;
 wire [12:0] all_key_press,all_key_stable_n;
 wire [3:0] key_press=all_key_press[3:0],key_stable_n=all_key_stable_n[3:0];
 wire signed [8:0] brightness_value;
 wire [8:0] gain_q8_value;wire [6:0] contrast_index;
 wire [7:0] fine_brightness_index=brightness_value+9'sd64;
 wire [14:0] fine_adjust_word={fine_brightness_index,contrast_index};
 wire fine_frame_tick;wire de,hs,vs;
 wire fade_enabled_value,wave_enabled_value;
 wire setting_active;
 wire [1:0] setting_page;
 wire cfg_autoplay,autoplay_page;
 wire autoplay_enabled=!mode_switching&&(!product_mode||cfg_autoplay)&&!home_visible&&!view_active;
 wire [3:0] mode_status={mode_switching,product_mode,autoplay_page,autoplay_enabled};
 generate if(FINE_ADJUST)begin:fine_frames
  (* async_reg="true" *) reg vs1,vs2;reg prev;
  always @(posedge sys_clk or negedge core_rst_n)
   if(!core_rst_n)begin vs1<=1;vs2<=1;prev<=1;end
   else begin vs1<=vs;vs2<=vs1;prev<=vs2;end
  assign fine_frame_tick=prev&&!vs2;
 end else begin:no_fine_frames
  assign fine_frame_tick=0;
 end endgenerate
 wire signed [3:0] brightness_step=brightness_value[8:5];
 wire [2:0] brightness_level=FINE_ADJUST?3'd0:brightness_step+4'sd2;
 wire [2:0] contrast_level=FINE_ADJUST?3'd0:gain_q8_value[8:6]-3'd2;
 wire [10:0] settings_word={setting_active,setting_page,brightness_level,
  contrast_level,fade_enabled_value,wave_enabled_value};
 board_key #(.WIDTH(13)) keys(.clk(sys_clk),.rst_n(keys_rst_n),
  .key_n({matrix_scene_n,matrix_home_n,matrix_view_n,matrix_key_n}),.press(all_key_press),.stable_n(all_key_stable_n));
 wire [3:0] control_event,infrared_event,normal_control_event;
 wire [3:0] ir_direction_event;
 wire ir_learning,ir_learning_enter,ir_home,ir_back,ir_easter_toggle,ir_model_event;
 wire [2:0] ir_learning_led;
 // Captured reset defaults remove learning circuitry from the fixed remote.
 media_infrared_control #(.HOME_KEY(1),.FIXED_ENABLE(IR_FIXED_ENABLE),
  .FIXED_KEYS(IR_FIXED_KEYS),.LEARN_ENABLE(!IR_FIXED_ENABLE),.EXTRA_ENABLE(IR_EXTRA_ENABLE),
  .DIRECTION_ENABLE(IR_DIRECTION_ENABLE&&IR_FIXED_ENABLE),
  .UP_COMMAND(IR_DIRECTION_KEYS[15:8]),.DOWN_COMMAND(IR_DIRECTION_KEYS[7:0]),
  .BACK_COMMAND(IR_EXTRA_KEYS[23:16]),.EGG_A(IR_EXTRA_KEYS[15:8]),.EGG_B(IR_EXTRA_KEYS[7:0])) infrared(.clk(sys_clk),.rst_n(core_rst_n),.enable(keys_rst_n),
  .infrared_n(infrared_n),.key_settings_down(!key_stable_n[3]),.key_settings_press(key_press[3]),
  .infrared_event(infrared_event),.direction_event(ir_direction_event),.learning(ir_learning),.learning_enter(ir_learning_enter),
  .learning_led(ir_learning_led),.paired(),.home_event(ir_home),.back_event(ir_back),.easter_toggle(ir_easter_toggle),.model_event(ir_model_event));
 // In a 3D view IR left/right rotate; the physical KEY1/3 keep time control.
 // A menu, HOME/BACK or a settings command wins over a coincident direction.
 wire ir_scene_context=IR_FIXED_ENABLE&&view_active&&!home_visible&&!setting_active&&!ir_learning&&!controls_block&&
  all_key_stable_n[9]&&!ir_home&&!ir_back&&!infrared_event[3]&&!(|key_press);
 wire ir_scene_controls=IR_DIRECTION_ENABLE&&ir_scene_context;
 // 0045 shares KEY5's model/reset path. Any physical key has priority.
 wire [2:0] scene_key_event=(|all_key_press)?all_key_press[12:10]:{2'd0,ir_scene_context&&ir_model_event};
 wire [3:0] ir_navigation_event=ir_scene_controls?(infrared_event&4'b1010):infrared_event;
 media_control_events control_events(.enable(keys_rst_n&&!ir_learning&&all_key_stable_n[9]),.key_press(key_press),
  .encoder_event(4'd0),.infrared_event(ir_navigation_event),.control_event(normal_control_event));
 // Close the existing menu once when learning begins; all settings persist.
 assign control_event=(ir_learning_enter&&setting_active)?4'b1000:normal_control_event;
 // Do not cancel an I2C write already being acknowledged by the RTC.
 wire home_return=HOME_UI&&product_mode&&(all_key_press[9]||ir_home||(ir_back&&!setting_active&&!home_visible))&&!ir_learning&&!rtc_busy;
 wire [3:0] adjusted_event=home_return?(setting_active?4'b1000:4'd0):
  ((ir_back&&setting_active&&!rtc_busy)?4'b1000:control_event);
 rtc_set_control clock_editor(.clk(sys_clk),.rst_n(core_rst_n),
  .enable(rtc_page),.key_press(adjusted_event),.time_bcd(rtc_time),.time_valid(rtc_valid),
  .set_busy(rtc_busy),.set_done(rtc_done),.set_error(rtc_error),.draft(rtc_draft),
  .field(rtc_field),.status(rtc_status),.set_request(rtc_request),.exit_request(rtc_exit));
 media_adjust_control #(.AUTOPLAY_MENU(1),.MUSIC_MENU(1),.RTC_MENU(1),.HOME_UI(HOME_UI),.FINE_ADJUST(FINE_ADJUST)) adjust_controls(.clk(sys_clk),.rst_n(controls_rst_n),
  .rtc_page(rtc_page),.rtc_exit(rtc_exit|ir_learning_enter|home_return),
  .product_mode(product_mode),.mode_change(mode_change),
  .cfg_autoplay(cfg_autoplay),.autoplay_page(autoplay_page),
  .music_count(music_count),.music_page(music_page),.cfg_music_index(cfg_music_index),.cfg_music_request(cfg_music_request),
  .home_play(home_autoplay),.home_music_index(active_music_index),
  .key_press(home_visible&&!setting_active?((home_starting||home_word[13])?4'd0:{adjusted_event[3],3'd0}):
   ((view_active&&!setting_active)?{adjusted_event[3],3'd0}:adjusted_event)),
  .frame_tick(fine_frame_tick),.held_key_n(key_stable_n),.contrast_index(contrast_index),
  .cfg_value(brightness_value),.cfg_gain_q8(gain_q8_value),
  .cfg_fade_enabled(fade_enabled_value),.cfg_wave_enabled(wave_enabled_value),
  .cfg_update(),.setting_active(setting_active),.setting_page(setting_page),
  .next_event(next_press),.prev_event(prev_press),.pause_event(pause_press));
 always @(posedge sys_clk or negedge core_rst_n)
  if(!core_rst_n)paused<=0;else if(mode_change||home_autoplay)paused<=0;else if(pause_press)paused<=!paused;
 wire card_ready,card_error,mem_ready,mem_error,prefetch_error,underflow,loading,image_error;
 wire [23:0] rgb;wire [COUNT_BITS-1:0] image_count;wire [INDEX_BITS-1:0] image_index;
 wire wav_valid,wav_ready,wav_playing,wav_error,audio_urgent,video_started,catalog_ready,wav_found;
 wire [47:0] wav_data;
 wire [INDEX_BITS-1:0] display_index;wire display_valid,audio_only;
 wire preparing;wire [6:0] prepare_pixels;
 // One compact status word for all waits. Stages without a measurable total
 // use an indeterminate bar; only image pixels provide a measured fraction.
 // A failed load is never advertised as 100 percent complete.
 reg [2:0] prepare_stage;
 wire wait_home=HOME_UI&&home_starting&&home_word[13:11]==3'd1;
 always @*begin
  prepare_stage=0;
  if(rtc_busy)prepare_stage=5;
  else if((rtc_page&&rtc_error)||(!home_visible&&product_mode&&wav_error&&!view_active))prepare_stage=6;
  else if(view_active)begin
   // The cube remains usable without a card or a valid BMP catalogue.
   if(mode_switching&&wait_home)prepare_stage=4;
   else if(wait_home&&!view_ready)prepare_stage=5;
   else if(wait_home)prepare_stage=4;
  end
  else if(card_error||mem_error||prefetch_error||(image_error&&!catalog_ready))prepare_stage=6;
  else if(!card_ready||!mem_ready)prepare_stage=1;
  else if(!catalog_ready)prepare_stage=2;
  else if(mode_switching)prepare_stage=4;
  else if((!view_active&&preparing)||(wait_home&&!view_active&&!album_ready&&!album_error))prepare_stage=3;
  else if(wait_home)prepare_stage=4;
  else if(image_error&&!home_visible&&!view_active)prepare_stage=6;
 end
 wire [9:0] prepare_word={prepare_stage,prepare_stage==3?prepare_pixels:7'd0};
 // Publish a complete directory word at the UI boundary. Register its ready
 // flag together with the ranges so a queued OK cannot use old flat ranges
 // on the first catalogue-ready cycle. This breaks the scan->card CE path.
 reg [24:0] folder_info_ui;
 reg folder_ui_ready;
 always @(posedge sys_clk or negedge core_rst_n)
  if(!core_rst_n)begin folder_info_ui<=0;folder_ui_ready<=0;end
  else begin
   folder_ui_ready<=catalog_ready;
   folder_info_ui<=catalog_ready?folder_info:25'd0;
  end
 generate if(HOME_UI)begin:homepage
  home_album_config #(.TOPIC_FOLDERS(1)) config_data(.index(home_index),.first_image(album_first),.image_limit(album_limit),.music_index(album_music),.folder_info(folder_info_ui));
  // The themed home is also the welcome screen; no second dismiss-only page.
  media_home_control #(.VIEW_3D(VIEW_3D),.EXHIBIT(0)) control(.clk(sys_clk),.rst_n(core_rst_n),.vsync(vs),
   .product_mode(product_mode),.mode_change(mode_change),.setting_active(setting_active),.home_request(home_return),
   .key_press(ir_learning?4'd0:control_event),.catalog_ready(catalog_ready&&folder_ui_ready),.image_count({{(6-COUNT_BITS){1'b0}},image_count}),
   .first_image(album_first),.image_limit(album_limit),.switching(mode_switching),
   .view_ready(view_ready),.view_active(view_active),.album_ready(album_ready),.album_error(album_error),.visible(home_visible),.starting(home_starting),
   .index(home_index),.home_word(home_word),.play_request(home_play),.autoplay_request(home_autoplay));
 end else begin:no_homepage
  assign home_visible=0;assign home_starting=0;assign home_play=0;assign home_autoplay=0;
  assign view_active=0;assign home_word=0;assign home_index=0;assign album_first=0;assign album_limit=0;assign album_music=0;
 end endgenerate
 // The five view keys share the original matrix scan/debounce; no GPIO added.
 generate if(HOME_UI&&VIEW_3D)begin:scene_controls
  (* async_reg="true" *) reg vs1,vs2;reg vs_prev;
  always @(posedge sys_clk or negedge core_rst_n)
   if(!core_rst_n)begin vs1<=1;vs2<=1;vs_prev<=1;end
   else begin vs1<=vs;vs2<=vs1;vs_prev<=vs2;end
  media_3d_control #(.GENERAL_KEYS(1),.DIRECTION_KEYS(1)) rotation(.clk(sys_clk),.rst_n(core_rst_n),
   .right_pulse(control_event[0]),.left_pulse(control_event[2]),.ok_pulse(control_event[1]),
   .direction_pulse(ir_scene_controls?ir_direction_event:4'd0),
   .enable(view_active),.pause_controls(home_visible||setting_active||ir_learning||controls_block),
   .frame_tick(vs_prev&&!vs2),.key_press(all_key_press[8:4]),
   .key_stable_n(all_key_stable_n[8:4]),.scene_key_press(scene_key_event),
   .scene_mode(scene_mode),.zoom(scene_zoom),.yaw(view_yaw),.pitch(view_pitch));
 end else begin:no_scene_controls
  assign view_yaw=0;assign view_pitch=0;assign scene_mode=0;assign scene_zoom=1;
 end endgenerate
 wire transition_active,transition_ready_pix,slide_transition;
 (* async_reg="true" *) reg [1:0] transition_ready_sys;
 always @(posedge sys_clk or negedge core_rst_n)
  if(!core_rst_n)transition_ready_sys<=0;
  else transition_ready_sys<={transition_ready_sys[0],transition_ready_pix};
 sd_media_player #(.MODE_CONTROL(1),.MAX_IMAGES(MAX_IMAGES),.SLIDE_TRANSITIONS(1),.MAX_WAVS(4),.ALBUMS(HOME_UI),.INTRO_ANIMATION(HOME_UI)) u_player(.clk(sys_clk),.pix_clk(pix_clk),.rst_n(core_rst_n),
  .intro_enable(!home_visible&&!view_active),.intro_pause(setting_active||mode_switching),.folder_info(folder_info),
  .preparing(preparing),.prepare_pixels(prepare_pixels),
  .album_request(home_play&&!view_active),.album_enable(product_mode),.album_first(album_first),.album_limit(album_limit[COUNT_BITS-1:0]),
  .album_ready(album_ready),.album_error(album_error),
  .auto_enable(autoplay_enabled),.wav_enable(wav_enable&&(!home_visible||home_starting)),.wav_idle(wav_idle),
  .wav_index(active_music_index),.wav_count(music_count),
  .sd_miso(miso2),.sd_sck(sd_sck),.sd_mosi(sd_mosi),.sd_cs(sd_cs),
  .next_pulse(next_press&&!home_visible&&!view_active),.prev_pulse(prev_press&&!home_visible&&!view_active),.pause(paused),.de(de),.hsync(hs),.vsync(vs),.rgb(rgb),
  .card_ready(card_ready),.card_error(card_error),.sdram_ready(mem_ready),.memory_fault(mem_error),
  .prefetch_error(prefetch_error),.frame_underflow(underflow),.loading(loading),.image_error(image_error),
  .image_count(image_count),.image_index(image_index),
  .wav_valid(wav_valid),.wav_ready(wav_ready),.wav_data(wav_data),
  .wav_playing(wav_playing),.wav_error(wav_error),.audio_urgent(audio_urgent),
  .video_started(video_started),.catalog_ready(catalog_ready),.wav_found(wav_found),
  .display_index(display_index),.display_valid(display_valid),.audio_only(audio_only),
  .transition_active(transition_active),.transition_ready(transition_ready_sys[1]),.slide_transition(slide_transition));
 wire [9:0] tr,tg,tb;
 wire audio_fault;
 hdmi_av_output #(.SETTINGS_UI(1),.MODE_CONTROL(1),.CHINESE_SUBTITLE(1),.CHINESE_SETTINGS(1),.SPECTRUM_FFT(1),.MUSIC_MENU(1),.RTC_OVERLAY(1),.RTC_SETTING(1),.HOME_UI(HOME_UI),.VIEW_3D(HOME_UI&&VIEW_3D),.FINE_ADJUST(FINE_ADJUST),.PREPARE_UI(1),.MUSIC_TOAST(HOME_UI),.MAX_IMAGES(MAX_IMAGES)) av(.sys_clk(sys_clk),.pix_clk(pix_clk),.rst_n(core_rst_n),
  .prepare_word(prepare_word),.easter_toggle(ir_easter_toggle),
  .fine_adjust_word(fine_adjust_word),.scene_enable(view_active),.scene_yaw(view_yaw),.scene_pitch(view_pitch),.scene_mode(scene_mode),.scene_zoom(scene_zoom),.scene_ready(view_ready),
  .home_word(home_word),.rtc_edit_word(rtc_edit_word),
  .rtc_word({rtc_valid,rtc_time}),
  .force_tone(!product_mode),.audio_flush_request(audio_flush_request),
  .audio_flush_done(audio_flush_done),.mode_status(mode_status),
  .settings_word(settings_word),.music_status(music_status),
  .audio_enable(!paused&&!mode_switching&&!home_visible),.tone_sel(3'd2),.brightness(brightness_value),.gain_q8(gain_q8_value),
  .loading(transition_active&&!slide_transition&&!view_active),.transition_ready(transition_ready_pix),
  .fade_enabled(fade_enabled_value&&!slide_transition&&!view_active),.wave_enabled(wave_enabled_value),
  .image_count(image_count),.image_index(display_index),.image_valid(display_valid),.audio_only(audio_only||view_active),
  .wav_valid(wav_valid),.wav_ready(wav_ready),.wav_data(wav_data),.wav_playing(wav_playing),
  .video_started(video_started),.catalog_ready(catalog_ready),.wav_found(wav_found),
  .wav_error(wav_error),
  .de(de),.hsync(hs),.vsync(vs),.rgb(rgb),
  .red(tr),.green(tg),.blue(tb),.audio_fault(audio_fault),.audio_urgent(audio_urgent));
 tmds_ddr_tx tx(.pix_clk(pix_clk),.ser_clk(ser_clk),.rst_n(core_rst_n),.red(tr),.green(tg),.blue(tb),
  .clk_p(hdmi_clk_p),.d0_p(hdmi_d0_p),.d1_p(hdmi_d1_p),.d2_p(hdmi_d2_p));
 // DMZ LEDs are active high: ready(memory/card), loading, aggregate error.
 assign led={card_error|mem_error|prefetch_error|underflow|image_error|wav_error|audio_fault,
  ir_learning?ir_learning_led:{loading,card_ready,mem_ready}};
endmodule
