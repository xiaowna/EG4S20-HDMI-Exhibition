// 固定 640x480 / 总计 800x525 / 25 MHz。输出完整视频与双声道测试音数据岛。
// 当前固定格式调试模式；未实现 EDID/HPD 协商。
module hdmi_av_output #(parameter SETTINGS_UI=0,parameter MODE_CONTROL=0,parameter CHINESE_SUBTITLE=0)(
 input wire sys_clk,pix_clk,rst_n,audio_enable,input wire [2:0] tone_sel,
 input wire video_started,catalog_ready,wav_found,wav_error,audio_only,image_valid,
 input wire [2:0] image_count,input wire [1:0] image_index,
 input wire wav_valid,wav_playing,input wire [47:0] wav_data,output wire wav_ready,
 input wire de,hsync,vsync,input wire [23:0] rgb,
 input wire signed [8:0] brightness,input wire [8:0] gain_q8,
 input wire loading,fade_enabled,wave_enabled,
 output wire [9:0] red,green,blue,output wire audio_fault,audio_urgent,
 input wire [10:0] settings_word,output wire transition_ready,
 input wire force_tone,audio_flush_request,input wire [3:0] mode_status,
 output wire audio_flush_done);
 wire sample_valid,sample_ready,overflow,fifo_full,fifo_empty,fifo_read;
 localparam AUDIO_FIFO_BITS=11;
 wire [AUDIO_FIFO_BITS:0] fifo_level,fifo_wr_level;
 reg audio_primed;
 wire [23:0] sample_left,sample_right;wire [47:0] fifo_data;
 wire forced_tone=MODE_CONTROL&&force_tone;
 wire fifo_rst_n,flush_block_pix,flush_hold_pix;
 wire flush_safe;
 generate if(MODE_CONTROL)begin:source_switch
  audio_source_flush flush(.sys_clk(sys_clk),.pix_clk(pix_clk),.rst_n(rst_n),
   .request(audio_flush_request),.safe_to_flush(flush_safe),.flush_done(audio_flush_done),
   .fifo_rst_n(fifo_rst_n),.block_reads(flush_block_pix),.flush_hold_pix(flush_hold_pix));
 end else begin:legacy_source
  assign fifo_rst_n=rst_n;
  assign flush_block_pix=1'b0;
  assign flush_hold_pix=1'b0;
  assign audio_flush_done=1'b0;
 end endgenerate
 wire use_tone=audio_enable&&(forced_tone||(catalog_ready&&!wav_found)||wav_error);
 audio_tone_bank #(.HOLD_ON_BACKPRESSURE(1)) tone(.clk(sys_clk),.rst_n(rst_n),.enable(use_tone),.tone_sel(tone_sel),
  .sample_ready(sample_ready),.sample_valid(sample_valid),.sample_left(sample_left),
  .sample_right(sample_right),.sample_tick(),.overflow(overflow));
 // Keep the file sample pending while paused; the packetizer inserts silence.
 wire use_wav=wav_playing&&audio_enable&&!wav_error&&!forced_tone;
 assign audio_urgent=use_wav && fifo_wr_level<12'd1536;
 assign sample_ready=!use_tone || !fifo_full;
 assign wav_ready=use_wav && !fifo_full;
 // 暂停时冻结已排队的样本，音频包仍按时发送静音；恢复后从原位置继续。
 wire selected_valid=use_wav?wav_valid:(use_tone&&sample_valid);
 wire [47:0] selected_data=use_wav?wav_data:
  (audio_enable?{sample_left,sample_right}:48'd0);
 audio_async_fifo #(.ADDR_BITS(AUDIO_FIFO_BITS)) fifo(
  .wr_clk(sys_clk),.wr_rst_n(fifo_rst_n),.wr_en(selected_valid&&!fifo_full),
  .wr_data(selected_data),.wr_full(fifo_full),.rd_clk(pix_clk),.rd_rst_n(fifo_rst_n),
  .rd_en(fifo_read),.rd_data(fifo_data),.rd_empty(fifo_empty),
  .rd_level(fifo_level),.wr_level(fifo_wr_level));
 // 起播及真正欠载后先存 1024 个样本，再按 HDMI 固定节拍读取。
 // 实际为空时仍立即阻止读取并发送静音。
 always @(posedge pix_clk or negedge rst_n)
  if(!rst_n)audio_primed<=0;
  else if(flush_hold_pix||fifo_empty)audio_primed<=0;
  else if(fifo_level>=12'd1024)audio_primed<=1;
 (* async_reg="true" *) reg [1:0] audio_enable_pix;
 always @(posedge pix_clk or negedge rst_n)
  if(!rst_n)audio_enable_pix<=0;
  else audio_enable_pix<={audio_enable_pix[0],audio_enable};
 (* async_reg="true" *) reg [1:0] audio_only_pix;
 always @(posedge pix_clk or negedge rst_n)
  if(!rst_n)audio_only_pix<=0;
  else audio_only_pix<={audio_only_pix[0],audio_only||forced_tone};
 wire playback_allowed=video_started||audio_only_pix[1];
 wire packet_fifo_empty=fifo_empty||!audio_primed||!audio_enable_pix[1]||!playback_allowed||flush_block_pix;
 wire sample_request;
 reg audio_started,audio_underflow;
 // 只记录正常起播后的真实缺样；初次预充、暂停和等待首帧不算欠载。
 always @(posedge pix_clk or negedge rst_n)
  if(!rst_n)begin audio_started<=0;audio_underflow<=0;end
  else begin
   if(flush_hold_pix)audio_started<=0;
   else if(fifo_read)audio_started<=1;
   if(sample_request && fifo_empty && audio_started && audio_enable_pix[1] && playback_allowed&&!flush_block_pix)
    audio_underflow<=1;
  end
 // Transfer the complete status as one stable word. A request is acknowledged
 // only after the pixel clock has captured it, so count/index cannot tear.
 localparam STATUS_BITS=MODE_CONTROL?24:(SETTINGS_UI?20:9);
 wire [STATUS_BITS-1:0] status_sys={MODE_CONTROL?mode_status:4'd0,
  SETTINGS_UI?settings_word:11'd0,image_valid,image_count,image_index,!audio_enable,
  wav_found&&!wav_error&&!forced_tone,catalog_ready||wav_error||forced_tone};
 reg [STATUS_BITS-1:0] status_hold,status_pix;
 wire [23:0] status_full=status_pix;
 reg status_req,status_ack;
 (* async_reg="true" *) reg [1:0] status_ack_sync,status_req_sync;
 always @(posedge sys_clk or negedge rst_n)
  if(!rst_n)begin
   status_hold<=0;status_req<=0;status_ack_sync<=0;
  end else begin
   status_ack_sync<={status_ack_sync[0],status_ack};
   if(status_req==status_ack_sync[1] && status_hold!=status_sys)begin
    status_hold<=status_sys;
    status_req<=!status_req;
   end
  end
 always @(posedge pix_clk or negedge rst_n)
  if(!rst_n)begin
   status_req_sync<=0;status_ack<=0;status_pix<=0;
  end else begin
   status_req_sync<={status_req_sync[0],status_req};
   if(status_req_sync[1]!=status_ack)begin
    status_pix<=status_hold;
    status_ack<=status_req_sync[1];
   end
  end
 wire [23:0] osd_rgb;
 wire [9:0] osd_x,osd_y;
 video_scroll_osd #(.SETTINGS_UI(SETTINGS_UI),.MODE_CONTROL(MODE_CONTROL),.SCROLL_TEXT(!CHINESE_SUBTITLE)) osd(.clk(pix_clk),.rst_n(rst_n),.de(de),.vsync(vsync),
  .mode_status(status_full[23:20]),
  .settings_word(status_full[19:9]),
  .image_valid(status_pix[8]),.image_count(status_pix[7:5]),.image_index(status_pix[4:3]),
  .paused(status_pix[2]),.wav_found(status_pix[1]),.catalog_ready(status_pix[0]),
  .rgb(rgb),.rgb_out(osd_rgb),.pixel_x(osd_x),.pixel_y(osd_y));
 // Observe exactly the FIFO reads already requested by the packetizer.
 // rd_data becomes available after that read edge; the next edge consumes it.
 reg wave_sample_valid;
 (* async_reg="true" *) reg [1:0] wave_enable_pix;
 always @(posedge pix_clk or negedge rst_n)
  if(!rst_n)begin wave_sample_valid<=0;wave_enable_pix<=0;end
  else begin
   wave_sample_valid<=fifo_read;
   wave_enable_pix<={wave_enable_pix[0],wave_enabled};
  end
 wire [23:0] wave_rgb;
 video_audio_waveform wave(.pix_clk(pix_clk),.rst_n(rst_n),.rgb_in(osd_rgb),
  .de(de),.vsync(vsync),.x(osd_x),.y(osd_y[8:0]),.wave_enable(wave_enable_pix[1]),
  .sample_valid(wave_sample_valid),.sample_left(fifo_data[47:24]),.rgb_out(wave_rgb));
 // The board drives loading only for a prepared, requested transition.
 // Background SD reads leave the current picture fully visible. Acknowledge
 // black only after the corresponding complete LUT has actually published.
 (* async_reg="true" *) reg [1:0] loading_pix,fade_enable_pix;
 reg fade_vsync_prev;
 reg [5:0] fade_level;
 always @(posedge pix_clk or negedge rst_n)
  if(!rst_n)begin
   loading_pix<=0;fade_enable_pix<=0;fade_vsync_prev<=1;fade_level<=6'd32;
  end else begin
   loading_pix<={loading_pix[0],loading};
   fade_enable_pix<={fade_enable_pix[0],fade_enabled};
   fade_vsync_prev<=vsync;
   // Keep the settings panel readable while a cold image load is in progress.
   if(!fade_enable_pix[1] || (SETTINGS_UI && status_full[19]))fade_level<=6'd32;
   else if(fade_vsync_prev && !vsync)begin
    if(loading_pix[1])fade_level<=(fade_level<=6'd2)?6'd0:fade_level-6'd2;
    else fade_level<=(fade_level>=6'd30)?6'd32:fade_level+6'd2;
   end
  end
 // Brightness and gain cross together as one 18-bit stable request word.
 // A stable-word request/acknowledge bridge retains an outstanding setting.
 // Later source changes coalesce when that request has been acknowledged.
 wire [17:0] adjust_sys={brightness,gain_q8};
 reg [17:0] adjust_hold;
 wire signed [8:0] brightness_hold=adjust_hold[17:9];
 wire [8:0] gain_hold=adjust_hold[8:0];
 reg brightness_req,brightness_ack;
 (* async_reg="true" *) reg [1:0] brightness_ack_sync,brightness_req_sync;
 wire brightness_valid=brightness_req_sync[1]!=brightness_ack;
 wire brightness_ready,brightness_applied;
 // A fade-only request must use the last accepted pixel-domain pair: the
 // source hold word may already be changing before its request synchronizes.
 reg [17:0] adjust_pix;
 reg [5:0] fade_sent;
 reg [5:0] fade_applied;
 assign transition_ready=loading_pix[1] &&
  (!fade_enable_pix[1] || (SETTINGS_UI && status_full[19]) || fade_applied==0);
 wire table_cfg_valid=brightness_valid || fade_level!=fade_sent;
 wire signed [8:0] table_brightness=brightness_valid?brightness_hold:adjust_pix[17:9];
 wire [8:0] table_gain=brightness_valid?gain_hold:adjust_pix[8:0];
 always @(posedge sys_clk or negedge rst_n)
  if(!rst_n)begin
   adjust_hold<={9'sd0,9'd256};brightness_req<=0;brightness_ack_sync<=0;
  end else begin
   brightness_ack_sync<={brightness_ack_sync[0],brightness_ack};
   if(brightness_req==brightness_ack_sync[1] && adjust_sys!=adjust_hold)begin
    adjust_hold<=adjust_sys;
    brightness_req<=!brightness_req;
   end
  end
 always @(posedge pix_clk or negedge rst_n)
  if(!rst_n)begin
   brightness_req_sync<=0;brightness_ack<=0;adjust_pix<={9'sd0,9'd256};fade_sent<=6'd32;fade_applied<=6'd32;
  end
  else begin
   brightness_req_sync<={brightness_req_sync[0],brightness_req};
   if(brightness_applied)fade_applied<=fade_sent;
   if(table_cfg_valid && brightness_ready)begin
    fade_sent<=fade_level;
    if(brightness_valid)begin
     adjust_pix<=adjust_hold;brightness_ack<=brightness_req_sync[1];
    end
   end
  end
 wire [23:0] adjusted_rgb;
 video_brightness_lut brightness_lut(.pix_clk(pix_clk),.rst_n(rst_n),.vsync(vsync),
  .rgb_in(wave_rgb),.cfg_valid(table_cfg_valid),.cfg_ready(brightness_ready),
  .brightness(table_brightness),.gain_q8(table_gain),.fade(fade_level),
  .cfg_applied(brightness_applied),.rgb_out(adjusted_rgb));
 // Reuse one of the final pixel delays for the synchronous subtitle ROM.
 // Total video delay stays ten clocks, including DE/sync and audio lookahead.
 localparam FIRST_PIXEL=CHINESE_SUBTITLE?3:2;
 reg [9:0] dp,hp,vp;reg [23:0] pixels[FIRST_PIXEL:9];integer i;
 wire [23:0] overlay_rgb;
 generate if(CHINESE_SUBTITLE)begin:chinese
  reg [9:0] x_pipe[0:1],y_pipe[0:1];
  always @(posedge pix_clk or negedge rst_n)begin
   if(!rst_n)begin x_pipe[0]<=0;x_pipe[1]<=0;y_pipe[0]<=0;y_pipe[1]<=0;end
   else begin x_pipe[0]<=osd_x;x_pipe[1]<=x_pipe[0];y_pipe[0]<=osd_y;y_pipe[1]<=y_pipe[0];end
  end
  video_chinese_subtitle subtitle(.clk(pix_clk),.rst_n(rst_n),.de(dp[1]),.vsync(vp[1]),
   .x(x_pipe[1]),.y(y_pipe[1]),.rgb_in(adjusted_rgb),.rgb_out(overlay_rgb));
 end else begin:legacy_subtitle
  assign overlay_rgb=adjusted_rgb;
 end endgenerate
 wire vd=dp[9],hs=hp[9],vs=vp[9];
 reg prev_hs,prev_vs,locked;
 reg [9:0] x;
 wire line_start=prev_hs&&!hs;
 wire frame_start=prev_vs&&!vs;
 reg island;reg [6:0] phase;
 reg schedule_fault;
 wire ar,br,ap,bp,av,bv;wire [4:0] ai,bi;
 wire [9:0] a0,a1,a2,b0,b1,b2;
 wire packet_valid;wire [23:0] ah,bh;wire [223:0] ab,bb;
 wire build=locked && x==580 && ar && br;
 // The preceding line's islands have finished by x=500, before the next
 // packet build at x=580. Never reset a packet builder or an active encoder.
 assign flush_safe=(!locked||x==500)&&!island&&ar&&br&&!packet_valid;
 hdmi_audio_packets packets(.clk(pix_clk),.rst_n(rst_n),.build(build),.frame_start(frame_start),
  .fifo_empty(packet_fifo_empty),.fifo_data(fifo_data),.fifo_read(fifo_read),.sample_request(sample_request),.packet_valid(packet_valid),
  .audio_header(ah),.audio_body(ab),.aux_header(bh),.aux_body(bb));
 hdmi_data_island_encoder audio_packet(.clk(pix_clk),.rst_n(rst_n),.packet_valid(packet_valid),
  .packet_ready(ar),.packet_header(ah),.packet_body(ab),.send_start(island&&phase==9),
  .hsync(hs),.vsync(vs),.control_d3(ai!=0),.prepared(ap),.symbol_valid(av),
  .symbol_last(),.symbol_index(ai),.channel0(a0),.channel1(a1),.channel2(a2));
 hdmi_data_island_encoder auxiliary_packet(.clk(pix_clk),.rst_n(rst_n),.packet_valid(packet_valid),
  .packet_ready(br),.packet_header(bh),.packet_body(bb),.send_start(island&&phase==41),
  .hsync(hs),.vsync(vs),.control_d3(1'b1),.prepared(bp),.symbol_valid(bv),
  .symbol_last(),.symbol_index(bi),.channel0(b0),.channel1(b1),.channel2(b2));
 always @(posedge pix_clk or negedge rst_n)begin
  if(!rst_n)begin
   dp<=0;hp<=10'h3ff;vp<=10'h3ff;for(i=FIRST_PIXEL;i<10;i=i+1)pixels[i]<=0;
   prev_hs<=1;prev_vs<=1;locked<=0;x<=0;island<=0;phase<=0;schedule_fault<=0;
  end else begin
   dp<={dp[8:0],de};hp<={hp[8:0],hsync};vp<={vp[8:0],vsync};
   pixels[FIRST_PIXEL]<=overlay_rgb;for(i=FIRST_PIXEL+1;i<10;i=i+1)pixels[i]<=pixels[i-1];
   prev_hs<=hs;prev_vs<=vs;
   if(line_start)begin locked<=1;x<=657;end
   else if(x==799)x<=0;else x<=x+1'b1;
   if(island)begin
    if(phase==75)begin island<=0;phase<=0;end else phase<=phase+1'b1;
    if(vd)schedule_fault<=1;
    if(phase>=10&&phase<=41&&!av)schedule_fault<=1;
    if(phase>=42&&phase<=73&&!bv)schedule_fault<=1;
   end else if(line_start&&ap&&bp)begin island<=1;phase<=0;end
   else if(line_start&&locked)schedule_fault<=1;
  end
 end
 wire video_preamble=!vd && de && !dp[7];
 wire video_guard=!vd && dp[7];
 wire [9:0] vr,vg,vb,guard0;
 tmds_channels video_enc(.pix_clk(pix_clk),.rst_n(rst_n),.de(vd),.hsync(hs),.vsync(vs),
  .red(pixels[9][23:16]),.green(pixels[9][15:8]),.blue(pixels[9][7:0]),
  .tmds_red(vr),.tmds_green(vg),.tmds_blue(vb));
 hdmi_terc4 guard_encode(.nibble({2'b11,vs,hs}),.symbol(guard0));
 function [9:0] control;input c0,c1;begin
  case({c1,c0})
   0:control=10'b1101010100;1:control=10'b0010101011;
   2:control=10'b0101010100;3:control=10'b1010101011;
  endcase
 end endfunction
 reg special;reg [9:0] sr,sg,sb;
 // 与视频编码器的单拍输出延迟一致，再送现有 DDR 串行器。
 always @(posedge pix_clk or negedge rst_n)begin
  if(!rst_n)begin special<=0;sr<=0;sg<=0;sb<=0;end
  else begin
   special<=!vd;
   sr<=control(0,0);sg<=control(0,0);sb<=control(hs,vs);
   if(island)begin
    if(phase<8)begin sr<=control(1,0);sg<=control(1,0);end
    else if(phase<10||phase>=74)begin sr<=10'b0100110011;sg<=10'b0100110011;sb<=guard0;end
    else if(phase<42)begin sr<=a2;sg<=a1;sb<=a0;end
    else begin sr<=b2;sg<=b1;sb<=b0;end
   end else if(video_guard)begin sr<=10'b1011001100;sg<=10'b0100110011;sb<=10'b1011001100;end
   else if(video_preamble)sg<=control(1,0);
  end
 end
 assign red=special?sr:vr;assign green=special?sg:vg;assign blue=special?sb:vb;
 assign audio_fault=overflow|schedule_fault|audio_underflow;
endmodule
