`timescale 1ns/1ps
module tb_ir_extra;
 reg clk=0,rst_n=0,enable=1,infrared_n=1,key_settings_down=0,key_settings_press=0;
 wire [3:0] infrared_event,direction_event;wire home_event,back_event,zoom_event,model_event,learning,learning_enter,paired;
 wire [2:0] learning_led;integer backs=0,zooms=0,models=0,ordinary=0;
 always #10 clk=~clk;
 media_infrared_control #(.HOME_KEY(1),.FIXED_ENABLE(1),.LEARN_ENABLE(0),
  .FIXED_KEYS(48'h000915074316),.EXTRA_ENABLE(1),.BACK_COMMAND(8'h0d),.ZOOM_COMMAND(8'h46),.MODEL_COMMAND(8'h45)) dut(.gallery_navigation(1'b0),.home_navigation(1'b0),.*);
 always @(posedge clk)begin #1;if(rst_n)begin
  if(back_event)backs=backs+1;
  if(zoom_event)zooms=zooms+1;
  if(model_event)models=models+1;
  if(infrared_event||direction_event||home_event)ordinary=ordinary+1;
 end end
 task cycles(input integer n);repeat(n)@(negedge clk);endtask
 task send(input [7:0] a,c,input bit rep);
 begin
  @(negedge clk);dut.receiver.frame_address=a;dut.receiver.frame_command=c;
  dut.receiver.frame_repeat=rep;dut.receiver.frame_valid=1;
  @(negedge clk);dut.receiver.frame_valid=0;cycles(2);
 end endtask
 initial begin
  cycles(4);rst_n=1;cycles(4);
  send(0,8'h0d,0);send(0,8'h0d,1);send(0,8'h0d,0);
  if(backs!=1||ordinary)$fatal(1,"BACK repeated or leaked navigation");
  send(1,8'h46,0);send(1,8'h45,0);
  if(zooms||models||ordinary)$fatal(1,"wrong address emitted a scene command");
  send(0,8'h46,0);send(0,8'h46,1);send(0,8'h46,0);
  send(0,8'h45,0);send(0,8'h45,1);send(0,8'h45,0);
  send(0,8'h46,0);send(0,8'h45,0);
  if(zooms!=2||models!=2||ordinary)$fatal(1,"scene commands repeated or leaked navigation");
  enable=0;cycles(4);send(0,8'h46,0);send(0,8'h45,0);
  if(zooms!=2||models!=2)$fatal(1,"blocked scene command emitted");
  rst_n=0;cycles(4);enable=1;rst_n=1;cycles(4);
  if(!paired)$fatal(1,"fixed remote lost after reset");
  $display("PASS IR extras: BACK and both scene keys, exact command counts, repeated/wrong-address/disabled rejection");$finish;
 end
 initial begin #1000000;$fatal(1,"IR extra timeout");end
endmodule
