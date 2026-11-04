// Exact affine/fade pixel mapping using available DSPs. The legacy module
// name and configuration timing are retained for existing AV callers.
// One registered pixel stage; coefficients publish only in vertical blanking.
module video_brightness_lut(
 input wire pix_clk,rst_n,vsync,
 input wire [23:0] rgb_in,
 input wire cfg_valid,output wire cfg_ready,
 input wire signed [8:0] brightness,input wire [8:0] gain_q8,
 input wire [5:0] fade,output reg cfg_applied,output reg [23:0] rgb_out);
 reg signed [8:0] active_bias,held_bias;
 reg [8:0] active_gain,held_gain;
 reg [5:0] active_fade,held_fade;
 reg building,pending,vsync_prev;
 reg [7:0] settle_index;
 assign cfg_ready=rst_n&&!building&&!pending;
 // Preserve the original 256-clock configuration settling window and
 // backpressure contract. Subsequent busy requests cannot replace the pair.
 always @(posedge pix_clk or negedge rst_n)
  if(!rst_n)begin
   active_bias<=0;active_gain<=256;active_fade<=32;
   held_bias<=0;held_gain<=256;held_fade<=32;
   building<=0;pending<=0;vsync_prev<=1;settle_index<=0;cfg_applied<=0;
  end else begin
   vsync_prev<=vsync;cfg_applied<=0;
   if(cfg_valid&&cfg_ready)begin
    held_bias<=brightness;held_gain<=gain_q8;held_fade<=fade;
    settle_index<=0;building<=1;
   end
   if(building)begin
    if(settle_index==255)begin building<=0;pending<=1;end
    else settle_index<=settle_index+1'b1;
   end
   if(pending&&vsync_prev&&!vsync)begin
    active_bias<=held_bias;active_gain<=held_gain;active_fade<=held_fade;
    pending<=0;cfg_applied<=1;
   end
  end
 wire signed [18:0] offset=$signed({{2{active_bias[8]}},active_bias,8'b0})+
  19'sd32768-$signed({3'b000,active_gain,7'b0});
 wire [23:0] mapped;
 genvar c;
 generate for(c=0;c<3;c=c+1)begin:channel
  wire [7:0] sample=rgb_in[c*8+:8];
  wire [16:0] product;
`ifdef __ICARUS__
  assign product=sample*active_gain;
`else
  EG_LOGIC_MULT #(.INPUT_WIDTH_A(8),.INPUT_WIDTH_B(9),.OUTPUT_WIDTH(17),
   .INPUTFORMAT("UNSIGNED"),.INPUTREGA("DISABLE"),.INPUTREGB("DISABLE"),
   .OUTPUTREG("DISABLE"),.IMPLEMENT("DSP")) affine_multiply(
   .a(sample),.b(active_gain),.p(product),.clk(pix_clk),
   .cea(1'b1),.ceb(1'b1),.cepd(1'b1),.rstan(1'b1),.rstbn(1'b1),.rstpdn(1'b1));
`endif
  wire signed [18:0] numerator=$signed({2'b00,product})+offset;
  wire [7:0] affine=(numerator<0)?8'd0:((numerator>65280)?8'd255:numerator[15:8]);
  wire [13:0] faded;
`ifdef __ICARUS__
  assign faded=affine*active_fade;
`else
  EG_LOGIC_MULT #(.INPUT_WIDTH_A(8),.INPUT_WIDTH_B(6),.OUTPUT_WIDTH(14),
   .INPUTFORMAT("UNSIGNED"),.INPUTREGA("DISABLE"),.INPUTREGB("DISABLE"),
   .OUTPUTREG("DISABLE"),.IMPLEMENT("DSP")) fade_multiply(
   .a(affine),.b(active_fade),.p(faded),.clk(pix_clk),
   .cea(1'b1),.ceb(1'b1),.cepd(1'b1),.rstan(1'b1),.rstbn(1'b1),.rstpdn(1'b1));
`endif
  assign mapped[c*8+:8]=faded[12:5];
 end endgenerate
 always @(posedge pix_clk or negedge rst_n)
  if(!rst_n)rgb_out<=0;
  else rgb_out<=mapped;
endmodule
