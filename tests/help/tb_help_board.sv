`timescale 1ns/1ps
module tb_help_board;
 reg clk50=0,rst_n=1,sd_miso=1,mode_sw7=1,infrared_n=1;
 reg [15:0] pressed=0;
 tri [3:0] key_col_n,key_row_n;wire rtc_scl,rtc_ce;tri0 rtc_sda;
 wire [3:0] led;wire sd_sck,sd_mosi,sd_cs,hdmi_clk_p,hdmi_d0_p,hdmi_d1_p,hdmi_d2_p;
 always #10 clk50=~clk50;
 dmz_keyboard_model keyboard_model(.*,.row_n(key_row_n),.col_n(key_col_n));
 hdmi_media_board_top dut(.*);
 defparam dut.infrared.SAMPLE_CYCLES=1,dut.keyboard.SCAN_CYCLES=4,dut.keys.COUNT=8,dut.mode_control.DEBOUNCE_CYCLES=8;
 integer plays=0,checks=0;
 always @(posedge dut.sys_clk)if(dut.home_play)plays=plays+1;
 task cycles(input integer n);begin repeat(n)@(negedge dut.sys_clk);#2;end endtask
 task level(input bit v,input integer n);begin infrared_n=v;cycles(n);end endtask
 task frame(input [7:0] a,c);
  reg [31:0] data;integer i;
  begin data={~c,c,~a,a};level(1,19000);level(0,900);level(1,450);
   for(i=0;i<32;i=i+1)begin level(0,56);level(1,data[i]?169:56);end
   level(0,56);level(1,100);
  end
 endtask
 task tap(input integer n);begin pressed=16'b1<<n;cycles(160);pressed=0;cycles(160);end endtask
 task state_check(input bit visible,input [1:0] page);
  begin
   if(dut.help_visible!==visible||dut.help_page!==page)$fatal(1,"help state expected %0d/%0d got %0d/%0d",visible,page,dut.help_visible,dut.help_page);
   if(!dut.home_visible||dut.home_index!=0||dut.paused||dut.scene_mode||dut.scene_zoom!=1||plays||
      dut.u_player.next_events||dut.u_player.prev_events)$fatal(1,"help leaked a content command");
   checks=checks+1;
  end
 endtask
 initial begin
  dut.u_pll.lock_enable=1;#1;rst_n=0;dut.u_pll.lock_enable=0;
  cycles(8);rst_n=1;cycles(8);dut.u_pll.lock_enable=1;cycles(500);
  frame(1,8'h40);state_check(0,0);
  frame(0,8'h40);state_check(1,0);
  frame(0,8'h07);state_check(1,3);
  frame(0,8'h09);state_check(1,0);
  tap(1);state_check(1,1);tap(3);state_check(1,0);
  frame(0,8'h45);frame(0,8'h46);state_check(1,0);
  frame(0,8'h15);state_check(0,0);
  tap(14);state_check(1,0);tap(2);state_check(0,0);
  tap(14);tap(4);state_check(0,0);
  if(dut.setting_active)$fatal(1,"closing help opened settings");
  frame(0,8'h40);frame(0,8'h43);state_check(0,0);
  if(dut.setting_active)$fatal(1,"IR close opened settings");
  tap(14);frame(0,8'h0d);state_check(0,0);
  tap(14);frame(0,8'h16);state_check(0,0);
  tap(14);tap(0);state_check(0,0);
  tap(4);frame(0,8'h40);tap(14);
  if(dut.help_visible||!dut.setting_active)$fatal(1,"help intercepted settings");
  tap(4);state_check(0,0);
  tap(14);mode_sw7=0;cycles(200);
  if(dut.help_visible||dut.product_mode)$fatal(1,"demo switch did not close help");
  mode_sw7=1;cycles(200);state_check(0,0);
  force dut.infrared.direction_event=4'b0100;force dut.all_key_press=13'd8;
  cycles(1);force dut.infrared.direction_event=4'd0;release dut.all_key_press;
  cycles(1);release dut.infrared.direction_event;cycles(3);
  if(dut.help_visible||!dut.setting_active)$fatal(1,"coincident settings priority");
  $display("PASS help board: %0d state checks, NEC and matrix controls, no-card access, wrap, exits, settings/mode isolation",checks);$finish;
 end
 initial begin #50000000;$fatal(1,"help board timeout");end
endmodule
