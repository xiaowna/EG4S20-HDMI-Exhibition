// 双时钟音频 FIFO：写入域通常为 50 MHz，读取域为 HDMI 音频时钟。
// 每个条目是 24 位左声道 + 24 位右声道，深度 256。
// 任意一侧复位会丢弃全部缓存；异步置位、各域两拍同步释放。
// 复位恢复期间 wr_full=1、rd_empty=1，禁止接受事务。
// ADDR_BITS >= 2；rd_data 在 rd_en && !rd_empty 的时钟沿后更新。
// rd_level 是读时钟域基于同步写指针得到的保守占用量。
module audio_async_fifo #(parameter ADDR_BITS=8)(
 input wire wr_clk,wr_rst_n,wr_en,input wire [47:0] wr_data,output wire wr_full,
 input wire rd_clk,rd_rst_n,rd_en,output reg [47:0] rd_data,output wire rd_empty,
 output wire [ADDR_BITS:0] rd_level,wr_level);
 wire reset_n=wr_rst_n && rd_rst_n;
 (* async_reg="true" *) reg [1:0] wr_release,rd_release;
 always @(posedge wr_clk or negedge reset_n)
  if(!reset_n)wr_release<=0;else wr_release<={wr_release[0],1'b1};
 always @(posedge rd_clk or negedge reset_n)
  if(!reset_n)rd_release<=0;else rd_release<={rd_release[0],1'b1};
 wire wr_active=wr_release[1];
 wire rd_active=rd_release[1];
 localparam DEPTH=(1<<ADDR_BITS);
 reg [47:0] mem[0:DEPTH-1];
 reg [ADDR_BITS:0] wr_bin,wr_gray,rd_bin,rd_gray;
 (* async_reg="true" *) reg [ADDR_BITS:0] rd_gray_w1,rd_gray_w2;
 (* async_reg="true" *) reg [ADDR_BITS:0] wr_gray_r1,wr_gray_r2;
 // 只用读时钟域已同步两拍的写指针计算保守占用量。
 function [ADDR_BITS:0] gray_to_bin;
  input [ADDR_BITS:0] gray;
  integer bit_index;
  begin
   gray_to_bin[ADDR_BITS]=gray[ADDR_BITS];
   for(bit_index=ADDR_BITS-1;bit_index>=0;bit_index=bit_index-1)
    gray_to_bin[bit_index]=gray_to_bin[bit_index+1]^gray[bit_index];
  end
 endfunction
 assign rd_level=rd_active?(gray_to_bin(wr_gray_r2)-rd_bin):{(ADDR_BITS+1){1'b0}};
 // 写时钟域使用已同步的读指针；未同步的近期读取只会使水位偏高。
 assign wr_level=wr_active?(wr_bin-gray_to_bin(rd_gray_w2)):{(ADDR_BITS+1){1'b0}};
 wire [ADDR_BITS:0] wr_bin_next=wr_bin+((wr_en&&!wr_full)?1'b1:1'b0);
 wire [ADDR_BITS:0] rd_bin_next=rd_bin+((rd_en&&!rd_empty)?1'b1:1'b0);
 wire [ADDR_BITS:0] wr_gray_next=(wr_bin_next>>1)^wr_bin_next;
 wire [ADDR_BITS:0] rd_gray_next=(rd_bin_next>>1)^rd_bin_next;
 wire full_next=(wr_gray_next=={~rd_gray_w2[ADDR_BITS:ADDR_BITS-1],rd_gray_w2[ADDR_BITS-2:0]});
 reg full_reg,empty_reg;
 assign wr_full=!wr_active || full_reg;assign rd_empty=!rd_active || empty_reg;
 always @(posedge wr_clk or negedge wr_active) begin
  if(!wr_active) begin wr_bin<=0;wr_gray<=0;rd_gray_w1<=0;rd_gray_w2<=0;full_reg<=0;end
  else begin
   rd_gray_w1<=rd_gray;rd_gray_w2<=rd_gray_w1;
   if(wr_en&&!full_reg) mem[wr_bin[ADDR_BITS-1:0]]<=wr_data;
   wr_bin<=wr_bin_next;wr_gray<=wr_gray_next;full_reg<=full_next;
  end
 end
 always @(posedge rd_clk or negedge rd_active) begin
  if(!rd_active) begin rd_bin<=0;rd_gray<=0;wr_gray_r1<=0;wr_gray_r2<=0;empty_reg<=1;end
  else begin
   wr_gray_r1<=wr_gray;wr_gray_r2<=wr_gray_r1;
   rd_bin<=rd_bin_next;rd_gray<=rd_gray_next;empty_reg<=(rd_gray_next==wr_gray_r2);
  end
 end
 // 无有效读取时数据本来不可用；不复位 BRAM 输出寄存器，避免复位释放
 // 直接进入 BRAM 异步复位脚的 removal 时序路径。
 always @(posedge rd_clk)
  if(rd_en&&!rd_empty)rd_data<=mem[rd_bin[ADDR_BITS-1:0]];
endmodule
