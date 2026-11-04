// HDMI 1.3 第 5.2.3.5 节：G(x)=1+x^6+x^7+x^8。
// data_in[0] 首先进入校验器；ecc[0] 首先发送。反馈掩码为反向 8'h83。
// start && !busy 时锁存整字，随后每拍处理一位；done 为单周期脉冲。
// DATA_BITS 用 24（包头）或 56（子包）。复位中止在途运算。
module hdmi_bch8 #(parameter integer DATA_BITS=24)(
 input wire clk,rst_n,start,
 input wire [DATA_BITS-1:0] data_in,
 output reg busy,done,output reg [7:0] ecc);
 localparam COUNT_BITS=(DATA_BITS<2)?1:$clog2(DATA_BITS);
 reg [DATA_BITS-1:0] shift;
 reg [COUNT_BITS-1:0] count;
 reg [7:0] remainder;
 wire [7:0] next_remainder={1'b0,remainder[7:1]} ^
                         ((remainder[0]^shift[0])?8'h83:8'h00);
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin busy<=0;done<=0;ecc<=0;shift<=0;count<=0;remainder<=0;end
  else begin
   done<=0;
   if(!busy)begin
    if(start)begin busy<=1;shift<=data_in;count<=0;remainder<=0;end
   end else begin
    shift<=shift>>1;remainder<=next_remainder;
    if(count==DATA_BITS-1)begin ecc<=next_remainder;busy<=0;done<=1;end
    else count<=count+1'b1;
   end
  end
 end
endmodule
