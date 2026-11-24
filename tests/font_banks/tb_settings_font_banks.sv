`timescale 1ns/1ps
module tb_settings_font_banks;
 reg clk=0;
 always #5 clk=~clk;
 reg [14:0] address=0;
 wire current64,current128,reference64,reference128;
 settings_font_rom #(.CLOCK_FONT(0)) dut64(.clk(clk),.address(address),.pixel(current64));
 settings_font_rom #(.CLOCK_FONT(1)) dut128(.clk(clk),.address(address),.pixel(current128));
 reference_settings_font_rom #(.CLOCK_FONT(0)) old64(.clk(clk),.address(address),.pixel(reference64));
 reference_settings_font_rom #(.CLOCK_FONT(1)) old128(.clk(clk),.address(address),.pixel(reference128));
 reg golden[0:32767];
 reg historical_golden[0:32767];
 reg [3:0] previous;
 reg have_previous=0;
 reg [31:0] random_state=32'h27182818;
 integer samples=0,fd;
 task probe(input [14:0] target);
  begin
   @(negedge clk);address=target;#1;
   // Changing an input address between clocks must not change a registered
   // lookup result, including when the selected bank and bit both change.
   if(have_previous&&{current64,current128,reference64,reference128}!==previous)
    $fatal(1,"asynchronous output change at address %h",target);
   @(posedge clk);#1;
   if(current64!==golden[target[13:0]]||reference64!==historical_golden[target[13:0]])
    $fatal(1,"64-slot mapping/latency mismatch at %h: new=%b old=%b golden=%b",target,current64,reference64,golden[target[13:0]]);
   if(current128!==golden[target])
    $fatal(1,"128-slot mapping/latency mismatch at %h: new=%b old=%b golden=%b",target,current128,reference128,golden[target]);
   if(reference128!==historical_golden[target])
    $fatal(1,"historical 128-slot mapping/latency mismatch at %h: old=%b golden=%b",target,reference128,historical_golden[target]);
   // Slots 74..81 contain note poses and slot 82 contains the seconds unit.
   if((target<74*256||target>=83*256)&&current128!==reference128)
    $fatal(1,"unintended historical glyph change at %h",target);
   if(current64!==reference64)
    $fatal(1,"legacy 64-slot comparison mismatch at %h",target);
   previous={current64,current128,reference64,reference128};
   have_previous=1;samples=samples+1;
  end
 endtask
 initial begin
  fd=$fopen("font_bits.hex","r");
  if(!fd)$fatal(1,"missing independent font bitmap");
  $fclose(fd);$readmemh("font_bits.hex",golden);
  fd=$fopen("reference_font_bits.hex","r");
  if(!fd)$fatal(1,"missing independent historical font bitmap");
  $fclose(fd);$readmemh("reference_font_bits.hex",historical_golden);
  // Every address in the complete public input space, in both modes.
  for(integer a=0;a<32768;a=a+1)probe(a[14:0]);
  // Cross all bank boundaries and output-bit lanes in both directions.
  for(integer b=1;b<4;b=b+1)begin
   probe(b*8192-1);probe(b*8192);probe(b*8192+1);
   probe(b*8192-2);probe(b*8192+2);probe(b*8192-1);
  end
  for(integer n=0;n<4096;n=n+1)begin
   random_state=random_state*32'd1664525+32'd1013904223;
   probe(random_state[14:0]);
  end
  // Repeated addresses and the legacy upper-bit alias must also retain data.
  repeat(8)probe(15'h7fff);
  repeat(8)begin probe(15'h0101);probe(15'h4101);end
  $display("PASS banked settings font: %0d samples; all addresses in both modes, historical glyphs preserved, note poses and seconds glyph, one-clock output",samples);
  $finish;
 end
 initial begin #1000000;$fatal(1,"font comparison timeout");end
endmodule
