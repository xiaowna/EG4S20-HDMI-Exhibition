// One-ahead cache using the existing back bank. A prepared frame is held until
// a user/timer request, then the optional fade and safe display swap authorize it.
// Reverse misses drain/discard the back frame; the visible bank is never reused.
module media_prefetch_control #(parameter INTERVAL_CYCLES=250000000,
 parameter AUTOPLAY_CYCLES=INTERVAL_CYCLES,
 parameter FAST_MANUAL=0,parameter CONTROLLED_AUTOPLAY=0,parameter ALBUMS=0,parameter CONTROLLED_PREFETCH=0,parameter integer MAX_IMAGES=4,
 parameter integer INDEX_BITS=(MAX_IMAGES>1)?$clog2(MAX_IMAGES):1,
 parameter integer COUNT_BITS=(MAX_IMAGES>0)?$clog2(MAX_IMAGES+1):1,
 parameter integer AUTOPLAY_SECOND_CYCLES=0,CACHE_FRAMES=0)(
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
 output wire preparing,prepare_progress_valid,input wire prefetch_enable,fast_pulse,
 output wire cancel_load,fast_commit,input wire [2:0] autoplay_interval,
 output wire [INDEX_BITS-1:0] retain_first,output wire preserve_album);
 localparam WAIT_CARD=0,SCAN=1,IDLE=2,LAUNCH=3,LOADING=4,
  DRAIN=5,CACHED=6,DISCARD=7,TRANSITION=8,FAILED=9,RETRY=10;
 localparam integer FIXED_LIMIT=(INTERVAL_CYCLES>AUTOPLAY_CYCLES)?INTERVAL_CYCLES:AUTOPLAY_CYCLES;
 localparam integer MENU_LIMIT=30*AUTOPLAY_SECOND_CYCLES;
 localparam integer TIMER_LIMIT=(MENU_LIMIT>FIXED_LIMIT)?MENU_LIMIT:FIXED_LIMIT;
 localparam integer TIMER_BITS=(TIMER_LIMIT>1)?$clog2(TIMER_LIMIT):1;
 reg [3:0] state;
 reg [TIMER_BITS-1:0] timer;
 wire [TIMER_BITS-1:0] autoplay_limit;
 wire autoplay_retiming;
 generate if(AUTOPLAY_SECOND_CYCLES>0)begin:interval_menu
  reg [2:0] current_interval;
  reg [TIMER_BITS-1:0] limit;
  assign autoplay_limit=limit;
  assign autoplay_retiming=current_interval!=autoplay_interval;
  always @(posedge clk or negedge rst_n)
   if(!rst_n)begin current_interval<=3'd7;limit<=AUTOPLAY_CYCLES-1;end
   else begin
    current_interval<=autoplay_interval;
    case(autoplay_interval)
     0:limit<=3*AUTOPLAY_SECOND_CYCLES-1;
     1:limit<=5*AUTOPLAY_SECOND_CYCLES-1;
     2:limit<=10*AUTOPLAY_SECOND_CYCLES-1;
     3:limit<=15*AUTOPLAY_SECOND_CYCLES-1;
     4:limit<=30*AUTOPLAY_SECOND_CYCLES-1;
     default:limit<=AUTOPLAY_CYCLES-1;
    endcase
   end
 end else begin:fixed_interval
  assign autoplay_limit=AUTOPLAY_CYCLES-1;
  assign autoplay_retiming=0;
 end endgenerate
 reg [INDEX_BITS-1:0] cursor;
 reg foreground,pending_request,pending_prev;
 reg [INDEX_BITS-1:0] pending_index;
 reg target_manual,target_backward;
 reg pending_fast,target_fast;
 reg cancel_pending;
 wire fast_request=FAST_MANUAL&&fast_pulse;
 // Stop an unrelated background prefetch at the file reader's next safe
 // sector boundary. The incomplete frame is rejected before a new load.
 assign cancel_load=FAST_MANUAL&&cancel_pending;
 reg album_pending,album_loading;
 reg [INDEX_BITS-1:0] range_first;
 reg [COUNT_BITS-1:0] range_limit;
 reg [COUNT_BITS-1:0] warm_index;
 reg warming,have_album;
 assign retain_first=range_first;
 assign preserve_album=album_enable&&have_album;
 wire warm_album=CACHE_FRAMES&&ALBUMS&&album_enable&&prefetch_enable&&
  !album_pending&&!album_loading&&warm_index<range_limit;
 wire [COUNT_BITS-1:0] end_index=(ALBUMS&&album_enable)?range_limit:image_count;
 wire [INDEX_BITS-1:0] begin_index=(ALBUMS&&album_enable)?range_first:{INDEX_BITS{1'b0}};
 wire manual_request=pending_request||next_pulse||prev_pulse;
 wire pulse_request=next_pulse||prev_pulse;
 wire fast_queued=FAST_MANUAL&&pending_request&&pending_fast;
 wire manual_fast=pulse_request?fast_request:fast_queued;
 // Before an automatic transition starts, manual IR navigation is relative
 // to the visible picture. Once a transition starts, let its bank reads retire.
 wire replace_auto=FAST_MANUAL&&foreground&&!target_manual&&front_valid&&
  state!=TRANSITION&&!(ALBUMS&&(album_pending||album_loading||album_request));
 wire backward=(next_pulse||prev_pulse)?(prev_pulse&&!next_pulse):pending_prev;
 wire [INDEX_BITS-1:0] forward_index=({1'b0,cursor}+1>=end_index)?begin_index:cursor+1'b1;
 // Keep every fast press made during an SD load; ordinary keys retain their
 // existing latest-direction queue. The loader still finishes its sector.
 wire [INDEX_BITS-1:0] step_base=(fast_request&&fast_queued)?pending_index:
  ((fast_request&&replace_auto)?display_index:cursor);
 wire [INDEX_BITS-1:0] step_last=end_index-1'b1;
 wire [INDEX_BITS-1:0] step_forward=(step_base>=step_last)?begin_index:step_base+1'b1;
 wire [INDEX_BITS-1:0] stepped_index=backward?
  ((step_base==begin_index)?step_last:step_base-1'b1):step_forward;
 wire [INDEX_BITS-1:0] target_index=(manual_request&&fast_queued&&!pulse_request)?
  pending_index:((manual_request)?stepped_index:forward_index);
 wire autoplay=!CONTROLLED_AUTOPLAY||auto_enable;
 wire count_autoplay=autoplay&&!pause&&!autoplay_retiming;
 reg count_autoplay_q;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)count_autoplay_q<=0;
  else count_autoplay_q<=count_autoplay;
 wire count_timer=CACHE_FRAMES?count_autoplay_q:count_autoplay;
 wire autoplay_due=timer>=autoplay_limit;
 wire request=manual_request||(count_autoplay&&autoplay_due);
 wire change_picture=!front_valid || target_index!=display_index;
 // An opposite step can withdraw a pending manual page before its swap.
 wire withdraw_manual=FAST_MANUAL&&foreground&&target_manual&&target_fast&&
  manual_fast&&!change_picture&&!(ALBUMS&&(album_pending||album_loading||album_request));
 wire retarget=(replace_auto&&manual_fast)||withdraw_manual;
 wire request_state=state==IDLE||state==LOADING||state==DRAIN||state==CACHED||state==FAILED;
 // Fast requests skip animation but still commit only in the loader swap window.
 assign transition_active=(state==TRANSITION) && front_valid && !target_fast;
 assign transition_manual=transition_active && target_manual;
 assign transition_backward=target_backward;
 // Only a cold frame, manual miss or album request makes the user wait.
 // Automatic misses keep displaying the front bank without a loading panel.
 assign preparing=((foreground&&((target_manual&&!target_fast)||!front_valid))||album_pending||album_loading)&&
  state!=TRANSITION&&state!=FAILED;
 assign prepare_progress_valid=foreground&&image_index==cursor&&
  (state==LOADING||state==DRAIN||state==CACHED);
 assign commit_enable=(state==TRANSITION) && (!front_valid||target_fast||transition_ready);
 assign fast_commit=commit_enable&&target_fast;
 assign discard_cached=(state==DISCARD);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=WAIT_CARD;timer<=0;cursor<=0;foreground<=0;
   pending_request<=0;pending_prev<=0;pending_index<=0;scan_start<=0;load_start<=0;image_index<=0;
   target_manual<=0;target_backward<=0;pending_fast<=0;target_fast<=0;cancel_pending<=0;
   album_pending<=0;album_loading<=0;range_first<=0;range_limit<=MAX_IMAGES;warm_index<=MAX_IMAGES;warming<=0;have_album<=0;album_ready<=0;album_error<=0;
  end else begin
   scan_start<=0;load_start<=0;
   if(state==LOADING && image_done)cancel_pending<=0;
   if(next_pulse||prev_pulse)begin
    pending_request<=1;pending_prev<=prev_pulse&&!next_pulse;pending_fast<=fast_request;
    if(fast_request)pending_index<=stepped_index;
   end
   if((CONTROLLED_AUTOPLAY&&!auto_enable)||autoplay_retiming)timer<=0;
   if(!foreground && count_timer && request_state && !autoplay_due)timer<=timer+1'b1;
   case(state)
    WAIT_CARD:if(card_ready)begin scan_start<=1;state<=SCAN;end
    SCAN:if(scan_done)begin
     timer<=0;cursor<=0;image_index<=0;
     if(!error && image_count!=0 && image_count<=MAX_IMAGES)begin foreground<=1;state<=LAUNCH;end
     else state<=RETRY;
    end
    IDLE:begin
     warming<=0;
     if(foreground)begin image_index<=cursor;state<=LAUNCH;end
     else if(warm_album&&!request)begin
      image_index<=warm_index[INDEX_BITS-1:0];warming<=1;state<=LAUNCH;
     end
     else if((!CONTROLLED_PREFETCH||prefetch_enable)&&image_count>1 && (!front_valid || forward_index!=display_index))begin
      image_index<=forward_index;state<=LAUNCH;
     end
    end
    LAUNCH:if(load_ready)begin load_start<=1;state<=LOADING;end
    LOADING:if(image_done)state<=DRAIN;
    // PENDING proves decoder success, exact pixel count and committed writes.
    // load_ready here means the attempted frame was rejected (or never began).
    DRAIN:if(frame_prepared)state<=CACHED;
          else if(load_ready)state<=(!foreground&&target_fast&&cursor==display_index&&
                                     image_index!=cursor)?IDLE:FAILED;
    CACHED:begin
     if(warm_album&&warm_index=={1'b0,image_index})warm_index<=warm_index+1'b1;
     if(foreground&&!retarget)begin
      if(image_index!=cursor)state<=DISCARD;
      // Wait for the previous fade acknowledgement to retire.
      else if(!front_valid || target_fast || !transition_ready)state<=TRANSITION;
     end else if(!foreground&&warm_album&&!request)state<=DISCARD;
    end
    DISCARD:if(load_ready)begin
     warming<=0;
     if(foreground)begin image_index<=cursor;state<=LAUNCH;end
     else state<=IDLE;
    end
    TRANSITION:if(frame_committed)begin
     foreground<=0;timer<=0;state<=IDLE;
     if(ALBUMS&&album_loading&&!album_pending&&!album_request)begin album_loading<=0;album_ready<=1;end
    end
    FAILED:if(foreground&&!retarget)begin
     if(image_index==cursor)begin
      foreground<=0;timer<=0;state<=IDLE;
      if(ALBUMS&&album_loading&&!album_pending&&!album_request)begin album_loading<=0;album_error<=1;end
     end
     else begin image_index<=cursor;warming<=0;state<=LAUNCH;end
    end else if(!foreground&&!request&&warm_album)begin
     if(warming&&warm_index=={1'b0,image_index})warm_index<=warm_index+1'b1;
     state<=IDLE;
    end
    RETRY:if(timer>=INTERVAL_CYCLES-1)begin timer<=0;state<=WAIT_CARD;end
          else timer<=timer+1'b1;
    default:state<=WAIT_CARD;
   endcase
   // During a foreground transition, retain one later direction. During a
   // background load, give a fast request for another picture priority.
   if((!foreground||retarget) && request_state && request)begin
    cursor<=target_index;timer<=0;pending_request<=0;pending_prev<=0;
    target_manual<=manual_request;target_backward<=manual_request&&backward;
    target_fast<=manual_fast;
    foreground<=change_picture;
    if(state==LOADING && !image_done && (manual_fast||warming) &&
       (change_picture||withdraw_manual) && target_index!=image_index)
     cancel_pending<=1;
    if(state==IDLE)begin
     warming<=0;
     if(front_valid && target_index==display_index)state<=IDLE;
     else begin image_index<=target_index;state<=LAUNCH;end
    end
   end
   // A column change never aborts a sector, memory write, or visible frame.
   // Drain to an idle/cached state, then discard only the back bank.
   if(ALBUMS&&album_pending&&!foreground&&(state==IDLE||state==CACHED||state==FAILED))begin
    album_pending<=0;album_loading<=1;cursor<=range_first;warming<=0;
    foreground<=1;pending_request<=0;pending_prev<=0;target_manual<=0;target_backward<=0;target_fast<=0;timer<=0;
    if(state==CACHED&&frame_prepared&&image_index==range_first)state<=CACHED;
    else if(state==CACHED)state<=DISCARD;
    else begin image_index<=range_first;state<=LAUNCH;end
   end
   if(ALBUMS&&album_request)begin
    album_ready<=0;album_loading<=0;
    if({1'b0,album_first}<image_count&&album_limit>{1'b0,album_first}&&image_count<=MAX_IMAGES)begin
     have_album<=1;range_first<=album_first;warm_index<={1'b0,album_first};range_limit<=(album_limit<image_count)?album_limit:image_count;
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
   if(ALBUMS&&!album_enable)begin have_album<=0;album_pending<=0;album_loading<=0;album_ready<=0;album_error<=0;end
  end
 end
endmodule
