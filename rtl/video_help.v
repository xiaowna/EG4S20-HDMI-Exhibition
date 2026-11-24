// Two synchronous ROM reads, fed one pixel earlier than the other overlays.
// Page changes commit only during vertical blank, never halfway down a page.
module video_help(input wire clk,rst_n,de,vsync,input wire [9:0] x,y,
 input wire [2:0] help_word,input wire hint_enable,
 output wire [23:0] rgb_out,output wire overlay_valid);
 reg [2:0] frame;
 reg vs_prev;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin frame<=0;vs_prev<=1;end
  else begin vs_prev<=vsync;if(vs_prev&&!vsync)frame<=help_word;end
 wire active=frame[2];
 wire hint=!active&&hint_enable&&y>=448&&y<464&&x>=64&&x<576;
 wire text_area=active&&x>=64&&x<576&&y>=48&&y<432;
 wire [8:0] u=x-10'd64,v=y-10'd48;
 wire [1:0] text_page=hint?2'd3:frame[1:0];
 wire [4:0] text_row=hint?5'd31:v[8:4];
 wire [11:0] character_address={text_page,text_row,u[8:4]};
 wire [15:0] characters;
 help_character_rom text(.clk(clk),.en(1'b1),.address(character_address[11:1]),.data(characters));
 reg half_q;
 reg [3:0] x_q,y_q,x_qq;
 reg text_q,text_qq,cover_q,cover_qq,accent_q,accent_qq;
 wire [7:0] glyph=half_q?characters[15:8]:characters[7:0];
 wire [15:0] low_rows,high_rows;
 help_glyph_bank0 low_font(.clk(clk),.en(1'b1),.address({glyph[6:0],y_q}),.data(low_rows));
 help_glyph_bank1 high_font(.clk(clk),.en(1'b1),.address({glyph[6:0],y_q}),.data(high_rows));
 reg bank_q;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin
   half_q<=0;x_q<=0;y_q<=0;x_qq<=0;bank_q<=0;
   text_q<=0;text_qq<=0;cover_q<=0;cover_qq<=0;accent_q<=0;accent_qq<=0;
  end else begin
   half_q<=character_address[0];x_q<=u[3:0];y_q<=hint?y[3:0]:v[3:0];
   x_qq<=x_q;bank_q<=glyph[7];
   text_q<=de&&(text_area||hint);text_qq<=text_q;
   cover_q<=de&&(active||hint);cover_qq<=cover_q;
   accent_q<=hint||v[8:4]==0||v[8:4]==23;accent_qq<=accent_q;
  end
 wire ink=bank_q?high_rows[x_qq]:low_rows[x_qq];
 assign rgb_out=(text_qq&&ink)?(accent_qq?24'h70d6bc:24'he7efec):24'h0b1420;
 assign overlay_valid=cover_qq;
endmodule
