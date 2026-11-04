`timescale 1ns/1ps
`ifdef TEST_NATIVE
`undef __ICARUS__
`endif
module tb_intro_roms;
 reg clk=0,en=0;reg [10:0] geometry_address=0;
 reg [8:0] character_address=0;reg [12:0] glyph_address=0;
 wire [15:0] geometry_data,character_data,glyph_data;
 reg [15:0] geometry[0:2047],characters[0:511],glyphs[0:8191];
 reg [15:0] hg,hc,hf;
 integer n,checked=0;
 always #5 clk=~clk;
 intro_geometry_rom g(.clk(clk),.en(en),.address(geometry_address),.data(geometry_data));
 intro_character_rom c(.clk(clk),.en(en),.address(character_address),.data(character_data));
 intro_glyph_rom f(.clk(clk),.en(en),.address(glyph_address),.data(glyph_data));
 initial begin
  $readmemh("geometry.hex",geometry);$readmemh("characters.hex",characters);$readmemh("glyphs.hex",glyphs);
  for(n=0;n<8192;n=n+1)begin
   @(negedge clk);en=1;geometry_address=n%2048;character_address=n%512;glyph_address=n;
   @(posedge clk);#1;
   if(geometry_data!==geometry[n%2048]||character_data!==characters[n%512]||glyph_data!==glyphs[n])
    $fatal(1,"ROM payload/latency mismatch n=%0d geometry=%h character=%h glyph=%h",n,geometry_data,character_data,glyph_data);
   checked=checked+3;
   if(n%17==0)begin
    hg=geometry_data;hc=character_data;hf=glyph_data;
    @(negedge clk);en=0;geometry_address=~geometry_address;character_address=~character_address;glyph_address=~glyph_address;
    @(posedge clk);#1;
    if(geometry_data!==hg||character_data!==hc||glyph_data!==hf)$fatal(1,"ROM enable hold mismatch n=%0d",n);
   end
  end
  $display("PASS all intro ROM words and bank boundaries checked=%0d; one-clock enable-hold",checked);$finish;
 end
endmodule
