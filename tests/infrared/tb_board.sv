`timescale 1ns/1ps
module tb_ir_board;
 reg clk50=0,rst_n=1,sd_miso=1,mode_sw7=1;
 reg encoder_a=1,encoder_b=1,encoder_press_n=1,infrared_n=1;
 always #10 clk50=~clk50;
 reg [15:0] pressed=0;
 tri [3:0] key_col_n,key_row_n;
 wire [3:0] led;
 wire sd_sck,sd_mosi,sd_cs,hdmi_clk_p,hdmi_d0_p,hdmi_d1_p,hdmi_d2_p;
 dmz_keyboard_model keyboard_model(.*,.row_n(key_row_n),.col_n(key_col_n));
 wire rtc_scl,rtc_ce;tri0 rtc_sda;
 hdmi_media_board_top #(.FINE_ADJUST(0),.HOME_UI(0),.IR_FIXED_ENABLE(0)) dut(.*);
 defparam dut.infrared.SAMPLE_CYCLES=1,dut.infrared.RELEASE_TICKS=80;
 defparam dut.infrared.LEARN_HOLD_TICKS=200,dut.infrared.LEARN_TIMEOUT_TICKS=100000;
 defparam dut.keyboard.SCAN_CYCLES=4,dut.keys.COUNT=8,dut.mode_control.DEBOUNCE_CYCLES=8;
 task cycles(input integer n);begin repeat(n)@(negedge dut.sys_clk);#2;end endtask
 task level(input bit v,input integer n);begin infrared_n=v;cycles(n);end endtask
 task frame(input [7:0] a,c);reg [31:0] data;integer i;begin
  data={~c,c,~a,a};level(1,600);level(0,900);level(1,450);
  for(i=0;i<32;i=i+1)begin level(0,56);level(1,data[i]?169:56);end
  level(0,56);level(1,100);
 end endtask
 task repeat_frame;begin level(1,4000);level(0,900);level(1,225);level(0,56);level(1,100);end endtask
 task learn;begin
  pressed=0;cycles(160);pressed=16'h0010;cycles(350);
  if(!dut.ir_learning||dut.setting_active||led[2:0]!=1)$fatal(1,"physical KEY4 learning/menu close");
  pressed=0;cycles(160);
 end endtask
 integer next_before,prev_before;
 initial begin
  dut.u_pll.lock_enable=1;#1;rst_n=0;dut.u_pll.lock_enable=0;
  cycles(8);rst_n=1;cycles(8);dut.u_pll.lock_enable=1;cycles(500);
  if(!dut.product_mode||dut.mode_switching||dut.setting_active)$fatal(1,"boot product");
  frame(8'h42,8'ha1);if(dut.u_player.next_events!=0)$fatal(1,"unpaired gallery event");
  learn;
  dut.u_player.mock_faults=1;cycles(2);if(led!=9)$fatal(1,"error LED hidden during learning");
  dut.u_player.mock_faults=0;
  frame(8'h42,8'ha1);if(led[2:0]!=2)$fatal(1,"learn right LED");
  repeat_frame;frame(8'h42,8'ha1);if(led[2:0]!=2)$fatal(1,"held/duplicate advanced learning");
  frame(8'h42,8'h12);if(led[2:0]!=3)$fatal(1,"learn OK LED");
  frame(8'h42,8'h33);if(led[2:0]!=4)$fatal(1,"learn left LED");
  frame(8'h42,8'hb4);if(!dut.ir_learning||led[2:0]!=5||dut.infrared.paired)$fatal(1,"fifth HOME key must be learned atomically");
  frame(8'h42,8'hb4);if(led[2:0]!=5)$fatal(1,"duplicate settings accepted as HOME");
  frame(8'h42,8'hc5);if(dut.ir_learning||!dut.infrared.paired)$fatal(1,"five-key learn complete");
  repeat_frame;frame(8'h42,8'hc5);
  if(dut.setting_active||dut.paused||dut.u_player.next_events!=0||dut.u_player.prev_events!=0)$fatal(1,"learning leaked control");
  frame(8'h42,8'ha1);frame(8'h42,8'h33);
  if(dut.u_player.next_events!=1||dut.u_player.prev_events!=1)$fatal(1,"IR gallery");
  frame(8'h42,8'h12);if(!dut.paused)$fatal(1,"IR pause");
  repeat_frame;frame(8'h42,8'h12);if(!dut.paused)$fatal(1,"held OK resumed");
  level(1,18500);frame(8'h42,8'h12);if(dut.paused)$fatal(1,"IR resume after release");
  frame(8'h42,8'hb4);if(!dut.setting_active)$fatal(1,"IR settings");
  repeat_frame;if(!dut.setting_active)$fatal(1,"held settings closed");
  frame(8'h42,8'ha1);if(dut.brightness_value!=32)$fatal(1,"IR brightness");
  frame(8'h42,8'h12);frame(8'h42,8'ha1);if(dut.gain_q8_value!=320)$fatal(1,"IR contrast");
  frame(8'h42,8'h12);frame(8'h42,8'ha1);if(!dut.fade_enabled_value)$fatal(1,"IR fade");
  frame(8'h42,8'h12);frame(8'h42,8'ha1);if(!dut.wave_enabled_value)$fatal(1,"IR FFT");
  frame(8'h42,8'h12);frame(8'h42,8'ha1);if(!dut.u_player.auto_enable)$fatal(1,"IR AUTO");
  frame(8'h42,8'h33);if(dut.u_player.auto_enable)$fatal(1,"IR manual");
  frame(8'h42,8'h12);if(!dut.music_page)$fatal(1,"IR music row");
  frame(8'h42,8'h33);cycles(160);if(dut.active_music_index!=3||!dut.music_page)$fatal(1,"IR song wrap to 4");
  frame(8'h42,8'ha1);cycles(160);if(dut.active_music_index!=0||!dut.music_page)$fatal(1,"IR song wrap to 1");
  frame(8'h42,8'h12);if(!dut.rtc_page||dut.paused)$fatal(1,"IR clock entry leaked pause");
  frame(8'h42,8'ha1);if(dut.rtc_draft!=48'h010101000000)$fatal(1,"IR clock year adjustment");
  frame(8'h42,8'h12);frame(8'h42,8'h33);
  if(dut.rtc_draft!=48'h011201000000)$fatal(1,"IR clock month adjustment");
  frame(8'h42,8'hb4);if(dut.setting_active||dut.paused||dut.rtc_request)$fatal(1,"IR clock cancellation wrote RTC or leaked pause");
  if(dut.u_player.next_events!=1||dut.u_player.prev_events!=1)$fatal(1,"IR settings leaked gallery");
  learn;frame(8'h55,8'h71);pressed=16'h0010;cycles(160);pressed=0;cycles(160);
  if(dut.ir_learning||dut.setting_active||!dut.infrared.paired)$fatal(1,"KEY4 cancellation");
  frame(8'h42,8'ha1);if(dut.u_player.next_events!=2)$fatal(1,"cancel lost map");
  learn;frame(8'h55,8'h71);mode_sw7=0;cycles(500);
  if(dut.ir_learning||!dut.infrared.paired||dut.product_mode||!dut.u_player.auto_enable||dut.paused)$fatal(1,"mode cancellation");
  mode_sw7=1;cycles(500);frame(8'h42,8'h33);
  if(dut.u_player.prev_events!=2||!dut.product_mode||dut.u_player.auto_enable||dut.setting_active)$fatal(1,"map/product preserved after SW7");
  // Stop a real frame during SW7 blocking; its tail cannot form a command.
  next_before=dut.u_player.next_events;prev_before=dut.u_player.prev_events;
  level(1,600);level(0,900);level(1,450);mode_sw7=0;cycles(100);level(0,56);level(1,56);
  mode_sw7=1;cycles(500);level(1,1500);
  if(dut.u_player.next_events!=next_before||dut.u_player.prev_events!=prev_before)$fatal(1,"partial cross-mode frame");
  frame(8'h42,8'ha1);if(dut.u_player.next_events!=next_before+1)$fatal(1,"recovery");
  $display("PASS IR board: real NEC, physical KEY4 five-key learning/cancel, binary LEDs with error preserved, gallery/pause, six settings/four songs, SW7 map retention and partial-frame blocking");$finish;
 end
 initial begin #30000000;$fatal(1,"IR board timeout");end
endmodule
