`timescale 1ns/1ps
module wav_pcm_decoder(
 input wire clk,rst_n,start,input wire [31:0] file_size,
 input wire byte_valid,input wire [7:0] byte_data,
 output wire byte_ready,sample_valid,input wire sample_ready,
 output wire [47:0] sample_data,output wire playing,error,data_done);
 wire old_ready,old_valid,old_playing,old_error,old_done;
 wire [47:0] old_data;integer checks=0;
 wav_pcm_decoder_candidate modified(.*);
 wav_pcm_decoder_o18 reference(.clk(clk),.rst_n(rst_n),.start(start),.file_size(file_size),
  .byte_valid(byte_valid),.byte_data(byte_data),.sample_ready(sample_ready),
  .byte_ready(old_ready),.sample_valid(old_valid),.sample_data(old_data),
  .playing(old_playing),.error(old_error),.data_done(old_done));
 always @(posedge clk)begin
  #1;
  if({byte_ready,sample_valid,sample_data,playing,error,data_done}!==
     {old_ready,old_valid,old_data,old_playing,old_error,old_done})
   $fatal(1,"WAV public-port cycle mismatch cycle=%0d",checks);
  checks=checks+1;
 end
 final $display("PASS WAV public-port equivalence: %0d cycles, 53 bits",checks);
endmodule
