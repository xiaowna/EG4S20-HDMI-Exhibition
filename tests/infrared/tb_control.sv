`timescale 1ns/1ps
// Unit injection isolates learning/repeat policy; the board test uses real NEC.
module media_nec_receiver #(parameter SAMPLE_CYCLES=500)(
 input wire clk,rst_n,enable,infrared_n,output wire sample_tick,
 output reg frame_valid,frame_repeat,
 output reg [7:0] frame_address,frame_command);
 initial begin frame_valid=0;frame_repeat=0;frame_address=0;frame_command=0;end
 assign sample_tick=1'b1;
endmodule
module tb_ir_control;
 reg clk=0,rst_n=0,enable=1,infrared_n=1,key_settings_down=0,key_settings_press=0;
 always #10 clk=~clk;
 wire [3:0] infrared_event,direction_event;wire home_event,back_event,model_event,learning,learning_enter,paired;wire [2:0] learning_led;
 media_infrared_control #(.SAMPLE_CYCLES(1),.RELEASE_TICKS(4),.LEARN_HOLD_TICKS(12),
  .LEARN_TIMEOUT_TICKS(400),.FIRST_REPEAT_TICKS(20),.NEXT_REPEAT_TICKS(8)) dut(.zoom_event(),.gallery_navigation(1'b0),.home_navigation(1'b0),.*);
 integer right=0,left=0,ok=0,back=0,entered=0,checks=0;
 reg [3:0] old_event=0;
 always @(posedge clk)begin #1;
  if(rst_n)begin
   if(infrared_event!=0&&infrared_event!=1&&infrared_event!=2&&infrared_event!=4&&infrared_event!=8)$fatal(1,"bad mapped event");
   if(old_event!=0&&infrared_event!=0)$fatal(1,"event width");
   if(learning&&infrared_event)$fatal(1,"learning leaked event");
   if(infrared_event[0])right=right+1;if(infrared_event[1])ok=ok+1;
   if(infrared_event[2])left=left+1;if(infrared_event[3])back=back+1;
   if(learning_enter)entered=entered+1;
  end
  old_event=infrared_event;
 end
 task cycles(input integer n);begin repeat(n)@(negedge clk);#2;end endtask
 task send(input [7:0] a,c,input bit rep);begin
  dut.receiver.frame_address=a;dut.receiver.frame_command=c;dut.receiver.frame_repeat=rep;
  dut.receiver.frame_valid=1;cycles(1);dut.receiver.frame_valid=0;cycles(2);
 end endtask
 task start_learning;begin
  key_settings_down=0;cycles(8);key_settings_down=1;cycles(15);key_settings_down=0;cycles(3);
  if(!learning||learning_led!=1)$fatal(1,"learning entry");
 end endtask
 task check_counts(input integer r,l,o,b);begin
  if(right!=r||left!=l||ok!=o||back!=b)$fatal(1,"counts %0d/%0d/%0d/%0d expected %0d/%0d/%0d/%0d",right,left,ok,back,r,l,o,b);
  checks=checks+1;
 end endtask
 initial begin
  cycles(4);rst_n=1;cycles(8);send(8'h42,8'ha1,0);check_counts(0,0,0,0);
  start_learning;send(8'h42,8'ha1,0);if(learning_led!=2)$fatal(1,"right learning");
  send(8'h42,8'ha1,1);send(8'h42,8'ha1,0);send(8'h43,8'h12,0);
  if(learning_led!=2||paired)$fatal(1,"repeat/duplicate/address admitted");
  send(8'h42,8'h12,0);send(8'h42,8'h33,0);send(8'h42,8'hb4,0);
  if(learning||!paired)$fatal(1,"atomic commit");check_counts(0,0,0,0);
  // Completion key held via either NEC repeats or complete-frame repeats.
  send(8'h42,8'hb4,1);send(8'h42,8'hb4,0);check_counts(0,0,0,0);
  send(8'h42,8'ha1,0);check_counts(1,0,0,0);
  send(8'h42,8'ha1,1);check_counts(1,0,0,0);cycles(22);
  send(8'h42,8'ha1,1);check_counts(2,0,0,0);
  send(8'h42,8'ha1,1);check_counts(2,0,0,0);cycles(9);
  send(8'h42,8'ha1,1);check_counts(3,0,0,0);
  send(8'h42,8'h12,0);cycles(24);send(8'h42,8'h12,1);send(8'h42,8'h12,0);check_counts(3,0,1,0);
  send(8'h42,8'h33,0);send(8'h42,8'hb4,0);check_counts(3,1,1,1);
  send(8'h44,8'ha1,0);send(8'h42,8'h99,0);check_counts(3,1,1,1);
  start_learning;send(8'h55,8'h71,0);send(8'h55,8'h72,0);
  key_settings_press=1;cycles(1);key_settings_press=0;cycles(2);
  if(learning||!paired)$fatal(1,"cancel lost old map");send(8'h42,8'ha1,0);check_counts(4,1,1,1);
  start_learning;send(8'h55,8'h71,0);cycles(405);
  if(learning||!paired)$fatal(1,"timeout lost old map");send(8'h42,8'h33,0);check_counts(4,2,1,1);
  start_learning;send(8'h55,8'h71,0);enable=0;cycles(2);enable=1;cycles(8);
  if(learning||!paired)$fatal(1,"mode block lost old map");send(8'h42,8'ha1,0);check_counts(5,2,1,1);
  // No decoder-association stub guarantee here: stale repeat still needs a recent mapped press.
  cycles(18005);send(8'h42,8'ha1,1);check_counts(5,2,1,1);
  if(dut.recent_valid)$fatal(1,"stale repeat rearmed a held press");
  send(8'h42,8'ha1,0);check_counts(6,2,1,1);
  if(dut.repeat_started)$fatal(1,"fresh press retained repeat state");
  // Startup key held is never interpreted as a new 2-second gesture.
  key_settings_down=1;rst_n=0;cycles(4);rst_n=1;cycles(40);
  if(learning||paired)$fatal(1,"reset held learning or persistent map");
  key_settings_down=0;cycles(8);start_learning;
  send(8'h68,8'h71,0);send(8'h68,8'h72,0);send(8'h68,8'h73,0);send(8'h68,8'h74,0);
  if(!paired||learning)$fatal(1,"fresh address pairing");send(8'h68,8'h71,0);check_counts(7,2,1,1);
  $display("PASS IR learning control checks=%0d: four distinct learned keys, address binding, atomic commit, cancellation/timeout/block rollback, repeat throttling, no repeated OK/settings, held-reset and re-pair",checks);$finish;
 end
 initial begin #10000000;$fatal(1,"IR control timeout");end
endmodule
