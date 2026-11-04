`timescale 1ns/1ps
module tb_music_notice;
 reg clk=0,rst_n=0,de=0,vsync=1;reg [9:0] x=0,y=0;
 reg [23:0] rgb_in=0;reg [10:0] settings_word=0;reg [3:0] mode_status=4;
 reg [7:0] music_status=16;reg [48:0] rtc_word=0;reg [53:0] rtc_edit_word=0;
 reg [14:0] fine_adjust_word={8'd64,7'd50},home_word=15'h4000;
 reg music_playing=0;wire [23:0] rgb_out;wire overlay_valid;
 integer i,expected_alpha,checks=0;
 always #5 clk=~clk;
 video_chinese_settings #(.MUSIC_MENU(1),.RTC_SETTING(1),.COMPACT_ROWS(1),.MUSIC_TOAST(1)) dut(.*);
 task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 task frame;begin vsync=0;tick;vsync=1;tick;end endtask
 task check(input integer age,input integer alpha,input integer active,input integer track);
  begin
   if(dut.music_notice.age!==age||dut.toast_alpha!==alpha||dut.toast_active!==active||dut.toast_track!==track)
    $fatal(1,"notice age/alpha/active/track wanted=%0d/%0d/%0d/%0d got=%0d/%0d/%b/%d",age,alpha,active,track,dut.music_notice.age,dut.toast_alpha,dut.toast_active,dut.toast_track);
   checks++;
  end
 endtask
 initial begin
  tick;rst_n=1;tick;music_playing=1;frame;check(298,0,0,0);
  home_word=0;music_playing=0;repeat(50)frame;check(298,0,0,0);
  music_playing=1;frame;check(0,16,1,0);
  for(i=1;i<298;i++)begin
   frame;expected_alpha=i<238?16:(298-i+3)/4;check(i,expected_alpha,1,0);
   if(dut.toast_pose!==(i/8)%8)$fatal(1,"note rotation phase");
  end
  frame;check(298,0,0,0);repeat(400)frame;check(298,0,0,0);
  music_playing=0;frame;music_playing=1;frame;check(298,0,0,0);
  // Requested menu number alone cannot claim a different song is playing.
  music_status=8'h70;frame;check(298,0,0,0);
  settings_word=11'h400;music_status=8'h71;frame;check(298,0,0,0);
  settings_word=0;mode_status=12;frame;check(298,0,0,0);
  mode_status=4;music_playing=0;frame;check(298,0,0,0);
  music_playing=1;frame;check(0,16,1,1);
  settings_word=11'h400;frame;check(298,0,0,1);settings_word=0;frame;check(298,0,0,1);
  home_word=15'h4000;frame;check(298,0,0,1);home_word=0;frame;check(0,16,1,1);
  mode_status=0;frame;check(298,0,0,1);mode_status=4;music_status=0;frame;check(298,0,0,1);
  rst_n=0;tick;check(298,0,0,0);
  $display("PASS music notice timing: %0d checks, 238 full + 60 fade frames, eight poses, no loop/pause retrigger, accepted track/menu/home/demo/reset guards",checks);$finish;
 end
endmodule

module tb_music_pixels;
 reg clk=0,rst_n=0,de=0,vsync=1;reg [9:0] x=0,y=0;
 reg [23:0] rgb_in=0;reg [10:0] settings_word=0;reg [3:0] mode_status=4;
 reg [7:0] music_status=16;reg [48:0] rtc_word=0;reg [53:0] rtc_edit_word=0;
 reg [14:0] fine_adjust_word={8'd64,7'd50},home_word=0;
 reg music_playing=1;wire [23:0] rgb_out;wire overlay_valid;
 integer file,read,xx,yy,age,track,checks=0,fd;reg [24:0] expected,actual;
 always #5 clk=~clk;
 video_chinese_settings #(.MUSIC_MENU(1),.RTC_SETTING(1),.COMPACT_ROWS(1),.MUSIC_TOAST(1)) dut(.*);
 initial begin
  @(negedge clk);rst_n=1;
  file=$fopen("toast_pixels.txt","r");if(!file)$fatal(1,"missing vectors");
  fd=$fopen("toast.ppm","w");$fwrite(fd,"P3\n640 480\n255\n");
  while(!$feof(file))begin
   read=$fscanf(file,"%d %d %d %d %h\n",xx,yy,age,track,expected);
   if(read!=5)$fatal(1,"bad pixel vector");
   x=xx;y=yy;de=1;rgb_in={x[7:0],y[7:0],x[7:0]^y[7:0]};
   // Control timing is tested independently above; seed only the frame pose.
   dut.music_notice.age=age;dut.music_notice.track=track;dut.music_notice.playing_frame=1;
   @(posedge clk);#1;actual={overlay_valid,overlay_valid?rgb_out:rgb_in};
   if(actual!==expected)$fatal(1,"toast RGB xy=%0d,%0d age=%0d track=%0d expected=%h got=%h",xx,yy,age,track,expected,actual);
   if(checks<640*480)$fwrite(fd,"%0d %0d %0d\n",actual[23:16],actual[15:8],actual[7:0]);
   checks++;@(negedge clk);
  end
  de=0;@(posedge clk);#1;if(overlay_valid)$fatal(1,"toast covered blanking");
  $fclose(fd);$fclose(file);
  $display("PASS music toast pixels: %0d independent pixels, all four numbers/eight rotations/16 alpha levels, transparent corners and one-clock alignment",checks);$finish;
 end
endmodule
