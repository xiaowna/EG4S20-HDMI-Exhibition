// 48 kHz 双声道 PCM 测试音源；所有逻辑工作在 clk 域。
// enable=1：1 kHz 正弦测试音，峰值为满量程的约 1/8；enable=0：静音。
// sample_valid/sample_ready 为握手接口，左右声道是有符号 24 位补码。
// 下游阻塞时保留已有样本；新采样点到来而旧样本未接收则丢弃新样本，
// overflow 置位并保持至复位。正常播放需要后续 FIFO 避免这种情况。
// CLK_HZ 必须 >= 48000，enable/sample_ready 必须已经同步到 clk 域。
module audio_test_tone #(parameter integer CLK_HZ=50_000_000)(
 input wire clk,rst_n,enable,sample_ready,
 output reg sample_valid,
 output reg signed [23:0] sample_left,sample_right,
 output reg sample_tick,overflow);
 localparam integer SAMPLE_HZ=48000;
 localparam integer ACC_BITS=(CLK_HZ>1)?$clog2(CLK_HZ):1;
 reg [ACC_BITS-1:0] rate_acc;
 reg [5:0] tone_phase;
 wire tick_due=(rate_acc>=CLK_HZ-SAMPLE_HZ);
 function [23:0] tone_value;
  input [5:0] phase;
  begin
   case(phase)
    6'd0: tone_value=24'h000000;
    6'd1: tone_value=24'h021700;
    6'd2: tone_value=24'h042400;
    6'd3: tone_value=24'h061f00;
    6'd4: tone_value=24'h080000;
    6'd5: tone_value=24'h09bd00;
    6'd6: tone_value=24'h0b5000;
    6'd7: tone_value=24'h0cb200;
    6'd8: tone_value=24'h0ddb00;
    6'd9: tone_value=24'h0ec800;
    6'd10: tone_value=24'h0f7400;
    6'd11: tone_value=24'h0fdd00;
    6'd12: tone_value=24'h100000;
    6'd13: tone_value=24'h0fdd00;
    6'd14: tone_value=24'h0f7400;
    6'd15: tone_value=24'h0ec800;
    6'd16: tone_value=24'h0ddb00;
    6'd17: tone_value=24'h0cb200;
    6'd18: tone_value=24'h0b5000;
    6'd19: tone_value=24'h09bd00;
    6'd20: tone_value=24'h080000;
    6'd21: tone_value=24'h061f00;
    6'd22: tone_value=24'h042400;
    6'd23: tone_value=24'h021700;
    6'd24: tone_value=24'h000000;
    6'd25: tone_value=24'hfde900;
    6'd26: tone_value=24'hfbdc00;
    6'd27: tone_value=24'hf9e100;
    6'd28: tone_value=24'hf80000;
    6'd29: tone_value=24'hf64300;
    6'd30: tone_value=24'hf4b000;
    6'd31: tone_value=24'hf34e00;
    6'd32: tone_value=24'hf22500;
    6'd33: tone_value=24'hf13800;
    6'd34: tone_value=24'hf08c00;
    6'd35: tone_value=24'hf02300;
    6'd36: tone_value=24'hf00000;
    6'd37: tone_value=24'hf02300;
    6'd38: tone_value=24'hf08c00;
    6'd39: tone_value=24'hf13800;
    6'd40: tone_value=24'hf22500;
    6'd41: tone_value=24'hf34e00;
    6'd42: tone_value=24'hf4b000;
    6'd43: tone_value=24'hf64300;
    6'd44: tone_value=24'hf80000;
    6'd45: tone_value=24'hf9e100;
    6'd46: tone_value=24'hfbdc00;
    6'd47: tone_value=24'hfde900;
    default: tone_value=24'd0;
   endcase
  end
 endfunction
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   rate_acc<=0;tone_phase<=0;
   sample_valid<=0;sample_left<=0;sample_right<=0;
   sample_tick<=0;overflow<=0;
  end else begin
   sample_tick<=tick_due;
   if(sample_valid && sample_ready) sample_valid<=0;
   // 使用时钟使能而非逻辑生成的时钟；50 MHz 下间隔为 1041/1042 周期。
   if(tick_due) begin
    rate_acc<=rate_acc-(CLK_HZ-SAMPLE_HZ);
    if(!sample_valid || sample_ready) begin
     sample_valid<=1;
     sample_left<=enable?tone_value(tone_phase):24'd0;
     sample_right<=enable?tone_value(tone_phase):24'd0;
    end else overflow<=1;
    // 即使丢样仍跟随时间推进，避免把过期采样点延后补发。
    if(!enable || tone_phase==47) tone_phase<=0;
    else tone_phase<=tone_phase+1'b1;
   end else rate_acc<=rate_acc+SAMPLE_HZ;
  end
 end
endmodule
