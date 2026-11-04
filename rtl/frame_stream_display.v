// Memory-read interface to continuous raster RGB. Owns the safe swap window.
// Front memory remains locked for a complete fetch/consume transaction.
// No new transaction until all prior FIFO pixels (including late data) retire.
module frame_stream_display #(
 parameter H_ACTIVE=640,H_FP=16,H_SYNC=96,H_BP=48,
 parameter V_ACTIVE=480,V_FP=10,V_SYNC=2,V_BP=33,FIFO_ADDR_BITS=8,SLIDE_TRANSITIONS=0,INTRO_ANIMATION=0)(
 input wire rst_n,sys_clk,pix_clk,front_valid,front_bank,
 output wire swap_window,burst_valid,output wire [31:0] burst_addr,output wire [8:0] burst_words,input wire burst_ready,
 input wire burst_data_valid,burst_last,burst_error,input wire [31:0] burst_data,
 output wire prefetch_error,
 output wire de,output reg hsync,vsync,output wire [23:0] rgb,
 output wire frame_underflow,output wire fetch_busy,output reg video_started,
 input wire slide_request,slide_right,slide_prepared,output wire slide_ready,
 input wire intro_enable,intro_pause,input wire [4:0] intro_index,output wire intro_animating);
 wire raw_de,raw_hs,raw_vs,blank_start,raster_start;
 wire pre_ready,pre_done,pv,plast,pr;wire [31:0] pa;wire [23:0] pd;
 reg pre_start;
 // Toggle mailboxes carry a request, accepted/rejected acknowledgement,
 // and completion. No multi-bit pixel payload is synchronized this way.
 reg request_toggle,ack_toggle,done_toggle,grant;
 (* async_reg="true" *) reg req1,req2,ack1,ack2,done1,done2;
 reg req_seen,ack_seen,done_seen;
 reg [2:0] sys_state;
 reg [1:0] pix_state;
 reg slide_running,slide_done,slide_direction;
 reg [4:0] slide_phase;
 reg slide_long;
 reg [3:0] slide_tempo_error;
 reg [1:0] slide_style,slide_style_next;
 reg intro_mode_q,intro_seen,intro_bank_q;
 reg [4:0] intro_index_q;
 reg [1:0] intro_topic_q;
 reg [5:0] intro_phase_q;
 wire introduction=INTRO_ANIMATION&&front_valid&&intro_enable&&
  (intro_index==5||intro_index==11||intro_index==17||intro_index==23);
 wire gallery_visible=INTRO_ANIMATION&&front_valid&&intro_enable;
 wire [5:0] phase_limit=introduction?6'd63:6'd12;
 assign intro_animating=gallery_visible&&intro_phase_q<phase_limit;
 // Quintic smootherstep for the faster gallery, calculated once per retired
 // displayed frame. Zero endpoint acceleration avoids a sharp final snap.
 // 10 nine-frame and 3 ten-frame transitions per 13 requests average exactly
 // 12/1.3 frames. Every change still occurs at a complete-frame boundary.
 // The independent legacy path retains its original 18-frame animation.
 wire [4:0] last_slide_phase=INTRO_ANIMATION?(slide_long?5'd9:5'd8):5'd17;
 function [8:0] slide_fraction;
  input [4:0] phase;input long_transition;
  begin
   if(INTRO_ANIMATION)begin
    if(long_transition)case(phase)
     0:slide_fraction=0;1:slide_fraction=2;2:slide_fraction=15;
     3:slide_fraction=42;4:slide_fraction=81;5:slide_fraction=128;
     6:slide_fraction=175;7:slide_fraction=214;8:slide_fraction=241;
     9:slide_fraction=254;default:slide_fraction=256;
    endcase else case(phase)
     0:slide_fraction=0;1:slide_fraction=3;2:slide_fraction=20;
     3:slide_fraction=54;4:slide_fraction=102;5:slide_fraction=154;
     6:slide_fraction=202;7:slide_fraction=236;8:slide_fraction=253;
     default:slide_fraction=256;
    endcase
   end else case(phase)
    0:slide_fraction=0;1:slide_fraction=2;2:slide_fraction=9;
    3:slide_fraction=19;4:slide_fraction=32;5:slide_fraction=48;
    6:slide_fraction=66;7:slide_fraction=86;8:slide_fraction=107;
    9:slide_fraction=128;10:slide_fraction=149;11:slide_fraction=170;
    12:slide_fraction=190;13:slide_fraction=208;14:slide_fraction=224;
    15:slide_fraction=237;16:slide_fraction=247;17:slide_fraction=254;
    default:slide_fraction=256;
   endcase
  end
 endfunction
 wire [8:0] slide_fraction_value=slide_fraction(slide_phase,slide_long);
 wire [31:0] slide_product=H_ACTIVE*slide_fraction_value;
 wire [15:0] slide_distance=slide_product>>8;
 assign slide_ready=SLIDE_TRANSITIONS&&slide_done;
 localparam S_IDLE=0,S_SWAP=1,S_SETTLE=2,S_LAUNCH=3,S_RUN=4,S_METADATA=5;
 localparam P_IDLE=0,P_ACK=1,P_READY=2,P_RUN=3;
 wire arm=(pix_state==P_READY)&&raster_start&&pv;
 assign swap_window=(sys_state==S_SWAP);
 video_raster_timing #(.H_ACTIVE(H_ACTIVE),.H_FP(H_FP),.H_SYNC(H_SYNC),.H_BP(H_BP),
 .V_ACTIVE(V_ACTIVE),.V_FP(V_FP),.V_SYNC(V_SYNC),.V_BP(V_BP)) u_timing(
 .clk(pix_clk),.rst_n(rst_n),.de(raw_de),.hsync(raw_hs),.vsync(raw_vs),.blank_start(blank_start),.raster_start(raster_start));
 frame_burst_prefetch #(.FRAME_PIXELS(H_ACTIVE*V_ACTIVE),.FIFO_ADDR_BITS(FIFO_ADDR_BITS),
  .SLIDE_TRANSITIONS(SLIDE_TRANSITIONS),.LINE_PIXELS(H_ACTIVE),.INTRO_ANIMATION(INTRO_ANIMATION)) u_prefetch(
 .rst_n(rst_n),.sys_clk(sys_clk),.pix_clk(pix_clk),.start(pre_start),.frame_base(front_bank?(H_ACTIVE*V_ACTIVE):32'd0),
 .start_ready(pre_ready),.busy(fetch_busy),.done(pre_done),.error(prefetch_error),
 .burst_valid(burst_valid),.burst_addr(burst_addr),.burst_words(burst_words),.burst_ready(burst_ready),
 .burst_data_valid(burst_data_valid),.burst_last(burst_last),.burst_error(burst_error),.burst_data(burst_data),
 .pixel_valid(pv),.pixel_addr(pa),.pixel_rgb(pd),.pixel_last(plast),.pixel_ready(pr),
 // Gallery descriptor: [11:10]=push/reveal/banded reveal, [9:0]=distance.
 // Legacy callers retain the original untagged 16-bit pixel distance.
 .slide_active(SLIDE_TRANSITIONS&&slide_running&&!slide_done),.slide_right(slide_direction),
 .slide_offset(INTRO_ANIMATION?{4'd0,slide_style,slide_distance[9:0]}:slide_distance),
 .intro_active(intro_mode_q),.intro_topic(intro_topic_q),.intro_phase(intro_phase_q),
 .slide_alpha(6'd32-slide_fraction_value[8:3]));
 video_pixel_sink #(.FRAME_PIXELS(H_ACTIVE*V_ACTIVE)) u_sink(
 .pix_clk(pix_clk),.rst_n(rst_n),.raster_start(arm),.de(raw_de),.pixel_valid(pv),.pixel_addr(pa),.pixel_rgb(pd),
 .pixel_last(plast),.pixel_ready(pr),.out_de(de),.out_rgb(rgb),.frame_underflow(frame_underflow));
 always @(posedge sys_clk or negedge rst_n)begin
  if(!rst_n)begin
   req1<=0;req2<=0;req_seen<=0;sys_state<=S_IDLE;
   ack_toggle<=0;done_toggle<=0;grant<=0;pre_start<=0;
   slide_running<=0;slide_done<=0;slide_direction<=0;slide_phase<=0;
   slide_long<=0;slide_tempo_error<=0;slide_style<=0;slide_style_next<=0;
   intro_mode_q<=0;intro_seen<=0;intro_bank_q<=0;intro_index_q<=0;intro_topic_q<=0;intro_phase_q<=0;
  end else begin
   req1<=request_toggle;req2<=req1;pre_start<=0;
   if(!SLIDE_TRANSITIONS || !slide_request)slide_done<=0;
   // S_SWAP follows FIFO retirement. No bank is writable until all mixed
   // frames have retired and the final ordinary swap has been acknowledged.
   if(SLIDE_TRANSITIONS&&sys_state==S_SWAP)begin
    if(slide_running && slide_phase<last_slide_phase)slide_phase<=slide_phase+1'b1;
    else if(!slide_running&&!slide_done&&slide_request&&slide_prepared&&front_valid)begin
     slide_running<=1;slide_phase<=0;slide_direction<=slide_right;
     if(INTRO_ANIMATION)begin
      slide_long<=slide_tempo_error>=10;
      slide_tempo_error<=(slide_tempo_error>=10)?slide_tempo_error-4'd10:slide_tempo_error+4'd3;
      slide_style<=slide_style_next;
      slide_style_next<=(slide_style_next==2)?2'd0:slide_style_next+1'b1;
     end
    end
   end
   if(SLIDE_TRANSITIONS&&sys_state==S_RUN&&pre_done&&slide_running&&slide_phase==last_slide_phase)begin
    slide_running<=0;slide_done<=1;
   end
   case(sys_state)
    S_IDLE:if(req2!=req_seen && pre_ready)begin req_seen<=req2;sys_state<=S_SWAP;end
    S_SWAP:sys_state<=S_SETTLE;
    S_SETTLE:if(INTRO_ANIMATION)sys_state<=S_METADATA;
    else begin
     grant<=front_valid;
     if(front_valid)begin pre_start<=1;sys_state<=S_LAUNCH;end
     else begin ack_toggle<=!ack_toggle;sys_state<=S_IDLE;end
    end
    S_METADATA:begin
     // frame_committed updates display_index one clock after the bank swap.
     // Wait for that metadata before snapshotting this complete transaction.
     grant<=front_valid;intro_mode_q<=introduction;intro_seen<=gallery_visible;
     intro_index_q<=intro_index;intro_bank_q<=front_bank;
     intro_topic_q<=(intro_index==5)?2'd0:((intro_index==11)?2'd1:((intro_index==17)?2'd2:2'd3));
     if(!gallery_visible||!intro_seen||intro_index!=intro_index_q||front_bank!=intro_bank_q)intro_phase_q<=0;
     else if(!intro_pause&&!slide_running&&intro_phase_q<phase_limit)
      intro_phase_q<=introduction?((intro_phase_q>=61)?6'd63:intro_phase_q+6'd2):(intro_phase_q+1'b1);
     if(front_valid)begin pre_start<=1;sys_state<=S_LAUNCH;end
     else begin ack_toggle<=!ack_toggle;sys_state<=S_IDLE;end
    end
    S_LAUNCH:begin ack_toggle<=!ack_toggle;sys_state<=S_RUN;end
    S_RUN:if(pre_done)begin done_toggle<=!done_toggle;sys_state<=S_IDLE;end
    default:sys_state<=S_IDLE;
   endcase
  end
 end
 always @(posedge pix_clk or negedge rst_n)begin
  if(!rst_n)begin
   ack1<=0;ack2<=0;done1<=0;done2<=0;ack_seen<=0;done_seen<=0;
   request_toggle<=0;pix_state<=P_IDLE;hsync<=1;vsync<=1;video_started<=0;
  end else begin
   ack1<=ack_toggle;ack2<=ack1;done1<=done_toggle;done2<=done1;
   hsync<=raw_hs;vsync<=raw_vs;
   if(arm)video_started<=1;
   case(pix_state)
    P_IDLE:if(blank_start)begin request_toggle<=!request_toggle;pix_state<=P_ACK;end
    // grant is held from before ack toggle until the NEXT request, so is
    // stable throughout this bundled-data mailbox acknowledgement.
    P_ACK:if(ack2!=ack_seen)begin ack_seen<=ack2;pix_state<=grant?P_READY:P_IDLE;end
    P_READY:if(arm)pix_state<=P_RUN;
    P_RUN:if(done2!=done_seen)begin done_seen<=done2;pix_state<=P_IDLE;end
   endcase
  end
 end
endmodule
