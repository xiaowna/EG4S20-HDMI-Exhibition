`timescale 1ns/1ps
module tb_3d_keys_board;
 reg clk=0,rst_n=0,enable=0,frame_tick=0;
 reg [15:0] pressed=0;
 tri [3:0] row_n,col_n;
 wire [3:0] normal_key_n;
 wire [4:0] view_key_n;
 wire ready;
 wire [8:0] all_press,all_stable_n;
 wire [6:0] yaw,pitch;
 integer normal_events=0;
 always #5 clk=~clk;
 dmz_keyboard_model switches(.pressed(pressed),.row_n(row_n),.col_n(col_n));
 board_matrix_keys #(.SCAN_CYCLES(4),.VIEW_KEYS(1)) scanner(.clk(clk),.rst_n(rst_n),
  .col_n(col_n),.row_n(row_n),.key_n(normal_key_n),.view_key_n(view_key_n),.ready(ready));
 board_key #(.COUNT(12),.WIDTH(9)) keys(.clk(clk),.rst_n(rst_n&&ready),
  .key_n({view_key_n,normal_key_n}),.press(all_press),.stable_n(all_stable_n));
 media_3d_control controls(.clk(clk),.rst_n(rst_n),.enable(enable),.pause_controls(1'b0),.frame_tick(frame_tick),
  .key_press(all_press[8:4]),.key_stable_n(all_stable_n[8:4]),.yaw(yaw),.pitch(pitch));
 always @(posedge clk)if(rst_n&&|all_press[3:0])normal_events<=normal_events+1;
 task ticks(input integer n);repeat(n)begin @(negedge clk);#1;end endtask
 task tap(input integer k);begin pressed=16'b1<<k;ticks(180);pressed=0;ticks(180);end endtask
 initial begin
  ticks(2);rst_n=1;ticks(180);enable=1;ticks(5);
  tap(14);if(yaw!=12||pitch!=11)$fatal(1,"physical KEY14 up");
  tap(6);if(yaw!=12||pitch!=10)$fatal(1,"physical KEY6 down");
  tap(11);if(yaw!=11||pitch!=10)$fatal(1,"physical KEY11 left");
  tap(9);if(yaw!=12||pitch!=10)$fatal(1,"physical KEY9 right");
  tap(14);tap(11);tap(10);if(yaw!=12||pitch!=10)$fatal(1,"physical KEY10 reset");
  if(normal_events)$fatal(1,"3D keys leaked into normal four-key controls");
  for(integer i=1;i<=4;i=i+1)tap(i);
  if(normal_events!=4||yaw!=12||pitch!=10)$fatal(1,"normal controls changed/lost");
  // Multi-key/ghost rejection remains latched until every contact releases.
  pressed=(16'b1<<9)|(16'b1<<14);ticks(180);pressed=16'b1<<9;ticks(180);
  if(yaw!=12||pitch!=10)$fatal(1,"chord released only partly was accepted");
  pressed=0;ticks(180);tap(9);if(yaw!=13)$fatal(1,"3D key failed to rearm");
  $display("PASS physical 3D keys: KEY14/10/11/9/6 mapping, shared debounce, no gallery leakage, normal KEY1..4 preserved, chord/release lock");$finish;
 end
 initial begin #1000000;$fatal(1,"3D key board timeout");end
endmodule
