// Public true-dual-port RAM contract for the two scanline planes. This model
// intentionally allows independent port addresses (unlike phase RAM's pairing).
module EG_PHY_BRAM32K #(
 parameter MODE="DP16K",DATA_WIDTH_A="16",DATA_WIDTH_B="16",
 REGMODE_A="NOREG",REGMODE_B="NOREG",WRITEMODE_A="NORMAL",WRITEMODE_B="NORMAL")(
 output reg [15:0] doa,dob,input wire [15:0] dia,dib,input wire [10:0] addra,addrb,
 input wire bytea,bytewea,csa,wea,clka,rsta,ocea,
 input wire byteb,byteweb,csb,web,clkb,rstb,oceb);
 reg [15:0] memory[0:2047];
 initial if(MODE!="DP16K"||DATA_WIDTH_A!="16"||DATA_WIDTH_B!="16"||
  REGMODE_A!="NOREG"||REGMODE_B!="NOREG"||WRITEMODE_A!="NORMAL"||WRITEMODE_B!="NORMAL")
  $fatal(1,"wrong native scanline RAM configuration");
 always @(posedge clka)begin
  if(rsta||rstb||!ocea||!oceb||bytea||byteb||bytewea||byteweb||web)
   $fatal(1,"unsupported native scanline port controls");
  if(csa&&wea)begin
   if(addra[9:0]>=640)$fatal(1,"scanline RAM write outside640 pixels");
   if(csb&&addra[10]==addrb[10])$fatal(1,"read/write scanline bank collision");
   memory[addra]<=dia;
  end
 end
 always @(posedge clkb)if(csb)begin
  if(addrb[9:0]>=640)$fatal(1,"scanline RAM read outside640 pixels");
  dob<=memory[addrb];
 end
endmodule
