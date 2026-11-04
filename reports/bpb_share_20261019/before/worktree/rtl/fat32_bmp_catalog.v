// BPB-to-directory integration at the sd_subsystem sector interface.
// partition_lba is the FAT32 volume boot sector, NOT automatically an MBR at LBA 0.
// Only commit found results after done && !error; MAX_FILES bounds catalogue size.
module fat32_bmp_catalog #(parameter integer MAX_FILES=4,TIMEOUT_CYCLES=50_000_000,
 parameter [23:0] EXTENSION=24'h424d50, parameter FIND_WAV=0)(
 input wire clk,rst_n,start,input wire [31:0] partition_lba,
 input wire [31:0] partition_sectors, // 0 means no externally specified length limit.
 input wire rd_ready,rd_done,rd_error,input wire [8:0] rd_addr,
 input wire [7:0] rd_data,input wire rd_valid,
 output wire rd_start,output wire [31:0] rd_lba,
 output reg busy,done,error,output wire found_valid,output wire [1:0] found_index,
 output wire [31:0] found_first_cluster,found_size,output wire [2:0] found_count,
 output wire [31:0] volume_fat_lba,volume_data_lba,volume_cluster_count,
 output wire [31:0] volume_root_lba,volume_root_cluster,
 output wire [7:0] volume_sectors_per_cluster,
 output wire wav_found,output wire [31:0] wav_first_cluster,wav_size);
 localparam IDLE=0,BOOT_START=1,BOOT_REQUEST=2,BOOT_WAIT=3,BOOT_CHECK=4,DIR_START=5,DIR_WAIT=6;
 reg [2:0] state;
 reg boot_start,boot_req,dir_start;
 reg [31:0] boot_sector,volume_limit;
 integer timer;
 wire boot_valid,boot_busy,boot_done,boot_error;
 wire [31:0] fat_base,root_base,root_cl,data_base,clusters,volume_sectors;
 wire [7:0] spc;
 wire dir_req,dir_done,dir_busy,dir_error,dir_found;
 wire [31:0] dir_lba;
 wire dir_active=(state==DIR_START || state==DIR_WAIT);
 assign volume_root_lba=root_base;assign volume_root_cluster=root_cl;
 assign volume_fat_lba=fat_base;
 assign volume_data_lba=data_base;
 assign volume_cluster_count=clusters;
 assign volume_sectors_per_cluster=spc;
 assign rd_start=dir_active?dir_req:boot_req;
 assign rd_lba=dir_active?dir_lba:boot_sector;
 assign found_valid=dir_active && dir_found;
 fat32_boot_parser #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) u_boot(
  .clk(clk),.rst_n(rst_n),.start(boot_start),.partition_lba(boot_sector),
  .byte_addr(rd_addr),.byte_in(rd_data),.byte_valid(rd_valid && state==BOOT_WAIT),
  .fat_lba(fat_base),.root_lba(root_base),.root_cluster(root_cl),.sectors_per_cluster(spc),
  .valid(boot_valid),.busy(boot_busy),.done(boot_done),.error(boot_error),.data_lba(data_base),.cluster_count(clusters),.volume_sectors(volume_sectors));
 fat32_dir_scan #(.MAX_FILES(MAX_FILES),.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.EXTENSION(EXTENSION),.FIND_WAV(FIND_WAV)) u_directory(
  .clk(clk),.rst_n(rst_n),.start(dir_start),.root_lba(root_base),.sectors_per_cluster(spc),
  .fat_lba(fat_base),.data_lba(data_base),.root_cluster(root_cl),.cluster_count(clusters),
  .rd_ready(rd_ready && dir_active),.rd_done(rd_done && dir_active),.rd_error(rd_error),
  .rd_start(dir_req),.rd_lba(dir_lba),.rd_addr(rd_addr),.rd_data(rd_data),.rd_valid(rd_valid && dir_active),
  .found_valid(dir_found),.found_index(found_index),.found_first_cluster(found_first_cluster),.found_size(found_size),
  .busy(dir_busy),.done(dir_done),.error(dir_error),.found_count(found_count),
  .wav_found(wav_found),.wav_first_cluster(wav_first_cluster),.wav_size(wav_size));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin state<=IDLE;boot_start<=0;boot_req<=0;dir_start<=0;boot_sector<=0;volume_limit<=0;timer<=0;busy<=0;done<=0;error<=0;end
  else begin
   boot_start<=0;boot_req<=0;dir_start<=0;done<=0;
   if(state!=IDLE && !dir_active && timer>=TIMEOUT_CYCLES-1) begin state<=IDLE;busy<=0;done<=1;error<=1;end
   else begin
    if(state!=IDLE) timer<=timer+1;
    case(state)
     IDLE:if(start) begin boot_sector<=partition_lba;volume_limit<=partition_sectors;busy<=1;error<=0;timer<=0;state<=BOOT_START;end
     BOOT_START:begin boot_start<=1;state<=BOOT_REQUEST;end
     BOOT_REQUEST:if(rd_ready && boot_busy) begin boot_req<=1;state<=BOOT_WAIT;end
     BOOT_WAIT:if(rd_done) begin
      if(rd_error) begin error<=1;busy<=0;done<=1;state<=IDLE;end
      else state<=BOOT_CHECK;
     end
     BOOT_CHECK:if(boot_valid && !boot_busy && !boot_error && (volume_limit==0 || volume_sectors<=volume_limit)) state<=DIR_START;
                else begin error<=1;busy<=0;done<=1;state<=IDLE;end
     DIR_START:begin dir_start<=1;state<=DIR_WAIT;end
     DIR_WAIT:if(dir_done) begin error<=dir_error;busy<=0;done<=1;state<=IDLE;end
     default:begin error<=1;busy<=0;done<=1;state<=IDLE;end
    endcase
   end
  end
 end
endmodule
