// FAT32 BPB only, not an MBR/GPT parser. One ordered 512-byte sector.
// valid is metadata validation only; the caller must also check sector CRC/status.
module fat32_boot_parser #(parameter integer TIMEOUT_CYCLES=50_000_000, parameter SHARED_BPB=0)(
 input wire clk,rst_n,start,input wire [31:0] partition_lba,
 input wire [8:0] byte_addr,input wire [7:0] byte_in,input wire byte_valid,
 output reg [31:0] fat_lba,root_lba,root_cluster,
 output reg [7:0] sectors_per_cluster,output reg valid,busy,done,error,
 output reg [31:0] data_lba,cluster_count,volume_sectors,
 // Optional arithmetic sharing keeps each caller's parser state independent.
 output wire [255:0] bpb_fields,input wire [128:0] bpb_result);
 reg [15:0] bps,reserved,root_entries,total16,fat16,flags,version;
 reg [31:0] total32,fat_size,root_raw,partition;
 reg [7:0] fats,sig_low;
 reg [9:0] expected;
 integer timer;
 // The fields remain local, including the timeout and in-flight byte count.
 // Only arithmetic/structural checks may be shared by mutually exclusive callers.
 assign bpb_fields={bps,reserved,root_entries,total16,fat16,flags,version,
                    total32,fat_size,root_raw,partition,fats,sectors_per_cluster};
 wire [128:0] checked_bpb;
 wire structural_ok;
 wire [31:0] checked_fat,checked_data,checked_root,checked_clusters;
 assign {structural_ok,checked_fat,checked_data,checked_root,checked_clusters}=checked_bpb;
 generate
  if(SHARED_BPB) begin: g_shared_bpb
   assign checked_bpb=bpb_result;
  end else begin: g_local_bpb
   fat32_bpb_math u_math(.clk(clk),.bpb_fields(bpb_fields),.bpb_result(checked_bpb));
  end
 endgenerate
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   fat_lba<=0;root_lba<=0;root_cluster<=0;data_lba<=0;cluster_count<=0;volume_sectors<=0;
   sectors_per_cluster<=0;valid<=0;busy<=0;done<=0;error<=0;
   bps<=0;reserved<=0;root_entries<=0;total16<=0;fat16<=0;flags<=0;version<=0;
   total32<=0;fat_size<=0;root_raw<=0;partition<=0;fats<=0;sig_low<=0;expected<=0;timer<=0;
  end else begin
   done<=0;
   if(start && !busy) begin
    valid<=0;error<=0;busy<=1;expected<=0;timer<=0;partition<=partition_lba;
    bps<=0;reserved<=0;root_entries<=0;total16<=0;fat16<=0;flags<=0;version<=0;
    total32<=0;fat_size<=0;root_raw<=0;fats<=0;sig_low<=0;sectors_per_cluster<=0;
    fat_lba<=0;root_lba<=0;root_cluster<=0;data_lba<=0;cluster_count<=0;volume_sectors<=0;
   end else if(busy) begin
    if(timer>=TIMEOUT_CYCLES-1) begin busy<=0;done<=1;error<=1;valid<=0;end
    else begin
     timer<=timer+1;
     if(byte_valid) begin
      if({1'b0,byte_addr}!=expected) begin busy<=0;done<=1;error<=1;valid<=0;end
      else begin
       expected<=expected+1'b1;
       case(byte_addr)
        11:bps[7:0]<=byte_in;12:bps[15:8]<=byte_in;13:sectors_per_cluster<=byte_in;
        14:reserved[7:0]<=byte_in;15:reserved[15:8]<=byte_in;16:fats<=byte_in;
        17:root_entries[7:0]<=byte_in;18:root_entries[15:8]<=byte_in;
        19:total16[7:0]<=byte_in;20:total16[15:8]<=byte_in;
        22:fat16[7:0]<=byte_in;23:fat16[15:8]<=byte_in;
        32:total32[7:0]<=byte_in;33:total32[15:8]<=byte_in;34:total32[23:16]<=byte_in;35:total32[31:24]<=byte_in;
        36:fat_size[7:0]<=byte_in;37:fat_size[15:8]<=byte_in;38:fat_size[23:16]<=byte_in;39:fat_size[31:24]<=byte_in;
        40:flags[7:0]<=byte_in;41:flags[15:8]<=byte_in;42:version[7:0]<=byte_in;43:version[15:8]<=byte_in;
        44:root_raw[7:0]<=byte_in;45:root_raw[15:8]<=byte_in;46:root_raw[23:16]<=byte_in;47:root_raw[31:24]<=byte_in;
        510:sig_low<=byte_in;
        511:begin
         busy<=0;done<=1;
         if(sig_low==8'h55 && byte_in==8'haa && structural_ok) begin
          valid<=1;fat_lba<=checked_fat;data_lba<=checked_data;
          root_lba<=checked_root;root_cluster<=root_raw;cluster_count<=checked_clusters;volume_sectors<=total32;
         end else begin valid<=0;error<=1;end
        end
       endcase
      end
     end
    end
   end
  end
 end
endmodule

// One pipelined BPB arithmetic unit. The selected fields must be stable for
// five clocks before consuming bpb_result. The card catalogue changes owner
// before requesting a sector; operands finish arriving by byte 47 and only
// byte 511 consumes these results. Neither caller's receive/timeout state is
// reset or borrowed, so an aborted sector can retain its original busy state.
module fat32_bpb_math(
 input wire clk,input wire [255:0] bpb_fields,output wire [128:0] bpb_result);
 wire [15:0] bps,reserved,root_entries,total16,fat16,flags,version;
 wire [31:0] total32,fat_size,root_raw,partition;
 wire [7:0] fats,sectors_per_cluster;
 assign {bps,reserved,root_entries,total16,fat16,flags,version,
         total32,fat_size,root_raw,partition,fats,sectors_per_cluster}=bpb_fields;
 integer shift_bits,k;
 // Two FATs plus reserved sectors and a partition fit in 34 bits.
 // Keep the full subtraction and range checks before truncating metadata.
 reg [33:0] overhead,data_start,fat_start;
 reg [31:0] clusters;
 reg [39:0] root_start;
 reg [32:0] fat_base_pipe;
 always @* begin
  shift_bits=0;
  for(k=0;k<8;k=k+1) if(sectors_per_cluster[k]) shift_bits=k;
 end
 always @(posedge clk) begin
  overhead<={18'b0,reserved}+((fats==2)?({2'b0,fat_size}<<1):{2'b0,fat_size});
  clusters<=({32'b0,total32}-{30'b0,overhead})>>shift_bits;
  data_start<={2'b0,partition}+overhead;
  fat_base_pipe<={1'b0,partition}+{17'b0,reserved};
  fat_start<={1'b0,fat_base_pipe}+((flags[7] && flags[3:0]!=0)?{2'b0,fat_size}:34'd0);
  root_start<={6'b0,data_start}+(({8'b0,root_raw}-40'd2)<<shift_bits);
 end
 wire structural_ok=bps==512 &&
  sectors_per_cluster!=0 && (sectors_per_cluster&(sectors_per_cluster-1'b1))==0 &&
  reserved!=0 && (fats==1 || fats==2) && fat_size!=0 && version==0 &&
  root_entries==0 && total16==0 && fat16==0 && {32'b0,total32}>overhead &&
  clusters>=65525 && clusters<32'h0ffffff5 && root_raw>=2 && root_raw<({1'b0,clusters}+33'd2) &&
  ({32'b0,fat_size}<<7)>=({1'b0,clusters}+33'd2) && (!flags[7] || flags[3:0]<fats) &&
  ({32'b0,partition}+{32'b0,total32})<=64'h100000000 && root_start<64'h100000000;
 assign bpb_result={structural_ok,fat_start[31:0],data_start[31:0],root_start[31:0],clusters};
endmodule
