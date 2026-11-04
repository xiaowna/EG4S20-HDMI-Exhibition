`timescale 1ns/1ps
// Independent command-level model, only BL1/CL3 subset used by this controller.
// Not a vendor silicon model, not a synthesis source.
module EG_PHY_SDRAM_2M_32(input wire clk,ras_n,cas_n,we_n,input wire [10:0] addr,
 input wire [1:0] ba,inout wire [31:0] dq,input wire cke,cs_n,dm0,dm1,dm2,dm3);
 wire [3:0] dm={dm3,dm2,dm1,dm0};
 reg [31:0] memory[0:2097151];reg [10:0] rows[0:3];reg [3:0] opened=0;
 reg out_enable=0;reg [31:0] out_data;
 reg [2:0] pipeline_valid=0;integer pipe_addr[0:2];
 integer pending=0,index=0,refreshes=0,run_refreshes=0,j;
 realtime activated[0:3],last_write[0:3],last_pre=-1000,last_refresh=-1000,last_mrs=-1000;
 realtime previous_edge=0,period=20;
 reg configured=0,precharged=0;reg [2:0] command;
 assign dq=out_enable?out_data:32'bz;
 initial for(j=0;j<4;j=j+1)begin activated[j]=-1000;last_write[j]=-1000;rows[j]=0;end
 always @(posedge clk)begin
  period=$realtime-previous_edge;previous_edge=$realtime;
  out_enable<=#5.4 0;
  if(!cke)begin configured=0;precharged=0;refreshes=0;pending=0;pipeline_valid=0;opened=0;end
  if(cke)begin
   command=cs_n?3'b111:{ras_n,cas_n,we_n};
   if(configured && $realtime-last_refresh>15600)$fatal(1,"refresh retention interval exceeded");
   if(pipeline_valid[2])begin out_data<=#5.4 memory[pipe_addr[2]];out_enable<=#5.4 1;end
   pipeline_valid={pipeline_valid[1:0],1'b0};pipe_addr[2]=pipe_addr[1];pipe_addr[1]=pipe_addr[0];
   if(command!=3'b111)begin
    if($realtime-last_refresh<63)$fatal(1,"tRFC violation");
    case(command)
     3'b010:begin
      if($realtime<200000)$fatal(1,"power-up delay less than 200us");
      for(j=0;j<4;j=j+1)if(addr[10] || ba==j)begin
       if(opened[j] && $realtime-activated[j]<42)$fatal(1,"tRAS violation");
       if(opened[j] && $realtime-last_write[j]<2*period)$fatal(1,"write recovery violation");
       opened[j]=0;
      end
      last_pre=$realtime;precharged=1;
     end
     3'b001:begin
      if(opened!=0||!precharged||$realtime-last_pre<21)$fatal(1,"refresh with open row/tRP");
      refreshes=refreshes+1;if(configured)run_refreshes=run_refreshes+1;last_refresh=$realtime;
     end
     3'b000:begin
      if(!precharged||refreshes<2||opened!=0||addr!==11'h030)$fatal(1,"bad initialization/MRS");
      configured=1;last_mrs=$realtime;
     end
     3'b011:begin
      if(!configured || opened[ba] || $realtime-last_pre<21 || $realtime-last_mrs<2*period)$fatal(1,"ACT timing/state");
      rows[ba]=addr;opened[ba]=1;activated[ba]=$realtime;
     end
     3'b100,3'b101:begin
      if(!configured||!opened[ba]||$realtime-activated[ba]<21||addr[10]||dm!=0)$fatal(1,"column timing/state");
      if(addr[9:8]!=0)$fatal(1,"column address bits");
      index=ba*524288+rows[ba]*256+addr[7:0];
      if(command==3'b100)begin
       if(^dq===1'bx)$fatal(1,"write DQ invalid");memory[index]=dq;last_write[ba]=$realtime;
      end else begin pipe_addr[0]=index;pipeline_valid[0]=1;end
     end
     default:$fatal(1,"unsupported SDRAM command");
    endcase
   end
  end
 end
endmodule
