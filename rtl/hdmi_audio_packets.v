// 48 kHz / 24 位 / 双声道 Layout 0。25 MHz/800 像素对应每秒 31250 行；
// 每行按 48000/31250 的分数节拍取 1 或 2 个样本，不能把 FIFO 积压当作取样节拍。
// FIFO 为同步读输出；read_en 后下一周期再锁存数据。
module hdmi_audio_packets(
 input wire clk,rst_n,build,frame_start,
 input wire fifo_empty,input wire [47:0] fifo_data,output wire fifo_read,output wire sample_request,
 output reg packet_valid,output reg [23:0] audio_header,aux_header,
 output reg [223:0] audio_body,aux_body);
 localparam IDLE=0,READ=1,CAPTURE=2,FINISH=3;
 reg [1:0] state;
 // 每行最多两个样本，显式限制为槽 0/1，便于裁剪其余常零子包。
 reg slot;
 reg [1:0] line_remaining;
 reg capture_zero;
 reg [14:0] pace_acc;
 wire [16:0] pace_sum={2'b00,pace_acc}+17'd48000;
 wire two_samples=(pace_sum>=17'd62500);
 reg [7:0] frame_index;
 reg [14:0] acr_count;
 reg acr_pending,avi_pending,info_pending;
 // IEC60958 消费级 PCM，左右声道编号 1/2，48 kHz，24 位。
 localparam [191:0] STATUS_L=192'h000000000000000000000000000000000000000b02100004;
 localparam [191:0] STATUS_R=192'h000000000000000000000000000000000000000b02200004;
 wire cl=STATUS_L[frame_index],cr=STATUS_R[frame_index];
 wire [47:0] packet_sample=capture_zero?48'd0:fifo_data;
 wire [23:0] left_sample=packet_sample[47:24],right_sample=packet_sample[23:0];
 wire [7:0] status_byte={(^right_sample)^cr,cr,2'b00,(^left_sample)^cl,cl,2'b00};
 // 子包按 SB0 在低位排列；N=6144，CTS=25000（25 MHz 像素时钟）。
 localparam [55:0] ACR=56'h001800a8610000;
 assign sample_request=(state==READ)&&(line_remaining!=0);
 assign fifo_read=sample_request&&!fifo_empty;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;slot<=0;line_remaining<=0;capture_zero<=0;pace_acc<=0;frame_index<=0;packet_valid<=0;
   audio_header<=0;audio_body<=0;aux_header<=0;aux_body<=0;
   acr_count<=0;acr_pending<=1;avi_pending<=1;info_pending<=1;
  end else begin
   packet_valid<=0;
   if(acr_count==24999)begin acr_count<=0;acr_pending<=1;end
   else acr_count<=acr_count+1'b1;
   if(frame_start)begin avi_pending<=1;info_pending<=1;end
   case(state)
    IDLE:if(build)begin
     slot<=0;audio_header<=0;audio_body<=0;aux_header<=0;aux_body<=0;
     line_remaining<=two_samples?2'd2:2'd1;
     pace_acc<=two_samples?pace_sum-17'd62500:pace_sum-17'd31250;
     if(acr_pending)begin
      aux_header<=24'h000001;aux_body<={4{ACR}};
      acr_pending<=(acr_count==24999);
     end else if(avi_pending)begin
      // RGB，4:3，VIC=0（本工程为 25 MHz 自定义 VGA 时序）。
      aux_header<=24'h0d0282;aux_body<=224'h0000000000000000000000000000000000000000000000000010005f;
      avi_pending<=frame_start;
     end else if(info_pending)begin
      // 2 声道；频率/字长参考 IEC60958；CA=0（FL/FR）。
      aux_header<=24'h0a0184;aux_body<=224'h00000000000000000000000000000000000000000000000000000170;
      info_pending<=frame_start;
     end
     state<=READ;
    end
    READ:if(line_remaining==0)state<=FINISH;
         else begin capture_zero<=fifo_empty;state<=CAPTURE;end
    CAPTURE:begin
     audio_header[7:0]<=8'h02;
     if(slot)begin
      audio_header[9]<=1'b1;
      audio_header[21]<=(frame_index==0);
      audio_body[111:56]<={status_byte,right_sample,left_sample};
     end else begin
      audio_header[8]<=1'b1;
      audio_header[20]<=(frame_index==0);
      audio_body[55:0]<={status_byte,right_sample,left_sample};
     end
     line_remaining<=line_remaining-1'b1;
     if(frame_index==191)frame_index<=0;else frame_index<=frame_index+1'b1;
     if(line_remaining==1)state<=FINISH;
     else begin slot<=slot+1'b1;state<=READ;end
    end
    FINISH:begin packet_valid<=1;state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
