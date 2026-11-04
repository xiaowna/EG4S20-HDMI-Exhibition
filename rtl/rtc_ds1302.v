// DS1302 three-wire host: LSB first, CE high, data changes on falling CLK.
// 50MHz /125 /4 =100kHz. CE setup/inactive >=5us, data hold >=2.5us.
// Only clk clocks the logic. DAT is released before the first read-data edge.
// Boot/save: unlock, disable trickle charge, optional calendar burst, protect,
// verify charger and complete calendar. Normal polling never writes the clock.
module rtc_ds1302 #(
 parameter integer QUARTER_CYCLES=125,POLL_TICKS=100000,TIMEOUT_TICKS=4000,
 parameter WRITE_ENABLE=0)(
 input wire clk,rst_n,output reg rtc_clk,rtc_ce,inout wire rtc_dat,
 output reg [47:0] time_bcd,output reg time_valid,
 input wire set_request,input wire [47:0] set_bcd,
 output reg set_busy,set_done,set_error);
 localparam integer DIV_BITS=(QUARTER_CYCLES>1)?$clog2(QUARTER_CYCLES):1;
 localparam integer TIMER_MAX=(POLL_TICKS>TIMEOUT_TICKS)?POLL_TICKS:TIMEOUT_TICKS;
 localparam integer TIMER_BITS=(TIMER_MAX>1)?$clog2(TIMER_MAX+1):1;
 localparam IDLE=0,BEGIN_TRANSFER=1,SETUP=2,TRANSFER=3,STOP=4,GAP=5,EVALUATE=6;
 localparam POLL=0,UNLOCK=1,CHARGE_OFF=2,CALENDAR=3,PROTECT=4,CHECK_CHARGE=5,VERIFY=6;
 reg [DIV_BITS-1:0] divider;
 wire tick=divider==QUARTER_CYCLES-1;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)divider<=0;else divider<=tick?0:divider+1'b1;
 reg dat_enable,dat_out;
 assign rtc_dat=dat_enable?dat_out:1'bz;
 (* async_reg="true" *) reg dat_sync1,dat_sync2;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin dat_sync1<=0;dat_sync2<=0;end
  else begin dat_sync1<=rtc_dat;dat_sync2<=dat_sync1;end
 reg [2:0] state,operation,bit_count,byte_index;
 reg [1:0] phase;
 reg command_done,reading,initializing,pending,setting,set_fault,bad_fields;
 reg [7:0] shift;
 reg [47:0] shadow,target;
 reg [TIMER_BITS-1:0] timer;
 function [7:0] command_byte;
  input [2:0] op;
  begin case(op)
   UNLOCK,PROTECT:command_byte=8'h8e;
   CHARGE_OFF:command_byte=8'h90;
   CALENDAR:command_byte=8'hbe;
   CHECK_CHARGE:command_byte=8'h91;
   default:command_byte=8'hbf;
  endcase end
 endfunction
 function [7:0] write_byte;
  input [2:0] op,index;
  begin
   if(op==PROTECT)write_byte=8'h80;
   else if(op!=CALENDAR)write_byte=0;
   else case(index)
    0:write_byte=target[7:0];1:write_byte=target[15:8];2:write_byte=target[23:16];
    3:write_byte=target[31:24];4:write_byte=target[39:32];5:write_byte=1;
    6:write_byte=target[47:40];default:write_byte=8'h80;
   endcase
  end
 endfunction
 function invalid_byte;
  input [2:0] index;input [7:0] value;
  begin case(index)
   0,1:invalid_byte=value[7]||value[6:4]>5||value[3:0]>9;
   2:invalid_byte=value[7:6]!=0||value[5:4]>2||value[3:0]>9||value>8'h23;
   3:invalid_byte=value[7:6]!=0||value[5:4]>3||value[3:0]>9||value<1||value>8'h31;
   4:invalid_byte=value[7:5]!=0||value[3:0]>9||value<1||value>8'h12;
   5:invalid_byte=value<1||value>7;
   6:invalid_byte=value[7:4]>9||value[3:0]>9;
   7:invalid_byte=value!=8'h80; // Write protection must have read back enabled.
  endcase end
 endfunction
 function [7:0] last_day;
  input [7:0] year,month;
  begin case(month)
   2:last_day=(year[1:0]=={year[4],1'b0})?8'h29:8'h28;
   4,6,9,8'h11:last_day=8'h30;
   default:last_day=8'h31;
  endcase end
 endfunction
 wire calendar_ok=shadow[31:24]<=last_day(shadow[47:40],shadow[39:32]);
 wire set_valid=!invalid_byte(0,set_bcd[7:0])&&!invalid_byte(1,set_bcd[15:8])&&
  !invalid_byte(2,set_bcd[23:16])&&!invalid_byte(3,set_bcd[31:24])&&
  !invalid_byte(4,set_bcd[39:32])&&!invalid_byte(6,set_bcd[47:40])&&
  set_bcd[31:24]<=last_day(set_bcd[47:40],set_bcd[39:32]);
 wire long_transfer=operation==POLL||operation==CALENDAR||operation==VERIFY;
 wire [7:0] next_command=command_byte(operation);
 wire accept_request=WRITE_ENABLE&&set_request&&!set_busy&&set_valid;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   rtc_clk<=0;rtc_ce<=0;dat_enable<=0;dat_out<=0;
   state<=IDLE;operation<=POLL;phase<=0;bit_count<=0;byte_index<=0;
   command_done<=0;reading<=0;initializing<=1;pending<=0;setting<=0;
   set_fault<=0;bad_fields<=1;shift<=0;shadow<=0;target<=0;timer<=0;
   time_bcd<=0;time_valid<=0;set_busy<=0;set_done<=0;set_error<=0;
  end else begin
   set_done<=0;set_error<=0;
   if(WRITE_ENABLE&&set_request&&!set_busy)begin
    if(set_valid)begin target<=set_bcd;pending<=1;set_busy<=1;end
    else set_error<=1;
   end
   if(tick)begin
    if(state==IDLE)begin
     rtc_clk<=0;rtc_ce<=0;dat_enable<=0;
     if(pending||accept_request||initializing)begin
      setting<=pending||accept_request;pending<=0;initializing<=0;operation<=UNLOCK;
      state<=BEGIN_TRANSFER;timer<=TIMEOUT_TICKS;time_valid<=0;
     end else if(timer==0)begin
      operation<=POLL;state<=BEGIN_TRANSFER;timer<=TIMEOUT_TICKS;
     end else timer<=timer-1'b1;
    end else if(timer==0)begin
     rtc_clk<=0;rtc_ce<=0;dat_enable<=0;state<=IDLE;
     timer<=POLL_TICKS-1;time_valid<=0;
     if(setting)begin set_busy<=0;set_error<=1;set_fault<=1;setting<=0;end
    end else begin
     timer<=timer-1'b1;
     case(state)
      BEGIN_TRANSFER:begin
       rtc_ce<=1;rtc_clk<=0;dat_enable<=1;dat_out<=next_command[0];
       shift<=next_command;phase<=0;bit_count<=0;byte_index<=0;
       command_done<=0;reading<=0;bad_fields<=0;state<=SETUP;
      end
      SETUP:if(phase==1)begin phase<=0;state<=TRANSFER;end else phase<=1;
      TRANSFER:begin
       phase<=phase+1'b1;
       case(phase)
        0:if(!reading)dat_out<=shift[0];
        1:begin
         // Sample the stable low-half data before raising CLK. The chip
         // may release DAT after that edge; do not sample it later high.
         rtc_clk<=1;
         if(reading)shift<={dat_sync2,shift[7:1]};
        end
        2:if(!command_done&&bit_count==7&&next_command[0])dat_enable<=0;
        3:begin
         rtc_clk<=0;
         if(bit_count==7)begin
          bit_count<=0;
          if(!command_done)begin
           command_done<=1;reading<=next_command[0];
           shift<=next_command[0]?8'd0:write_byte(operation,0);
          end else begin
           if(reading&&operation!=CHECK_CHARGE)begin
            bad_fields<=bad_fields||invalid_byte(byte_index,shift);
            case(byte_index)
             0:shadow[7:0]<=shift;1:shadow[15:8]<=shift;2:shadow[23:16]<=shift;
             3:shadow[31:24]<=shift;4:shadow[39:32]<=shift;6:shadow[47:40]<=shift;
            endcase
           end
           if(!long_transfer||byte_index==7)state<=STOP;
           else begin byte_index<=byte_index+1'b1;shift<=reading?8'd0:write_byte(operation,byte_index+1'b1);end
          end
         end else begin bit_count<=bit_count+1'b1;if(!reading)shift<={1'b0,shift[7:1]};end
        end
       endcase
      end
      STOP:begin rtc_ce<=0;dat_enable<=0;phase<=0;state<=GAP;end
      GAP:if(phase==1)begin phase<=0;state<=EVALUATE;end else phase<=1;
      EVALUATE:begin
       state<=BEGIN_TRANSFER;timer<=TIMEOUT_TICKS;
       case(operation)
        UNLOCK:operation<=CHARGE_OFF;
        CHARGE_OFF:operation<=setting?CALENDAR:PROTECT;
        CALENDAR:operation<=PROTECT;
        PROTECT:operation<=CHECK_CHARGE;
        CHECK_CHARGE:if(shift==0)operation<=VERIFY;
         else begin
          state<=IDLE;timer<=POLL_TICKS-1;time_valid<=0;set_fault<=1;
          if(setting)begin setting<=0;set_busy<=0;set_error<=1;end
         end
        default:begin
         state<=IDLE;timer<=POLL_TICKS-1;
         if(!bad_fields&&calendar_ok&&(!setting||shadow==target)&&
            (operation==VERIFY||!set_fault))begin
          time_bcd<=shadow;time_valid<=1;
          if(setting)begin set_fault<=0;setting<=0;set_busy<=0;set_done<=1;end
         end else begin
          time_valid<=0;
          if(setting)begin set_fault<=1;setting<=0;set_busy<=0;set_error<=1;end
         end
        end
       endcase
      end
      default:begin state<=IDLE;timer<=0;rtc_ce<=0;rtc_clk<=0;dat_enable<=0;time_valid<=0;end
     endcase
    end
   end
  end
 end
endmodule
