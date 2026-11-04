// Root directory cluster-chain scanner; 1..4 short-name BMP results.
// Sectors arrive before rd_done; buffer then parse only after successful CRC/status.
// Results are provisional until done && !error. Errors invalidate this scan's results.
module fat32_dir_scan #(parameter integer MAX_FILES=4,TIMEOUT_CYCLES=50_000_000,
 parameter integer MAX_DIR_CLUSTERS=64,
 parameter [23:0] EXTENSION=24'h424d50, parameter FIND_WAV=0)(
 input wire clk,rst_n,start,input wire [31:0] root_lba,
 input wire [7:0] sectors_per_cluster,
 input wire [31:0] fat_lba,data_lba,root_cluster,cluster_count,
 input wire rd_ready,rd_done,rd_error,output reg rd_start,output reg [31:0] rd_lba,
 input wire [8:0] rd_addr,input wire [7:0] rd_data,input wire rd_valid,
 output reg found_valid,output reg [1:0] found_index,
 output reg [31:0] found_first_cluster,found_size,
 output reg busy,done,error,output reg [2:0] found_count,
 output reg wav_found,output reg [31:0] wav_first_cluster,wav_size);
 localparam IDLE=0,REQUEST=1,RECEIVE=2,CHECK=3,FETCH=4,PARSE=5,AFTER_SECTOR=6,FAT_NEXT=7;
 reg [3:0] state;
 reg [7:0] sector_mem[0:511];
 reg [7:0] entry_byte,name0,attr,ext0,ext1,ext2,spc,sector_index;
 reg [31:0] entry_cluster,entry_size,fat_base,data_base,current_cluster,max_clusters;
 reg [31:0] fat_entry;
 reg [9:0] received;
 reg [8:0] pos;
 reg read_fat,bad_order;
 integer timer,hops;
 wire timeout_now=(state!=IDLE && timer>=TIMEOUT_CYCLES-1);
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
 wire is_wav=FIND_WAV && upper_ext==24'h574156 && name0!=0 &&
  name0!=8'he5 && !attr[3] && !attr[4];
 wire is_target=name0!=0 && name0!=8'he5 && !attr[3] && !attr[4] &&
  upper_ext==EXTENSION;
 function [2:0] spc_log2;
  input [7:0] value;
  begin case(value)
   2:spc_log2=1;4:spc_log2=2;8:spc_log2=3;16:spc_log2=4;
   32:spc_log2=5;64:spc_log2=6;128:spc_log2=7;default:spc_log2=0;
  endcase end
 endfunction
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;rd_start<=0;rd_lba<=0;found_valid<=0;found_index<=0;
   found_first_cluster<=0;found_size<=0;found_count<=0;wav_found<=0;wav_first_cluster<=0;wav_size<=0;busy<=0;done<=0;error<=0;
   name0<=0;attr<=0;ext0<=0;ext1<=0;ext2<=0;spc<=0;sector_index<=0;
   entry_cluster<=0;entry_size<=0;fat_base<=0;data_base<=0;current_cluster<=0;max_clusters<=0;
   fat_entry<=0;received<=0;pos<=0;read_fat<=0;bad_order<=0;timer<=0;hops<=0;
  end else begin
   rd_start<=0;found_valid<=0;done<=0;
   if(timeout_now) begin state<=IDLE;busy<=0;done<=1;error<=1;end
   else begin
    if(state!=IDLE) timer<=timer+1;
    case(state)
     IDLE:if(start) begin
      found_count<=0;wav_found<=0;error<=0;timer<=0;sector_index<=0;read_fat<=0;hops<=1;
      if(MAX_FILES<1 || MAX_FILES>4 || sectors_per_cluster==0 || (sectors_per_cluster&(sectors_per_cluster-1'b1))!=0 || root_cluster<2 || root_cluster>=cluster_count+2) begin error<=1;done<=1;end
      else begin
       busy<=1;rd_lba<=root_lba;fat_base<=fat_lba;data_base<=data_lba;spc<=sectors_per_cluster;
       current_cluster<=root_cluster;max_clusters<=cluster_count;state<=REQUEST;
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
     FETCH:state<=PARSE;
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
        0:begin name0<=entry_byte;entry_cluster<=0;entry_size<=0;
          if(entry_byte==0) begin busy<=0;done<=1;state<=IDLE;end end
        8:ext0<=entry_byte;9:ext1<=entry_byte;10:ext2<=entry_byte;11:attr<=entry_byte;
        20:entry_cluster[23:16]<=entry_byte;21:entry_cluster[31:24]<={4'b0,entry_byte[3:0]};
        26:entry_cluster[7:0]<=entry_byte;27:entry_cluster[15:8]<=entry_byte;
        28:entry_size[7:0]<=entry_byte;29:entry_size[15:8]<=entry_byte;30:entry_size[23:16]<=entry_byte;
        31:begin
         if(pos==511) state<=AFTER_SECTOR;
         if(is_wav && !wav_found && entry_cluster>=2 &&
            entry_cluster<max_clusters+2 && {entry_byte,entry_size[23:0]}!=0)begin
          wav_found<=1;wav_first_cluster<=entry_cluster;
          wav_size<={entry_byte,entry_size[23:0]};
          if(found_count>=MAX_FILES)begin busy<=0;done<=1;state<=IDLE;end
         end
         if(is_target && found_count<MAX_FILES && entry_cluster>=2 && entry_cluster<max_clusters+2 && {entry_byte,entry_size[23:0]}!=0) begin
          found_valid<=1;found_index<=found_count[1:0];found_first_cluster<=entry_cluster;
          found_size<={entry_byte,entry_size[23:0]};found_count<=found_count+1'b1;
          if(found_count==MAX_FILES-1 && (!FIND_WAV || wav_found)) begin
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
      if(next_cluster>=28'hffffff8) begin busy<=0;done<=1;state<=IDLE;end
      else if(next_cluster<2 || next_cluster>=28'hffffff0 || next_cluster>=max_clusters+2 ||
              next_cluster==current_cluster || hops>=MAX_DIR_CLUSTERS) begin error<=1;busy<=0;done<=1;state<=IDLE;end
      else begin
       hops<=hops+1;current_cluster<={4'b0,next_cluster};sector_index<=0;read_fat<=0;
       rd_lba<=data_base+(({4'b0,next_cluster}-2)<<spc_log2(spc));state<=REQUEST;
      end
     end
     default:begin error<=1;busy<=0;done<=1;state<=IDLE;end
    endcase
   end
  end
 end
endmodule
