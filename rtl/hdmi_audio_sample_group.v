// 历史实验模块，未按 HDMI 完整包格式实现，不得直接接入数据岛编码器。
// HDMI 音频样本组缓存：仅按自定义接口收集 3 个立体声 PCM 帧，并非 HDMI 固定要求。
// 每帧为左右声道各 24 位；组满后输出 6 个样本并保持 stable，等待消费。
// 这是数据岛编码前的规范化输入，不包含 BCH/TERC4，也不直接连接 TMDS。
module hdmi_audio_sample_group(
 input wire clk,rst_n,input wire in_valid,input wire signed [23:0] in_left,in_right,
 output wire in_ready,output reg group_valid,input wire group_ready,
 output reg signed [23:0] left0,right0,left1,right1,left2,right2,
 output reg [1:0] frame_count);
 assign in_ready=!group_valid && (frame_count<3);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin group_valid<=0;frame_count<=0;left0<=0;right0<=0;left1<=0;right1<=0;left2<=0;right2<=0;end
  else begin
   if(group_valid) begin
    if(group_ready)begin group_valid<=0;frame_count<=0;end
   end else if(in_valid&&in_ready) begin
    case(frame_count)
     2'd0:begin left0<=in_left;right0<=in_right;end
     2'd1:begin left1<=in_left;right1<=in_right;end
     default:begin left2<=in_left;right2<=in_right;end
    endcase
    if(frame_count==2)begin group_valid<=1;frame_count<=3;end
    else frame_count<=frame_count+1'b1;
   end
  end
 end
endmodule
