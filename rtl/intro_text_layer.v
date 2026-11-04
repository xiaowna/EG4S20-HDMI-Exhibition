// Antialiased Chinese introduction, composed before the shared pixel FIFO.
// Five enabled clock edges from input to output. ce freezes the whole pipeline,
// including both synchronous ROMs, so downstream backpressure cannot lose tags.
module intro_text_layer #(parameter CAPTION_BITMAP=0)(
 input wire clk,rst_n,ce,valid_in,
 input wire [18:0] pixel_addr,input wire [9:0] pixel_x,input wire [8:0] pixel_y,
 input wire [23:0] rgb_in,input wire [1:0] topic,
 input wire [6:0] text_offset,input wire [5:0] text_alpha,
 input wire caption_pixel,input wire [5:0] caption_alpha,
 output wire valid_out,output wire [18:0] addr_out,output reg [23:0] rgb_out);
 localparam NONE=0,HEADING=1,BODY=2,UNDERLINE=3;
 wire [10:0] lx={1'b0,pixel_x}-(11'd352+{4'd0,text_offset});
 wire [9:0] ly={1'b0,pixel_y}-10'd101;
 reg [1:0] kind;
 reg [2:0] text_row;
 reg [4:0] glyph_y;
 always @*begin
  kind=NONE;text_row=0;glyph_y=0;
  if(lx<128&&ly<24)kind=HEADING;
  else if(lx<100&&ly>=26&&ly<28)kind=UNDERLINE;
  else if(lx<240)begin
   if(ly>=36&&ly<56)begin kind=BODY;text_row=0;glyph_y=ly-36;end
   else if(ly>=59&&ly<79)begin kind=BODY;text_row=1;glyph_y=ly-59;end
   else if(ly>=82&&ly<102)begin kind=BODY;text_row=2;glyph_y=ly-82;end
   else if(ly>=105&&ly<125)begin kind=BODY;text_row=3;glyph_y=ly-105;end
   else if(ly>=128&&ly<148)begin kind=BODY;text_row=4;glyph_y=ly-128;end
   else if(ly>=151&&ly<171)begin kind=BODY;text_row=5;glyph_y=ly-151;end
  end
 end
 wire [6:0] cell_number=({4'd0,text_row}<<4)-text_row+{3'd0,lx[7:4]};
 wire [8:0] character_address={topic,7'd0}+{2'd0,cell_number};
 wire [15:0] character_data,glyph_data;
 intro_character_rom characters(.clk(clk),.en(ce),.address(character_address),.data(character_data));
 reg [1:0] kind1,kind2,topic1,topic2;
 reg [6:0] local_x1;
 reg [4:0] local_y1,glyph_y1;
 reg [2:0] bit2;
 reg [5:0] alpha1,alpha2;
 reg caption1,caption2;
 wire input_caption=CAPTION_BITMAP&&caption_pixel;
 wire [12:0] glyph_base=({5'd0,character_data[7:0]}<<5)+({5'd0,character_data[7:0]}<<3);
 wire [12:0] glyph_address=(kind1==HEADING)?
  (13'd7680+{4'd0,local_y1,4'd0}+{9'd0,local_x1[6:3]}):
  (glyph_base+{7'd0,glyph_y1,1'b0}+{12'd0,local_x1[3]});
 intro_glyph_rom glyphs(.clk(clk),.en(ce),.address(glyph_address),.data(glyph_data));
 wire [15:0] shifted_glyph=glyph_data>>{bit2,1'b0};
 wire [1:0] coverage=caption2?2'd3:((kind2==NONE)?2'd0:((kind2==UNDERLINE)?2'd3:shifted_glyph[1:0]));
 function [5:0] coverage_weight;
  input [1:0] value;
  begin case(value)0:coverage_weight=0;1:coverage_weight=11;
   2:coverage_weight=21;default:coverage_weight=32;endcase end
 endfunction
 function [23:0] accent;
  input [1:0] value;
  begin case(value)0:accent=24'hedbb6e;1:accent=24'hdaa185;
   2:accent=24'h88c8e0;default:accent=24'hb6ade2;endcase end
 endfunction
 reg [4:0] valid_pipe;
 reg [18:0] addresses[0:4];
 reg [23:0] bg1,bg2,bg3,bg4,fg3;
 reg [11:0] alpha_product;
 wire [12:0] rounded_alpha={1'b0,alpha_product}+13'd16;
 wire [5:0] effective_alpha=rounded_alpha[10:5];
 wire signed [8:0] diff_r=$signed({1'b0,fg3[23:16]})-$signed({1'b0,bg3[23:16]});
 wire signed [8:0] diff_g=$signed({1'b0,fg3[15:8]})-$signed({1'b0,bg3[15:8]});
 wire signed [8:0] diff_b=$signed({1'b0,fg3[7:0]})-$signed({1'b0,bg3[7:0]});
 reg signed [15:0] product_r,product_g,product_b;
 wire signed [16:0] rounded_r=$signed({product_r[15],product_r})+17'sd16;
 wire signed [16:0] rounded_g=$signed({product_g[15],product_g})+17'sd16;
 wire signed [16:0] rounded_b=$signed({product_b[15],product_b})+17'sd16;
 wire signed [16:0] result_r=$signed({9'd0,bg4[23:16]})+(rounded_r>>>5);
 wire signed [16:0] result_g=$signed({9'd0,bg4[15:8]})+(rounded_g>>>5);
 wire signed [16:0] result_b=$signed({9'd0,bg4[7:0]})+(rounded_b>>>5);
 assign valid_out=valid_pipe[4];
 assign addr_out=addresses[4];
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)valid_pipe<=0;
  else if(ce)valid_pipe<={valid_pipe[3:0],valid_in};
 end
 // Datapaths deliberately have no reset. Validity masks stale RAM/DSP words.
 always @(posedge clk)if(ce)begin
  addresses[0]<=pixel_addr;
  for(i=1;i<5;i=i+1)addresses[i]<=addresses[i-1];
  kind1<=kind;kind2<=kind1;topic1<=topic;topic2<=topic1;
  local_x1<=lx[6:0];local_y1<=ly[4:0];glyph_y1<=glyph_y;
  bit2<=local_x1[2:0];alpha1<=input_caption?caption_alpha:text_alpha;alpha2<=alpha1;
  caption1<=input_caption;caption2<=caption1;
  bg1<=rgb_in;bg2<=bg1;bg3<=caption2?24'h060c14:bg2;bg4<=bg3;
  fg3<=caption2?bg2:((kind2==BODY)?24'hdae3e9:accent(topic2));
  alpha_product<=coverage_weight(coverage)*alpha2;
  product_r<=diff_r*$signed({1'b0,effective_alpha});
  product_g<=diff_g*$signed({1'b0,effective_alpha});
  product_b<=diff_b*$signed({1'b0,effective_alpha});
  rgb_out<={result_r[7:0],result_g[7:0],result_b[7:0]};
 end
endmodule
