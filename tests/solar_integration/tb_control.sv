`timescale 1ns/1ps
module tb_solar_home_control;
 reg clk=0,rst_n=0,vsync=1,product_mode=1,mode_change=0,setting_active=0,home_request=0;
 reg [3:0] key_press=0;reg catalog_ready=1;reg [5:0] image_count=24;
 reg switching=0,album_ready=0,album_error=0,view_ready=0;
 wire [4:0] first_image;wire [5:0] image_limit;wire [1:0] music_index;
 wire visible,starting,play_request,autoplay_request,view_active;
 wire [2:0] index;wire [14:0] home_word;integer plays=0,autos=0;
 always #5 clk=~clk;
 media_home_control #(.VIEW_3D(1),.EXHIBIT(1)) dut(.*);
 home_album_config config_data(.folder_info(25'd0),.*);
 always @(posedge clk)if(rst_n)begin
  if(play_request)plays<=plays+1;if(autoplay_request)autos<=autos+1;
 end
 task ticks(input integer n);repeat(n)begin @(negedge clk);#1;end endtask
 task press(input [3:0] k);begin key_press=k;ticks(1);key_press=0;ticks(1);end endtask
 task frame_tick;begin vsync=0;ticks(5);vsync=1;ticks(5);end endtask
 task go_home;begin home_request=1;ticks(1);home_request=0;ticks(2);end endtask
 task turn_left;begin press(4);repeat(19)frame_tick();ticks(2);end endtask
 task ready_page(input bit view);begin
  if(view)view_ready=1;else album_ready=1;
  ticks(3);if(home_word[12:11]!=1)$fatal(1,"prepared page bypassed audio fence");
  switching=1;ticks(3);switching=0;ticks(3);
  if(home_word[12:11]!=2)$fatal(1,"prepared page did not open after audio fence");
  repeat(19)frame_tick();ticks(2);
  if(visible||starting||home_word[12:11]!=3)$fatal(1,"page did not retire home overlay");
 end endtask
 initial begin
  ticks(2);rst_n=1;ticks(2);
  if(!visible||!home_word[13]||starting||view_active)$fatal(1,"first-entry cover missing");
  press(1);repeat(20)frame_tick();ticks(2);
  if(home_word[13]||index!=0||home_word[10]||plays!=0)$fatal(1,"first navigation leaked into card selection");
  press(2);if(!starting||plays!=1)$fatal(1,"second navigation did not start first topic");
  ready_page(0);
  setting_active=1;press(8);ticks(2);setting_active=0;press(8);ticks(2);
  if(visible||starting||view_active||plays!=1)$fatal(1,"KEY4 settings exit lost album page");
  go_home();
  if(!visible||home_word[13]||index!=0)$fatal(1,"KEY0 should return to carousel without cover");
  turn_left();if(index!=4||first_image>=24||image_limit>24)$fatal(1,"solar card config is outside 24-image profile");
  press(2);if(!starting||!view_active||plays!=2)$fatal(1,"solar card not launched");
  ready_page(1);
  setting_active=1;press(8);ticks(2);setting_active=0;press(8);ticks(2);
  if(visible||starting||!view_active||plays!=2)$fatal(1,"KEY4 settings exit lost solar page");
  go_home();
  if(!visible||view_active||home_word[13]||index!=4)$fatal(1,"KEY0 did not retire solar page");
  mode_change=1;product_mode=0;ticks(1);mode_change=0;ticks(3);
  if(visible||view_active||starting)$fatal(1,"demo mode retained exhibit overlay");
  mode_change=1;product_mode=1;ticks(1);mode_change=0;ticks(3);
  if(!visible||home_word[13]||index!=4||plays!=2)$fatal(1,"mode return reset cover/selection or restarted music");
  rst_n=0;ticks(3);rst_n=1;ticks(3);press(2);
  if(home_word[13]||starting||index!=0||home_word[10])$fatal(1,"first OK should only dismiss cover");
  rst_n=0;ticks(3);rst_n=1;ticks(3);go_home();
  if(home_word[13]||starting||index!=0)$fatal(1,"KEY0 should also dismiss cover safely");
  $display("PASS solar home control: first navigation/OK dismiss cover only; KEY0, KEY4 album/solar retention, audio fence and SW7 exits");$finish;
 end
 initial begin #1000000;$fatal(1,"solar home control timeout");end
endmodule
