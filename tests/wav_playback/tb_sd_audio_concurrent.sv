`timescale 1ns/1ps
// Sixteen-sector 48 kHz / 24-bit stereo WAV, looped while image sectors
// compete for a 6.25 MHz-equivalent card. Two-sector clusters force FAT reads.
module tb_sd_audio_concurrent;
 reg sys_clk=0,pix_clk=0,rst_n=0;
 always #10 sys_clk=~sys_clk;
 always #20 pix_clk=~pix_clk;

 wire card_ready,card_start,image_ready,image_done,image_error,image_valid;
 wire audio_ready,audio_done,audio_error,audio_valid;
 wire [31:0] card_lba,audio_lba;
 wire [8:0] image_addr,audio_addr;
 wire [7:0] image_data,audio_byte;
 reg card_busy=0,card_done=0,card_error=0,card_valid=0;
 reg [8:0] card_addr=0;
 reg [7:0] card_data=0;
 reg image_start=0;
 reg [31:0] image_lba=0;
 reg image_pending=0;
 wire audio_start,audio_urgent;
 assign card_ready=!card_busy;

 sd_sector_arbiter arbiter(
  .clk(sys_clk),.rst_n(rst_n),.card_ready(card_ready),
  .audio_urgent(audio_urgent),
  .card_done(card_done),.card_error(card_error),.card_addr(card_addr),
  .card_data(card_data),.card_valid(card_valid),.card_start(card_start),
  .card_lba(card_lba),.image_start(image_start),.image_lba(image_lba),
  .image_ready(image_ready),.image_done(image_done),.image_error(image_error),
  .image_addr(image_addr),.image_data(image_data),.image_valid(image_valid),
  .audio_start(audio_start),.audio_lba(audio_lba),.audio_ready(audio_ready),
  .audio_done(audio_done),.audio_error(audio_error),.audio_addr(audio_addr),
  .audio_data(audio_byte),.audio_valid(audio_valid));

 wire playing,wav_error,sample_valid,fifo_full,fifo_empty;
 wire [47:0] sample_data,fifo_data;
 wire [8:0] fifo_level;
 wire sample_ready=!fifo_full;
 reg urgent_pix=1;
 reg [1:0] urgent_sync=2'b11;
 assign audio_urgent=playing&&urgent_sync[1];
 reg primed=0;
 reg [24:0] phase=0;
 wire tick=({1'b0,phase}+26'd48000>=26'd25000000);
 wire fifo_read=primed&&tick&&!fifo_empty;
 fat32_wav_player #(.TIMEOUT_CYCLES(2000000)) player(
  .clk(sys_clk),.rst_n(rst_n),.volume_ready(1'b1),.file_found(1'b1),
  .first_cluster(32'd5),.file_size(32'd8192),.fat_lba(32'd32),
  .data_lba(32'd1232),.cluster_count(32'd70000),.sectors_per_cluster(8'd2),
  .rd_ready(audio_ready),.rd_done(audio_done),.rd_error(audio_error),
  .rd_addr(audio_addr),.rd_data(audio_byte),.rd_valid(audio_valid),
  .rd_start(audio_start),.rd_lba(audio_lba),.sample_valid(sample_valid),
  .sample_ready(sample_ready),.sample_data(sample_data),
  .playing(playing),.error(wav_error));
 audio_async_fifo fifo(
  .wr_clk(sys_clk),.wr_rst_n(rst_n),.wr_en(sample_valid&&sample_ready),
  .wr_data(sample_data),.wr_full(fifo_full),.rd_clk(pix_clk),
  .rd_rst_n(rst_n),.rd_en(fifo_read),.rd_data(fifo_data),
  .rd_empty(fifo_empty),.rd_level(fifo_level));
 // Cross only the threshold decision, not the multi-bit FIFO pointer count.
 always @(posedge pix_clk or negedge rst_n)
  if(!rst_n)urgent_pix<=1;
  else urgent_pix<=fifo_level<9'd192;
 always @(posedge sys_clk or negedge rst_n)
  if(!rst_n)urgent_sync<=2'b11;
  else urgent_sync<={urgent_sync[0],urgent_pix};

 // Header: RIFF size 8184, PCM stereo 48 kHz 24-bit,
 // data size 8148 = 1358 frames.
 function [7:0] wav_byte;
  input integer offset;
  begin
   case(offset)
    0: wav_byte="R"; 1: wav_byte="I"; 2: wav_byte="F"; 3: wav_byte="F";
    4: wav_byte=8'hf8; 5: wav_byte=8'h1f;
    8: wav_byte="W"; 9: wav_byte="A"; 10: wav_byte="V"; 11: wav_byte="E";
    12: wav_byte="f"; 13: wav_byte="m"; 14: wav_byte="t"; 15: wav_byte=" ";
    16: wav_byte=8'd16; 20: wav_byte=8'd1; 22: wav_byte=8'd2;
    24: wav_byte=8'h80; 25: wav_byte=8'hbb;
    28: wav_byte=8'h00; 29: wav_byte=8'h65; 30: wav_byte=8'h04;
    32: wav_byte=8'd6; 34: wav_byte=8'd24;
    36: wav_byte="d"; 37: wav_byte="a"; 38: wav_byte="t"; 39: wav_byte="a";
    40: wav_byte=8'hd4; 41: wav_byte=8'h1f;
    default:begin
     if(offset>=44&&offset<8192)begin
      case((offset-44)%6)
       0: wav_byte=8'h56; 1: wav_byte=8'h34; 2: wav_byte=8'h12;
       3: wav_byte=8'hef; 4: wav_byte=8'hcd; 5: wav_byte=8'hab;
      endcase
     end else wav_byte=0;
    end
   endcase
  end
 endfunction

 function [7:0] fat_byte;
  input integer offset;
  integer next_cluster;
  begin
   next_cluster=(offset/4)+1;
   case(offset%4)
    0:fat_byte=next_cluster[7:0];
    1:fat_byte=next_cluster[15:8];
    2:fat_byte=next_cluster[23:16];
    3:fat_byte=next_cluster[31:24];
   endcase
  end
 endfunction

 integer image_requests=0,image_sectors=0,audio_sectors=0,first_sector_reads=0,fat_reads=0;
 integer image_bytes=0,audio_bytes=0,card_transactions=0;
 reg [31:0] active_lba=0;
 integer byte_index;
 always @(posedge sys_clk)begin
  if(!rst_n)begin image_start<=0;image_lba<=0;image_pending<=0;end
  else begin
   image_start<=0;
   if(image_done)image_pending<=0;
   else if(!image_pending&&image_ready)begin
    image_lba<=32'd2000+image_requests;
    image_start<=1;
    image_pending<=1;
    image_requests=image_requests+1;
   end
  end
 end
 // 64 system clocks per byte = 1.28 us/byte, matching a 6.25 MHz SPI stream.
 initial forever begin
  @(posedge sys_clk);
  if(card_start)begin
   if(card_busy)$fatal(1,"overlapping card requests");
   card_busy<=1;active_lba=card_lba;card_transactions=card_transactions+1;
   repeat(80)@(negedge sys_clk);
   for(byte_index=0;byte_index<512;byte_index=byte_index+1)begin
    repeat(63)@(negedge sys_clk);
    card_addr=byte_index;
    if(active_lba>=1238&&active_lba<1254)
     card_data=wav_byte((active_lba-1238)*512+byte_index);
    else if(active_lba==32)card_data=fat_byte(byte_index);
    else card_data=byte_index[7:0];
    card_valid=1;
    @(negedge sys_clk);card_valid=0;
   end
   repeat(2)@(negedge sys_clk);
   card_done=1;
   @(negedge sys_clk);card_done=0;card_busy=0;
  end
 end
 always @(posedge sys_clk)if(rst_n)begin
  if(image_valid)begin
   if(active_lba<2000||audio_valid||image_data!==image_addr[7:0])
    $fatal(1,"image sector data crossed owner");
   image_bytes=image_bytes+1;
  end
  if(audio_valid)begin
   if(!((active_lba>=1238&&active_lba<1254)||active_lba==32)||image_valid||
      audio_byte!==(active_lba==32?fat_byte(audio_addr):wav_byte((active_lba-1238)*512+audio_addr)))
    $fatal(1,"WAV sector data crossed owner");
   audio_bytes=audio_bytes+1;
  end
  if(image_done)image_sectors=image_sectors+1;
  if(audio_done)begin
   audio_sectors=audio_sectors+1;
   if(active_lba==1238)first_sector_reads=first_sector_reads+1;
   if(active_lba==32)fat_reads=fat_reads+1;
  end
  if(wav_error||image_error||audio_error)$fatal(1,"media read error");
 end

 integer consumed=0,min_level=256;
 reg check_data=0;
 always @(posedge pix_clk)begin
  if(!rst_n)begin phase<=0;primed<=0;check_data<=0;end
  else begin
   if(fifo_level>=9'd128)primed<=1;
   if(primed&&fifo_level<min_level)min_level=fifo_level;
   if(check_data&&fifo_data!==48'h123456abcdef)
    $fatal(1,"corrupt consumed WAV sample %h",fifo_data);
   check_data<=fifo_read;
   if(tick)begin
    phase<=phase+25'd48000-25'd25000000;
    if(primed)begin
     if(fifo_empty)$fatal(1,"audio underflow after prebuffer, samples=%0d image=%0d audio=%0d",consumed,image_sectors,audio_sectors);
     consumed=consumed+1;
    end
   end else phase<=phase+25'd48000;
  end
 end
 initial begin
  repeat(8)@(negedge sys_clk);rst_n=1;
  wait(first_sector_reads>=2 && image_sectors>=8 && fat_reads>=7 && consumed>=1500);
  repeat(8)@(negedge pix_clk);
  if(audio_sectors<23||image_bytes<4096||audio_bytes<23*512||min_level>256)
   $fatal(1,"insufficient concurrent traffic image=%0d audio=%0d samples=%0d",image_sectors,audio_sectors,consumed);
  $display("PASS concurrent SD+WAV: image sectors=%0d audio sectors=%0d FAT reads=%0d loops=%0d consumed=%0d minimum FIFO=%0d",
   image_sectors,audio_sectors,fat_reads,first_sector_reads,consumed,min_level);
  $finish;
 end
 initial begin #100000000;$fatal(1,"concurrent media timeout image=%0d audio=%0d FAT=%0d loops=%0d samples=%0d",image_sectors,audio_sectors,fat_reads,first_sector_reads,consumed);end
endmodule
