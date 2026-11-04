`timescale 1ns/1ps
module tb_gallery_interval_constants;
 reg clk=0,rst_n=0;
 sd_media_player #(.INTRO_ANIMATION(1)) gallery(.clk(clk),.pix_clk(clk),.rst_n(rst_n));
 sd_media_player #(.INTRO_ANIMATION(0)) legacy(.clk(clk),.pix_clk(clk),.rst_n(rst_n));
 sd_media_player #(.INTRO_ANIMATION(1),.INTERVAL_CYCLES(1)) tiny(.clk(clk),.pix_clk(clk),.rst_n(rst_n));
 initial begin
  #1;
  if(gallery.u_control.AUTOPLAY_CYCLES!=192307692||gallery.u_control.INTERVAL_CYCLES!=250000000)
   $fatal(1,"production5second dwell scaling overflowed or changed retries");
  if(legacy.u_control.AUTOPLAY_CYCLES!=250000000||legacy.u_control.INTERVAL_CYCLES!=250000000)
   $fatal(1,"legacy timing changed");
  if(tiny.u_control.AUTOPLAY_CYCLES!=1)$fatal(1,"small gallery interval became zero");
  $display("PASS actual player constants:gallery192307692cycles,legacy/retry250000000cycles,onecycle lower bound");$finish;
 end
endmodule

module fat32_wav_player #(parameter CONTROLLED_STOP=0)(
 input wire clk,rst_n,volume_ready,file_found,play_enable,
 input wire [31:0] first_cluster,file_size,fat_lba,data_lba,cluster_count,
 input wire [7:0] sectors_per_cluster,
 input wire rd_ready,rd_done,rd_error,input wire [8:0] rd_addr,input wire [7:0] rd_data,input wire rd_valid,
 output wire rd_start,output wire [31:0] rd_lba,output wire sample_valid,input wire sample_ready,
 output wire [47:0] sample_data,output wire playing,error,idle);
 assign rd_start=0;assign rd_lba=0;assign sample_valid=0;assign sample_data=0;assign playing=0;assign error=0;assign idle=1;
endmodule
