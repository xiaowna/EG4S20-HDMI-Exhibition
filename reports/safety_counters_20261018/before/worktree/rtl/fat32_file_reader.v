// Read a FAT32 file by first cluster and byte size. No contiguous-file assumption.
// One 512-byte buffer: bytes are exposed only after sector CRC/status passes.
// out_valid/out_ready handshake; offset/data stay stable during backpressure.
// Earlier bytes remain provisional if a later sector fails; commit on done&&!error.
module fat32_file_reader #(parameter integer TIMEOUT_CYCLES=50_000_000,
 parameter integer MAX_FILE_CLUSTERS=0,
 parameter integer MAX_SECTOR_RETRIES=2)(
 input wire clk,rst_n,start,stop,input wire [31:0] first_cluster,file_size,
 input wire [31:0] fat_lba,data_lba,cluster_count,input wire [7:0] sectors_per_cluster,
 input wire rd_ready,rd_done,rd_error,input wire [8:0] rd_addr,input wire [7:0] rd_data,input wire rd_valid,
 output reg rd_start,output reg [31:0] rd_lba,
 input wire out_ready,output wire out_valid,output reg [7:0] out_data,output reg [31:0] out_offset,
 output reg busy,done,error,output reg [3:0] error_code);
 localparam IDLE=0,REQUEST=1,RECEIVE=2,CHECK=3,FETCH=4,SEND=5,ADVANCE=6,FAT_APPLY=7,FAT_NEXT=8,START_CHECK=9;
 // error_code: 1 metadata, 2 transport/CRC, 3 byte order/length,
 // 4 premature EOC, 5 invalid/cyclic cluster chain or hop limit, 6 timeout.
 reg [3:0] state;
 reg [7:0] buffer_mem[0:511];
 reg [31:0] fat_base,data_base,max_clusters,current_cluster,size_latched,fat_entry;
 // FAT 文件长度最多 2^32-1 字节；512 字节/簇时最多需要 2^23 个簇。
 reg [23:0] cluster_limit;
 reg [24:0] hops;
 reg [39:0] first_sector_end;
 reg [7:0] spc,sector_index;
 localparam RETRY_BITS=(MAX_SECTOR_RETRIES<2)?1:$clog2(MAX_SECTOR_RETRIES+1);
 reg [RETRY_BITS-1:0] sector_retries;
 reg [8:0] pos;
 reg [9:0] received;
 reg is_fat,bad_order;
 // Brent 检测只保存锚点及计数，不维护随文件增长的已访问簇表。
 reg [27:0] start_cluster,chain_anchor;
 // 最多探查 3N 步，25 位可容纳；前缀中的比较位置只需 24 位。
 // 完整读取结束后复用 hops 作为探查位置；重放阶段复用
 // chain_power 为比较位置、chain_anchor 为比较簇，减少独立计数器和多路器。
 reg [24:0] chain_power,chain_span;
 reg validating,probe_replay;
 wire [24:0] probe_next_step=hops+1'b1;
 wire [24:0] detected_cycle_length=chain_span+1'b1;
 integer timer;
 wire [27:0] next_cluster=fat_entry[27:0];
 function [2:0] spc_log2;
  input [7:0] value;
  begin case(value)
   2:spc_log2=1;4:spc_log2=2;8:spc_log2=3;16:spc_log2=4;
   32:spc_log2=5;64:spc_log2=6;128:spc_log2=7;default:spc_log2=0;
  endcase end
 endfunction
 // 28 位簇号最多左移 7 位；用 36 位保留 LBA 加法进位，避免重复 64 位移位器。
 wire [34:0] next_data_offset=({7'b0,next_cluster}-35'd2)<<spc_log2(spc);
 wire [35:0] next_sector_start={4'b0,data_base}+{1'b0,next_data_offset};
 wire [35:0] next_sector_end=next_sector_start+spc;
 wire next_invalid=(next_cluster<2 || next_cluster>=28'hffffff0 ||
                    next_cluster>=max_clusters+2 || next_sector_end>36'h100000000);
 // 使用者取完所需数据后可提前结束；仅在没有扇区事务进行时响应。
 wire stop_ready=(state==FETCH || state==SEND || state==ADVANCE);
 assign out_valid=(state==SEND)&&!stop;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;rd_start<=0;rd_lba<=0;out_data<=0;out_offset<=0;busy<=0;done<=0;error<=0;error_code<=0;
   fat_base<=0;data_base<=0;max_clusters<=0;current_cluster<=0;size_latched<=0;fat_entry<=0;cluster_limit<=0;first_sector_end<=0;
   spc<=0;sector_index<=0;sector_retries<=0;pos<=0;received<=0;is_fat<=0;bad_order<=0;timer<=0;hops<=0;
   start_cluster<=0;chain_anchor<=0;
   chain_power<=1;chain_span<=0;
   validating<=0;probe_replay<=0;
  end else begin
   rd_start<=0;done<=0;
   // Sink backpressure is allowed indefinitely; timeout applies to sector requests.
   if(stop_ready && stop) begin
    state<=IDLE;busy<=0;done<=1;error<=0;error_code<=0;
   end else if((state==REQUEST || state==RECEIVE) && timer>=TIMEOUT_CYCLES-1) begin
    state<=IDLE;busy<=0;done<=1;error<=1;error_code<=6;
   end else begin
    if(state==REQUEST || state==RECEIVE) timer<=timer+1;
    case(state)
     IDLE:if(start) begin
      error<=0;error_code<=0;out_offset<=0;sector_index<=0;sector_retries<=0;is_fat<=0;timer<=0;hops<=1;
      start_cluster<=first_cluster[27:0];chain_anchor<=first_cluster[27:0];
      chain_power<=1;chain_span<=0;validating<=0;probe_replay<=0;
      if(file_size==0) done<=1;
      else begin
       busy<=1;current_cluster<=first_cluster;size_latched<=file_size;fat_base<=fat_lba;
       cluster_limit<=((file_size-1'b1)>>(9+spc_log2(sectors_per_cluster)))+1'b1;
       data_base<=data_lba;max_clusters<=cluster_count;spc<=sectors_per_cluster;
       first_sector_end<={8'b0,data_lba}+(({8'b0,first_cluster}-40'd2)<<spc_log2(sectors_per_cluster))+sectors_per_cluster;
       state<=START_CHECK;
      end
     end
     START_CHECK:begin
      if(current_cluster<2 || current_cluster>=28'hffffff0 || current_cluster>=max_clusters+2 ||
         spc==0 || (spc&(spc-1'b1))!=0 || first_sector_end>40'h100000000) begin
       busy<=0;error<=1;error_code<=1;done<=1;state<=IDLE;
      end else begin
       rd_lba<=data_base+((current_cluster-2)<<spc_log2(spc));state<=REQUEST;
      end
     end
     REQUEST:if(rd_ready) begin rd_start<=1;received<=0;bad_order<=0;state<=RECEIVE;end
     RECEIVE:begin
      if(rd_valid) begin
       if(received>=512 || {1'b0,rd_addr}!=received) bad_order<=1;
       else begin buffer_mem[rd_addr]<=rd_data;received<=received+1'b1;end
      end
      if(rd_done) begin
       if(rd_error) begin
        // 扇区事务结束后才重试；重新请求会清空接收计数，失败数据不会输出。
        if(sector_retries<MAX_SECTOR_RETRIES) begin
         sector_retries<=sector_retries+1'b1;timer<=0;state<=REQUEST;
        end else begin busy<=0;done<=1;error<=1;error_code<=2;state<=IDLE;end
       end else begin sector_retries<=0;state<=CHECK;end
      end
     end
     CHECK:begin
      if(received!=512 || bad_order) begin busy<=0;done<=1;error<=1;error_code<=3;state<=IDLE;end
      else begin pos<=is_fat?{current_cluster[6:0],2'b00}:9'd0;state<=FETCH;end
     end
     FETCH:begin out_data<=buffer_mem[pos];state<=is_fat?FAT_APPLY:SEND;end
     SEND:if(out_ready) begin
      if(out_offset==size_latched-1'b1) begin
       if(hops==1)begin busy<=0;done<=1;state<=IDLE;end
       else begin
        // 最后一个字节已交付，但 done 尚不能提交成功。
        // 流式 Brent 可能在有限文件结束前尚未相遇；重走 FAT 前缀做精确检查。
        // 使用原扇区接收器，因此 CRC、重试、超时与普通读取相同。
        validating<=1;probe_replay<=0;hops<=0;
        chain_anchor<=start_cluster;chain_power<=1;chain_span<=0;
        current_cluster<={4'b0,start_cluster};is_fat<=1;timer<=0;
        rd_lba<=fat_base+({4'b0,start_cluster}>>7);state<=REQUEST;
       end
      end
      else begin
       out_offset<=out_offset+1'b1;
       if(pos==511) state<=ADVANCE;
       else begin pos<=pos+1'b1;state<=FETCH;end
      end
     end
     ADVANCE:begin
      timer<=0;
      if(sector_index==spc-1'b1) begin rd_lba<=fat_base+(current_cluster>>7);is_fat<=1;end
      else begin sector_index<=sector_index+1'b1;rd_lba<=rd_lba+1'b1;end
      state<=REQUEST;
     end
     FAT_APPLY:begin
      case(pos[1:0])
       0:fat_entry[7:0]<=out_data;1:fat_entry[15:8]<=out_data;
       2:fat_entry[23:16]<=out_data;3:fat_entry[31:24]<=out_data;
      endcase
      if(pos[1:0]==3) state<=FAT_NEXT;
      else begin pos<=pos+1'b1;state<=FETCH;end
     end
     FAT_NEXT:begin
      // 两种读取阶段共用相同的 Brent 更新；错误退出时锚点值不再使用。
      if(!probe_replay && next_cluster!=chain_anchor)begin
       if(detected_cycle_length==chain_power)begin
        chain_anchor<=next_cluster;chain_power<=chain_power<<1;chain_span<=0;
       end else chain_span<=detected_cycle_length;
      end
      if(validating)begin
       // 无环链遇到结束标记即停止。文件所需前缀之外的无效链接不拒绝文件。
       if(next_invalid)begin
        busy<=0;done<=1;state<=IDLE;validating<=0;
        if(probe_next_step<cluster_limit)begin
         error<=1;error_code<=(next_cluster>=28'hffffff8)?4:5;
        end
       end else if(probe_replay)begin
        // 已知周期 lambda。检查 x[N-1-lambda] 与 x[N-1] 是否相同：
        // 相同当且仅当文件所需的 N 个簇中已经重复使用某个簇。
        if(probe_next_step==chain_power)chain_anchor<=next_cluster;
        if(probe_next_step==cluster_limit-1'b1)begin
         busy<=0;done<=1;state<=IDLE;validating<=0;
         if(next_cluster==chain_anchor)begin error<=1;error_code<=5;end
        end else begin
         hops<=probe_next_step;current_cluster<={4'b0,next_cluster};timer<=0;
         rd_lba<=fat_base+({4'b0,next_cluster}>>7);state<=REQUEST;
        end
       end else if(next_cluster==chain_anchor)begin
        if(detected_cycle_length>=cluster_limit)begin
         busy<=0;done<=1;state<=IDLE;validating<=0;
        end else begin
         // 发现周期不等于文件前缀必有环；重新定位有限前缀，避免误报尾部环。
         chain_power<=cluster_limit-detected_cycle_length-1'b1;
         chain_anchor<=start_cluster;hops<=0;probe_replay<=1;
         current_cluster<={4'b0,start_cluster};timer<=0;
         rd_lba<=fat_base+({4'b0,start_cluster}>>7);state<=REQUEST;
        end
       end else if(chain_power>=cluster_limit && detected_cycle_length>=cluster_limit)begin
        // 锚点位置为 power-1，已越过可能位于前 N 簇内的环入口。
        // 连续 N 次比较仍未相遇，说明前缀无环；总步数仍小于 3N。
        busy<=0;done<=1;state<=IDLE;validating<=0;
       end else begin
        hops<=probe_next_step;current_cluster<={4'b0,next_cluster};timer<=0;
        rd_lba<=fat_base+({4'b0,next_cluster}>>7);state<=REQUEST;
       end
      end else if(next_cluster>=28'hffffff8) begin busy<=0;done<=1;error<=1;error_code<=4;state<=IDLE;end
      else if(next_invalid ||
              next_cluster==current_cluster || next_cluster==start_cluster ||
              next_cluster==chain_anchor || hops>=cluster_limit ||
              (MAX_FILE_CLUSTERS>0 && hops>=MAX_FILE_CLUSTERS)) begin
       busy<=0;done<=1;error<=1;error_code<=5;state<=IDLE;
      end else begin
       hops<=hops+1;current_cluster<={4'b0,next_cluster};sector_index<=0;is_fat<=0;timer<=0;
       // 常见环在正常流式读取阶段即可发现，不额外请求 FAT 扇区。
       rd_lba<=next_sector_start[31:0];state<=REQUEST;
      end
     end
     default:begin busy<=0;done<=1;error<=1;error_code<=1;state<=IDLE;end
    endcase
   end
  end
 end
endmodule
