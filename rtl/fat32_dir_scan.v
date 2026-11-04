// Root directory cluster-chain scanner; up to MAX_FILES short-name results.
// Sectors arrive before rd_done; buffer then parse only after successful CRC/status.
// Results are provisional until done && !error. Errors invalidate this scan's results.
module fat32_dir_scan #(parameter integer MAX_FILES=4,TIMEOUT_CYCLES=50_000_000,
 parameter integer MAX_DIR_CLUSTERS=64,
 parameter [23:0] EXTENSION=24'h424d50, parameter FIND_WAV=0,
 parameter integer INDEX_BITS=(MAX_FILES>1)?$clog2(MAX_FILES):1,
 parameter integer COUNT_BITS=(MAX_FILES>0)?$clog2(MAX_FILES+1):1,parameter MAX_WAVS=1,TOPIC_FOLDERS=0)(
 input wire clk,rst_n,start,input wire [31:0] root_lba,
 input wire [7:0] sectors_per_cluster,
 input wire [31:0] fat_lba,data_lba,root_cluster,cluster_count,
 input wire rd_ready,rd_done,rd_error,output reg rd_start,output // Cache the exclusive cluster bound once; preserve 32-bit wrap semantics.
 reg [31:0] rd_lba,
 input wire [8:0] rd_addr,input wire [7:0] rd_data,input wire rd_valid,
 output reg found_valid,output reg [INDEX_BITS-1:0] found_index,
 output reg [31:0] found_first_cluster,found_size,
 output reg busy,done,error,output reg [COUNT_BITS-1:0] found_count,
 output reg wav_found,output wire [31:0] wav_first_cluster,wav_size,
 input wire [1:0] wav_index,output reg [2:0] wav_count,output wire [24:0] folder_info);
 localparam IDLE=0,REQUEST=1,RECEIVE=2,CHECK=3,FETCH=4,PARSE=5,AFTER_SECTOR=6,FAT_NEXT=7,
  TOPIC_SELECT=8,TOPIC_START=9,DIR_ADDRESS=10,DIR_VALIDATE=11;
 reg [3:0] state;
 reg [7:0] sector_mem[0:511];
 reg [7:0] entry_byte,name0,attr,ext0,ext1,ext2,spc,sector_index;
 reg [31:0] entry_cluster,entry_size,fat_base,data_base,current_cluster,data_cluster_end;
 reg entry_cluster_in_bounds;
 reg [31:0] fat_entry;
 reg [9:0] received;
 reg [8:0] pos;
 reg read_fat,bad_order;
 localparam integer TIMER_BITS=(TIMEOUT_CYCLES>1)?$clog2(TIMEOUT_CYCLES):1;
 localparam integer HOP_BITS=(MAX_DIR_CLUSTERS>0)?$clog2(MAX_DIR_CLUSTERS+1):1;
 reg [TIMER_BITS-1:0] timer;
 reg [HOP_BITS-1:0] hops;
 wire timeout_now=(state!=IDLE && timer>=TIMEOUT_CYCLES-1);
 reg folder_mode,folder_name_good;
 reg [1:0] folder_tag;
 reg [3:0] folders_seen;
 reg [2:0] topic_index;
 reg [COUNT_BITS-1:0] topic_limit;
 reg [23:0] topic_ends;
 reg [2:0] cluster_shift;
 reg [34:0] directory_offset;
 reg [27:0] directory_anchor;
 reg [HOP_BITS-1:0] directory_power,directory_span;
 wire [HOP_BITS-1:0] directory_span_next=directory_span+1'b1;
 wire [35:0] directory_start={4'd0,data_base}+{1'b0,directory_offset};
 wire [35:0] directory_end=directory_start+{28'd0,spc};
 wire topic_entry=TOPIC_FOLDERS&&!folder_mode&&folder_name_good&&name0!=8'he5&&attr[4]&&!attr[3];
 wire topic_store=rst_n&&!timeout_now&&state==PARSE&&!read_fat&&pos[4:0]==31&&
  topic_entry&&!folders_seen[folder_tag]&&entry_cluster_in_bounds&&entry_cluster!=root_cluster;
 wire [27:0] selected_topic_cluster;
 generate if(TOPIC_FOLDERS)begin:topic_metadata
  // Only four directory pointers; the validity mask authorizes every read.
  // Share the existing sector buffer and parser; no recursive directory stack.
  (* ram_style="bram" *) reg [27:0] clusters[0:3];
  reg [27:0] selected;
  always @(posedge clk)begin
   if(topic_store)clusters[folder_tag]<=entry_cluster[27:0];
   if(rst_n&&state==TOPIC_SELECT&&topic_index<4&&folders_seen[topic_index[1:0]])
    selected<=clusters[topic_index[1:0]];
  end
  assign selected_topic_cluster=selected;
 end else begin:no_topic_metadata
  assign selected_topic_cluster=0;
 end endgenerate
 assign folder_info=TOPIC_FOLDERS?{folder_mode&&!error,topic_ends}:25'd0;
 wire buffer_write=rst_n && !timeout_now && state==RECEIVE && rd_valid &&
  received<512 && {1'b0,rd_addr}==received;
 // RAM data is not reset. CHECK validates a complete, successful sector
 // before FETCH/PARSE can consume it; keep the original one-clock read.
 always @(posedge clk) begin
  if(buffer_write) sector_mem[rd_addr]<=rd_data;
  if(rst_n && !timeout_now && state==FETCH) entry_byte<=sector_mem[pos];
 end
 wire [27:0] next_cluster=fat_entry[27:0];
 wire [23:0] upper_ext={ext0&8'hdf,ext1&8'hdf,ext2&8'hdf};
 wire is_wav=FIND_WAV && !folder_mode && upper_ext==24'h574156 && name0!=0 &&
  name0!=8'he5 && !attr[3] && !attr[4];
 wire is_target=name0!=0 && name0!=8'he5 && !attr[3] && !attr[4] &&
  upper_ext==EXTENSION;
 reg [63:0] first_wav_metadata;
 wire wav_accept=!timeout_now && state==PARSE && !read_fat && pos[4:0]==31 &&
  is_wav && wav_count<MAX_WAVS && entry_cluster_in_bounds &&
  {entry_byte,entry_size[23:0]}!=0;
 generate if(MAX_WAVS==1)begin:single_wav
  assign {wav_first_cluster,wav_size}=first_wav_metadata;
 end else begin:music_catalog
  // No reset on metadata RAM. The complete successful scan and bounded count
  // authorize reads; a switch changes wav_index only after the old reader/FIFO retire.
  (* ram_style="bram" *) reg [63:0] files[0:MAX_WAVS-1];
  reg [63:0] selected;
  always @(posedge clk)begin
   if(rst_n && wav_accept)files[wav_count[1:0]]<={entry_cluster,entry_byte,entry_size[23:0]};
   if(rst_n && state==IDLE && !start && !error && wav_found && {1'b0,wav_index}<wav_count)
    selected<=files[wav_index];
  end
  assign {wav_first_cluster,wav_size}=selected;
 end endgenerate
 function [2:0] spc_log2;
  input [7:0] value;
  begin case(value)
   2:spc_log2=1;4:spc_log2=2;8:spc_log2=3;16:spc_log2=4;
   32:spc_log2=5;64:spc_log2=6;128:spc_log2=7;default:spc_log2=0;
  endcase end
 endfunction
 task finish_directory;
  input [COUNT_BITS-1:0] count_value;
  begin
   found_count<=count_value;
   if(TOPIC_FOLDERS&&!folder_mode&&folders_seen!=0)begin
    // Root results were provisional. Topic metadata now replaces them before
    // catalog_ready can authorize any file read; root WAV entries are retained.
    folder_mode<=1;found_count<=0;topic_index<=0;state<=TOPIC_SELECT;timer<=0;
   end else if(TOPIC_FOLDERS&&folder_mode)begin
    case(topic_index)
     0:topic_ends[5:0]<=count_value;1:topic_ends[11:6]<=count_value;
     2:topic_ends[17:12]<=count_value;3:topic_ends[23:18]<=count_value;
    endcase
    topic_index<=topic_index+1'b1;state<=TOPIC_SELECT;timer<=0;
   end else begin busy<=0;done<=1;state<=IDLE;end
  end
 endtask
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;rd_start<=0;rd_lba<=0;found_valid<=0;found_index<=0;
   found_first_cluster<=0;found_size<=0;found_count<=0;wav_found<=0;first_wav_metadata<=0;wav_count<=0;busy<=0;done<=0;error<=0;
   name0<=0;attr<=0;ext0<=0;ext1<=0;ext2<=0;spc<=0;sector_index<=0;
   entry_cluster<=0;entry_cluster_in_bounds<=0;entry_size<=0;fat_base<=0;data_base<=0;current_cluster<=0;data_cluster_end<=0;
   fat_entry<=0;received<=0;pos<=0;read_fat<=0;bad_order<=0;timer<=0;hops<=0;
   folder_mode<=0;folder_name_good<=0;folder_tag<=0;folders_seen<=0;
   topic_index<=0;topic_limit<=0;topic_ends<=0;cluster_shift<=0;directory_offset<=0;
   directory_anchor<=0;directory_power<=1;directory_span<=0;
  end else begin
   rd_start<=0;found_valid<=0;done<=0;
   if(timeout_now) begin state<=IDLE;busy<=0;done<=1;error<=1;end
   else begin
    if(state!=IDLE) timer<=timer+1;
    case(state)
     IDLE:if(start) begin
      found_count<=0;wav_found<=0;wav_count<=0;error<=0;timer<=0;sector_index<=0;read_fat<=0;hops<=1;
      folder_mode<=0;folders_seen<=0;topic_index<=0;topic_limit<=0;topic_ends<=0;
      if(MAX_FILES<1 || MAX_FILES>32 || (TOPIC_FOLDERS&&MAX_FILES!=24) || MAX_WAVS<1 || MAX_WAVS>4 || sectors_per_cluster==0 || (sectors_per_cluster&(sectors_per_cluster-1'b1))!=0 || root_cluster<2 || root_cluster>=cluster_count+2) begin error<=1;done<=1;end
      else begin
       busy<=1;rd_lba<=root_lba;fat_base<=fat_lba;data_base<=data_lba;spc<=sectors_per_cluster;
       current_cluster<=root_cluster;data_cluster_end<=cluster_count+32'd2;state<=REQUEST;
       cluster_shift<=spc_log2(sectors_per_cluster);
       directory_anchor<=root_cluster[27:0];directory_power<=1;directory_span<=0;
      end
     end
     REQUEST:if(rd_ready) begin rd_start<=1;received<=0;bad_order<=0;state<=RECEIVE;end
     RECEIVE:begin
      if(rd_valid) begin
       if(received>=512 || {1'b0,rd_addr}!=received) bad_order<=1;
       else received<=received+1'b1;
      end
      if(rd_done) begin
       if(rd_error) begin error<=1;busy<=0;done<=1;state<=IDLE;end
       else state<=CHECK;
      end
     end
     CHECK:begin
      timer<=0;
      if(received!=512 || bad_order) begin error<=1;busy<=0;done<=1;state<=IDLE;end
      else begin pos<=read_fat?{current_cluster[6:0],2'b00}:9'd0;state<=FETCH;end
     end
     FETCH:begin
      // Cluster bytes finish at PARSE offset 27. Validate at FETCH 28, well
      // before offset 31 consumes it, breaking the long accept/finish path.
      // Keep the original 32-bit bound arithmetic, timeout and CRC fences.
      if(!read_fat&&pos[4:0]==28)
       entry_cluster_in_bounds<=entry_cluster>=2&&entry_cluster<data_cluster_end;
      state<=PARSE;
     end
     PARSE:begin
      if(read_fat) begin
       case(pos[1:0])
        0:fat_entry[7:0]<=entry_byte;1:fat_entry[15:8]<=entry_byte;
        2:fat_entry[23:16]<=entry_byte;3:fat_entry[31:24]<=entry_byte;
       endcase
       if(pos[1:0]==3) state<=FAT_NEXT;
       else begin pos<=pos+1'b1;state<=FETCH;end
      end else begin
       pos<=pos+1'b1;state<=FETCH;
       case(pos[4:0])
        0:begin name0<=entry_byte;entry_cluster<=0;entry_cluster_in_bounds<=0;entry_size<=0;
          folder_name_good<=(entry_byte&8'hdf)==8'h54;
          if(entry_byte==0)finish_directory(found_count);end
        1:folder_name_good<=folder_name_good&&((entry_byte&8'hdf)==8'h4f);
        2:folder_name_good<=folder_name_good&&((entry_byte&8'hdf)==8'h50);
        3:folder_name_good<=folder_name_good&&((entry_byte&8'hdf)==8'h49);
        4:folder_name_good<=folder_name_good&&((entry_byte&8'hdf)==8'h43);
        5:begin folder_name_good<=folder_name_good&&entry_byte>=8'h31&&entry_byte<=8'h34;folder_tag<=entry_byte-8'h31;end
        6,7:folder_name_good<=folder_name_good&&entry_byte==8'h20;
        8:begin ext0<=entry_byte;folder_name_good<=folder_name_good&&entry_byte==8'h20;end
        9:begin ext1<=entry_byte;folder_name_good<=folder_name_good&&entry_byte==8'h20;end
        10:begin ext2<=entry_byte;folder_name_good<=folder_name_good&&entry_byte==8'h20;end
        11:attr<=entry_byte;
        20:entry_cluster[23:16]<=entry_byte;21:entry_cluster[31:24]<={4'b0,entry_byte[3:0]};
        26:entry_cluster[7:0]<=entry_byte;27:entry_cluster[15:8]<=entry_byte;
        28:entry_size[7:0]<=entry_byte;29:entry_size[15:8]<=entry_byte;30:entry_size[23:16]<=entry_byte;
        31:begin
         if(pos==511) state<=AFTER_SECTOR;
         if(topic_entry)begin
          if(folders_seen[folder_tag]||!entry_cluster_in_bounds||entry_cluster==root_cluster)begin
           error<=1;busy<=0;done<=1;state<=IDLE;
          end else folders_seen[folder_tag]<=1;
         end
         if(wav_accept)begin
          wav_found<=1;wav_count<=wav_count+1'b1;
          if(!wav_found)first_wav_metadata<={entry_cluster,entry_byte,entry_size[23:0]};
          if(!TOPIC_FOLDERS&&found_count>=MAX_FILES && wav_count==MAX_WAVS-1)begin busy<=0;done<=1;state<=IDLE;end
         end
         if(is_target && found_count<MAX_FILES && entry_cluster_in_bounds && {entry_byte,entry_size[23:0]}!=0) begin
          found_valid<=1;found_index<=found_count[INDEX_BITS-1:0];found_first_cluster<=entry_cluster;
          found_size<={entry_byte,entry_size[23:0]};found_count<=found_count+1'b1;
          if(TOPIC_FOLDERS&&folder_mode&&found_count+1'b1==topic_limit)
           finish_directory(found_count+1'b1);
          else if(!TOPIC_FOLDERS&&found_count==MAX_FILES-1 && (!FIND_WAV || wav_count>=MAX_WAVS))begin
           busy<=0;done<=1;state<=IDLE;end
         end
        end
       endcase
      end
     end
     AFTER_SECTOR:begin
      if(sector_index==spc-1'b1) begin rd_lba<=fat_base+(current_cluster>>7);read_fat<=1;end
      else begin sector_index<=sector_index+1'b1;rd_lba<=rd_lba+1'b1;end
      state<=REQUEST;
     end
     FAT_NEXT:begin
      if(next_cluster>=28'hffffff8)finish_directory(found_count);
      else if(next_cluster<2 || next_cluster>=28'hffffff0 || next_cluster>=data_cluster_end ||
              next_cluster==current_cluster || hops>=MAX_DIR_CLUSTERS ||
              (TOPIC_FOLDERS&&next_cluster==directory_anchor)) begin error<=1;busy<=0;done<=1;state<=IDLE;end
      else begin
       hops<=hops+1;current_cluster<={4'b0,next_cluster};sector_index<=0;read_fat<=0;
       if(TOPIC_FOLDERS)begin
        if(directory_span_next==directory_power)begin
         directory_anchor<=next_cluster;directory_power<=directory_power<<1;directory_span<=0;
        end else directory_span<=directory_span_next;
        state<=DIR_ADDRESS;
       end
       else begin rd_lba<=data_base+(({4'b0,next_cluster}-2)<<spc_log2(spc));state<=REQUEST;end
      end
     end
     TOPIC_SELECT:begin
      timer<=0;
      if(topic_index==4)begin busy<=0;done<=1;state<=IDLE;end
      else if(folders_seen[topic_index[1:0]])state<=TOPIC_START;
      else finish_directory(found_count);
     end
     TOPIC_START:begin
      current_cluster<={4'd0,selected_topic_cluster};sector_index<=0;read_fat<=0;hops<=1;
      directory_anchor<=selected_topic_cluster;directory_power<=1;directory_span<=0;
      topic_limit<=found_count+6;state<=DIR_ADDRESS;
     end
     DIR_ADDRESS:begin
      directory_offset<=({7'd0,current_cluster[27:0]}-35'd2)<<cluster_shift;
      state<=DIR_VALIDATE;
     end
     DIR_VALIDATE:begin
      if(current_cluster<2||current_cluster>=28'hffffff0||current_cluster>=data_cluster_end||directory_end>36'h100000000)begin
       error<=1;busy<=0;done<=1;state<=IDLE;
      end else begin rd_lba<=directory_start[31:0];state<=REQUEST;timer<=0;end
     end
     default:begin error<=1;busy<=0;done<=1;state<=IDLE;end
    endcase
   end
  end
 end
endmodule
