// Burst prefetch interface, independent of the physical SDRAM controller.
// MAX_BURST <= FIFO depth and <=256. Each command stays within a 256-word row.
// Backend may return one word per sys_clk with no backpressure: reserve space
// BEFORE issue. First response must be after command handshake, not on it.
// burst_last marks exactly the last response. Any fault requires common reset.
module frame_burst_prefetch #(parameter FRAME_PIXELS=640*480,MAX_BURST=32,
 FIFO_ADDR_BITS=6,TIMEOUT_CYCLES=1000000,SLIDE_TRANSITIONS=0,LINE_PIXELS=640,INTRO_ANIMATION=0,CACHE_FRAMES=0)(
 input wire rst_n,sys_clk,pix_clk,start,input wire [31:0] frame_base,
 output wire start_ready,output reg busy,done,error,
 output wire burst_valid,output wire [31:0] burst_addr,output wire [8:0] burst_words,input wire burst_ready,
 input wire burst_data_valid,burst_last,burst_error,input wire [31:0] burst_data,
 output wire pixel_valid,output wire [31:0] pixel_addr,output wire [23:0] pixel_rgb,
 output wire pixel_last,input wire pixel_ready,
 input wire slide_active,slide_right,input wire [15:0] slide_offset,
 input wire intro_active,input wire [1:0] intro_topic,input wire [5:0] intro_phase,
 input wire [5:0] slide_alpha,input wire [20:0] back_base);
 localparam IDLE=0,PREP=1,ISSUE=2,RECEIVE=3,DRAIN=4,INTRO=5;
 localparam integer OFFSET_BITS=(FRAME_PIXELS>0)?$clog2(FRAME_PIXELS+1):1;
 localparam integer TIMER_BITS=(TIMEOUT_CYCLES>1)?$clog2(TIMEOUT_CYCLES):1;
 reg [2:0] state;reg [31:0] base,request_addr;reg [8:0] reserved,received;
 reg [OFFSET_BITS-1:0] offset;
 reg [TIMER_BITS-1:0] timer;
 // A sliding line is two contiguous source segments. The back bank is
 // immutable while the loader holds its validated PENDING frame.
 reg slide_mode,first_segment;
 reg intro_mode;
 reg [20:0] line_first,line_second,source_cursor;
 reg [15:0] boundary,segment_left;
 // Only the gallery compositor interprets [11:10] as a style tag. The
 // independent legacy prefetch retains all 16 distance/validation bits.
 wire [15:0] geometry_offset=INTRO_ANIMATION?{6'd0,slide_offset[9:0]}:slide_offset;
 wire select_slide=SLIDE_TRANSITIONS && slide_active && geometry_offset!=0 && geometry_offset<LINE_PIXELS;
 wire [31:0] other_base=CACHE_FRAMES?{11'd0,back_base}:((frame_base==0)?FRAME_PIXELS:32'd0);
 wire [31:0] first_address=slide_right?(other_base+LINE_PIXELS-geometry_offset):(frame_base+geometry_offset);
 wire [31:0] second_address=slide_right?frame_base:other_base;
 wire [15:0] first_length=slide_right?geometry_offset:(LINE_PIXELS-geometry_offset);
 // The gallery compositor emits a 19-bit frame-relative address.
 // Keep all 32 bits for the legacy producer.
 localparam FIFO_PIXEL_ADDR_BITS=INTRO_ANIMATION?19:32;
 localparam FIFO_WIDTH=1+FIFO_PIXEL_ADDR_BITS+24;
 wire [FIFO_ADDR_BITS:0] free_words;
 wire fifo_ready,fifo_empty;
 wire [FIFO_WIDTH-1:0] fifo_data;
 wire [FIFO_PIXEL_ADDR_BITS-1:0] fifo_pixel_addr;
 wire [FIFO_PIXEL_ADDR_BITS-1:0] legacy_pixel_addr=offset+{23'b0,received};
 wire [FIFO_WIDTH-1:0] legacy_fifo_word={offset+received==FRAME_PIXELS-1,legacy_pixel_addr,burst_data[23:0]};
 wire [31:0] absolute_addr=(SLIDE_TRANSITIONS&&slide_mode)?{11'd0,source_cursor}:base+offset;
 wire [31:0] remain=FRAME_PIXELS-offset;
 wire [31:0] row_left=256-{24'b0,absolute_addr[7:0]};
 wire [31:0] limit1=(remain<MAX_BURST)?remain:MAX_BURST;
 wire [31:0] limit2=(limit1<row_left)?limit1:row_left;
 wire [31:0] planned=(SLIDE_TRANSITIONS&&slide_mode&&segment_left<limit2)?segment_left:limit2;
 // Select the engine at elaboration, rather than retaining unreachable
 // legacy arithmetic behind a run-time mode bit. Unexpected idle responses
 // still fault; active gallery responses are checked by its compositor.
 wire bad_data=burst_data_valid && (INTRO_ANIMATION?!intro_mode:
  (state!=RECEIVE || !fifo_ready || burst_last!=(received==reserved-1)));
 wire put=!INTRO_ANIMATION && burst_data_valid && state==RECEIVE && !bad_data && !burst_error && !error;
 wire intro_ready,intro_busy,intro_done,intro_error,intro_burst_valid,intro_pixel_valid,intro_last;
 wire [31:0] intro_burst_addr,intro_pixel_addr;wire [8:0] intro_words;
 wire [23:0] intro_rgb;
 // The exhibition uses one gallery producer for both ordinary photos and
 // introductions. The legacy engine is constant-inactive in this build.
 wire choose_intro=INTRO_ANIMATION;
 generate if(INTRO_ANIMATION)begin:introduction
  frame_intro_prefetch #(.MAX_BURST(MAX_BURST),.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.GALLERY_CAPTIONS(1),.CACHE_FRAMES(CACHE_FRAMES)) compositor(
   .rst_n(rst_n),.sys_clk(sys_clk),.start(start&&start_ready&&choose_intro),
   .frame_base(frame_base),.back_base(back_base),.topic(intro_topic),.phase(intro_phase),
   .start_ready(intro_ready),.busy(intro_busy),.done(intro_done),.error(intro_error),
   .burst_valid(intro_burst_valid),.burst_addr(intro_burst_addr),.burst_words(intro_words),
   .burst_ready(intro_mode&&burst_ready),.burst_data_valid(intro_mode&&burst_data_valid),
   .burst_last(burst_last),.burst_error(burst_error),.burst_data(burst_data),
   .pixel_valid(intro_pixel_valid),.pixel_addr(intro_pixel_addr),.pixel_rgb(intro_rgb),
   .pixel_last(intro_last),.pixel_ready(intro_mode&&fifo_ready&&!error),
   .intro_active(intro_active),.slide_active(slide_active),.slide_right(slide_right),
   .slide_offset(slide_offset),.slide_alpha(slide_alpha));
 end else begin:no_introduction
  assign intro_ready=1;assign intro_busy=0;assign intro_done=0;assign intro_error=0;
  assign intro_burst_valid=0;assign intro_burst_addr=0;assign intro_words=0;
  assign intro_pixel_valid=0;assign intro_pixel_addr=0;assign intro_rgb=0;assign intro_last=0;
 end endgenerate
 assign start_ready=state==IDLE && fifo_empty && intro_ready && !error;
 assign burst_valid=(INTRO_ANIMATION?(intro_mode&&intro_burst_valid):(state==ISSUE)) && !error;
 // Hold the address from PREP through the ISSUE handshake. This also removes
 // the base+offset carry chain from the SDRAM half-cycle output path.
 assign burst_addr=INTRO_ANIMATION?(intro_mode?intro_burst_addr:32'd0):request_addr;
 assign burst_words=INTRO_ANIMATION?(intro_mode?intro_words:9'd0):reserved;
 assign {pixel_last,fifo_pixel_addr,pixel_rgb}=fifo_data;
 assign pixel_addr={{(32-FIFO_PIXEL_ADDR_BITS){1'b0}},fifo_pixel_addr};
 pixel_async_fifo #(.WIDTH(FIFO_WIDTH),.ADDR_BITS(FIFO_ADDR_BITS)) u_fifo(
 .rst_n(rst_n),.wclk(sys_clk),.rclk(pix_clk),.wvalid(INTRO_ANIMATION?(intro_mode&&intro_pixel_valid&&!error):put),
 .wdata(INTRO_ANIMATION?{intro_last,intro_pixel_addr[FIFO_PIXEL_ADDR_BITS-1:0],intro_rgb}:
  legacy_fifo_word),
 .wready(fifo_ready),.wempty(fifo_empty),.w_free(free_words),.rvalid(pixel_valid),.rdata(fifo_data),.rready(pixel_ready));
 always @(posedge sys_clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;base<=0;offset<=0;request_addr<=0;reserved<=0;received<=0;timer<=0;busy<=0;done<=0;error<=0;
   slide_mode<=0;first_segment<=0;line_first<=0;line_second<=0;source_cursor<=0;boundary<=0;segment_left<=0;intro_mode<=0;
  end
  else begin
   done<=0;
   if(!error)begin
    if(burst_error||bad_data||intro_error)begin error<=1;busy<=0;end
    else case(state)
     IDLE:if(start&&start_ready)begin
      if({32'b0,frame_base}+FRAME_PIXELS>64'd2097152 ||
         (SLIDE_TRANSITIONS&&slide_active&&
          (LINE_PIXELS<1 || LINE_PIXELS>65535 || FRAME_PIXELS%LINE_PIXELS!=0 ||
           geometry_offset>=LINE_PIXELS ||
           (INTRO_ANIMATION&&(slide_offset[15:12]!=0||slide_offset[11:10]==3)) ||
           (CACHE_FRAMES?({11'd0,back_base}+FRAME_PIXELS>32'd2097152 || other_base==frame_base):
            (frame_base!=0 && frame_base!=FRAME_PIXELS)) ||
           2*FRAME_PIXELS>2097152)) ||
         (choose_intro&&(FRAME_PIXELS!=307200||LINE_PIXELS!=640)))error<=1;
      else begin
       busy<=1;state<=choose_intro?INTRO:PREP;intro_mode<=choose_intro;
       if(!INTRO_ANIMATION)begin
       base<=frame_base;offset<=0;slide_mode<=select_slide;
       if(select_slide)begin
        first_segment<=1;line_first<=first_address[20:0];line_second<=second_address[20:0];
        source_cursor<=first_address[20:0];boundary<=first_length;segment_left<=first_length;
       end
       end
      end
     end
     PREP:if(INTRO_ANIMATION)begin error<=1;busy<=0;end
          else if(free_words>=planned)begin request_addr<=absolute_addr;reserved<=planned;received<=0;timer<=0;state<=ISSUE;end
     ISSUE:if(INTRO_ANIMATION)begin error<=1;busy<=0;end
           else if(burst_ready)begin timer<=0;state<=RECEIVE;end
           else if(timer>=TIMEOUT_CYCLES-1)begin error<=1;busy<=0;end else timer<=timer+1'b1;
     RECEIVE:if(INTRO_ANIMATION)begin error<=1;busy<=0;end
     else if(put)begin
      timer<=0;
      if(burst_last)begin
       offset<=offset+reserved;state<=(offset+reserved==FRAME_PIXELS)?DRAIN:PREP;
       if(SLIDE_TRANSITIONS&&slide_mode)begin
        if(segment_left==reserved)begin
         if(first_segment)begin
          source_cursor<=line_second;segment_left<=LINE_PIXELS-boundary;first_segment<=0;
         end else begin
          line_first<=line_first+LINE_PIXELS;line_second<=line_second+LINE_PIXELS;
          source_cursor<=line_first+LINE_PIXELS;segment_left<=boundary;first_segment<=1;
         end
        end else begin source_cursor<=source_cursor+reserved;segment_left<=segment_left-reserved;end
       end
      end
      else received<=received+1'b1;
     end else if(timer>=TIMEOUT_CYCLES-1)begin error<=1;busy<=0;end else timer<=timer+1'b1;
     INTRO:if(intro_done)state<=DRAIN;
     DRAIN:if(fifo_empty)begin done<=1;busy<=0;state<=IDLE;intro_mode<=0;end
     default:begin error<=1;busy<=0;end
    endcase
   end
  end
 end
endmodule
