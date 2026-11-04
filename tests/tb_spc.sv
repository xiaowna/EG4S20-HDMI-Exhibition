`timescale 1ns/1ps
module tb_spc;
 reg clk=0,rst=0,start=0;reg [7:0] spc=1;always #5 clk=~clk;
 wire req;wire [31:0] lba;integer i;
 fat32_file_reader dut(.clk(clk),.rst_n(rst),.start(start),.stop(1'b0),.first_cluster(32'h12345),.file_size(32'd1),
 .fat_lba(32'd32),.data_lba(32'd1000),.cluster_count(32'd200000),.sectors_per_cluster(spc),
 .rd_ready(1'b1),.rd_done(1'b0),.rd_error(1'b0),.rd_addr(9'd0),.rd_data(8'd0),.rd_valid(1'b0),.rd_start(req),.rd_lba(lba),.out_ready(1'b1));
 initial begin
  for(i=0;i<8;i=i+1)begin
   @(negedge clk);rst=0;spc=1<<i;@(negedge clk);rst=1;start=1;@(negedge clk);start=0;
   wait(req);#1;if(lba!==(1000+(32'h12345-2)*(1<<i)))$fatal(1,"SPC address mismatch");
  end
  $display("PASS FAT32 shift optimization: all legal sectors-per-cluster values");$finish;
 end
 initial begin #10000;$fatal(1,"timeout");end
endmodule
