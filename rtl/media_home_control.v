// Four existing command events drive a five-column home, with one queued turn.
// HOME/WAIT/OPEN/PLAY use one easing phase counter, updated per frame.
module media_home_control #(parameter VIEW_3D=0,parameter EXHIBIT=0)(
 input wire clk,rst_n,vsync,product_mode,mode_change,setting_active,home_request,
 input wire [3:0] key_press,input wire catalog_ready,input wire [5:0] image_count,
 input wire [4:0] first_image,input wire [5:0] image_limit,
 input wire switching,album_ready,album_error,view_ready,output wire view_active,
 output wire visible,starting,output reg [2:0] index,
 output wire [14:0] home_word,output reg play_request,autoplay_request);
 localparam [1:0] HOME=0,WAIT=1,OPEN=2,PLAY=3;
 reg [1:0] state;
 reg cover_active;
 reg [4:0] phase;
 reg moving,backward,pending,pending_backward,confirm_pending,error,audio_seen;
 (* async_reg="true" *) reg vs1,vs2;
 reg vs_prev;
 wire frame_tick=vs_prev&&!vs2;
 wire right=key_press[0]&&!key_press[2];
 wire left=key_press[2]&&!key_press[0];
 wire is_view=VIEW_3D&&index==4;
 assign view_active=product_mode&&is_view&&state!=HOME;
 wire valid_album=is_view||(catalog_ready&&{1'b0,first_image}<image_count&&image_limit>{1'b0,first_image});
 assign visible=product_mode&&state!=PLAY;
 assign starting=product_mode&&(state==WAIT||state==OPEN);
 assign home_word={visible,(EXHIBIT&&cover_active),state,moving,backward,phase,index,error};
 function [2:0] turn;
  input [2:0] value;input reverse;
  begin turn=reverse?((value==0)?3'd4:value-1'b1):((value==4)?3'd0:value+1'b1);end
 endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   vs1<=1;vs2<=1;vs_prev<=1;state<=HOME;cover_active<=EXHIBIT;index<=0;phase<=0;moving<=0;backward<=0;
   pending<=0;pending_backward<=0;confirm_pending<=0;error<=0;audio_seen<=0;
   play_request<=0;autoplay_request<=0;
  end else begin
   vs1<=vsync;vs2<=vs1;vs_prev<=vs2;
   play_request<=0;autoplay_request<=0;
   if(mode_change)begin
    state<=HOME;phase<=0;moving<=0;pending<=0;confirm_pending<=0;error<=0;audio_seen<=0;
   end else if(product_mode&&home_request)begin
    // Explicit navigation is separate from KEY4 closing an overlay. Cancel
    // pending home gestures, while retaining the selected card and settings.
    state<=HOME;cover_active<=0;phase<=0;moving<=0;pending<=0;confirm_pending<=0;error<=0;audio_seen<=0;
   end else if(product_mode)begin
    case(state)
     HOME:begin
      if(EXHIBIT&&cover_active)begin
       if(!setting_active&&key_press!=0)cover_active<=0;
      end else begin
      if(!setting_active)begin
       if(key_press[3])begin confirm_pending<=0;pending<=0;end
       else if(key_press[1])begin
        if(moving)begin confirm_pending<=1;pending<=0;end
        else if(valid_album)begin state<=WAIT;play_request<=1;audio_seen<=0;error<=0;end
        else error<=1;
       end else if(right||left)begin
        error<=0;confirm_pending<=0;
        if(moving)begin pending<=1;pending_backward<=left;end
        else begin moving<=1;backward<=left;phase<=0;end
       end
      end
      if(moving&&frame_tick)begin
       if(phase==18)begin
        index<=turn(index,backward);phase<=0;moving<=0;
        // Commit the visual target first; confirmation uses its descriptor
        // on the next clock, rather than the departing card's music/range.
       end else phase<=phase+1'b1;
      end
      if(!moving&&!setting_active&&!key_press[3]&&!key_press[1]&&!right&&!left)begin
       if(confirm_pending)begin
        confirm_pending<=0;
        if(valid_album)begin state<=WAIT;play_request<=1;audio_seen<=0;error<=0;end
        else error<=1;
       end else if(pending)begin moving<=1;backward<=pending_backward;pending<=0;phase<=0;end
      end
      end
     end
     WAIT:begin
      if(switching)audio_seen<=1;
      if(!play_request)begin
       if(!is_view&&album_error)begin state<=HOME;error<=1;end
       else if((is_view?view_ready:album_ready)&&audio_seen&&!switching)begin state<=OPEN;phase<=0;autoplay_request<=1;end
      end
     end
     OPEN:if(frame_tick)begin
      if(phase>=18)begin state<=PLAY;phase<=0;end else phase<=phase+5'd4;
     end
     // Settings own KEY4 and subpage exits. Closing an overlay is not a
     // navigation request: keep the album/cube and its playback state alive.
     PLAY:;
     default:state<=HOME;
    endcase
   end
  end
 end
endmodule
