// 历史实验模块，未按 HDMI 完整包格式实现，不得直接接入数据岛编码器。
// HDMI 音频子包基础封装：每次请求输出 4 个 32 位子包字。
// word0/word1 为左右声道 24 位样本，word2/word3 保留为静音子包。
// 这一级只负责数据格式和 N/CTS 参数，不负责 TMDS data-island 调度。
module hdmi_audio_packetizer #(parameter integer TMDS_CLK_HZ=25_000_000,
 parameter integer SAMPLE_HZ=48_000)(
 input wire clk,rst_n,input wire packet_start,
 input wire sample_valid,input wire signed [23:0] sample_left,sample_right,
 output wire sample_ready,output reg packet_valid,packet_last,
 output reg [1:0] packet_index,output reg [31:0] packet_word,
 output reg [23:0] n_value,output reg [19:0] cts_value,
 output reg busy);
 localparam integer N_CONST=128*SAMPLE_HZ/1000;
 localparam integer CTS_CONST=(TMDS_CLK_HZ/1000)*N_CONST/((SAMPLE_HZ/1000)*128);
 reg signed [23:0] left_reg,right_reg;
 reg [1:0] word_count;
 reg parity;
 assign sample_ready=packet_start && !busy && sample_valid;
 function automatic parity32;
  input [31:0] value;
  integer i;begin parity32=1'b0;for(i=0;i<32;i=i+1)parity32=parity32^value[i];end
 endfunction
 function automatic [31:0] make_word;
  input signed [23:0] sample;input [1:0] channel;
  reg [31:0] base;begin
   // 24-bit PCM + channel marker + odd parity. The downstream HDMI
   // scheduler adds the data-island header and BCH/TMDS protection.
   base={sample,4'b0,channel,2'b0};make_word={base[31:1],~parity32(base)};
  end
 endfunction
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin left_reg<=0;right_reg<=0;word_count<=0;packet_valid<=0;packet_last<=0;packet_index<=0;packet_word<=0;busy<=0;n_value<=N_CONST;cts_value<=CTS_CONST;end
  else begin
   packet_valid<=0;packet_last<=0;
   if(!busy)begin
    if(packet_start&&sample_valid)begin left_reg<=sample_left;right_reg<=sample_right;word_count<=0;packet_index<=0;busy<=1;end
   end else begin
    packet_valid<=1;packet_index<=word_count;
    case(word_count)
     2'd0:packet_word<=make_word(left_reg,2'd0);
     2'd1:packet_word<=make_word(right_reg,2'd1);
     default:packet_word<=32'd0;
    endcase
    if(word_count==3)begin packet_last<=1;busy<=0;end
    else word_count<=word_count+1'b1;
   end
  end
 end
endmodule

