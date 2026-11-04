`timescale 1ns/1ps
// Pin-level slave. The expected byte sequence and calendar oracle live in the
// test, independently of the DUT's states, divider and BCD validation function.
module ds3231_model(input wire rst_n,inout wire scl,sda);
 reg drive_low=0;
 reg [7:0] registers[0:15],snapshot[0:15];
 integer nack_stage=-1,transactions=0,starts=0,stops=0,i;
 assign sda=drive_low?1'b0:1'bz;
 task start;
  begin:wait_start
   forever begin @(negedge sda);if(scl===1'b1)disable wait_start;end
  end
 endtask
 task receive(output reg [7:0] value);
  integer n;
  begin for(n=7;n>=0;n=n-1)begin @(posedge scl);value[n]=sda;end @(negedge scl);end
 endtask
 task ack(input integer which);
  begin drive_low=(nack_stage!=which);@(posedge scl);@(negedge scl);drive_low=0;end
 endtask
 task send(input reg [7:0] value,input integer last);
  integer n;
  begin
   for(n=7;n>=0;n=n-1)begin drive_low=!value[n];@(posedge scl);@(negedge scl);end
   drive_low=0;@(posedge scl);
   if(sda!==last[0])$fatal(1,"master ACK/NACK wrong: last=%0d level=%b",last,sda);
   @(negedge scl);
  end
 endtask
 task transaction;
  reg [7:0] value;integer n;
  begin:flow
   start;starts=starts+1;
   receive(value);if(value!==8'hd0)$fatal(1,"wrong write address %h",value);
   ack(0);if(nack_stage==0)disable flow;
   receive(value);if(value!==0)$fatal(1,"wrong register pointer %h",value);
   ack(1);if(nack_stage==1)disable flow;
   start;starts=starts+1;
   for(n=0;n<16;n=n+1)snapshot[n]=registers[n];
   receive(value);if(value!==8'hd1)$fatal(1,"wrong read address %h",value);
   ack(2);if(nack_stage==2)disable flow;
   for(n=0;n<16;n=n+1)send(snapshot[n],n==15);
   @(posedge sda);if(scl!==1)$fatal(1,"missing STOP");
   stops=stops+1;transactions=transactions+1;
  end
 endtask
 initial begin
  for(i=0;i<16;i=i+1)registers[i]=0;
  forever begin
   wait(rst_n);
   fork:resettable
    transaction;
    begin @(negedge rst_n);end
   join_any
   disable resettable;drive_low=0;
  end
 end
endmodule
