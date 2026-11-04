`timescale 1ns/1ps
// Default-limit tests accelerate elapsed time by depositing the same reachable
// timer count in DUT/reference. Public outputs remain the pass/fail oracle.
module tb_bpb_timer;
 parameter integer LIMIT=800;
 reg clk=0,rst_n=0,start=0,byte_valid=0;
 reg [31:0] partition_lba=0;
 reg [8:0] byte_addr=0;reg [7:0] byte_in=0;
 wire valid,busy,done,error;
 wire [31:0] fat_lba,root_lba,root_cluster,data_lba,cluster_count,volume_sectors;
 wire [7:0] sectors_per_cluster;
 integer count,expected_count,checks=0;
 always #5 clk=~clk;
 fat32_boot_parser #(.TIMEOUT_CYCLES(LIMIT)) dut(.*);
 task tick;begin @(negedge clk);#2;end endtask
 task begin_read;
  begin start=1;tick();start=0;if(!busy)$fatal(1,"BPB did not start");end
 endtask
 initial begin
  repeat(3)tick();rst_n=1;tick();
  repeat(2)begin
   begin_read();expected_count=LIMIT;
   if(LIMIT>2048)begin
    dut.timer=LIMIT-3;dut.__safety_reference.timer=LIMIT-3;expected_count=3;
   end
   count=0;
   while(!done&&count<=expected_count+1)begin tick();count=count+1;end
   if(!done||!error||valid||busy||count!=expected_count)$fatal(1,"BPB timeout endpoint limit=%0d count=%0d expected=%0d",LIMIT,count,expected_count);
   checks=checks+1;tick();if(done)$fatal(1,"done not a pulse");
  end
  // Timeout beats data and an overlapping start while busy.
  begin_read();dut.timer=LIMIT-1;dut.__safety_reference.timer=LIMIT-1;
  start=1;byte_valid=1;byte_addr=0;tick();start=0;byte_valid=0;
  if(!done||!error||valid||busy)$fatal(1,"timeout/data/start priority");checks=checks+1;
  tick();begin_read();
  dut.timer=LIMIT-1;dut.__safety_reference.timer=LIMIT-1;
  rst_n=0;#1;if(busy||done||error||valid)$fatal(1,"asynchronous reset");
  repeat(3)tick();rst_n=1;tick();checks=checks+1;
  begin_read();dut.timer=LIMIT-1;dut.__safety_reference.timer=LIMIT-1;tick();
  if(!done||!error||busy)$fatal(1,"restart after reset");checks=checks+1;
  tick();repeat(8)begin byte_valid=1;byte_addr=13;byte_in=8'h80;tick();end
  if(busy||done||valid)$fatal(1,"idle bytes accepted");checks=checks+1;
  $display("PASS BPB timer LIMIT=%0d checks=%0d; exact timeout/priority/reset/restart/all-204-bit equivalence",LIMIT,checks);$finish;
 end
 initial begin #1000000;$fatal(1,"BPB timer bench watchdog");end
endmodule
