`timescale 1ns/1ps
module tb_rtc_set_menu;
 reg clk=0,rst_n=0,de=0,vsync=1;
 reg [9:0] x=0,y=0;
 reg [23:0] rgb_in=24'h406080;
 reg [10:0] settings_word=11'h400;
 reg [3:0] mode_status=4'b0100;
 reg [7:0] music_status=8'h08;
 reg [48:0] rtc_word={1'b1,48'h261021123456};
 reg [53:0] rtc_edit_word={1'b1,2'd0,3'd0,48'h261021123456};
 wire [23:0] rgb_out;wire overlay_valid;
 reg font[0:32767];reg [6:0] glyphs[0:47];
 reg [2:0] expected_field=0;reg [1:0] expected_status=0;
 reg [23:0] expected;integer glyph,px,py,i,j,fd,checks=0;reg window;
 always #10 clk=~clk;
 video_chinese_settings #(.MUSIC_MENU(1),.RTC_OVERLAY(1),.RTC_SETTING(1)) dut(.home_word(15'd0),.music_playing(1'b0),.fine_adjust_word(15'd0),.*);
 task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 task frame;begin de=0;vsync=0;tick;vsync=1;tick;end endtask
 task scan(input integer save);
  integer digit_field,col;
  begin
   for(j=0;j<480;j=j+1)for(i=0;i<640;i=i+1)begin
    x=i;y=j;de=1;window=0;glyph=0;px=0;py=0;expected=24'he7efec;
    if(i>=144&&i<272&&j>=104&&j<136)begin
     window=1;glyph=glyphs[(i-144)/32];px=(i-144)%32/2;py=(j-104)/2;expected=24'h70d6bc;
    end else if(i>=160&&i<480&&j>=192&&j<224)begin
     window=1;col=(i-160)/32;glyph=glyphs[4+col];px=(i-160)%32/2;py=(j-192)/2;
     digit_field=(col<4)?0:((col<7)?1:2);
     if(expected_field==digit_field)expected=24'h70d6bc;
    end else if(i>=192&&i<448&&j>=264&&j<296)begin
     window=1;col=(i-192)/32;glyph=glyphs[14+col];px=(i-192)%32/2;py=(j-264)/2;
     digit_field=(col<2)?3:((col<5)?4:5);
     if(expected_field==digit_field)expected=24'h70d6bc;
    end else if(j>=348&&j<380&&((i>=216&&i<280)||(i>=360&&i<424)))begin
     window=1;col=(i<280)?(i-216)/32:((i-360)/32+2);glyph=glyphs[22+col];
     px=(i<280)?(i-216)%32/2:(i-360)%32/2;py=(j-348)/2;
     if((i<280&&expected_field==6)||(i>=360&&expected_field==7))expected=24'h70d6bc;
    end else if(i>=304&&i<336&&j>=312&&j<328&&expected_status!=0)begin
     window=1;glyph=glyphs[26+(expected_status-1)*2+(i-304)/16];px=(i-304)%16;py=j-312;
     expected=(expected_status==3)?24'he5a89b:24'hb6e7d7;
    end
    if(window&&!font[glyph*256+py*16+px])expected=24'h162737;
    @(posedge clk);#1;
    if(window)begin
     if(overlay_valid!==1||rgb_out!==expected)$fatal(1,"clock menu pixel %0d,%0d glyph=%0d expected=%h got=%h",i,j,glyph,expected,rgb_out);
     checks=checks+1;
    end
    if(save)$fwrite(fd,"%0d %0d %0d\n",rgb_out[23:16],rgb_out[15:8],rgb_out[7:0]);
    @(negedge clk);
   end
  end
 endtask
 initial begin
  $readmemh("clock_font.hex",font);$readmemh("clock_labels.hex",glyphs);
  repeat(3)tick;rst_n=1;frame;
  fd=$fopen("clock_menu.ppm","w");$fwrite(fd,"P3\n640 480\n255\n");scan(1);$fclose(fd);
  // Entire menu word freezes for the frame, not only the top timestamp.
  rtc_edit_word={1'b1,2'd3,3'd7,48'h991231235959};scan(0);
  rtc_edit_word={1'b1,2'd3,3'd7,48'h261021123456};frame;
  expected_status=3;expected_field=7;scan(0);
  rtc_edit_word={1'b1,2'd1,3'd6,48'h261021123456};frame;
  expected_status=1;expected_field=6;scan(0);
  rtc_edit_word={1'b1,2'd2,3'd6,48'h261021123456};frame;
  expected_status=2;scan(0);
  $display("PASS RTC Chinese clock menu: %0d exact pixels, original font slots, field highlighting, busy/success/failure, frame freeze",checks);$finish;
 end
 initial begin #100000000;$fatal(1,"clock menu timeout");end
endmodule
