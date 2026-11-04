`timescale 1ns/1ps
module tb_ir_direction_board;
 reg clk50=0,rst_n=1,sd_miso=1,mode_sw7=1,infrared_n=1;
 reg [15:0] pressed=0;
 tri [3:0] key_col_n,key_row_n;wire rtc_scl,rtc_ce;tri0 rtc_sda;
 wire [3:0] led;wire sd_sck,sd_mosi,sd_cs,hdmi_clk_p,hdmi_d0_p,hdmi_d1_p,hdmi_d2_p;
 always #10 clk50=~clk50;
 dmz_keyboard_model keyboard_model(.*,.row_n(key_row_n),.col_n(key_col_n));
 hdmi_media_board_top dut(.*);
 defparam dut.infrared.SAMPLE_CYCLES=1,dut.keyboard.SCAN_CYCLES=4,dut.keys.COUNT=8,dut.mode_control.DEBOUNCE_CYCLES=8;
 reg [6:0] saved_yaw,saved_pitch;integer right_events=0,left_events=0,checks=0;
 always @(posedge dut.sys_clk)begin
  if(dut.control_event[0])right_events=right_events+1;
  if(dut.control_event[2])left_events=left_events+1;
 end
 task cycles(input integer n);begin repeat(n)@(negedge dut.sys_clk);#2;end endtask
 task level(input bit v,input integer n);begin infrared_n=v;cycles(n);end endtask
 task frame(input [7:0] a,c);
  reg [31:0] data;integer i;
  begin
   data={~c,c,~a,a};level(1,19000);level(0,900);level(1,450);
   for(i=0;i<32;i=i+1)begin level(0,56);level(1,data[i]?169:56);end
   level(0,56);level(1,100);
  end
 endtask
 task repeat_frame;begin
  level(1,4000);level(0,900);level(1,225);level(0,56);level(1,100);
 end endtask
 task video_frame;begin dut.u_player.mock_vsync=0;cycles(10);dut.u_player.mock_vsync=1;cycles(10);end endtask
 task save_camera;begin saved_yaw=dut.view_yaw;saved_pitch=dut.view_pitch;end endtask
 task unchanged;begin
  if(dut.view_yaw!==saved_yaw||dut.view_pitch!==saved_pitch)$fatal(1,"paused/context-blocked camera moved");checks=checks+1;
 end endtask
 task directions;
  integer r,l;begin
   r=right_events;l=left_events;save_camera;
   frame(0,8'h40);
   if(dut.view_pitch[6:3]!==saved_pitch[6:3]+4'd1||dut.view_yaw!==saved_yaw||dut.view_pitch[2:0]!==saved_pitch[2:0])$fatal(1,"IR UP must elevate camera only");checks=checks+1;
   frame(0,8'h19);unchanged;
   frame(0,8'h09);
   if(dut.view_yaw!==saved_yaw+7'd1||dut.view_pitch!==saved_pitch)$fatal(1,"IR RIGHT must orbit camera, preserving speed");checks=checks+1;
   frame(0,8'h07);unchanged;
   if(right_events!=r||left_events!=l)$fatal(1,"3D IR horizontal keys leaked into general speed/navigation events");
   frame(1,8'h40);unchanged;
  end
 endtask
 task tap(input integer n);begin pressed=16'b1<<n;cycles(100);pressed=0;cycles(100);end endtask
 initial begin
  dut.u_pll.lock_enable=1;#1;rst_n=0;dut.u_pll.lock_enable=0;
  cycles(8);rst_n=1;cycles(8);dut.u_pll.lock_enable=1;cycles(500);
  dut.u_player.mock_catalog_ready=1;dut.u_player.mock_image_count=24;cycles(5);
  if(!dut.home_visible||dut.home_index!=0)$fatal(1,"home startup");
  frame(0,8'h45);
  if(!dut.home_visible||dut.home_index!=0||dut.scene_mode)$fatal(1,"0045 must be inactive on home");
  frame(0,8'h40);frame(0,8'h19);
  if(dut.home_index!=0||!dut.home_visible)$fatal(1,"UP/DOWN must not navigate home");
  frame(0,8'h07);repeat(19)video_frame();cycles(2);
  if(dut.home_index!=4)$fatal(1,"LEFT must retain home navigation");
  frame(0,8'h15);cycles(100);repeat(19)video_frame();cycles(3);
  if(!dut.view_active||dut.home_visible||dut.scene_mode)$fatal(1,"enter solar");
  directions;
  save_camera;tap(1);
  if(dut.view_yaw!==saved_yaw||dut.view_pitch[6:3]!==saved_pitch[6:3]||dut.view_pitch[2:0]!==saved_pitch[2:0]+3'd1)$fatal(1,"physical KEY1 speed behavior lost");
  tap(3);unchanged;
  frame(0,8'h45);
  if(!dut.scene_mode||dut.scene_zoom!=1||dut.view_yaw!=0||dut.view_pitch[6:3]!=3)
   $fatal(1,"0045 must select Earth-Moon using KEY5's initial view");
  repeat(8)repeat_frame();
  if(!dut.scene_mode)$fatal(1,"held 0045 repeated the model toggle");
  frame(1,8'h45);if(!dut.scene_mode)$fatal(1,"wrong address toggled model");
  frame(0,8'h45);
  if(dut.scene_mode||dut.scene_zoom!=1||dut.view_yaw!=12||dut.view_pitch[6:3]!=10)
   $fatal(1,"second 0045 must restore solar model and initial view");
  tap(5);if(!dut.scene_mode)$fatal(1,"KEY5 must select Earth-Moon model");
  directions;
  force dut.infrared.model_event=1;force dut.all_key_press=13'h400;
  cycles(1);force dut.infrared.model_event=0;release dut.all_key_press;
  cycles(1);release dut.infrared.model_event;cycles(2);
  if(dut.scene_mode)$fatal(1,"coincident physical KEY5 and 0045 must toggle once");
  tap(5);
  force dut.infrared.model_event=1;force dut.all_key_press=13'h800;
  cycles(1);force dut.infrared.model_event=0;release dut.all_key_press;
  cycles(1);release dut.infrared.model_event;cycles(2);
  if(!dut.scene_mode||dut.scene_zoom!=0)$fatal(1,"physical KEY7 must win over 0045");
  tap(8);
  // A physical key and decoded IR direction can arrive on the same clock.
  // Inject at the decoder/debounce boundaries without bypassing top routing.
  save_camera;force dut.infrared.direction_event=4'b0001;force dut.all_key_press=13'd1;
  cycles(1);force dut.infrared.direction_event=4'd0;release dut.all_key_press;
  cycles(1);release dut.infrared.direction_event;cycles(2);
  if(dut.view_yaw!==saved_yaw||dut.view_pitch[6:3]!==saved_pitch[6:3]||dut.view_pitch[2:0]!==saved_pitch[2:0]+3'd1)
   $fatal(1,"physical KEY1 must win over coincident remote rotation: yaw=%0d/%0d pitch=%0d/%0d",dut.view_yaw,saved_yaw,dut.view_pitch,saved_pitch);checks=checks+1;
  save_camera;force dut.infrared.direction_event=4'b1000;force dut.all_key_press=13'd2;
  cycles(1);force dut.infrared.direction_event=4'd0;release dut.all_key_press;
  cycles(1);release dut.infrared.direction_event;cycles(2);
  if(dut.view_yaw!==7'd12||dut.view_pitch[6:3]!==4'd2||dut.view_pitch[2:0]!==saved_pitch[2:0])
   $fatal(1,"physical KEY2 preset must win over coincident remote rotation");checks=checks+1;
  save_camera;force dut.infrared.direction_event=4'b0001;force dut.all_key_press=13'd8;
  cycles(1);force dut.infrared.direction_event=4'd0;release dut.all_key_press;
  cycles(1);release dut.infrared.direction_event;cycles(2);unchanged;
  if(!dut.setting_active)$fatal(1,"IR SETTINGS failed");
  frame(0,8'h45);unchanged;
  if(!dut.scene_mode||!dut.setting_active)$fatal(1,"0045 leaked through settings");
  frame(0,8'h40);frame(0,8'h19);frame(0,8'h09);frame(0,8'h07);unchanged;
  if(right_events==0||left_events<2)$fatal(1,"menu must retain horizontal IR events");
  frame(0,8'h0d);
  if(dut.setting_active||dut.home_visible||!dut.view_active)$fatal(1,"BACK must close settings and retain scene");
  save_camera;frame(0,8'h15);
  if(dut.view_yaw===saved_yaw&&dut.view_pitch[6:3]===saved_pitch[6:3])$fatal(1,"IR OK must retain preset view cycling");
  frame(0,8'h16);if(!dut.home_visible||dut.view_active)$fatal(1,"IR HOME must leave 3D");
  frame(0,8'h40);frame(0,8'h19);if(!dut.home_visible)$fatal(1,"UP/DOWN leaked outside 3D");
  frame(0,8'h09);repeat(19)video_frame();cycles(2);
  frame(0,8'h15);cycles(100);dut.u_player.mock_album_ready=1;
  cycles(20);repeat(19)video_frame();cycles(3);
  if(dut.view_active||dut.home_visible)$fatal(1,"photo album entry failed");
  frame(0,8'h45);
  if(dut.view_active||dut.home_visible||dut.setting_active||dut.scene_mode)$fatal(1,"0045 must be inactive in photo album");
  $display("PASS IR 3D board: %0d camera assertions, wire-level 0045 model switch/held rejection/KEY5 priority/home-album-settings isolation, 0040/0019/0009/0007 in both models, OK/BACK/HOME/KEY5 preservation",checks);$finish;
 end
 initial begin #50000000;$fatal(1,"direction board timeout");end
endmodule
