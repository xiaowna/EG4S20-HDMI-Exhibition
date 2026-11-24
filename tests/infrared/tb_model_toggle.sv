`timescale 1ns/1ps
module tb_ir_model_toggle;
 reg clk=0,rst_n=0,enable=1,infrared_n=1,key_settings_down=0,key_settings_press=0;
 always #10 clk=~clk;
 wire [3:0] infrared_event,direction_event;
 wire home_event,back_event,model_event,learning,learning_enter,paired;
 wire [2:0] learning_led;integer checks=0;
 media_infrared_control #(.HOME_KEY(1),.FIXED_ENABLE(1),.LEARN_ENABLE(0),
  .FIXED_KEYS(48'h000915074316),.EXTRA_ENABLE(1),.BACK_COMMAND(8'h0d),.ZOOM_COMMAND(8'h46),.MODEL_COMMAND(8'h45),
  .FIRST_REPEAT_TICKS(20),.NEXT_REPEAT_TICKS(8)) dut(.zoom_event(),.gallery_navigation(1'b0),.home_navigation(1'b0),.*);
 task cycles(input integer n);begin repeat(n)@(negedge clk);#2;end endtask
 task send(input [7:0] a,c,input bit rep,expected);
  begin
   dut.receiver.frame_address=a;dut.receiver.frame_command=c;dut.receiver.frame_repeat=rep;
   dut.receiver.frame_valid=1;cycles(1);
   if(model_event!==expected)$fatal(1,"model event: address=%02x command=%02x repeat=%b got=%b expected=%b",a,c,rep,model_event,expected);
   if(infrared_event||direction_event||home_event||back_event)$fatal(1,"model leaked navigation");
   dut.receiver.frame_valid=0;cycles(1);
   if(model_event!==0)$fatal(1,"model event exceeds one clock");
   cycles(1);checks=checks+1;
  end
 endtask
 initial begin
  cycles(4);rst_n=1;cycles(4);
  send(0,8'h45,1,0);send(1,8'h45,0,0);send(0,8'h44,0,0);
  send(0,8'h45,0,1);
  send(0,8'h45,1,0);cycles(30);send(0,8'h45,1,0);
  send(0,8'h45,0,0); // Full-frame repeats also count as the held press.
  cycles(18005);send(0,8'h45,1,0);send(0,8'h45,0,1);
  enable=0;cycles(2);send(0,8'h45,0,0);enable=1;cycles(2);
  send(0,8'h45,1,0);send(0,8'h45,0,1);
  rst_n=0;cycles(3);
  if(model_event!==0)$fatal(1,"reset leaked model event");
  rst_n=1;cycles(3);send(0,8'h45,0,1);
  $display("PASS IR model toggle: %0d cases, 0045 one-clock pulse, wrong address/unknown/orphan/stale/held/full-repeat rejection, disable and reset",checks);$finish;
 end
 initial begin #2000000;$fatal(1,"IR model toggle timeout");end
endmodule
