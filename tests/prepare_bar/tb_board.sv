`timescale 1ns/1ps
module tb_prepare_board;
 reg clk50=0,rst_n=0,sd_miso=1,mode_sw7=1;
 reg encoder_a=1,encoder_b=1,encoder_press_n=1,infrared_n=1;always #10 clk50=~clk50;
 wire rtc_scl,rtc_ce;tri0 rtc_sda;tri1 [3:0] key_col_n;wire [3:0] key_row_n,led;
 wire sd_sck,sd_mosi,sd_cs,hdmi_clk_p,hdmi_d0_p,hdmi_d1_p,hdmi_d2_p;
 hdmi_media_board_top dut(.*);
 integer checks=0;
 task expect_stage(input integer stage,units);begin #2;
  if(dut.av.prepare_word!=={stage[2:0],units[6:0]})$fatal(1,"board stage got=%h want=%0d,%0d",dut.av.prepare_word,stage,units);
  checks=checks+1;
 end endtask
 initial begin
  force dut.rtc_busy=0;force dut.rtc_page=0;force dut.rtc_error=0;force dut.view_active=0;force dut.wait_home=0;
  force dut.card_error=0;force dut.mem_error=0;force dut.prefetch_error=0;
  force dut.card_ready=0;force dut.mem_ready=0;force dut.catalog_ready=0;
  force dut.mode_switching=0;force dut.preparing=0;force dut.prepare_pixels=37;
  force dut.image_error=0;force dut.home_visible=0;force dut.paused=0;
  force dut.display_valid=0;
  force dut.product_mode=1;force dut.wav_enable=1;force dut.wav_found=0;force dut.wav_playing=0;force dut.wav_error=0;
  expect_stage(1,0);force dut.card_ready=1;force dut.mem_ready=1;expect_stage(2,0);
  force dut.catalog_ready=1;expect_stage(0,0);
  force dut.preparing=1;expect_stage(3,37);force dut.prepare_pixels=75;expect_stage(3,75);
  force dut.preparing=0;expect_stage(0,0);
  force dut.mode_switching=1;expect_stage(4,0);force dut.mode_switching=0;
  force dut.wav_found=1;expect_stage(0,0);force dut.wav_playing=1;expect_stage(0,0);
  force dut.wav_playing=0;force dut.paused=1;expect_stage(0,0);
  force dut.paused=0;force dut.wav_error=1;expect_stage(6,0);
  force dut.wav_found=0;force dut.wav_error=0;
  force dut.card_error=1;expect_stage(6,0);
  force dut.view_active=1;expect_stage(0,0);
  force dut.wait_home=1;force dut.view_ready=0;expect_stage(5,0);
  force dut.view_ready=1;expect_stage(4,0);force dut.wait_home=0;expect_stage(0,0);
  force dut.rtc_page=1;force dut.rtc_busy=1;expect_stage(5,0);force dut.rtc_busy=0;
  force dut.rtc_page=1;force dut.rtc_error=1;expect_stage(6,0);force dut.rtc_page=0;force dut.rtc_error=0;
  force dut.view_active=0;force dut.card_error=0;force dut.image_error=1;expect_stage(6,0);
  $display("PASS prepare board: %0d stages; foreground, music, pause, absent card/cube, RTC and errors",checks);$finish;
 end
endmodule
