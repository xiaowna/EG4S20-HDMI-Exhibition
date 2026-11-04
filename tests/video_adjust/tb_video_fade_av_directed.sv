`timescale 1ns/1ps
// Accelerated frame edges exercise fade scheduling; the separate real-raster
// bench proves complete-frame HDMI video. Active pixels are disabled here so
// the independent source colour reaches the shared LUT without an OSD overlay.
module tb_video_fade_av_directed;
 reg sys=0,pix=0,rst_n=0;
 integer sys_half=10;
 initial begin #3;forever begin #(sys_half);sys=!sys;end end
 always #20 pix=!pix;
 reg [9:0] x=0;
 always @(posedge pix)if(!rst_n)x<=0;else if(x==799)x<=0;else x<=x+1'b1;
 wire hs=!(x>=656&&x<752);
 reg vs=1,loading=0,fade_enabled=0;
 reg signed [8:0] brightness=0;
 reg [8:0] gain_q8=256;
 wire [23:0] source_rgb={x[7:0],8'h7f,8'hc1};
 reg [47:0] wav_data=48'h010203fefdfc;
 wire wav_ready,ref_ready,audio_fault,ref_fault,audio_urgent,ref_urgent;
 wire [9:0] red,green,blue,ref_red,ref_green,ref_blue;
 hdmi_av_output dut(.sys_clk(sys),.pix_clk(pix),.rst_n(rst_n),
  .audio_enable(1'b1),.tone_sel(3'd2),.video_started(1'b1),
  .catalog_ready(1'b1),.wav_found(1'b1),.wav_error(1'b0),.audio_only(1'b0),
  .image_valid(1'b1),.image_count(3'd4),.image_index(2'd2),
  .wav_valid(1'b1),.wav_playing(1'b1),.wav_data(wav_data),.wav_ready(wav_ready),
  .de(1'b0),.hsync(hs),.vsync(vs),.rgb(source_rgb),.brightness(brightness),.gain_q8(gain_q8),
  .loading(loading),.fade_enabled(fade_enabled),
  .red(red),.green(green),.blue(blue),.audio_fault(audio_fault),.audio_urgent(audio_urgent));
 hdmi_av_output_reference reference(.sys_clk(sys),.pix_clk(pix),.rst_n(rst_n),
  .audio_enable(1'b1),.tone_sel(3'd2),.video_started(1'b1),
  .catalog_ready(1'b1),.wav_found(1'b1),.wav_error(1'b0),.audio_only(1'b0),
  .image_valid(1'b1),.image_count(3'd4),.image_index(2'd2),
  .wav_valid(1'b1),.wav_playing(1'b1),.wav_data(wav_data),.wav_ready(ref_ready),
  .de(1'b0),.hsync(hs),.vsync(vs),.rgb(source_rgb),.brightness(brightness),.gain_q8(gain_q8),
  .red(ref_red),.green(ref_green),.blue(ref_blue),.audio_fault(ref_fault),.audio_urgent(ref_urgent));
 always @(posedge sys)if(!rst_n)wav_data<=48'h010203fefdfc;
  else if(ref_ready)wav_data<={wav_data[47:24]+24'd17,wav_data[23:0]-24'd29};
 integer cycles=0,frames=0,accepts=0,applies=0,resets=0,fade_only=0,bg_priority=0,busy_cycles=0;
 integer math_pixels=0,fifo_reads=0,packets=0,disabled_cycles=0,source_changes=0,source_requests=0;
 reg [1:0] model_loading=0,model_enable=0;
 reg model_vs=1,model_busy=0;
 integer target_fade=32,sent_fade=32,active_fade=32,active_bias=0,active_gain=256;
 integer queued_fade=32,queued_bias=0,queued_gain=256,complete_cycle=0,expected_applied=0;
 reg [17:0] pixel_pair={9'd0,9'd256};
 reg [23:0] expected_lut,source_q=0;
 // F4 adds one registered waveform/bypass stage before pixel adjustment.
 // From the adjusted sample to pixels[9] there are eight retained delays;
 // the complete source-to-video path still has ten stages.
 reg [23:0] expected_pipe[0:8];
 reg [8:0] expected_valid=0;
 reg [17:0] allowed_pairs[0:63];
 integer pair_count=1,j;
 function automatic [7:0] mapped(input integer value,input integer bias,input integer gain,input integer fade_value);
  integer numerator,result;
  begin
   numerator=(value-128)*gain+(128+bias)*256;
   result=(numerator>=0)?numerator/256:-((-numerator+255)/256);
   if(result<0)result=0;else if(result>255)result=255;
   mapped=result*fade_value/32;
  end
 endfunction
 function automatic [23:0] mapped_rgb(input [23:0] value,input integer bias,input integer gain,input integer fade_value);
  begin mapped_rgb={mapped(value[23:16],bias,gain,fade_value),mapped(value[15:8],bias,gain,fade_value),mapped(value[7:0],bias,gain,fade_value)};end
 endfunction
 function automatic bit allowed(input [17:0] pair);
  integer k;
  begin allowed=0;for(k=0;k<pair_count;k=k+1)if(pair===allowed_pairs[k])allowed=1;end
 endfunction
 always @(posedge pix)begin
  cycles=cycles+1;
  if(!rst_n)begin
   model_loading=0;model_enable=0;model_vs=1;target_fade=32;sent_fade=32;active_fade=32;
   active_bias=0;active_gain=256;queued_fade=32;queued_bias=0;queued_gain=256;complete_cycle=0;
   pixel_pair={9'd0,9'd256};model_busy=0;expected_applied=0;expected_valid=0;
   source_q=0;for(j=0;j<9;j=j+1)expected_pipe[j]=0;
  end else begin
   expected_lut=mapped_rgb(source_q,active_bias,active_gain,active_fade);
   source_q=source_rgb;
   for(j=8;j>0;j=j-1)expected_pipe[j]=expected_pipe[j-1];
   expected_pipe[0]=expected_lut;expected_valid={expected_valid[7:0],1'b1};
   if(dut.table_cfg_valid!==(dut.brightness_valid||(target_fade!=sent_fade)))$fatal(1,"fade/BG arbiter lost a request");
   if(dut.table_cfg_valid&&dut.brightness_ready)begin
    if(dut.table_brightness!==(dut.brightness_valid?dut.legacy_pixel_adjust.adjust_hold[17:9]:pixel_pair[17:9]) ||
       dut.table_gain!==(dut.brightness_valid?dut.legacy_pixel_adjust.adjust_hold[8:0]:pixel_pair[8:0]))
     $fatal(1,"BG priority or stable accepted pixel pair violated");
    if(dut.brightness_valid)begin
     if(!allowed(dut.legacy_pixel_adjust.adjust_hold)||$isunknown(dut.legacy_pixel_adjust.adjust_hold))$fatal(1,"torn/unrequested BG pair");
     pixel_pair=dut.legacy_pixel_adjust.adjust_hold;bg_priority=bg_priority+1;
    end else fade_only=fade_only+1;
    queued_bias=$signed(dut.table_brightness);queued_gain=dut.table_gain;queued_fade=target_fade;
    sent_fade=target_fade;model_busy=1;complete_cycle=cycles+256;accepts=accepts+1;
   end else if(dut.table_cfg_valid)busy_cycles=busy_cycles+1;
   expected_applied=0;
   if(model_busy&&cycles>complete_cycle&&model_vs&&!vs)begin
    active_bias=queued_bias;active_gain=queued_gain;active_fade=queued_fade;
    model_busy=0;expected_applied=1;applies=applies+1;
   end
   // Independent frame-level specification: step by 2 toward 0 while loading,
   // toward 32 otherwise; disabled always targets the F2 endpoint 32.
   if(!model_enable[1])target_fade=32;
   else if(model_vs&&!vs)begin
    if(model_loading[1])target_fade=(target_fade<2)?0:target_fade-2;
    else target_fade=(target_fade>30)?32:target_fade+2;
   end
   model_loading={model_loading[0],loading};model_enable={model_enable[0],fade_enabled};model_vs=vs;
   if(dut.fifo_read!==reference.fifo_read||dut.sample_request!==reference.sample_request)$fatal(1,"fade changed audio schedule");
   if(dut.fifo_read)fifo_reads=fifo_reads+1;
  end
  #1;
  if({wav_ready,audio_fault,audio_urgent}!=={ref_ready,ref_fault,ref_urgent})$fatal(1,"fade changed public audio");
  if({dut.dp,dut.hp,dut.vp,dut.x,dut.island,dut.phase,dut.video_guard,dut.video_preamble}!==
     {reference.dp,reference.hp,reference.vp,reference.x,reference.island,reference.phase,reference.video_guard,reference.video_preamble})
   $fatal(1,"fade changed sync/island schedule");
  if({dut.packet_valid,dut.ah,dut.ab,dut.bh,dut.bb}!=={reference.packet_valid,reference.ah,reference.ab,reference.bh,reference.bb})
   $fatal(1,"fade changed audio/aux packets");
  if(rst_n)begin
   if(dut.fade_level!==target_fade||dut.brightness_applied!==expected_applied[0]||dut.brightness_ready!==!model_busy)
    $fatal(1,"fade target/publication/ready mismatch cycle=%0d target=%0d got=%0d",cycles,target_fade,dut.fade_level);
   if(dut.adjusted_rgb!==expected_lut)$fatal(1,"fade source math/publish mismatch cycle=%0d B=%0d G=%0d F=%0d expected=%h got=%h",
      cycles,active_bias,active_gain,active_fade,expected_lut,dut.adjusted_rgb);
   if(expected_valid[8])begin
    if(dut.pixels[9]!==expected_pipe[8])$fatal(1,"fade ten-stage RGB mismatch");math_pixels=math_pixels+1;
   end
   if(reference.special&&{red,green,blue}!=={ref_red,ref_green,ref_blue})$fatal(1,"fade changed blank/guard/island symbols");
   if(!fade_enabled&&brightness==0&&gain_q8==256&&active_fade==32&&active_bias==0&&active_gain==256)begin
    if({red,green,blue}!=={ref_red,ref_green,ref_blue})$fatal(1,"disabled default differs from F2");disabled_cycles=disabled_cycles+1;
   end
   if(audio_fault)$fatal(1,"fade caused audio fault");
   if(dut.packet_valid)packets=packets+1;
  end
 end
 reg previous_req=0,bridge_idle=0;
 reg [17:0] previous_hold={9'd0,9'd256},sampled_pair;
 always @(posedge sys)begin
  sampled_pair={brightness,gain_q8};bridge_idle=(dut.legacy_pixel_adjust.brightness_req==dut.legacy_pixel_adjust.brightness_ack_sync[1]);
  if(!rst_n)begin previous_req=0;previous_hold={9'd0,9'd256};end
  #1;if(rst_n)begin
   if(dut.legacy_pixel_adjust.brightness_req!=previous_req)begin
    if(!bridge_idle||dut.legacy_pixel_adjust.adjust_hold!==sampled_pair)$fatal(1,"fade CDC held pair torn or overwritten");source_requests=source_requests+1;
   end else if(dut.legacy_pixel_adjust.adjust_hold!==previous_hold)$fatal(1,"fade CDC word edited without new request");
   previous_req=dut.legacy_pixel_adjust.brightness_req;previous_hold=dut.legacy_pixel_adjust.adjust_hold;
  end
 end
 task ticks(input integer count);begin repeat(count)@(negedge pix);end endtask
 task frame_edge;
  begin vs=1;ticks(620);vs=0;ticks(8);vs=1;ticks(12);frames=frames+1;end
 endtask
 task reset_pair;
  begin
   @(negedge pix);rst_n=0;brightness=0;gain_q8=256;loading=0;fade_enabled=0;vs=1;resets=resets+1;
   ticks(8);rst_n=1;ticks(20);
  end
 endtask
 task set_pair(input integer bias,input integer gain);
  begin
   if(pair_count>=64)$fatal(1,"fade test pair list overflow");
   allowed_pairs[pair_count]={bias[8:0],gain[8:0]};pair_count=pair_count+1;
   @(negedge sys);brightness=bias;gain_q8=gain;source_changes=source_changes+1;
  end
 endtask
 task expect_active(input integer bias,input integer gain,input integer fade_value);
  begin
   if(active_bias!=bias||active_gain!=gain||active_fade!=fade_value)$fatal(1,"fade failed to converge got=%0d/%0d/%0d expected=%0d/%0d/%0d",
       active_bias,active_gain,active_fade,bias,gain,fade_value);
  end
 endtask
 integer n,g,b,prior_accepts;
 initial begin
  allowed_pairs[0]={9'd0,9'd256};reset_pair;loading=1;prior_accepts=accepts;
  repeat(3)frame_edge;
  if(accepts!=prior_accepts)$fatal(1,"disabled loading unnecessarily built a fade table");
  fade_enabled=1;ticks(8);repeat(17)frame_edge;expect_active(0,256,0);
  // A load failure/end restores brightness even if loading ended before black.
  loading=0;ticks(8);repeat(17)frame_edge;expect_active(0,256,32);
  loading=1;ticks(8);repeat(4)frame_edge;loading=0;ticks(8);repeat(5)frame_edge;expect_active(0,256,32);
  loading=1;ticks(8);repeat(17)frame_edge;expect_active(0,256,0);
  fade_enabled=0;ticks(8);repeat(3)frame_edge;expect_active(0,256,32);

  // Rapid whole BG words compete with fade-only updates. Eventually the latest
  // request must publish; a pending old table is allowed to publish first.
  fade_enabled=1;loading=1;ticks(8);frame_edge;sys_half=9;
  for(n=0;n<30;n=n+1)begin
   b=((n*73+29)%511)-255;
   case(n%5)0:g=128;1:g=192;2:g=256;3:g=320;4:g=384;endcase
   set_pair(b,g);
  end
  set_pair(-32,384);repeat(18)frame_edge;expect_active(-32,384,0);sys_half=10;
  fade_enabled=0;ticks(8);repeat(3)frame_edge;expect_active(-32,384,32);

  // Reset while a fade-only table is building, pending, then active.
  loading=1;fade_enabled=1;ticks(8);frame_edge;ticks(30);reset_pair;
  loading=1;fade_enabled=1;ticks(8);frame_edge;ticks(300);reset_pair;
  loading=1;fade_enabled=1;ticks(8);repeat(2)frame_edge;reset_pair;
  repeat(2)frame_edge;expect_active(0,256,32);
  if(fade_only<30||bg_priority<2||busy_cycles<100||math_pixels<50000||source_changes<=source_requests||resets!=4)
   $fatal(1,"fade scheduler coverage fade=%0d bg=%0d busy=%0d math=%0d changes=%0d requests=%0d resets=%0d",
      fade_only,bg_priority,busy_cycles,math_pixels,source_changes,source_requests,resets);
  $display("PASS: F3 directed fade schedule cycles=%0d frames=%0d resets=%0d cfg_accepts=%0d cfg_applies=%0d fade_only=%0d BG_priority=%0d busy_cycles=%0d independent_pixels=%0d FIFO_reads=%0d packets=%0d disabled_33bit=%0d source_changes=%0d source_requests=%0d",
      cycles,frames,resets,accepts,applies,fade_only,bg_priority,busy_cycles,math_pixels,fifo_reads,packets,disabled_cycles,source_changes,source_requests);
  $finish;
 end
 initial begin #40000000;$fatal(1,"fade schedule deadline");end
endmodule
