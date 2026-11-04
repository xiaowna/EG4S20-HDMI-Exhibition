`timescale 1ns/1ps
module tb_control_events;
 reg enable=0;
 reg [3:0] key_press=0,encoder_event=0,infrared_event=0;
 wire [3:0] control_event;
 reg [3:0] table_value[0:15];
 reg [3:0] expected;
 integer en,k,e,i,cases=0;
 media_control_events dut(.*);
 initial begin
  // Literal truth table of the pre-existing menu priority, independent of RTL.
  table_value[0]=0;table_value[1]=1;table_value[2]=2;table_value[3]=2;
  table_value[4]=4;table_value[5]=0;table_value[6]=2;table_value[7]=2;
  for(i=8;i<16;i=i+1)table_value[i]=8;
  for(en=0;en<2;en=en+1)
   for(k=0;k<16;k=k+1)
    for(e=0;e<16;e=e+1)
     for(i=0;i<16;i=i+1)begin
      enable=en;key_press=k;encoder_event=e;infrared_event=i;
      expected=!en?4'b0:(k!=0?table_value[k]:(e!=0?table_value[e]:table_value[i]));
      #1;
      if(control_event!==expected)$fatal(1,"arbiter en=%0d keys=%h encoder=%h IR=%h expected=%h actual=%h",en,k,e,i,expected,control_event);
      if(control_event!=0 && (control_event&(control_event-1))!=0)$fatal(1,"multiple commands escaped");
      cases=cases+1;
     end
  // A canceled high-priority chord must not fall through to an unrelated source.
  enable=1;key_press=5;encoder_event=2;infrared_event=8;#1;
  if(control_event!==0)$fatal(1,"canceled key chord fell through");
  key_press=0;encoder_event=5;#1;
  if(control_event!==0)$fatal(1,"canceled encoder chord fell through");
  // Removing all sources must clear immediately; there is no delayed queue.
  encoder_event=0;infrared_event=0;#1;
  if(control_event!==0)$fatal(1,"stale command");
  $display("PASS control_events: %0d exhaustive vectors, one-hot/zero, source priority, cancel, disable and no queued replay",cases);
  $finish;
 end
endmodule
