// 3.3 V A/B encoder, idle 11, four Gray transitions per full detent.
// 50 MHz defaults: sample 100 us, A/B filter 300 us, button 20 ms,
// long press 600 ms. Pulses use the existing right/OK/left/settings bus.
// A held button never repeats; a long press never also emits short OK.
module media_rotary_encoder #(
 parameter integer SAMPLE_CYCLES=5000,AB_SAMPLES=3,
 parameter integer BUTTON_SAMPLES=200,LONG_SAMPLES=6000)(
 input wire clk,rst_n,enable,encoder_a,encoder_b,encoder_press_n,
 output reg [3:0] encoder_event);
 localparam integer SAMPLE_BITS=(SAMPLE_CYCLES>1)?$clog2(SAMPLE_CYCLES):1;
 localparam integer AB_BITS=(AB_SAMPLES>1)?$clog2(AB_SAMPLES):1;
 localparam integer BUTTON_BITS=(BUTTON_SAMPLES>1)?$clog2(BUTTON_SAMPLES):1;
 localparam integer LONG_BITS=(LONG_SAMPLES>1)?$clog2(LONG_SAMPLES):1;
 (* async_reg="true" *) reg [2:0] sync1,sync2;
 reg [1:0] sync_valid;
 reg [SAMPLE_BITS-1:0] sample_count;
 wire tick=(sample_count==SAMPLE_CYCLES-1);
 reg [1:0] ab_candidate,ab_stable,previous_ab;
 reg [AB_BITS-1:0] ab_count;
 reg button_stable;
 reg [BUTTON_BITS-1:0] button_count;
 reg rotation_armed,button_armed,press_active,long_sent;
 reg signed [3:0] movement;
 reg [LONG_BITS-1:0] hold_count;
 wire positive=({previous_ab,ab_stable}==4'b1110)||
  ({previous_ab,ab_stable}==4'b1000)||({previous_ab,ab_stable}==4'b0001)||
  ({previous_ab,ab_stable}==4'b0111);
 wire negative=({previous_ab,ab_stable}==4'b1101)||
  ({previous_ab,ab_stable}==4'b0100)||({previous_ab,ab_stable}==4'b0010)||
  ({previous_ab,ab_stable}==4'b1011);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin sync1<=3'b111;sync2<=3'b111;sync_valid<=0;sample_count<=0;end
  else begin
   sync1<={encoder_press_n,encoder_a,encoder_b};sync2<=sync1;
   sync_valid<={sync_valid[0],1'b1};
   if(tick)sample_count<=0;else sample_count<=sample_count+1'b1;
  end
 end
 // Sample and debounce even while commands are blocked. Re-enabling does
 // not reinterpret a held input as a new gesture.
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   ab_candidate<=2'b11;ab_stable<=2'b11;ab_count<=0;
   button_stable<=1;button_count<=0;
  end else if(tick)begin
   if(sync2[1:0]!=ab_candidate)begin
    ab_candidate<=sync2[1:0];ab_count<=0;
    if(AB_SAMPLES==1)ab_stable<=sync2[1:0];
   end else if(ab_stable!=ab_candidate)begin
    if(AB_SAMPLES==1 || ab_count==AB_SAMPLES-2)begin
     ab_stable<=ab_candidate;ab_count<=0;
    end else ab_count<=ab_count+1'b1;
   end else ab_count<=0;
   if(sync2[2]==button_stable)button_count<=0;
   else if(BUTTON_SAMPLES==1 || button_count==BUTTON_SAMPLES-1)begin
    button_stable<=sync2[2];button_count<=0;
   end else button_count<=button_count+1'b1;
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   encoder_event<=0;previous_ab<=2'b11;movement<=0;rotation_armed<=0;
   button_armed<=0;press_active<=0;long_sent<=0;hold_count<=0;
  end else begin
   encoder_event<=0;
   if(!enable || !sync_valid[1])begin
    previous_ab<=ab_stable;movement<=0;rotation_armed<=0;
    button_armed<=0;press_active<=0;long_sent<=0;hold_count<=0;
   end else if(tick)begin
    previous_ab<=ab_stable;
    // Rotation during a press is discarded. A complete idle detent is
    // required after reset, mode blocking, diagonal jumps or pressing.
    if(!button_stable || !sync2[2] || press_active)begin movement<=0;rotation_armed<=0;end
    else if(!rotation_armed)begin
     movement<=0;if(ab_stable==2'b11 && sync2[1:0]==2'b11)rotation_armed<=1;
    end else if(ab_stable!=previous_ab)begin
     if(!positive&&!negative)begin movement<=0;rotation_armed<=0;end
     else if(ab_stable==2'b11)begin
      if(positive&&movement==4'sd3)encoder_event<=4'b0001;
      else if(negative&&movement==-4'sd3)encoder_event<=4'b0100;
      movement<=0;
     end else if(positive)movement<=movement+1'b1;
     else movement<=movement-1'b1;
    end
    if(!button_armed)begin
     if(button_stable&&sync2[2])button_armed<=1;
    end else if(!press_active)begin
     if(!button_stable)begin press_active<=1;long_sent<=0;hold_count<=0;end
    end else if(button_stable)begin
     if(!long_sent)encoder_event<=4'b0010;
     press_active<=0;long_sent<=0;hold_count<=0;
    end else if(!long_sent&&!sync2[2])begin
     if(LONG_SAMPLES==1 || hold_count==LONG_SAMPLES-1)begin
      encoder_event<=4'b1000;long_sent<=1;
     end else hold_count<=hold_count+1'b1;
    end
   end
  end
 end
endmodule
