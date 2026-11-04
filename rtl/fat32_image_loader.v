// Sector-interface image loader: mount/catalogue -> select slot -> file -> BMP pixels.
// Pulse scan_start while idle, wait scan_done&&!error. Then pulse load_start.
// pixel stream writes a non-display buffer; commit only image_done&&!error.
module fat32_image_loader #(parameter integer FRAME_WIDTH=640,FRAME_HEIGHT=480,
 parameter integer TIMEOUT_CYCLES=50_000_000,FIND_WAV=0,MAX_IMAGES=4,
 parameter integer INDEX_BITS=(MAX_IMAGES>1)?$clog2(MAX_IMAGES):1,
 parameter integer COUNT_BITS=(MAX_IMAGES>0)?$clog2(MAX_IMAGES+1):1,parameter MAX_WAVS=1)(
 input wire clk,rst_n,scan_start,load_start,input wire [INDEX_BITS-1:0] image_index,
 input wire rd_ready,rd_done,rd_error,input wire [8:0] rd_addr,input wire [7:0] rd_data,input wire rd_valid,
 output wire rd_start,output wire [31:0] rd_lba,
 input wire pixel_ready,output wire pixel_valid,output wire [31:0] pixel_addr,output wire [23:0] pixel_rgb,
 output reg busy,catalog_ready,scan_done,image_done,error,output reg [COUNT_BITS-1:0] image_count,
 output reg frame_start,
 output wire [31:0] volume_root_lba,volume_root_cluster,
 volume_fat_lba,volume_data_lba,volume_cluster_count,
 output wire [7:0] volume_sectors_per_cluster,
 output wire wav_found,output wire [31:0] wav_first_cluster,wav_size,
 input wire [1:0] wav_index,output wire [2:0] wav_count,output wire [24:0] folder_info);
 localparam IDLE=0,SCAN_LAUNCH=1,SCAN_WAIT=2,LOAD_LAUNCH=3,LOAD_WAIT=4;
 reg [2:0] state;
 reg cat_start,file_start,decoder_start;
 reg [63:0] chosen_metadata;
 wire [31:0] chosen_cluster=chosen_metadata[63:32],chosen_size=chosen_metadata[31:0];
 wire cat_req,cat_done,cat_error,cat_busy,found;
 wire [INDEX_BITS-1:0] found_index;
 wire [COUNT_BITS-1:0] found_count;
 wire [31:0] cat_lba,found_cluster,found_size,fat_base,data_base,clusters;
 wire [7:0] spc;
 assign volume_fat_lba=fat_base;assign volume_data_lba=data_base;
 assign volume_cluster_count=clusters;assign volume_sectors_per_cluster=spc;
 wire file_req,file_done,file_error,file_busy,byte_valid,byte_ready;
 wire [31:0] file_lba,byte_offset;
 wire [7:0] byte_data;
 wire [3:0] file_error_code;
 wire dec_done,dec_error,dec_busy,dec_pixel_valid;
 wire loading=(state==LOAD_LAUNCH || state==LOAD_WAIT);
 // Larger catalogues use synchronous RAM reads at the original load-accept
 // edge. Both metadata words are ready before LOAD_LAUNCH starts decoding.
 wire metadata_write=rst_n && state==SCAN_WAIT && found && found_index<MAX_IMAGES;
 wire metadata_read=rst_n && state==IDLE && !scan_start && load_start &&
  catalog_ready && {1'b0,image_index}<image_count;
 generate if(MAX_IMAGES<=4)begin:small_catalog
  reg [31:0] file_clusters[0:MAX_IMAGES-1],file_sizes[0:MAX_IMAGES-1];
  integer i;
  always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin
    chosen_metadata<=0;
    for(i=0;i<MAX_IMAGES;i=i+1)begin file_clusters[i]<=0;file_sizes[i]<=0;end
   end else begin
    if(metadata_write)begin file_clusters[found_index]<=found_cluster;file_sizes[found_index]<=found_size;end
    if(metadata_read)chosen_metadata<={file_clusters[image_index],file_sizes[image_index]};
   end
  end
 end else begin:ram_catalog
  // TD's documented RAM-Inference-Styles directive avoids a bank of
  // registers for this shallow 32-entry, 64-bit metadata table.
  (* ram_style="bram" *) reg [63:0] file_metadata[0:MAX_IMAGES-1];
  // No reset on RAM or its output registers. catalog_ready/count guard every
  // read, so entries from an incomplete/failed scan are never consumed.
  always @(posedge clk)begin
   if(metadata_write)file_metadata[found_index]<={found_cluster,found_size};
   if(metadata_read)chosen_metadata<=file_metadata[image_index];
  end
 end endgenerate
 assign rd_start=loading?file_req:cat_req;
 assign rd_lba=loading?file_lba:cat_lba;
 assign pixel_valid=loading && dec_pixel_valid;
 fat32_card_catalog #(.MAX_FILES(MAX_IMAGES),.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.FIND_WAV(FIND_WAV),.MAX_WAVS(MAX_WAVS),.TOPIC_FOLDERS(MAX_IMAGES==24)) u_catalog(
  .clk(clk),.rst_n(rst_n),.start(cat_start),.rd_ready(rd_ready && !loading),.rd_done(rd_done && !loading),
  .rd_error(rd_error),.rd_addr(rd_addr),.rd_data(rd_data),.rd_valid(rd_valid && !loading),
  .rd_start(cat_req),.rd_lba(cat_lba),.busy(cat_busy),.done(cat_done),.error(cat_error),
  .found_valid(found),.found_index(found_index),.found_first_cluster(found_cluster),.found_size(found_size),.found_count(found_count),
  .volume_fat_lba(fat_base),.volume_data_lba(data_base),
  .volume_root_lba(volume_root_lba),.volume_root_cluster(volume_root_cluster),.volume_cluster_count(clusters),.volume_sectors_per_cluster(spc),
  .wav_index(wav_index),.wav_count(wav_count),.wav_found(wav_found),.wav_first_cluster(wav_first_cluster),.wav_size(wav_size),.folder_info(folder_info));
 fat32_file_reader #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) u_file(
  .clk(clk),.rst_n(rst_n),.start(file_start),.stop(1'b0),.first_cluster(chosen_cluster),.file_size(chosen_size),
  .fat_lba(fat_base),.data_lba(data_base),.cluster_count(clusters),.sectors_per_cluster(spc),
  .rd_ready(rd_ready && loading),.rd_done(rd_done && loading),.rd_error(rd_error),
  .rd_addr(rd_addr),.rd_data(rd_data),.rd_valid(rd_valid && loading),.rd_start(file_req),.rd_lba(file_lba),
  .out_ready(byte_ready),.out_valid(byte_valid),.out_data(byte_data),.out_offset(byte_offset),
  .busy(file_busy),.done(file_done),.error(file_error),.error_code(file_error_code));
 // Runtime 320x240 -> 640x480 nearest-neighbor expansion on the board profile.
 // Other diagnostic dimensions retain the original fixed-size contract.
 bmp_stream_decoder #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT),
  .ALLOW_HALF(FRAME_WIDTH==640 && FRAME_HEIGHT==480)) u_decoder(
  .clk(clk),.rst_n(rst_n),.start(decoder_start),.file_size(chosen_size),.byte_data(byte_data),
  .byte_offset(byte_offset),.byte_valid(byte_valid),.byte_ready(byte_ready),.stream_done(file_done),.stream_error(file_error),
  .pixel_ready(pixel_ready),.pixel_valid(dec_pixel_valid),.pixel_addr(pixel_addr),.pixel_rgb(pixel_rgb),
  .busy(dec_busy),.done(dec_done),.error(dec_error));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   state<=IDLE;cat_start<=0;file_start<=0;decoder_start<=0;
   busy<=0;catalog_ready<=0;scan_done<=0;image_done<=0;error<=0;image_count<=0;frame_start<=0;
  end else begin
   cat_start<=0;file_start<=0;decoder_start<=0;scan_done<=0;image_done<=0;frame_start<=0;
   case(state)
    IDLE:if(scan_start)begin busy<=1;error<=0;catalog_ready<=0;image_count<=0;state<=SCAN_LAUNCH;end
         else if(load_start)begin
          error<=0;
          if(!catalog_ready || {1'b0,image_index}>=image_count)begin error<=1;image_done<=1;end
          else begin
           busy<=1;
           frame_start<=1;state<=LOAD_LAUNCH;
          end
         end
    SCAN_LAUNCH:begin cat_start<=1;state<=SCAN_WAIT;end
    SCAN_WAIT:if(cat_done)begin
     busy<=0;scan_done<=1;error<=cat_error;catalog_ready<=!cat_error;
     image_count<=cat_error?0:found_count;state<=IDLE;
    end
    LOAD_LAUNCH:begin file_start<=1;decoder_start<=1;state<=LOAD_WAIT;end
    LOAD_WAIT:if(dec_done)begin busy<=0;image_done<=1;error<=dec_error;state<=IDLE;end
    default:begin busy<=0;error<=1;state<=IDLE;end
   endcase
  end
 end
endmodule
