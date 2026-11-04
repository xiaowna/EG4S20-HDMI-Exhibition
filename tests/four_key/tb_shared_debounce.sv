`timescale 1ns/1ps
module tb_shared_debounce;
 parameter COUNT=32;
 reg clk=0,rst_n=1;reg [3:0] key_n=15;
 wire [3:0] press,stable_n;
 integer events=0,i,j;
 always #5 clk=~clk;
 board_key #(.COUNT(COUNT),.WIDTH(4)) dut(.*);
 task ticks(input integer n);begin repeat(n)begin @(negedge clk);#1;end end endtask
 always @(negedge clk)if(rst_n && press!=0)begin
  if(press!=1 && press!=2 && press!=4 && press!=8)$fatal(1,"multiple key pulse");
  events=events+1;
 end
 initial begin
  #1;rst_n=0;ticks(3);rst_n=1;ticks(3);
  key_n=14;
  // Exactly two synchronizer edges, followed by COUNT stable samples.
  ticks(COUNT+1);if(press || stable_n!=15)$fatal(1,"debounce accepted early COUNT=%0d",COUNT);
  ticks(1);if(press!=1 || stable_n!=14)$fatal(1,"debounce edge wrong COUNT=%0d",COUNT);
  ticks(COUNT+5);if(events!=1)$fatal(1,"held repeat");
  key_n=15;ticks(COUNT+3);
  if(COUNT>2)begin
   for(i=0;i<4;i=i+1)begin key_n=15^(1<<i);ticks(COUNT-1);key_n=15;ticks(3);end
   if(events!=1)$fatal(1,"short bounce accepted");
   // Different candidates must restart the shared timer, even while none
   // has yet reached the debounced state.
   key_n=14;ticks(COUNT-1);key_n=13;ticks(COUNT-1);
   key_n=11;ticks(COUNT-1);key_n=15;ticks(COUNT+4);
   if(events!=1)$fatal(1,"shared timer accumulated across different keys");
  end
  for(j=0;j<4;j=j+1)begin
   key_n=15^(1<<j);ticks(COUNT+4);key_n=15;ticks(COUNT+4);
  end
  if(events!=5)$fatal(1,"all four key masks not delivered");
  $display("PASS shared debounce COUNT=%0d: exact 20ms-equivalent boundary, held one-shot, all four masks, bounce and candidate restart",COUNT);$finish;
 end
 initial begin #2000000000;$fatal(1,"shared debounce timeout");end
endmodule
