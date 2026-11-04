`timescale 1ns/1ps
// Full VGA raster and real SDRAM controller/model. The mock loader publishes
// index one clock after its safe bank commit, matching sd_media_player.
module tb_intro_raster #(parameter SMOKE=0);
 localparam N=640*480;
 reg sys_clk=0,pix_clk=0,rst_n=0;
 always #10 sys_clk=~sys_clk;
 always #20 pix_clk=~pix_clk;
 reg front_valid=0,front_bank=0,intro_enable=1,intro_pause=1;
 reg [4:0] intro_index=0,target_index=0;
 reg pending_swap=0,commit_pulse=0,write_enable=0;
 reg [18:0] write_offset=0;
 wire swap_window,burst_valid,burst_ready,burst_data_valid,burst_last,burst_error;
 wire [31:0] burst_addr,burst_data;
 wire [8:0] burst_words;
 wire de,hsync,vsync,frame_underflow,fetch_busy,video_started,prefetch_error,intro_animating,slide_ready;
 wire [23:0] rgb;
 wire wr_ready,wr_drained,memory_fault,init_done;
 wire [31:0] wr_addr=(front_bank?0:N)+write_offset;
 wire [31:0] wr_data={8'd0,color(wr_addr)};
 integer writes=0,commands=0,swaps=0,checked_pixels=0,good_frames=0;
 integer retired_intro_before_fifo=0,normal0=0,normal1=0;
 integer phase_frames[0:11];
 integer transaction_serial=0,transaction_bank=0,transaction_topic=0,transaction_phase=0;
 reg transaction_intro=0;
 integer frame_bank=0,frame_topic=0,frame_phase=0,position=0,frame_serial=0;
 reg frame_intro=0,checking=0;
 reg [23:0] golden[0:N-1];
 string golden_path;
 integer topic_number,previous_count,phase_slot,goal;
 function automatic [23:0] color(input integer address);
  color=(address*37)^(address<<7)^24'h5a39c7;
 endfunction
 eg4s20_stream_memory memory(.clk(sys_clk),.rst_n(rst_n),.wr_valid(write_enable),
  .wr_addr(wr_addr),.wr_data(wr_data),.wr_ready(wr_ready),.wr_drained(wr_drained),
  .burst_valid(burst_valid),.burst_addr(burst_addr),.burst_words(burst_words),.burst_ready(burst_ready),
  .burst_data_valid(burst_data_valid),.burst_last(burst_last),.burst_data(burst_data),
  .burst_error(burst_error),.fault(memory_fault),.init_done(init_done));
 frame_stream_display #(.FIFO_ADDR_BITS(8),.SLIDE_TRANSITIONS(1),.INTRO_ANIMATION(1)) display(
  .rst_n(rst_n),.sys_clk(sys_clk),.pix_clk(pix_clk),.front_valid(front_valid),.front_bank(front_bank),
  .swap_window(swap_window),.burst_valid(burst_valid),.burst_addr(burst_addr),.burst_words(burst_words),
  .burst_ready(burst_ready),.burst_data_valid(burst_data_valid),.burst_last(burst_last),
  .burst_error(burst_error),.burst_data(burst_data),.prefetch_error(prefetch_error),
  .de(de),.hsync(hsync),.vsync(vsync),.rgb(rgb),.frame_underflow(frame_underflow),
  .fetch_busy(fetch_busy),.video_started(video_started),.slide_request(1'b0),.slide_right(1'b0),
  .slide_prepared(1'b0),.slide_ready(slide_ready),.intro_enable(intro_enable),
  .intro_pause(intro_pause),.intro_index(intro_index),.intro_animating(intro_animating));
 always @(posedge sys_clk)if(rst_n)begin
  commit_pulse<=0;
  if(init_done)front_valid<=1;
  if(commit_pulse)intro_index<=target_index;
  if(swap_window&&pending_swap)begin
   if(!wr_drained)$fatal(1,"mock loader committed before writes drained");
   front_bank<=!front_bank;commit_pulse<=1;pending_swap<=0;swaps=swaps+1;
  end
  if(write_enable&&wr_ready)begin
   if(wr_addr/N==front_bank)$fatal(1,"background writer owns front bank");
   writes=writes+1;write_offset<=(write_offset==N-1)?0:write_offset+1'b1;
  end
  if(memory_fault||prefetch_error||frame_underflow)
   $fatal(1,"raster/memory failure phase=%0d topic=%0d pixel=%0d state=%0d fifoempty=%b",transaction_phase,transaction_topic,position,display.sys_state,display.u_prefetch.fifo_empty);
  if(display.pre_start)begin
   transaction_serial=transaction_serial+1;transaction_bank=front_bank;
   transaction_intro=display.intro_mode_q;transaction_topic=display.intro_topic_q;
   transaction_phase=display.intro_phase_q;
   if(transaction_intro!==(intro_enable&&(intro_index==5||intro_index==11||intro_index==17||intro_index==23)))
    $fatal(1,"committed index was sampled before its delayed publication");
   if(transaction_intro&&transaction_topic!==(intro_index/6))$fatal(1,"wrong committed topic");
  end
  if(burst_valid&&burst_ready)begin
   if(burst_addr/N!=transaction_bank||(burst_addr+burst_words-1)/N!=transaction_bank)
    $fatal(1,"display fetched writable/back bank");
   commands=commands+1;
  end
  if(display.u_prefetch.intro_done&&!display.u_prefetch.fifo_empty)
   retired_intro_before_fifo=retired_intro_before_fifo+1;
  if(swap_window)begin
   if(fetch_busy||!display.u_prefetch.fifo_empty||display.u_prefetch.intro_busy||
      display.u_prefetch.introduction.compositor.request_valid||
      (memory.inflight&&!memory.writing)||burst_data_valid||burst_valid)
    $fatal(1,"unsafe swap window before producer/FIFO/read retirement");
  end
 end
 always @(posedge pix_clk)begin
  if(rst_n&&display.arm)begin
   if(checking)$fatal(1,"new raster armed over an incomplete raster");
   checking=1;position=0;frame_bank=transaction_bank;frame_intro=transaction_intro;
   frame_topic=transaction_topic;frame_phase=transaction_phase;frame_serial=transaction_serial;
   if(frame_intro)begin
    case(frame_phase)0:phase_slot=0;49:phase_slot=1;63:phase_slot=2;
     default:$fatal(1,"unexpected non-test phase=%0d",frame_phase);endcase
    golden_path=$sformatf("golden_%0d_%0d_%0d.hex",frame_topic,frame_phase,frame_bank);
   end else golden_path=$sformatf("normal_%0d_%0d.hex",frame_phase,frame_bank);
   $readmemh(golden_path,golden);
  end
  #1;
  if(rst_n&&de&&checking)begin
   if(frame_serial!=transaction_serial)$fatal(1,"fetch transaction changed during active raster");
   if(rgb!==(golden[position]))
    $fatal(1,"full raster mismatch topic=%0d phase=%0d bank=%0d pixel=%0d x=%0d y=%0d got=%h expected=%h",frame_topic,frame_phase,frame_bank,position,position%640,position/640,rgb,golden[position]);
   position=position+1;checked_pixels=checked_pixels+1;
   if(position==N)begin
    checking=0;good_frames=good_frames+1;
    if(frame_intro)phase_frames[frame_topic*3+phase_slot]=phase_frames[frame_topic*3+phase_slot]+1;
    else if(frame_bank)normal1=normal1+1;else normal0=normal0+1;
    $display("PASS raster frame=%0d intro=%b topic=%0d phase=%0d bank=%0d writes=%0d refreshes=%0d",good_frames,frame_intro,frame_topic,frame_phase,frame_bank,writes,memory.u_memory.run_refreshes);
   end
  end
 end
 task commit_page(input integer index_value);
  begin
   @(negedge sys_clk);write_enable=0;wait(wr_drained);
   @(negedge sys_clk);target_index=index_value;pending_swap=1;
   wait(!pending_swap);wait(!commit_pulse);
   @(negedge sys_clk);write_enable=1;
  end
 endtask
 task choose_phase(input integer value);
  begin
   @(negedge sys_clk);while(!swap_window)@(negedge sys_clk);
   case(value)9:force display.intro_phase_q=6'd9;18:force display.intro_phase_q=6'd18;49:force display.intro_phase_q=6'd49;63:force display.intro_phase_q=6'd63;endcase
  end
 endtask
 initial begin
  for(integer i=0;i<12;i=i+1)phase_frames[i]=0;
  for(integer i=0;i<2*N;i=i+1)memory.u_memory.memory[i]={8'd0,color(i)};
  repeat(4)@(negedge pix_clk);rst_n=1;wait(init_done);@(negedge sys_clk);write_enable=1;
  wait(normal0>=1);
  for(topic_number=0;topic_number<(SMOKE?1:4);topic_number=topic_number+1)begin
   previous_count=phase_frames[topic_number*3];
   release display.intro_phase_q;
   commit_page(topic_number*6+5);
   wait(phase_frames[topic_number*3]>previous_count);
   if(!SMOKE)begin
    choose_phase(49);wait(phase_frames[topic_number*3+1]>=1);
    choose_phase(63);wait(phase_frames[topic_number*3+2]>=1);
   end
  end
  if(!SMOKE)begin
   release display.intro_phase_q;
   goal=normal0+normal1+1;commit_page(0);wait(normal0+normal1>=goal);
   choose_phase(9);goal=normal0+normal1+1;wait(normal0+normal1>=goal);
   choose_phase(18);goal=normal0+normal1+1;wait(normal0+normal1>=goal);
   release display.intro_phase_q;
   previous_count=phase_frames[9];commit_page(23);wait(phase_frames[9]>previous_count);
   @(negedge sys_clk);intro_enable=0;goal=normal0+normal1+1;wait(normal0+normal1>=goal);
   previous_count=phase_frames[9];@(negedge sys_clk);intro_enable=1;wait(phase_frames[9]>previous_count);
  end
  if(checked_pixels<2*N||writes==0||memory.u_memory.run_refreshes==0||retired_intro_before_fifo==0)
   $fatal(1,"missing full-raster/arbitration/refresh/retirement coverage");
  $display("PASS intro raster totals frames=%0d pixels=%0d writes=%0d reads=%0d refreshes=%0d safe_commits=%0d producer_before_fifo=%0d; real640x48050/25MHz, front-only reads, delayed committed metadata, normal/intro ownership, forced selected phases only",good_frames,checked_pixels,writes,commands,memory.u_memory.run_refreshes,swaps,retired_intro_before_fifo);
  $finish;
 end
 initial begin #1500000000;$fatal(1,"full intro raster timeout frames=%0d",good_frames);end
endmodule
