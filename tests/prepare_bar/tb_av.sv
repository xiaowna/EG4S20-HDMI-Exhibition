`timescale 1ns/1ps
module tb_prepare_av;
 reg sys_clk=0,pix_clk=0,rst_n=0,start_raster=0,manual_vs=1;
 always #10 sys_clk=~sys_clk;always #20 pix_clk=~pix_clk;
 integer x=0,y=0,i,cycles=0,checks=0,panel_checks=0;
 wire de=start_raster&&x<640&&y<480;
 wire hs=!(x>=656&&x<752),vs=start_raster?!(y>=490&&y<492):manual_vs;
 wire [23:0] rgb={x[7:0],y[7:0],x[7:0]^y[7:0]};
 wire [9:0] red,green,blue,rr,rg,rb;wire fault,ref_fault;
 reg [24:0] golden[0:307199];integer xx[0:10],yy[0:10];reg dd[0:10];reg [24:0] expected;
 hdmi_av_output #(.SETTINGS_UI(1),.MODE_CONTROL(1),.CHINESE_SUBTITLE(1),.CHINESE_SETTINGS(1),.FINE_ADJUST(1),.HOME_UI(1),.MUSIC_MENU(1),.RTC_OVERLAY(1),.RTC_SETTING(1),.PREPARE_UI(1)) dut(
  .sys_clk(sys_clk),.pix_clk(pix_clk),.rst_n(rst_n),.audio_enable(1'b1),.tone_sel(3'd2),
  .video_started(1'b1),.catalog_ready(1'b1),.wav_found(1'b0),.wav_error(1'b0),.audio_only(1'b0),.image_valid(1'b1),
  .image_count(3'd4),.image_index(2'd0),.wav_valid(1'b0),.wav_playing(1'b0),.wav_data(48'd0),.wav_ready(),
  .de(de),.hsync(hs),.vsync(vs),.rgb(rgb),.brightness(-9'sd64),.gain_q8(9'd128),.loading(1'b0),
  .fade_enabled(1'b0),.wave_enabled(1'b0),.settings_word(11'h400),.transition_ready(),
  .force_tone(1'b0),.audio_flush_request(1'b0),.mode_status(4'd4),.audio_flush_done(),
  .music_status(8'd0),.rtc_word(49'd0),.rtc_edit_word(54'd0),.home_word(15'd0),
  .fine_adjust_word({8'd0,7'd0}),.scene_enable(1'b0),.scene_yaw(7'd0),.scene_pitch(7'd0),.scene_ready(),
  .prepare_word({3'd3,7'd37}),.red(red),.green(green),.blue(blue),.audio_fault(fault),.audio_urgent());
 hdmi_av_output #(.SETTINGS_UI(1),.MODE_CONTROL(1),.CHINESE_SUBTITLE(1),.CHINESE_SETTINGS(1),.FINE_ADJUST(1),.HOME_UI(1),.MUSIC_MENU(1),.RTC_OVERLAY(1),.RTC_SETTING(1),.PREPARE_UI(0)) reference(
  .sys_clk(sys_clk),.pix_clk(pix_clk),.rst_n(rst_n),.audio_enable(1'b1),.tone_sel(3'd2),
  .video_started(1'b1),.catalog_ready(1'b1),.wav_found(1'b0),.wav_error(1'b0),.audio_only(1'b0),.image_valid(1'b1),
  .image_count(3'd4),.image_index(2'd0),.wav_valid(1'b0),.wav_playing(1'b0),.wav_data(48'd0),.wav_ready(),
  .de(de),.hsync(hs),.vsync(vs),.rgb(rgb),.brightness(-9'sd64),.gain_q8(9'd128),.loading(1'b0),
  .fade_enabled(1'b0),.wave_enabled(1'b0),.settings_word(11'h400),.transition_ready(),
  .force_tone(1'b0),.audio_flush_request(1'b0),.mode_status(4'd4),.audio_flush_done(),
  .music_status(8'd0),.rtc_word(49'd0),.rtc_edit_word(54'd0),.home_word(15'd0),
  .fine_adjust_word({8'd0,7'd0}),.scene_enable(1'b0),.scene_yaw(7'd0),.scene_pitch(7'd0),.scene_ready(),
  .prepare_word({3'd3,7'd37}),.red(rr),.green(rg),.blue(rb),.audio_fault(ref_fault),.audio_urgent());
 always @(posedge pix_clk)begin
  if(!rst_n||!start_raster)begin x<=0;y<=0;end
  else if(x==799)begin x<=0;if(y==524)y<=0;else y<=y+1;end else x<=x+1;
 end
 always @(negedge pix_clk)if(start_raster&&x==0&&(y%64)==0)$display("PROGRESS prepare HDMI raster row=%0d",y);
 always @(posedge pix_clk)if(rst_n)begin
  for(i=10;i>0;i=i-1)begin xx[i]=xx[i-1];yy[i]=yy[i-1];dd[i]=dd[i-1];end
  xx[0]=x;yy[0]=y;dd[0]=de;cycles=cycles+1;#1;
  if(cycles>100)begin
   if({dut.dp,dut.hp,dut.vp,dut.x,dut.island,dut.phase,dut.fifo_read,dut.sample_request}!==
      {reference.dp,reference.hp,reference.vp,reference.x,reference.island,reference.phase,reference.fifo_read,reference.sample_request})
    $fatal(1,"progress changed HDMI timing/audio scheduling");
   if(dd[9])begin
    expected=golden[yy[9]*640+xx[9]];
    if(expected[24])begin
     if(dut.pixels[9]!==expected[23:0])$fatal(1,"progress AV alignment at %0d,%0d got=%h want=%h",xx[9],yy[9],dut.pixels[9],expected[23:0]);
     panel_checks=panel_checks+1;
    end else if(dut.pixels[9]!==reference.pixels[9])$fatal(1,"progress changed image/menu outside panel");
    checks=checks+1;
   end
   if(!dd[10]&&{red,green,blue}!=={rr,rg,rb})$fatal(1,"progress changed blanking/audio symbols");
  end
 end
 initial begin
  $readmemh("av_pixels.hex",golden);
  for(i=0;i<=10;i=i+1)begin xx[i]=0;yy[i]=0;dd[i]=0;end
  repeat(8)@(negedge pix_clk);rst_n=1;$display("PROGRESS prepare HDMI reset released");
  repeat(4000)@(negedge pix_clk);$display("PROGRESS prepare HDMI status settled");
  if(dut.prepare_pix!=={3'd3,7'd37})$fatal(1,"coherent preparation CDC missing");
  manual_vs=0;repeat(16)@(negedge pix_clk);manual_vs=1;repeat(16)@(negedge pix_clk);
  start_raster=1;$display("PROGRESS prepare HDMI raster started");repeat(800*480+32)@(negedge pix_clk);
  if(checks!=307200||panel_checks!=10176)$fatal(1,"incomplete AV frame checks=%0d panel=%0d",checks,panel_checks);
  $display("PASS preparation HDMI: 307200 real raster pixels, one-clock overlay/ten-clock pipeline, minimum brightness, coherent status, unchanged blanking and audio");$finish;
 end
 initial begin #30000000;$fatal(1,"timeout");end
endmodule
