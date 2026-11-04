`timescale 1ns/1ps
module tb_rtc_defaults;
 reg clk=0,rst_n=0;
 tri1 rtc_scl,rtc_sda;
 wire [47:0] time_bcd;wire time_valid;
 rtc_ds3231 dut(.*,.set_request(1'b0),.set_bcd(48'd0),.set_busy(),.set_done(),.set_error());
 ds3231_model model(.rst_n(rst_n),.scl(rtc_scl),.sda(rtc_sda));
 always #10 clk=~clk;
 time stopped,next_start;
 initial begin
  #1;model.registers[3]=1;model.registers[4]=1;model.registers[5]=1;
  #199;rst_n=1;
  wait(model.stops==1);stopped=$time;
  wait(model.starts==3);next_start=$time;
  if(next_start-stopped<250000000||next_start-stopped>250015000)
   $fatal(1,"default poll interval wrong: %0t",next_start-stopped);
  wait(model.stops==2);wait(time_valid);
  if(time_bcd!==48'h000101000000)$fatal(1,"default calendar");
  $display("PASS RTC default timing: 50MHz clock, 100kHz maximum I2C, poll gap_ns=%0d",next_start-stopped);$finish;
 end
 initial begin #300000000;$fatal(1,"default RTC polling timeout");end
endmodule
