`timescale 1ns/1ps
module tb_chain_cycles;
 reg clk=0,rst_n=0,start=0,rd_ready=1,rd_done=0,rd_valid=0,rd_error=0;
 reg injected=0,inject_failure=0;
 reg [8:0] rd_addr=0;
 reg [7:0] rd_data=0;
 reg [31:0] file_size=1536;
 reg [7:0] spc=1;
 reg [31:0] data_lba=2048;
 wire rd_start,out_valid,busy,done,error;
 wire [31:0] rd_lba,out_offset;
 wire [7:0] out_data;
 wire [3:0] error_code;
 integer mode=0,k,entry,seen=0,requests=0,data_requests=0,validation_requests=0;
 reg [31:0] link_value;
 always #5 clk=~clk;
 fat32_file_reader #(.TIMEOUT_CYCLES(5000)) dut(
  .clk(clk),.rst_n(rst_n),.start(start),.stop(1'b0),
  .first_cluster(32'd5),.file_size(file_size),.fat_lba(32'd32),
  .data_lba(data_lba),.cluster_count(32'd70000),.sectors_per_cluster(spc),
  .rd_ready(rd_ready),.rd_done(rd_done),.rd_error(rd_error),.rd_addr(rd_addr),
  .rd_data(rd_data),.rd_valid(rd_valid),.rd_start(rd_start),.rd_lba(rd_lba),
  .out_ready(1'b1),.out_valid(out_valid),.out_data(out_data),.out_offset(out_offset),
  .busy(busy),.done(done),.error(error),.error_code(error_code));
 function [31:0] next_link(input integer cluster);
  begin
   case(cluster)
    5:next_link=(mode==5 || mode==10)?5:130;
    130:next_link=(mode==0 || mode==11)?5:9;
    9:next_link=(mode==1 || mode==19)?130:10;
    10:next_link=11;
    11:next_link=12;
    12:next_link=(mode==2 || mode==3)?11:13;
    13:next_link=(mode==18)?9:32'h0fffffff;
    default:next_link=32'h0fffffff;
   endcase
  end
 endfunction
 always @(posedge clk)if(rst_n && out_valid)begin
  if(out_offset!==seen)$fatal(1,"offset changed mode=%0d",mode);
  seen=seen+1;
 end
 initial forever begin
  @(negedge clk);
  if(rd_start)begin
   if(!rd_ready)$fatal(1,"overlapping FAT transaction");
   requests=requests+1;rd_ready=0;
   rd_error=0;
   inject_failure=dut.validating && (mode==7 || (mode==6 && !injected));
   if(inject_failure)injected=1;
   if(dut.validating)validation_requests=validation_requests+1;
   if(rd_lba>=2048)data_requests=data_requests+1;
   if(!(dut.validating && mode==9))begin
   for(k=0;k<512;k=k+1)begin
    rd_addr=k;rd_valid=1;
    if(dut.validating && mode==8 && k==100)rd_valid=0;
    if(rd_lba>=2048)rd_data=8'ha5;
    else begin
     if(rd_lba!=32 && rd_lba!=33)$fatal(1,"unexpected FAT LBA=%0d",rd_lba);
     entry=(rd_lba-32)*128+(k/4);
     link_value=next_link(entry);
     rd_data=(link_value>>((k%4)*8));
    end
    @(negedge clk);
   end
   rd_valid=0;rd_error=inject_failure;rd_done=1;
   @(negedge clk);rd_done=0;rd_ready=1;
   end
  end
 end
 initial begin
  if(!$value$plusargs("MODE=%d",mode))mode=0;
  case(mode)
   1:file_size=4*512;
   2,4,6,7,8,9:file_size=7*512;
   3:file_size=6*512; // 后面的环不属于文件需要使用的簇前缀，不应误报。
   5:file_size=2*512;
   10:file_size=512;
   11:file_size=2*512;
   12:file_size=32'hffffffff;
   13:begin file_size=32'hffffffff;spc=128;end
   14:begin file_size=512;spc=128;data_lba=32'hfffffff0;end
   15:begin file_size=512;spc=128;data_lba=32'hfffffe00;end
   16:begin file_size=1024;data_lba=32'hffffff80;end
   17:file_size=2*512;
   18,19:file_size=3*512;
   default:;
  endcase
  repeat(3)@(negedge clk);rst_n=1;
  @(negedge clk);start=1;@(negedge clk);start=0;
  if(mode==12 || mode==13)begin
   wait(dut.state==1);#1;
   if(dut.cluster_limit!=((mode==12)?8388608:65536))
    $fatal(1,"maximum file length counter truncated mode=%0d limit=%0d",mode,dut.cluster_limit);
   $display("PASS FAT maximum file metadata mode=%0d clusters=%0d",mode,dut.cluster_limit);$finish;
  end
  if(mode==15)begin
   wait(dut.state==1);#1;
   if(error || rd_lba!=32'hffffff80)$fatal(1,"legal LBA upper boundary rejected");
   $display("PASS FAT legal LBA boundary: exclusive end is 2^32");$finish;
  end
  wait(done);#1;
  if(busy || out_valid)$fatal(1,"reader not stopped");
  if(mode==3 || mode==4 || mode==6 || mode==10 || mode==11 || mode>=17)begin
   if(error || seen!=file_size)$fatal(1,"valid prefix rejected mode=%0d code=%0d bytes=%0d",mode,error_code,seen);
  end else if(mode==14)begin
   if(!error || error_code!=1 || requests!=0)$fatal(1,"initial LBA overflow escaped");
  end else if(mode>=7 && mode<=9)begin
   if(!error || seen!=file_size || error_code!=((mode==7)?2:((mode==8)?3:6)))
    $fatal(1,"validation transport failure escaped mode=%0d code=%0d",mode,error_code);
  end else if(!error || error_code!=5)$fatal(1,"cyclic prefix accepted mode=%0d bytes=%0d",mode,seen);
  if(mode==0 && seen!=1024)$fatal(1,"start-cluster cycle not rejected promptly");
  if(mode==1 && seen!=1536)$fatal(1,"tail cycle not rejected promptly");
  if(mode==2 && validation_requests==0)$fatal(1,"finite-prefix replay not exercised");
  if(mode==17 && validation_requests!=3)$fatal(1,"acyclic prefix bound not exercised");
  if(mode==18 && validation_requests!=6)$fatal(1,"cycle beyond prefix was not bounded");
  if(validation_requests>4*(file_size/512))$fatal(1,"validation bound exceeded");
  $display("PASS FAT cycle mode=%0d bytes=%0d data=%0d validation FAT reads=%0d",mode,seen,data_requests,validation_requests);
  $finish;
 end
 initial begin #1000000;$fatal(1,"cycle test timeout mode=%0d",mode);end
endmodule
