`timescale 1ns/1ps

// Four one-sector clusters exercise the file-size bound independently of the
// optional legacy MAX_FILE_CLUSTERS cap. The old RTL rejects the first hop
// when MAX_FILE_CLUSTERS is zero.
module tb_cluster_limit;
 reg clk=0,rst_n=0,start=0;
 always #5 clk=~clk;
 reg [31:0] file_size=1600;
 reg rd_ready=1,rd_done=0,rd_valid=0;
 reg [8:0] rd_addr=0;
 reg [7:0] rd_data=0;
 wire rd_start,busy,done,error,out_valid;
 wire [31:0] rd_lba,out_offset;
 wire [7:0] out_data;
 wire [3:0] error_code;
 integer mode=0,requests=0,seen=0,bank,k;
 reg [31:0] expected_lba;

 function [7:0] pattern;
  input integer offset;
  begin pattern=offset*13+7;end
 endfunction

 fat32_file_reader #(.TIMEOUT_CYCLES(5000),.MAX_FILE_CLUSTERS(0)) dut(
  .clk(clk),.rst_n(rst_n),.start(start),.stop(1'b0),
  .first_cluster(32'd5),.file_size(file_size),
  .fat_lba(32'd32),.data_lba(32'd2048),.cluster_count(32'd100),
  .sectors_per_cluster(8'd1),
  .rd_ready(rd_ready),.rd_done(rd_done),.rd_error(1'b0),
  .rd_addr(rd_addr),.rd_data(rd_data),.rd_valid(rd_valid),
  .rd_start(rd_start),.rd_lba(rd_lba),
  .out_ready(1'b1),.out_valid(out_valid),.out_data(out_data),
  .out_offset(out_offset),.busy(busy),.done(done),.error(error),
  .error_code(error_code));

 always @(posedge clk) if(rst_n && out_valid) begin
  if(out_offset!==seen || out_data!==pattern(seen))
   $fatal(1,"Byte %0d: offset=%0d data=%02h",seen,out_offset,out_data);
  seen=seen+1;
 end

 // Complete CMD17-sized transactions, including a FAT sector for each hop.
 initial forever begin
  @(negedge clk);
  if(rd_start) begin
   if(!rd_ready)$fatal(1,"Overlapping sector request");
   if(dut.validating)expected_lba=32;
   else case(requests)
    0:expected_lba=2051;
    1:expected_lba=32;
    2:expected_lba=2052;
    3:expected_lba=32;
    4:expected_lba=2053;
    5:expected_lba=32;
    6:expected_lba=2054;
    default:$fatal(1,"Unexpected extra sector request %0d",requests);
   endcase
   if(rd_lba!==expected_lba)
    $fatal(1,"Request %0d: LBA=%0d expected=%0d",requests,rd_lba,expected_lba);
   if(!dut.validating)requests=requests+1;
   rd_ready=0;
   bank=rd_lba-2051;
   repeat(2)@(negedge clk);
   for(k=0;k<512;k=k+1)begin
    rd_addr=k;rd_valid=1;rd_data=0;
    if(rd_lba!=32)rd_data=pattern(bank*512+k);
    else begin
     if(k==20)rd_data=6;
     if(k==24)rd_data=7;
     if(k==28)rd_data=(mode==2)?8'hff:8;
     if(mode==2 && k==29)rd_data=8'hff;
     if(mode==2 && k==30)rd_data=8'hff;
     if(mode==2 && k==31)rd_data=8'h0f;
    end
    @(negedge clk);
   end
   rd_valid=0;
   repeat(2)@(negedge clk);
   rd_done=1;
   @(negedge clk);rd_done=0;rd_ready=1;
  end
 end

 initial begin
  if(!$value$plusargs("MODE=%d",mode))mode=0;
  if(mode==1)file_size=1024;
  repeat(3)@(negedge clk);rst_n=1;
  @(negedge clk);start=1;
  @(negedge clk);start=0;
  wait(done);#1;
  if(busy || out_valid)$fatal(1,"Reader did not stop at file boundary");
  case(mode)
   0:if(error || seen!=1600 || requests!=7)
      $fatal(1,"Four-cluster file failed: error=%0d code=%0d bytes=%0d sectors=%0d",error,error_code,seen,requests);
   1:if(error || seen!=1024 || requests!=3)
      $fatal(1,"File-size boundary failed: error=%0d code=%0d bytes=%0d sectors=%0d",error,error_code,seen,requests);
   2:if(!error || error_code!=4 || seen!=1536 || requests!=6)
      $fatal(1,"Premature EOC failed: error=%0d code=%0d bytes=%0d sectors=%0d",error,error_code,seen,requests);
   default:$fatal(1,"Unknown mode %0d",mode);
  endcase
  $display("PASS cluster limit mode=%0d bytes=%0d sectors=%0d",mode,seen,requests);
  $finish;
 end
 initial begin #1000000;$fatal(1,"Cluster limit simulation timeout");end
endmodule
