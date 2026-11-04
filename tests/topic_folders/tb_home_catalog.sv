`timescale 1ns/1ps
module tb_topic_home_catalog;
 reg clk50=0,rst_n=0,sd_miso=1,mode_sw7=1;
 reg encoder_a=1,encoder_b=1,encoder_press_n=1,infrared_n=1;
 wire [3:0] key_col_n=15;wire [3:0] key_row_n,led;
 wire sd_sck,sd_mosi,sd_cs,hdmi_clk_p,hdmi_d0_p,hdmi_d1_p,hdmi_d2_p,rtc_scl,rtc_ce;tri0 rtc_sda;
 reg [24:0] folders=0;reg [3:0] events=0;integer plays=0;
 always #10 clk50=~clk50;
 hdmi_media_board_top dut(.*);
 defparam dut.keyboard.SCAN_CYCLES=4,dut.keys.COUNT=8,dut.mode_control.DEBOUNCE_CYCLES=8;
 task tick;begin @(negedge dut.sys_clk);#1;end endtask
 always @(posedge dut.sys_clk)if(dut.home_play)begin
  if(!dut.folder_ui_ready||dut.album_first!=0||dut.album_limit!=2)$fatal(1,"queued OK used partial/stale catalogue ranges");
  plays=plays+1;
 end
 initial begin
  force dut.folder_info=folders;force dut.control_event=events;
  repeat(5)tick;rst_n=1;dut.u_pll.lock_enable=1;
  wait(dut.keys_rst_n&&!dut.mode_switching);repeat(30)tick;
  if(!dut.home_visible||dut.folder_ui_ready)$fatal(1,"initial UI catalogue guard");
  events=2;tick;events=0;repeat(10)tick;
  if(plays||dut.home_starting)$fatal(1,"OK while scan unfinished launched playback");
  folders={1'b1,6'd6,6'd5,6'd2,6'd2};dut.u_player.mock_image_count=6;
  dut.u_player.mock_catalog_ready=1;dut.u_player.mock_album_ready=1;
  events=2;
  #1;if(dut.folder_ui_ready||dut.homepage.control.catalog_ready)$fatal(1,"ready bypassed register");
  tick;if(!dut.folder_ui_ready||dut.folder_info_ui!==folders||dut.album_limit!=2)$fatal(1,"atomic folder publication");
  events=0;tick;if(plays)$fatal(1,"first ready edge used stale ranges");
  events=2;tick;events=0;
  wait(plays==1);repeat(5)tick;
  dut.u_player.mock_catalog_ready=0;#1;
  if(dut.homepage.control.catalog_ready)$fatal(1,"rescan retains stale UI readiness");
  tick;if(dut.folder_ui_ready||dut.folder_info_ui!=0)$fatal(1,"rescan failed to clear UI snapshot");
  $display("PASS topic UI register: OK blocked until atomic unequal-folder ranges are ready;20ns retime, rescan immediately blocks and clears stale metadata");$finish;
 end
 initial begin #3000000;$fatal(1,"topic home publication timeout");end
endmodule
