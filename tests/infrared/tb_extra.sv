`timescale 1ns/1ps
module tb_ir_extra;
 reg clk=0,rst_n=0,enable=1,infrared_n=1,key_settings_down=0,key_settings_press=0;
 wire [3:0] infrared_event,direction_event;wire home_event,back_event,easter_toggle,model_event,learning,learning_enter,paired;
 wire [2:0] learning_led;integer backs=0,ordinary=0;
 always #10 clk=~clk;
 media_infrared_control #(.HOME_KEY(1),.FIXED_ENABLE(1),.LEARN_ENABLE(0),
  .FIXED_KEYS(48'h000915074316),.EXTRA_ENABLE(1),.BACK_COMMAND(8'h0d),.EGG_A(8'h46),.EGG_B(8'h45)) dut(.*);
 always @(posedge clk)begin #1;if(rst_n)begin
  if(back_event)backs=backs+1;
  if(infrared_event||home_event)ordinary=ordinary+1;
 end end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task send(input [7:0] a,c,input bit rep);
 begin
  @(negedge clk);dut.receiver.frame_address=a;dut.receiver.frame_command=c;
  dut.receiver.frame_repeat=rep;dut.receiver.frame_valid=1;
  @(negedge clk);dut.receiver.frame_valid=0;cycles(2);
 end endtask
 task secret;
 begin send(0,8'h46,0);send(0,8'h45,0);send(0,8'h46,0);send(0,8'h45,0);end
 endtask
 initial begin
  cycles(4);rst_n=1;cycles(4);
  send(0,8'h0d,0);send(0,8'h0d,1);send(0,8'h0d,0);
  if(backs!=1||ordinary)$fatal(1,"BACK repeated or leaked navigation");
  send(1,8'h46,0);send(1,8'h45,0);send(1,8'h46,0);send(1,8'h45,0);
  if(easter_toggle)$fatal(1,"wrong address secret");
  send(0,8'h46,0);send(0,8'h46,1);send(0,8'h46,0);send(0,8'h45,0);
  if(easter_toggle)$fatal(1,"held key advanced secret");
  send(0,8'h46,0);send(0,8'h45,0);
  if(!easter_toggle||ordinary)$fatal(1,"four-key sequence or event isolation");
  secret();if(easter_toggle)$fatal(1,"second complete sequence must retrigger");
  send(0,8'h46,0);send(0,8'h43,0);send(0,8'h45,0);send(0,8'h46,0);send(0,8'h45,0);
  if(easter_toggle)$fatal(1,"unrelated key did not reset secret");
  enable=0;cycles(4);enable=1;cycles(4);
  send(0,8'h46,0);send(0,8'h45,0);if(easter_toggle)$fatal(1,"partial sequence survived disable");
  rst_n=0;cycles(4);rst_n=1;cycles(4);
  if(easter_toggle||!paired)$fatal(1,"reset state");
  $display("PASS IR extras: actual BACK, held/repeat suppression, address fence, exact secret/retrigger, wrong sequence and reset/block isolation");$finish;
 end
 initial begin #1000000;$fatal(1,"IR extra timeout");end
endmodule
