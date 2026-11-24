`timescale 1ns/1ps
module tb_ir_fixed;
 reg clk=0,rst_n=0,enable=1,infrared_n=1,key_settings_down=0,key_settings_press=0;
 wire [3:0] infrared_event,direction_event;wire home_event,back_event,model_event,learning,learning_enter,paired;wire [2:0] learning_led;
 always #10 clk=~clk;
 // Fixture only. The main board must use codes actually captured from its remote.
 media_infrared_control #(.HOME_KEY(1),.FIXED_ENABLE(1),.LEARN_ENABLE(0),
  .FIXED_KEYS(48'h425a1c081545),.LEARN_HOLD_TICKS(4),
  .FIRST_REPEAT_TICKS(20),.NEXT_REPEAT_TICKS(8)) dut(.zoom_event(),.gallery_navigation(1'b0),.home_navigation(1'b0),.*);
 integer right=0,ok=0,left=0,settings=0,home=0;
 always @(posedge clk)begin #1;
  if(rst_n)begin
   if(infrared_event[0])right=right+1;if(infrared_event[1])ok=ok+1;
   if(infrared_event[2])left=left+1;if(infrared_event[3])settings=settings+1;
   if(home_event)home=home+1;
   if(home_event&&infrared_event)$fatal(1,"HOME leaked ordinary event");
   if(learning||learning_enter)$fatal(1,"fixed firmware entered learning");
  end
 end
 task ticks(input integer n);repeat(n)@(negedge clk);endtask
 task send(input [7:0] a,c,input bit rep);
 begin
  @(negedge clk);dut.receiver.frame_address=a;dut.receiver.frame_command=c;
  dut.receiver.frame_repeat=rep;dut.receiver.frame_valid=1;
  @(negedge clk);dut.receiver.frame_valid=0;ticks(1);
 end
 endtask
 initial begin
  ticks(4);rst_n=1;ticks(4);if(!paired)$fatal(1,"fixed remote not ready at boot");
  send(8'h42,8'h5a,0);send(8'h42,8'h1c,0);send(8'h42,8'h08,0);send(8'h42,8'h15,0);send(8'h42,8'h45,0);
  if(right!=1||ok!=1||left!=1||settings!=1||home!=1)$fatal(1,"five fixed mappings");
  send(8'h42,8'h45,1);send(8'h42,8'h45,0);
  if(home!=1)$fatal(1,"held HOME repeated");
  send(8'h43,8'h5a,0);send(8'h42,8'h99,0);
  if(right!=1||home!=1)$fatal(1,"unknown address or command accepted");
  key_settings_down=1;key_settings_press=1;ticks(2);key_settings_press=0;ticks(50);
  key_settings_down=0;enable=0;send(8'h42,8'h08,0);enable=1;ticks(4);
  if(!paired||left!=1)$fatal(1,"blocking lost fixed configuration or leaked event");
  rst_n=0;ticks(4);rst_n=1;ticks(4);send(8'h42,8'h45,0);
  if(!paired||home!=2)$fatal(1,"reset required new learning");
  $display("PASS fixed five-key IR: boot/reset restoration, exact mappings, dedicated HOME, held HOME suppression, no learning, invalid codes and block fences");$finish;
 end
 initial begin #1000000;$fatal(1,"fixed IR timeout");end
endmodule
