`timescale 1ns/1ps
// Stub tick is 1/clock: validate default counter widths and exact tick counts.
// tb_receiver separately validates the physical 500-clock / 10 us tick.
module tb_ir_thresholds;
 reg clk=0,rst_n=0,enable=1,infrared_n=1,key_settings_down=0,key_settings_press=0;
 always #10 clk=~clk;
 wire [3:0] infrared_event,direction_event;wire home_event,back_event,easter_toggle,model_event,learning,learning_enter,paired;wire [2:0] learning_led;
 media_infrared_control dut(.*);
 task cycles(input integer n);begin repeat(n)@(negedge clk);#2;end endtask
 initial begin
  cycles(4);rst_n=1;cycles(2500);
  if(!dut.learn_armed)$fatal(1,"default release interval");
  key_settings_down=1;cycles(199999);if(learning)$fatal(1,"early 2s threshold");
  cycles(1);if(!learning||!learning_enter)$fatal(1,"missing 200000-tick entry");
  key_settings_down=0;cycles(2999999);if(!learning)$fatal(1,"early 30s timeout");
  cycles(1);if(learning)$fatal(1,"missing 3000000-tick timeout");
  $display("PASS IR default counters: release=2500, hold=200000, timeout=3000000 ticks; no overflow");$finish;
 end
 initial begin #70000000;$fatal(1,"IR thresholds timeout");end
endmodule
