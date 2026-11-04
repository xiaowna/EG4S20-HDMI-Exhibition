`timescale 1ns/1ps
module tb_av_status_fallback;
 reg sys=0,pix=0,rst_n=0,de=0,vsync=1;
 reg audio_enable=1,catalog_ready=0,wav_found=0,wav_error=0;
 reg wav_valid=0,wav_playing=1,image_valid=1;
 reg [2:0] image_count=0;
 reg [1:0] image_index=0;
 reg [47:0] wav_data=0;
 wire wav_ready;
 wire [9:0] red,green,blue;
 always #10 sys=~sys;
 always #20 pix=~pix;
 hdmi_av_output dut(.brightness(9'sd0),.gain_q8(9'd256),.loading(1'b0),.fade_enabled(1'b0),.wave_enabled(1'b0),.audio_only(1'b0),.image_valid(image_valid),.sys_clk(sys),.pix_clk(pix),.rst_n(rst_n),
  .audio_enable(audio_enable),.tone_sel(3'd2),.video_started(1'b0),
  .catalog_ready(catalog_ready),.wav_found(wav_found),.wav_error(wav_error),
  .image_count(image_count),.image_index(image_index),
  .wav_valid(wav_valid),.wav_playing(wav_playing),.wav_data(wav_data),
  .wav_ready(wav_ready),.de(de),.hsync(1'b1),.vsync(vsync),
  .rgb(24'h804020),.red(red),.green(green),.blue(blue),
  .audio_fault(),.audio_urgent());

 task wait_status(input [8:0] expected);
  integer cycles;
  begin
   cycles=0;
   while(dut.status_pix!==expected && cycles<40)begin
    @(posedge pix);#1;cycles=cycles+1;
   end
   if(dut.status_pix!==expected)
    $fatal(1,"status CDC timeout: got %h expected %h",dut.status_pix,expected);
  end
 endtask
 task frame_pulse;
  begin
   @(negedge pix);vsync=0;
   repeat(2)@(negedge pix);
   vsync=1;
   repeat(2)@(posedge pix);#1;
  end
 endtask
 task expect_glyph(input integer slot,input [4:0] expected);
  begin
   @(negedge pix);
   dut.osd.active_x=16+slot*16;
   dut.osd.active_y=440;
   de=1;
   #1;
   if(dut.osd.status_glyph!==expected)
    $fatal(1,"status glyph %0d: got %0d expected %0d",slot,dut.osd.status_glyph,expected);
  end
 endtask
 integer i,nonzero;
 initial begin
  repeat(5)@(posedge pix);
  @(negedge sys);rst_n=1;
  repeat(6)@(posedge pix);

  @(negedge sys);
  image_count=4;image_index=1;catalog_ready=1;wav_found=1;
  wait_status({1'b1,3'd4,2'd1,1'b0,1'b1,1'b1});
  if(dut.osd.status_frame!==8'd0)
   $fatal(1,"status changed before frame boundary");
  frame_pulse();
  if(dut.osd.status_frame!=={1'b1,3'd4,2'd1,1'b0,1'b1,1'b1})
   $fatal(1,"PLAY WAV frame snapshot incorrect");
  expect_glyph(4,5'd5);  // image 2
  expect_glyph(6,5'd3);  // total 4
  expect_glyph(9,5'd19); // PLAY
  expect_glyph(14,5'd23); // WAV
  expect_glyph(16,5'd24);
  @(negedge pix);
  dut.osd.active_x=20;dut.osd.active_y=440;de=1;
  #1;
  if(dut.osd_rgb!==24'hb6e7d7)
   $fatal(1,"status foreground pixel incorrect: %h",dut.osd_rgb);
  de=0;

  @(negedge sys);
  wav_data=48'h123456abcdef;wav_valid=1;
  if(wav_ready!==1'b1)$fatal(1,"WAV sample was not accepted");
  @(posedge sys);#1;
  @(negedge sys);wav_valid=0;
  if(dut.fifo_wr_level!==12'd1 || dut.fifo.mem[0]!==48'h123456abcdef)
   $fatal(1,"initial WAV sample was not queued");

  @(negedge sys);
  image_count=3;image_index=2;audio_enable=0;
  wait_status({1'b1,3'd3,2'd2,1'b1,1'b1,1'b1});
  if(dut.osd.status_frame[2]!==1'b0)
   $fatal(1,"pause appeared before VSYNC");
  frame_pulse();
  expect_glyph(4,5'd13); // image 3
  expect_glyph(9,5'd20); // PAUSE
  expect_glyph(12,5'd1);

  @(negedge sys);
  image_count=7;image_index=3;audio_enable=1;wav_error=1;
  wait_status({1'b1,3'd7,2'd3,1'b0,1'b0,1'b1});
  if(wav_ready!==1'b0 || dut.use_tone!==1'b1 || dut.use_wav!==1'b0)
   $fatal(1,"WAV error did not switch to tone");
  frame_pulse();
  expect_glyph(4,5'd3);  // image 4
  expect_glyph(6,5'd16); // total 7
  expect_glyph(9,5'd19); // PLAY
  expect_glyph(14,5'd25); // TONE
  expect_glyph(17,5'd1);
  repeat(3500)@(posedge sys);
  #1;
  if(dut.fifo_wr_level<12'd3 || dut.fifo.mem[0]!==48'h123456abcdef)
   $fatal(1,"queued WAV sample was lost or tone did not start");
  nonzero=0;
  for(i=1;i<5;i=i+1)
   if(i<dut.fifo_wr_level && (^dut.fifo.mem[i] !== 1'bx) &&
      dut.fifo.mem[i]!=48'd0)nonzero=nonzero+1;
  if(nonzero==0)$fatal(1,"fallback tone samples are all zero");

  @(negedge sys);
  catalog_ready=0;wav_found=0;wav_error=0;
  wait_status({1'b1,3'd7,2'd3,1'b0,1'b0,1'b0});
  frame_pulse();
  expect_glyph(14,5'd23); // WAIT
  expect_glyph(16,5'd10);
  expect_glyph(17,5'd25);
  @(negedge sys);image_valid=0;
  wait_status({1'b0,3'd7,2'd3,1'b0,1'b0,1'b0});
  frame_pulse();
  expect_glyph(4,5'd6); // 无已提交图像时显示 0，而不是待加载编号。
  $display("PASS AV status CDC, frame labels, and WAV-error tone fallback");
  $finish;
 end
endmodule
