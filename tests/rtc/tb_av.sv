`timescale 1ns/1ps
module tb_rtc_av;
 reg sys_clk=0,pix_clk=0,rst_n=0,start_raster=0,manual_vs=1;
 always #10 sys_clk=~sys_clk;
 always #20 pix_clk=~pix_clk;
 integer x=0,y=0,i,cycles=0,checks=0,clock_pixels=0,reads=0;
 wire de=start_raster&&x<640&&y<480;
 wire hs=!(x>=656&&x<752),vs=start_raster?!(y>=490&&y<492):manual_vs;
 wire [23:0] rgb={x[7:0],y[7:0],x[7:0]^y[7:0]};
 wire [9:0] red,green,blue,rr,rg,rb;wire fault,ref_fault;
 reg font[0:16383];reg [5:0] glyphs[0:18];
 integer xx[0:10],yy[0:10];reg dd[0:10];reg [23:0] expected;integer address;
`define CONNECTIONS \
  .sys_clk(sys_clk),.pix_clk(pix_clk),.rst_n(rst_n),.audio_enable(1'b1),.tone_sel(3'd2), \
  .video_started(1'b1),.catalog_ready(1'b1),.wav_found(1'b0),.wav_error(1'b0),.audio_only(1'b0),.image_valid(1'b1), \
  .image_count(6'd32),.image_index(5'd0),.wav_valid(1'b0),.wav_playing(1'b0),.wav_data(48'd0),.wav_ready(), \
  .de(de),.hsync(hs),.vsync(vs),.rgb(rgb),.brightness(9'sd0),.gain_q8(9'd256),.loading(1'b0), \
  .fade_enabled(1'b0),.wave_enabled(1'b1),.settings_word(11'd0),.transition_ready(), \
  .force_tone(1'b1),.audio_flush_request(1'b0),.mode_status(4'b0001),.audio_flush_done(), \
  .music_status(8'd0),.rtc_word({1'b1,48'h261021235959}),.audio_urgent()
 hdmi_av_output #(.SETTINGS_UI(1),.MODE_CONTROL(1),.CHINESE_SUBTITLE(1),.CHINESE_SETTINGS(1),
  .SPECTRUM_FFT(1),.MUSIC_MENU(1),.RTC_OVERLAY(1),.MAX_IMAGES(32)) dut(
  `CONNECTIONS,.red(red),.green(green),.blue(blue),.audio_fault(fault));
 hdmi_av_output #(.SETTINGS_UI(1),.MODE_CONTROL(1),.CHINESE_SUBTITLE(1),.CHINESE_SETTINGS(1),
  .SPECTRUM_FFT(1),.MUSIC_MENU(1),.RTC_OVERLAY(0),.MAX_IMAGES(32)) reference(
  `CONNECTIONS,.red(rr),.green(rg),.blue(rb),.audio_fault(ref_fault));
`undef CONNECTIONS
 always @(posedge pix_clk)begin
  if(!rst_n||!start_raster)begin x<=0;y<=0;end
  else if(x==799)begin x<=0;if(y==524)y<=0;else y<=y+1;end else x<=x+1;
 end
 always @(posedge pix_clk)if(rst_n)begin
  for(i=10;i>0;i=i-1)begin xx[i]=xx[i-1];yy[i]=yy[i-1];dd[i]=dd[i-1];end
  xx[0]=x;yy[0]=y;dd[0]=de;cycles=cycles+1;#1;
  if(cycles>100)begin
   if({dut.dp,dut.hp,dut.vp,dut.x,dut.island,dut.phase,dut.fifo_read,dut.sample_request}!==
      {reference.dp,reference.hp,reference.vp,reference.x,reference.island,reference.phase,reference.fifo_read,reference.sample_request})
    $fatal(1,"RTC changed HDMI timing/audio scheduling");
   if(dut.fifo_read)reads=reads+1;
   expected=reference.pixels[9];
   if(dd[9]&&xx[9]>=320&&xx[9]<624&&yy[9]>=8&&yy[9]<24)begin
    address=glyphs[(xx[9]-320)/16]*256+(yy[9]-8)*16+(xx[9]-320)%16;
    if(font[address])expected=24'hc3d8de;
    clock_pixels=clock_pixels+1;
   end
   if(dut.pixels[9]!==expected)$fatal(1,"RTC AV pixel alignment xy=%0d,%0d expected %h got %h",xx[9],yy[9],expected,dut.pixels[9]);
   if(!dd[10]&&{red,green,blue}!=={rr,rg,rb})$fatal(1,"RTC changed HDMI blanking/audio symbols");
   checks=checks+1;
  end
 end
 initial begin
  $readmemh("font.hex",font);$readmemh("timestamp_glyphs.hex",glyphs);
  for(i=0;i<=10;i=i+1)begin xx[i]=0;yy[i]=0;dd[i]=0;end
  repeat(8)@(negedge pix_clk);rst_n=1;
  repeat(600000)@(negedge pix_clk);
  manual_vs=0;repeat(4)@(negedge pix_clk);manual_vs=1;repeat(20)@(negedge pix_clk);
  start_raster=1;repeat(800*480+20)@(negedge pix_clk);
  if(clock_pixels!=304*16||reads<100||fault||ref_fault)$fatal(1,"RTC AV coverage/audio fault");
  $display("PASS RTC production AV: %0d cycles, %0d exact clock pixels, unchanged remaining RGB/FFT/subtitle and HDMI timing/audio symbols",checks,clock_pixels);$finish;
 end
 initial begin #50000000;$fatal(1,"RTC AV timeout");end
endmodule
