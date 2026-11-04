`timescale 1ns/1ps
module tb_ir_fixed_board;
 reg clk50=0,rst_n=1,sd_miso=1,mode_sw7=1,infrared_n=1;
 reg [15:0] pressed=0;
 tri [3:0] key_col_n,key_row_n;wire rtc_scl,rtc_ce;tri0 rtc_sda;
 wire [3:0] led;wire sd_sck,sd_mosi,sd_cs,hdmi_clk_p,hdmi_d0_p,hdmi_d1_p,hdmi_d2_p;
 always #10 clk50=~clk50;
 dmz_keyboard_model keyboard_model(.*,.row_n(key_row_n),.col_n(key_col_n));
 // Actual codes observed by the user on the capture image, 2026-10-25.
 hdmi_media_board_top #(.IR_FIXED_ENABLE(1),.IR_FIXED_KEYS(48'h000915074316),
  .IR_EXTRA_ENABLE(1),.IR_EXTRA_KEYS(24'h0d4645)) dut(.*);
 defparam dut.infrared.SAMPLE_CYCLES=1,dut.keyboard.SCAN_CYCLES=4,dut.keys.COUNT=8,dut.mode_control.DEBOUNCE_CYCLES=8;
 task cycles(input integer n);begin repeat(n)@(negedge dut.sys_clk);#2;end endtask
 task level(input bit v,input integer n);begin infrared_n=v;cycles(n);end endtask
 task frame(input [7:0] c);
  reg [31:0] data;integer i;
  begin
   data={~c,c,8'hff,8'h00};level(1,19000);level(0,900);level(1,450);
   for(i=0;i<32;i=i+1)begin level(0,56);level(1,data[i]?169:56);end
   level(0,56);level(1,100);
  end
 endtask
 task video_frame;begin dut.u_player.mock_vsync=0;cycles(10);dut.u_player.mock_vsync=1;cycles(10);end endtask
 initial begin
  dut.u_pll.lock_enable=1;#1;rst_n=0;dut.u_pll.lock_enable=0;
  cycles(8);rst_n=1;cycles(8);dut.u_pll.lock_enable=1;cycles(500);
  dut.u_player.mock_catalog_ready=1;dut.u_player.mock_image_count=24;
  if(!dut.infrared.paired||dut.ir_learning||!dut.home_visible)$fatal(1,"fixed boot");
  frame(8'h07);repeat(19)video_frame();cycles(2);
  if(dut.home_index!=4)$fatal(1,"fixed LEFT home selection");
  frame(8'h15);cycles(100);repeat(19)video_frame();cycles(3);
  if(!dut.view_active||dut.home_visible)$fatal(1,"fixed OK enter solar");
  frame(8'h43);if(!dut.setting_active)$fatal(1,"fixed SETTINGS");
  frame(8'h0d);if(dut.home_visible||!dut.view_active||dut.setting_active)$fatal(1,"BACK did not close menu in solar");
  frame(8'h43);frame(8'h16);if(!dut.home_visible||dut.view_active||dut.setting_active)$fatal(1,"remote HOME did not close settings and leave solar");
  frame(8'h09);repeat(19)video_frame();cycles(2);
  if(dut.home_index!=0)$fatal(1,"fixed RIGHT home selection");
  frame(8'h15);cycles(100);dut.u_player.mock_album_ready=1;cycles(20);repeat(19)video_frame();cycles(3);
  if(dut.home_visible||dut.view_active)$fatal(1,"fixed OK album entry");
  frame(8'h43);if(!dut.setting_active)$fatal(1,"album SETTINGS");
  force dut.rtc_busy=1'b1;frame(8'h0d);
  if(dut.home_visible||!dut.setting_active)$fatal(1,"BACK aborted in-flight calendar save");
  frame(8'h16);
  if(dut.home_visible||!dut.setting_active)$fatal(1,"HOME aborted in-flight calendar save");
  release dut.rtc_busy;frame(8'h0d);
  if(dut.home_visible||dut.setting_active)$fatal(1,"BACK must keep album");
  frame(8'h0d);if(!dut.home_visible)$fatal(1,"BACK from album must return to parent home");
  frame(8'h46);frame(8'h45);frame(8'h09);frame(8'h46);frame(8'h45);
  if(dut.ir_easter_toggle)$fatal(1,"wrong sequence triggered secret");
  frame(8'h46);frame(8'h45);
  if(!dut.ir_easter_toggle||dut.home_index!=0||dut.setting_active)$fatal(1,"secret completion/navigation leak");
  rst_n=0;cycles(8);rst_n=1;cycles(500);
  if(!dut.infrared.paired||dut.ir_learning)$fatal(1,"fixed board reset lost remote");
  if(dut.ir_easter_toggle)$fatal(1,"reset must clear secret");
  $display("PASS fixed IR board: actual captured six navigation keys, parent BACK versus HOME, calendar-write fences, secret sequence, reset without learning");$finish;
 end
 initial begin #50000000;$fatal(1,"fixed board timeout");end
endmodule
