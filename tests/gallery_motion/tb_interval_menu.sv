`timescale 1ns/1ps
module tb_interval_menu;
 reg clk=0,rst_n=0,vsync=1,de=0;
 reg [9:0] x=0,y=0;
 reg [3:0] autoplay_word=0;
 reg [3:0] mode_status=4'b0110;
 wire [23:0] rgb;
 wire valid;
 reg expected[0:32767];
 always #5 clk=~clk;
 video_chinese_settings #(.MUSIC_MENU(1),.RTC_SETTING(1),.COMPACT_ROWS(1),.AUTOPLAY_INTERVAL_MENU(1)) menu(
  .clk(clk),.rst_n(rst_n),.de(de),.vsync(vsync),.x(x),.y(y),.rgb_in(24'd0),
  .settings_word(11'h400),.mode_status(mode_status),.music_status(8'h10),
  .rtc_word(49'd0),.rtc_edit_word(54'd0),.fine_adjust_word(15'd0),.home_word(15'd0),
  .music_playing(1'b0),.autoplay_word(autoplay_word),.rgb_out(rgb),.overlay_valid(valid));
 task tick;
  begin @(posedge clk);#1;@(negedge clk);#1;end
 endtask
 task snapshot(input [3:0] word);
  begin de=0;autoplay_word=word;vsync=0;tick();vsync=1;tick();end
 endtask
 task tile(input integer col,glyph,input bit off);
  integer px,py,bit_address;
  reg [23:0] want;
  begin
   for(py=0;py<16;py=py+1)for(px=0;px<16;px=px+1)begin
    x=416+(off?32:16)*col+px*(off?2:1);
    y=(off?288:296)+py*(off?2:1);
    de=1;bit_address=glyph*256+py*16+px;
    // The bottom four pixels of the compact row are below the selection.
    want=expected[bit_address]?24'he7efec:(y<316?24'h203f47:24'h162737);
    tick();
    if(!valid||rgb!==want)$fatal(1,"interval glyph=%0d xy=%0d,%0d got=%h expected=%h",glyph,x,y,rgb,want);
   end
  end
 endtask
 initial begin
  $readmemh("interval_font.hex",expected);
  tick();rst_n=1;tick();
  snapshot(4'b0001);tile(0,22,1);tile(1,23,1); // 关闭
  snapshot(4'b1000);tile(0,0,0);tile(1,41,0);tile(2,82,0); // 3 秒
  snapshot(4'b1001);tile(0,0,0);tile(1,43,0);tile(2,82,0); // 5 秒
  snapshot(4'b1010);tile(0,39,0);tile(1,38,0);tile(2,82,0); // 10 秒
  snapshot(4'b1011);tile(0,39,0);tile(1,43,0);tile(2,82,0); // 15 秒
  snapshot(4'b1100);autoplay_word=0;
  tile(0,41,0);tile(1,38,0);tile(2,82,0); // 30 秒 stays coherent for the frame
  $display("PASS autoplay settings raster: off and all five seconds values, coherent frame snapshot");$finish;
 end
 initial begin #1000000;$fatal(1,"autoplay menu timeout");end
endmodule
