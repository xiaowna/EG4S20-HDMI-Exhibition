// Automatic LBA0 -> FAT32 volume -> root BMP catalogue. Sector interface.
// found events remain provisional until done && !error; repeat start only when idle.
module fat32_card_catalog #(parameter integer MAX_FILES=4,TIMEOUT_CYCLES=50_000_000,
 parameter [23:0] EXTENSION=24'h424d50, parameter FIND_WAV=0,
 parameter integer INDEX_BITS=(MAX_FILES>1)?$clog2(MAX_FILES):1,
 parameter integer COUNT_BITS=(MAX_FILES>0)?$clog2(MAX_FILES+1):1,parameter MAX_WAVS=1,TOPIC_FOLDERS=0)(
 input wire clk,rst_n,start,input wire rd_ready,rd_done,rd_error,
 input wire [8:0] rd_addr,input wire [7:0] rd_data,input wire rd_valid,
 output wire rd_start,output wire [31:0] rd_lba,
 output reg busy,done,error,output wire found_valid,output wire [INDEX_BITS-1:0] found_index,
 output wire [31:0] found_first_cluster,found_size,output wire [COUNT_BITS-1:0] found_count,
 output wire [31:0] volume_fat_lba,volume_data_lba,volume_cluster_count,
 output wire [31:0] volume_root_lba,volume_root_cluster,
 output wire [7:0] volume_sectors_per_cluster,
 output wire wav_found,output wire [31:0] wav_first_cluster,wav_size,
 input wire [1:0] wav_index,output wire [2:0] wav_count,output wire [24:0] folder_info);
 localparam IDLE=0,LOC_START=1,LOC_WAIT=2,CAT_START=3,CAT_WAIT=4;
 reg [2:0] state;
 reg locate_start,catalog_start;
 wire loc_req,loc_done,loc_error,loc_valid,loc_busy;
 wire [31:0] loc_lba,volume_lba,volume_len;
 wire cat_req,cat_done,cat_error,cat_found,cat_busy;
 wire [31:0] cat_lba;
 wire cat_active=(state==CAT_START || state==CAT_WAIT);
 wire [255:0] loc_bpb_fields,cat_bpb_fields;
 wire [128:0] shared_bpb_result;
 // Sector delivery uses this same owner selection. Only the selected parser
 // can receive byte 511; local state and provisional metadata stay separate.
 fat32_bpb_math u_bpb_math(.clk(clk),
  .bpb_fields(cat_active?cat_bpb_fields:loc_bpb_fields),.bpb_result(shared_bpb_result));
 assign rd_start=cat_active?cat_req:loc_req;
 assign rd_lba=cat_active?cat_lba:loc_lba;
 assign found_valid=cat_active && cat_found;
 fat32_volume_locator #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.SHARED_BPB(1)) u_locator(
  .clk(clk),.rst_n(rst_n),.start(locate_start),.rd_ready(rd_ready && !cat_active),
  .rd_done(rd_done && !cat_active),.rd_error(rd_error),.rd_addr(rd_addr),.rd_data(rd_data),.rd_valid(rd_valid && !cat_active),
  .rd_start(loc_req),.rd_lba(loc_lba),.busy(loc_busy),.done(loc_done),.error(loc_error),.valid(loc_valid),
  .partition_lba(volume_lba),.partition_sectors(volume_len),
  .bpb_fields(loc_bpb_fields),.bpb_result(shared_bpb_result));
 fat32_bmp_catalog #(.MAX_FILES(MAX_FILES),.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.EXTENSION(EXTENSION),.FIND_WAV(FIND_WAV),.SHARED_BPB(1),.MAX_WAVS(MAX_WAVS),.TOPIC_FOLDERS(TOPIC_FOLDERS)) u_catalog(
  .clk(clk),.rst_n(rst_n),.start(catalog_start),.partition_lba(volume_lba),.partition_sectors(volume_len),
  .rd_ready(rd_ready && cat_active),.rd_done(rd_done && cat_active),.rd_error(rd_error),
  .rd_addr(rd_addr),.rd_data(rd_data),.rd_valid(rd_valid && cat_active),.rd_start(cat_req),.rd_lba(cat_lba),
  .busy(cat_busy),.done(cat_done),.error(cat_error),.found_valid(cat_found),.found_index(found_index),
  .found_first_cluster(found_first_cluster),.found_size(found_size),.found_count(found_count),
  .volume_fat_lba(volume_fat_lba),.volume_data_lba(volume_data_lba),
  .volume_root_lba(volume_root_lba),.volume_root_cluster(volume_root_cluster),
  .volume_cluster_count(volume_cluster_count),.volume_sectors_per_cluster(volume_sectors_per_cluster),
  .wav_index(wav_index),.wav_count(wav_count),.wav_found(wav_found),.wav_first_cluster(wav_first_cluster),.wav_size(wav_size),
  .bpb_fields(cat_bpb_fields),.bpb_result(shared_bpb_result),.folder_info(folder_info));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin state<=IDLE;locate_start<=0;catalog_start<=0;busy<=0;done<=0;error<=0;end
  else begin
   locate_start<=0;catalog_start<=0;done<=0;
   case(state)
    IDLE:if(start) begin busy<=1;error<=0;state<=LOC_START;end
    LOC_START:begin locate_start<=1;state<=LOC_WAIT;end
    LOC_WAIT:if(loc_done) begin
     if(loc_error || !loc_valid) begin busy<=0;done<=1;error<=1;state<=IDLE;end
     else state<=CAT_START;
    end
    CAT_START:begin catalog_start<=1;state<=CAT_WAIT;end
    CAT_WAIT:if(cat_done) begin busy<=0;done<=1;error<=cat_error;state<=IDLE;end
    default:begin busy<=0;done<=1;error<=1;state<=IDLE;end
   endcase
  end
 end
endmodule
