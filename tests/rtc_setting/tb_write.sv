`timescale 1ns/1ps
module tb_rtc_write;
 parameter QUARTER=5;
 reg clk=0,rst_n=0,set_request=0,hold_scl=0;
 reg [47:0] set_bcd=48'h261021123456;
 tri1 rtc_scl,rtc_sda;
 assign rtc_scl=hold_scl?1'b0:1'bz;
 wire [47:0] time_bcd;wire time_valid,set_busy,set_done,set_error;
 always #10 clk=~clk;
 rtc_ds3231 #(.WRITE_ENABLE(1),.QUARTER_CYCLES(QUARTER),.POLL_TICKS(40)) dut(.*);
 ds3231_write_model model(.rst_n(rst_n),.scl(rtc_scl),.sda(rtc_sda));
 time rise_time=0,fall_time=0,data_time=0,start_time=0;
 reg monitor=0;
 always @(negedge rtc_scl)if(monitor)begin
  if(QUARTER==125&&rise_time&&$time-rise_time<4000)$fatal(1,"write SCL high below 4us");
  if(QUARTER==125&&start_time&&$time-start_time<4000)$fatal(1,"write START hold below 4us");
  fall_time=$time;start_time=0;
 end
 always @(posedge rtc_scl)if(monitor)begin
  if(QUARTER==125&&fall_time&&$time-fall_time<4700)$fatal(1,"write SCL low below 4.7us");
  if(QUARTER==125&&data_time&&$time-data_time<250)$fatal(1,"write data setup below 250ns");
  rise_time=$time;
 end
 always @(rtc_sda)if(monitor)begin
  data_time=$time;
  if(rtc_scl===1)begin
   if(QUARTER==125&&$time-rise_time<(rtc_sda===0?4700:4000))$fatal(1,"write START/STOP setup");
   if(rtc_sda===0)start_time=$time;
  end
 end
 task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 task fresh;
  begin
   monitor=0;rst_n=0;repeat(3)tick;
   model.nack_transaction=-1;model.nack_byte=-1;model.corrupt_read=0;
   model.registers[0]=0;model.registers[1]=0;model.registers[2]=0;model.registers[3]=1;
   model.registers[4]=1;model.registers[5]=1;model.registers[6]=0;model.registers[15]=8'h8b;
   rst_n=1;rise_time=0;fall_time=0;data_time=0;start_time=0;monitor=1;
  end
 endtask
 task request;
  begin set_request=1;tick;set_request=0;end
 endtask
 task finished(input integer success);
  integer n;
  begin:waiting
   for(n=0;n<QUARTER*18000;n=n+1)begin
    tick;
    if(set_done||set_error)begin
     if(set_done!==success[0]||set_busy!==0)$fatal(1,"save outcome wrong");
     if(success&&(time_bcd!==set_bcd||time_valid!==1))$fatal(1,"save published before verified");
     if(!success&&time_valid!==0)$fatal(1,"failed save reports valid time");
     disable waiting;
    end
   end
   $fatal(1,"save timeout");
  end
 endtask
 integer n,j,base_writes,base_status,base_transaction;
 initial begin
  fresh;wait(model.stops>0);base_writes=model.writes;
  if(time_valid!==0)$fatal(1,"OSF must show invalid before setting");
  // No request: polling must never write a data register.
  repeat(QUARTER*10000)tick;
  if(model.writes!=base_writes)$fatal(1,"poll wrote registers without confirmation");
  for(n=0;n<4;n=n+1)begin
   case(n)
    0:set_bcd=48'h000229000000;1:set_bcd=48'h240229235959;
    2:set_bcd=48'h261231123456;3:set_bcd=48'h991231235959;
   endcase
   base_writes=model.writes;base_status=model.status_writes;
   request;finished(1);
   if(model.writes-base_writes!=8||model.status_writes-base_status!=1)$fatal(1,"wrong write scope");
   if(model.registers[15]!==8'h0b)$fatal(1,"OSF clearing damaged other status flags");
   if(model.registers[7]!==0||model.registers[14]!==0)$fatal(1,"save modified alarms/control");
   repeat(3)tick;
  end
  // Every byte ACK of calendar write, verification, status write and final read.
  for(n=0;n<4;n=n+1)begin
   for(j=0;j<(n==0?9:3);j=j+1)begin
    fresh;wait(dut.state==0);base_transaction=model.transaction_index+1;
    model.nack_transaction=base_transaction+n;model.nack_byte=j;
    request;finished(0);
    // Failed verification must not clear OSF.
    if(n<2&&model.registers[15][7]!==1)$fatal(1,"cleared OSF before verified write");
   end
  end
  fresh;wait(dut.state==0);model.corrupt_read=1;request;finished(0);
  if(model.registers[15][7]!==1)$fatal(1,"mismatched readback cleared OSF");
  // Reject invalid calendar before touching the bus.
  fresh;set_bcd=48'h250229000000;base_writes=model.writes;request;
  if(set_error!==1||set_busy!==0||model.writes!=base_writes)$fatal(1,"invalid leap day accepted");
  // Bounded stuck-clock failure and explicit retry after reconnection.
  fresh;set_bcd=48'h261021123456;request;wait(dut.operation==1);monitor=0;hold_scl=1;
  finished(0);hold_scl=0;repeat(20)tick;request;finished(1);
  // FPGA reset restarts the bus master, not the powered RTC calendar.
  monitor=0;rst_n=0;repeat(3)tick;rst_n=1;wait(time_valid);tick;
  if(time_bcd!==set_bcd)$fatal(1,"FPGA reset lost stored RTC calendar");
  $display("PASS RTC save: four calendar boundaries, 18 ACK fault positions, readback mismatch, OSF preservation, invalid date, timeout/retry, no unsolicited writes; Q=%0d",QUARTER);
  $finish;
 end
 initial begin #300000000;$fatal(1,"RTC save overall timeout state=%d op=%d starts=%d stops=%d writes=%d",dut.state,dut.operation,model.starts,model.stops,model.writes);end
endmodule
