`timescale 1ns/1ps
module tb_ds1302 #(parameter Q=5,STRICT=0);
 reg clk=0,rst_n=0,set_request=0;reg [47:0] set_bcd=0;
 wire rtc_clk,rtc_ce,time_valid,set_busy,set_done,set_error;tri0 rtc_dat;
 wire [47:0] time_bcd;
 integer success=0,failures=0,vectors=0,code,file,valid_expected,weekday,control,before_writes,before_calendar;
 reg [47:0] calendar;reg [7:0] charge_before;
 always #10 clk=~clk;
 rtc_ds1302 #(.WRITE_ENABLE(1),.QUARTER_CYCLES(Q),.POLL_TICKS(4)) dut(.*);
 ds1302_model #(.STRICT_TIMING(STRICT),.DATA_DELAY(STRICT?800:10),.RELEASE_DELAY(STRICT?280:10)) model(.ce(rtc_ce),.sclk(rtc_clk),.dat(rtc_dat));
 always @(posedge clk)begin
  if(rst_n&&dut.dat_enable&&model.output_enable&&model.connected)$fatal(1,"DS1302 DAT ownership collision");
  if(set_done)success=success+1;if(set_error)failures=failures+1;
 end
 task tick;begin @(negedge clk);#1;end endtask
 task fields(input [47:0] c,input integer w,input integer ctl);
  begin model.registers[0]=c[7:0];model.registers[1]=c[15:8];model.registers[2]=c[23:16];
   model.registers[3]=c[31:24];model.registers[4]=c[39:32];model.registers[5]=w;
   model.registers[6]=c[47:40];model.registers[7]=ctl;
  end
 endtask
 task read_result;
  integer reads;
  begin reads=model.clock_reads;wait(model.clock_reads>reads);wait(dut.state==0);tick;end
 endtask
 task save(input [47:0] c,input bit good);
  integer s,f;
  begin s=success;f=failures;tick;set_bcd=c;set_request=1;tick;set_request=0;
   // The editor freezes its draft, but the driver also owns a snapshot.
   set_bcd=48'h991231235959;
   wait(success>s||failures>f);tick;
   if(good?(success!=s+1||set_busy||!time_valid||time_bcd!==c):(failures!=f+1||set_busy))$fatal(1,"save/readback expected=%b success=%0d failures=%0d time=%h",good,success-s,failures-f,time_bcd);
  end
 endtask
 initial begin
  // Existing write protection and an enabled charger must be handled without
  // modifying the old clock. A halted oscillator stays invalid until save.
  model.charger=8'ha5;fields(48'h2610251234d6,7,128);
  repeat(4)tick;rst_n=1;wait(model.clock_reads>0);wait(dut.state==0);tick;
  if(time_valid||model.charger!=0||model.registers[7]!=128||model.calendar_writes!=0)$fatal(1,"boot charger/protection/CH policy");
  file=$fopen("vectors.txt","r");if(!file)$fatal(1,"missing calendar oracle");
  while(!$feof(file))begin
   code=$fscanf(file,"%h %h %h %d\n",calendar,weekday,control,valid_expected);
   if(code==4)begin
    wait(dut.state==0);fields(calendar,weekday,control);read_result;
    if(time_valid!==valid_expected[0]||(valid_expected&&time_bcd!==calendar))$fatal(1,"calendar vector%0d %h day=%h ctl=%h expected%0d got%b %h",vectors,calendar,weekday,control,valid_expected,time_valid,time_bcd);
    vectors=vectors+1;
   end
  end
  $fclose(file);
  fields(48'h261025123456,7,128);read_result;
  before_writes=model.writes;repeat(3)read_result;if(model.writes!=before_writes)$fatal(1,"polling wrote RTC");
  model.connected=0;wait(!time_valid);wait(dut.state==0);
  save(48'h261025123456,0);
  model.connected=1;save(48'h240229235959,1);
  if(model.charger!=0||model.registers[7]!=128||model.registers[0][7])$fatal(1,"save left charger/WP/CH unsafe");
  before_writes=model.writes;save(48'h250229123456,0);if(model.writes!=before_writes)$fatal(1,"invalid calendar touched RTC");
  model.ignore_calendar=1;save(48'h261231235959,0);model.ignore_calendar=0;
  save(48'h261231235959,1);
  model.ignore_protect=1;save(48'h270101000000,0);model.ignore_protect=0;
  model.corrupt_index=1;save(48'h270101000000,0);model.corrupt_index=-1;
  model.ignore_charge=1;model.charger=8'ha5;save(48'h270101000000,0);model.ignore_charge=0;
  save(48'h270101000000,1);
  // A request exactly on the first reset-release tick must not get lost.
  rst_n=0;repeat(4)tick;set_bcd=48'h280229000001;set_request=1;rst_n=1;
  tick;set_request=0;wait(set_done);tick;
  if(set_busy||!time_valid||time_bcd!==48'h280229000001)$fatal(1,"first tick request lost");
  before_calendar=model.calendar_writes;rst_n=0;repeat(4)tick;rst_n=1;
  wait(time_valid);tick;
  if(time_bcd!==48'h280229000001||model.calendar_writes!=before_calendar)$fatal(1,"FPGA reset changed battery-backed calendar");
  $display("PASS DS1302 Q=%0d strict=%0d: %0d independent calendar vectors; CE/clock timing, read turnaround, charger off, WP/CH, no-module, save/readback, invalid date, ignored writes, reset persistence, first-tick request",Q,STRICT,vectors);$finish;
 end
 initial begin #2000000000;$fatal(1,"DS1302 regression timeout Q=%0d state%0d op%0d",Q,dut.state,dut.operation);end
endmodule
