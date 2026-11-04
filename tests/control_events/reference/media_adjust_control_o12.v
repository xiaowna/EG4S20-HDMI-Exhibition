// Debounced KEY1 right, KEY2 OK, KEY3 left, KEY4 settings/back.
// Settings apply immediately and survive leaving the menu, until reset.
module media_adjust_control_o12(
 input wire clk,rst_n,input wire [3:0] key_press,
 output reg signed [8:0] cfg_value,
 output reg [8:0] cfg_gain_q8,
 output reg cfg_fade_enabled,cfg_wave_enabled,cfg_update,
 output wire setting_active,output wire [1:0] setting_page,
 output wire next_event,prev_event,pause_event);
 localparam NORMAL=0,BRIGHT=1,CONTRAST=2,FADE=3,WAVE=4;
 reg [2:0] state;
 wire right=key_press[0]&&!key_press[2];
 wire left=key_press[2]&&!key_press[0];
 assign setting_active=(state!=NORMAL);
 assign setting_page=state[1:0]-1'b1;
 assign next_event=(state==NORMAL)&&!key_press[3]&&!key_press[1]&&right;
 assign prev_event=(state==NORMAL)&&!key_press[3]&&!key_press[1]&&left;
 assign pause_event=(state==NORMAL)&&!key_press[3]&&key_press[1];
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=NORMAL;cfg_value<=0;cfg_gain_q8<=9'd256;
   cfg_fade_enabled<=0;cfg_wave_enabled<=0;cfg_update<=0;
  end else begin
   cfg_update<=0;
   if(key_press[3])state<=(state==NORMAL)?BRIGHT:NORMAL;
   else if(state!=NORMAL && key_press[1])state<=(state==WAVE)?NORMAL:state+1'b1;
   else case(state)
    NORMAL:;
    BRIGHT:begin
     if(right && cfg_value<9'sd64)begin cfg_value<=cfg_value+9'sd32;cfg_update<=1;end
     else if(left && cfg_value>-9'sd64)begin cfg_value<=cfg_value-9'sd32;cfg_update<=1;end
    end
    CONTRAST:begin
     if(right && cfg_gain_q8<9'd384)begin cfg_gain_q8<=cfg_gain_q8+9'd64;cfg_update<=1;end
     else if(left && cfg_gain_q8>9'd128)begin cfg_gain_q8<=cfg_gain_q8-9'd64;cfg_update<=1;end
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
    default:state<=NORMAL;
   endcase
  end
 end
endmodule
