// Parallel, one-clock home overlay; no additional HDMI pixel latency.
// A 256-pixel periodic strip makes carousel coordinates shifts/additions only.
module video_home #(parameter EXHIBIT=0)(input wire clk,rst_n,de,vsync,input wire [9:0] x,y,
 input wire [14:0] home_word,output wire [23:0] rgb_out,output wire overlay_valid,
 input wire easter_toggle,output wire easter_valid);
 reg [14:0] frame;
 reg vs_prev;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin frame<=0;vs_prev<=1;end
  else begin vs_prev<=vsync;if(vs_prev&&!vsync)begin
   frame<=home_word;
  end end
 (* async_reg="true" *) reg [1:0] egg_sync;
 reg egg_seen,egg_active;reg [7:0] egg_frame;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin egg_sync<=0;egg_seen<=0;egg_active<=0;egg_frame<=0;end
  else begin
   egg_sync<={egg_sync[0],easter_toggle};
   if(vs_prev&&!vsync)begin
    if(egg_sync[1]!=egg_seen)begin egg_seen<=egg_sync[1];egg_active<=1;egg_frame<=0;end
    else if(egg_active)begin
     if(egg_frame==239)egg_active<=0;else egg_frame<=egg_frame+1'b1;
    end
   end
  end
 wire [2:0] state=EXHIBIT?{1'b0,frame[12:11]}:frame[13:11],index=frame[3:1];
 wire moving=frame[10],backward=frame[9];
 function [8:0] ease;
  input [4:0] phase;
  begin case(phase)
   0:ease=0;1:ease=2;2:ease=9;3:ease=19;4:ease=32;5:ease=48;
   6:ease=66;7:ease=86;8:ease=107;9:ease=128;10:ease=149;11:ease=170;
   12:ease=190;13:ease=208;14:ease=224;15:ease=237;16:ease=247;
   17:ease=254;default:ease=256;
  endcase end
 endfunction
 wire [8:0] fraction=ease(frame[8:4]);
 wire [8:0] distance=moving?fraction:9'd0;
 wire reverse=moving&&backward;
 wire [9:0] world=x+10'd64+(reverse?(10'd256-{1'b0,distance}):{1'b0,distance});
 wire [2:0] base=reverse?((index>=2)?index-3'd2:index+3'd3):((index==0)?3'd4:index-1'b1);
 wire [3:0] sum={1'b0,base}+{2'b0,world[9:8]};
 wire [2:0] tile=(sum>=5)?sum-4'd5:sum[2:0];
 wire [7:0] local_x=world[7:0];
 wire card=local_x>=16&&local_x<240&&y>=144&&y<352&&
  ((local_x>=24&&local_x<232)||(y>=152&&y<344));
 wire border=card&&(local_x<19||local_x>=237||y<147||y>=349);
 wire focus=x>=204&&x<436&&y>=140&&y<356&&
  (x<208||x>=432||y<144||y>=352);
 wire center=x>=208&&x<432;
 wire tile_window=local_x>=64&&local_x<192&&y>=176&&y<304;
 wire title_window=EXHIBIT?(x>=320&&x<544&&y>=32&&y<96):(x>=192&&x<448&&y>=48&&y<112);
 wire footer_window=x>=256&&x<384&&y>=400&&y<432;
 wire status_window=x>=256&&x<384&&y>=364&&y<380&&(state==1||frame[0]);
 wire competition=EXHIBIT&&x>=8&&x<312&&y>=16&&y<120;
 wire challenge=EXHIBIT&&x>=552&&x<624&&y>=76&&y<124;
 wire [7:0] competition_u=(x-10'd8)>>1;
 wire [6:0] competition_v=(y-10'd16)>>1;
 wire [6:0] challenge_u=(x-10'd552)>>1,challenge_v=(y-10'd76)>>1;
 wire [16:0] competition_address=17'd98304+({10'd0,competition_v}<<7)+
  ({10'd0,competition_v}<<4)+({10'd0,competition_v}<<3)+{9'd0,competition_u};
 wire [6:0] tile_y=y-10'd176,title_x=(x-(EXHIBIT?10'd320:10'd192))>>1,
  title_y=(y-(EXHIBIT?10'd32:10'd48))>>1;
 wire [6:0] footer_x=x-10'd256,footer_y=y-10'd336;
 wire [3:0] status_y=y-10'd364;
 wire egg_panel=egg_active&&x>=152&&x<488&&y>=192&&y<256;
 wire egg_text=egg_active&&x>=176&&x<464&&y>=208&&y<240;
 wire [8:0] egg_x=x-10'd176;wire [4:0] egg_y=y-10'd208;
 wire [3:0] egg_glyph=egg_x[8:5];
 wire [2:0] egg_column=(egg_glyph>=5)?egg_glyph-4'd5:egg_glyph[2:0];
 wire [6:0] egg_u={egg_column,egg_x[4:1]},egg_v={2'b11,(egg_glyph>=5),egg_y[4:1]};
 // Both bursts occupy disjoint screen halves, so one arithmetic unit draws
 // them with different centres/phases. No multipliers or particle framebuffer.
 wire spark_right=x>=320;
 wire [5:0] spark_phase=egg_frame[5:0]+(spark_right?6'd32:6'd0);
 function spark;
  input [9:0] px,py,cx,cy;input [5:0] age;
  reg [9:0] dx,dy;reg [6:0] radius,diagonal;
  begin
   dx=(px>=cx)?px-cx:cx-px;dy=(py>=cy)?py-cy:cy-py;
   radius={age,1'b0}+7'd4;diagonal=(radius>>1)+(radius>>2);
   spark=age<48&&(((dx<=1)&&(dy+6>=radius)&&(dy<=radius))||
    ((dy<=1)&&(dx+6>=radius)&&(dx<=radius))||
    ((dx+1>=dy)&&(dy+1>=dx)&&(dx+4>=diagonal)&&(dx<=diagonal)));
  end
 endfunction
 wire fireworks=egg_active&&spark(x,y,spark_right?10'd480:10'd160,
  spark_right?10'd128:10'd144,spark_phase);
 wire [23:0] spark_bright=spark_right?(egg_frame[6]?24'hd9a8ff:24'h8ae7ff):
  (egg_frame[6]?24'hff9ebc:24'hffd26a);
 wire [23:0] spark_rgb=spark_phase<16?24'hfff0c2:
  ((spark_phase<32)?spark_bright:((spark_bright>>1)&24'h7f7f7f));
 reg [16:0] address;
 always @*begin
  address={tile,tile_y,{~world[6],world[5:0]}};
  if(title_window)address={3'd5,title_y,title_x};
  else if(footer_window)address={3'd5,footer_y,footer_x};
  else if(status_window)address={3'd5,(state==1?3'b011:3'b010),status_y,footer_x};
  if(competition)address=competition_address;
  else if(challenge)address={3'd5,(7'd96+challenge_v),(7'd92+challenge_u)};
  if(egg_text)address={3'd5,egg_v,egg_u};
 end
 wire ink;
 home_assets_rom assets(.clk(clk),.address(address),.pixel(ink));
 reg [23:0] base_rgb,text_rgb;
 reg [23:0] base_q,text_q;
 reg text_window_q,home_cover_q,egg_cover_q;
 always @*begin
  base_rgb=(y[5:0]==0)?24'h122431:24'h0b1420;
  if(card)begin
   case(tile)
    0:base_rgb=24'h193c3c;1:base_rgb=24'h213a4c;2:base_rgb=24'h343a4f;
    3:base_rgb=24'h453d37;default:base_rgb=24'h263f40;
   endcase
   if(border)base_rgb=24'h3b5363;
  end
  if(focus)base_rgb=24'h70d6bc;
  if(EXHIBIT&&x>=544&&x<632&&y>=68&&y<132)base_rgb=24'hf5f7fa;
  // Five small position markers, with the committed selection emphasized.
  if(y>=328&&y<332&&x>=280&&x<360&&x[3:0]>=8)
   base_rgb=((x-10'd280)>>4)==index?24'hb6e7d7:24'h405865;
  text_rgb=center?24'he7efec:24'h93a9b4;
  if(title_window)text_rgb=24'hb6e7d7;
  if(footer_window)text_rgb=24'h93a9b4;
  if(status_window)text_rgb=frame[0]?24'he5a89b:24'hb6e7d7;
  if(competition)text_rgb=24'h3b91d8;
  if(challenge)text_rgb=({challenge_u,1'b0}>(8'd25+{1'b0,challenge_v}))?24'he51b2b:24'h1d2d50;
  if(fireworks)base_rgb=spark_rgb;
  if(egg_panel)begin
   base_rgb=(x<154||x>=486||y<194||y>=254)?24'h70d6bc:24'h162737;
   text_rgb=24'he7efec;
  end
 end
 // 640*fraction/256 = 2*fraction + fraction/2, exactly at phase endpoints.
 wire [9:0] reveal={fraction,1'b0}+{2'b0,fraction[8:1]};
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin base_q<=0;text_q<=0;text_window_q<=0;home_cover_q<=0;egg_cover_q<=0;end
  else begin
   base_q<=base_rgb;text_q<=text_rgb;
   text_window_q<=egg_text||(!(egg_panel||fireworks)&&
    (tile_window||title_window||footer_window||status_window||competition||challenge));
   home_cover_q<=de&&frame[14]&&((state==2)?x>=reveal:((state==4)?x<reveal:1'b1));
   egg_cover_q<=de&&(egg_panel||fireworks);
  end
 assign overlay_valid=home_cover_q||egg_cover_q;
 assign easter_valid=egg_cover_q;
 assign rgb_out=(text_window_q&&ink)?text_q:base_q;
endmodule
