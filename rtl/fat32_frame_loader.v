// Sector-to-double-buffer integration. All ports use clk; memory is external.
// Pulse load_start only while load_ready. Display access is a stalled memory
// transaction interface, NOT a direct pixel-clock video output.
module fat32_frame_loader #(parameter integer FRAME_WIDTH=640,FRAME_HEIGHT=480,
 parameter integer TIMEOUT_CYCLES=50_000_000,FIND_WAV=0,CONTROLLED_SWAP=0,MAX_IMAGES=4,
 parameter integer INDEX_BITS=(MAX_IMAGES>1)?$clog2(MAX_IMAGES):1,
 parameter integer COUNT_BITS=(MAX_IMAGES>0)?$clog2(MAX_IMAGES+1):1,parameter MAX_WAVS=1,parameter ABORTABLE=0,CACHE_FRAMES=0)(
 input wire clk,rst_n,scan_start,load_start,input wire [INDEX_BITS-1:0] image_index,
 output wire load_ready,busy,catalog_ready,scan_done,image_done,error,
 output wire [COUNT_BITS-1:0] image_count,
 output wire [31:0] volume_root_lba,volume_root_cluster,
 volume_fat_lba,volume_data_lba,volume_cluster_count,
 output wire [7:0] volume_sectors_per_cluster,
 output wire wav_found,output wire [31:0] wav_first_cluster,wav_size,
 input wire rd_ready,rd_done,rd_error,input wire [8:0] rd_addr,input wire [7:0] rd_data,input wire rd_valid,
 output wire rd_start,output wire [31:0] rd_lba,
 output wire wr_valid,output wire [31:0] wr_addr,wr_data,input wire wr_ready,wr_drained,
 input wire swap_window,output wire front_valid,front_bank,frame_committed,frame_rejected,swap_pending,
 input wire read_valid,input wire [31:0] read_addr,output wire read_ready,
 output wire rgb_valid,output wire [23:0] rgb_data,input wire rgb_ready,
 output wire mem_read_valid,output wire [31:0] mem_read_addr,input wire mem_read_ready,
 input wire mem_response_valid,input wire [31:0] mem_response_data,
 input wire commit_enable,discard_cached,abort_load,
 input wire [1:0] wav_index,output wire [2:0] wav_count,output wire [6:0] prepare_pixels,output wire [24:0] folder_info,
 input wire retain_album,front_matches,input wire [INDEX_BITS-1:0] retain_first,
 output wire cache_hit,output wire [20:0] front_base,back_base);
 wire loader_busy,frame_ready,frame_start,pixel_valid,pixel_ready,decoder_done,decoder_error;
 // Allocate the slot on the same edge that selects cache reuse or starts
 // the decoder. Album changes can update the mapping on the next edge.
 wire allocate=load_start&&load_ready&&{1'b0,image_index}<image_count;
 wire reuse=CACHE_FRAMES&&cache_hit&&allocate;
 reg reuse_done,reused_frame;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin reuse_done<=0;reused_frame<=0;end
  else begin
   reuse_done<=reuse;
   if(scan_start)reused_frame<=0;
   else if(load_start&&load_ready)reused_frame<=reuse;
  end
 assign image_done=decoder_done||(CACHE_FRAMES&&reuse_done);
 assign error=decoder_error&&!(CACHE_FRAMES&&reused_frame);
 wire [31:0] pixel_addr;
 wire [23:0] pixel_rgb;
 assign load_ready=frame_ready && !loader_busy && catalog_ready && !scan_start;
 assign busy=loader_busy || !frame_ready;
 fat32_image_loader #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT),.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.FIND_WAV(FIND_WAV),.MAX_IMAGES(MAX_IMAGES),.MAX_WAVS(MAX_WAVS),.ABORTABLE(ABORTABLE)) u_image(
 .clk(clk),.rst_n(rst_n),.scan_start(scan_start),.load_start(load_start && load_ready&&!reuse),.image_index(image_index),.abort_load(abort_load),
 .rd_ready(rd_ready),.rd_done(rd_done),.rd_error(rd_error),.rd_addr(rd_addr),.rd_data(rd_data),.rd_valid(rd_valid),
 .rd_start(rd_start),.rd_lba(rd_lba),.pixel_ready(pixel_ready),.pixel_valid(pixel_valid),.pixel_addr(pixel_addr),.pixel_rgb(pixel_rgb),
 .busy(loader_busy),.catalog_ready(catalog_ready),.scan_done(scan_done),.image_done(decoder_done),.error(decoder_error),.image_count(image_count),.frame_start(frame_start),
 .volume_root_lba(volume_root_lba),.volume_root_cluster(volume_root_cluster),
 .volume_fat_lba(volume_fat_lba),.volume_data_lba(volume_data_lba),
 .volume_cluster_count(volume_cluster_count),
 .volume_sectors_per_cluster(volume_sectors_per_cluster),
 .wav_index(wav_index),.wav_count(wav_count),.wav_found(wav_found),.wav_first_cluster(wav_first_cluster),.wav_size(wav_size),.folder_info(folder_info));
 frame_buffer_manager #(.FRAME_PIXELS(FRAME_WIDTH*FRAME_HEIGHT),.ALLOW_DISCARD(CONTROLLED_SWAP),.CACHE_FRAMES(CACHE_FRAMES),.INDEX_BITS(INDEX_BITS)) u_frame(
 .clk(clk),.rst_n(rst_n),.frame_start(CACHE_FRAMES?allocate:frame_start),.frame_done(decoder_done),.frame_error(error),.frame_ready(frame_ready),
 .pixel_valid(pixel_valid),.pixel_addr(pixel_addr),.pixel_rgb(pixel_rgb),.pixel_ready(pixel_ready),
 .wr_valid(wr_valid),.wr_addr(wr_addr),.wr_data(wr_data),.wr_ready(wr_ready),.wr_drained(wr_drained),
 .swap_window(swap_window && (!CONTROLLED_SWAP || commit_enable)),
 .discard_frame(discard_cached),.front_valid(front_valid),.front_bank(front_bank),.frame_committed(frame_committed),.frame_rejected(frame_rejected),.swap_pending(swap_pending),.prepare_pixels(prepare_pixels),
 .read_valid(read_valid),.read_addr(read_addr),.read_ready(read_ready),.rgb_valid(rgb_valid),.rgb_data(rgb_data),.rgb_ready(rgb_ready),
 .mem_read_valid(mem_read_valid),.mem_read_addr(mem_read_addr),.mem_read_ready(mem_read_ready),
 .mem_response_valid(mem_response_valid),.mem_response_data(mem_response_data),
 .image_index(image_index),.retain_first(retain_first),
 .retain_album(retain_album),.front_matches(front_matches),.reuse_frame(reuse),.cache_hit(cache_hit),.front_base(front_base),.back_base(back_base));
endmodule
