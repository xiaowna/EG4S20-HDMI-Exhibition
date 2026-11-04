// One-ahead cache using the existing back bank. A prepared frame is held until
// a user/timer request, then the optional fade and safe display swap authorize it.
// Reverse misses drain/discard the back frame; the visible bank is never reused.
module media_prefetch_control #(parameter INTERVAL_CYCLES=250000000,
 parameter AUTOPLAY_CYCLES=INTERVAL_CYCLES,
 parameter CONTROLLED_AUTOPLAY=0,parameter ALBUMS=0,parameter CONTROLLED_PREFETCH=0,parameter integer MAX_IMAGES=4,
 parameter integer INDEX_BITS=(MAX_IMAGES>1)?$clog2(MAX_IMAGES):1,
 parameter integer COUNT_BITS=(MAX_IMAGES>0)?$clog2(MAX_IMAGES+1):1)(
 input wire clk,rst_n,card_ready,load_ready,scan_done,image_done,error,
 input wire [COUNT_BITS-1:0] image_count,
 input wire next_pulse,prev_pulse,pause,front_valid,
 input wire [INDEX_BITS-1:0] display_index,
 input wire frame_prepared,frame_committed,transition_ready,
 output reg scan_start,load_start,output reg [INDEX_BITS-1:0] image_index,
 output wire commit_enable,discard_cached,transition_active,input wire auto_enable,
 output wire transition_manual,transition_backward,
 input wire album_request,album_enable,input wire [INDEX_BITS-1:0] album_first,
 input wire [COUNT_BITS-1:0] album_limit,output reg album_ready,album_error,
 output wire preparing,prepare_progress_valid,input wire prefetch_enable);
 localparam WAIT_CARD=0,SCAN=1,IDLE=2,LAUNCH=3,LOADING=4,
  DRAIN=5,CACHED=6,DISCARD=7,TRANSITION=8,FAILED=9,RETRY=10;
 localparam integer TIMER_LIMIT=(INTERVAL_CYCLES>AUTOPLAY_CYCLES)?INTERVAL_CYCLES:AUTOPLAY_CYCLES;
 localparam integer TIMER_BITS=(TIMER_LIMIT>1)?$clog2(TIMER_LIMIT):1;
 reg [3:0] state;
 reg [TIMER_BITS-1:0] timer;
 reg [INDEX_BITS-1:0] cursor;
 reg foreground,pending_request,pending_prev;
 reg target_manual,target_backward;
 reg album_pending,album_loading;
 reg [INDEX_BITS-1:0] range_first;
 reg [COUNT_BITS-1:0] range_limit;
 wire [COUNT_BITS-1:0] end_index=(ALBUMS&&album_enable)?range_limit:image_count;
 wire [INDEX_BITS-1:0] begin_index=(ALBUMS&&album_enable)?range_first:{INDEX_BITS{1'b0}};
 wire manual_request=pending_request||next_pulse||prev_pulse;
 wire backward=(next_pulse||prev_pulse)?(prev_pulse&&!next_pulse):pending_prev;
 wire [INDEX_BITS-1:0] forward_index=({1'b0,cursor}+1>=end_index)?begin_index:cursor+1'b1;
 wire [INDEX_BITS-1:0] target_index=(manual_request&&backward)?
  ((cursor==begin_index)?end_index-1'b1:cursor-1'b1):forward_index;
 wire autoplay=!CONTROLLED_AUTOPLAY||auto_enable;
 wire request=manual_request||(autoplay&&!pause && timer>=AUTOPLAY_CYCLES-1);
 wire request_state=state==IDLE||state==LOADING||state==DRAIN||state==CACHED||state==FAILED;
 assign transition_active=(state==TRANSITION) && front_valid;
 assign transition_manual=transition_active && target_manual;
 assign transition_backward=target_backward;
 // Only a cold frame, manual miss or album request makes the user wait.
 // Automatic misses keep displaying the front bank without a loading panel.
 assign preparing=((foreground&&(target_manual||!front_valid))||album_pending||album_loading)&&
  state!=TRANSITION&&state!=FAILED;
 assign prepare_progress_valid=foreground&&image_index==cursor&&
  (state==LOADING||state==DRAIN||state==CACHED);
 assign commit_enable=(state==TRANSITION) && (!front_valid||transition_ready);
 assign discard_cached=(state==DISCARD);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=WAIT_CARD;timer<=0;cursor<=0;foreground<=0;
   pending_request<=0;pending_prev<=0;scan_start<=0;load_start<=0;image_index<=0;
   target_manual<=0;target_backward<=0;
   album_pending<=0;album_loading<=0;range_first<=0;range_limit<=MAX_IMAGES;album_ready<=0;album_error<=0;
  end else begin
   scan_start<=0;load_start<=0;
   if(next_pulse||prev_pulse)begin pending_request<=1;pending_prev<=prev_pulse&&!next_pulse;end
   if(CONTROLLED_AUTOPLAY&&!auto_enable)timer<=0;
   if(!foreground && autoplay && !pause && request_state && timer<AUTOPLAY_CYCLES-1)timer<=timer+1'b1;
   case(state)
    WAIT_CARD:if(card_ready)begin scan_start<=1;state<=SCAN;end
    SCAN:if(scan_done)begin
     timer<=0;cursor<=0;image_index<=0;
     if(!error && image_count!=0 && image_count<=MAX_IMAGES)begin foreground<=1;state<=LAUNCH;end
     else state<=RETRY;
    end
    IDLE:begin
     if(foreground)begin image_index<=cursor;state<=LAUNCH;end
     else if((!CONTROLLED_PREFETCH||prefetch_enable)&&image_count>1 && (!front_valid || forward_index!=display_index))begin
      image_index<=forward_index;state<=LAUNCH;
     end
    end
    LAUNCH:if(load_ready)begin load_start<=1;state<=LOADING;end
    LOADING:if(image_done)state<=DRAIN;
    // PENDING proves decoder success, exact pixel count and committed writes.
    // load_ready here means the attempted frame was rejected (or never began).
    DRAIN:if(frame_prepared)state<=CACHED;
          else if(load_ready)state<=FAILED;
    CACHED:if(foreground)begin
     if(image_index!=cursor)state<=DISCARD;
     // Require the previous level acknowledgement to retire before raising
     // a new fade request, even for very short synthetic frames.
     else if(!front_valid || !transition_ready)state<=TRANSITION;
    end
    DISCARD:if(load_ready)begin image_index<=cursor;state<=LAUNCH;end
    TRANSITION:if(frame_committed)begin
     foreground<=0;timer<=0;state<=IDLE;
     if(ALBUMS&&album_loading&&!album_pending&&!album_request)begin album_loading<=0;album_ready<=1;end
    end
    FAILED:if(foreground)begin
     if(image_index==cursor)begin
      foreground<=0;timer<=0;state<=IDLE;
      if(ALBUMS&&album_loading&&!album_pending&&!album_request)begin album_loading<=0;album_error<=1;end
     end
     else begin image_index<=cursor;state<=LAUNCH;end
    end
    RETRY:if(timer>=INTERVAL_CYCLES-1)begin timer<=0;state<=WAIT_CARD;end
          else timer<=timer+1'b1;
    default:state<=WAIT_CARD;
   endcase
   // During a foreground transition, retain one later direction. During a
   // background load, lock the requested target without restarting SD midway.
   if(!foreground && request_state && request)begin
    cursor<=target_index;timer<=0;pending_request<=0;pending_prev<=0;
    target_manual<=manual_request;target_backward<=manual_request&&backward;
    foreground<=!(front_valid && target_index==display_index);
    if(state==IDLE)begin
     if(front_valid && target_index==display_index)state<=IDLE;
     else begin image_index<=target_index;state<=LAUNCH;end
    end
   end
   // A column change never aborts a sector, memory write, or visible frame.
   // Drain to an idle/cached state, then discard only the back bank.
   if(ALBUMS&&album_pending&&!foreground&&(state==IDLE||state==CACHED||state==FAILED))begin
    album_pending<=0;album_loading<=1;cursor<=range_first;
    foreground<=1;pending_request<=0;pending_prev<=0;target_manual<=0;target_backward<=0;timer<=0;
    if(state==CACHED&&frame_prepared&&image_index==range_first)state<=CACHED;
    else if(state==CACHED)state<=DISCARD;
    else begin image_index<=range_first;state<=LAUNCH;end
   end
   if(ALBUMS&&album_request)begin
    album_ready<=0;album_loading<=0;
    if({1'b0,album_first}<image_count&&album_limit>{1'b0,album_first}&&image_count<=MAX_IMAGES)begin
     range_first<=album_first;range_limit<=(album_limit<image_count)?album_limit:image_count;
     album_error<=0;
     if(front_valid&&!foreground&&request_state&&display_index==album_first)begin
      // The validated front image is already the requested first page.
      // Keep any background SD transaction alive; opening needs no reload.
      album_pending<=0;album_loading<=0;album_ready<=1;cursor<=album_first;
      foreground<=0;pending_request<=0;pending_prev<=0;timer<=0;
      target_manual<=0;target_backward<=0;
     end else album_pending<=1;
    end else begin album_pending<=0;album_error<=1;end
   end
   if(ALBUMS&&!album_enable)begin album_pending<=0;album_loading<=0;album_ready<=0;album_error<=0;end
  end
 end
endmodule
