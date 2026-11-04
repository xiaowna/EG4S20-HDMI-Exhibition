// A transparent 16px Chinese subtitle, one pixel per frame, one ROM-read stage.
// x/y, DE, VSYNC and RGB must describe the same input pixel.
module video_chinese_subtitle #(parameter SOFT_EDGES=0)(
 input wire clk,rst_n,de,vsync,input wire [9:0] x,y,
 input wire [23:0] rgb_in,output wire [23:0] rgb_out);
 reg [9:0] scroll;
 reg vsync_prev;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin scroll<=0;vsync_prev<=1;end
  else begin
   vsync_prev<=vsync;
   if(vsync_prev&&!vsync)scroll<=(scroll==10'd512)?10'd0:scroll+1'b1;
  end
 end
 // Left header [16,304); the clock starts at x=320, leaving a 16px gap.
 // Native 16px glyphs keep the existing font and avoid another scaling stage.
 wire [10:0] shifted_x={1'b0,x}+{1'b0,scroll};
 wire [10:0] text_x=shifted_x-11'd304;
 wire [3:0] font_y=y[3:0]-4'd8;
 wire text_window=de && x>=10'd16 && x<10'd304 && y>=10'd8 && y<10'd24 &&
  shifted_x>=11'd304 && shifted_x<11'd528;
 wire [1:0] font_pixel;
 subtitle_font_rom font(.clk(clk),.address({text_x[7:4],font_y,text_x[3:0]}),.pixel(font_pixel));
 reg inside_q;
 reg [23:0] rgb_q;
 reg [4:0] alpha_q;
 // Thirty-two pixels at either edge form a transparent feather. At the
 // loop boundary the last pixels are already invisible, avoiding a hard cut.
 wire [9:0] left_distance=x-10'd16,right_distance=10'd303-x;
 wire [9:0] edge_distance=(left_distance<right_distance)?left_distance:right_distance;
 wire [4:0] edge_alpha=(edge_distance>=32)?5'd16:edge_distance[5:1];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin inside_q<=0;rgb_q<=0;alpha_q<=0;end
  else begin inside_q<=text_window;rgb_q<=rgb_in;alpha_q<=edge_alpha;end
 end
 function [7:0] blend;
  input [7:0] background,foreground;input [4:0] alpha;
  reg signed [8:0] difference;reg signed [14:0] product;reg signed [15:0] result;
  begin
   difference=$signed({1'b0,foreground})-$signed({1'b0,background});
   product=difference*$signed({1'b0,alpha});
   result=$signed({8'd0,background})+(($signed({product[14],product})+16'sd8)>>>4);
   blend=result[7:0];
  end
 endfunction
 wire [23:0] ink=(font_pixel==2'd2)?24'he7efec:24'h0b1420;
 wire [23:0] softened={blend(rgb_q[23:16],ink[23:16],alpha_q),
  blend(rgb_q[15:8],ink[15:8],alpha_q),blend(rgb_q[7:0],ink[7:0],alpha_q)};
 assign rgb_out=(inside_q&&font_pixel!=0)?(SOFT_EDGES?softened:ink):rgb_q;
endmodule
