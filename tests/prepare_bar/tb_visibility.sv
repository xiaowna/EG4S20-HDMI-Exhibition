`timescale 1ns/1ps
module tb_prepare_visibility;
 parameter CUBE_FIRST=0;
 reg clk50=0,rst_n=0,sd_miso=1,mode_sw7=1;
 reg encoder_a=1,encoder_b=1,encoder_press_n=1,infrared_n=1;always #10 clk50=~clk50;
 wire rtc_scl,rtc_ce;tri0 rtc_sda;tri1 [3:0] key_col_n;wire [3:0] key_row_n,led;
 wire sd_sck,sd_mosi,sd_cs,hdmi_clk_p,hdmi_d0_p,hdmi_d1_p,hdmi_d2_p;
 hdmi_media_board_top dut(.*);
 integer checks=0;
 task stage(input integer expected);begin #2;
  if(dut.prepare_stage!==expected[2:0])$fatal(1,"healthy page unexpected indicator: got=%0d expected=%0d",dut.prepare_stage,expected);
  checks=checks+1;
 end endtask
 initial begin
  force dut.rtc_busy=0;force dut.rtc_page=0;force dut.rtc_error=0;force dut.view_active=0;force dut.wait_home=0;
  force dut.card_error=0;force dut.mem_error=0;force dut.prefetch_error=0;
  force dut.card_ready=1;force dut.mem_ready=1;force dut.catalog_ready=1;force dut.display_valid=1;
  force dut.mode_switching=0;force dut.preparing=0;force dut.prepare_pixels=37;
  force dut.image_error=0;force dut.home_visible=0;force dut.paused=0;
  force dut.product_mode=1;force dut.wav_enable=1;force dut.wav_found=1;force dut.wav_playing=1;force dut.wav_error=0;
  if(CUBE_FIRST)begin
   force dut.view_active=1;force dut.wav_error=1;stage(0);
   force dut.view_active=0;force dut.wav_error=0;
  end
  stage(0);
  // A looping/restarting WAV must not create a new foreground loading task.
  repeat(4)begin force dut.wav_playing=0;stage(0);force dut.wav_playing=1;stage(0);end
  // Healthy 3D is independent of background card/image/audio jobs.
  force dut.view_active=1;force dut.wav_error=1;force dut.card_error=1;force dut.image_error=1;
  force dut.mode_switching=1;force dut.preparing=1;stage(0);
  if(dut.prepare_word!==10'd0)$fatal(1,"3D must release stale completion/error panel");
  force dut.mode_switching=0;force dut.wait_home=1;force dut.view_ready=0;stage(5);
  force dut.view_ready=1;stage(4);force dut.wait_home=0;stage(0);
  force dut.rtc_page=1;force dut.rtc_busy=1;stage(5);
  force dut.rtc_busy=0;force dut.rtc_error=1;stage(6);
  force dut.rtc_page=0;force dut.view_active=0;force dut.card_error=0;
  force dut.wav_error=0;force dut.mode_switching=0;force dut.preparing=0;force dut.image_error=0;stage(0);
  force dut.display_valid=0;force dut.image_error=1;stage(6);
  $display("PASS prepare visibility: %0d page/loop/error checks",checks);$finish;
 end
endmodule
