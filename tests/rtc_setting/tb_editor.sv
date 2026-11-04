`timescale 1ns/1ps
module tb_rtc_editor;
 reg clk=0,rst_n=0,enable=0,time_valid=1,set_busy=0,set_done=0,set_error=0;
 reg [3:0] key_press=0;reg [47:0] time_bcd=0;
 wire [47:0] draft;wire [2:0] field;wire [1:0] status;wire set_request,exit_request;
 always #10 clk=~clk;
 rtc_set_control dut(.*);
 always @(negedge clk)if(rst_n&&(draft&~48'hff1f3f3f7f7f)!==0)
  $fatal(1,"reserved BCD bits became nonzero in a validated editor draft");
 task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
 task press(input [3:0] value);begin key_press=value;tick;key_press=0;tick;end endtask
 integer fd,scanned,target,direction,count=0,n;
 reg [47:0] expected;
 initial begin
  repeat(3)tick;rst_n=1;tick;
  fd=$fopen("edit_vectors.txt","r");if(!fd)$fatal(1,"missing calendar editor oracle");
  while(!$feof(fd))begin
   scanned=$fscanf(fd,"%h %d %d %h\n",time_bcd,target,direction,expected);
   if(scanned!=4)$fatal(1,"bad editor vector");
   enable=0;tick;enable=1;tick;
   if(draft!==time_bcd||field!==0)$fatal(1,"entry snapshot wrong");
   for(n=0;n<target;n=n+1)press(2);
   press(direction?1:4);
   if(draft!==expected||set_request!==0)$fatal(1,"editor oracle case %0d field=%0d got=%h expected=%h",count,target,draft,expected);
   count=count+1;
  end
  $fclose(fd);
  enable=0;time_valid=0;tick;enable=1;tick;
  if(draft!==48'h000101000000)$fatal(1,"uncalibrated draft default wrong");
  press(5);if(draft!==48'h000101000000)$fatal(1,"opposing arrows changed calendar");
  for(n=0;n<6;n=n+1)press(2);
  key_press=2;tick;key_press=0;
  if(!set_request||status!==1)$fatal(1,"save did not issue exactly one request");
  set_busy=1;tick;
  press(1);press(4);press(2);press(8);
  if(draft!==48'h000101000000||exit_request||set_request)$fatal(1,"busy editor is not frozen");
  set_busy=0;set_error=1;tick;set_error=0;tick;
  if(status!==3||field!==6)$fatal(1,"failed save lost draft");
  press(1);if(field!==7)$fatal(1,"cancel selection wrong");
  key_press=2;tick;key_press=0;
  if(!exit_request||set_request)$fatal(1,"cancel wrote RTC");tick;
  press(4);key_press=2;tick;key_press=0;
  if(!set_request)$fatal(1,"retry failed");set_busy=1;tick;
  set_busy=0;set_done=1;tick;set_done=0;tick;
  if(status!==2)$fatal(1,"success not shown");
  key_press=2;tick;key_press=0;
  if(!exit_request||set_request)$fatal(1,"success OK repeated write");
  $display("PASS RTC editor: %0d independent calendar adjustments, default/snapshot, opposed inputs, busy freeze, save/cancel/failure/retry/success",count);$finish;
 end
 initial begin #50000000;$fatal(1,"editor timeout");end
endmodule
