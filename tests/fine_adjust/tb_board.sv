`timescale 1ns/1ps
module tb_fine_board;
 reg clk50=0,rst_n=1,sd_miso=1,mode_sw7=1;
 reg infrared_n=1;
 always #10 clk50=~clk50;
 reg [15:0] pressed=0;tri [3:0] key_col_n,key_row_n;wire rtc_scl,rtc_ce;tri0 rtc_sda;
 wire [3:0] led;wire sd_sck,sd_mosi,sd_cs,hdmi_clk_p,hdmi_d0_p,hdmi_d1_p,hdmi_d2_p;
 dmz_keyboard_model keyboard_model(.*,.row_n(key_row_n),.col_n(key_col_n));
 hdmi_media_board_top dut(.*);
 defparam dut.keyboard.SCAN_CYCLES=4,dut.keys.COUNT=8,dut.mode_control.DEBOUNCE_CYCLES=8;
 task cycles(input integer n);begin repeat(n)@(negedge dut.sys_clk);#2;end endtask
 task tap(input integer k);begin pressed=1<<k;cycles(160);pressed=0;cycles(160);end endtask
 task frame;begin dut.u_player.mock_vsync=0;cycles(10);dut.u_player.mock_vsync=1;cycles(10);end endtask
 initial begin
  dut.u_pll.lock_enable=1;#1;rst_n=0;dut.u_pll.lock_enable=0;
  cycles(8);rst_n=1;cycles(8);dut.u_pll.lock_enable=1;cycles(500);
  tap(4);tap(1);
  if(!dut.setting_active||dut.brightness_value!=1||dut.av.fine_adjust_word!={8'd65,7'd50})$fatal(1,"KEY1 fine brightness/word");
  tap(3);tap(3);if(dut.brightness_value!=-1)$fatal(1,"KEY3 fine brightness");
  tap(2);tap(1);
  if(dut.gain_q8_value!=259||dut.contrast_index!=51||dut.av.fine_adjust_word!={8'd63,7'd51})$fatal(1,"KEY1 exact rounded 101 percent");
  tap(1);
  if(dut.contrast_index!=52||dut.gain_q8_value!=261)$fatal(1,"second KEY1 one percent step");
  pressed=1<<1;cycles(160);repeat(25)frame();pressed=0;cycles(160);
  if(dut.contrast_index!=56)$fatal(1,"physical held contrast repeat got %0d",dut.contrast_index);
  if(dut.u_player.next_events||dut.u_player.prev_events)$fatal(1,"menu leaked to gallery");
  tap(4);repeat(30)frame();
  if(dut.contrast_index!=56||dut.brightness_value!=-1||dut.setting_active)$fatal(1,"settings not retained after exit");
  $display("PASS fine production top: real matrix/debounce, held-key vsync repeat, coherent menu fields and playback isolation");$finish;
 end
 initial begin #3000000;$fatal(1,"fine board timeout");end
endmodule
