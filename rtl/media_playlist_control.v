// Auto-scan and circular playback. next_pulse is already synchronized/debounced.
// Failed scans retry after INTERVAL_CYCLES. Unsupported images are skipped
// after the same interval; playback waits for the buffer manager's load_ready.
module media_playlist_control #(parameter INTERVAL_CYCLES=250000000)(
 input wire clk,rst_n,card_ready,load_ready,scan_done,image_done,error,
 input wire [2:0] image_count,input wire next_pulse,pause,
 output reg scan_start,load_start,output reg [1:0] image_index,
 input wire prev_pulse);
 localparam WAIT_CARD=0,SCAN=1,LOAD=2,LOADING=3,HOLD=4,RETRY=5;
 localparam integer TIMER_BITS=(INTERVAL_CYCLES>1)?$clog2(INTERVAL_CYCLES):1;
 reg [2:0] state;reg [TIMER_BITS-1:0] timer;reg pending_next,pending_prev;
 // Keep one pending request while loading; the latest direction wins.
 wire backward=(next_pulse||prev_pulse)?(prev_pulse&&!next_pulse):pending_prev;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=WAIT_CARD;timer<=0;pending_next<=0;pending_prev<=0;scan_start<=0;load_start<=0;image_index<=0;end
  else begin
   scan_start<=0;load_start<=0;
   if(next_pulse||prev_pulse)begin pending_next<=1;pending_prev<=prev_pulse&&!next_pulse;end
   case(state)
    WAIT_CARD:if(card_ready)begin scan_start<=1;state<=SCAN;end
    SCAN:if(scan_done)begin timer<=0;image_index<=0;state<=(!error && image_count!=0)?LOAD:RETRY;end
    LOAD:if(load_ready)begin load_start<=1;state<=LOADING;end
    LOADING:if(image_done)begin timer<=0;state<=HOLD;end
    HOLD:begin
     if(!pause && timer<INTERVAL_CYCLES-1)timer<=timer+1'b1;
     if(pending_next||next_pulse||prev_pulse||(!pause && timer>=INTERVAL_CYCLES-1))begin
      if(backward && (pending_next||prev_pulse))
       image_index<=(image_index==0)?image_count-1'b1:image_index-1'b1;
      else image_index<=({1'b0,image_index}+1>=image_count)?2'd0:image_index+1'b1;
      pending_next<=0;pending_prev<=0;state<=LOAD;
     end
    end
    RETRY:if(timer>=INTERVAL_CYCLES-1)begin state<=WAIT_CARD;timer<=0;end else timer<=timer+1'b1;
    default:state<=WAIT_CARD;
   endcase
  end
 end
endmodule
