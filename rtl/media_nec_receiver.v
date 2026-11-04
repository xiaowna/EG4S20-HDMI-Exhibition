// Standard 8-bit-address NEC on an active-low demodulated receiver output.
// 50 MHz / 500 = 10 us. Do not connect an un-demodulated IR photodiode.
// Accept a frame only after all 32 bits, both inverse bytes and the stop mark.
module media_nec_receiver #(parameter integer SAMPLE_CYCLES=500)(
 input wire clk,rst_n,enable,infrared_n,
 output wire sample_tick,output reg frame_valid,frame_repeat,
 output wire [7:0] frame_address,frame_command);
 localparam integer SAMPLE_BITS=(SAMPLE_CYCLES>1)?$clog2(SAMPLE_CYCLES):1;
 localparam IDLE=0,LEADER=1,GAP=2,MARK=3,SPACE=4,STOP=5,REPEAT_STOP=6;
 (* async_reg="true" *) reg ir_sync1,ir_sync2;
 reg [1:0] sync_valid,filter_count;
 reg filtered,previous;
 reg [SAMPLE_BITS-1:0] sample_count;
 reg [10:0] width_count;
 wire [10:0] duration=width_count+1'b1;
 reg [2:0] state;
 reg [4:0] bit_index;
 reg [31:0] data;
 reg last_valid;
 reg [14:0] repeat_age;
 assign sample_tick=(sample_count==SAMPLE_CYCLES-1);
 assign frame_address=data[7:0];
 assign frame_command=data[23:16];
 wire mark_ok=(duration>=35&&duration<=80);
 wire zero_ok=(duration>=35&&duration<=85);
 wire one_ok=(duration>=120&&duration<=210);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin ir_sync1<=1;ir_sync2<=1;sync_valid<=0;sample_count<=0;end
  else begin
   ir_sync1<=infrared_n;ir_sync2<=ir_sync1;sync_valid<={sync_valid[0],1'b1};
   if(sample_tick)sample_count<=0;else sample_count<=sample_count+1'b1;
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin filtered<=1;filter_count<=0;end
  else if(sample_tick)begin
   if(ir_sync2==filtered)filter_count<=0;
   else if(filter_count==2)begin filtered<=ir_sync2;filter_count<=0;end
   else filter_count<=filter_count+1'b1;
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;previous<=1;width_count<=0;bit_index<=0;data<=0;
   last_valid<=0;repeat_age<=18000;frame_valid<=0;frame_repeat<=0;
  end else begin
   frame_valid<=0;frame_repeat<=0;
   if(!enable||!sync_valid[1])begin
    state<=IDLE;previous<=filtered;width_count<=0;bit_index<=0;
    last_valid<=0;repeat_age<=18000;
   end else if(sample_tick)begin
    previous<=filtered;
    if(repeat_age<18000)repeat_age<=repeat_age+1'b1;
    else last_valid<=0;
    if(filtered==previous)begin
     if(width_count<2046)width_count<=width_count+1'b1;
     if(state!=IDLE && duration>=1200)begin state<=IDLE;last_valid<=0;end
    end else begin
     width_count<=0;
     case(state)
      IDLE:if(!filtered && duration>=500)state<=LEADER;
      LEADER:if(filtered && duration>=750 && duration<=1050)state<=GAP;
       else begin state<=IDLE;last_valid<=0;end
      GAP:if(!filtered && duration>=350 && duration<=550)begin
        state<=MARK;bit_index<=0;last_valid<=0;
       end else if(!filtered && duration>=170 && duration<=280)state<=REPEAT_STOP;
       else begin state<=IDLE;last_valid<=0;end
      MARK:if(filtered && mark_ok)state<=SPACE;
       else begin state<=IDLE;last_valid<=0;end
      SPACE:if(!filtered && (zero_ok||one_ok))begin
        // NEC sends LSB first. After 32 right shifts the complete word has
        // the same byte order, without a 32-way indexed register write mux.
        data<={one_ok,data[31:1]};
        if(bit_index==31)state<=STOP;
        else begin bit_index<=bit_index+1'b1;state<=MARK;end
       end else begin state<=IDLE;last_valid<=0;end
      STOP:begin
       state<=IDLE;
       if(filtered && mark_ok && (data[7:0]^data[15:8])==8'hff &&
          (data[23:16]^data[31:24])==8'hff)begin
        frame_valid<=1;last_valid<=1;repeat_age<=0;
       end else last_valid<=0;
      end
      REPEAT_STOP:begin
       state<=IDLE;
       if(filtered && mark_ok && last_valid && repeat_age<18000)begin
        frame_valid<=1;frame_repeat<=1;repeat_age<=0;
       end else last_valid<=0;
      end
      default:begin state<=IDLE;last_valid<=0;end
     endcase
    end
   end
  end
 end
endmodule
