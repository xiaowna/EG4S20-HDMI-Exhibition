// Standard NEC commands from one address. Fixed keys are restored on reset.
// Optional learning records right/OK/left/settings and an optional HOME key.
module media_infrared_control #(
 parameter integer SAMPLE_CYCLES=500,LEARN_HOLD_TICKS=200000,
 parameter integer RELEASE_TICKS=2500,LEARN_TIMEOUT_TICKS=3000000,
 parameter integer FIRST_REPEAT_TICKS=30000,NEXT_REPEAT_TICKS=10000,
 parameter HOME_KEY=0,FIXED_ENABLE=0,LEARN_ENABLE=1,
 parameter EXTRA_ENABLE=0,parameter [7:0] BACK_COMMAND=8'd0,EGG_A=8'd0,EGG_B=8'd0,
 parameter DIRECTION_ENABLE=0,parameter [7:0] UP_COMMAND=8'd0,DOWN_COMMAND=8'd0,
 parameter [47:0] FIXED_KEYS=48'd0)(
 input wire clk,rst_n,enable,infrared_n,key_settings_down,key_settings_press,
 output reg [3:0] infrared_event,direction_event,output reg home_event,back_event,easter_toggle,model_event,learning,learning_enter,
 output wire [2:0] learning_led,output reg paired);
 wire tick,frame_valid,frame_repeat;
 wire [7:0] address,command;
 media_nec_receiver #(.SAMPLE_CYCLES(SAMPLE_CYCLES)) receiver(
  .clk(clk),.rst_n(rst_n),.enable(enable),.infrared_n(infrared_n),.sample_tick(tick),
  .frame_valid(frame_valid),.frame_repeat(frame_repeat),.frame_address(address),.frame_command(command));
 localparam integer TIMER_MAX=(LEARN_TIMEOUT_TICKS>LEARN_HOLD_TICKS)?LEARN_TIMEOUT_TICKS:LEARN_HOLD_TICKS;
 localparam integer TIMER_BITS=(TIMER_MAX>1)?$clog2(TIMER_MAX):1;
 reg [TIMER_BITS-1:0] learn_timer;
 reg learn_armed;
 reg [2:0] learn_index;
 reg [7:0] pending_address,pending_right,pending_ok,pending_left,pending_settings;
 reg [7:0] active_address,active_right,active_ok,active_left,active_settings,active_home;
 reg recent_valid,repeat_started;
 reg [7:0] recent_command;
 reg [14:0] recent_age,repeat_wait;
 wire [3:0] mapped={command==active_settings,command==active_left,
                    command==active_ok,command==active_right};
 wire mapped_home=HOME_KEY&&command==active_home;
 wire mapped_back=EXTRA_ENABLE&&command==BACK_COMMAND;
 // The existing second secret key also provides a one-shot model action.
 // The board routes it only in 3D; the original secret sequence is retained.
 wire mapped_model=EXTRA_ENABLE&&command==EGG_B;
 wire mapped_secret=(EXTRA_ENABLE&&command==EGG_A)||mapped_model;
 // Dedicated camera events keep up/down out of the existing four-key menu.
 wire mapped_up=DIRECTION_ENABLE&&command==UP_COMMAND;
 wire mapped_down=DIRECTION_ENABLE&&command==DOWN_COMMAND;
 wire [3:0] mapped_direction=DIRECTION_ENABLE?{mapped_down,mapped_up,mapped[2],mapped[0]}:4'd0;
 reg [1:0] secret_step;
 wire same_press=recent_valid&&recent_age<18000&&command==recent_command;
 wire duplicate=(learn_index>0&&command==pending_right)||
                (learn_index>1&&command==pending_ok)||(learn_index>2&&command==pending_left)||
                (learn_index>3&&command==pending_settings);
 assign learning_led=learn_index+3'd1;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   infrared_event<=0;direction_event<=0;home_event<=0;back_event<=0;easter_toggle<=0;model_event<=0;secret_step<=0;
   learning<=0;learning_enter<=0;paired<=FIXED_ENABLE;learn_timer<=0;
   learn_armed<=0;learn_index<=0;pending_address<=0;pending_right<=0;pending_ok<=0;pending_left<=0;pending_settings<=0;
   active_address<=FIXED_KEYS[47:40];active_right<=FIXED_KEYS[39:32];active_ok<=FIXED_KEYS[31:24];
   active_left<=FIXED_KEYS[23:16];active_settings<=FIXED_KEYS[15:8];active_home<=FIXED_KEYS[7:0];
   recent_valid<=0;recent_command<=0;recent_age<=18000;repeat_wait<=0;repeat_started<=0;
  end else begin
   infrared_event<=0;direction_event<=0;home_event<=0;back_event<=0;model_event<=0;learning_enter<=0;
   if(!enable)begin
    learning<=0;learn_timer<=0;learn_armed<=0;recent_valid<=0;secret_step<=0;
    recent_age<=18000;repeat_wait<=0;repeat_started<=0;
   end else begin
    if(tick)begin
     if(recent_age<18000)recent_age<=recent_age+1'b1;else recent_valid<=0;
     if(repeat_wait<30000)repeat_wait<=repeat_wait+1'b1;
    end
    if(LEARN_ENABLE&&learning)begin
     if(key_settings_press)begin learning<=0;learn_timer<=0;end
     else if(frame_valid&&!frame_repeat&&!duplicate&&
             (learn_index==0||address==pending_address))begin
      learn_timer<=0;
      if(learn_index==(HOME_KEY?3'd4:3'd3))begin
        active_address<=pending_address;active_right<=pending_right;
        active_ok<=pending_ok;active_left<=pending_left;
        active_settings<=HOME_KEY?pending_settings:command;active_home<=HOME_KEY?command:8'd0;
        paired<=1;learning<=0;recent_command<=command;recent_valid<=1;
        recent_age<=0;repeat_wait<=0;repeat_started<=0;
      end else begin
       learn_index<=learn_index+1'b1;
       case(learn_index)
        0:begin pending_address<=address;pending_right<=command;end
        1:pending_ok<=command;
        2:pending_left<=command;
        3:pending_settings<=command;
        default:;
       endcase
      end
     end else if(tick)begin
      if(learn_timer==LEARN_TIMEOUT_TICKS-1)begin learning<=0;learn_timer<=0;end
      else learn_timer<=learn_timer+1'b1;
     end
    end else begin
     if(LEARN_ENABLE)begin
     if(!learn_armed)begin
      if(key_settings_down)learn_timer<=0;
      else if(tick)begin
       if(RELEASE_TICKS==1||learn_timer==RELEASE_TICKS-1)begin learn_armed<=1;learn_timer<=0;end
       else learn_timer<=learn_timer+1'b1;
      end
     end else if(!key_settings_down)learn_timer<=0;
     else if(tick)begin
      if(LEARN_HOLD_TICKS==1||learn_timer==LEARN_HOLD_TICKS-1)begin
       learning<=1;learning_enter<=1;learn_index<=0;learn_timer<=0;
       learn_armed<=0;recent_valid<=0;infrared_event<=0;
      end else learn_timer<=learn_timer+1'b1;
     end
     end
     if(EXTRA_ENABLE&&frame_valid&&paired&&address==active_address&&!frame_repeat&&!same_press)begin
      case(secret_step)
       0:secret_step<=(command==EGG_A)?1:0;
       1:secret_step<=(command==EGG_B)?2:((command==EGG_A)?1:0);
       2:secret_step<=(command==EGG_A)?3:0;
       3:begin
        secret_step<=(command==EGG_A)?1:0;
        if(command==EGG_B)easter_toggle<=!easter_toggle;
       end
      endcase
     end
     if(frame_valid&&paired&&address==active_address&&((|mapped)||mapped_home||mapped_back||mapped_secret||mapped_up||mapped_down)&&(!frame_repeat||same_press))begin
      recent_valid<=1;recent_command<=command;recent_age<=0;
      if(!frame_repeat&&!same_press)begin
       infrared_event<=(mapped_home||mapped_back||mapped_secret)?4'd0:mapped;
       direction_event<=(mapped_home||mapped_back||mapped_secret)?4'd0:mapped_direction;
       home_event<=mapped_home;back_event<=mapped_back;model_event<=mapped_model;
       repeat_wait<=0;repeat_started<=0;
      end else if(same_press&&(mapped[0]||mapped[2]||mapped_up||mapped_down)&&
          repeat_wait>=(repeat_started?NEXT_REPEAT_TICKS:FIRST_REPEAT_TICKS))begin
       infrared_event<=mapped;direction_event<=mapped_direction;repeat_wait<=0;repeat_started<=1;
      end
     end
     // Entering learning takes priority over a coincident decoded command.
     if(LEARN_ENABLE&&learn_armed&&key_settings_down&&tick&&learn_timer==LEARN_HOLD_TICKS-1)begin
      infrared_event<=0;direction_event<=0;home_event<=0;model_event<=0;
     end
    end
   end
  end
 end
endmodule
