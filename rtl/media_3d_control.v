// Four physical directions orbit the camera. KEY10 restores the initial view.
// KEY1/3 adjust time speed; IR up/down can adjust it in settings.
// Optional remote directions use the same camera actions in either model.
// Keep the existing AV wires: yaw=azimuth, pitch={elevation[3:0],speed[2:0]}.
module media_3d_control #(parameter INITIAL_YAW=7'd12,INITIAL_PITCH=7'd83,
 parameter HOLD_FRAMES=12,REPEAT_FRAMES=2,GENERAL_KEYS=0,DIRECTION_KEYS=0)(
 input wire clk,rst_n,enable,frame_tick,pause_controls,
 input wire [4:0] key_press,key_stable_n,
 input wire right_pulse,left_pulse,ok_pulse,
 input wire [3:0] direction_pulse,input wire [1:0] menu_speed,
 input wire [2:0] scene_key_press,input wire zoom_toggle,
 output reg scene_mode,output reg [1:0] zoom,
 output reg [6:0] yaw,pitch);
 localparam integer MAX_DELAY=(HOLD_FRAMES>REPEAT_FRAMES)?HOLD_FRAMES:REPEAT_FRAMES;
 localparam integer TIMER_BITS=(MAX_DELAY>1)?$clog2(MAX_DELAY):1;
 reg [TIMER_BITS-1:0] repeat_delay;
 reg armed;
 reg [2:0] preset_index;
 function [10:0] preset_view;
  input [2:0] n;
  begin case(n)
   1:preset_view={7'd12,4'd2};
   2:preset_view={7'd0,4'd8};
   3:preset_view={7'd32,4'd8};
   4:preset_view={7'd64,4'd8};
   5:preset_view={7'd96,4'd8};
   6:preset_view={7'd12,4'd15};
   7:preset_view={7'd76,4'd4};
   default:preset_view={INITIAL_YAW[6:0],INITIAL_PITCH[6:3]};
  endcase end
 endfunction
 wire [10:0] next_view=preset_view(preset_index+3'd1);
 wire [4:0] held=~key_stable_n;
 wire press_valid=key_press==5'b00001||key_press==5'b00010||key_press==5'b00100||
  key_press==5'b01000||key_press==5'b10000;
 wire held_direction=held==5'b00001||held==5'b00100||held==5'b01000||held==5'b10000;
 wire repeated=frame_tick&&held_direction&&repeat_delay==0;
 wire [4:0] action=armed?(press_valid?key_press:(repeated?held:5'd0)):5'd0;
 wire direction_valid=direction_pulse==4'b0001||direction_pulse==4'b0010||
  direction_pulse==4'b0100||direction_pulse==4'b1000;
 wire [4:0] remote_action=(DIRECTION_KEYS&&armed&&direction_valid)?
  {direction_pulse[3:1],1'b0,direction_pulse[0]}:5'd0;
 wire [4:0] rotation_action=(action!=0)?action:remote_action;
 wire right_command=GENERAL_KEYS&&right_pulse;
 wire left_command=GENERAL_KEYS&&left_pulse;
 wire ok_command=GENERAL_KEYS&&ok_pulse;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin yaw<=INITIAL_YAW;pitch<=INITIAL_PITCH;repeat_delay<=0;armed<=0;preset_index<=0;scene_mode<=0;zoom<=1;end
  else if(!enable)begin
   yaw<=INITIAL_YAW;pitch<=INITIAL_PITCH;repeat_delay<=0;armed<=0;preset_index<=0;scene_mode<=0;zoom<=1;
  end else if(pause_controls)begin
   armed<=0;repeat_delay<=0;
   if(menu_speed==2'b01&&pitch[2:0]<7)pitch[2:0]<=pitch[2:0]+1'b1;
   else if(menu_speed==2'b10&&pitch[2:0]!=0)pitch[2:0]<=pitch[2:0]-1'b1;
  end
  else begin
   if(held==0)begin armed<=1;repeat_delay<=0;end
   else if(armed)begin
    if(press_valid)repeat_delay<=(HOLD_FRAMES>0)?HOLD_FRAMES-1:0;
    else if(!held_direction)repeat_delay<=0;
    else if(frame_tick)begin
     if(repeat_delay!=0)repeat_delay<=repeat_delay-1'b1;
     else repeat_delay<=(REPEAT_FRAMES>0)?REPEAT_FRAMES-1:0;
    end
   end
   // Atomic priority: reset, physical controls, remote direction, general command.
   if(action==5'b00010)begin yaw<=scene_mode?7'd0:INITIAL_YAW;pitch<=scene_mode?{4'd3,INITIAL_PITCH[2:0]}:INITIAL_PITCH;preset_index<=0;zoom<=1;end
   else if(armed&&scene_key_press==3'b001)begin
    scene_mode<=!scene_mode;zoom<=1;preset_index<=0;
    yaw<=scene_mode?INITIAL_YAW:7'd0;pitch[6:3]<=scene_mode?INITIAL_PITCH[6:3]:4'd3;
   end
   else if(armed&&scene_key_press==3'b010)begin if(zoom!=0)zoom<=zoom-1'b1;end
   else if(armed&&scene_key_press==3'b100)begin if(zoom<2)zoom<=zoom+1'b1;end
   else if(armed&&zoom_toggle)zoom<=(zoom==2)?2'd1:2'd2;
   else if(rotation_action==5'b01000)begin if(pitch[6:3]<15)pitch[6:3]<=pitch[6:3]+1'b1;end
   else if(rotation_action==5'b10000)begin if(pitch[6:3]>1)pitch[6:3]<=pitch[6:3]-1'b1;end
   else if(rotation_action==5'b00001)yaw<=yaw+1'b1;
   else if(rotation_action==5'b00100)yaw<=yaw-1'b1;
   else if(ok_command)begin
    yaw<=next_view[10:4];pitch[6:3]<=next_view[3:0];preset_index<=preset_index+1'b1;
   end
   else if(right_command&&!left_command)begin if(pitch[2:0]<7)pitch[2:0]<=pitch[2:0]+1'b1;end
   else if(left_command&&!right_command)begin if(pitch[2:0]!=0)pitch[2:0]<=pitch[2:0]-1'b1;end
  end
 end
endmodule
