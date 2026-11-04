// Clock draft editor. The draft is frozen from request until completion.
// Fields: year/month/date/hour/minute/second, then save and cancel.
module rtc_set_control(
 input wire clk,rst_n,enable,input wire [3:0] key_press,
 input wire [47:0] time_bcd,input wire time_valid,
 input wire set_busy,set_done,set_error,
 output reg [47:0] draft,output reg [2:0] field,
 output reg [1:0] status,output reg set_request,exit_request);
 reg enabled;
 reg [7:0] value,minimum,maximum,next_value;
 reg [3:0] next_units,next_tens;
 reg [47:0] candidate;
 wire right=key_press[0]&&!key_press[2];
 wire left=key_press[2]&&!key_press[0];
 function [7:0] last_day;
  input [7:0] year,month;
  begin case(month)
   8'h02:last_day=(year[1:0]=={year[4],1'b0})?8'h29:8'h28;
   8'h04,8'h06,8'h09,8'h11:last_day=8'h30;
   default:last_day=8'h31;
  endcase end
 endfunction
 always @*begin
  minimum=0;maximum=8'h59;
  case(field)
   0:begin value=draft[47:40];maximum=8'h99;end
   1:begin value=draft[39:32];minimum=1;maximum=8'h12;end
   2:begin value=draft[31:24];minimum=1;maximum=last_day(draft[47:40],draft[39:32]);end
   3:begin value=draft[23:16];maximum=8'h23;end
   4:value=draft[15:8];
   default:value=draft[7:0];
  endcase
  // Draft fields start valid and stay valid. One BCD digit adder per nibble
  // avoids four whole-byte correction adders and magnitude comparators.
  next_units=value[3:0]+(right?4'd1:4'hf);next_tens=value[7:4];
  if(right?(value[3:0]==9):(value[3:0]==0))begin
   next_units=right?0:9;
   next_tens=value[7:4]+(right?4'd1:4'hf);
  end
  next_value={next_tens,next_units};
  if(right?(value==maximum):(value==minimum))next_value=right?minimum:maximum;
  candidate=draft;
  case(field)
   0:candidate[47:40]=next_value;1:candidate[39:32]=next_value;
   2:candidate[31:24]=next_value;3:candidate[23:16]=next_value;
   4:candidate[15:8]=next_value;5:candidate[7:0]=next_value;
  endcase
  // Changing month/year cannot leave February 30 or an invalid leap day.
  if(candidate[31:24]>last_day(candidate[47:40],candidate[39:32]))
   candidate[31:24]=last_day(candidate[47:40],candidate[39:32]);
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   enabled<=0;draft<=48'h000101000000;field<=0;status<=0;set_request<=0;exit_request<=0;
  end else begin
   enabled<=enable;set_request<=0;exit_request<=0;
   if(set_done)status<=2;
   else if(set_error)status<=3;
   else if(enable&&!enabled&&!set_busy)begin
    draft<=time_valid?time_bcd:48'h000101000000;field<=0;status<=0;
   end else if(enable&&!set_busy&&!set_request)begin
    if(key_press[3])exit_request<=1;
    else if(key_press[1])begin
     if(status==2||field==7)exit_request<=1;
     else if(field==6)begin set_request<=1;status<=1;end
     else begin field<=field+1'b1;status<=0;end
    end else if(right||left)begin
     status<=0;
     if(field>=6)field<=field^3'b001;
     else draft<=candidate;
    end
   end
  end
 end
endmodule
