`timescale 1ns/1ps
// Real buffer manager, delayed loader and write draining. The scoreboards use
// accepted memory words and committed identities, not controller state names.
module tb_home_album;
 parameter integer COUNT=32,INTERVAL=257;
 reg clk=0,rst_n=0,card_ready=0,scan_done=0,error=0,pause=1,next_pulse=0,prev_pulse=0;
 reg [5:0] image_count=COUNT;
 reg album_request=0,album_enable=1;reg [4:0] album_first=0;reg [5:0] album_limit=32;wire album_ready,album_error;
 wire scan_start,load_start,commit_enable,discard_cached,transition_active;
 wire transition_manual,transition_backward;
 wire [4:0] image_index;
 reg [4:0] display_index=0,loaded_index=0;
 wire front_valid,front_bank,frame_committed,frame_rejected,frame_prepared,frame_ready;
 reg busy=0,frame_start=0,image_done=0,pixel_valid=0;
 reg [31:0] pixel_addr=0;
 wire pixel_ready,wr_valid;
 wire [31:0] wr_addr,wr_data;
 integer cycles=0,load_count=0,commits=0,discards=0,rejects=0,writes=0,drain=0;
 integer loader_state=0,delay_count=0,fade_ticks=0,fail_slot=-1,failed_loads=0;
 reg fail_load=0,hold_fade=0;
 reg previous_commit_enable=0;
 wire transition_ready=transition_active && !hold_fade && fade_ticks>=3;
 wire load_ready=frame_ready&&!busy;
 wire wr_ready=(cycles%3!=0);
 wire [23:0] pixel_rgb={19'd0,loaded_index}+{pixel_addr[21:0],2'b00};
 reg [31:0] memory[0:11];
 reg [4:0] committed_log[0:127];
 reg [4:0] last_index=0;
 integer i,before_load,before_commit,start_cycle,latency=0;
 always #5 clk=~clk;
 always @(negedge clk)if($test$plusargs("TRACE") &&
  (load_start||next_pulse||prev_pulse||frame_committed||frame_prepared))
  $display("TRACE cycle=%0d state=%0d cursor=%0d fg=%b pending=%b prev=%b next=%b index=%0d shown=%0d ready=%b hold=%b commits=%0d",cycles,control.state,control.cursor,control.foreground,control.pending_request,prev_pulse,next_pulse,image_index,display_index,transition_ready,hold_fade,commits);
 media_prefetch_control #(.INTERVAL_CYCLES(INTERVAL),.CONTROLLED_AUTOPLAY(1),.ALBUMS(1),.MAX_IMAGES(32)) control(.prefetch_enable(1'b1),.preparing(),.prepare_progress_valid(),.auto_enable(1'b1),.*);
 frame_buffer_manager #(.FRAME_PIXELS(6),.ALLOW_DISCARD(1)) frame(
  .clk(clk),.rst_n(rst_n),.frame_start(frame_start),.frame_done(image_done),.frame_error(error),
  .frame_ready(frame_ready),.pixel_valid(pixel_valid),.pixel_addr(pixel_addr),
  .pixel_rgb(pixel_rgb),.pixel_ready(pixel_ready),
  .wr_valid(wr_valid),.wr_addr(wr_addr),.wr_data(wr_data),.wr_ready(wr_ready),.wr_drained(drain==0),
  .swap_window((cycles%17==0)&&commit_enable),.front_valid(front_valid),.front_bank(front_bank),
  .frame_committed(frame_committed),.frame_rejected(frame_rejected),.swap_pending(frame_prepared),
  .discard_frame(discard_cached),.read_valid(1'b0),.read_addr(32'd0),.rgb_ready(1'b1),
  .mem_read_ready(1'b0),.mem_response_valid(1'b0),.mem_response_data(32'd0));
 always @(posedge clk)begin
  cycles<=cycles+1;
  previous_commit_enable<=commit_enable;
  if(!rst_n)begin
   busy<=0;frame_start<=0;image_done<=0;pixel_valid<=0;error<=0;
   loader_state<=0;pixel_addr<=0;drain<=0;display_index<=0;fade_ticks<=0;
  end else begin
   frame_start<=0;image_done<=0;
   if(transition_active)fade_ticks<=fade_ticks+1;else fade_ticks<=0;
   if(drain>0)drain<=drain-1;
   if(wr_valid&&wr_ready)begin
    if(front_valid && wr_addr/6==front_bank)$fatal(1,"write overwrote visible bank");
    memory[wr_addr]<=wr_data;writes<=writes+1;drain<=9;
   end
   if(load_start)begin
    if(!load_ready || image_index>=COUNT)$fatal(1,"bad/overlapping load");
    busy<=1;frame_start<=1;loaded_index<=image_index;fail_load<=image_index==fail_slot;
    load_count<=load_count+1;delay_count<=25;loader_state<=1;pixel_addr<=0;
   end
   case(loader_state)
    1:if(delay_count==0)begin pixel_valid<=1;loader_state<=2;end else delay_count<=delay_count-1;
    2:if(pixel_valid&&pixel_ready)begin
     if(pixel_addr==5)begin pixel_valid<=0;loader_state<=3;end else pixel_addr<=pixel_addr+1;
    end
    3:begin image_done<=1;error<=fail_load;busy<=0;loader_state<=0;if(fail_load)failed_loads<=failed_loads+1;end
   endcase
   if(frame_committed)begin
    if(!previous_commit_enable || drain!=0)$fatal(1,"commit without authorization/drain");
    display_index<=loaded_index;committed_log[commits]<=loaded_index;commits<=commits+1;
    for(integer k=0;k<6;k=k+1)
     if(memory[front_bank*6+k]!==loaded_index+k*4)$fatal(1,"incomplete/wrong committed memory");
   end
   if(frame_rejected)rejects<=rejects+1;
   if(discard_cached&&frame_prepared)discards<=discards+1;
   if(transition_active && !frame_prepared && !frame_committed)$fatal(1,"fade before prepared");
  end
 end
 task tick(input integer n);begin repeat(n)@(negedge clk);#1;end endtask
 task press(input bit back);begin @(negedge clk);#1;prev_pulse=back;next_pulse=!back;tick(1);prev_pulse=0;next_pulse=0;end endtask
 task committed(input integer expected,input integer old_count);begin
  wait(commits>old_count);tick(1);
  if(display_index!==expected || committed_log[old_count]!==expected)
   $fatal(1,"wrong commit expected=%0d got=%0d",expected,display_index);
 end endtask
 task select_album(input integer first,lim);begin
  @(negedge clk);#1;album_first=first;album_limit=lim;album_request=1;tick(1);album_request=0;tick(1);
 end endtask
 initial begin
  tick(3);rst_n=1;card_ready=1;wait(scan_start);tick(1);scan_done=1;tick(1);scan_done=0;committed(0,0);
  wait(frame_prepared);before_commit=commits;select_album(6,12);
  wait(album_ready);tick(2);if(album_error||display_index!=6||commits!=before_commit+1)$fatal(1,"cached album request");
  before_commit=commits;press(1);committed(11,before_commit);
  before_commit=commits;press(0);committed(6,before_commit);
  // Every group wraps in its own inclusive/exclusive interval.
  for(integer group=0;group<5;group=group+1)begin
   select_album(group*6,(group==4)?32:(group+1)*6);wait(album_ready);tick(2);
   if(display_index!=group*6)$fatal(1,"album first picture");
   before_commit=commits;press(1);committed((group==4)?31:(group+1)*6-1,before_commit);
   before_commit=commits;press(0);committed(group*6,before_commit);
  end
  // A later selection supersedes an old foreground load only after its
  // complete transaction and writes have drained. Old ready cannot publish.
  select_album(6,12);wait(load_start);select_album(18,24);
  wait(album_ready);tick(2);if(display_index!=18)$fatal(1,"obsolete album marked ready");
  fail_slot=12;select_album(12,18);wait(album_error);tick(2);
  if(album_ready||display_index!=18)$fatal(1,"failed album overwrote good front");fail_slot=-1;
  select_album(24,32);wait(album_ready);tick(2);image_count=27;
  select_album(24,32);wait(album_ready);tick(2);before_commit=commits;press(1);committed(26,before_commit);
  before_load=load_count;select_album(28,32);tick(2);
  if(!album_error||album_ready)$fatal(1,"empty range not rejected");
  select_album(20,20);tick(2);if(!album_error)$fatal(1,"reversed/empty range");
  // Demo mode restores all-catalogue wrapping without resetting the loader.
  album_enable=0;tick(2);before_commit=commits;press(0);committed(0,before_commit);
  if(album_ready||album_error)$fatal(1,"demo retained album acknowledgements");
  $display("PASS home albums: five groups, wrap/clipping, cached/in-flight changes, failed/empty ranges, demo restore; loads=%0d commits=%0d discards=%0d writes=%0d",load_count,commits,discards,writes);$finish;
 end
 initial begin #2000000;$fatal(1,"cache control timeout count=%0d state=%0d index=%0d shown=%0d commits=%0d",COUNT,control.state,image_index,display_index,commits);end
endmodule
