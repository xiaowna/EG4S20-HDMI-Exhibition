// Active-low key, two-stage synchronizer and 20 ms stable-level debounce.
// WIDTH>1 shares one timer across the complete keyboard snapshot. A direct
// change between held keys cannot emit a new press before a stable release.
module board_key #(parameter COUNT=1000000,parameter WIDTH=1)(
 input wire clk,rst_n,input wire [WIDTH-1:0] key_n,
 output reg [WIDTH-1:0] press,output wire [WIDTH-1:0] stable_n);
 localparam integer COUNT_BITS=(COUNT>1)?$clog2(COUNT):1;
 localparam [WIDTH-1:0] RELEASED={WIDTH{1'b1}};
 (* async_reg="true" *) reg [WIDTH-1:0] k1,k2;
 reg [WIDTH-1:0] stable,candidate;
 reg [COUNT_BITS-1:0] count;
 assign stable_n=stable;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin k1<=RELEASED;k2<=RELEASED;stable<=RELEASED;
   candidate<=RELEASED;count<=0;press<=0;end
  else begin
   k1<=key_n;k2<=k1;candidate<=k2;press<=0;
   if(k2==stable)count<=0;
   else if(COUNT==1 || (count==COUNT-1 && (WIDTH==1 || k2==candidate)))begin
    stable<=k2;count<=0;
    if(WIDTH==1 || stable==RELEASED)press<=~k2;
   end
   else if(WIDTH!=1 && k2!=candidate)count<=1;
   else count<=count+1'b1;
  end
 end
endmodule
