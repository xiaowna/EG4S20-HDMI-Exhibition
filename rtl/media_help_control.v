// Home-only help. All page keys are consumed before normal UI dispatch.
module media_help_control(input wire clk,rst_n,enable,open_event,close_event,
 input wire [3:0] key_event,output reg visible,output reg [1:0] page);
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin visible<=0;page<=0;end
  else if(!enable||close_event)begin visible<=0;page<=0;end
  else if(visible)begin
   if(key_event[3]||key_event[1])begin visible<=0;page<=0;end
   else if(key_event[0]&&!key_event[2])page<=page+1'b1;
   else if(key_event[2]&&!key_event[0])page<=page-1'b1;
  end else if(open_event&&key_event==0)begin visible<=1;page<=0;end
endmodule
