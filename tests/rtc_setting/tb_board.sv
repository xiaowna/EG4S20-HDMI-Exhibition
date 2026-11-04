`timescale 1ns/1ps
module tb_rtc_setting_board;
 reg clk50=0,rst_n=0,sd_miso=1,mode_sw7=0;
 reg encoder_a=1,encoder_b=1,encoder_press_n=1,infrared_n=1;
 wire [3:0] key_col_n=4'hf;wire [3:0] key_row_n,led;
 wire sd_sck,sd_mosi,sd_cs,hdmi_clk_p,hdmi_d0_p,hdmi_d1_p,hdmi_d2_p;
 wire rtc_scl,rtc_ce;tri0 rtc_sda;
 reg [3:0] event_bus=0;
 hdmi_media_board_top #(.FINE_ADJUST(0),.HOME_UI(0)) dut(.*);
 ds1302_model model(.ce(rtc_ce),.sclk(rtc_scl),.dat(rtc_sda));
 defparam dut.rtc.QUARTER_CYCLES=5;
 defparam dut.rtc.POLL_TICKS=40;
 defparam dut.mode_control.DEBOUNCE_CYCLES=100;
 always #10 clk50=~clk50;
 task tick;begin @(posedge dut.sys_clk);#1;@(negedge dut.sys_clk);end endtask
 task press(input [3:0] value);begin event_bus=value;tick;event_bus=0;tick;end endtask
 task enter;
  integer n;
  begin press(8);for(n=0;n<4;n=n+1)press(2);tick;
   if(dut.rtc_page!==1||dut.av.RTC_SETTING!=1||dut.av.rtc_edit_word[53]!==1)$fatal(1,"clock page not connected to board/AV state=%d mode=%b change=%b controls=%b setting=%d page=%b avflag=%d word=%h",dut.adjust_controls.state,dut.product_mode,dut.mode_change,dut.control_event,dut.setting_active,dut.rtc_page,dut.av.RTC_SETTING,dut.av.rtc_edit_word);
  end
 endtask
 integer n,before_writes;reg [47:0] saved;
 initial begin
  force dut.normal_control_event=event_bus;
  #1;model.registers[0]=8'h80;model.registers[1]=0;model.registers[2]=0;
  model.registers[3]=1;model.registers[4]=1;model.registers[5]=1;model.registers[6]=0;
  model.registers[7]=8'h80;
  #199;rst_n=1;dut.u_pll.lock_enable=1;
  wait(dut.keys_rst_n&&!dut.mode_switching);wait(model.clock_reads>0);wait(dut.rtc.state==0);repeat(3)tick;
  before_writes=model.writes;enter;press(1);saved=dut.rtc_draft;
  for(n=0;n<6;n=n+1)press(2);
  press(2);wait(dut.rtc_busy);press(1);press(8);
  if(dut.rtc_draft!==saved||dut.rtc_page!==1||dut.next_press||dut.pause_press)$fatal(1,"busy controls escaped clock page");
  wait(dut.rtc_done);tick;
  if(dut.rtc_time!==saved||!dut.rtc_valid||model.writes-before_writes!=11||model.charger!=0||model.registers[7]!=128)$fatal(1,"board save/readback/protection failed");
  press(2);if(dut.setting_active)$fatal(1,"success did not return to playback");
  before_writes=model.writes;enter;press(1);press(8);
  if(dut.setting_active||model.writes!=before_writes)$fatal(1,"cancel modified RTC");
  // Learning closes UI; an already-confirmed save completes in the background.
  enter;press(1);saved=dut.rtc_draft;
  for(n=0;n<6;n=n+1)press(2);press(2);wait(dut.rtc_busy);
  force dut.ir_learning_enter=1;tick;release dut.ir_learning_enter;tick;
  if(dut.setting_active)$fatal(1,"learning did not close clock UI");
  wait(dut.rtc_done);tick;
  if(dut.rtc_time!==saved||dut.rtc_busy)$fatal(1,"learning interrupted confirmed save");
  $display("PASS RTC setting production board: menu entry, command/AV wiring, save/readback, cancel, no media events, busy freeze, IR learning close with background completion");$finish;
 end
 initial begin #30000000;$fatal(1,"clock setting board timeout");end
endmodule
