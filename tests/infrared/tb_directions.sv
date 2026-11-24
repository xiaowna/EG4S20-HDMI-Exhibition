`timescale 1ns/1ps
// Receiver injection isolates the shared address/repeat policy. The board
// companion test drives the actual NEC decoder from the external IR pin.
module tb_ir_directions;
 reg clk=0,rst_n=0,enable=1,infrared_n=1,key_settings_down=0,key_settings_press=0;
 always #10 clk=~clk;
 wire [3:0] infrared_event,direction_event;
 wire home_event,back_event,model_event,learning,learning_enter,paired;
 wire [2:0] learning_led;
 media_infrared_control #(.HOME_KEY(1),.FIXED_ENABLE(1),.LEARN_ENABLE(0),
  .FIXED_KEYS(48'h000915074316),.EXTRA_ENABLE(1),.BACK_COMMAND(8'h0d),.ZOOM_COMMAND(8'h46),.MODEL_COMMAND(8'h45),
  .DIRECTION_ENABLE(1),.UP_COMMAND(8'h40),.DOWN_COMMAND(8'h19),
  .FIRST_REPEAT_TICKS(20),.NEXT_REPEAT_TICKS(8)) dut(.zoom_event(),.gallery_navigation(1'b0),.home_navigation(1'b0),.*);
 integer directions[0:3];integer ordinary[0:3];integer homes=0,backs=0,checks=0,i;
 reg [3:0] old_direction=0;
 always @(posedge clk)begin #1;
  if(rst_n)begin
   if(direction_event!=0&&direction_event!=1&&direction_event!=2&&direction_event!=4&&direction_event!=8)
    $fatal(1,"non-atomic IR direction");
   if(old_direction!=0&&direction_event!=0)$fatal(1,"IR direction pulse wider than one clock");
   if((!enable||learning)&&direction_event)$fatal(1,"blocked direction leaked");
   for(integer k=0;k<4;k=k+1)begin
    if(direction_event[k])directions[k]=directions[k]+1;
    if(infrared_event[k])ordinary[k]=ordinary[k]+1;
   end
   if(home_event)homes=homes+1;if(back_event)backs=backs+1;
  end
  old_direction=direction_event;
 end
 task cycles(input integer n);begin repeat(n)@(negedge clk);#2;end endtask
 task send(input [7:0] a,c,input bit rep,input [3:0] expected_direction,expected_ordinary);
  begin
   dut.receiver.frame_address=a;dut.receiver.frame_command=c;dut.receiver.frame_repeat=rep;
   dut.receiver.frame_valid=1;cycles(1);
   if(direction_event!==expected_direction||infrared_event!==expected_ordinary)
    $fatal(1,"command %02x addr %02x repeat %b: direction=%b ordinary=%b expected=%b/%b",c,a,rep,direction_event,infrared_event,expected_direction,expected_ordinary);
   dut.receiver.frame_valid=0;cycles(2);checks=checks+1;
  end
 endtask
 initial begin
  for(i=0;i<4;i=i+1)begin directions[i]=0;ordinary[i]=0;end
  cycles(4);rst_n=1;cycles(4);
  if(!paired||learning)$fatal(1,"fixed remote must work immediately after reset");
  send(0,8'h40,1,0,0); // Orphan repeat cannot establish a new press.
  send(1,8'h40,0,0,0);
  send(0,8'h40,0,4,0);
  send(0,8'h40,1,0,0);cycles(22);send(0,8'h40,1,4,0);
  send(0,8'h40,1,0,0);cycles(9);send(0,8'h40,1,4,0);
  cycles(9);send(0,8'h40,0,4,0); // Remotes repeating complete frames use the same throttle.
  send(0,8'h19,0,8,0);
  send(0,8'h19,1,0,0);cycles(22);send(0,8'h19,1,8,0);
  send(0,8'h09,0,1,1);send(0,8'h07,0,2,4);
  send(0,8'h15,0,0,2);send(0,8'h43,0,0,8);
  send(0,8'h16,0,0,0);send(0,8'h0d,0,0,0);
  if(homes!=1||backs!=1)$fatal(1,"HOME/BACK mapping changed");
  send(0,8'h46,0,0,0);send(0,8'h45,0,0,0);send(0,8'h46,0,0,0);send(0,8'h45,0,0,0);
  send(0,8'hff,0,0,0);send(1,8'h19,0,0,0);
  enable=0;cycles(2);send(0,8'h40,0,0,0);enable=1;cycles(2);
  send(0,8'h40,1,0,0);send(0,8'h40,0,4,0);
  cycles(18005);send(0,8'h40,1,0,0);
  rst_n=0;cycles(3);rst_n=1;cycles(3);send(0,8'h19,0,8,0);
  if(!paired||learning)$fatal(1,"reset lost fixed directional map");
  if(directions[0]!=1||directions[1]!=1||directions[2]!=5||directions[3]!=3)
   $fatal(1,"unexpected direction totals %0d/%0d/%0d/%0d",directions[0],directions[1],directions[2],directions[3]);
  $display("PASS IR directions: %0d directed cases, captured 0040/0019, address binding, one-cycle atomic events, repeat pacing, disable/stale/orphan rejection, HOME/BACK/zoom/model isolation and reset defaults",checks);$finish;
 end
 initial begin #2000000;$fatal(1,"direction policy timeout");end
endmodule
