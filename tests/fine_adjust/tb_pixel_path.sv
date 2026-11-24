`timescale 1ns/1ps
// Actual settings controller -> CDC -> LUT -> Chinese menu -> HDMI pixels.
// Only blanking is accelerated while publishing a new mapping. Pixel checks
// use the normal 640x480 raster and pixels outside the opaque menu panel.
module tb_fine_pixel_path;
 reg sys_clk=0,pix_clk=0,rst_n=0,start_raster=0,manual_vs=1;
 always #10 sys_clk=~sys_clk;
 always #20 pix_clk=~pix_clk;
 reg [3:0] key_press=0;
 wire signed [8:0] brightness;wire [8:0] gain_q8;wire [6:0] contrast_index;
 wire setting_active,fade_enabled,wave_enabled;wire [1:0] setting_page;
 media_adjust_control #(.FINE_ADJUST(1),.HOME_UI(1)) controls(
  .clk(sys_clk),.rst_n(rst_n),.key_press(key_press),.frame_tick(1'b0),.held_key_n(4'hf),
  .cfg_value(brightness),.cfg_gain_q8(gain_q8),.contrast_index(contrast_index),
  .cfg_fade_enabled(fade_enabled),.cfg_wave_enabled(wave_enabled),.cfg_update(),
  .setting_active(setting_active),.setting_page(setting_page),.next_event(),.prev_event(),.pause_event(),
  .product_mode(1'b1),.mode_change(1'b0),.cfg_autoplay(),.autoplay_page(),.music_count(3'd0),
  .music_page(),.cfg_music_index(),.cfg_music_request(),.rtc_page(),.rtc_exit(1'b0),
  .home_play(1'b0),.home_music_index(2'd0));
 wire raw_de,raw_hs,raw_vs;
 video_raster_timing raster(.clk(pix_clk),.rst_n(rst_n&&start_raster),
  .de(raw_de),.hsync(raw_hs),.vsync(raw_vs),.blank_start(),.raster_start());
 wire de=start_raster&&raw_de,hsync=start_raster?raw_hs:1'b1,vsync=start_raster?raw_vs:manual_vs;
 wire [7:0] brightness_index=brightness+9'sd64;
 wire [14:0] fine_word={brightness_index,contrast_index};
 wire [10:0] settings_word={setting_active,setting_page,3'd0,3'd0,fade_enabled,wave_enabled};
 wire [9:0] red,green,blue;
 // Keep both old standalone inputs neutral deliberately: the production
 // fine-menu snapshot must be the single source for displayed/applied values.
 hdmi_av_output #(.SETTINGS_UI(1),.MODE_CONTROL(1),.MUSIC_MENU(1),.RTC_OVERLAY(1),.RTC_SETTING(1),
  .CHINESE_SUBTITLE(1),.CHINESE_SETTINGS(1),.HOME_UI(1),.FINE_ADJUST(1),
  .SPECTRUM_FFT(1),.PREPARE_UI(1),.MAX_IMAGES(24)) av(
  .sys_clk(sys_clk),.pix_clk(pix_clk),.rst_n(rst_n),.audio_enable(1'b0),.tone_sel(3'd2),
  .video_started(1'b1),.catalog_ready(1'b1),.wav_found(1'b0),.wav_error(1'b0),.audio_only(1'b0),
  .image_valid(1'b1),.image_count(5'd24),.image_index(5'd0),.wav_valid(1'b0),.wav_playing(1'b0),
  .wav_data(48'd0),.wav_ready(),.de(de),.hsync(hsync),.vsync(vsync),.rgb(24'h406080),
  .brightness(9'sd0),.gain_q8(9'd256),.loading(1'b0),.fade_enabled(fade_enabled),.wave_enabled(wave_enabled),
  .settings_word(settings_word),.fine_adjust_word(fine_word),.transition_ready(),.force_tone(1'b0),
  .audio_flush_request(1'b0),.mode_status(4'b0100),.audio_flush_done(),.music_status(8'd0),
  .rtc_word(49'd0),.rtc_edit_word(54'd0),.home_word(15'd0),.scene_enable(1'b0),
  .scene_yaw(7'd0),.scene_pitch(7'd0),.scene_mode(1'b0),.scene_zoom(2'd1),.scene_ready(),
  .prepare_word(10'd0),.red(red),.green(green),.blue(blue),.audio_fault(),.audio_urgent());
 task sys_cycles(input integer n);repeat(n)@(negedge sys_clk);endtask
 task pixel_cycles(input integer n);repeat(n)@(negedge pix_clk);endtask
 task press(input [3:0] value);begin
  @(negedge sys_clk);key_press=value;sys_cycles(1);key_press=0;sys_cycles(3);
 end endtask
 task publish_blank;begin
  start_raster=0;manual_vs=1;pixel_cycles(12);
  repeat(5)begin pixel_cycles(350);manual_vs=0;pixel_cycles(4);manual_vs=1;pixel_cycles(12);end
 end endtask
 // The controller uses a remainder accumulator; the pixel path uses a ROM.
 // Compare their independently implemented conversion at every 1% step.
 integer gain_checks=0;
 task check_numeric_pair;begin
  pixel_cycles(16);
  if(av.adjust_target!=={brightness,gain_q8})
   $fatal(1,"fine numeric snapshot lost: b=%0d index=%0d controller=%0d pixel=%h",$signed(brightness),contrast_index,gain_q8,av.adjust_target);
  gain_checks=gain_checks+1;
 end endtask
 function automatic [7:0] channel(input integer value,bias,gain);
  integer n;
  begin n=(value-128)*gain+(128+bias)*256;
   channel=n<0?0:((n>65280)?255:n/256);
  end
 endfunction
 integer xx[0:9],yy[0:9],i,samples=0,maps=0,total=0;
 reg dd[0:9];reg checking=0;reg [23:0] expected;
 always @(posedge pix_clk)begin
  for(i=9;i>0;i=i-1)begin xx[i]=xx[i-1];yy[i]=yy[i-1];dd[i]=dd[i-1];end
  xx[0]=raster.x;yy[0]=raster.y;dd[0]=de;
  #1;
  if(checking&&dd[9]&&xx[9]>=32&&xx[9]<96&&yy[9]>=160&&yy[9]<176)begin
   if(av.pixels[9]!==expected)
    $fatal(1,"settings-to-photo path: b=%0d gain=%0d menu=%b xy=%0d,%0d got=%h expected=%h",$signed(brightness),gain_q8,setting_active,xx[9],yy[9],av.pixels[9],expected);
   samples=samples+1;total=total+1;
  end
 end
 task photo(input integer bias,gain);
  integer ticks;
  begin
   expected={channel(64,bias,gain),channel(96,bias,gain),channel(128,bias,gain)};
   samples=0;ticks=0;start_raster=1;checking=1;
   while(samples<128)begin pixel_cycles(1);ticks=ticks+1;if(ticks>200000)$fatal(1,"photo pixel check timeout");end
   checking=0;start_raster=0;pixel_cycles(12);maps=maps+1;
  end
 endtask
 initial begin
  for(i=0;i<10;i=i+1)begin xx[i]=0;yy[i]=0;dd[i]=0;end
  sys_cycles(8);rst_n=1;pixel_cycles(20);
  photo(0,256);
  press(8);repeat(64)press(1);
  if(brightness!=64||!setting_active)$fatal(1,"brightness setting did not reach +64");
  publish_blank;photo(64,256);
  press(8);publish_blank;photo(64,256);
  press(8);repeat(64)press(4);press(2);repeat(50)press(1);
  if(brightness!=0||gain_q8!=384||contrast_index!=100||!setting_active)$fatal(1,"contrast setting did not reach 150 percent");
  publish_blank;photo(0,384);
  press(8);publish_blank;photo(0,384);
  press(8);repeat(64)press(4);publish_blank;photo(-64,384);
  press(2);check_numeric_pair;repeat(100)begin press(4);check_numeric_pair;end
  publish_blank;photo(-64,128);
  press(8);publish_blank;photo(-64,128);
  $display("PASS settings-to-photo: %0d exact final pixels across %0d maps, +/-64 brightness and 50/150-percent contrast while menu open/closed; %0d exact gain comparisons; fine snapshot overrides stale standalone inputs",total,maps,gain_checks);$finish;
 end
 initial begin #80000000;$fatal(1,"settings pixel path timeout");end
endmodule
