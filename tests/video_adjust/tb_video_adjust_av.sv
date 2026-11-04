`timescale 1ns/1ps
module tb_video_wave_av;
 reg sys=0,pix=0,rst_n=0;
 initial begin #3;forever #10 sys=!sys;end
 always #20 pix=!pix;
 reg [9:0] raster_x=0,raster_y=0;
 wire de=raster_x<640 && raster_y<480;
 wire hs=!(raster_x>=656 && raster_x<752);
 wire vs=!(raster_y>=490 && raster_y<492);
 wire [7:0] source_r=raster_x[7:0],source_g=raster_y[7:0];
 wire [7:0] source_b=raster_x[7:0]^raster_y[7:0]^8'h5a;
 wire [23:0] source_rgb={source_r,source_g,source_b};
 reg wave_enabled=0,audio_enable=1;
 wire wav_ready,ref_ready,audio_fault,ref_fault,audio_urgent,ref_urgent;
 wire [9:0] red,green,blue,ref_red,ref_green,ref_blue;
 integer source_number=0;
 function automatic [47:0] pcm_pair(input integer n);
  reg [7:0] left_high,right_high;
  reg [15:0] left_low,right_low;
  begin
   left_high=n*73+17;right_high=n*39+109;
   left_low=n*197+997;right_low=n*151+313;
   pcm_pair={left_high,left_low,right_high,right_low};
  end
 endfunction
 wire [47:0] wav_data=pcm_pair(source_number);
 hdmi_av_output dut(.sys_clk(sys),.pix_clk(pix),.rst_n(rst_n),
  .audio_enable(audio_enable),.tone_sel(3'd2),.video_started(1'b1),
  .catalog_ready(1'b1),.wav_found(1'b1),.wav_error(1'b0),.audio_only(1'b0),
  .image_valid(1'b1),.image_count(3'd4),.image_index(2'd2),
  .wav_valid(1'b1),.wav_playing(1'b1),.wav_data(wav_data),.wav_ready(wav_ready),
  .de(de),.hsync(hs),.vsync(vs),.rgb(source_rgb),.brightness(9'sd0),.gain_q8(9'd256),
  .loading(1'b0),.fade_enabled(1'b0),.wave_enabled(wave_enabled),
  .red(red),.green(green),.blue(blue),.audio_fault(audio_fault),.audio_urgent(audio_urgent));
 hdmi_av_output_reference reference(.sys_clk(sys),.pix_clk(pix),.rst_n(rst_n),
  .audio_enable(audio_enable),.tone_sel(3'd2),.video_started(1'b1),
  .catalog_ready(1'b1),.wav_found(1'b1),.wav_error(1'b0),.audio_only(1'b0),
  .image_valid(1'b1),.image_count(3'd4),.image_index(2'd2),
  .wav_valid(1'b1),.wav_playing(1'b1),.wav_data(wav_data),.wav_ready(ref_ready),
  .de(de),.hsync(hs),.vsync(vs),.rgb(source_rgb),.brightness(9'sd0),.gain_q8(9'd256),
  .loading(1'b0),.fade_enabled(1'b0),
  .red(ref_red),.green(ref_green),.blue(ref_blue),.audio_fault(ref_fault),.audio_urgent(ref_urgent));
 always @(posedge pix)
  if(!rst_n)begin raster_x<=0;raster_y<=0;end
  else if(raster_x==799)begin raster_x<=0;if(raster_y==524)raster_y<=0;else raster_y<=raster_y+1'b1;end
  else raster_x<=raster_x+1'b1;
 always @(posedge sys)
  if(!rst_n)source_number<=0;
  else if(ref_ready)source_number<=source_number+1;
 always @(posedge sys)begin
  #1;if(wav_ready!==ref_ready)$fatal(1,"F4 changed sys-domain WAV backpressure");
 end

 // Independent stream/snapshot oracle. Only the frozen reference FIFO's
 // existing read strobe and returned data are observed, never either RAM.
 // A modulo-four integer observation count replaces DUT capture counters.
 integer collecting[0:255],front[0:255],seen_columns[0:255];
 integer observations=0,ready_snapshot=0,front_valid=0,enabled=0,last_vsync=1;
 integer previous_read=0,enable_delay0=0,enable_delay1=0;
 integer active_x=0,active_y=0,previous_de=0;
 integer cycles=0,identity_cycles=0,blank_cycles=0,math_pixels=0,outside_pixels=0;
 integer reads=0,packets=0,observed_samples=0,stored_points=0,completed=0,published=0;
 integer wave_input_checks=0,trace_pixels=0,center_pixels=0,background_pixels=0;
 integer paused_cycles=0,reset_checks=0,pre_ready,amplitude,plot_y,index,j;
 reg identity_exact=1,full_math_frame=0;
 reg [23:0] expected_pixels[0:9];
 reg [9:0] math_valid=0,inside_delayed=0,eligible_delayed=0;
 reg [23:0] this_pixel;
 reg this_inside;
 always @(posedge pix)begin
  cycles=cycles+1;
  if(!rst_n)begin
   observations=0;ready_snapshot=0;front_valid=0;enabled=0;last_vsync=1;
   previous_read=0;enable_delay0=0;enable_delay1=0;
   active_x=0;active_y=0;previous_de=0;
   math_valid=0;inside_delayed=0;eligible_delayed=0;
   for(j=0;j<10;j=j+1)expected_pixels[j]=0;
  end else begin
   // Published OSD coordinates must mean the original, current input pixel.
   // These abstract input counters use no candidate coordinate as an oracle.
   if(dut.osd_x!==active_x[9:0] || dut.osd_y!==active_y[9:0])
    $fatal(1,"OSD coordinate export disagrees with input raster cycle=%0d",cycles);
   if(dut.wave_sample_valid!==previous_read[0] || dut.waveform.wave.sample_valid!==previous_read[0])
    $fatal(1,"wave valid is not exactly previous accepted FIFO read cycle=%0d",cycles);
   if(dut.wave_enable_pix[1]!==enable_delay1[0])$fatal(1,"wave enable synchronization cycle=%0d",cycles);
   if(previous_read)begin
    if(dut.waveform.wave.sample_left!==reference.fifo_data[47:24])
     $fatal(1,"wave left data misaligned/wrong channel cycle=%0d",cycles);
    wave_input_checks=wave_input_checks+1;
   end
   this_pixel=source_rgb;
   this_inside=front_valid && enabled && de && active_x>=16 && active_x<=271 && active_y>=336 && active_y<=415;
   if(this_inside)begin
    index=active_x-16;plot_y=410-front[index]/4;
    if(active_y==plot_y)begin this_pixel=24'h00ff60;if(full_math_frame)trace_pixels=trace_pixels+1;end
    else if(active_y==378)begin this_pixel=24'h214438;if(full_math_frame)center_pixels=center_pixels+1;end
    else begin this_pixel=24'h081018;if(full_math_frame)background_pixels=background_pixels+1;end
    if(full_math_frame)seen_columns[index]=1;
   end
   for(j=9;j>0;j=j-1)expected_pixels[j]=expected_pixels[j-1];
   expected_pixels[0]=this_pixel;
   math_valid={math_valid[8:0],full_math_frame && de && !(active_y>=24 && active_y<56) && !(active_y>=432 && active_y<464)};
   inside_delayed={inside_delayed[8:0],this_inside};
   eligible_delayed={eligible_delayed[8:0],de};

   pre_ready=ready_snapshot;
   if(last_vsync && !vs)begin
    enabled=enable_delay1;
    if(pre_ready)begin
     for(j=0;j<256;j=j+1)front[j]=collecting[j];
     observations=0;ready_snapshot=0;front_valid=1;published=published+1;
     $display("PROGRESS F4 reference snapshot published=%0d cycle=%0d enabled=%0d",published,cycles,enabled);
    end
   end
   if(previous_read)begin
    observed_samples=observed_samples+1;
    if(!pre_ready)begin
     observations=observations+1;
     if(observations%4==0)begin
      amplitude=$signed(reference.fifo_data[47:24]) >>> 16;
      collecting[observations/4-1]=amplitude+128;
      stored_points=stored_points+1;
     end
     if(observations==1024)begin ready_snapshot=1;completed=completed+1;end
    end
   end
   previous_read=reference.fifo_read;
   enable_delay1=enable_delay0;enable_delay0=wave_enabled;
   last_vsync=vs;
   if(!vs)active_y=0;
   else if(previous_de && !de)active_y=active_y+1;
   if(de)active_x=active_x+1;else active_x=0;
   previous_de=de;
   if(dut.fifo_read!==reference.fifo_read || dut.sample_request!==reference.sample_request)
    $fatal(1,"wave changed FIFO/audio pacing cycle=%0d",cycles);
   if(dut.fifo_read)reads=reads+1;
   if(!audio_enable)paused_cycles=paused_cycles+1;
  end
  #1;
  if({wav_ready,audio_fault,audio_urgent}!=={ref_ready,ref_fault,ref_urgent})
   $fatal(1,"public audio mismatch cycle=%0d",cycles);
  if({dut.dp,dut.hp,dut.vp,dut.x,dut.island,dut.phase,dut.video_guard,dut.video_preamble}!==
     {reference.dp,reference.hp,reference.vp,reference.x,reference.island,reference.phase,reference.video_guard,reference.video_preamble})
   $fatal(1,"wave changed ten-stage sync/blanking/island schedule cycle=%0d",cycles);
  if({dut.packet_valid,dut.ah,dut.ab,dut.bh,dut.bb}!==
     {reference.packet_valid,reference.ah,reference.ab,reference.bh,reference.bb})
   $fatal(1,"wave changed packet contents cycle=%0d",cycles);
  if(rst_n)begin
   if(audio_fault)$fatal(1,"unexpected audio fault cycle=%0d",cycles);
   if(identity_exact)begin
    if({red,green,blue,wav_ready,audio_fault,audio_urgent}!==
       {ref_red,ref_green,ref_blue,ref_ready,ref_fault,ref_urgent})
     $fatal(1,"disabled 33-bit AV mismatch cycle=%0d",cycles);
    identity_cycles=identity_cycles+1;
   end
   if(reference.special)begin
    if({red,green,blue}!=={ref_red,ref_green,ref_blue})
     $fatal(1,"blank/preamble/guard/island symbols changed cycle=%0d",cycles);
    blank_cycles=blank_cycles+1;
   end
   if(eligible_delayed[9] && !inside_delayed[9])begin
    if(dut.pixels[9]!==reference.pixels[9])$fatal(1,"outside overlay pixels differ cycle=%0d",cycles);
    outside_pixels=outside_pixels+1;
   end
   if(math_valid[9])begin
    if(dut.pixels[9]!==expected_pixels[9])
     $fatal(1,"independent ten-stage wave RGB cycle=%0d expected=%h actual=%h",cycles,expected_pixels[9],dut.pixels[9]);
    math_pixels=math_pixels+1;
   end
   if(dut.packet_valid)packets=packets+1;
  end else begin
   if(dut.wave_rgb!==0 || dut.adjusted_rgb!==0)$fatal(1,"AV reset leaked old waveform RAM");
   reset_checks=reset_checks+1;
  end
 end
 task automatic deadline_check(input integer deadline,input [255:0] reason);
  begin if(cycles>=deadline)$fatal(1,"timeout %0s",reason);end
 endtask
 integer deadline,old_observations,old_reads,old_published,old_completed;
 initial begin
  for(j=0;j<256;j=j+1)seen_columns[j]=0;
  repeat(8)@(negedge pix);rst_n=1;
  repeat(800*525)@(negedge pix);
  if(identity_cycles<420000)$fatal(1,"missing complete disabled public frame");
  $display("PASS: F4 disabled equals frozen F3 all 33 public bits for one full 800x525 frame");
  identity_exact=0;
  @(negedge sys);wave_enabled=1;
  deadline=cycles+800*525*3;
  while(published<1 || !enabled)begin @(negedge pix);deadline_check(deadline,"first complete wave snapshot");end
  while(raster_x!=0 || raster_y!=0)begin @(negedge pix);deadline_check(deadline,"full wave frame start");end
  full_math_frame=1;
  repeat(800*525)@(negedge pix);
  full_math_frame=0;
  // Flush final 10 pipeline samples so every active input pixel is checked.
  repeat(12)@(negedge pix);
  for(j=0;j<256;j=j+1)if(!seen_columns[j])$fatal(1,"wave column not visited: %0d",j);
  if(math_pixels!=640*(480-64) || trace_pixels!=256 || center_pixels<248 || background_pixels<19000)
   $fatal(1,"full-frame wave coverage math=%0d trace=%0d center=%0d background=%0d",math_pixels,trace_pixels,center_pixels,background_pixels);
  $display("PASS: F4 enabled full frame independent 10-stage RGB; all 256 columns/trace/center/background");

  // Pause prevents actual reads, preserving the sample stream. Packetizer
  // continues to emit silence and all handshake comparisons remain active.
  @(negedge sys);audio_enable=0;
  repeat(12)@(negedge pix);
  old_observations=observed_samples;old_reads=reads;
  repeat(4096)@(negedge pix);
  if(observed_samples!=old_observations || reads!=old_reads)$fatal(1,"pause consumed audio/wave samples");
  $display("PASS: F4 pause freezes consumed sample stream for 4096 pixel clocks");
  @(negedge sys);audio_enable=1;

  // Disable in the active frame, retain overlay until real VSYNC boundary.
  @(negedge sys);wave_enabled=0;
  deadline=cycles+800*525*2;
  while(enabled)begin @(negedge pix);deadline_check(deadline,"wave disable boundary");end
  // Check a real window scan after the disable boundary. Outside-overlay
  // comparison stays enabled for every DE pixel including the original OSD.
  while(raster_y!=416 || raster_x!=0)begin @(negedge pix);deadline_check(deadline,"disabled window scan");end
  repeat(12)@(negedge pix);
  $display("PASS: F4 frame-boundary disable restored F3 pixels across the full wave window");

  // Reset with a captured active waveform, then verify fresh default frames
  // immediately bypass retained RAM. No source/testbench internal RAM access.
  @(negedge pix);rst_n=0;wave_enabled=0;audio_enable=1;
  #1;if(dut.wave_rgb!==0 || dut.adjusted_rgb!==0)$fatal(1,"async AV reset bypass failed");
  repeat(4)@(negedge pix);rst_n=1;identity_exact=1;
  repeat(1600)@(negedge pix);
  if(observations>=1024 || front_valid)$fatal(1,"reset reused old wave snapshot");
  if(reads<1500 || packets<1500 || wave_input_checks<1500 || completed<1 || published<1 || reset_checks<8)
   $fatal(1,"F4 AV coverage missing reads=%0d packets=%0d samples=%0d snapshots=%0d/%0d reset=%0d",reads,packets,wave_input_checks,completed,published,reset_checks);
  $display("PASS: F4 reset masks retained RAM and defaults restore exact AV bypass");
  $display("PASS: isolated F4 HDMI waveform integration cycles=%0d disabled_33bit=%0d blank_symbols=%0d independent_pixels=%0d outside_pixels=%0d fifo_reads=%0d packets=%0d observed_samples=%0d stored_points=%0d completed=%0d published=%0d wave_input_checks=%0d trace=%0d center=%0d background=%0d paused_cycles=%0d reset_checks=%0d",
   cycles,identity_cycles,blank_cycles,math_pixels,outside_pixels,reads,packets,observed_samples,stored_points,completed,published,wave_input_checks,trace_pixels,center_pixels,background_pixels,paused_cycles,reset_checks);
  $finish;
 end
 initial begin #1000000000;$fatal(1,"F4 AV real-raster timeout");end
endmodule
