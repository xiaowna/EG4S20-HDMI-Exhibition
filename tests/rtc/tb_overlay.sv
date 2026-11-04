`timescale 1ns/1ps
module tb_rtc_overlay;
 reg clk=0,rst_n=0,de=0,vsync=1;
 reg [9:0] x=0,y=0;
 reg [23:0] rgb_in=0;
 reg [10:0] settings_word=0;
 reg [3:0] mode_status=0;
 reg [7:0] music_status=0;
 reg [48:0] rtc_word=0;
 wire [23:0] rgb_out;wire overlay_valid;
 reg font[0:16383];
 reg [48:0] expected_frame;
 reg [23:0] expected,composed;
 integer i,j,slot,glyph,nibble,address,checks=0,lit=0,fd;
 always #10 clk=~clk;
 video_chinese_settings #(.SPECTRUM_FFT(1),.MUSIC_MENU(1),.RTC_OVERLAY(1)) dut(.home_word(15'd0),.music_playing(1'b0),.fine_adjust_word(15'd0),.*,.rtc_edit_word(54'd0));
 task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 task frame;
  begin de=0;vsync=0;tick;vsync=1;tick;expected_frame=rtc_word;end
 endtask
 function integer character(input integer col,input [48:0] value);
  reg [127:0] text;integer digit;
  begin
   text={8'h20,value[47:40],value[39:32],value[31:24],value[23:16],value[15:8],value[7:0]};
   case(col)
    0:digit=2;1:digit=0;2:digit=value[47:44];3:digit=value[43:40];
    5:digit=value[39:36];6:digit=value[35:32];8:digit=value[31:28];9:digit=value[27:24];
    11:digit=value[23:20];12:digit=value[19:16];14:digit=value[15:12];15:digit=value[11:8];
    17:digit=value[7:4];18:digit=value[3:0];default:digit=0;
   endcase
   if(col==4||col==7)character=49;
   else if(col==10)character=0;
   else if(col==13||col==16)character=62;
   else character=value[48]?38+digit:49;
  end
 endfunction
 task scan(input integer save);
  begin
   for(j=0;j<80;j=j+1)for(i=0;i<640;i=i+1)begin
    x=i;y=j;de=1;rgb_in={x[7:0],y[7:0],8'h70};expected=rgb_in;
    if(i>=320&&i<624&&j>=8&&j<24)begin
     glyph=character((i-320)/16,expected_frame);
     address=glyph*256+(j-8)*16+(i-320)%16;
     if(font[address])begin expected=expected_frame[48]?24'hc8ddd7:24'h93a9b4;lit=lit+1;end
    end
    @(posedge clk);#1;
    if(overlay_valid!==(i>=320&&i<624&&j>=8&&j<24))$fatal(1,"timestamp cover outside/inside expected window");
    composed=overlay_valid?rgb_out:rgb_in;
    if(composed!==expected)$fatal(1,"timestamp pixel %0d,%0d expected %h actual %h",i,j,expected,composed);
    if(save)$fwrite(fd,"%0d %0d %0d\n",composed[23:16],composed[15:8],composed[7:0]);
    checks=checks+1;@(negedge clk);
   end
  end
 endtask
 initial begin
  $readmemh("font.hex",font);tick;rst_n=1;tick;
  rtc_word={1'b1,48'h261021235959};frame;
  fd=$fopen("rtc_overlay.ppm","w");$fwrite(fd,"P3\n640 80\n255\n");scan(1);$fclose(fd);
  // A new date arriving during active video must wait for the next frame.
  rtc_word={1'b1,48'h261022000000};scan(0);
  frame;scan(0);rtc_word=0;scan(0);frame;scan(0);
  // The calendar stays visible when the menu opens; outside its own glyphs
  // the top-right area stays transparent even with the menu enabled.
  settings_word[10]=1;frame;x=320;y=8;de=1;tick;
  if(!overlay_valid||dut.rtc_frame!==0)$fatal(1,"RTC/menu coexistence");
  de=0;tick;if(overlay_valid)$fatal(1,"blanking is covered");
  rst_n=0;tick;if(overlay_valid||dut.rtc_frame!=0)$fatal(1,"overlay reset");
  if(lit<100)$fatal(1,"missing visible digits");
  $display("PASS RTC overlay: %0d exact pixels, frame freeze, date rollover, placeholders, transparency, menu and reset",checks);$finish;
 end
endmodule
