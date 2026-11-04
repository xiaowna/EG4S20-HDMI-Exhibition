`timescale 1ns/1ps

// Ideal digital model only: no metastability, pad delay or board delay.
// Preload the first bit before start; this does not test CS-to-first-bit timing.
module tb_dmz_spi_miso;
 reg clk=0;
 always #10 clk=~clk;
 reg rst_n=0,start=0,card_miso=1;
 reg miso1=1,miso2=1;
 wire [7:0] rx_data;
 wire busy,done,sd_sck,sd_mosi;

 // Keep the same two-stage, same-edge chain as the board top.
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin miso1<=1; miso2<=1; end
  else begin miso1<=card_miso; miso2<=miso1; end
 end
 sd_spi_master #(.CLK_DIV(64),.READ_CLK_DIV(4)) dut(
  .clk(clk),.rst_n(rst_n),.start(start),.fast_mode(1'b1),
  .tx_data(8'hFF),.rx_data(rx_data),.busy(busy),.done(done),
  .sd_sck(sd_sck),.sd_mosi(sd_mosi),.sd_miso(miso2));

 reg model_active=0;
 reg [7:0] card_byte;
 integer card_bit,return_delay_ns,sck_edges,half_period_checks;
 integer transfers=0,late_mismatches=0;
 time accepted_at,last_sck_edge;

 // Mode 0 card: after each falling SCK edge, present the next bit.
 // The final falling edge ends the byte and must not advance past bit 0.
 always @(negedge sd_sck) begin
  if(model_active && card_bit>0) begin
   card_bit=card_bit-1;
   #(return_delay_ns);
   card_miso=card_byte[card_bit];
  end
 end

 always @(sd_sck) begin
  if(model_active && rst_n) begin
   if(sck_edges==0) begin
    if($time-accepted_at!=80)
     $fatal(1,"First SCK edge is not 80 ns after acceptance");
   end else begin
    if($time-last_sck_edge!=80)
     $fatal(1,"SCK half-period: got %0t, expected 80 ns",$time-last_sck_edge);
    half_period_checks=half_period_checks+1;
   end
   last_sck_edge=$time;
   sck_edges=sck_edges+1;
  end
 end

 task automatic check_byte(input [7:0] expected,input integer delay_ns);
  reg [7:0] predicted;
  begin
   @(negedge clk);
   card_byte=expected;
   card_bit=7;
   card_miso=expected[7];
   return_delay_ns=delay_ns;
   sck_edges=0;
   half_period_checks=0;
   model_active=1;
   // The first bit is already stable through both synchronizer stages.
   repeat(3) @(negedge clk);
   start=1;
   @(posedge clk);
   accepted_at=$time;
   @(negedge clk);
   start=0;
   wait(done===1'b1);
   #1;
   model_active=0;
   if(sck_edges!=16 || half_period_checks!=15)
    $fatal(1,"Expected 16 SCK edges and 15 half-period checks, got %0d/%0d",sck_edges,half_period_checks);
   if(busy!==1'b0 || sd_sck!==1'b0)
    $fatal(1,"Byte completion did not return SPI to idle");
   // At a rising SCK edge, the master consumes a pin sample from 40 ns ago.
   // A change after falling-edge +40 ns therefore arrives one bit too late.
   predicted=(delay_ns<=39)?expected:{expected[7],expected[7:1]};
   if(rx_data!==predicted)
    $fatal(1,"tOD=%0d ns, card=%02x: received=%02x, predicted=%02x",delay_ns,expected,rx_data,predicted);
   if(delay_ns>40 && rx_data!=expected) late_mismatches=late_mismatches+1;
   transfers=transfers+1;
  end
 endtask

 reg [7:0] patterns[0:7];
 integer delays[0:5];
 integer d,p;
 initial begin
  patterns[0]=8'hD3; patterns[1]=8'h96; patterns[2]=8'hA5; patterns[3]=8'h3C;
  patterns[4]=8'h81; patterns[5]=8'h7E; patterns[6]=8'h00; patterns[7]=8'hFF;
  delays[0]=0; delays[1]=14; delays[2]=25; delays[3]=39; delays[4]=41; delays[5]=60;
  repeat(3) @(negedge clk);
  rst_n=1;
  for(d=0;d<6;d=d+1) begin
   for(p=0;p<8;p=p+1) check_byte(patterns[p],delays[d]);
   if(delays[d]<=39)
    $display("PASS DMZ MISO tOD=%0d ns: eight bytes received correctly",delays[d]);
   else
    $display("PASS DMZ MISO tOD=%0d ns: eight bytes follow deterministic one-bit delay",delays[d]);
  end
  if(transfers!=48 || late_mismatches!=12)
   $fatal(1,"Unexpected coverage: transfers=%0d late mismatches=%0d",transfers,late_mismatches);
  $display("PASS DMZ SPI MISO: 48 bytes, 80 ns SCK half-period, ideal digital 40 ns boundary");
  $display("MODEL LIMIT: ignores metastability and IO/board delay; 39 ns pass is not physical margin; first bit is pre-stabilized");
  $finish;
 end
 initial begin
  #200000;
  $fatal(1,"DMZ SPI MISO test timeout");
 end
endmodule
