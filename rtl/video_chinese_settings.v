// Fixed Chinese settings panel. RGB, coordinates and DE/VS describe one pixel.
// One synchronous font read runs in parallel with the subtitle, not in series.
module video_chinese_settings #(parameter SPECTRUM_FFT=0,parameter MUSIC_MENU=0,parameter RTC_OVERLAY=0,parameter RTC_SETTING=0,parameter COMPACT_ROWS=0,parameter FINE_ADJUST=0,parameter MUSIC_TOAST=0,parameter AUTOPLAY_INTERVAL_MENU=0)(
 input wire clk,rst_n,de,vsync,input wire [9:0] x,y,input wire [23:0] rgb_in,
 input wire [10:0] settings_word,input wire [3:0] mode_status,
 output wire [23:0] rgb_out,output wire overlay_valid,input wire [7:0] music_status,
 input wire [48:0] rtc_word,input wire [53:0] rtc_edit_word,input wire [14:0] fine_adjust_word,
 input wire [14:0] home_word,input wire music_playing,input wire [3:0] autoplay_word);
 reg [10:0] settings_frame;
 reg [3:0] mode_frame;
 reg [7:0] music_frame;
 reg [48:0] rtc_frame;
 reg [53:0] edit_frame;
 reg [14:0] fine_frame;
 reg [3:0] autoplay_frame;
 reg vsync_prev;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin settings_frame<=0;mode_frame<=0;music_frame<=0;rtc_frame<=0;edit_frame<=0;fine_frame<={8'd64,7'd50};autoplay_frame<=0;vsync_prev<=1;end
  else begin
   vsync_prev<=vsync;
   if(vsync_prev&&!vsync)begin settings_frame<=settings_word;mode_frame<=mode_status;
    music_frame<=MUSIC_MENU?music_status:8'd0;end
   // The board's 50/25 MHz clocks share one PLL. This complete registered
   // source word crosses a fully timed path, then freezes for a whole frame.
   if(vsync_prev&&!vsync)rtc_frame<=RTC_OVERLAY?rtc_word:49'd0;
   if(vsync_prev&&!vsync)edit_frame<=RTC_SETTING?rtc_edit_word:54'd0;
   if(vsync_prev&&!vsync)fine_frame<=FINE_ADJUST?fine_adjust_word:15'd0;
   if(vsync_prev&&!vsync)autoplay_frame<=AUTOPLAY_INTERVAL_MENU?autoplay_word:4'd0;
  end
 end
 wire toast_active;wire [4:0] toast_alpha;wire [2:0] toast_pose;wire [1:0] toast_track;
 generate if(MUSIC_TOAST)begin:music_notice
  // 25MHz/(800*525): 238 full frames = 3.9984s, then 60 fade frames = 1.008s.
  // Pause/resume and WAV loops keep `seen`; a new album or accepted track
  // starts a notice only once the actual WAV is playing and the menu closes.
  reg [8:0] age;reg seen;reg [1:0] track;reg playing_frame;
  always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin age<=298;seen<=0;track<=0;playing_frame<=0;end
   else if(vsync_prev&&!vsync)begin
    playing_frame<=music_playing;
    if(!mode_status[2]||home_word[14]||music_status[4:2]==0)begin age<=298;seen<=0;end
    else if(settings_word[10]||mode_status[3])age<=298;
    else if(music_playing&&(!seen||track!=music_status[1:0]))begin
     age<=0;seen<=1;track<=music_status[1:0];
    end else if(age<298)age<=age+1'b1;
   end
  end
  wire [8:0] remaining=9'd298-age;
  wire [8:0] rounded=remaining+9'd3;
  assign toast_active=age<298&&playing_frame;
  assign toast_alpha=age<238?5'd16:{1'b0,rounded[5:2]};
  assign toast_pose=age[5:3];assign toast_track=track;
 end else begin:no_music_notice
  assign toast_active=0;assign toast_alpha=0;assign toast_pose=0;assign toast_track=0;
 end endgenerate
 wire toast_window=toast_active&&x>=16&&x<176&&y>=40&&y<88&&
  ((x>=22&&x<170)||(y>=46&&y<82));
 wire toast_border=toast_window&&(x<18||x>=174||y<42||y>=86);
 wire [9:0] note_x=x-10'd28,note_y=y-10'd48,music_x=x-10'd80;
 wire [7:0] brightness_digits;wire [11:0] contrast_digits;
 generate if(FINE_ADJUST)begin:fine_numbers
  // Convert two small binary values once per frame, sharing one BCD shifter.
  // Sixteen pixel clocks finish well inside the fixed vertical blanking.
  reg busy,second;reg [2:0] step;reg [7:0] binary;
  reg [11:0] bcd;reg [7:0] bright_bcd;reg [11:0] contrast_bcd;
  function [11:0] shifted_bcd;
   input [11:0] value;input next_bit;reg [11:0] t;integer k;
   begin
    t=value;
    for(k=0;k<3;k=k+1)if(t[k*4+:4]>=5)t[k*4+:4]=t[k*4+:4]+4'd3;
    shifted_bcd={t[10:0],next_bit};
   end
  endfunction
  wire [11:0] next_bcd=shifted_bcd(bcd,binary[7]);
  always @(posedge clk or negedge rst_n)begin
   if(!rst_n)begin busy<=0;second<=0;step<=0;binary<=0;bcd<=0;bright_bcd<=0;contrast_bcd<=12'h100;end
   else if(vsync_prev&&!vsync)begin
    busy<=1;second<=0;step<=0;bcd<=0;
    binary<=(fine_adjust_word[14:7]>=64)?fine_adjust_word[14:7]-8'd64:8'd64-fine_adjust_word[14:7];
   end else if(busy)begin
    binary<={binary[6:0],1'b0};bcd<=next_bcd;step<=step+1'b1;
    if(step==7)begin
     if(!second)begin
      bright_bcd<=next_bcd[7:0];second<=1;binary<={1'b0,fine_frame[6:0]}+8'd50;bcd<=0;
     end else begin contrast_bcd<=next_bcd;busy<=0;end
    end
   end
  end
  assign brightness_digits=bright_bcd;assign contrast_digits=contrast_bcd;
 end else begin:coarse_numbers
  assign brightness_digits=0;assign contrast_digits=0;
 end endgenerate
 // Encoded glyph IDs are fixed by assets/settings_v02.json.
 localparam [5:0] SP=0,BO=1,FANG=2,SHE=3,ZHI=4,LIANG=5,DU=6,DUI=7,BI=8,
  QIE=9,TU=10,JIAN=11,BIAN=12,YIN=13,PIN=14,BO_WAVE=15,XING=16,
  ZI=17,DONG=18,LUN=19,KAI=20,QI=21,GUAN=22,TIAO=26,JIE=27,
  XIA=30,XIANG=31,FAN=32,HUI=33,CHAN=34,PIN_PRODUCT=35,YAN=36,SHI=37,
  N0=38,N1=39,N2=40,N3=41,N4=42,N5=43,N6=44,N7=45,
  PLUS=48,MINUS=49,PERCENT=52,K=53,LEFT=54,RIGHT=55;
 // BI is contrast's 比; CLOSED is 闭.
 localparam [5:0] CLOSED=23,CAI=56,SE=57,PU=58,BEI=59,JING=60,YUE=61,SLASH=51;
 reg [2:0] row_index;
 reg [9:0] row_y;
 always @*begin
  if(COMPACT_ROWS)begin row_index=y[7:5]-3'd5;row_y={5'd0,y[4:0]};end
  else if(y<200)begin row_index=0;row_y=y-10'd160;end
  else if(y<240)begin row_index=1;row_y=y-10'd200;end
  else if(y<280)begin row_index=2;row_y=y-10'd240;end
  else if(y<320)begin row_index=3;row_y=y-10'd280;end
  else if(!MUSIC_MENU || y<360)begin row_index=4;row_y=y-10'd320;end
  else if(!RTC_SETTING||y<400)begin row_index=5;row_y=y-10'd360;end
  else begin row_index=6;row_y=y-10'd400;end
 end
 wire disabled_row=((row_index==4)||(MUSIC_MENU&&row_index==5))&&
  (!mode_frame[2] || (row_index==5&&music_frame[4:2]==0));
 wire switch_on=(row_index==2)?settings_frame[1]:
  ((row_index==3)?settings_frame[0]:((AUTOPLAY_INTERVAL_MENU&&mode_frame[2])?autoplay_frame[3]:mode_frame[0]));
 wire show_autoplay_seconds=AUTOPLAY_INTERVAL_MENU&&row_index==4&&mode_frame[2]&&autoplay_frame[3];
 reg [9:0] selected_top;
 always @*begin
  if(COMPACT_ROWS)begin
   if(MUSIC_MENU&&music_frame[7])selected_top=316;
   else if(mode_frame[1])selected_top=284;
   else selected_top={3'd0,settings_frame[9:8],5'd0}+10'd156;
  end else if(MUSIC_MENU&&music_frame[7])selected_top=356;
  else if(mode_frame[1])selected_top=316;
  else case(settings_frame[9:8])
   0:selected_top=156;1:selected_top=196;2:selected_top=236;default:selected_top=276;
  endcase
 end
 wire selected=x>=128&&x<512&&y>=selected_top&&y<selected_top+(COMPACT_ROWS?10'd32:10'd40);
 localparam PANEL_BOTTOM=COMPACT_ROWS?432:(RTC_SETTING?472:(MUSIC_MENU?464:424)),
  FOOTER_TOP=COMPACT_ROWS?400:(RTC_SETTING?448:(MUSIC_MENU?424:384));
 wire editing=RTC_SETTING&&edit_frame[53];
 wire panel=x>=112&&x<528&&y>=80&&y<PANEL_BOTTOM&&
  ((x>=120&&x<520)||(y>=88&&y<PANEL_BOTTOM-8));
 wire panel_inner=x>=114&&x<526&&y>=82&&y<PANEL_BOTTOM-2&&
  ((x>=122&&x<518)||(y>=90&&y<PANEL_BOTTOM-10));
 wire shadow=x>=120&&x<536&&y>=88&&y<PANEL_BOTTOM+8&&
  ((x>=128&&x<528)||(y>=96&&y<PANEL_BOTTOM));
 wire [2:0] level=(row_index==0)?settings_frame[7:5]:settings_frame[4:2];
 reg [9:0] fill_end;
 always @*case(level)
  0:fill_end=364;1:fill_end=388;2:fill_end=412;3:fill_end=436;default:fill_end=460;
 endcase
 wire [12:0] contrast_span={fine_frame[6:0],5'd0}+{fine_frame[6:0],3'd0}+fine_frame[6:0];
 wire [7:0] fine_fill=(row_index==0)?fine_frame[14:7]:contrast_span[12:5];
 wire [9:0] fine_bar_x=x-10'd344;
 wire bar=x>=344&&x<(FINE_ADJUST?472:464)&&row_y>=26&&row_y<30&&row_index<2&&y>=160;
 wire bar_gap=!FINE_ADJUST&&((x>=364&&x<368)||(x>=388&&x<392)||(x>=412&&x<416)||
  (x>=436&&x<440)||(x>=460&&x<464));
 wire toggle=x>=344&&x<396&&row_y>=8&&row_y<24&&row_index>=2&&row_index<5&&y<(COMPACT_ROWS?320:352);
 wire knob=toggle&&row_y>=10&&row_y<22&&
  (switch_on?(x>=380&&x<392):(x>=348&&x<360));
 reg [23:0] base_rgb,foreground;
 always @*begin
  base_rgb={1'b0,rgb_in[23:17],1'b0,rgb_in[15:9],1'b0,rgb_in[7:1]};
  if(panel)begin
   base_rgb=24'h162737;
   if(!panel_inner)base_rgb=24'h3b5363;
   else if(y>=148&&y<150&&x>=128&&x<512)base_rgb=24'h3b5363;
   else if(y>=FOOTER_TOP-20&&y<FOOTER_TOP-18&&x>=128&&x<512)base_rgb=24'h3b5363;
   else if(x>=416&&x<496&&y>=100&&y<132)base_rgb=24'h203641;
   else if(selected)base_rgb=(x<132)?24'h70d6bc:24'h203f47;
   if(bar)base_rgb=bar_gap?24'h162737:((FINE_ADJUST?(fine_bar_x<{2'd0,fine_fill}):(x<fill_end))?24'h70d6bc:24'h405865);
   if(toggle)base_rgb=disabled_row?24'h405865:(switch_on?24'h347e6c:24'h405865);
   if(knob)base_rgb=disabled_row?24'h8298a4:24'hedf6ef;
   if(editing&&panel_inner)base_rgb=24'h162737;
  end
  foreground=disabled_row?24'h8298a4:24'he7efec;
 end
 reg [23:0] label_word,value_word;
 always @*begin
  case(row_index)
   0:label_word={LIANG,DU,SP,SP};
   1:label_word={DUI,BI,DU,SP};
   2:label_word={QIE,TU,JIAN,BIAN};
   3:label_word=SPECTRUM_FFT?{CAI,SE,PIN,PU}:{YIN,PIN,BO_WAVE,XING};
   4:label_word={ZI,DONG,LUN,BO};
   default:label_word={BEI,JING,YIN,YUE};
  endcase
  value_word={SP,SP,SP,SP};
  if(FINE_ADJUST&&row_index==0)begin
   if(brightness_digits==0)value_word={SP,SP,SP,N0};
   else if(brightness_digits[7:4]==0)value_word={SP,SP,(fine_frame[14:7]<64?MINUS:PLUS),N0+{2'b0,brightness_digits[3:0]}};
   else value_word={SP,(fine_frame[14:7]<64?MINUS:PLUS),N0+{2'b0,brightness_digits[7:4]},N0+{2'b0,brightness_digits[3:0]}};
  end else if(FINE_ADJUST&&row_index==1)begin
   value_word={(contrast_digits[11:8]==0?SP:N0+{2'b0,contrast_digits[11:8]}),
    N0+{2'b0,contrast_digits[7:4]},N0+{2'b0,contrast_digits[3:0]},PERCENT};
  end else if(row_index==0)case(level)
   0:value_word={SP,MINUS,N6,N4};1:value_word={SP,MINUS,N3,N2};
   2:value_word={SP,SP,SP,N0};3:value_word={SP,PLUS,N3,N2};
   default:value_word={SP,PLUS,N6,N4};
  endcase
  else if(row_index==1)case(level)
   0:value_word={SP,N5,N0,PERCENT};1:value_word={SP,N7,N5,PERCENT};
   2:value_word={N1,N0,N0,PERCENT};3:value_word={N1,N2,N5,PERCENT};
   default:value_word={N1,N5,N0,PERCENT};
  endcase
  else if(MUSIC_MENU&&row_index==5)
   value_word={(music_frame[4:2]==0?N0:N1+{4'd0,music_frame[6:5]}),SLASH,
    (N0+{3'd0,music_frame[4:2]}),SP};
  else value_word=switch_on?{KAI,QI,SP,SP}:{GUAN,CLOSED,SP,SP};
 end
 function [5:0] word_char;
  input [23:0] word;input [1:0] col;
  begin case(col)
   0:word_char=word[23:18];1:word_char=word[17:12];
   2:word_char=word[11:6];default:word_char=word[5:0];
  endcase end
 endfunction
 function [5:0] footer_char;
  input [4:0] col;
  begin case(col)
   0:footer_char=LEFT;1:footer_char=RIGHT;2:footer_char=TIAO;3:footer_char=JIE;
   6:footer_char=K;7:footer_char=N2;8:footer_char=XIA;9:footer_char=XIANG;
   12:footer_char=K;13:footer_char=N4;14:footer_char=FAN;15:footer_char=HUI;
   default:footer_char=SP;
  endcase end
 endfunction
 reg [6:0] glyph;
 reg [5:0] interval_tens,interval_ones;
 always @*begin
  case(autoplay_frame[2:0])
   0:begin interval_tens=SP;interval_ones=N3;end
   2:begin interval_tens=N1;interval_ones=N0;end
   3:begin interval_tens=N1;interval_ones=N5;end
   4:begin interval_tens=N3;interval_ones=N0;end
   default:begin interval_tens=SP;interval_ones=N5;end
  endcase
 end
 reg [3:0] font_x,font_y;
 reg text_window;
 reg [23:0] text_color;
 wire [9:0] label_x=x-10'd152,value_x=x-10'd416,title_x=x-10'd144;
 wire [9:0] footer_x=x-10'd192,tag_x=x-10'd440;
 wire [9:0] title_y=y-10'd104,tag_y=y-10'd108,footer_y=y-FOOTER_TOP;
 wire rtc_window=RTC_OVERLAY&&x>=320&&x<624&&y>=8&&y<24;
 wire [9:0] rtc_x=x-10'd320;
 wire [9:0] date_x=x-10'd160,time_x=x-10'd192,button_x=x-10'd216;
 wire edit_date=editing&&x>=160&&x<480&&y>=192&&y<224;
 wire edit_time=editing&&x>=192&&x<448&&y>=264&&y<296;
 wire [4:0] rtc_col=edit_date?date_x[8:5]:(edit_time?({2'b0,time_x[7:5]}+5'd11):rtc_x[8:4]);
 wire [48:0] display_time=(edit_date||edit_time)?{1'b1,edit_frame[47:0]}:rtc_frame;
 reg [2:0] digit_field;
 reg [3:0] rtc_digit;
 reg [5:0] rtc_glyph;
 always @*begin
  rtc_digit=0;
  case(rtc_col)
   0:rtc_digit=2;1:rtc_digit=0;
   2:rtc_digit=display_time[47:44];3:rtc_digit=display_time[43:40];
   5:rtc_digit=display_time[39:36];6:rtc_digit=display_time[35:32];
   8:rtc_digit=display_time[31:28];9:rtc_digit=display_time[27:24];
   11:rtc_digit=display_time[23:20];12:rtc_digit=display_time[19:16];
   14:rtc_digit=display_time[15:12];15:rtc_digit=display_time[11:8];
   17:rtc_digit=display_time[7:4];18:rtc_digit=display_time[3:0];
  endcase
  rtc_glyph=display_time[48]?(N0+{2'b0,rtc_digit}):MINUS;
  case(rtc_col)
   4,7:rtc_glyph=MINUS;
   10:rtc_glyph=SP;
   13,16:rtc_glyph=6'd62; // ':' occupies a previously unused ROM slot.
  endcase
  if(rtc_col<4)digit_field=0;
  else if(rtc_col<7)digit_field=1;
  else if(rtc_col<10)digit_field=2;
  else if(rtc_col<13)digit_field=3;
  else if(rtc_col<16)digit_field=4;
  else digit_field=5;
 end
 always @*begin
  glyph=SP;font_x=0;font_y=0;text_window=0;text_color=foreground;
  if(toast_window)begin
   if(x>=28&&x<60&&y>=48&&y<80)begin
    glyph=7'd74+{4'd0,toast_pose};font_x=note_x[4:1];font_y=note_y[4:1];text_window=1;text_color=24'h70d6bc;
   end else if(x>=80&&x<128&&y>=56&&y<72)begin
    case(music_x[5:4])
     0:glyph=YIN;1:glyph=YUE;default:glyph=N1+{4'd0,toast_track};
    endcase
    font_x=music_x[3:0];font_y=y-10'd56;text_window=1;text_color=24'he7efec;
   end
  end else if(rtc_window)begin
   glyph=rtc_glyph;font_x=rtc_x[3:0];font_y=y-10'd8;
   text_window=1;text_color=rtc_frame[48]?24'hc8ddd7:24'h93a9b4;
  end else if(editing)begin
   if(x>=144&&x<272&&y>=104&&y<136)begin
    case(title_x[6:5])
     0:glyph=64;1:glyph=65;2:glyph=SHE;default:glyph=ZHI;
    endcase
    font_x=title_x[4:1];font_y=title_y[4:1];text_window=1;text_color=24'h70d6bc;
   end else if(edit_date||edit_time)begin
    glyph=rtc_glyph;font_x=edit_date?date_x[4:1]:time_x[4:1];font_y=edit_date?((y-10'd192)>>1):((y-10'd264)>>1);
    text_window=1;text_color=(edit_frame[50:48]==digit_field)?24'h70d6bc:24'he7efec;
   end else if(y>=348&&y<380&&((x>=216&&x<280)||(x>=360&&x<424)))begin
    if(x<280)begin glyph=button_x[5]?67:66;font_x=button_x[4:1];end
    else begin glyph=(x-10'd360)>=32?HUI:FAN;font_x=(x-10'd360)>>1;end
    font_y=(y-10'd348)>>1;text_window=1;
    text_color=((x<280&&edit_frame[50:48]==6)||(x>=360&&edit_frame[50:48]==7))?24'h70d6bc:24'he7efec;
   end else if(x>=304&&x<336&&y>=312&&y<328&&edit_frame[52:51]!=0)begin
    case(edit_frame[52:51])
     1:glyph=x<320?68:69;2:glyph=x<320?70:71;default:glyph=x<320?72:73;
    endcase
    font_x=x[3:0];font_y=(y-10'd312);text_window=1;
    text_color=(edit_frame[52:51]==3)?24'he5a89b:24'hb6e7d7;
   end else if(x>=192&&x<448&&y>=FOOTER_TOP&&y<FOOTER_TOP+16)begin
    glyph=footer_char(footer_x[7:4]);font_x=footer_x[3:0];font_y=footer_y[3:0];
    text_window=1;text_color=24'h93a9b4;
   end
  end else if(x>=144&&x<272&&y>=104&&y<136)begin
   glyph=word_char({BO,FANG,SHE,ZHI},title_x[6:5]);
   font_x=title_x[4:1];font_y=title_y[4:1];text_window=1;text_color=24'h70d6bc;
  end else if(x>=440&&x<472&&y>=108&&y<124)begin
   glyph=tag_x[4]?(mode_frame[2]?PIN_PRODUCT:SHI):(mode_frame[2]?CHAN:YAN);
   font_x=tag_x[3:0];font_y=tag_y[3:0];text_window=1;text_color=24'hb6e7d7;
  end else if(x>=152&&x<280&&y>=160&&y<(COMPACT_ROWS?(RTC_SETTING?384:(MUSIC_MENU?352:320)):(RTC_SETTING?432:(MUSIC_MENU?392:352)))&&row_y<32)begin
   if(RTC_SETTING&&row_index==6)case(label_x[6:5])
    0:glyph=64;1:glyph=65;2:glyph=SHE;default:glyph=ZHI;
   endcase
   else glyph=word_char(label_word,label_x[6:5]);
   font_x=label_x[4:1];font_y=row_y[4:1];text_window=1;
  end else if(x>=416&&x<480&&y>=160&&y<(COMPACT_ROWS?(MUSIC_MENU?352:320):(MUSIC_MENU?392:352)))begin
   if(show_autoplay_seconds)begin
    if(row_y>=8&&row_y<24&&value_x<48)begin
     case(value_x[5:4])
      0:glyph=interval_tens;1:glyph=interval_ones;default:glyph=7'd82; // 秒
     endcase
     font_x=value_x[3:0];font_y=row_y-10'd8;text_window=1;
    end
   end else if((row_index<2 || (MUSIC_MENU&&row_index==5))&&row_y>=4&&row_y<20)begin
    glyph=word_char(value_word,value_x[5:4]);
    font_x=value_x[3:0];font_y=row_y-10'd4;text_window=1;
    if(MUSIC_MENU&&row_index==5&&music_frame[6:5]!=music_frame[1:0])text_color=24'hb6e7d7;
   end else if(row_index>=2&&row_index<5&&row_y<32)begin
    glyph=word_char(value_word,{1'b0,value_x[5]});
    font_x=value_x[4:1];font_y=row_y[4:1];text_window=1;
   end
  end else if(x>=192&&x<448&&y>=FOOTER_TOP&&y<FOOTER_TOP+16)begin
   glyph=footer_char(footer_x[7:4]);font_x=footer_x[3:0];font_y=footer_y[3:0];
   text_window=1;text_color=24'h93a9b4;
  end
 end
 wire font_pixel;
 settings_font_rom #(.CLOCK_FONT(RTC_SETTING||AUTOPLAY_INTERVAL_MENU)) font(.clk(clk),.address({glyph,font_y,font_x}),.pixel(font_pixel));
 reg [23:0] base_q,color_q;
 reg text_q,overlay_q,clock_only_q,toast_q,border_q;reg [4:0] alpha_q;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin overlay_q<=0;clock_only_q<=0;base_q<=0;color_q<=0;text_q<=0;toast_q<=0;border_q<=0;alpha_q<=0;end
  else begin
   overlay_q<=de&&((settings_frame[10]&&(panel||shadow))||rtc_window||toast_window);
   clock_only_q<=rtc_window;
   base_q<=(rtc_window||toast_window)?rgb_in:base_rgb;color_q<=text_color;text_q<=text_window;
   toast_q<=toast_window;border_q<=toast_border;alpha_q<=toast_alpha;
  end
 end
 function [7:0] blend;
  input [7:0] foreground,background;input [4:0] alpha;
  reg signed [8:0] delta;reg signed [14:0] product,total;
  begin
   delta=$signed({1'b0,foreground})-$signed({1'b0,background});
   product=delta*$signed({1'b0,alpha});total=$signed({1'b0,background})+(product>>>4);
   blend=total[7:0];
  end
 endfunction
 wire [23:0] toast_color=(text_q&&font_pixel)?color_q:(border_q?24'h3b5363:24'h162737);
 assign rgb_out=toast_q?{blend(toast_color[23:16],base_q[23:16],alpha_q),
  blend(toast_color[15:8],base_q[15:8],alpha_q),blend(toast_color[7:0],base_q[7:0],alpha_q)}:
  ((text_q&&font_pixel)?color_q:base_q);
 // The home composition keeps the pixels between clock glyphs transparent.
 assign overlay_valid=overlay_q&&(!COMPACT_ROWS||!clock_only_q||font_pixel);
endmodule
