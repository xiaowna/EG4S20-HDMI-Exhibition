`timescale 1ns/1ps
// Independent edge-driven peripheral model. Calendar survives FPGA resets.
// Snapshot at CE rising, command/input LSB first on rising CLK, read data
// appears after falling CLK and is released after the following rising CLK.
module ds1302_model #(parameter STRICT_TIMING=0,DATA_DELAY=10,RELEASE_DELAY=10)(
 input wire ce,sclk,inout wire dat);
 reg connected=1,ignore_calendar=0,ignore_protect=0,ignore_charge=0;
 integer corrupt_index=-1;
 reg [7:0] registers[0:7],snapshot[0:7],payload[0:7];reg [7:0] charger=8'h00,command=0,value;
 reg output_enable=0,output_bit=0,active=0,command_done=0,reading=0;
 integer command_bits=0,input_bits=0,read_rises=0,transactions=0,clock_reads=0,writes=0,calendar_writes=0;
 integer read_index=0;realtime ce_on=0,ce_off=-100000,rose=-100000,fell=-100000,data_changed=-100000;
 assign dat=connected&&output_enable?output_bit:1'bz;
 initial begin
  registers[0]=8'h56;registers[1]=8'h34;registers[2]=8'h12;registers[3]=8'h25;
  registers[4]=8'h10;registers[5]=7;registers[6]=8'h26;registers[7]=8'h80;
 end
 always @(dat)data_changed=$realtime;
 always @(posedge ce)begin
  if(STRICT_TIMING&&($realtime-ce_off<4000||sclk!==0))$fatal(1,"DS1302 CE inactive/CLK-low setup");
  ce_on=$realtime;command=0;command_bits=0;input_bits=0;read_rises=0;
  command_done=0;reading=0;active=connected;output_enable=0;
  for(integer i=0;i<8;i=i+1)begin snapshot[i]=registers[i];payload[i]=0;end
 end
 always @(posedge sclk)if(ce&&active&&connected)begin
  if(STRICT_TIMING&&($realtime-ce_on<4000||$realtime-fell<1000))$fatal(1,"DS1302 CLK low/CE setup");
  rose=$realtime;
  if(!command_done)begin
   if(STRICT_TIMING&&$realtime-data_changed<200)$fatal(1,"DS1302 command data setup");
   if(dat!==0&&dat!==1)$fatal(1,"DS1302 floating/contended command");
   command[command_bits]=dat;command_bits=command_bits+1;
   if(command_bits==8)begin
    command_done=1;reading=command[0];
    if(command!=8'hbf&&command!=8'hbe&&command!=8'h8e&&command!=8'h90&&command!=8'h91)$fatal(1,"unexpected RTC command %h",command);
   end
  end else if(reading)begin
   read_rises=read_rises+1;output_enable<=#RELEASE_DELAY 0;
  end else begin
   if(STRICT_TIMING&&$realtime-data_changed<200)$fatal(1,"DS1302 write data setup");
   if(input_bits>=64||dat!==0&&dat!==1)$fatal(1,"DS1302 write overflow/contention");
   payload[input_bits/8][input_bits%8]=dat;input_bits=input_bits+1;
  end
 end
 always @(negedge sclk)if(ce&&active&&connected)begin
  if(STRICT_TIMING&&$realtime-rose<1000)$fatal(1,"DS1302 CLK high time");
  fell=$realtime;
  if(command_done&&reading&&read_rises<((command==8'hbf)?64:8))begin
   read_index=read_rises/8;
   value=(command==8'h91)?charger:snapshot[read_index];
   if(command==8'hbf&&read_index==corrupt_index)value=value^8'h01;
   output_bit<=#DATA_DELAY value[read_rises%8];output_enable<=#DATA_DELAY 1;
  end
 end
 always @(negedge ce)begin
  if(active&&connected)begin
   if(STRICT_TIMING&&$realtime-rose<240)$fatal(1,"DS1302 CE hold");
   transactions=transactions+1;
   if(command_done)begin
    if(reading)begin
     if(read_rises!=((command==8'hbf)?64:8))$fatal(1,"partial RTC read command=%h bits=%0d",command,read_rises);
     if(command==8'hbf)clock_reads=clock_reads+1;
    end else if(input_bits==((command==8'hbe)?64:8))begin
     case(command)
      8'h8e:if(!ignore_protect)begin registers[7]={payload[0][7],7'd0};writes=writes+1;end
      8'h90:if(!registers[7][7]&&!ignore_charge)begin
       if(payload[0]!=0)$fatal(1,"driver enabled battery trickle charge");
       charger=payload[0];writes=writes+1;
      end
      8'hbe:if(!registers[7][7]&&!ignore_calendar)begin
       for(integer i=0;i<8;i=i+1)registers[i]=payload[i];calendar_writes=calendar_writes+1;writes=writes+8;
      end
     endcase
    end
   end
  end
  ce_off=$realtime;output_enable<=#RELEASE_DELAY 0;active=0;
 end
endmodule
