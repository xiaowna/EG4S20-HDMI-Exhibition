`timescale 1ns/1ps
// Transaction slave independent of the master's state machine.
module ds3231_write_model(input wire rst_n,inout wire scl,sda);
 reg drive_low=0;
 reg [7:0] registers[0:15],snapshot[0:15];
 integer starts=0,stops=0,writes=0,calendar_writes=0,status_writes=0;
 integer nack_transaction=-1,nack_byte=-1,transaction_index=-1,corrupt_read=0;
 integer i;
 assign sda=drive_low?1'b0:1'bz;
 task start;
  begin:waiting
   forever begin @(negedge sda);if(scl===1)disable waiting;end
  end
 endtask
 task stop;
  begin:waiting
   forever begin @(posedge sda);if(scl===1)disable waiting;end
  end
 endtask
 task receive(output reg [7:0] value);
  integer n;
  begin for(n=7;n>=0;n=n-1)begin @(posedge scl);value[n]=sda;end @(negedge scl);end
 endtask
 task ack(input integer which,output reg accepted);
  begin
   accepted=!(nack_transaction==transaction_index&&nack_byte==which);
   drive_low=accepted;@(posedge scl);@(negedge scl);drive_low=0;
  end
 endtask
 task send(input [7:0] value,input integer last);
  integer n;
  begin
   for(n=7;n>=0;n=n-1)begin drive_low=!value[n];@(posedge scl);@(negedge scl);end
   drive_low=0;@(posedge scl);
   if(sda!==last[0])$fatal(1,"write model read ACK/NACK wrong");
   @(negedge scl);
  end
 endtask
 task transaction;
  reg [7:0] value,pointer;reg accepted;integer count,n;
  begin:flow
   start;starts=starts+1;transaction_index=transaction_index+1;
   receive(value);if(value!==8'hd0)$fatal(1,"write address wrong %h",value);
   ack(0,accepted);if(!accepted)disable flow;
   receive(pointer);if(pointer!==0&&pointer!==15)$fatal(1,"unexpected register write %h",pointer);
   ack(1,accepted);if(!accepted)disable flow;
   count=0;
   fork:branches
    begin
    fork:read_or_write
    begin:read_flow
     start;starts=starts+1;disable write_flow;
     for(n=0;n<16;n=n+1)snapshot[n]=registers[n];
     if(corrupt_read>0)begin snapshot[6]=snapshot[6]^1;corrupt_read=corrupt_read-1;end
     receive(value);if(value!==8'hd1)$fatal(1,"read address wrong");
     ack(2,accepted);if(!accepted)begin wait(0);end
     for(n=0;n<16;n=n+1)send(snapshot[n],n==15);
     wait(0);
    end
    begin:write_flow
     forever begin
      receive(value);ack(2+count,accepted);
      if(!accepted)wait(0);
      registers[pointer]=value;writes=writes+1;
      if(pointer==0)calendar_writes=calendar_writes+1;
      if(pointer==15)status_writes=status_writes+1;
      pointer=pointer+1;count=count+1;
     end
    end
    join
    end
    begin stop;stops=stops+1;end
   join_any
   disable branches;
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
