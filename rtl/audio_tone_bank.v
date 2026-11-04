// 48 kHz 可选频率 PCM 测试音源。tone_sel 对应 440/880/1000/2000/4000/8000/12000/16000 Hz。
module audio_tone_bank #(parameter integer CLK_HZ=50_000_000,
 parameter integer HOLD_ON_BACKPRESSURE=0,parameter integer FIXED_1KHZ=0)(
 input wire clk,input wire rst_n,input wire enable,input wire [2:0] tone_sel,
 input wire sample_ready,output reg sample_valid,
 output reg signed [23:0] sample_left,sample_right,
 output reg sample_tick,output reg overflow);
 localparam integer SAMPLE_HZ=48000;
 localparam integer ACC_BITS=(CLK_HZ>1)?$clog2(CLK_HZ):1;
 localparam [31:0] INC440=32'h0258bf26,
                    INC880=32'h04b17e4b,
                    INC1000=32'h05555555,
                    INC2000=32'h0aaaaaab,
                    INC4000=32'h15555555,
                    INC8000=32'h2aaaaaab,
                    INC12000=32'h40000000,
                    INC16000=32'h55555555;
 reg [ACC_BITS-1:0] rate_acc; reg [31:0] phase_acc;reg [5:0] fixed_phase;
 wire tick_due=(rate_acc>=CLK_HZ-SAMPLE_HZ); reg [31:0] phase_inc;
 function [23:0] sine_value; input [5:0] index; begin case(index)
    6'd0: sine_value=24'h000000;
    6'd1: sine_value=24'h01917a;
    6'd2: sine_value=24'h031f17;
    6'd3: sine_value=24'h04a502;
    6'd4: sine_value=24'h061f79;
    6'd5: sine_value=24'h078ad7;
    6'd6: sine_value=24'h08e39e;
    6'd7: sine_value=24'h0a267a;
    6'd8: sine_value=24'h0b504f;
    6'd9: sine_value=24'h0c5e40;
    6'd10: sine_value=24'h0d4db3;
    6'd11: sine_value=24'h0e1c59;
    6'd12: sine_value=24'h0ec836;
    6'd13: sine_value=24'h0f4fa1;
    6'd14: sine_value=24'h0fb14c;
    6'd15: sine_value=24'h0fec47;
    6'd16: sine_value=24'h100000;
    6'd17: sine_value=24'h0fec47;
    6'd18: sine_value=24'h0fb14c;
    6'd19: sine_value=24'h0f4fa1;
    6'd20: sine_value=24'h0ec836;
    6'd21: sine_value=24'h0e1c59;
    6'd22: sine_value=24'h0d4db3;
    6'd23: sine_value=24'h0c5e40;
    6'd24: sine_value=24'h0b504f;
    6'd25: sine_value=24'h0a267a;
    6'd26: sine_value=24'h08e39e;
    6'd27: sine_value=24'h078ad7;
    6'd28: sine_value=24'h061f79;
    6'd29: sine_value=24'h04a502;
    6'd30: sine_value=24'h031f17;
    6'd31: sine_value=24'h01917a;
    6'd32: sine_value=24'h000000;
    6'd33: sine_value=24'hfe6e86;
    6'd34: sine_value=24'hfce0e9;
    6'd35: sine_value=24'hfb5afe;
    6'd36: sine_value=24'hf9e087;
    6'd37: sine_value=24'hf87529;
    6'd38: sine_value=24'hf71c62;
    6'd39: sine_value=24'hf5d986;
    6'd40: sine_value=24'hf4afb1;
    6'd41: sine_value=24'hf3a1c0;
    6'd42: sine_value=24'hf2b24d;
    6'd43: sine_value=24'hf1e3a7;
    6'd44: sine_value=24'hf137ca;
    6'd45: sine_value=24'hf0b05f;
    6'd46: sine_value=24'hf04eb4;
    6'd47: sine_value=24'hf013b9;
    6'd48: sine_value=24'hf00000;
    6'd49: sine_value=24'hf013b9;
    6'd50: sine_value=24'hf04eb4;
    6'd51: sine_value=24'hf0b05f;
    6'd52: sine_value=24'hf137ca;
    6'd53: sine_value=24'hf1e3a7;
    6'd54: sine_value=24'hf2b24d;
    6'd55: sine_value=24'hf3a1c0;
    6'd56: sine_value=24'hf4afb1;
    6'd57: sine_value=24'hf5d986;
    6'd58: sine_value=24'hf71c62;
    6'd59: sine_value=24'hf87529;
    6'd60: sine_value=24'hf9e087;
    6'd61: sine_value=24'hfb5afe;
    6'd62: sine_value=24'hfce0e9;
    6'd63: sine_value=24'hfe6e86;
    default: sine_value=24'd0; endcase end endfunction
 localparam [767:0] FIXED_SAMPLES=768'hfde9fbdcf9e1f800f643f4b0f34ef225f138f08cf023f000f023f08cf138f225f34ef4b0f643f800f9e1fbdcfde9000002170424061f080009bd0b500cb20ddb0ec80f740fdd10000fdd0f740ec80ddb0cb20b5009bd0800061f042402170000;
 wire [23:0] fixed_sample;
 generate if(FIXED_1KHZ)begin:fixed_tone
  // Exact 48-sample, 1kHz period at 48kHz; prefetched between sample ticks.
  (* rom_style="bram" *) reg [15:0] samples[0:47];reg [15:0] q;integer k;
  initial for(k=0;k<48;k=k+1)samples[k]=FIXED_SAMPLES[k*16+:16];
  always @(posedge clk)q<=samples[fixed_phase];
  assign fixed_sample={q,8'd0};
 end else begin:no_fixed_tone
  assign fixed_sample=24'd0;
 end endgenerate
 wire [23:0] next_sample=FIXED_1KHZ?fixed_sample:sine_value(phase_acc[31:26]);
 always @* begin case(tone_sel)
 3'd0:phase_inc=INC440;3'd1:phase_inc=INC880;3'd2:phase_inc=INC1000;3'd3:phase_inc=INC2000;
 3'd4:phase_inc=INC4000;3'd5:phase_inc=INC8000;3'd6:phase_inc=INC12000;default:phase_inc=INC16000;endcase end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin rate_acc<=0;phase_acc<=0;fixed_phase<=0;sample_valid<=0;sample_left<=0;sample_right<=0;sample_tick<=0;overflow<=0;end
  else begin
   sample_tick<=0;
   // The board output must retain the next tone sample while its FIFO is full.
   // Other users keep the original overflow reporting by leaving this off.
   if(!(HOLD_ON_BACKPRESSURE && sample_valid && !sample_ready))begin
    sample_tick<=tick_due;
    if(sample_valid&&sample_ready)sample_valid<=0;
    if(tick_due) begin rate_acc<=rate_acc-(CLK_HZ-SAMPLE_HZ);
     if(!sample_valid||sample_ready) begin sample_valid<=1;sample_left<=enable?$signed(next_sample):24'sd0;sample_right<=enable?$signed(next_sample):24'sd0;end else overflow<=1;
     phase_acc<=FIXED_1KHZ?32'd0:phase_acc+phase_inc;
     fixed_phase<=FIXED_1KHZ?((fixed_phase==47)?6'd0:fixed_phase+1'b1):6'd0;
    end else rate_acc<=rate_acc+SAMPLE_HZ;
   end
  end
 end
endmodule
