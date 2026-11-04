`timescale 1ns/1ps
// One valid 48kHz stereo PCM16 file: 160 samples in clusters 2 and 3.
// Transaction completion follows all 512 bytes; no mid-sector cancellation.
module mode_wav_sector_model(
 input wire clk,rst_n,rd_start,input wire [31:0] rd_lba,
 input wire [15:0] extra_delay,
 output wire rd_ready,output reg rd_done,output wire rd_error,
 output reg [8:0] rd_addr,output reg [7:0] rd_data,output reg rd_valid,
 output reg busy);
 reg [31:0] lba;
 integer delay_count,position,cycle;
 assign rd_ready=!busy;
 assign rd_error=0;
 function [7:0] byte_at;
  input [31:0] sector;input integer address;
  integer offset,index,value;
  begin
   byte_at=0;
   if(sector==20)begin
    if(address==8)byte_at=3;
    if(address==12 || address==13 || address==14)byte_at=8'hff;
    if(address==15)byte_at=8'h0f;
   end else if(sector==100 || sector==101)begin
    offset=(sector-100)*512+address;
    case(offset)
     0:byte_at="R";1:byte_at="I";2:byte_at="F";3:byte_at="F";
     4:byte_at=8'ha4;5:byte_at=2;
     8:byte_at="W";9:byte_at="A";10:byte_at="V";11:byte_at="E";
     12:byte_at="f";13:byte_at="m";14:byte_at="t";15:byte_at=" ";
     16:byte_at=16;20:byte_at=1;22:byte_at=2;
     24:byte_at=8'h80;25:byte_at=8'hbb;
     28:byte_at=0;29:byte_at=8'hee;30:byte_at=2;
     32:byte_at=4;34:byte_at=16;
     36:byte_at="d";37:byte_at="a";38:byte_at="t";39:byte_at="a";
     40:byte_at=8'h80;41:byte_at=2;
     default:if(offset>=44 && offset<684)begin
      index=(offset-44)/4;
      value=((offset-44)%4<2?16'h1000:16'h6000)+index;
      byte_at=((offset-44)%2)?value>>8:value;
     end
    endcase
   end
  end
 endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin busy<=0;rd_done<=0;rd_valid<=0;rd_addr<=0;rd_data<=0;lba<=0;delay_count<=0;position<=0;cycle<=0;end
  else begin
   cycle<=cycle+1;rd_done<=0;rd_valid<=0;
   if(!busy)begin
    if(rd_start)begin busy<=1;lba<=rd_lba;position<=0;delay_count<=extra_delay+3;end
   end else if(delay_count!=0)delay_count<=delay_count-1;
   else if(position==512)begin rd_done<=1;busy<=0;end
   else if(cycle%5!=0)begin
    rd_addr<=position;rd_data<=byte_at(lba,position);rd_valid<=1;position<=position+1;
   end
  end
 end
endmodule
