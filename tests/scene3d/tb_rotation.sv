`timescale 1ns/1ps
module tb_3d_control;
 reg [2:0] scene_key_press=0;wire scene_mode;wire [1:0] zoom;
 parameter HOLD=12,INTERVAL=2;
 reg clk=0,rst_n=0,enable=0,frame_tick=0;
 reg [4:0] key_press=0,key_stable_n=31;
 wire [3:0] direction_pulse=4'd0;
 wire [6:0] yaw,pitch;
 integer checks=0;
 always #5 clk=~clk;
 media_3d_control #(.HOLD_FRAMES(HOLD),.REPEAT_FRAMES(INTERVAL)) dut(.pause_controls(1'b0),.menu_speed(2'd0),.*,.zoom_toggle(1'b0));
 task ticks(input integer n);repeat(n)begin @(negedge clk);#1;end endtask
 task frame;begin frame_tick=1;ticks(1);frame_tick=0;ticks(1);end endtask
 task press(input [4:0] k);begin key_stable_n=~k;key_press=k;ticks(1);key_press=0;ticks(1);end endtask
 task release_keys;begin key_stable_n=31;ticks(2);end endtask
 task click(input [4:0] k);begin press(k);release_keys();end endtask
 task expect_angle(input integer y,p);begin checks=checks+1;
  if(yaw!==y[6:0]||pitch!==p[6:0])$fatal(1,"rotation expected %0d/%0d got %0d/%0d",y,p,yaw,pitch);
 end endtask
 integer initial_yaw;
 initial begin
  ticks(2);rst_n=1;enable=1;release_keys();expect_angle(12,10);
  for(integer j=1;j<=128;j=j+1)begin click(1);expect_angle((12+j)%128,10);end
  for(integer j=1;j<=128;j=j+1)begin click(4);expect_angle((140-j)%128,10);end
  for(integer j=1;j<=128;j=j+1)begin click(8);expect_angle(12,(10+j)%128);end
  for(integer j=1;j<=128;j=j+1)begin click(16);expect_angle(12,(138-j)%128);end
  click(1);click(8);click(2);expect_angle(12,10);
  press(1);expect_angle(13,10);
  repeat(HOLD-1)frame();expect_angle(13,10);frame();expect_angle(14,10);
  for(integer k=1;k<=20;k=k+1)begin repeat(INTERVAL)frame();expect_angle(14+k,10);end
  release_keys();repeat(20)frame();expect_angle(34,10);
  // Reset stays a one-shot action even when held for many video frames.
  press(2);repeat(30)frame();expect_angle(12,10);release_keys();
  // Held controls across view/mode entry require a complete stable release.
  enable=0;press(1);repeat(5)frame();enable=1;repeat(30)frame();expect_angle(12,10);
  release_keys();click(4);expect_angle(11,10);
  // Up/down/left/right ambiguity must not choose an arbitrary direction.
  click(5);click(24);expect_angle(11,10);
  enable=0;ticks(2);expect_angle(12,10);enable=1;release_keys();
  $display("PASS 3D controls HOLD=%0d INTERVAL=%0d: %0d angle checks, 512 wrapped turns, reset, held repeat, release/mode gating and conflicting controls",HOLD,INTERVAL,checks);$finish;
 end
 initial begin #1000000;$fatal(1,"3D control timeout");end
endmodule
