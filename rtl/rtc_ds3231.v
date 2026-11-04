// DS3231: 00h..0Fh burst, 24-hour BCD, years 2000..2099.
// 50 MHz / 125 / four phases gives at most 100 kHz I2C. Both pins are
// open drain; fit external pullups to 3.3 V. All logic uses clk, never SCL.
module rtc_ds3231 #(
 parameter integer QUARTER_CYCLES=125,POLL_TICKS=100000,TIMEOUT_TICKS=4000,
 parameter WRITE_ENABLE=0)(
 input wire clk,rst_n,inout wire rtc_scl,rtc_sda,
 output reg [47:0] time_bcd,output reg time_valid,
 input wire set_request,input wire [47:0] set_bcd,
 output reg set_busy,set_done,set_error);
 localparam integer DIV_BITS=(QUARTER_CYCLES>1)?$clog2(QUARTER_CYCLES):1;
 // The bit-phase counter is idle between reads. Reuse it as /4 for polling,
 // keeping the 250ms interval while the shared timer needs two fewer bits.
 localparam integer POLL_GROUPS=(POLL_TICKS+3)/4;
 localparam integer TIMER_MAX=(POLL_GROUPS>TIMEOUT_TICKS)?POLL_GROUPS:TIMEOUT_TICKS;
 localparam integer TIMER_BITS=(TIMER_MAX>1)?$clog2(TIMER_MAX+1):1;
 localparam [3:0] IDLE=0,BUS_CHECK=1,START_HOLD=2,TRANSFER=3,
  RESTART_LOW=4,RESTART_HIGH=5,RESTART_HOLD=6,
  STOP_LOW=7,STOP_HIGH=8,STOP_RELEASE=9,RECOVER_LOW=10,RECOVER_HIGH=11;
 reg [DIV_BITS-1:0] divider;
 wire tick=divider==QUARTER_CYCLES-1;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)divider<=0;else divider<=tick?0:divider+1'b1;
 reg scl_low,sda_low;
 assign rtc_scl=scl_low?1'b0:1'bz;
 assign rtc_sda=sda_low?1'b0:1'bz;
 (* async_reg="true" *) reg scl_sync1,scl_sync2,sda_sync1,sda_sync2;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin scl_sync1<=1;scl_sync2<=1;sda_sync1<=1;sda_sync2<=1;end
  else begin scl_sync1<=rtc_scl;scl_sync2<=scl_sync1;sda_sync1<=rtc_sda;sda_sync2<=sda_sync1;end
 reg [3:0] state,bit_count,byte_index;
 reg [1:0] phase,command;
 reg high_seen;
 reg [7:0] shift;
 reg [TIMER_BITS-1:0] timer;
 reg [47:0] shadow;
 reg bad_fields,complete,recovery;
 // 0 poll, 1 calendar write, 2 verify, 3 clear OSF, 4 final readback.
 reg [2:0] operation;
 reg [7:0] status_byte;
 reg pending,set_fault;
 // DS3231 latches the complete calendar at START; never publish partial bytes.
 wire leap=shadow[41:40]=={shadow[44],1'b0};
 wire february=shadow[39:32]==8'h02;
 wire short_month=shadow[39:32]==8'h04 || shadow[39:32]==8'h06 ||
  shadow[39:32]==8'h09 || shadow[39:32]==8'h11;
 wire calendar_ok=shadow[31:24]<=(february?(leap?8'h29:8'h28):(short_month?8'h30:8'h31));
 function invalid_byte;
  input [3:0] index;input [7:0] value;
  begin case(index)
   0,1:invalid_byte=value[7] || value[6:4]>5 || value[3:0]>9;
   // Reject 12-hour mode instead of silently displaying an incorrect hour.
   2:invalid_byte=value[7:6]!=0 || value[5:4]>2 || value[3:0]>9 || value>8'h23;
   3:invalid_byte=value<1 || value>7;
   4:invalid_byte=value[7:6]!=0 || value[5:4]>3 || value[3:0]>9 || value<1 || value>8'h31;
   5:invalid_byte=value[7:5]!=0 || value[3:0]>9 || value<1 || value>8'h12;
   6:invalid_byte=value[7:4]>9 || value[3:0]>9;
   15:invalid_byte=value[7]; // OSF stays set until a deliberate clock-setting write.
   default:invalid_byte=0;
  endcase end
 endfunction
 function [7:0] calendar_byte;
  input [3:0] index;
  begin case(index)
   0:calendar_byte=set_bcd[7:0];1:calendar_byte=set_bcd[15:8];
   2:calendar_byte=set_bcd[23:16];
   3:calendar_byte=1; // User-defined day-of-week counter; not displayed.
   4:calendar_byte=set_bcd[31:24];5:calendar_byte=set_bcd[39:32];
   default:calendar_byte=set_bcd[47:40];
  endcase end
 endfunction
 wire writing=WRITE_ENABLE&&(operation==1||operation==3);
 wire set_leap=set_bcd[41:40]=={set_bcd[44],1'b0};
 wire [7:0] set_last_day=(set_bcd[39:32]==2)?(set_leap?8'h29:8'h28):
  ((set_bcd[39:32]==4||set_bcd[39:32]==6||set_bcd[39:32]==9||set_bcd[39:32]==8'h11)?8'h30:8'h31);
 wire set_valid=!invalid_byte(0,set_bcd[7:0])&&!invalid_byte(1,set_bcd[15:8])&&
  !invalid_byte(2,set_bcd[23:16])&&!invalid_byte(4,set_bcd[31:24])&&
  !invalid_byte(5,set_bcd[39:32])&&!invalid_byte(6,set_bcd[47:40])&&set_bcd[31:24]<=set_last_day;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;timer<=0;scl_low<=0;sda_low<=0;phase<=0;command<=0;
   bit_count<=0;byte_index<=0;shift<=0;shadow<=0;bad_fields<=1;
   complete<=0;recovery<=0;high_seen<=0;time_bcd<=0;time_valid<=0;
   operation<=0;status_byte<=0;pending<=0;set_fault<=0;set_busy<=0;set_done<=0;set_error<=0;
  end else begin
   set_done<=0;set_error<=0;
   if(WRITE_ENABLE&&set_request&&!set_busy)begin
    if(set_valid)begin pending<=1;set_busy<=1;end
    else set_error<=1;
   end
   if(tick)begin
   if(state==IDLE)begin
    scl_low<=0;sda_low<=0;
    if(WRITE_ENABLE&&pending)begin
     pending<=0;operation<=1;time_valid<=0;set_fault<=1;
     timer<=TIMEOUT_TICKS;state<=BUS_CHECK;recovery<=0;complete<=0;
     bad_fields<=0;command<=0;byte_index<=0;phase<=0;
    end else if(phase==3)begin
     phase<=0;
     if(timer!=0)timer<=timer-1'b1;
     else begin
     timer<=TIMEOUT_TICKS;state<=BUS_CHECK;recovery<=0;complete<=0;
     bad_fields<=0;command<=0;byte_index<=0;phase<=0;
     end
    end else phase<=phase+1'b1;
   end else if(timer==0)begin
    // Bound the complete transaction, including a slave holding either line.
    state<=IDLE;timer<=POLL_GROUPS-1;phase<=0;scl_low<=0;sda_low<=0;time_valid<=0;
    if(WRITE_ENABLE&&operation!=0)begin set_busy<=0;set_error<=1;operation<=0;end
   end else begin
    timer<=timer-1'b1;
    case(state)
     BUS_CHECK:if(scl_sync2)begin
      if(phase==2)begin
      if(sda_sync2)begin sda_low<=1;phase<=0;recovery<=0;state<=START_HOLD;end
      else begin
       recovery<=1;bit_count<=8;scl_low<=1;phase<=0;state<=RECOVER_LOW;
      end
      end else phase<=phase+1'b1;
     end else phase<=0;
     RECOVER_LOW:begin
      if(phase==1)begin scl_low<=0;phase<=0;state<=RECOVER_HIGH;end
      else phase<=phase+1'b1;
     end
     RECOVER_HIGH:if(scl_sync2)begin
      // Reuse the normal START entry as soon as SDA releases, keeping SCL
      // high. Do not clock remaining pulses into an interrupted write.
      if(phase==2)begin
       if(sda_sync2)begin state<=BUS_CHECK;phase<=0;end
       else begin
        scl_low<=1;phase<=0;
        if(bit_count==0)begin sda_low<=1;state<=STOP_LOW;end
        else begin bit_count<=bit_count-1'b1;state<=RECOVER_LOW;end
       end
      end else phase<=phase+1'b1;
     end else phase<=0;
     START_HOLD:if(phase==1)begin
      scl_low<=1;shift<=8'hd0;bit_count<=7;phase<=0;state<=TRANSFER;
     end else phase<=1;
     TRANSFER:begin
      case(phase)
       0:begin
        if(command!=3)sda_low<=(bit_count==8)?1'b0:!shift[7];
        else sda_low<=(bit_count==8)&&(byte_index!=15);
        phase<=1;
       end
       1:begin scl_low<=0;high_seen<=0;phase<=2;end
       2:if(scl_sync2)begin
        // Measure the high interval from the synchronized pin, including
        // delayed rises/clock stretch. Two more quarters guarantee >=5us.
        if(!high_seen)high_seen<=1;
        else begin
         if(bit_count!=8&&command==3)shift<={shift[6:0],sda_sync2};
         phase<=3;
        end
       end else high_seen<=0;
       3:begin
        scl_low<=1;phase<=0;
        // A NACK still receives the complete high interval before STOP.
        if(bit_count==8&&command!=3&&sda_sync2)begin
         complete<=0;state<=STOP_LOW;sda_low<=1;
        end else if(bit_count==8)begin
         bit_count<=7;
         case(command)
          0:begin command<=1;shift<=(WRITE_ENABLE&&operation==3)?8'h0f:8'h00;end
          1:begin
           if(writing)begin command<=2;shift<=(operation==3)?(status_byte&8'h7f):calendar_byte(0);end
           else begin sda_low<=0;state<=RESTART_LOW;end
          end
          2:begin
           if(writing)begin
            if(operation==3||byte_index==6)begin complete<=1;sda_low<=1;state<=STOP_LOW;end
            else begin byte_index<=byte_index+1'b1;shift<=calendar_byte(byte_index+1'b1);end
           end else begin command<=3;sda_low<=0;end
          end
          3:begin
           bad_fields<=bad_fields||(invalid_byte(byte_index,shift)&&
            !(WRITE_ENABLE&&operation==2&&byte_index==15));
           if(WRITE_ENABLE&&byte_index==15)status_byte<=shift;
           // Reserved high bits are checked above, then stored as constants.
           // Keep only the BCD field width; invalid bytes still reject the
           // entire snapshot and never replace the published calendar.
           case(byte_index)
            0:shadow[7:0]<={1'b0,shift[6:0]};
            1:shadow[15:8]<={1'b0,shift[6:0]};
            2:shadow[23:16]<={2'b0,shift[5:0]};
            4:shadow[31:24]<={2'b0,shift[5:0]};
            5:shadow[39:32]<={3'b0,shift[4:0]};
            6:shadow[47:40]<=shift;
           endcase
           if(byte_index==15)begin complete<=1;sda_low<=1;state<=STOP_LOW;end
           else byte_index<=byte_index+1'b1;
          end
         endcase
        end else if(bit_count==0)bit_count<=8;
        else begin bit_count<=bit_count-1'b1;if(command!=3)shift<={shift[6:0],1'b0};end
       end
      endcase
     end
     RESTART_LOW:if(phase==1)begin scl_low<=0;phase<=0;state<=RESTART_HIGH;end
      else phase<=1;
     RESTART_HIGH:if(scl_sync2)begin
      if(phase==2)begin sda_low<=1;phase<=0;state<=RESTART_HOLD;end
      else phase<=phase+1'b1;
     end else phase<=0;
     RESTART_HOLD:if(phase==1)begin
      scl_low<=1;command<=2;shift<=8'hd1;bit_count<=7;phase<=0;state<=TRANSFER;
     end else phase<=1;
     STOP_LOW:if(phase==1)begin scl_low<=0;phase<=0;state<=STOP_HIGH;end
      else phase<=1;
     STOP_HIGH:if(scl_sync2)begin
      if(phase==2)begin sda_low<=0;state<=STOP_RELEASE;end
      else phase<=phase+1'b1;
     end else phase<=0;
     STOP_RELEASE:begin
      if(recovery)begin recovery<=0;phase<=0;state<=BUS_CHECK;end
      else if(WRITE_ENABLE&&operation!=0)begin
       phase<=0;command<=0;byte_index<=0;recovery<=0;complete<=0;bad_fields<=0;
       if(complete&&sda_sync2&&scl_sync2&&
          (writing||(!bad_fields&&calendar_ok&&shadow==set_bcd)))begin
        if(operation==4)begin
         time_bcd<=shadow;time_valid<=1;set_fault<=0;set_busy<=0;set_done<=1;
         operation<=0;state<=IDLE;timer<=POLL_GROUPS-1;
        end else begin operation<=operation+1'b1;state<=BUS_CHECK;timer<=TIMEOUT_TICKS;end
       end else begin
        operation<=0;state<=IDLE;timer<=POLL_GROUPS-1;time_valid<=0;set_busy<=0;set_error<=1;
       end
      end else begin
       state<=IDLE;timer<=POLL_GROUPS-1;phase<=0;
       time_valid<=complete&&!bad_fields&&calendar_ok&&sda_sync2&&scl_sync2&&!(WRITE_ENABLE&&set_fault);
       if(complete&&!bad_fields&&calendar_ok&&sda_sync2&&scl_sync2&&!(WRITE_ENABLE&&set_fault))time_bcd<=shadow;
      end
     end
     default:begin state<=IDLE;timer<=POLL_GROUPS-1;phase<=0;scl_low<=0;sda_low<=0;time_valid<=0;end
    endcase
   end
  end
  end
 end
endmodule
