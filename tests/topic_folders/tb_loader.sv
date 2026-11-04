`timescale 1ns/1ps
module tb_topic_loader;
 reg clk=0,rst_n=0,scan_start=0,load_start=0;reg [4:0] image_index=0;reg [1:0] wav_index=0;
 wire load_ready,catalog_ready,scan_done,image_done,error,rd_start,wr_valid,front_valid,front_bank,committed,rejected;
 wire [4:0] image_count;wire [2:0] wav_count;wire [24:0] folder_info;
 wire [31:0] rd_lba,wr_addr,wr_data,wav_cluster,wav_size;
 reg rd_valid=0,rd_done=0,rd_error=0;reg [8:0] rd_addr=0;reg [7:0] rd_data=0;
 reg responding=0;integer pos=0,bank=0,cycles=0,drain=0,writes=0,commits=0,rejects=0;
 integer requests=0,before_requests=0,before_commits=0,variant=0,loading=0;
 reg fail_directory=0;reg [7:0] fixture[0:32767];reg [31:0] memory[0:15];
 always #5 clk=~clk;
 wire wr_ready=cycles%5!=0;
 fat32_frame_loader #(.FRAME_WIDTH(4),.FRAME_HEIGHT(2),.MAX_IMAGES(24),.FIND_WAV(1),.MAX_WAVS(4),.TIMEOUT_CYCLES(30000)) dut(
  .clk(clk),.rst_n(rst_n),.scan_start(scan_start),.load_start(load_start),.image_index(image_index),
  .load_ready(load_ready),.catalog_ready(catalog_ready),.scan_done(scan_done),.image_done(image_done),.error(error),.image_count(image_count),
  .rd_start(rd_start),.rd_lba(rd_lba),.rd_ready(!responding),.rd_valid(rd_valid),.rd_done(rd_done),.rd_error(rd_error),.rd_addr(rd_addr),.rd_data(rd_data),
  .wr_valid(wr_valid),.wr_addr(wr_addr),.wr_data(wr_data),.wr_ready(wr_ready),.wr_drained(drain==0),
  .swap_window(cycles%17==0),.front_valid(front_valid),.front_bank(front_bank),.frame_committed(committed),.frame_rejected(rejected),
  .read_valid(1'b0),.read_addr(32'd0),.rgb_ready(1'b1),.mem_read_ready(1'b0),.mem_response_valid(1'b0),.mem_response_data(32'd0),
  .commit_enable(1'b1),.discard_cached(1'b0),.wav_index(wav_index),.wav_count(wav_count),.wav_first_cluster(wav_cluster),.wav_size(wav_size),.folder_info(folder_info));
 function automatic [23:0] color(input integer p,id);
  reg [7:0] r,g,b;begin r=17+id*3+p%4;g=31+id*5+p/4;b=29+id*7+p%4+p/4;color={r,g,b};end
 endfunction
 task tick;begin @(negedge clk);#1;end endtask
 always @(posedge clk)begin
  cycles<=cycles+1;if(drain>0)drain<=drain-1;
  if(rst_n)begin
   if(load_start&&load_ready)begin loading=image_index;writes=0;end
   if(wr_valid&&wr_ready)begin
    if(wr_addr>=16||(front_valid&&wr_addr/8==front_bank))$fatal(1,"visible/out-of-range bank write");
    if(wr_data!=={8'd0,color(wr_addr%8,loading)})$fatal(1,"folder metadata selected wrong BMP id%0d addr%0d got%h",loading,wr_addr,wr_data);
    memory[wr_addr]=wr_data;writes=writes+1;drain<=7;
   end
   if(committed)begin if(writes!=8||drain!=0)$fatal(1,"partial frame commit");commits=commits+1;end
   if(rejected)rejects=rejects+1;
   if(rd_start)begin
    if(responding)$fatal(1,"overlapping sectors");
    case(rd_lba)0:bank=0;2048:bank=1;2080:bank=2;
     default:begin if(rd_lba<2680||rd_lba>=2741)$fatal(1,"unexpected sector %0d",rd_lba);bank=3+rd_lba-2680;end
    endcase
    responding=1;pos=0;requests=requests+1;
   end
  end
 end
 always @(negedge clk)begin
  rd_valid=0;rd_done=0;rd_error=0;
  if(responding)begin
   if(pos<512)begin rd_valid=1;rd_addr=pos;rd_data=fixture[bank*512+pos];pos=pos+1;end
   else begin rd_done=1;rd_error=fail_directory&&bank==6;responding=0;end
  end
 end
 task scan(input integer count,input [24:0] info,input bit bad);
  begin
   tick;scan_start=1;tick;scan_start=0;wait(scan_done);tick;
   if(error!==bad||catalog_ready===bad)$fatal(1,"catalogue ready/error publication");
   if(!bad&&(image_count!=count||folder_info!==info||wav_count!=4))$fatal(1,"folder pipeline count/info got %0d %h expected%0d %h",image_count,folder_info,count,info);
   if(bad&&(image_count!=0||folder_info[24]))$fatal(1,"bad scan publishes stale catalogue");
   if(!bad)for(integer j=0;j<4;j=j+1)begin wav_index=j;repeat(4)tick;
    if(wav_cluster!=50+j||wav_size!=1000+j)$fatal(1,"root shared music lost");
   end
  end
 endtask
 task photo(input integer id);
  begin wait(load_ready);tick;image_index=id;before_commits=commits;load_start=1;tick;load_start=0;
   wait(commits>before_commits);tick;
   for(integer p=0;p<8;p=p+1)if(memory[front_bank*8+p]!=={8'd0,color(p,id)})$fatal(1,"incomplete visible photo");
  end
 endtask
 initial begin
  $readmemh("loader0.hex",fixture);repeat(4)tick;rst_n=1;
  scan(6,{1'b1,6'd6,6'd5,6'd2,6'd2},0);
  for(integer j=0;j<6;j=j+1)photo(j);
  before_commits=commits;fail_directory=1;scan(0,0,1);
  if(commits!=before_commits||!front_valid)$fatal(1,"failed scan replaced front");
  before_requests=requests;tick;load_start=1;tick;load_start=0;repeat(20)tick;
  if(requests!=before_requests||commits!=before_commits)$fatal(1,"failed scan reads stale metadata");
  fail_directory=0;$readmemh("loader1.hex",fixture);scan(1,{1'b1,6'd1,6'd1,6'd0,6'd0},0);photo(0);
  $readmemh("loader2.hex",fixture);scan(2,25'd0,0);photo(0);photo(1);
  $display("PASS mounted FAT32 -> TOPIC folders -> BMP -> double-buffer commit:9 photos, CRC rescan fence, shortened/missing groups, root-only4 WAV and flat rescan fallback");$finish;
 end
 initial begin #100000000;$fatal(1,"folder loader timeout");end
endmodule
