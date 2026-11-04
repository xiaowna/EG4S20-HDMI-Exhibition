`timescale 1ns/1ps
module tb_wav_pause;
 reg sys=0,pix=0,rst_n=0,audio_enable=1,wav_valid=0;
 reg [47:0] wav_data=0;
 always #10 sys=~sys;
 always #20 pix=~pix;
 reg [9:0] x=0,y=0;
 wire de=x<640&&y<480;
 wire hs=!(x>=656&&x<752);
 wire vs=!(y>=490&&y<492);
 always @(posedge pix)begin
  if(!rst_n)begin x<=0;y<=0;end
  else if(x==799)begin x<=0;y<=y==524?0:y+1'b1;end
  else x<=x+1'b1;
 end
 wire wav_ready;
 wire [9:0] red,green,blue;
 wire fault;
 hdmi_av_output dut(.brightness(9'sd0),.gain_q8(9'd256),.loading(1'b0),.fade_enabled(1'b0),.wave_enabled(1'b0),.audio_only(1'b0),.image_valid(1'b1),.sys_clk(sys),.pix_clk(pix),.rst_n(rst_n),
  .audio_enable(audio_enable),.tone_sel(3'd2),
  .video_started(1'b1),.catalog_ready(1'b1),.wav_found(1'b1),
  .wav_error(1'b0),.image_count(3'd0),.image_index(2'd0),
  .wav_valid(wav_valid),.wav_playing(1'b1),.wav_data(wav_data),
  .wav_ready(wav_ready),.de(de),.hsync(hs),.vsync(vs),.rgb(24'd0),
  .red(red),.green(green),.blue(blue),.audio_fault(fault),.audio_urgent());

 function [47:0] sample_at;
  input integer index;
  begin sample_at={24'hA00000|index[23:0],24'h500000|index[23:0]};end
 endfunction
 integer phase=0,writes=0,next_sample=0,silent_slots=0,silent_packets=0;
 reg [11:0] held_rd,held_wr;
 reg freeze_check=0;
 always @(posedge sys)if(rst_n)begin
  if(phase==1||phase==2)begin
   if(wav_ready||dut.fifo.wr_en)$fatal(1,"WAV advanced while paused");
  end
  if(dut.fifo.wr_en&&!dut.fifo.wr_full)begin
   if(dut.fifo.wr_data!==sample_at(writes))
    $fatal(1,"WAV write order %0d: %h",writes,dut.fifo.wr_data);
   writes=writes+1;
  end
 end
 always @(posedge pix)if(rst_n)begin
  if(freeze_check&&phase!=3)begin
   if(dut.fifo.rd_bin!==held_rd||dut.fifo.wr_bin!==held_wr||dut.fifo_read)
    $fatal(1,"queued WAV samples moved during pause");
  end
  if(dut.packets.state==2)begin // CAPTURE: synchronous FIFO output is valid.
   if(!dut.packets.capture_zero)begin
    if(phase==2)$fatal(1,"nonzero WAV sample captured while paused");
    if(dut.packets.packet_sample!==sample_at(next_sample))
     $fatal(1,"WAV sample order %0d: got %h",next_sample,dut.packets.packet_sample);
    next_sample=next_sample+1;
   end else if(phase==2) silent_slots=silent_slots+1;
  end
  if(phase==2&&dut.island&&dut.phase==10)begin
   if(dut.ah[7:0]!==8'h02)$fatal(1,"no HDMI audio packet during pause");
   if(dut.ah[8]&&dut.ab[0 +: 48]!==48'd0)
    $fatal(1,"HDMI output was not silent during pause");
   if(dut.ah[9]&&dut.ab[56 +: 48]!==48'd0)
    $fatal(1,"second HDMI sample was not silent during pause");
   silent_packets=silent_packets+1;
  end
  if(fault)$fatal(1,"HDMI audio fault");
 end
 integer i;
 initial begin
  repeat(8)@(negedge pix);rst_n=1;
  // Fill the 1024-sample prebuffer with real WAV data before pausing.
  wait(wav_ready);
  @(negedge sys);wav_valid=1;
  for(i=0;i<1060;i=i+1)begin
   if(!wav_ready)$fatal(1,"FIFO did not accept prebuffer sample %0d",i);
   wav_data=sample_at(i);
   @(negedge sys);
  end
  wav_valid=0;
  wait(next_sample>=4);
  @(negedge sys);audio_enable=0;wav_valid=1;wav_data=sample_at(1060);phase=1;
  // Two pixel clocks are allowed for the pause synchronizer to settle.
  repeat(2)@(negedge pix);
  held_rd=dut.fifo.rd_bin;held_wr=dut.fifo.wr_bin;
  freeze_check=1;
  repeat(800*2)@(negedge pix);
  phase=2;
  repeat(800*4)@(negedge pix);
  if(silent_slots<4||silent_packets<3)
   $fatal(1,"HDMI did not continue sending silence: slots=%0d packets=%0d",
    silent_slots,silent_packets);
  @(negedge sys);audio_enable=1;phase=3;
  @(negedge sys);wav_valid=0;
  repeat(800*12)@(negedge pix);
  if(writes!=1061||next_sample<16||fault)
   $fatal(1,"resume failed: writes=%0d played=%0d",writes,next_sample);
  $display("PASS WAV pause: %0d queued samples retained, %0d silent packets, %0d ordered samples played",
   held_wr-held_rd,silent_packets,next_sample);
  $finish;
 end
 initial begin #2000000;$fatal(1,"pause regression timeout");end
endmodule
