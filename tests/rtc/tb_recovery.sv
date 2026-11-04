`timescale 1ns/1ps
// The RTC remains powered across a master reset. Model its outstanding low
// data/ACK until any of nine recovery edges, then require immediate START.
// This specifically rejects clocking the remaining pulses after SDA releases.
module tb_rtc_recovery;
 reg clk=0,rst_n=0,slave_ready=0,held_data=1,awaiting_start=0;
 tri1 rtc_scl,rtc_sda;
 assign rtc_sda=held_data?1'b0:1'bz;
 wire [47:0] time_bcd;wire time_valid;
 always #10 clk=~clk;
 rtc_ds3231 #(.POLL_TICKS(20)) dut(.*,.set_request(1'b0),.set_bcd(48'd0),.set_busy(),.set_done(),.set_error());
 ds3231_model rtc(.rst_n(slave_ready),.scl(rtc_scl),.sda(rtc_sda));
 integer n,k,starts_before;
 always @(negedge rtc_sda)if(awaiting_start&&rtc_scl===1)awaiting_start=0;
 always @(negedge rtc_scl)if(awaiting_start)$fatal(1,"extra clock after SDA released: would risk an interrupted write");
 initial begin
  #1;rtc.registers[0]=8'h56;rtc.registers[1]=8'h34;rtc.registers[2]=8'h12;
  rtc.registers[3]=3;rtc.registers[4]=8'h21;rtc.registers[5]=8'h10;rtc.registers[6]=8'h26;
  for(n=1;n<=9;n=n+1)begin
   rst_n=0;slave_ready=0;held_data=1;awaiting_start=0;
   repeat(5)@(negedge clk);rst_n=1;
   // Release only on a falling edge, as a real slave changes its data/ACK.
   for(k=0;k<n;k=k+1)@(negedge rtc_scl);
   #1;held_data=0;slave_ready=1;awaiting_start=1;starts_before=rtc.starts;
   wait(rtc.starts>starts_before);wait(time_valid);#1;
   if(awaiting_start||time_bcd!==48'h261021123456)$fatal(1,"recovered calendar or START invalid");
   // The model's calendar was not reinitialized when the master reset.
   if(rtc.registers[0]!==8'h56||rtc.registers[6]!==8'h26)$fatal(1,"calendar changed during recovery");
  end
  $display("PASS RTC powered-slave recovery: all 9 SDA-release positions, immediate START without extra clocks, calendar retained");$finish;
 end
 initial begin #30000000;$fatal(1,"RTC powered-slave recovery timeout");end
endmodule
