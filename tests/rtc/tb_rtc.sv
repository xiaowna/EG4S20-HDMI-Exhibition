`timescale 1ns/1ps
module tb_rtc;
 parameter integer QUARTER=5;
 reg clk=0,rst_n=0,hold_scl=0,hold_sda=0;
 tri1 rtc_scl,rtc_sda;
 assign rtc_scl=hold_scl?1'b0:1'bz;
 assign rtc_sda=hold_sda?1'b0:1'bz;
 wire [47:0] time_bcd;wire time_valid;
 always #10 clk=~clk;
 rtc_ds3231 #(.QUARTER_CYCLES(QUARTER),.POLL_TICKS(20),.TIMEOUT_TICKS(4000)) dut(.*,.set_request(1'b0),.set_bcd(48'd0),.set_busy(),.set_done(),.set_error());
 ds3231_model model(.rst_n(rst_n),.scl(rtc_scl),.sda(rtc_sda));
 integer fd,result,expected,index,count=0,k,old_stop,recovery_edges,target_start;
 reg [47:0] calendar,last_time;
 reg [7:0] weekday,status;
 reg [48:0] previous;
 time fall_time=0,rise_time=0,data_time=0,start_time=0;
 reg monitor=0;
 // This monitor uses nanoseconds, independent of the RTL's quarter counter.
 always @(negedge rtc_scl)if(monitor)begin
  if(QUARTER==125&&rise_time!=0&&$time-rise_time<4000)$fatal(1,"SCL high below 4us");
  if(QUARTER==125&&start_time!=0&&$time-start_time<4000)$fatal(1,"START hold below 4us");
  fall_time=$time;start_time=0;
 end
 always @(posedge rtc_scl)if(monitor)begin
  if(QUARTER==125&&fall_time!=0&&$time-fall_time<4700)$fatal(1,"SCL low below 4.7us");
  if(QUARTER==125&&data_time!=0&&$time-data_time<250)$fatal(1,"data setup below 250ns");
  rise_time=$time;
 end
 always @(rtc_sda)if(monitor)begin
  data_time=$time;
  if(rtc_scl===1)begin
   if(QUARTER==125&&$time-rise_time<(rtc_sda===0?4700:4000))$fatal(1,"START/STOP setup below specification");
   if(rtc_sda===0)start_time=$time;
  end
 end
 task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 task load(input [47:0] value,input [7:0] day,input [7:0] flags);
  begin
   model.registers[0]=value[7:0];model.registers[1]=value[15:8];model.registers[2]=value[23:16];
   model.registers[3]=day;model.registers[4]=value[31:24];model.registers[5]=value[39:32];
   model.registers[6]=value[47:40];model.registers[15]=flags;
  end
 endtask
 task fresh;
  begin rst_n=0;repeat(3)tick;rst_n=1;end
 endtask
 task completed;
  integer n;
  begin:wait_complete
   old_stop=model.stops;
   for(n=0;n<4500*QUARTER;n=n+1)begin
    tick;
    if(model.stops>old_stop&&dut.state==0)disable wait_complete;
   end
   $fatal(1,"RTC transaction did not complete");
  end
 endtask
 task failed_poll;
  integer n;
  begin
   last_time=time_bcd;
   wait(dut.state!=0);
   for(n=0;n<4100*QUARTER&&dut.state!=0;n=n+1)tick;
   if(dut.state!=0||time_valid!==0||time_bcd!==last_time)$fatal(1,"failure not bounded or overwrote prior calendar");
   if(dut.scl_low!==0||dut.sda_low!==0)$fatal(1,"failed transfer did not release bus");
  end
 endtask
 initial begin
  previous=0;repeat(3)tick;
  fd=$fopen("vectors.txt","r");if(!fd)$fatal(1,"missing vectors");
  while(!$feof(fd))begin
   result=$fscanf(fd,"%h %h %h %d\n",calendar,weekday,status,expected);
   if(result!=4)$fatal(1,"bad vector");
   load(calendar,weekday,status);fresh;monitor=1;completed;monitor=0;
   if(time_valid!==expected[0])$fatal(1,"validity case %0d calendar=%h weekday=%h status=%h expected=%d",count,calendar,weekday,status,expected);
   if(expected&&time_bcd!==calendar)$fatal(1,"calendar byte order or partial commit");
   if(!expected&&time_bcd!==0)$fatal(1,"bad calendar published");
   count=count+1;
  end
  $fclose(fd);
  load(48'h261021235959,3,0);fresh;monitor=1;completed;
  // Cross midnight during a burst: the chip's START snapshot stays coherent.
  target_start=model.starts+2;wait(model.starts>=target_start);#1;load(48'h261022000000,4,0);
  completed;
  if(time_bcd!==48'h261021235959)$fatal(1,"mid-burst calendar tore");
  completed;if(time_bcd!==48'h261022000000)$fatal(1,"next complete calendar missing");
  for(k=0;k<3;k=k+1)begin
   model.nack_stage=k;failed_poll;model.nack_stage=-1;completed;
   if(!time_valid)$fatal(1,"NACK recovery failed");
  end
  // One short clock stretch must be tolerated without changing any byte.
  for(k=0;k<3;k=k+1)begin
   wait(dut.state==3&&dut.phase==1);@(negedge clk);hold_scl=1;
   // Release off the quarter-clock boundary, emulating arbitrary slave delay.
   repeat(10*QUARTER+1+k*37)tick;hold_scl=0;completed;
   if(!time_valid||time_bcd!==48'h261022000000)$fatal(1,"clock stretch corrupted burst");
  end
  monitor=0;wait(dut.state==0);hold_scl=1;failed_poll;hold_scl=0;completed;
  if(!time_valid)$fatal(1,"stuck SCL recovery");
  // Abort/reset both master and slave, with SDA held low externally. Bus clear
  // emits at least nine clocks, times out, and succeeds after the fault clears.
  monitor=0;hold_sda=1;fresh;recovery_edges=0;
  fork
   begin repeat(9)begin @(posedge rtc_scl);recovery_edges=recovery_edges+1;end end
   begin failed_poll;end
  join
  if(recovery_edges!=9)$fatal(1,"missing nine bus-clear clocks");
  hold_sda=0;fresh;completed;if(!time_valid)$fatal(1,"SDA bus clear did not recover");
  wait(dut.state==3&&dut.command==3&&dut.byte_index==4);fresh;
  if(time_valid||time_bcd!=0)$fatal(1,"reset leaked partial calendar");
  completed;if(!time_valid)$fatal(1,"mid-burst reset recovery");
  $display("PASS RTC Q=%0d: %0d calendar vectors; ACK/NACK, START snapshot, stretch, stuck SCL/SDA, reset, retry",QUARTER,count);
  $finish;
 end
 initial begin #20000000000;$fatal(1,"RTC test global timeout");end
endmodule
