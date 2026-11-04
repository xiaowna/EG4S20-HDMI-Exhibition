`timescale 1ns/1ps
module tb_file;
 reg clk=0,rst_n=0,start=0;
 always #5 clk=~clk;
 reg [31:0] first_cluster=5,file_size=1300;
 reg [7:0] spc=1;
 reg rd_ready=1,rd_done=0,rd_error=0,rd_valid=0,out_ready=0;
 reg [8:0] rd_addr=0;
 reg [7:0] rd_data=0;
 wire req,busy,done,error,out_valid;
 wire [31:0] lba,offset;
 wire [7:0] data;
 wire [3:0] code;
 integer mode=0,requests=0,seen=0,k,bank,cycles=0;
 reg [31:0] old_offset;
 reg [7:0] old_data;
 reg stalled=0;
 function [7:0] pattern;
  input integer pos;
  begin pattern=(pos*73)+(pos/256)+17;end
 endfunction
 fat32_file_reader #(.TIMEOUT_CYCLES(3000),.MAX_FILE_CLUSTERS(8)) dut(
  .clk(clk),.rst_n(rst_n),.start(start),.stop(1'b0),.first_cluster(first_cluster),.file_size(file_size),
  .fat_lba(32'd32),.data_lba(32'd2048),.cluster_count(32'd70000),.sectors_per_cluster(spc),
  .rd_ready(rd_ready),.rd_done(rd_done),.rd_error(rd_error),.rd_addr(rd_addr),.rd_data(rd_data),.rd_valid(rd_valid),
  .rd_start(req),.rd_lba(lba),.out_ready(out_ready),.out_valid(out_valid),.out_data(data),.out_offset(offset),
  .busy(busy),.done(done),.error(error),.error_code(code));
 always @(negedge clk) begin cycles=cycles+1;out_ready=(cycles%9>=4);end
 always @(posedge clk) begin
  if(rst_n) begin
   if(stalled && (!out_valid || data!==old_data || offset!==old_offset)) $fatal(1,"Output changed while stalled");
   stalled=out_valid && !out_ready;old_data=data;old_offset=offset;
   if(out_valid && out_ready) begin
    if(offset!==seen || data!==pattern(seen)) $fatal(1,"Bad data at %0d got offset=%0d data=%h",seen,offset,data);
    seen=seen+1;
   end
  end
 end
 initial forever begin
  @(negedge clk);
  if(req) begin
   if(!rd_ready) $fatal(1,"Overlapping request");
   // requests 保留原传输/重试计数；末尾 FAT 复核由专门环路回归计数。
   if(!dut.validating)requests=requests+1;
   rd_ready=0;rd_error=0;
   if(mode==10) begin
    if(lba==2054) bank=0;else if(lba==2055)bank=1;else if(lba==2304)bank=2;else if(lba==32)bank=3;
    else if(dut.validating && lba==33)bank=4;
    else $fatal(1,"Bad multi-sector-cluster LBA %0d",lba);
   end else begin
    if(lba==2051)bank=0;else if(lba==2176)bank=1;else if(lba==2055)bank=2;
    else if(lba==32)bank=3;else if(lba==33)bank=4;
    else $fatal(1,"Bad fragmented-file LBA %0d",lba);
   end
   if(mode!=11) begin
    repeat(3) @(negedge clk);
    for(k=0;k<512;k=k+1) begin
     rd_addr=k;rd_valid=1;rd_data=0;
     if(bank<3)rd_data=pattern(bank*512+k);
     if(bank==3 && k==20)rd_data=8'h82;
     if(bank==3 && k==23)rd_data=8'hf0;
     if(bank==4 && k==8)rd_data=9;
     if(mode==7 && bank==3 && k>=20 && k<=23) rd_data=(k==23)?8'h0f:8'hff;
     if(mode==8 && bank==3 && k==20)rd_data=5;
     if(mode==9 && bank==3 && k>=20 && k<=23)rd_data=(k==20)?8'hf7:(k==23)?8'h0f:8'hff;
     if(mode==5 && bank==0 && k==400)rd_valid=0;
     if(mode==6 && bank==0 && k==400)rd_addr=399;
     @(negedge clk);rd_valid=0;
     if(k%17==0)repeat(2)@(negedge clk);
    end
    repeat(4)@(negedge clk);
    if(mode==3 && bank==0 && seen!=0)$fatal(1,"CRC-unchecked bytes escaped");
    rd_error=(mode==3 && bank==0)||(mode==4 && bank==1)||(mode==14 && bank==3);
    rd_done=1;@(negedge clk);rd_done=0;rd_ready=1;
   end
  end
 end
 initial begin
  if(!$value$plusargs("MODE=%d",mode)) mode=0;
  case(mode)
   1:file_size=512;
   2:file_size=0;
   10:spc=2;
   12:first_cluster=1;
   13:spc=3;
   15:file_size=1536;
   16:file_size=1;
   17:file_size=514;
  endcase
  #12;rst_n=1;@(negedge clk);start=1;@(negedge clk);start=0;
  // Latch check: caller values can change after the accepted start.
  first_cluster=99;
  wait(done);#1;
  if(busy || out_valid) $fatal(1,"Reader did not stop");
  case(mode)
   0:if(error || seen!=1300 || requests!=5)$fatal(1,"Fragmented-file failure");
   1:if(error || seen!=512 || requests!=1)$fatal(1,"Sector boundary failure");
   2:if(error || seen!=0 || requests!=0)$fatal(1,"Zero file failure");
   3:if(!error || code!=2 || seen!=0)$fatal(1,"CRC failure");
   4:if(!error || code!=2 || seen!=512)$fatal(1,"Late CRC failure");
   5,6:if(!error || code!=3 || seen!=0)$fatal(1,"Byte sequence failure");
   7:if(!error || code!=4 || seen!=512)$fatal(1,"Truncated chain failure");
   8,9:if(!error || code!=5 || seen!=512)$fatal(1,"Bad chain failure");
   10:if(error || seen!=1300 || requests!=4)$fatal(1,"Multi-sector-cluster failure");
   11:if(!error || code!=6 || seen!=0)$fatal(1,"Timeout failure");
   12,13:if(!error || code!=1 || requests!=0)$fatal(1,"Metadata failure");
   14:if(!error || code!=2 || seen!=512)$fatal(1,"FAT CRC failure");
   15:if(error || seen!=1536 || requests!=5)$fatal(1,"Exact file end failure");
   16:if(error || seen!=1 || requests!=1)$fatal(1,"Short file failure");
   17:if(error || seen!=514 || requests!=3)$fatal(1,"Short second cluster failure");
  endcase
  if(mode==0) begin
   @(negedge clk);first_cluster=5;file_size=1;seen=0;requests=0;start=1;
   @(negedge clk);start=0;wait(done);#1;
   if(error || seen!=1 || requests!=1)$fatal(1,"Restart failure");
  end
  $display("PASS FAT32 file stream mode=%0d",mode);$finish;
 end
 initial begin #500000;$fatal(1,"Simulation deadline");end
endmodule
