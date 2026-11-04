`timescale 1ns/1ps
module tb_encoder;
 parameter integer SAMPLE=3,FILTER=3,BUTTON=5,LONG=80;
 reg clk=0,rst_n=0,enable=1,encoder_a=1,encoder_b=1,encoder_press_n=1;
 always #10 clk=~clk;
 wire [3:0] encoder_event;
 media_rotary_encoder #(.SAMPLE_CYCLES(SAMPLE),.AB_SAMPLES(FILTER),
  .BUTTON_SAMPLES(BUTTON),.LONG_SAMPLES(LONG)) dut(.*);
 localparam integer WAIT=(FILTER+5)*SAMPLE+6;
 integer right=0,left=0,ok=0,back=0,checks=0;
 reg [3:0] last_event=0;
 always @(posedge clk)begin #1;
  if(rst_n)begin
   if(encoder_event!==0 && encoder_event!==1 && encoder_event!==2 && encoder_event!==4 && encoder_event!==8)
    $fatal(1,"invalid command %b",encoder_event);
   if(encoder_event!=0 && last_event!=0)$fatal(1,"event lasted more than one clock");
   if(!enable&&encoder_event!=0)$fatal(1,"disabled event");
   if(encoder_event[0])right=right+1;
   if(encoder_event[1])ok=ok+1;
   if(encoder_event[2])left=left+1;
   if(encoder_event[3])back=back+1;
  end
  last_event=encoder_event;
 end
 task cycles(input integer n);begin repeat(n)@(negedge clk);#2;end endtask
 task phase(input [1:0] v);begin {encoder_a,encoder_b}=v;cycles(WAIT);end endtask
 task cw;begin phase(2'b10);phase(2'b00);phase(2'b01);phase(2'b11);end endtask
 task ccw;begin phase(2'b01);phase(2'b00);phase(2'b10);phase(2'b11);end endtask
 task expect_counts(input integer r,l,o,b);begin
  if(right!=r||left!=l||ok!=o||back!=b)
   $fatal(1,"counts R/L/OK/back=%0d/%0d/%0d/%0d expected %0d/%0d/%0d/%0d",right,left,ok,back,r,l,o,b);
  checks=checks+1;
 end endtask
 task restart;begin rst_n=0;cycles(4);rst_n=1;cycles(WAIT+(BUTTON+5)*SAMPLE);end endtask
 task short_press;begin
  encoder_press_n=0;cycles((BUTTON+7)*SAMPLE);
  encoder_press_n=1;cycles((BUTTON+7)*SAMPLE);
 end endtask
 integer r,l,o,b,k;
 initial begin
  restart;expect_counts(0,0,0,0);
  cw;ccw;cw;expect_counts(2,1,0,0);
  // Each contact bounces all the way back to the preceding stable phase.
  phase(2'b10);phase(2'b11);phase(2'b10);
  phase(2'b00);phase(2'b10);phase(2'b00);
  phase(2'b01);phase(2'b00);phase(2'b01);
  phase(2'b11);expect_counts(3,1,0,0);
  phase(2'b10);phase(2'b11);phase(2'b10);phase(2'b00);
  phase(2'b10);phase(2'b11);expect_counts(3,1,0,0);
  // Diagonal jumps and short phase noise must not synthesize a detent.
  phase(2'b00);phase(2'b01);phase(2'b11);expect_counts(3,1,0,0);
  if(FILTER>1)begin
   {encoder_a,encoder_b}=2'b10;cycles(SAMPLE);{encoder_a,encoder_b}=2'b11;cycles(WAIT);
   expect_counts(3,1,0,0);
  end
  for(k=0;k<32;k=k+1)begin cw;ccw;end
  expect_counts(35,33,0,0);
  short_press;expect_counts(35,33,1,0);
  // Press/release bounce shorter than the button qualification interval.
  if(BUTTON>2)begin
   encoder_press_n=0;cycles(SAMPLE);encoder_press_n=1;cycles((BUTTON+7)*SAMPLE);
   expect_counts(35,33,1,0);
  end
  encoder_press_n=0;cycles((BUTTON+LONG+12)*SAMPLE);
  expect_counts(35,33,1,1);
  cw;ccw;cycles((LONG+12)*SAMPLE);expect_counts(35,33,1,1);
  encoder_press_n=1;cycles((BUTTON+8)*SAMPLE);expect_counts(35,33,1,1);
  short_press;expect_counts(35,33,2,1);
  // Commands disabled in the middle of a gesture: discard, require release.
  encoder_press_n=0;cycles((BUTTON+8)*SAMPLE);enable=0;cycles(3);
  enable=1;cycles((LONG+12)*SAMPLE);encoder_press_n=1;cycles((BUTTON+8)*SAMPLE);
  expect_counts(35,33,2,1);
  phase(2'b10);enable=0;cycles(3);enable=1;phase(2'b00);phase(2'b01);phase(2'b11);
  expect_counts(35,33,2,1);cw;expect_counts(36,33,2,1);
  // Reset while held: neither startup nor eventual release is an OK.
  encoder_press_n=0;restart;cycles((LONG+10)*SAMPLE);
  encoder_press_n=1;cycles((BUTTON+8)*SAMPLE);expect_counts(36,33,2,1);
  short_press;expect_counts(36,33,3,1);
  enable=0;r=right;l=left;o=ok;b=back;cw;ccw;short_press;expect_counts(r,l,o,b);
  enable=1;cycles(WAIT);cw;expect_counts(r+1,l,o,b);
  $display("PASS encoder SAMPLE=%0d FILTER=%0d BUTTON=%0d LONG=%0d checks=%0d: both directions, bounce, reversal, diagonal rejection, short/long, held/reset/block, one-clock pulses",SAMPLE,FILTER,BUTTON,LONG,checks);$finish;
 end
 initial begin #1000000000;$fatal(1,"encoder unit timeout");end
endmodule
