// 赛题扩展：在图像上叠加半透明底栏和逐帧滚动的动态字幕。
// 输入 RGB、DE 和 VSYNC 均属于像素时钟域；输出与输入同拍。
module video_scroll_osd #(parameter SETTINGS_UI=0)(
 input wire clk,rst_n,de,vsync,input wire [23:0] rgb,
 input wire [2:0] image_count,input wire [1:0] image_index,
 input wire paused,wav_found,catalog_ready,image_valid,
 output wire [23:0] rgb_out,output wire [9:0] pixel_x,pixel_y,
 input wire [10:0] settings_word);
 reg [9:0] active_x,active_y,scroll;
 assign pixel_x=active_x;
 assign pixel_y=active_y;
 reg [8:0] status_frame;
 reg [10:0] settings_frame;
 reg de_prev,vsync_prev;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin
   active_x<=0;active_y<=0;scroll<=0;de_prev<=0;vsync_prev<=1;
   status_frame<=0;settings_frame<=0;
  end else begin
   de_prev<=de;vsync_prev<=vsync;
   if(!vsync)active_y<=0;
   else if(de_prev&&!de)active_y<=active_y+1'b1;
   if(de)active_x<=active_x+1'b1;else active_x<=0;
   if(vsync_prev&&!vsync)begin
    status_frame<={image_valid,image_count,image_index,paused,wav_found,catalog_ready};
    settings_frame<=SETTINGS_UI?settings_word:11'd0;
    if(scroll==10'd896)scroll<=0;
    else scroll<=scroll+10'd4;
   end
  end
 end

 // 16 个 8x8 字符各放大两倍：kskbl,zdjd，末尾留六个空格。
 // scroll 从 0 到 896 循环，使 256 像素宽的字幕从右向左穿过屏幕。
 wire [10:0] shifted_x={1'b0,active_x}+{1'b0,scroll};
 wire in_text_x=shifted_x>=11'd640 && shifted_x<11'd896;
 wire [7:0] text_x=shifted_x-11'd640;
 // 字幕只保存需要的小写字形，底部状态栏继续使用原字体。
 function [7:0] scroll_font_row;
  input [3:0] slot;
  input [2:0] row;
  begin
   scroll_font_row=0;
   case({slot,row})
    {4'd0,3'd0},{4'd0,3'd1},{4'd2,3'd0},{4'd2,3'd1}:scroll_font_row=8'h40; // k
    {4'd0,3'd2},{4'd0,3'd6},{4'd2,3'd2},{4'd2,3'd6}:scroll_font_row=8'h44;
    {4'd0,3'd3},{4'd0,3'd5},{4'd2,3'd3},{4'd2,3'd5}:scroll_font_row=8'h48;
    {4'd0,3'd4},{4'd2,3'd4}:scroll_font_row=8'h70;
    {4'd1,3'd2}:scroll_font_row=8'h3c; // s
    {4'd1,3'd3}:scroll_font_row=8'h40;
    {4'd1,3'd4}:scroll_font_row=8'h38;
    {4'd1,3'd5}:scroll_font_row=8'h04;
    {4'd1,3'd6}:scroll_font_row=8'h78;
    {4'd3,3'd0},{4'd3,3'd1}:scroll_font_row=8'h40; // b
    {4'd3,3'd2},{4'd3,3'd6}:scroll_font_row=8'h78;
    {4'd3,3'd3},{4'd3,3'd4},{4'd3,3'd5}:scroll_font_row=8'h44;
    {4'd4,3'd0}:scroll_font_row=8'h30; // l
    {4'd4,3'd1},{4'd4,3'd2},{4'd4,3'd3},{4'd4,3'd4},{4'd4,3'd5}:scroll_font_row=8'h10;
    {4'd4,3'd6}:scroll_font_row=8'h38;
    {4'd5,3'd5},{4'd5,3'd6}:scroll_font_row=8'h18; // comma
    {4'd5,3'd7}:scroll_font_row=8'h10;
    {4'd6,3'd2},{4'd6,3'd6}:scroll_font_row=8'h7c; // z
    {4'd6,3'd3}:scroll_font_row=8'h08;
    {4'd6,3'd4}:scroll_font_row=8'h10;
    {4'd6,3'd5}:scroll_font_row=8'h20;
    {4'd7,3'd0},{4'd7,3'd1},{4'd9,3'd0},{4'd9,3'd1}:scroll_font_row=8'h04; // d
    {4'd7,3'd2},{4'd7,3'd6},{4'd9,3'd2},{4'd9,3'd6}:scroll_font_row=8'h3c;
    {4'd7,3'd3},{4'd7,3'd4},{4'd7,3'd5},
    {4'd9,3'd3},{4'd9,3'd4},{4'd9,3'd5}:scroll_font_row=8'h44;
    {4'd8,3'd0},{4'd8,3'd3},{4'd8,3'd4}:scroll_font_row=8'h08; // j
    {4'd8,3'd2}:scroll_font_row=8'h18;
    {4'd8,3'd5}:scroll_font_row=8'h48;
    {4'd8,3'd6}:scroll_font_row=8'h30;
   endcase
  end
 endfunction
 function [7:0] font_row;
  input [4:0] letter;
  input [2:0] row;
  begin
   font_row=0;
   case({letter,row})
    {4'd1,3'd0}:font_row=8'b01111110;
    {4'd1,3'd1},{4'd1,3'd2},{4'd1,3'd4},{4'd1,3'd5}:font_row=8'b01000000;
    {4'd1,3'd3}:font_row=8'b01111100;
    {4'd1,3'd6}:font_row=8'b01111110;
    {4'd2,3'd0},{4'd2,3'd6}:font_row=8'b00111100;
    {4'd2,3'd1},{4'd2,3'd5}:font_row=8'b01000010;
    {4'd2,3'd2}:font_row=8'b01000000;
    {4'd2,3'd3}:font_row=8'b01001110;
    {4'd2,3'd4}:font_row=8'b01000010;
    {4'd3,3'd0}:font_row=8'b00001100;
    {4'd3,3'd1}:font_row=8'b00010100;
    {4'd3,3'd2}:font_row=8'b00100100;
    {4'd3,3'd3}:font_row=8'b01000100;
    {4'd3,3'd4}:font_row=8'b01111110;
    {4'd3,3'd5},{4'd3,3'd6}:font_row=8'b00000100;
    {4'd4,3'd0}:font_row=8'b00111110;
    {4'd4,3'd1},{4'd4,3'd2}:font_row=8'b01000000;
    {4'd4,3'd3}:font_row=8'b00111100;
    {4'd4,3'd4},{4'd4,3'd5}:font_row=8'b00000010;
    {4'd4,3'd6}:font_row=8'b01111100;
    {4'd5,3'd0}:font_row=8'b00111100;
    {4'd5,3'd1}:font_row=8'b01000010;
    {4'd5,3'd2}:font_row=8'b00000010;
    {4'd5,3'd3}:font_row=8'b00001100;
    {4'd5,3'd4}:font_row=8'b00110000;
    {4'd5,3'd5}:font_row=8'b01000000;
    {4'd5,3'd6}:font_row=8'b01111110;
    {4'd6,3'd0},{4'd6,3'd6}:font_row=8'b00111100;
    {4'd6,3'd1}:font_row=8'b01000010;
    {4'd6,3'd2}:font_row=8'b01000110;
    {4'd6,3'd3}:font_row=8'b01001010;
    {4'd6,3'd4}:font_row=8'b01010010;
    {4'd6,3'd5}:font_row=8'b01100010;
    {4'd7,3'd0},{4'd7,3'd1},{4'd7,3'd2},
    {4'd7,3'd4},{4'd7,3'd5},{4'd7,3'd6}:font_row=8'b01000010;
    {4'd7,3'd3}:font_row=8'b01111110;
    {4'd8,3'd0},{4'd8,3'd6}:font_row=8'b01111000;
    {4'd8,3'd1},{4'd8,3'd5}:font_row=8'b01000100;
    {4'd8,3'd2},{4'd8,3'd3},{4'd8,3'd4}:font_row=8'b01000010;
    {4'd9,3'd0},{4'd9,3'd3},{4'd9,3'd4},
    {4'd9,3'd5},{4'd9,3'd6}:font_row=8'b01000010;
    {4'd9,3'd1}:font_row=8'b01100110;
    {4'd9,3'd2}:font_row=8'b01011010;
    {4'd10,3'd0},{4'd10,3'd6}:font_row=8'b00111100;
    {4'd10,3'd1},{4'd10,3'd2},{4'd10,3'd3},
    {4'd10,3'd4},{4'd10,3'd5}:font_row=8'b00011000;
    {4'd11,3'd0},{4'd11,3'd6}:font_row=8'b00111100;
    {4'd11,3'd1},{4'd11,3'd2},{4'd11,3'd3},
    {4'd11,3'd4},{4'd11,3'd5}:font_row=8'b01000010;
    {5'd12,3'd0}:font_row=8'b00011000; // 1
    {5'd12,3'd1}:font_row=8'b00101000;
    {5'd12,3'd2},{5'd12,3'd3},{5'd12,3'd4},{5'd12,3'd5}:font_row=8'b00001000;
    {5'd12,3'd6}:font_row=8'b00111110;
    {5'd13,3'd0},{5'd13,3'd6}:font_row=8'b00111100; // 3
    {5'd13,3'd1},{5'd13,3'd5}:font_row=8'b01000010;
    {5'd13,3'd2},{5'd13,3'd4}:font_row=8'b00000010;
    {5'd13,3'd3}:font_row=8'b00011100;
    {5'd14,3'd0}:font_row=8'b01111110; // 5
    {5'd14,3'd1}:font_row=8'b01000000;
    {5'd14,3'd2}:font_row=8'b01111100;
    {5'd14,3'd3},{5'd14,3'd4}:font_row=8'b00000010;
    {5'd14,3'd5}:font_row=8'b01000010;
    {5'd14,3'd6}:font_row=8'b00111100;
    {5'd15,3'd0},{5'd15,3'd6}:font_row=8'b00111100; // 6
    {5'd15,3'd1}:font_row=8'b01000000;
    {5'd15,3'd2}:font_row=8'b01111100;
    {5'd15,3'd3},{5'd15,3'd4},{5'd15,3'd5}:font_row=8'b01000010;
    {5'd16,3'd0}:font_row=8'b01111110; // 7
    {5'd16,3'd1}:font_row=8'b00000010;
    {5'd16,3'd2}:font_row=8'b00000100;
    {5'd16,3'd3}:font_row=8'b00001000;
    {5'd16,3'd4},{5'd16,3'd5},{5'd16,3'd6}:font_row=8'b00010000;
    {5'd17,3'd0}:font_row=8'b00000010; // /
    {5'd17,3'd1},{5'd17,3'd2}:font_row=8'b00000100;
    {5'd17,3'd3}:font_row=8'b00001000;
    {5'd17,3'd4},{5'd17,3'd5}:font_row=8'b00010000;
    {5'd17,3'd6}:font_row=8'b00100000;
    {5'd18,3'd0},{5'd18,3'd3}:font_row=8'b01111100; // P
    {5'd18,3'd1},{5'd18,3'd2}:font_row=8'b01000010;
    {5'd18,3'd4},{5'd18,3'd5},{5'd18,3'd6}:font_row=8'b01000000;
    {5'd19,3'd0},{5'd19,3'd1},{5'd19,3'd2},
    {5'd19,3'd3},{5'd19,3'd4},{5'd19,3'd5}:font_row=8'b01000000; // L
    {5'd19,3'd6}:font_row=8'b01111110;
    {5'd20,3'd0}:font_row=8'b00111100; // A
    {5'd20,3'd1},{5'd20,3'd2},{5'd20,3'd4},
    {5'd20,3'd5},{5'd20,3'd6}:font_row=8'b01000010;
    {5'd20,3'd3}:font_row=8'b01111110;
    {5'd21,3'd0},{5'd21,3'd1}:font_row=8'b01000010; // Y
    {5'd21,3'd2}:font_row=8'b00100100;
    {5'd21,3'd3},{5'd21,3'd4},{5'd21,3'd5},{5'd21,3'd6}:font_row=8'b00011000;
    {5'd22,3'd0},{5'd22,3'd1},{5'd22,3'd2},
    {5'd22,3'd3},{5'd22,3'd4},{5'd22,3'd5}:font_row=8'b01000010; // U
    {5'd22,3'd6}:font_row=8'b00111100;
    {5'd23,3'd0},{5'd23,3'd1},{5'd23,3'd6}:font_row=8'b01000010; // W
    {5'd23,3'd2},{5'd23,3'd3}:font_row=8'b01011010;
    {5'd23,3'd4},{5'd23,3'd5}:font_row=8'b01100110;
    {5'd24,3'd0},{5'd24,3'd1},{5'd24,3'd2}:font_row=8'b01000010; // V
    {5'd24,3'd3},{5'd24,3'd4}:font_row=8'b00100100;
    {5'd24,3'd5},{5'd24,3'd6}:font_row=8'b00011000;
    {5'd25,3'd0}:font_row=8'b01111110; // T
    {5'd25,3'd1},{5'd25,3'd2},{5'd25,3'd3},
    {5'd25,3'd4},{5'd25,3'd5},{5'd25,3'd6}:font_row=8'b00011000;
    {5'd26,3'd0},{5'd26,3'd5},{5'd26,3'd6}:font_row=8'b01000010; // N
    {5'd26,3'd1}:font_row=8'b01100010;
    {5'd26,3'd2}:font_row=8'b01010010;
    {5'd26,3'd3}:font_row=8'b01001010;
    {5'd26,3'd4}:font_row=8'b01000110;
    {5'd27,3'd0},{5'd27,3'd3},{5'd27,3'd6}:font_row=8'h7c; // B
    {5'd27,3'd1},{5'd27,3'd2},{5'd27,3'd4},{5'd27,3'd5}:font_row=8'h42;
    {5'd28,3'd0},{5'd28,3'd3}:font_row=8'h7c; // R
    {5'd28,3'd1},{5'd28,3'd2}:font_row=8'h42;
    {5'd28,3'd4}:font_row=8'h48;
    {5'd28,3'd5}:font_row=8'h44;
    {5'd28,3'd6}:font_row=8'h42;
    {5'd29,3'd0},{5'd29,3'd6}:font_row=8'h3c; // C
    {5'd29,3'd1},{5'd29,3'd5}:font_row=8'h42;
    {5'd29,3'd2},{5'd29,3'd3},{5'd29,3'd4}:font_row=8'h40;
    {5'd30,3'd0}:font_row=8'h7e; // F
    {5'd30,3'd1},{5'd30,3'd2},{5'd30,3'd4},{5'd30,3'd5},{5'd30,3'd6}:font_row=8'h40;
    {5'd30,3'd3}:font_row=8'h7c;
    {5'd31,3'd0},{5'd31,3'd6}:font_row=8'h42; // K
    {5'd31,3'd1},{5'd31,3'd5}:font_row=8'h44;
    {5'd31,3'd2},{5'd31,3'd4}:font_row=8'h48;
    {5'd31,3'd3}:font_row=8'h70;
   endcase
  end
 endfunction
 function [4:0] digit_glyph;
  input [2:0] digit;
  begin
   case(digit)
    3'd0:digit_glyph=5'd6;
    3'd1:digit_glyph=5'd12;
    3'd2:digit_glyph=5'd5;
    3'd3:digit_glyph=5'd13;
    3'd4:digit_glyph=5'd3;
    3'd5:digit_glyph=5'd14;
    3'd6:digit_glyph=5'd15;
    default:digit_glyph=5'd16;
   endcase
  end
 endfunction
 wire [7:0] row_pixels=scroll_font_row(text_x[7:4],active_y[3:1]);
 wire lit=in_text_x && active_y>=10'd32 && active_y<10'd48 &&
  row_pixels[3'd7-text_x[3:1]];
 // A fixed 18-character status line: IMG n/N PLAY|PAUSE WAV|TONE|WAIT.
 // Its inputs are a coherent pixel-domain word; show a new word only at VSYNC.
 wire [2:0] shown_index=(!status_frame[8] || status_frame[7:5]==0)?3'd0:
  {1'b0,status_frame[4:3]}+3'd1;
 wire [9:0] status_x=active_x-10'd16;
 wire [3:0] status_y=active_y-10'd440;
 // Small fixed panel reuses the status font lookup; no full-screen buffer.
 wire panel=SETTINGS_UI && settings_frame[10] &&
  active_x>=10'd160 && active_x<10'd480 && active_y>=10'd112 && active_y<10'd352;
 wire [9:0] menu_x=active_x-10'd176,menu_y=active_y-10'd128;
 wire [2:0] menu_line=menu_y[7:5];
 wire menu_label=panel && active_x>=10'd176 && active_x<10'd304 && !menu_y[4];
 wire selected=panel && menu_line>=1 && menu_line<=4 &&
  {1'b0,settings_frame[9:8]}==menu_line-1'b1;
 reg [4:0] menu_glyph;
 always @* begin
  menu_glyph=0;
  case({menu_line,menu_x[6:4]})
   {3'd0,3'd0}:menu_glyph=4; // SETUP
   {3'd0,3'd1}:menu_glyph=1;
   {3'd0,3'd2}:menu_glyph=25;
   {3'd0,3'd3}:menu_glyph=22;
   {3'd0,3'd4}:menu_glyph=18;
   {3'd1,3'd0}:menu_glyph=27; // BRIGHT
   {3'd1,3'd1}:menu_glyph=28;
   {3'd1,3'd2}:menu_glyph=10;
   {3'd1,3'd3}:menu_glyph=2;
   {3'd1,3'd4}:menu_glyph=7;
   {3'd1,3'd5}:menu_glyph=25;
   {3'd2,3'd0}:menu_glyph=29; // CONTRAST
   {3'd2,3'd1}:menu_glyph=11;
   {3'd2,3'd2}:menu_glyph=26;
   {3'd2,3'd3}:menu_glyph=25;
   {3'd2,3'd4}:menu_glyph=28;
   {3'd2,3'd5}:menu_glyph=20;
   {3'd2,3'd6}:menu_glyph=4;
   {3'd2,3'd7}:menu_glyph=25;
   {3'd3,3'd0}:menu_glyph=30; // FADE
   {3'd3,3'd1}:menu_glyph=20;
   {3'd3,3'd2}:menu_glyph=8;
   {3'd3,3'd3}:menu_glyph=1;
   {3'd4,3'd0}:menu_glyph=23; // WAVE
   {3'd4,3'd1}:menu_glyph=20;
   {3'd4,3'd2}:menu_glyph=24;
   {3'd4,3'd3}:menu_glyph=1;
   {3'd6,3'd0}:menu_glyph=11; // OK
   {3'd6,3'd1}:menu_glyph=31;
  endcase
 end
 reg [4:0] status_glyph;
 always @* begin
  status_glyph=0;
  case(status_x[8:4])
   5'd0:status_glyph=5'd10; // I
   5'd1:status_glyph=5'd9;  // M
   5'd2:status_glyph=5'd2;  // G
   5'd4:status_glyph=digit_glyph(shown_index);
   5'd5:status_glyph=5'd17; // /
   5'd6:status_glyph=digit_glyph(status_frame[7:5]);
   5'd8:status_glyph=5'd18; // P
   5'd9:status_glyph=status_frame[2]?5'd20:5'd19; // A/L
   5'd10:status_glyph=status_frame[2]?5'd22:5'd20; // U/A
   5'd11:status_glyph=status_frame[2]?5'd4:5'd21; // S/Y
   5'd12:status_glyph=status_frame[2]?5'd1:5'd0; // E/space
   5'd14:status_glyph=status_frame[0]&&!status_frame[1]?5'd25:5'd23; // T/W
   5'd15:status_glyph=status_frame[0]&&!status_frame[1]?5'd11:5'd20; // O/A
   5'd16:status_glyph=!status_frame[0]?5'd10:
    (status_frame[1]?5'd24:5'd26); // I/V/N
   5'd17:status_glyph=!status_frame[0]?5'd25:
    (status_frame[1]?5'd0:5'd1); // T/space/E
   default:status_glyph=0;
  endcase
  if(menu_label)status_glyph=menu_glyph;
 end
 wire [7:0] status_row=font_row(status_glyph,menu_label?menu_y[3:1]:status_y[3:1]);
 wire status_lit=active_x>=10'd16 && active_x<10'd304 &&
  active_y>=10'd440 && active_y<10'd456 &&
  status_row[3'd7-status_x[3:1]];
 wire [23:0] dim_rgb={1'b0,rgb[23:17],1'b0,rgb[15:9],1'b0,rgb[7:1]};
 wire menu_lit=menu_label && status_row[3'd7-menu_x[3:1]];
 wire [9:0] bar_x=active_x-10'd336;
 wire in_bar=panel && active_x>=10'd336 && active_x<10'd456 &&
  menu_y[4:0]>=4 && menu_y[4:0]<12;
 wire [2:0] level=(menu_line==1)?settings_frame[7:5]:settings_frame[4:2];
 wire bar_lit=in_bar && ((menu_line==1 || menu_line==2)?
  ((bar_x<16 && level==0)||(bar_x>=24 && bar_x<40 && level==1)||
   (bar_x>=48 && bar_x<64 && level==2)||(bar_x>=72 && bar_x<88 && level==3)||
   (bar_x>=96 && bar_x<112 && level==4)):
  ((menu_line==3 && settings_frame[1])||(menu_line==4 && settings_frame[0])));
 assign rgb_out=(de && panel)?
  (menu_lit?24'hffffff:(bar_lit?24'hffe040:(selected?24'h184058:24'h101820))):
  (de && active_y>=10'd24 && active_y<10'd56)?
  (lit?24'hffe040:dim_rgb):
  ((de && active_y>=10'd432 && active_y<10'd464)?
   (status_lit?24'h80e8ff:dim_rgb):rgb);
endmodule
