`timescale 1ns/1ps
module tb_solar_control;
 reg [2:0] scene_key_press=0;wire scene_mode;wire [1:0] zoom;
 reg clk=0,rst_n=0,enable=1,frame_tick=0,pause_controls=0;
 reg [4:0] key_press=0,key_stable_n=31;
 reg right_pulse=0,left_pulse=0,ok_pulse=0;reg [1:0] menu_speed=0;
 wire [3:0] direction_pulse=4'd0;
 wire [6:0] yaw,pitch;
 always #10 clk=~clk;
 media_3d_control #(.GENERAL_KEYS(1),.HOLD_FRAMES(3),.REPEAT_FRAMES(2)) dut(.*,.zoom_toggle(1'b0));
 integer i;
 reg [6:0] preset_yaw[0:7];reg [3:0] preset_elevation[0:7];
 task ticks(input integer n);repeat(n)@(negedge clk);endtask
 task general_key(input integer n);
 begin right_pulse=n==0;left_pulse=n==1;ok_pulse=n==2;ticks(1);right_pulse=0;left_pulse=0;ok_pulse=0;ticks(1);end
 endtask
 task physical(input [4:0] mask);
 begin key_press=mask;key_stable_n=~mask;ticks(1);key_press=0;ticks(1);key_stable_n=31;ticks(2);end
 endtask
 task frame;begin frame_tick=1;ticks(1);frame_tick=0;ticks(1);end endtask
 initial begin
  preset_yaw[0]=12;preset_elevation[0]=10;
  preset_yaw[1]=12;preset_elevation[1]=2;
  preset_yaw[2]=0;preset_elevation[2]=8;
  preset_yaw[3]=32;preset_elevation[3]=8;
  preset_yaw[4]=64;preset_elevation[4]=8;
  preset_yaw[5]=96;preset_elevation[5]=8;
  preset_yaw[6]=12;preset_elevation[6]=15;
  preset_yaw[7]=76;preset_elevation[7]=4;
  ticks(4);rst_n=1;ticks(4);
  if(yaw!=12||pitch!=83)$fatal(1,"initial camera/speed");
  for(i=0;i<10;i=i+1)general_key(0);
  if(pitch[2:0]!=7||yaw!=12)$fatal(1,"maximum speed clamp");
  for(i=0;i<10;i=i+1)general_key(1);
  if(pitch[2:0]!=0||yaw!=12)$fatal(1,"minimum speed clamp");
  right_pulse=1;left_pulse=1;ticks(1);right_pulse=0;left_pulse=0;ticks(1);
  if(pitch[2:0]!=0)$fatal(1,"opposite commands not cancelled");
  for(i=1;i<=8;i=i+1)begin
   general_key(2);
   if(yaw!=preset_yaw[i%8]||pitch[6:3]!=preset_elevation[i%8]||pitch[2:0]!=0)
    $fatal(1,"preset %0d did not select its independent camera or preserve speed",i%8);
  end
  physical(5'b10000);if(pitch[6:3]!=9)$fatal(1,"KEY6 camera down");
  physical(5'b01000);if(pitch[6:3]!=10)$fatal(1,"KEY14 camera up");
  physical(5'b00010);if(yaw!=12||pitch!=83)$fatal(1,"KEY10 reset");
  physical(5'b00100);if(yaw!=11)$fatal(1,"KEY11 camera left");
  physical(5'b00001);if(yaw!=12)$fatal(1,"KEY9 camera right");
  key_press=1;key_stable_n=30;ticks(1);key_press=0;ticks(1);
  for(i=0;i<3;i=i+1)frame();
  if(yaw!=14||pitch[2:0]!=3)$fatal(1,"held KEY9 repeat camera %0d",yaw);
  pause_controls=1;general_key(1);general_key(2);frame();
  if(yaw!=14||pitch!=83)$fatal(1,"settings failed to suspend controls");
  menu_speed=1;ticks(1);menu_speed=0;ticks(1);
  if(yaw!=14||pitch!=84)$fatal(1,"settings speed change moved camera");
  menu_speed=2;ticks(1);menu_speed=0;ticks(1);
  if(yaw!=14||pitch!=83)$fatal(1,"settings speed down");
  pause_controls=0;key_stable_n=31;ticks(3);enable=0;ticks(2);
  if(yaw!=12||pitch!=83)$fatal(1,"entry defaults");
  enable=1;ticks(3);
  for(i=0;i<25;i=i+1)physical(5'b10000);
  if(pitch[6:3]!=1)$fatal(1,"camera minimum elevation");
  for(i=0;i<25;i=i+1)physical(5'b01000);
  if(pitch[6:3]!=15)$fatal(1,"camera maximum elevation");
  for(i=0;i<128;i=i+1)physical(5'b00001);
  if(yaw!=12)$fatal(1,"azimuth wrap");
  $display("PASS solar control: eight distinct camera presets, four directions, eight time speeds, elevation limits, azimuth wrap, repeat, pause and reset");$finish;
 end
 initial begin #1000000;$fatal(1,"control timeout");end
endmodule
