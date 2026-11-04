// Public EG4 true-dual-port, synchronous read contract for the FFT wrappers.
// This validates native elaboration and wiring, not encrypted vendor timing.
module EG_PHY_BRAM32K #(
 parameter MODE="DP16K",DATA_WIDTH_A="16",DATA_WIDTH_B="16",
 REGMODE_A="NOREG",REGMODE_B="NOREG",WRITEMODE_A="NORMAL",WRITEMODE_B="NORMAL")(
 output reg [15:0] doa,dob,input wire [15:0] dia,dib,input wire [10:0] addra,addrb,
 input wire bytea,bytewea,csa,wea,clka,rsta,ocea,
 input wire byteb,byteweb,csb,web,clkb,rstb,oceb);
 reg [15:0] memory[0:2047];
 initial if(MODE!="DP16K"||DATA_WIDTH_A!="16"||DATA_WIDTH_B!="16"||
  REGMODE_A!="NOREG"||REGMODE_B!="NOREG"||WRITEMODE_A!="NORMAL"||WRITEMODE_B!="NORMAL")
  $fatal(1,"unsupported FFT native RAM configuration");
 always @(posedge clka)begin
  if(clkb!==1'b1||rsta||rstb||!ocea||!oceb||bytea||byteb||bytewea||byteweb)
   $fatal(1,"unsupported FFT native RAM clock or controls");
  if(csa&&wea&&csb&&web&&addra==addrb)$fatal(1,"native RAM has conflicting writes");
  if(csa)begin doa<=memory[addra];if(wea)memory[addra]<=dia;end
 end
 always @(posedge clkb)if(csb)begin dob<=memory[addrb];if(web)memory[addrb]<=dib;end
endmodule
