`timescale 1ns/1ps
module tb_ir_receiver;
 parameter integer SAMPLE=1;
 reg clk=0,rst_n=0,enable=1,infrared_n=1;
 always #10 clk=~clk;
 wire sample_tick,frame_valid,frame_repeat;
 wire [7:0] frame_address,frame_command;
 media_nec_receiver #(.SAMPLE_CYCLES(SAMPLE)) dut(.*);
 integer frames=0,checks=0,clocks=0,previous_tick=0,ticks=0;
 reg [7:0] last_address=0,last_command=0;
 reg last_repeat=0,previous_valid=0;
 always @(posedge clk)begin
  clocks=clocks+1;
  if(rst_n&&sample_tick)begin
   if(ticks>0&&clocks-previous_tick!=SAMPLE)$fatal(1,"sample period");
   ticks=ticks+1;previous_tick=clocks;
  end
  #1;
  if(rst_n)begin
   if(frame_valid&&previous_valid)$fatal(1,"frame valid not one clock");
   if(!enable&&frame_valid)$fatal(1,"disabled decode");
   if(frame_valid)begin frames=frames+1;last_address=frame_address;last_command=frame_command;last_repeat=frame_repeat;end
  end
  previous_valid=frame_valid;
 end
 task cycles(input integer n);begin repeat(n)@(negedge clk);#2;end endtask
 integer f,n,e,level,duration,expected,addr,command,rep,result;
 initial begin
  cycles(4);rst_n=1;f=$fopen("stimulus.txt","r");if(!f)$fatal(1,"stimulus missing");
  n=0;
  while(!$feof(f))begin
   result=$fscanf(f,"%d %d %d %d %d %d %d\n",e,level,duration,expected,addr,command,rep);
   if(result!=7)$fatal(1,"bad stimulus line %0d",n);
   enable=e;infrared_n=level;cycles(duration*SAMPLE);n=n+1;
   if(expected>=0)begin
    if(frames!=expected || (expected>0&&(last_address!=addr||last_command!=command||last_repeat!=rep)))
     $fatal(1,"line %0d frames=%0d expected=%0d last=%02x/%02x/%b expected=%02x/%02x/%0d",n,frames,expected,last_address,last_command,last_repeat,addr,command,rep);
    checks=checks+1;
   end
  end
  $fclose(f);
  $display("PASS NEC receiver SAMPLE=%0d frames=%0d checks=%0d: LSB byte order, full inverse/stop validation, tolerance, noise, orphan/expired repeats, truncation, reset/block and recovery",SAMPLE,frames,checks);$finish;
 end
 initial begin #2000000000;$fatal(1,"NEC receiver timeout");end
endmodule
