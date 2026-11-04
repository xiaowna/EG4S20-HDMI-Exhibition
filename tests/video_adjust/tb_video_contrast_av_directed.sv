`timescale 1ns/1ps
// Short protocol/reset companion to the three complete real-raster frames.
// VSYNC is driven explicitly to reach build/pending/active reset corners;
// the long bench, rather than this accelerated fixture, proves real framing.
module tb_video_contrast_av_directed;
 reg sys=0,pix=0,rst_n=0;
 always #10 sys=!sys;
 always #20 pix=!pix;
 reg [9:0] x=0;
 always @(posedge pix)if(!rst_n)x<=0;else if(x==799)x<=0;else x<=x+1'b1;
 wire de=x<640,hs=!(x>=656&&x<752);
 reg vs=1,audio_enable=1;
 reg signed [8:0] brightness=0;
 reg [8:0] gain_q8=256;
 wire [23:0] source_rgb={x[7:0],8'h7f,8'hc1};
 reg [47:0] wav_data=48'h010203fefdfc;
 wire wav_ready,ref_ready,audio_fault,ref_fault,audio_urgent,ref_urgent;
 wire [9:0] red,green,blue,ref_red,ref_green,ref_blue;
 hdmi_av_output dut(.sys_clk(sys),.pix_clk(pix),.rst_n(rst_n),
  .audio_enable(audio_enable),.tone_sel(3'd2),.video_started(1'b1),
  .catalog_ready(1'b1),.wav_found(1'b1),.wav_error(1'b0),.audio_only(1'b0),
  .image_valid(1'b1),.image_count(3'd4),.image_index(2'd2),
  .wav_valid(1'b1),.wav_playing(1'b1),.wav_data(wav_data),.wav_ready(wav_ready),
  .de(de),.hsync(hs),.vsync(vs),.rgb(source_rgb),.brightness(brightness),.gain_q8(gain_q8),
  .red(red),.green(green),.blue(blue),.audio_fault(audio_fault),.audio_urgent(audio_urgent));
 hdmi_av_output_reference reference(.sys_clk(sys),.pix_clk(pix),.rst_n(rst_n),
  .audio_enable(audio_enable),.tone_sel(3'd2),.video_started(1'b1),
  .catalog_ready(1'b1),.wav_found(1'b1),.wav_error(1'b0),.audio_only(1'b0),
  .image_valid(1'b1),.image_count(3'd4),.image_index(2'd2),
  .wav_valid(1'b1),.wav_playing(1'b1),.wav_data(wav_data),.wav_ready(ref_ready),
  .de(de),.hsync(hs),.vsync(vs),.rgb(source_rgb),.brightness(9'sd0),
  .red(ref_red),.green(ref_green),.blue(ref_blue),.audio_fault(ref_fault),.audio_urgent(ref_urgent));
 always @(posedge sys)
  if(!rst_n)wav_data<=48'h010203fefdfc;
  else if(ref_ready)wav_data<={wav_data[47:24]+24'd17,wav_data[23:0]-24'd29};
 reg identity_exact=1,paused=0;
 integer cycles=0,identity_cycles=0,blank_cycles=0,resets=0,accepts=0,applies=0;
 integer fifo_reads=0,paused_cycles=0,packets=0;
 reg [11:0] paused_fifo_level=0;
 always @(posedge pix)begin
  cycles=cycles+1;
  if(rst_n)begin
   if(dut.brightness_valid&&dut.brightness_ready)accepts=accepts+1;
   if(dut.fifo_read!==reference.fifo_read||dut.sample_request!==reference.sample_request)
    $fatal(1,"directed FIFO/sample schedule mismatch");
   if(dut.fifo_read)fifo_reads=fifo_reads+1;
   if(paused)begin
    if(dut.fifo_read)$fatal(1,"pause consumed a queued WAV sample");
    paused_cycles=paused_cycles+1;
   end
  end
  #1;
  if({wav_ready,audio_fault,audio_urgent}!=={ref_ready,ref_fault,ref_urgent})$fatal(1,"directed public audio mismatch");
  if({dut.dp,dut.hp,dut.vp,dut.x,dut.island,dut.phase,dut.video_guard,dut.video_preamble}!==
     {reference.dp,reference.hp,reference.vp,reference.x,reference.island,reference.phase,reference.video_guard,reference.video_preamble})
   $fatal(1,"directed sync/island scheduler mismatch");
  if({dut.packet_valid,dut.ah,dut.ab,dut.bh,dut.bb}!==
     {reference.packet_valid,reference.ah,reference.ab,reference.bh,reference.bb})$fatal(1,"directed audio/aux packet mismatch");
  if(rst_n)begin
   if(audio_fault)$fatal(1,"directed audio fault");
   if(identity_exact)begin
    if({red,green,blue,wav_ready,audio_fault,audio_urgent}!=={ref_red,ref_green,ref_blue,ref_ready,ref_fault,ref_urgent})
     $fatal(1,"reset default leaked stale/unknown table");
    identity_cycles=identity_cycles+1;
   end
   if(reference.special)begin
    if({red,green,blue}!=={ref_red,ref_green,ref_blue})$fatal(1,"directed blank/packet symbols mismatch");
    blank_cycles=blank_cycles+1;
   end
   if(dut.brightness_applied)applies=applies+1;
   if(dut.packet_valid)packets=packets+1;
  end
 end
 task ticks(input integer count);
  begin repeat(count)@(negedge pix);end
 endtask
 task reset_pair;
  begin
   @(negedge pix);rst_n=0;brightness=0;gain_q8=256;vs=1;audio_enable=1;paused=0;identity_exact=1;resets=resets+1;
   ticks(8);rst_n=1;ticks(5);
   if(dut.brightness_lut.active_bias!==0||dut.brightness_lut.active_gain!==256||dut.brightness_lut.active_fade!==32||dut.brightness_lut.building||dut.brightness_lut.pending)
    $fatal(1,"reset retained a partial/complete/active table");
   // Fall once after reset; no pre-reset request may later become active.
   vs=0;ticks(3);vs=1;ticks(800);
   if(dut.brightness_lut.active_bias!==0||dut.brightness_lut.active_gain!==256||dut.legacy_pixel_adjust.adjust_hold!=={9'd0,9'd256})$fatal(1,"stale pair survived reset");
  end
 endtask
 task request_pair(input integer bias,input integer gain);
  begin @(negedge sys);identity_exact=0;brightness=bias;gain_q8=gain;end
 endtask
 task wait_build;
  integer deadline;
  begin deadline=cycles+1000;while(!dut.brightness_lut.building)begin ticks(1);if(cycles>deadline)$fatal(1,"directed request never built");end end
 endtask
 task wait_pending;
  integer deadline;
  begin deadline=cycles+1000;while(!dut.brightness_lut.pending)begin ticks(1);if(cycles>deadline)$fatal(1,"directed request never pending");end end
 endtask
 integer old_reads,old_applies;
 initial begin
  reset_pair;
  request_pair(64,384);wait_build;ticks(91);reset_pair;
  request_pair(-64,128);wait_pending;ticks(37);reset_pair;
  request_pair(32,320);wait_pending;old_applies=applies;
  vs=0;ticks(3);vs=1;ticks(20);
  if(applies!=old_applies+1||dut.brightness_lut.active_bias!==32||dut.brightness_lut.active_gain!==320)$fatal(1,"directed table failed to activate");
  // Queue a second table while the first active table remains in use.
  request_pair(-32,192);wait_build;ticks(1);reset_pair;

  // A fully active nonidentity mapping also resets to exact F1 identity.
  request_pair(0,384);wait_pending;vs=0;ticks(3);vs=1;ticks(20);
  if(dut.brightness_lut.active_bias!==0||dut.brightness_lut.active_gain!==384)$fatal(1,"active reset setup failed");
  reset_pair;
  // Fill and exercise normal WAV scheduling before pause. The FIFO content
  // must freeze after the synchronizer settles and resume at the same samples.
  ticks(2400);
  old_reads=fifo_reads;
  @(negedge sys);audio_enable=0;ticks(12);paused=1;
  paused_fifo_level=dut.fifo_level;ticks(1600);
  if(dut.fifo_level!==paused_fifo_level||wav_ready!==0||audio_urgent!==0)$fatal(1,"paused FIFO was not retained");
  paused=0;@(negedge sys);audio_enable=1;ticks(2400);
  if(fifo_reads<=old_reads)$fatal(1,"WAV playback did not resume");
  if(resets!=5||accepts<5||applies<2||identity_cycles<5000||paused_cycles<1600||packets==0)
   $fatal(1,"directed coverage resets=%0d accepts=%0d applies=%0d identity=%0d paused=%0d packets=%0d",resets,accepts,applies,identity_cycles,paused_cycles,packets);
  $display("PASS: F2 directed AV reset/pause cycles=%0d resets=%0d cfg_accepts=%0d cfg_applies=%0d identity_33bit=%0d blank_symbols=%0d fifo_reads=%0d paused_cycles=%0d packets=%0d",
           cycles,resets,accepts,applies,identity_cycles,blank_cycles,fifo_reads,paused_cycles,packets);
  $finish;
 end
 initial begin #20000000;$fatal(1,"directed AV deadline");end
endmodule
