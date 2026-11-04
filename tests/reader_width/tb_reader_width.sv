`timescale 1ns/1ps
module tb_reader_width #(parameter TIMEOUT_CYCLES=800);
 reg clk=0,rst_n=0,start=0,stop=0;
 always #5 clk=~clk;
 reg [31:0] first_cluster=5,file_size=0,fat_lba=32,data_lba=2048,cluster_count=70000;
 reg [7:0] spc=1;
 reg rd_ready=1,rd_done=0,rd_error=0,rd_valid=0,out_ready=0;
 reg [8:0] rd_addr=0;
 reg [7:0] rd_data=0;
 wire rd_start,out_valid,busy,done,error;
 wire [31:0] rd_lba,out_offset;
 wire [7:0] out_data;
 wire [3:0] error_code;
 integer cycles=0,cases=0,starts=0,completions=0,seen=0,requests=0,total_requests=0;
 integer outputs=0,arithmetic_checks=0,stall_checks=0,reset_aborts=0;
 integer j,k,n,spc_number,expected_requests;
 reg freeze_sink=0,stalled=0;
 reg [31:0] stalled_offset;
 reg [7:0] stalled_data;
 wire [80:0] public_outputs={rd_start,rd_lba,out_valid,out_data,out_offset,busy,done,error,error_code};

 fat32_file_reader #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.MAX_SECTOR_RETRIES(2)) dut(
  .clk(clk),.rst_n(rst_n),.start(start),.stop(stop),.first_cluster(first_cluster),.file_size(file_size),
  .fat_lba(fat_lba),.data_lba(data_lba),.cluster_count(cluster_count),.sectors_per_cluster(spc),
  .rd_ready(rd_ready),.rd_done(rd_done),.rd_error(rd_error),.rd_addr(rd_addr),.rd_data(rd_data),.rd_valid(rd_valid),
  .rd_start(rd_start),.rd_lba(rd_lba),.out_ready(out_ready),.out_valid(out_valid),.out_data(out_data),.out_offset(out_offset),
  .busy(busy),.done(done),.error(error),.error_code(error_code));
`ifdef COMPARE_BASELINE
 wire old_rd_start,old_out_valid,old_busy,old_done,old_error;
 wire [31:0] old_rd_lba,old_out_offset;
 wire [7:0] old_out_data;
 wire [3:0] old_error_code;
 wire [80:0] old_public={old_rd_start,old_rd_lba,old_out_valid,old_out_data,old_out_offset,
                       old_busy,old_done,old_error,old_error_code};
 fat32_file_reader_baseline #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.MAX_SECTOR_RETRIES(2)) old(
  .clk(clk),.rst_n(rst_n),.start(start),.stop(stop),.first_cluster(first_cluster),.file_size(file_size),
  .fat_lba(fat_lba),.data_lba(data_lba),.cluster_count(cluster_count),.sectors_per_cluster(spc),
  .rd_ready(rd_ready),.rd_done(rd_done),.rd_error(rd_error),.rd_addr(rd_addr),.rd_data(rd_data),.rd_valid(rd_valid),
  .rd_start(old_rd_start),.rd_lba(old_rd_lba),.out_ready(out_ready),.out_valid(old_out_valid),.out_data(old_out_data),
  .out_offset(old_out_offset),.busy(old_busy),.done(old_done),.error(old_error),.error_code(old_error_code));
`endif

 function [7:0] pattern;
  input integer position;
  begin pattern=position*73+(position/256)+17;end
 endfunction

 // The oracle uses 64-bit division, independently of the RTL's shifts and widths.
 function [63:0] required_clusters;
  input [31:0] bytes;
  input [7:0] sectors;
  reg [63:0] capacity;
  begin
   capacity=64'd512*sectors;
   required_clusters=({32'd0,bytes}+capacity-1)/capacity;
  end
 endfunction

 always @(negedge clk) out_ready=!freeze_sink && (cycles%11>=4);
 always @(posedge clk) begin
  cycles=cycles+1;
  if(!rst_n || stop) stalled=0;
  else begin
   if(stalled) begin
    if(!out_valid || out_data!==stalled_data || out_offset!==stalled_offset)
     $fatal(1,"Backpressure changed public byte case=%0d",cases);
    stall_checks=stall_checks+1;
   end
   stalled=out_valid&&!out_ready;stalled_data=out_data;stalled_offset=out_offset;
   if(out_valid&&out_ready) begin
    if(out_offset!==seen || out_data!==pattern(seen))
     $fatal(1,"Byte oracle case=%0d seen=%0d offset=%0d data=%h",cases,seen,out_offset,out_data);
    seen=seen+1;outputs=outputs+1;
   end
  end
  #1;
`ifdef COMPARE_BASELINE
  // Every public bit, including stale data, addresses and idle/error outputs.
  if(public_outputs!==old_public)
   $fatal(1,"81-bit cycle equivalence case=%0d cycle=%0d new=%h old=%h",cases,cycles,public_outputs,old_public);
`endif
 end

 task init_case;
  begin
   @(negedge clk);rst_n=0;start=0;stop=0;rd_valid=0;rd_done=0;rd_error=0;rd_ready=1;
   freeze_sink=0;first_cluster=5;file_size=1;fat_lba=32;data_lba=2048;cluster_count=70000;spc=1;
   seen=0;requests=0;cases=cases+1;
   repeat(3)@(negedge clk);rst_n=1;
  end
 endtask

 task launch;
  reg [63:0] expected;
  begin
   @(negedge clk);start=1;starts=starts+1;
   @(negedge clk);start=0;
   if(file_size!=0 && spc!=0 && (spc&(spc-1))==0) begin
    expected=required_clusters(file_size,spc);
    if(dut.cluster_limit!==expected[23:0])
     $fatal(1,"Required-cluster oracle bytes=%0d spc=%0d got=%0d expected=%0d",file_size,spc,dut.cluster_limit,expected);
    arithmetic_checks=arithmetic_checks+1;
   end
  end
 endtask

 task await_request;
  integer guard;
  begin
   guard=0;
   while(!rd_start) begin
    @(negedge clk);guard=guard+1;
    if(done || guard>TIMEOUT_CYCLES+20)$fatal(1,"Missing request case=%0d",cases);
   end
  end
 endtask

 task check_done;
  input integer expected_error,expected_code,expected_seen;
  integer guard;
  begin
   guard=0;
   while(!done) begin
    @(negedge clk);guard=guard+1;
    if(guard>TIMEOUT_CYCLES+3000)$fatal(1,"Missing completion case=%0d",cases);
   end
   if(busy || out_valid || error!==expected_error[0] || error_code!==expected_code[3:0] || seen!=expected_seen)
    $fatal(1,"Completion case=%0d err=%0d code=%0d seen=%0d expected=%0d/%0d/%0d",cases,error,error_code,seen,
           expected_error,expected_code,expected_seen);
   completions=completions+1;
  end
 endtask

 // Complete a sector. Failed CRC bytes deliberately disagree with the oracle.
 task sector;
  input integer is_fat,byte_base,fail_crc,bad_order,fat_mode;
  integer idx,entry,shift,before_seen;
  reg [31:0] entry_value;
  begin
   requests=requests+1;total_requests=total_requests+1;rd_ready=0;before_seen=seen;
   for(idx=0;idx<512;idx=idx+1) begin
    rd_valid=1;rd_addr=(bad_order && idx==400)?399:idx;rd_data=pattern(byte_base+idx);
    if(is_fat) begin
     entry=idx/4;shift=(idx%4)*8;entry_value=0;
     if(entry==5)entry_value=(fat_mode==1)?32'h0fffffff:(fat_mode==2)?5:6;
     if(entry==6)entry_value=32'h0fffffff;
     rd_data=entry_value>>shift;
    end
    if(fail_crc)rd_data=~rd_data;
    @(negedge clk);
    rd_valid=0;
    if(idx%43==0)@(negedge clk);
   end
   if(seen!=before_seen)$fatal(1,"Unverified sector byte escaped case=%0d",cases);
   repeat(2)@(negedge clk);
   rd_error=fail_crc;rd_done=1;
   @(negedge clk);rd_done=0;rd_error=0;rd_ready=1;
  end
 endtask

 // Independent public request model: clusters 5 -> 6 -> EOC, contiguous LBAs.
 // It validates the full final sector and the transition after sector 127.
 task run_file;
  input integer fault,expected_error,expected_code,expected_seen;
  integer data_sectors,attempt,failed,fat_seen,guard,base_offset;
  reg [63:0] expected_lba;
  begin
   data_sectors=0;attempt=0;fat_seen=0;guard=0;
   while(!done) begin
    @(negedge clk);guard=guard+1;
    if(guard>1000000)$fatal(1,"File deadline case=%0d",cases);
    if(rd_start) begin
     if(rd_lba==fat_lba) begin
      if(seen!=file_size && (data_sectors==0 || data_sectors%spc!=0))
       $fatal(1,"Premature FAT request case=%0d sectors=%0d",cases,data_sectors);
      sector(1,0,0,0,(fault==4)?1:(fault==6)?2:0);fat_seen=fat_seen+1;
     end else begin
      expected_lba={32'd0,data_lba}+({32'd0,first_cluster}-2)*spc+data_sectors;
      if(rd_lba!==expected_lba[31:0] || expected_lba>64'hffffffff)
       $fatal(1,"Data LBA oracle case=%0d sector=%0d got=%h expected=%h",cases,data_sectors,rd_lba,expected_lba);
      if(data_sectors>0 && data_sectors%spc==0 && fat_seen==0)
       $fatal(1,"Skipped FAT lookup at cluster boundary");
      failed=(fault==1 && attempt==0)||(fault==2);
      base_offset=data_sectors*512;
      sector(0,base_offset,failed,fault==3,0);attempt=attempt+1;
      if(!failed)begin data_sectors=data_sectors+1;fat_seen=0;end
     end
    end
   end
   check_done(expected_error,expected_code,expected_seen);
  end
 endtask

 task start_only;
  input [31:0] bytes;
  begin
   init_case;file_size=bytes;spc=spc_number;rd_ready=0;launch;
   if(bytes==0)check_done(0,0,0);
   else begin
    repeat(3)@(negedge clk);
    if(!busy || rd_start || rd_lba!==2048+3*spc_number)$fatal(1,"START_CHECK boundary failed");
    reset_aborts=reset_aborts+1;
   end
  end
 endtask

 // First-cluster sharing must reject all upper cluster bits and keep the
 // exclusive sector-end boundary exact for every legal cluster size.
 task address_probe;
  input [31:0] cluster,base,limit;
  input [7:0] sectors;
  reg [63:0] sector_start,sector_end;
  reg [31:0] limit_end;
  begin
   init_case;first_cluster=cluster;data_lba=base;cluster_count=limit;spc=sectors;rd_ready=0;
   sector_start={32'd0,base}+({32'd0,cluster}-64'd2)*sectors;
   sector_end=sector_start+sectors;limit_end=limit+2;
   launch;
   if(cluster<2||cluster>=32'h0ffffff0||cluster>=limit_end||sector_end>64'h100000000)
    check_done(1,1,0);
   else begin
    repeat(3)@(negedge clk);
    if(!busy||rd_start||rd_lba!==sector_start[31:0])$fatal(1,"Shared first LBA oracle cluster=%h base=%h spc=%0d got=%h expected=%h",cluster,base,sectors,rd_lba,sector_start);
    reset_aborts=reset_aborts+1;
   end
  end
 endtask

 initial begin
  for(j=0;j<8;j=j+1)begin
   spc_number=1<<j;
   address_probe(5,32'hffffffff-4*spc_number+1,70000,spc_number);
   address_probe(5,32'hffffffff-4*spc_number+2,70000,spc_number);
   address_probe(5,32'hffffffff-4*spc_number,70000,spc_number);
   address_probe(32'h0fffffef,0,32'h0fffffee,spc_number);
   address_probe(32'h10000005,0,70000,spc_number);
   address_probe(32'hf0000005,0,70000,spc_number);
   address_probe(0,32'hffffffff,70000,spc_number);
  end
  // Full width boundaries for every legal cluster size. These transactions are
  // intentionally reset after START_CHECK instead of streaming gigabytes.
  for(j=0;j<8;j=j+1)begin
   spc_number=1<<j;
   start_only(0);start_only(1);start_only(511);start_only(512);start_only(513);
   start_only(32'hffffffff);
   start_only(spc_number*512-1);start_only(spc_number*512);start_only(spc_number*512+1);
   start_only(spc_number*512*255);start_only(spc_number*512*255+1);
   // Public transaction and byte checks across the final sector of each SPC.
   init_case;spc=spc_number;file_size=spc_number*512+1;launch;run_file(0,0,0,file_size);
   expected_requests=spc_number+4;
   if(requests!=expected_requests)$fatal(1,"Cluster-boundary request count spc=%0d got=%0d expected=%0d",spc,requests,expected_requests);
  end

  // Short complete files exercise sector and cluster rounding without aborts.
  for(j=0;j<5;j=j+1)begin
   init_case;
   case(j)0:file_size=0;1:file_size=1;2:file_size=511;3:file_size=512;4:file_size=513;endcase
   launch;
   if(file_size==0)check_done(0,0,0);else run_file(0,0,0,file_size);
  end

  init_case;file_size=513;launch;run_file(1,0,0,513);
  if(requests!=6)$fatal(1,"CRC retry request count");
  init_case;launch;run_file(2,1,2,0);
  if(requests!=3)$fatal(1,"CRC exhaustion request count");
  init_case;launch;run_file(3,1,3,0);
  init_case;file_size=513;launch;run_file(4,1,4,512);
  init_case;file_size=513;launch;run_file(6,1,5,512);

  // First-sector exclusive end exactly 2^32 is legal; one above is rejected.
  init_case;data_lba=32'hfffffffc;launch;run_file(0,0,0,1);
  init_case;data_lba=32'hfffffffc;first_cluster=6;launch;check_done(1,1,0);
  init_case;data_lba=32'hfffffffc;file_size=513;launch;run_file(0,1,5,512);
  init_case;spc=128;data_lba=32'hffffff00;first_cluster=5;launch;check_done(1,1,0);
  init_case;spc=3;launch;check_done(1,1,0);
  init_case;spc=0;launch;check_done(1,1,0);
  init_case;first_cluster=1;launch;check_done(1,1,0);
  init_case;first_cluster=32'h0ffffff0;launch;check_done(1,1,0);

  // Requests and receives independently exercise the timer and restart path.
  init_case;rd_ready=0;launch;check_done(1,6,0);
  @(negedge clk);seen=0;requests=0;rd_ready=1;launch;run_file(0,0,0,1);
  init_case;launch;await_request;rd_ready=0;
  rd_valid=1;rd_addr=0;rd_data=pattern(0);@(negedge clk);rd_valid=0;
  check_done(1,6,0);

  // Stop while a verified byte is stalled; no byte is accepted by the sink.
  init_case;file_size=513;freeze_sink=1;launch;await_request;sector(0,0,0,0,0);
  while(!out_valid)@(negedge clk);
  repeat(5)@(negedge clk);stop=1;@(negedge clk);check_done(0,0,0);stop=0;
  // Reset during an incomplete receive, then restart normally.
  init_case;launch;await_request;rd_ready=0;rd_valid=1;rd_addr=0;rd_data=pattern(0);
  @(negedge clk);rd_valid=0;reset_aborts=reset_aborts+1;
  init_case;launch;run_file(0,0,0,1);

  $display("PASS reader-width timeout=%0d cases=%0d starts=%0d completions=%0d reset_aborts=%0d arithmetic=%0d requests=%0d bytes=%0d stalls=%0d cycles=%0d public_bits=81",
           TIMEOUT_CYCLES,cases,starts,completions,reset_aborts,arithmetic_checks,total_requests,outputs,stall_checks,cycles);
  $finish;
 end
 initial begin #30000000;$fatal(1,"Simulation deadline");end
endmodule
