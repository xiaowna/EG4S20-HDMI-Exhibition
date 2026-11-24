`timescale 1ns/1ps
// Fixed mounted catalog isolates the real player/WAV/arbiter transaction fence.
module sd_subsystem #(parameter CLK_HZ=50000000)(
 input wire clk,rst_n,sd_miso,read_start,input wire [31:0] read_lba,
 output wire sd_sck,sd_mosi,sd_cs,ready,error,read_request_ready,read_done,read_error,
 output wire [8:0] data_addr,output wire [7:0] data_out,output wire data_valid);
 reg [15:0] stall_delay=2000;
 wire card_busy;
 assign sd_sck=0;assign sd_mosi=1;assign sd_cs=1;assign ready=rst_n;assign error=0;
 mode_wav_sector_model backend(.clk(clk),.rst_n(rst_n),.rd_start(read_start),.rd_lba(read_lba),
  .extra_delay(stall_delay),.rd_ready(read_request_ready),.rd_done(read_done),.rd_error(read_error),
  .rd_addr(data_addr),.rd_data(data_out),.rd_valid(data_valid),.busy(card_busy));
endmodule
// Integrated sector-to-video streaming pipeline with internal SDRAM.
module media_stream_pipeline #(parameter integer CLK_HZ=50000000, FRAME_WIDTH=640,FRAME_HEIGHT=480,
 parameter H_FP=16,H_SYNC=96,H_BP=48,V_FP=10,V_SYNC=2,V_BP=33,FIFO_ADDR_BITS=8,
 parameter integer TIMEOUT_CYCLES=50_000_000,FIND_WAV=0,CONTROLLED_SWAP=0,MAX_IMAGES=4,
 parameter integer INDEX_BITS=(MAX_IMAGES>1)?$clog2(MAX_IMAGES):1,
 parameter integer COUNT_BITS=(MAX_IMAGES>0)?$clog2(MAX_IMAGES+1):1,parameter SLIDE_TRANSITIONS=0,parameter MAX_WAVS=1,parameter INTRO_ANIMATION=0,ABORTABLE=0,CACHE_FRAMES=0)(
 input wire clk,pix_clk,rst_n,scan_start,load_start,input wire [INDEX_BITS-1:0] image_index,
 output wire load_ready,busy,catalog_ready,scan_done,image_done,error,
 output wire [COUNT_BITS-1:0] image_count,
 output wire [31:0] volume_root_lba,volume_root_cluster,
 volume_fat_lba,volume_data_lba,volume_cluster_count,
 output wire [7:0] volume_sectors_per_cluster,
 output wire wav_found,output wire [31:0] wav_first_cluster,wav_size,
 input wire rd_ready,rd_done,rd_error,input wire [8:0] rd_addr,input wire [7:0] rd_data,input wire rd_valid,
 output wire rd_start,output wire [31:0] rd_lba,
 output wire front_valid,front_bank,frame_committed,frame_rejected,
 output wire de,hsync,vsync,output wire [23:0] rgb,output wire frame_underflow,video_started,
 output wire sdram_ready,memory_fault,prefetch_error,
 input wire commit_enable,discard_cached,abort_load,output wire frame_prepared,
 input wire slide_request,slide_right,output wire slide_ready,
 input wire [1:0] wav_index,output wire [2:0] wav_count,output wire [6:0] prepare_pixels,
 input wire intro_enable,intro_pause,input wire [4:0] intro_index,output wire intro_animating,output wire [24:0] folder_info,input wire intro_instant,
 input wire retain_album,front_matches,input wire [INDEX_BITS-1:0] retain_first);
 assign folder_info=0;
 assign intro_animating=0;
 assign wav_count=1;assign prepare_pixels=0;

 assign load_ready=1;assign busy=0;assign catalog_ready=rst_n;assign scan_done=scan_start;
 assign image_done=0;assign error=0;assign image_count=0;
 assign volume_root_lba=0;assign volume_root_cluster=2;assign volume_fat_lba=20;
 assign volume_data_lba=100;assign volume_cluster_count=100;assign volume_sectors_per_cluster=1;
 assign wav_found=1;assign wav_first_cluster=2;assign wav_size=684;
 assign rd_start=0;assign rd_lba=0;assign front_valid=0;assign front_bank=0;
 assign frame_committed=0;assign frame_rejected=0;assign frame_prepared=0;
 assign slide_ready=0;
 assign de=0;assign hsync=1;assign vsync=1;assign rgb=0;
 assign frame_underflow=0;assign video_started=1;assign sdram_ready=1;
 assign memory_fault=0;assign prefetch_error=0;
endmodule

module tb_mode_player_fence;
 reg clk=0,rst_n=1,wav_enable=1;
 wire wav_idle,wav_valid;wire [47:0] wav_data;
 integer count=0,timeout=0;
 always #5 clk=~clk;
 sd_media_player #(.MODE_CONTROL(1)) dut(.clk(clk),.pix_clk(clk),.rst_n(rst_n),.sd_miso(1'b1),
  .next_pulse(1'b0),.prev_pulse(1'b0),.pause(1'b0),.audio_urgent(1'b1),.wav_ready(1'b1),
  .transition_ready(1'b1),.auto_enable(1'b0),.wav_enable(wav_enable),.wav_idle(wav_idle),
  .wav_valid(wav_valid),.wav_data(wav_data));
 defparam dut.u_wav.TIMEOUT_CYCLES=1000;
 task tick;begin @(negedge clk);#1;end endtask
 initial begin
  #1;rst_n=0;tick;rst_n=1;
  wait(dut.u_wav.reader.busy);wait(!dut.u_wav.reader.busy);#1;
  if(wav_idle || !dut.u_card.card_busy)$fatal(1,"logical reader timeout released in-flight card owner");
  wav_enable=0;
  while(dut.u_card.card_busy)begin tick;if(wav_idle)$fatal(1,"WAV reported idle before complete sector/CRC");end
  timeout=0;while(!wav_idle)begin tick;timeout=timeout+1;if(timeout>10)$fatal(1,"card owner fence never retired");end
  dut.u_card.stall_delay=3;wav_enable=1;timeout=0;
  while(count<8)begin
   @(posedge clk);#1;
   if(wav_valid)begin
    if(wav_data[47:24]!==((24'h1000+count)<<8))$fatal(1,"post-timeout source did not restart");
    count=count+1;
   end
   timeout=timeout+1;if(timeout>4000)$fatal(1,"WAV did not recover after card drained");
  end
  $display("PASS mode_player_fence: real sd_media_player and arbiter retain ownership after file timeout, drain all 512 bytes, then restart WAV at sample zero");$finish;
 end
 initial begin #1000000;$fatal(1,"player transaction fence timeout");end
endmodule
