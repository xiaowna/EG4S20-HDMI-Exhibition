// 512 real samples -> normalized complex FFT bins 0..255, in natural order.
// One radix-2 DIT butterfly and one signed 16x16 multiplier are time shared.
// Capture and processing are separate snapshots; busy samples are observed
// and discarded locally, never backpressured into the audio playback path.
module audio_fft512_reference(
 input wire clk,rst_n,capture_enable,sample_valid,
 input wire signed [23:0] sample_left,
 output reg bin_valid,output reg [7:0] bin_index,
 output reg signed [15:0] bin_real,bin_imag,output wire busy);
 localparam CAPTURE=0,LREQ=1,LMUL=2,LSTORE=3,AREQ=4,ASAVE=5,
  BREQ=6,BSAVE=7,M0=8,M1=9,M2=10,M3=11,CALC=12,WA=13,WB=14,
  OREQ=15,OSEND=16,DRAIN0=17,DRAIN1=18;
 reg [4:0] state;
 reg [8:0] capture_index,load_index,addr_a,half_span,group_mask,twiddle_step;
 reg [7:0] butterfly_index,twiddle_index,scan_index;
 reg signed [15:0] ar,ai,br,bi;
 reg signed [32:0] acc_r,acc_i;
 reg [15:0] capture_mem[0:511];reg signed [15:0] capture_read;
 reg [31:0] fft_mem[0:511],fft_read;
 wire signed [15:0] window_value,wr,wi;
 audio_fft_coeff_rom coefficients(.clk(clk),.window_address(load_index),
  .twiddle_address(twiddle_index),.window_value(window_value),.twiddle_real(wr),.twiddle_imag(wi));
 function [8:0] reverse9;
  input [8:0] v;
  begin reverse9={v[0],v[1],v[2],v[3],v[4],v[5],v[6],v[7],v[8]};end
 endfunction
 wire [8:0] ram_address=(state==LSTORE)?reverse9(load_index):
  ((state==BREQ||state==WB)?(addr_a|half_span):((state==OREQ)?{1'b0,scan_index}:addr_a));
 reg signed [15:0] mul_a,mul_b;
 reg signed [31:0] mul_product;
 always @*begin
  mul_a=br;mul_b=wr;
  case(state)
   LMUL:begin mul_a=capture_read;mul_b=window_value;end
   M1:begin mul_a=bi;mul_b=wi;end
   M2:begin mul_a=br;mul_b=wi;end
   M3:begin mul_a=bi;mul_b=wr;end
   default:;
  endcase
 end
 // Keep resets off DSP and memory datapaths; metadata masks stale contents.
 always @(posedge clk)mul_product<=mul_a*mul_b;
 wire signed [33:0] a_real_q15={{3{ar[15]}},ar,15'd0};
 wire signed [33:0] a_imag_q15={{3{ai[15]}},ai,15'd0};
 wire signed [33:0] b_real_q15={acc_r[32],acc_r};
 wire signed [33:0] b_imag_q15={acc_i[32],acc_i};
 wire signed [33:0] result_r=(state==WB)?a_real_q15-b_real_q15:a_real_q15+b_real_q15;
 wire signed [33:0] result_i=(state==WB)?a_imag_q15-b_imag_q15:a_imag_q15+b_imag_q15;
 function [15:0] normalized;
  input signed [33:0] value;reg signed [33:0] shifted;
  begin
   shifted=value>>>16;
   if(shifted>34'sd32767)normalized=16'h7fff;
   else if(shifted< -34'sd32768)normalized=16'h8000;
   else normalized=shifted[15:0];
  end
 endfunction
 wire ram_write=state==LSTORE||state==WA||state==WB;
 wire [31:0] ram_data=(state==LSTORE)?{mul_product[30:15],16'd0}:
  {normalized(result_r),normalized(result_i)};
 always @(posedge clk)begin
  capture_read<=capture_mem[load_index];
  if(rst_n&&state==CAPTURE&&capture_enable&&sample_valid)
   capture_mem[capture_index]<=sample_left[23:8];
  fft_read<=fft_mem[ram_address];
  if(rst_n&&ram_write)fft_mem[ram_address]<=ram_data;
 end
 assign busy=state!=CAPTURE;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=CAPTURE;capture_index<=0;load_index<=0;addr_a<=0;half_span<=1;
   group_mask<=0;twiddle_step<=256;butterfly_index<=0;twiddle_index<=0;scan_index<=0;
   ar<=0;ai<=0;br<=0;bi<=0;acc_r<=0;acc_i<=0;
   bin_valid<=0;bin_index<=0;bin_real<=0;bin_imag<=0;
  end else begin
   bin_valid<=0;
   case(state)
    CAPTURE:if(capture_enable&&sample_valid)begin
     if(capture_index==511)begin load_index<=0;capture_index<=0;state<=LREQ;end
     else capture_index<=capture_index+1'b1;
    end
    LREQ:state<=LMUL;
    LMUL:state<=LSTORE;
    LSTORE:if(load_index==511)begin
     addr_a<=0;half_span<=1;group_mask<=0;twiddle_step<=256;
     butterfly_index<=0;twiddle_index<=0;state<=AREQ;
    end else begin load_index<=load_index+1'b1;state<=LREQ;end
    AREQ:state<=ASAVE;
    ASAVE:begin ar<=fft_read[31:16];ai<=fft_read[15:0];state<=BREQ;end
    BREQ:state<=BSAVE;
    BSAVE:begin br<=fft_read[31:16];bi<=fft_read[15:0];state<=M0;end
    M0:state<=M1;
    M1:begin acc_r<={mul_product[31],mul_product};state<=M2;end
    M2:begin acc_r<=acc_r-$signed({mul_product[31],mul_product});state<=M3;end
    M3:begin acc_i<={mul_product[31],mul_product};state<=CALC;end
    CALC:begin acc_i<=acc_i+$signed({mul_product[31],mul_product});state<=WA;end
    WA:state<=WB;
    WB:begin
     if(butterfly_index==255)begin
      butterfly_index<=0;addr_a<=0;twiddle_index<=0;
      if(half_span==256)begin scan_index<=0;state<=OREQ;end
      else begin
       half_span<=half_span<<1;group_mask<={group_mask[7:0],1'b1};
       twiddle_step<=twiddle_step>>1;state<=AREQ;
      end
     end else begin
      butterfly_index<=butterfly_index+1'b1;twiddle_index<=twiddle_index+twiddle_step[7:0];
      addr_a<=addr_a+9'd1+(((addr_a&group_mask)==group_mask)?half_span:9'd0);state<=AREQ;
     end
    end
    OREQ:state<=OSEND;
    OSEND:begin
     bin_valid<=1;bin_index<=scan_index;bin_real<=fft_read[31:16];bin_imag<=fft_read[15:0];
     if(scan_index==255)state<=DRAIN0;
     else begin scan_index<=scan_index+1'b1;state<=OREQ;end
    end
    DRAIN0:state<=DRAIN1;
    DRAIN1:state<=CAPTURE;
    default:state<=CAPTURE;
   endcase
  end
 end
endmodule
