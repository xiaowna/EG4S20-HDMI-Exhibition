`timescale 1ns/1ps
module tb_home_control;
 reg clk=0,rst_n=0,vsync=1,product_mode=1,mode_change=0,setting_active=0;
 reg [3:0] key_press=0;reg home_request=0;reg catalog_ready=1;reg [5:0] image_count=32;
 wire [4:0] first_image;wire [5:0] image_limit;wire [1:0] music_index;
 reg switching=0,album_ready=0,album_error=0;
 wire visible,starting,play_request,autoplay_request;wire [2:0] index;wire [14:0] home_word;
 integer plays=0,autos=0;
 always #5 clk=~clk;
 media_home_control dut(.view_ready(1'b0),.view_active(),.*);
 home_album_config config_data(.folder_info(25'd0),.*);
 always @(posedge clk)if(rst_n)begin
  if(play_request)plays<=plays+1;if(autoplay_request)autos<=autos+1;
 end
 task ticks(input integer n);repeat(n)begin @(negedge clk);#1;end endtask
 task press(input [3:0] k);begin key_press=k;ticks(1);key_press=0;ticks(1);end endtask
 task frame_tick;begin vsync=0;ticks(5);vsync=1;ticks(5);end endtask
 task turn(input bit back,input integer target);begin
  press(back?4:1);repeat(19)frame_tick();ticks(2);
  if(index!=target||home_word[10]||!visible)$fatal(1,"carousel wrap/easing commit target=%0d got=%0d",target,index);
 end endtask
 task enter_album;begin
  press(2);if(!starting||plays==0)$fatal(1,"confirmation did not start preparation");
  // Old ready must not bypass the required audio flush observation.
  album_ready=1;ticks(3);if(home_word[13:11]!=1)$fatal(1,"opened before audio fence");
  switching=1;ticks(3);switching=0;ticks(3);
  if(home_word[13:11]!=2||autos==0)$fatal(1,"ready picture/audio did not open");
  repeat(19)frame_tick();if(visible||starting)$fatal(1,"home did not retire");
 end endtask
 initial begin
  ticks(2);rst_n=1;ticks(2);
  for(integer j=1;j<=10;j=j+1)turn(0,j%5);
  turn(1,4);if(first_image!=0||image_limit!=6||music_index!=0)$fatal(1,"fifth config");
  // Confirmation during an animation uses the arriving card descriptor.
  press(1);repeat(7)frame_tick();press(2);repeat(12)frame_tick();ticks(2);
  if(index!=0||!starting||first_image!=0||music_index!=0||plays!=1)$fatal(1,"queued OK selected departing card");
  album_error=1;ticks(2);album_error=0;if(!visible||!home_word[0])$fatal(1,"failed album was not reported");
  image_count=4;turn(0,1);press(2);
  if(starting||plays!=1||!home_word[0])$fatal(1,"empty album launched IO");
  // A rapid reversal is retained once and finishes without a discontinuity.
  image_count=32;press(1);repeat(6)frame_tick();press(4);
  repeat(13)frame_tick();ticks(3);repeat(19)frame_tick();ticks(3);
  if(index!=1||home_word[10])$fatal(1,"queued reversal");
  setting_active=1;press(1);press(2);ticks(2);
  if(index!=1||starting)$fatal(1,"home stole settings commands");setting_active=0;
  enter_album();
  // Closing settings (including a subpage exit) must retain the album.
  repeat(3)begin
   setting_active=1;ticks(2);setting_active=0;ticks(2);
   if(visible||starting||home_word[13:11]!=3)$fatal(1,"closing settings jumped from album to home");
   repeat(20)frame_tick();ticks(2);
   if(visible||plays!=2||autos!=1)$fatal(1,"settings exit changed album or restarted playback");
  end
  // SW7 preserves selection but cancels partial home gestures/preparation.
  press(4);repeat(4)frame_tick();mode_change=1;product_mode=0;ticks(1);mode_change=0;ticks(2);
  if(visible||starting||home_word[10])$fatal(1,"demo retained home operation");
  product_mode=1;mode_change=1;ticks(1);mode_change=0;ticks(2);
  if(!visible||index!=1)$fatal(1,"mode return lost home selection");
  $display("PASS home control: five wraps, queued confirmation/reversal, empty/failure guards, settings/back and SW7; plays=%0d autos=%0d",plays,autos);$finish;
 end
 initial begin #1000000;$fatal(1,"home control timeout");end
endmodule
