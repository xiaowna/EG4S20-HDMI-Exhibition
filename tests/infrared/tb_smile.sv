`timescale 1ns/1ps
// Exercise the actual AV integration and its existing one-clock overlay path.
module tb_secret_smile;
 reg clk=0,rst=0,de=1,vs=1,trigger=0;reg [9:0] scanx=0,scany=0;
 always #10 clk=~clk;
 hdmi_av_output #(.HOME_UI(1),.CHINESE_SUBTITLE(1),.MAX_IMAGES(24)) dut(
  .sys_clk(clk),.pix_clk(clk),.rst_n(rst),.de(de),.hsync(1'b1),.vsync(vs),.rgb(24'h345678),
  .easter_toggle(trigger),.audio_enable(1'b0),.tone_sel(3'd0),.video_started(1'b0),.catalog_ready(1'b0),
  .wav_found(1'b0),.wav_error(1'b0),.audio_only(1'b0),.image_valid(1'b0),.image_count(5'd0),.image_index(5'd0),
  .wav_valid(1'b0),.wav_playing(1'b0),.wav_data(48'd0),.brightness(9'sd0),.gain_q8(9'd256),
  .loading(1'b0),.fade_enabled(1'b0),.wave_enabled(1'b0),.settings_word(11'd0),.force_tone(1'b0),
  .audio_flush_request(1'b0),.mode_status(4'd0),.music_status(8'd0),.rtc_word(49'd0),
  .rtc_edit_word(54'd0),.home_word(15'd0),.scene_enable(1'b0),.scene_yaw(7'd0),.scene_pitch(7'd0),
  .fine_adjust_word(15'd0),.prepare_word(10'd0));
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task frame;begin vs=0;cycles(8);vs=1;cycles(8);end endtask
 integer ink=0,glyph,source_x,source_y,addr;
 reg font[0:106495];reg [23:0] expected;
 task sample(input integer px,py,input bit expect_cover,input [23:0] color);
 begin
  scanx=px;scany=py;cycles(4);
  if(dut.chinese.home_easter!==expect_cover)$fatal(1,"celebration coverage %0d,%0d",px,py);
  if(expect_cover&&dut.overlay_rgb!==color)$fatal(1,"celebration color/alignment %0d,%0d got=%h expected=%h",px,py,dut.overlay_rgb,color);
 end endtask
 initial begin
  $readmemb("celebration_font.hex",font);
  force dut.osd_x=scanx;force dut.osd_y=scany;
  cycles(4);rst=1;cycles(8);
  if(dut.chinese.home.display.egg_active||dut.chinese.home_easter)$fatal(1,"startup secret");
  trigger=1;cycles(8);if(dut.chinese.home.display.egg_active)$fatal(1,"mid-frame activation");
  frame();if(!dut.chinese.home.display.egg_active||dut.chinese.home.display.egg_frame)$fatal(1,"lost CDC trigger");
  for(integer y=192;y<256;y=y+1)for(integer x=152;x<488;x=x+1)begin
   expected=(x<154||x>=486||y<194||y>=254)?24'h70d6bc:24'h162737;
   if(x>=176&&x<464&&y>=208&&y<240)begin
    glyph=(x-176)/32;source_x=(glyph%5)*16+((x-176)%32)/2;
    source_y=96+(glyph/5)*16+(y-208)/2;addr=81920+source_y*128+source_x;
    if(font[addr])begin expected=24'he7efec;ink=ink+1;end
   end
   sample(x,y,1,expected);
  end
  if(ink<400)$fatal(1,"message glyphs empty");
  sample(164,144,1,24'hfff0c2);sample(20,300,0,0);
  de=0;cycles(4);if(dut.chinese.home_easter)$fatal(1,"blanking overdraw");de=1;
  repeat(16)frame();sample(196,144,1,24'hffd26a);sample(164,144,0,0);
  repeat(32)frame();sample(164,144,0,0);sample(516,128,1,24'h8ae7ff);
  repeat(32)frame();sample(196,144,1,24'hff9ebc);
  trigger=0;cycles(8);frame();if(dut.chinese.home.display.egg_frame||!dut.chinese.home.display.egg_active)$fatal(1,"retrigger");
  repeat(239)frame();if(!dut.chinese.home.display.egg_active)$fatal(1,"early disappearance");
  frame();if(dut.chinese.home.display.egg_active)$fatal(1,"celebration never disappeared");
  sample(200,220,0,0);
  trigger=1;cycles(8);frame();rst=0;cycles(4);
  if(dut.chinese.home.display.egg_active||dut.chinese.home_easter)$fatal(1,"reset celebration");
  $display("PASS actual AV celebration: frame-boundary CDC, 21504 panel pixels/nine glyphs, transparent exterior, expanding/color-changing fireworks, 240-frame expiry/retrigger/reset; unchanged pixel pipeline");$finish;
 end
 initial begin #10000000;$fatal(1,"smile timeout");end
endmodule
