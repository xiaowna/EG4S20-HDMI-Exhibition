// Debounced KEY1 right, KEY2 OK, KEY3 left, KEY4 settings/back.
// Settings apply immediately and survive leaving the menu, until reset.
module media_adjust_control #(parameter AUTOPLAY_MENU=0,parameter MUSIC_MENU=0,parameter RTC_MENU=0,parameter HOME_UI=0,parameter FINE_ADJUST=0,parameter AUTOPLAY_INTERVAL_MENU=0)(
 input wire clk,rst_n,input wire [3:0] key_press,
 output reg signed [8:0] cfg_value,
 output reg [8:0] cfg_gain_q8,
 output reg cfg_fade_enabled,cfg_wave_enabled,cfg_update,
 output wire setting_active,output wire [1:0] setting_page,
 output wire next_event,prev_event,pause_event,
 input wire product_mode,mode_change,output reg cfg_autoplay,output wire autoplay_page,
 input wire [2:0] music_count,output wire music_page,
 output reg [1:0] cfg_music_index,output reg cfg_music_request,
 output wire rtc_page,input wire rtc_exit,home_play,input wire [1:0] home_music_index,
 input wire frame_tick,input wire [3:0] held_key_n,output reg [6:0] contrast_index,
 output reg [2:0] autoplay_interval);
 localparam NORMAL=0,BRIGHT=1,CONTRAST=2,FADE=3,WAVE=4,AUTO=5,MUSIC=6,RTC=7;
 reg [2:0] state;
 wire pressed_right=key_press[0]&&!key_press[2];
 wire pressed_left=key_press[2]&&!key_press[0];
 // Repeat only physical LEFT/RIGHT in numeric settings. A held key must be
 // released after entry/page changes; encoder/IR events remain single steps.
 reg repeat_armed;reg [4:0] repeat_delay;reg [1:0] repeat_direction;
 wire numeric=state==BRIGHT||state==CONTRAST;
 wire held_right=held_key_n==4'b1110,held_left=held_key_n==4'b1011;
 wire repeat_matches=(repeat_direction==1&&held_right)||(repeat_direction==2&&held_left);
 wire repeating=FINE_ADJUST&&numeric&&repeat_armed&&repeat_matches&&frame_tick&&repeat_delay==0&&key_press==0;
 wire right=pressed_right||(repeating&&held_right);
 wire left=pressed_left||(repeating&&held_left);
 // g = round(percent*256/100). Advancing one percent adds 2 or 3 Q8 units.
 // Tracking remainder modulo 25 avoids a multiplier or divider in control.
 reg [4:0] gain_remainder;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin repeat_armed<=0;repeat_delay<=0;repeat_direction<=0;end
  else if(!FINE_ADJUST||!numeric||key_press[3]||key_press[1]||mode_change||(HOME_UI&&home_play))begin
   repeat_armed<=0;repeat_delay<=0;repeat_direction<=0;
  end else if(held_key_n==4'hf)begin repeat_armed<=1;repeat_delay<=0;repeat_direction<=0;end
  else if(!held_right&&!held_left)begin repeat_armed<=0;repeat_delay<=0;repeat_direction<=0;end
  else if(repeat_armed)begin
   if(repeat_direction!=0&&!repeat_matches)begin repeat_armed<=0;repeat_direction<=0;repeat_delay<=0;end
   else if((pressed_right&&held_right)||(pressed_left&&held_left))begin
    repeat_delay<=5'd20;repeat_direction<=held_right?2'd1:2'd2;
   end else if(frame_tick&&repeat_matches)begin
    if(repeat_delay!=0)repeat_delay<=repeat_delay-1'b1;
    else repeat_delay<=5'd1;
   end
  end
 end
 assign setting_active=(state!=NORMAL);
 assign setting_page=state[1:0]-1'b1;
 assign autoplay_page=AUTOPLAY_MENU&&(state==AUTO);
 assign music_page=MUSIC_MENU&&(state==MUSIC);
 assign rtc_page=RTC_MENU&&(state==RTC);
 assign next_event=(state==NORMAL)&&!key_press[3]&&!key_press[1]&&right;
 assign prev_event=(state==NORMAL)&&!key_press[3]&&!key_press[1]&&left;
 assign pause_event=(state==NORMAL)&&!key_press[3]&&key_press[1];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=NORMAL;cfg_value<=0;cfg_gain_q8<=9'd256;
   cfg_fade_enabled<=0;cfg_wave_enabled<=0;cfg_update<=0;cfg_autoplay<=0;autoplay_interval<=3'd1;
   cfg_music_index<=0;cfg_music_request<=0;contrast_index<=7'd50;gain_remainder<=5'd12;
  end else begin
   cfg_update<=0;cfg_music_request<=0;
   if(AUTOPLAY_MENU&&mode_change)begin state<=NORMAL;cfg_autoplay<=0;end
   else if(HOME_UI&&home_play)begin state<=NORMAL;cfg_autoplay<=1;cfg_music_index<=home_music_index;end
   else if(RTC_MENU&&state==RTC)begin
    if(rtc_exit)state<=NORMAL;
   end
   else if(key_press[3])state<=(state==NORMAL)?BRIGHT:NORMAL;
   else if(state!=NORMAL && key_press[1])begin
    if(state==MUSIC || (state==AUTO&&(!MUSIC_MENU||!product_mode)) ||
       (state==WAVE&&(!AUTOPLAY_MENU||!product_mode)))state<=RTC_MENU?RTC:NORMAL;
    else state<=state+1'b1;
   end
   else case(state)
    NORMAL:;
    BRIGHT:begin
     if(right && cfg_value<9'sd64)begin cfg_value<=cfg_value+(FINE_ADJUST?9'sd1:9'sd32);cfg_update<=1;end
     else if(left && cfg_value>-9'sd64)begin cfg_value<=cfg_value-(FINE_ADJUST?9'sd1:9'sd32);cfg_update<=1;end
    end
    CONTRAST:begin
     if(FINE_ADJUST)begin
      if(right&&contrast_index<100)begin
       contrast_index<=contrast_index+1'b1;cfg_update<=1;
       cfg_gain_q8<=cfg_gain_q8+((gain_remainder>=11)?9'd3:9'd2);
       gain_remainder<=(gain_remainder>=11)?gain_remainder-5'd11:gain_remainder+5'd14;
      end else if(left&&contrast_index>0)begin
       contrast_index<=contrast_index-1'b1;cfg_update<=1;
       cfg_gain_q8<=cfg_gain_q8-((gain_remainder<14)?9'd3:9'd2);
       gain_remainder<=(gain_remainder<14)?gain_remainder+5'd11:gain_remainder-5'd14;
      end
     end else begin
      if(right && cfg_gain_q8<9'd384)begin cfg_gain_q8<=cfg_gain_q8+9'd64;cfg_update<=1;end
      else if(left && cfg_gain_q8>9'd128)begin cfg_gain_q8<=cfg_gain_q8-9'd64;cfg_update<=1;end
     end
    end
    FADE:begin
     if((right && !cfg_fade_enabled)||(left && cfg_fade_enabled))begin
      cfg_fade_enabled<=right;cfg_update<=1;
     end
    end
    WAVE:begin
     if((right && !cfg_wave_enabled)||(left && cfg_wave_enabled))begin
      cfg_wave_enabled<=right;cfg_update<=1;
     end
    end
    AUTO:if(AUTOPLAY_MENU&&product_mode)begin
     if(AUTOPLAY_INTERVAL_MENU)begin
      // Off, 3, 5, 10, 15, 30 seconds. The album entry uses the last interval.
      if(right&&!cfg_autoplay)begin cfg_autoplay<=1;autoplay_interval<=0;cfg_update<=1;end
      else if(right&&autoplay_interval<4)begin autoplay_interval<=autoplay_interval+1'b1;cfg_update<=1;end
      else if(left&&cfg_autoplay)begin
       if(autoplay_interval==0)cfg_autoplay<=0;
       else autoplay_interval<=autoplay_interval-1'b1;
       cfg_update<=1;
      end
     end else if((right&&!cfg_autoplay)||(left&&cfg_autoplay))begin cfg_autoplay<=right;cfg_update<=1;end
    end
    MUSIC:if(MUSIC_MENU&&product_mode&&music_count>1&&music_count<=4)begin
     if(right || left)begin
      if(right)cfg_music_index<=({1'b0,cfg_music_index}+1>=music_count)?0:cfg_music_index+1'b1;
      else cfg_music_index<=(cfg_music_index==0)?music_count-1'b1:cfg_music_index-1'b1;
      cfg_music_request<=1;
     end
    end
    default:state<=NORMAL;
   endcase
  end
 end
endmodule
