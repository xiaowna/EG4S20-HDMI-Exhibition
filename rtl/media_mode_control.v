// SW7 is an asynchronous level: 0=demo, 1=product. Filter both directions,
// including the first level after reset, before enabling either audio source.
// A mode change drains WAV reads, flushes audio at a packet boundary, commits
// the newest stable mode and waits for both FIFO domains to leave reset.
module media_mode_control #(parameter integer DEBOUNCE_CYCLES=1000000,parameter MUSIC_SELECT=0,parameter HOME_UI=0)(
 input wire clk,rst_n,mode_sw7,wav_idle,audio_flush_done,
 output reg product_mode,output wire switching,wav_enable,audio_flush_request,
 output reg mode_change,input wire music_request,input wire [1:0] music_index,
 output reg [1:0] active_music_index,output wire controls_block,input wire restart_audio);
 localparam integer COUNT_BITS=(DEBOUNCE_CYCLES>1)?$clog2(DEBOUNCE_CYCLES):1;
 (* async_reg="true" *) reg sw1,sw2;
 reg [1:0] valid_pipe;
 reg candidate,requested_mode,switch_ready;
 reg [COUNT_BITS-1:0] count;
 localparam BOOT=0,ACTIVE=1,QUIESCE=2,FLUSH=3,RELEASE=4;
 reg [2:0] state;
 reg [1:0] requested_music;
 reg restart_pending;
 wire music_pending=MUSIC_SELECT&&(requested_music!=active_music_index||(HOME_UI&&restart_pending));
 assign switching=(state!=ACTIVE)||!switch_ready||(requested_mode!=product_mode)||music_pending;
 // Song switching must not reset the physical debouncer: a held selection
 // key would otherwise be re-armed after every flush and repeatedly skip songs.
 assign controls_block=MUSIC_SELECT?(!switch_ready || requested_mode!=product_mode ||
  state==BOOT || mode_change):switching;
 assign wav_enable=!switching&&product_mode;
 assign audio_flush_request=(state==FLUSH);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   sw1<=1;sw2<=1;valid_pipe<=0;candidate<=1;requested_mode<=1;switch_ready<=0;count<=0;
  end else begin
   sw1<=mode_sw7;sw2<=sw1;valid_pipe<={valid_pipe[0],1'b1};
   if(!valid_pipe[1])count<=0;
   else if(sw2!=candidate)begin candidate<=sw2;count<=0;end
   else if(!switch_ready || requested_mode!=candidate)begin
    if(DEBOUNCE_CYCLES==1 || count==DEBOUNCE_CYCLES-1)begin
     requested_mode<=candidate;switch_ready<=1;count<=0;
    end else count<=count+1'b1;
   end else count<=0;
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=BOOT;product_mode<=1;mode_change<=0;requested_music<=0;active_music_index<=0;restart_pending<=0;end
  else begin
   mode_change<=0;
   if(MUSIC_SELECT&&music_request)requested_music<=music_index;
   if(HOME_UI&&restart_audio)restart_pending<=1;
   case(state)
    BOOT:if(switch_ready)state<=QUIESCE;
    ACTIVE:if(requested_mode!=product_mode || music_pending)state<=QUIESCE;
    QUIESCE:if(wav_idle)state<=FLUSH;
    FLUSH:if(audio_flush_done)begin
     product_mode<=requested_mode;
     // Selecting a song preserves menu focus, pause and AUTO settings.
     mode_change<=!MUSIC_SELECT || requested_mode!=product_mode;
     if(MUSIC_SELECT)active_music_index<=requested_music;
     if(HOME_UI&&!restart_audio)restart_pending<=0;
     state<=RELEASE;
    end
    RELEASE:if(!audio_flush_done)state<=ACTIVE;
    default:state<=BOOT;
   endcase
  end
 end
endmodule
