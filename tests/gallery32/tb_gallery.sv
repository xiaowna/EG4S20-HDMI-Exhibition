`timescale 1ns/1ps
// Real FAT32 mount/catalogue/file/BMP path, prefetch controller, frame banks
// and SD/audio arbiter. Sector bytes and pixel expectations are independent.
module tb_gallery #(parameter integer COUNT=32,CAP=32);
 localparam W=4,H=2,N=W*H,EXPECTED=(COUNT>CAP)?CAP:COUNT,COUNT_BITS=$clog2(CAP+1);
 reg clk=0,rst_n=0,next_pulse=0,prev_pulse=0,pause=1,auto_enable=0;
 reg manual=1,manual_scan=0,manual_load=0;reg [4:0] manual_index=31;
 wire control_scan,control_load;wire [4:0] control_index;
 wire scan_start=manual?manual_scan:control_scan;
 wire load_start=manual?manual_load:control_load;
 wire [4:0] image_index=manual?manual_index:control_index;
 wire load_ready,scan_done,image_done,error,catalog_ready;
 wire [COUNT_BITS-1:0] image_count;
 wire control_commit,control_discard,transition_active;
 wire commit_enable=manual?1'b1:control_commit;
 wire discard_cached=manual?1'b0:control_discard;
 wire frame_prepared,front_valid,front_bank,frame_committed,frame_rejected;
 wire wr_valid;wire [31:0] wr_addr,wr_data;
 reg [4:0] display_index=0,loading_index=0;
 integer cycles=0,commits=0,loads=0,rejects=0,writes=0,frame_writes=0,drain=0;
 integer audio_bytes=0,audio_sectors=0,audio_cooldown=0,crc_errors=0,requests=0,image_requests=0,invalid_events=0;
 integer bad_slot=-1,crc_slot=-1;
 reg [31:0] memory[0:2*N-1];reg seen[0:N-1];
 wire wr_ready=cycles%5!=0;
 wire image_start,image_ready,rd_done,rd_error,rd_valid;
 wire [31:0] image_lba;wire [8:0] rd_addr;wire [7:0] rd_data;
 wire card_start;wire [31:0] card_lba;
 reg card_ready=1,card_done=0,card_error=0,card_valid=0;
 reg [8:0] card_addr=0;reg [7:0] card_data=0;
 reg audio_start=0,audio_busy=0;
 wire audio_ready,audio_done,audio_error,audio_valid;
 wire [8:0] audio_addr;wire [7:0] audio_data;
 reg [7:0] fixture[0:19967];
 integer bank,k,before_commit,before_requests,goal;
 reg [31:0] selected_lba;
 always #5 clk=~clk;
 function automatic [23:0] color(input integer px,py,id);
  reg [7:0] r,g,b;
  begin r=17+id*3+px;g=31+id*5+py;b=29+id*7+px+py;color={r,g,b};end
 endfunction
 media_prefetch_control #(.INTERVAL_CYCLES(257),.CONTROLLED_AUTOPLAY(1),.MAX_IMAGES(CAP)) control(
  .clk(clk),.rst_n(rst_n),.card_ready(!manual),.auto_enable(auto_enable),
  .load_ready(load_ready),.scan_done(scan_done),.image_done(image_done),.error(error),
  .image_count(image_count),.next_pulse(next_pulse),.prev_pulse(prev_pulse),.pause(pause),
  .front_valid(front_valid),.display_index(display_index),.frame_prepared(frame_prepared),
  .frame_committed(frame_committed),.transition_ready(transition_active),.scan_start(control_scan),
  .load_start(control_load),.image_index(control_index),.commit_enable(control_commit),
  .discard_cached(control_discard),.transition_active(transition_active));
 fat32_frame_loader #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.TIMEOUT_CYCLES(50000),
  .CONTROLLED_SWAP(1),.FIND_WAV(1),.MAX_IMAGES(CAP)) loader(
  .clk(clk),.rst_n(rst_n),.scan_start(scan_start),.load_start(load_start),.image_index(image_index),
  .load_ready(load_ready),.catalog_ready(catalog_ready),.scan_done(scan_done),
  .image_done(image_done),.error(error),.image_count(image_count),
  .rd_start(image_start),.rd_lba(image_lba),.rd_ready(image_ready),.rd_done(rd_done),
  .rd_error(rd_error),.rd_addr(rd_addr),.rd_data(rd_data),.rd_valid(rd_valid),
  .wr_valid(wr_valid),.wr_addr(wr_addr),.wr_data(wr_data),.wr_ready(wr_ready),.wr_drained(drain==0),
  .swap_window(cycles%17==0),.front_valid(front_valid),.front_bank(front_bank),
  .frame_committed(frame_committed),.frame_rejected(frame_rejected),.swap_pending(frame_prepared),
  .commit_enable(commit_enable),.discard_cached(discard_cached),
  .read_valid(1'b0),.read_addr(32'd0),.rgb_ready(1'b1),.mem_read_ready(1'b0),
  .mem_response_valid(1'b0),.mem_response_data(32'd0));
 sd_sector_arbiter arb(.clk(clk),.rst_n(rst_n),.audio_urgent(cycles%8==0),
  .card_ready(card_ready),.card_done(card_done),.card_error(card_error),.card_addr(card_addr),
  .card_data(card_data),.card_valid(card_valid),.card_start(card_start),.card_lba(card_lba),
  .image_start(image_start),.image_lba(image_lba),.image_ready(image_ready),
  .image_done(rd_done),.image_error(rd_error),.image_addr(rd_addr),.image_data(rd_data),.image_valid(rd_valid),
  .audio_start(audio_start),.audio_lba(32'd900000),.audio_ready(audio_ready),
  .audio_done(audio_done),.audio_error(audio_error),.audio_addr(audio_addr),
  .audio_data(audio_data),.audio_valid(audio_valid));
 always @(posedge clk)begin
  cycles<=cycles+1;
  if(!rst_n)begin
   display_index<=0;loading_index<=0;audio_start<=0;audio_busy<=0;
   audio_bytes<=0;audio_cooldown<=0;drain<=0;frame_writes<=0;
  end else begin
   audio_start<=0;
   if(audio_cooldown>0)audio_cooldown<=audio_cooldown-1;
   if(audio_ready&&!audio_busy&&audio_cooldown==0)begin audio_start<=1;audio_busy<=1;end
   if(audio_done)begin
    if(audio_error||audio_bytes!=512)$fatal(1,"audio sector damaged/interleaved");
    audio_busy<=0;audio_sectors<=audio_sectors+1;audio_bytes<=0;audio_cooldown<=1023;
   end
   if(audio_valid)begin
    if(audio_addr!==audio_bytes || audio_data!==((audio_bytes^165)&255))$fatal(1,"audio byte ownership");
    audio_bytes<=audio_bytes+1;
   end
   if(drain>0)drain<=drain-1;
   if(load_start&&load_ready&&image_index<image_count)begin
    loading_index<=image_index;loads<=loads+1;frame_writes<=0;
    for(integer j=0;j<N;j=j+1)seen[j]=0;
   end
   if(image_done&&error&&manual)invalid_events<=invalid_events+1;
   if(wr_valid&&wr_ready)begin
    if(wr_addr>=2*N || (front_valid&&wr_addr/N==front_bank) || seen[wr_addr%N])
     $fatal(1,"duplicate/out-of-bounds/visible-bank write");
    seen[wr_addr%N]=1;
    if(wr_data!=={8'd0,color((wr_addr%N)%W,(wr_addr%N)/W,loading_index)})
     $fatal(1,"wrong catalogue slot/pixel slot=%0d addr=%0d value=%h",loading_index,wr_addr,wr_data);
    memory[wr_addr]<=wr_data;writes<=writes+1;frame_writes<=frame_writes+1;drain<=7;
   end
   if(frame_committed)begin
    if(drain!=0||frame_writes!=N)$fatal(1,"partial/undrained frame commit");
    display_index<=loading_index;commits<=commits+1;
   end
   if(frame_rejected)rejects<=rejects+1;
  end
 end
 initial forever begin
  @(posedge clk);
  if(rst_n&&card_start)begin
   selected_lba=card_lba;#1;card_ready=0;requests=requests+1;bank=-1;
   if(selected_lba!=900000)image_requests=image_requests+1;
   case(selected_lba)
    0:bank=0;2048:bank=1;2080:bank=2;
    2680:bank=3;2681:bank=4;2682:bank=5;900000:bank=-2;
    default:begin
     if(selected_lba>=2688 && selected_lba<=2752 && (selected_lba-2688)%2==0)
      bank=6+(selected_lba-2688)/2;
     else $fatal(1,"unexpected sector LBA=%0d",selected_lba);
    end
   endcase
   repeat(3)@(negedge clk);
   for(k=0;k<512;k=k+1)begin
    card_valid=1;card_addr=k;
    card_data=(bank==-2)?(k^165):fixture[bank*512+k];
    if(bad_slot>=0 && bank==6+bad_slot && k==0)card_data=0;
    @(negedge clk);
   end
   card_valid=0;card_error=(crc_slot>=0 && bank==6+crc_slot);
   if(card_error)crc_errors=crc_errors+1;
   card_done=1;@(negedge clk);card_done=0;card_error=0;card_ready=1;
  end
 end
 task tick(input integer n);begin repeat(n)@(negedge clk);end endtask
 task press(input bit back);begin tick(1);next_pulse=!back;prev_pulse=back;tick(1);next_pulse=0;prev_pulse=0;end endtask
 task front(input integer id);begin
  if(!front_valid||display_index!=id)$fatal(1,"wrong committed identity expected=%0d actual=%0d",id,display_index);
  for(integer j=0;j<N;j=j+1)
   if(memory[front_bank*N+j]!=={8'd0,color(j%W,j/W,id)})$fatal(1,"visible frame changed outside commit");
 end endtask
 task shown(input integer id,input integer previous_commits);begin
  wait(commits>previous_commits);tick(1);front(id);
 end endtask
 initial begin
  if($size(loader.u_image.ram_catalog.file_metadata)!=CAP)
   $fatal(1,"metadata RAM depth does not match catalogue capacity");
  $readmemh("fixture.hex",fixture);
  tick(4);rst_n=1;tick(1);manual_scan=1;tick(1);manual_scan=0;
  wait(scan_done);tick(1);
  if(error||!catalog_ready||image_count!=EXPECTED||!loader.u_image.wav_found)
   $fatal(1,"catalog count/wav expected=%0d got=%0d error=%b",EXPECTED,image_count,error);
  if(EXPECTED<32)begin
   before_requests=image_requests;manual_load=1;tick(1);manual_load=0;tick(5);
   if(invalid_events!=1||writes!=0||front_valid||image_requests!=before_requests)
    $fatal(1,"invalid index consumed stale RAM metadata");
  end
  if(EXPECTED==0)begin
   $display("PASS gallery COUNT=0: empty catalogue, WAV found, invalid index rejected without frame/file reads");$finish;
  end
  manual=0;shown(0,0);
  for(goal=1;goal<EXPECTED;goal=goal+1)begin before_commit=commits;press(0);shown(goal,before_commit);end
  before_commit=commits;press(0);
  if(EXPECTED>1)shown(0,before_commit);else tick(100);
  before_commit=commits;press(1);
  if(EXPECTED>1)shown(EXPECTED-1,before_commit);else tick(100);
  if(EXPECTED>1)begin
   before_commit=commits;auto_enable=1;pause=0;shown(0,before_commit);auto_enable=0;pause=1;
  end
  if(EXPECTED==CAP)begin
   // A second scan retains unreset RAM physically; only newly validated
   // metadata may be used. Exercise damaged files above the old 2-bit range.
   rst_n=0;bad_slot=17;tick(5);rst_n=1;before_commit=commits;shown(0,before_commit);
   for(goal=1;goal<=16;goal=goal+1)begin before_commit=commits;press(0);shown(goal,before_commit);end
   wait(rejects>=1);before_commit=commits;press(0);tick(1000);
   if(commits!=before_commit)$fatal(1,"bad BMP replaced good front");front(16);
   press(0);shown(18,before_commit);crc_slot=19;
   wait(crc_errors==3);wait(rejects>=2);before_commit=commits;press(0);tick(1000);
   if(commits!=before_commit)$fatal(1,"CRC-failed frame was committed");front(18);
   press(0);shown(20,before_commit);
  end
  if(audio_sectors<4||writes<EXPECTED*N)$fatal(1,"insufficient image/audio coverage");
  $display("PASS gallery COUNT=%0d cap=%0d commits=%0d loads=%0d writes=%0d rejects=%0d CRC_retries=%0d audio_sectors=%0d requests=%0d cycles=%0d; metadata/all-slots/wrap/reverse/autoplay",COUNT,EXPECTED,commits,loads,writes,rejects,crc_errors,audio_sectors,requests,cycles);$finish;
 end
 initial begin #30000000;$fatal(1,"gallery timeout COUNT=%0d state=%0d index=%0d shown=%0d commits=%0d error=%b",COUNT,control.state,image_index,display_index,commits,error);end
endmodule
