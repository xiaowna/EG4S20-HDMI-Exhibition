// Integration/synthesis core. clk=50 MHz, pix_clk=25 MHz supplied externally.
// RGB/sync outputs feed a separately verified HDMI transmitter.
// next_pulse and pause must already be safe in clk domain.
module sd_media_player #(parameter CLK_HZ=50000000,FRAME_WIDTH=640,FRAME_HEIGHT=480,
 parameter INTERVAL_CYCLES=250000000,parameter MODE_CONTROL=0,parameter integer MAX_IMAGES=4,
 parameter integer INDEX_BITS=(MAX_IMAGES>1)?$clog2(MAX_IMAGES):1,
 parameter integer COUNT_BITS=(MAX_IMAGES>0)?$clog2(MAX_IMAGES+1):1,parameter SLIDE_TRANSITIONS=0,parameter MAX_WAVS=1,parameter ALBUMS=0,parameter INTRO_ANIMATION=0,parameter FAST_MANUAL=0,parameter AUTOPLAY_INTERVAL_MENU=0)(
 input wire clk,pix_clk,rst_n,sd_miso,next_pulse,pause,audio_urgent,
 output wire sd_sck,sd_mosi,sd_cs,
 output wire de,hsync,vsync,output wire [23:0] rgb,
 output wire card_ready,card_error,sdram_ready,memory_fault,prefetch_error,frame_underflow,video_started,
 output wire loading,image_error,output wire [COUNT_BITS-1:0] image_count,output wire [INDEX_BITS-1:0] image_index,
 output wire wav_valid,input wire wav_ready,output wire [47:0] wav_data,
 output wire wav_playing,wav_error,catalog_ready,wav_found,
 output reg [INDEX_BITS-1:0] display_index,output wire display_valid,output reg audio_only,
 input wire prev_pulse,transition_ready,output wire transition_active,
 input wire auto_enable,wav_enable,output wire wav_idle,slide_transition,
 input wire [1:0] wav_index,output wire [2:0] wav_count,
 input wire album_request,album_enable,input wire [INDEX_BITS-1:0] album_first,
 input wire [COUNT_BITS-1:0] album_limit,output wire album_ready,album_error,
 output wire preparing,output wire [6:0] prepare_pixels,input wire intro_enable,intro_pause,output wire [24:0] folder_info,input wire fast_pulse,
 input wire [2:0] autoplay_interval);
 // Production gallery dwell is 10/13 of its configured duration. Divide first
 // to avoid signed 32-bit overflow at the ordinary 250,000,000-cycle setting.
 // Retry timing remains INTERVAL_CYCLES inside the prefetch controller.
 localparam integer GALLERY_INTERVAL=(INTERVAL_CYCLES/13)*10+((INTERVAL_CYCLES%13)*10+6)/13;
 localparam integer AUTOPLAY_INTERVAL=INTRO_ANIMATION?((GALLERY_INTERVAL>0)?GALLERY_INTERVAL:1):INTERVAL_CYCLES;
 wire frame_committed;
 wire prepare_progress_valid;wire [6:0] loaded_pixels;
 assign prepare_pixels=prepare_progress_valid?loaded_pixels:7'd0;
 wire scan_start,load_start,load_ready,scan_done,image_done,rd_ready,rd_done,rd_error,rd_valid,rd_start;
 wire commit_enable,discard_cached,frame_prepared;
 wire transition_manual,transition_backward,slide_ready;
 localparam CACHE_FRAMES=FAST_MANUAL&&ALBUMS;
 wire [INDEX_BITS-1:0] retain_first;wire preserve_album;
 wire cancel_load,fast_commit,load_error;
 reg intro_instant,cancelled_error;
 // A cancelled prefetch is rejected by the buffer manager, without raising a
 // media error or enabling the audio-only fallback.
 assign image_error=load_error&&!cancel_load&&!cancelled_error;
 wire intro_animating;
 wire [4:0] display_intro_index;
 wire display_intro_last;
 generate if(INTRO_ANIMATION&&MAX_IMAGES==24)begin:folder_display_index
  wire [5:0] ordinal={1'b0,display_index};
  wire [1:0] group=(ordinal<folder_info[5:0])?2'd0:
   ((ordinal<folder_info[11:6])?2'd1:((ordinal<folder_info[17:12])?2'd2:2'd3));
  wire [5:0] first=(group==0)?6'd0:((group==1)?folder_info[5:0]:((group==2)?folder_info[11:6]:folder_info[17:12]));
  wire [5:0] last=(group==0)?folder_info[5:0]:((group==1)?folder_info[11:6]:((group==2)?folder_info[17:12]:folder_info[23:18]));
  wire [4:0] topic_base={1'b0,group,2'b00}+{2'b0,group,1'b0};
  assign display_intro_index=folder_info[24]?(topic_base+((ordinal+1'b1==last)?5'd5:ordinal-first)):display_index;
  // Catalogue ranges contain at most six pages per topic. Test their ends
  // directly; the playback controller does not need the caption remapping
  // subtraction/addition on its pause and transition path.
  wire [5:0] following=ordinal+6'd1;
  assign display_intro_last=folder_info[24]?
   (following==folder_info[5:0]||following==folder_info[11:6]||
    following==folder_info[17:12]||following==folder_info[23:18]):
   (display_index==5||display_index==11||display_index==17||display_index==23);
 end else begin:flat_display_index
  assign display_intro_index={{(5-INDEX_BITS){1'b0}},display_index};
  assign display_intro_last=(display_intro_index==5||display_intro_index==11||display_intro_index==17||display_intro_index==23);
 end endgenerate
 wire intro_frame=INTRO_ANIMATION&&intro_enable&&display_intro_last;
 wire wait_intro=(!AUTOPLAY_INTERVAL_MENU||autoplay_interval==3'd7)&&intro_animating;
 // Fade a composed introduction on exit; a raw-source slide would enlarge
 // its settled photograph. Ordinary photo-to-photo slides are unchanged.
 assign slide_transition=SLIDE_TRANSITIONS&&!intro_frame&&(transition_manual||(ALBUMS&&album_enable&&transition_active));
 reg [INDEX_BITS-1:0] loading_index;
 // 只发布已提交前帧的编号，失败加载保留旧编号。
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin loading_index<=0;display_index<=0;audio_only<=0;intro_instant<=0;cancelled_error<=0;end
  else begin
   if(load_start && load_ready)begin loading_index<=image_index;cancelled_error<=0;end
   if(image_done && cancel_load)cancelled_error<=1;
   if(frame_committed)begin display_index<=loading_index;intro_instant<=fast_commit;end
   // 首图失败或目录没有图片时允许音频独立播放，直到复位。
   if((catalog_ready && image_count==0) || (image_done && image_error))audio_only<=1;
  end
 end
 wire [8:0] rd_addr,card_addr,wav_addr;
 wire [7:0] rd_data,card_data,wav_byte;
 wire [31:0] rd_lba,card_lba,wav_lba;
 wire card_rd_start,card_rd_ready,card_rd_done,card_rd_error,card_valid;
 wire wav_rd_start,wav_rd_ready,wav_rd_done,wav_rd_error,wav_byte_valid;
 wire [31:0] volume_root_lba,volume_root_cluster,
  volume_fat_lba,volume_data_lba,volume_cluster_count;
 wire [7:0] volume_sectors_per_cluster;
 wire [31:0] wav_first_cluster,wav_size;
 sd_subsystem #(.CLK_HZ(CLK_HZ)) u_card(
 .clk(clk),.rst_n(rst_n),.sd_sck(sd_sck),.sd_mosi(sd_mosi),.sd_miso(sd_miso),.sd_cs(sd_cs),.ready(card_ready),.error(card_error),
 .read_start(card_rd_start),.read_lba(card_lba),.read_request_ready(card_rd_ready),
 .read_done(card_rd_done),.read_error(card_rd_error),
 .data_addr(card_addr),.data_out(card_data),.data_valid(card_valid));
 sd_sector_arbiter u_arbiter(.clk(clk),.rst_n(rst_n),.card_ready(card_rd_ready),.audio_urgent(audio_urgent),
 .card_done(card_rd_done),.card_error(card_rd_error),.card_addr(card_addr),
 .card_data(card_data),.card_valid(card_valid),.card_start(card_rd_start),.card_lba(card_lba),
 .image_start(rd_start),.image_lba(rd_lba),.image_ready(rd_ready),
 .image_done(rd_done),.image_error(rd_error),.image_addr(rd_addr),
 .image_data(rd_data),.image_valid(rd_valid),
 .audio_start(wav_rd_start),.audio_lba(wav_lba),.audio_ready(wav_rd_ready),
 .audio_done(wav_rd_done),.audio_error(wav_rd_error),.audio_addr(wav_addr),
 .audio_data(wav_byte),.audio_valid(wav_byte_valid));
 wire wav_reader_idle;
 reg wav_sector_busy;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)wav_sector_busy<=0;
  else if(wav_rd_done)wav_sector_busy<=0;
  else if(wav_rd_start)wav_sector_busy<=1;
 // Also wait for the card owner after a file-reader timeout. Never reset or
 // reassign an in-flight sector merely because its logical reader stopped.
 assign wav_idle=wav_reader_idle&&!wav_sector_busy&&!wav_rd_start;
 fat32_wav_player #(.CONTROLLED_STOP(MODE_CONTROL)) u_wav(.clk(clk),.rst_n(rst_n),.volume_ready(catalog_ready),.file_found(wav_found),
 .play_enable(wav_enable),.idle(wav_reader_idle),
 .first_cluster(wav_first_cluster),.file_size(wav_size),
 .fat_lba(volume_fat_lba),.data_lba(volume_data_lba),
 .cluster_count(volume_cluster_count),.sectors_per_cluster(volume_sectors_per_cluster),
 .rd_ready(wav_rd_ready),.rd_done(wav_rd_done),.rd_error(wav_rd_error),
 .rd_addr(wav_addr),.rd_data(wav_byte),.rd_valid(wav_byte_valid),
 .rd_start(wav_rd_start),.rd_lba(wav_lba),.sample_valid(wav_valid),
 .sample_ready(wav_ready),.sample_data(wav_data),.playing(wav_playing),.error(wav_error));
 media_prefetch_control #(.FAST_MANUAL(FAST_MANUAL),.INTERVAL_CYCLES(INTERVAL_CYCLES),.AUTOPLAY_CYCLES(AUTOPLAY_INTERVAL),.CONTROLLED_AUTOPLAY(MODE_CONTROL),.CONTROLLED_PREFETCH(INTRO_ANIMATION),.MAX_IMAGES(MAX_IMAGES),.ALBUMS(ALBUMS),
 .AUTOPLAY_SECOND_CYCLES(AUTOPLAY_INTERVAL_MENU?CLK_HZ:0),.CACHE_FRAMES(CACHE_FRAMES)) u_control(
 .retain_first(retain_first),.preserve_album(preserve_album),
 .prefetch_enable(intro_enable),.fast_pulse(fast_pulse),.cancel_load(cancel_load),.fast_commit(fast_commit),
 .preparing(preparing),.prepare_progress_valid(prepare_progress_valid),
 .album_request(album_request),.album_enable(album_enable),.album_first(album_first),.album_limit(album_limit),
 .album_ready(album_ready),.album_error(album_error),
 .auto_enable(auto_enable),.autoplay_interval(autoplay_interval),
 .clk(clk),.rst_n(rst_n),.card_ready(card_ready&&sdram_ready&&!memory_fault&&!prefetch_error),.load_ready(load_ready),
 .scan_done(scan_done),.image_done(image_done),.error(image_error),.image_count(image_count),.next_pulse(next_pulse),.prev_pulse(prev_pulse),.pause(pause||(INTRO_ANIMATION&&(wait_intro||(intro_frame&&intro_pause)))),
 .front_valid(display_valid),.display_index(display_index),.frame_prepared(frame_prepared),
 .frame_committed(frame_committed),.transition_ready(slide_transition?slide_ready:transition_ready),
 .commit_enable(commit_enable),.discard_cached(discard_cached),.transition_active(transition_active),
 .scan_start(scan_start),.load_start(load_start),.image_index(image_index),
 .transition_manual(transition_manual),.transition_backward(transition_backward));
 media_stream_pipeline #(.CLK_HZ(CLK_HZ),.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT),.FIND_WAV(1),.CONTROLLED_SWAP(1),.MAX_IMAGES(MAX_IMAGES),.SLIDE_TRANSITIONS(SLIDE_TRANSITIONS),.MAX_WAVS(MAX_WAVS),.INTRO_ANIMATION(INTRO_ANIMATION),.ABORTABLE(FAST_MANUAL),.CACHE_FRAMES(CACHE_FRAMES)) u_media(
 .retain_album(preserve_album),.front_matches(display_valid&&image_index==display_index&&image_index==retain_first),.retain_first(retain_first),
 .prepare_pixels(loaded_pixels),.folder_info(folder_info),
 .clk(clk),.pix_clk(pix_clk),.rst_n(rst_n),.scan_start(scan_start),.load_start(load_start),.image_index(image_index),
 .load_ready(load_ready),.catalog_ready(catalog_ready),.busy(loading),.scan_done(scan_done),.image_done(image_done),.error(load_error),.image_count(image_count),
 .rd_ready(rd_ready),.rd_done(rd_done),.rd_error(rd_error),.rd_addr(rd_addr),.rd_data(rd_data),.rd_valid(rd_valid),.rd_start(rd_start),.rd_lba(rd_lba),
 .front_valid(display_valid),.frame_committed(frame_committed),
 .commit_enable(commit_enable),.discard_cached(discard_cached),.frame_prepared(frame_prepared),
 .slide_request(slide_transition),.slide_right(transition_backward),.slide_ready(slide_ready),.abort_load(cancel_load),
 .de(de),.hsync(hsync),.vsync(vsync),.rgb(rgb),.frame_underflow(frame_underflow),.video_started(video_started),
 .sdram_ready(sdram_ready),.memory_fault(memory_fault),.prefetch_error(prefetch_error),
 .volume_root_lba(volume_root_lba),.volume_root_cluster(volume_root_cluster),
 .volume_fat_lba(volume_fat_lba),.volume_data_lba(volume_data_lba),
 .volume_cluster_count(volume_cluster_count),
 .volume_sectors_per_cluster(volume_sectors_per_cluster),
 .wav_index(wav_index),.wav_count(wav_count),
 .wav_found(wav_found),.wav_first_cluster(wav_first_cluster),.wav_size(wav_size),
 // Playback pause must not hide a manually selected picture's caption or
 // freeze its introduction. Menu/mode and bank-transition fences still apply.
 .intro_enable(intro_enable),.intro_pause(intro_pause||transition_active),
 .intro_index(display_intro_index),.intro_instant(intro_instant),.intro_animating(intro_animating));
endmodule
