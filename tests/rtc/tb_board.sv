`timescale 1ns/1ps
module tb_rtc_board;
 reg clk50=0,rst_n=0,sd_miso=1,mode_sw7=0;
 reg encoder_a=1,encoder_b=1,encoder_press_n=1,infrared_n=1;
 wire [3:0] key_col_n=4'hf;wire [3:0] key_row_n,led;
 wire sd_sck,sd_mosi,sd_cs,hdmi_clk_p,hdmi_d0_p,hdmi_d1_p,hdmi_d2_p;
 wire rtc_scl,rtc_ce;tri0 rtc_sda;
 hdmi_media_board_top #(.FINE_ADJUST(0),.HOME_UI(0)) dut(.*);
 ds1302_model #(.STRICT_TIMING(1),.DATA_DELAY(800),.RELEASE_DELAY(280)) model(.ce(rtc_ce),.sclk(rtc_scl),.dat(rtc_sda));
 defparam dut.rtc.POLL_TICKS=20;
 always #10 clk50=~clk50;
 integer i;
 initial begin
  #1;model.registers[0]=8'h58;model.registers[1]=8'h59;model.registers[2]=8'h23;
  model.registers[3]=8'h31;model.registers[4]=8'h12;model.registers[5]=7;model.registers[6]=8'h26;
  #199;rst_n=1;dut.u_pll.lock_enable=1;
  wait(dut.rtc_valid);#1;
  if(dut.av.RTC_OVERLAY!=1||dut.av.rtc_word!=={1'b1,48'h261231235958})$fatal(1,"production RTC/AV wiring or format");
  mode_sw7=1;#10000;
  if(dut.av.rtc_word!=={1'b1,48'h261231235958})$fatal(1,"mode switch changed RTC");
  model.connected=0;wait(!dut.rtc_valid);#1;
  if(dut.av.rtc_word[48]!==0||led[3]!==0)$fatal(1,"absent RTC blocks media or fails to invalidate overlay");
  model.connected=1;wait(dut.rtc_valid);
  rst_n=0;#100;
  if(dut.av.rtc_word!==0)$fatal(1,"board reset not propagated to RTC");
  $display("PASS RTC production board: real 50MHz DS1302 three-wire timing, AV49-bit word, mode independence, disconnect/reconnect and reset");$finish;
 end
 initial begin #20000000;$fatal(1,"RTC board test timeout");end
endmodule
