`timescale 1ns/1ps
// WAV may fill the FIFO during image loading, but HDMI must stay silent until
// the display has actually armed its first raster. No-WAV mode keeps the tone.
module tb_av_first_frame;
 reg sys=0,pix=0,rst_n=0,video_started=0,catalog_ready=0,wav_found=0;
 reg wav_playing=0,wav_valid=0;
 reg [47:0] wav_data=0;
 always #10 sys=~sys;
 always #20 pix=~pix;
 reg [9:0] x=0,y=0;
 wire de=x<640&&y<480;
 wire hs=!(x>=656&&x<752);
 wire vs=!(y>=490&&y<492);
 always @(posedge pix)
  if(!rst_n)begin x<=0;y<=0;end
  else if(x==799)begin x<=0;y<=y==524?0:y+1'b1;end
  else x<=x+1'b1;
 wire wav_ready,audio_fault,audio_urgent;
 wire [9:0] red,green,blue;
 hdmi_av_output dut(.brightness(9'sd0),.gain_q8(9'd256),.loading(1'b0),.fade_enabled(1'b0),.wave_enabled(1'b0),.audio_only(1'b0),.image_valid(1'b1),.sys_clk(sys),.pix_clk(pix),.rst_n(rst_n),
  .audio_enable(1'b1),.tone_sel(3'd2),.video_started(video_started),
  .catalog_ready(catalog_ready),.wav_found(wav_found),
  .wav_error(1'b0),.image_count(3'd0),.image_index(2'd0),
  .wav_valid(wav_valid),.wav_playing(wav_playing),.wav_data(wav_data),
  .wav_ready(wav_ready),.de(de),.hsync(hs),.vsync(vs),.rgb(24'h123456),
  .red(red),.green(green),.blue(blue),.audio_fault(audio_fault),
  .audio_urgent(audio_urgent));
 function [47:0] sample_at;
  input integer n;
  begin sample_at={24'h010000|n[23:0],24'h020000|n[23:0]};end
 endfunction
 integer phase=0,writes=0,played=0,silent=0,tone_writes=0,tone_nonzero=0,tone_played=0;
 always @(posedge sys)if(rst_n)begin
  if(phase==0 && dut.fifo.wr_en)
   $fatal(1,"tone queued before WAV catalog was known");
  if(phase==1 && dut.fifo.wr_en)begin
   if(dut.fifo.wr_data!==sample_at(writes))
    $fatal(1,"tone or reordered sample polluted WAV FIFO at %0d",writes);
   writes=writes+1;
  end
  if(phase==3 && dut.fifo.wr_en)begin
   tone_writes=tone_writes+1;
   if(dut.fifo.wr_data!=0)tone_nonzero=tone_nonzero+1;
  end
 end
 always @(posedge pix)if(rst_n)begin
  if(!video_started && dut.fifo_read)
   $fatal(1,"WAV FIFO advanced before the first visible frame");
  if(dut.packets.state==2)begin
   if(!video_started)begin
    if(!dut.packets.capture_zero || dut.packets.packet_sample!==48'd0)
     $fatal(1,"non-silent HDMI audio before the first visible frame");
    silent=silent+1;
   end else if(phase==2 && !dut.packets.capture_zero)begin
    if(dut.packets.packet_sample!==sample_at(played))
     $fatal(1,"WAV order changed at first frame: sample %0d",played);
    played=played+1;
   end else if(phase==3 && !dut.packets.capture_zero && dut.packets.packet_sample!=0)begin
    tone_played=tone_played+1;
   end
  end
  if(audio_fault)$fatal(1,"HDMI audio scheduling or FIFO fault");
 end
 integer i;
 initial begin
  repeat(8)@(negedge pix);rst_n=1;
  repeat(800*4)@(negedge pix);
  if(silent<4)$fatal(1,"no silent HDMI packets before catalog");
  @(negedge sys);catalog_ready=1;wav_found=1;phase=1;
  // A discovered WAV can take time to parse. Do not queue a fallback tone.
  repeat(4000)@(negedge sys);
  if(writes!=0)$fatal(1,"tone queued while WAV header was pending");
  wav_playing=1;
  for(i=0;i<1100;i=i+1)begin
   @(negedge sys);
   if(!wav_ready)$fatal(1,"WAV prebuffer stalled at %0d",i);
   wav_valid=1;wav_data=sample_at(i);
  end
  @(negedge sys);wav_valid=0;
  if(writes!=1100)$fatal(1,"WAV prebuffer incomplete: %0d",writes);
  repeat(800*4)@(negedge pix);
  if(dut.fifo_level<1024 || dut.fifo_read)
   $fatal(1,"WAV prebuffer not retained before video start");
  @(negedge pix);video_started=1;phase=2;
  repeat(800*20)@(negedge pix);
  if(played<20)$fatal(1,"prebuffered WAV did not begin after first frame: %0d",played);
  @(negedge pix);rst_n=0;video_started=0;catalog_ready=0;
  wav_found=0;wav_playing=0;phase=0;
  repeat(8)@(negedge pix);
  rst_n=1;
  @(negedge sys);catalog_ready=1;phase=3;
  // 45 ms exceeds the 2048-sample FIFO fill time at 48 kHz. A slow first BMP
  // must not turn harmless tone backpressure into a latched audio fault.
  repeat(2250000)@(negedge sys);
  if(!dut.fifo_full || tone_writes!=2048 || tone_nonzero<1800)
   $fatal(1,"no-WAV prebuffer did not fill: writes=%0d nonzero=%0d",tone_writes,tone_nonzero);
  video_started=1;
  repeat(800*20)@(negedge pix);
  if(tone_played<20)
   $fatal(1,"tone did not play after first image: samples=%0d",tone_played);
  $display("PASS AV first-frame gate: %0d silent slots, %0d prefilled WAV samples played, %0d tone samples after slow first BMP",silent,played,tone_played);
  $finish;
 end
 initial begin #80000000;$fatal(1,"first-frame audio test timeout");end
endmodule
