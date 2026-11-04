`timescale 1ns/1ps
// Replace only the SPI transport. Mount/scan, all metadata pass-throughs, the
// WAV decoder, sector ownership, SDRAM/video and HDMI audio are production RTL.
module sd_subsystem #(parameter CLK_HZ=50000000)(
 input wire clk,rst_n,sd_miso,read_start,input wire [31:0] read_lba,
 output wire sd_sck,sd_mosi,sd_cs,ready,error,read_request_ready,read_error,
 output reg read_done,data_valid,output reg [8:0] data_addr,output reg [7:0] data_out);
 reg [7:0] fixture[0:1535];
 reg busy=0;integer lba=0,pos=0,delay=0,cycles=0,bad_track=-1,requests=0;
 assign sd_sck=0;assign sd_mosi=1;assign sd_cs=1;assign ready=rst_n;assign error=0;
 assign read_error=0;assign read_request_ready=!busy;
 initial $readmemh("wav_playback/card_fixture.hex",fixture);
 function [7:0] byte_at(input integer sector,address);
  integer song,offset,sample_index,value,field;begin
   byte_at=0;
   if(sector==0)byte_at=fixture[address];
   else if(sector==1234)begin
    song=address/32;field=address%32;
    if(song<4)case(field)
     0:byte_at="A"+song;8:byte_at="W";9:byte_at="A";10:byte_at="V";
     26:byte_at=10+2*song;28:byte_at=8'hac;29:byte_at=2;
    endcase
   end else if(sector>=1248&&sector<1262)begin
    song=(sector-1248)/4;offset=((sector-1248)%4)*512+address;
    case(offset)
     0:byte_at=(song==bad_track)?"X":"R";1:byte_at="I";2:byte_at="F";3:byte_at="F";
     4:byte_at=8'ha4;5:byte_at=2;
     8:byte_at="W";9:byte_at="A";10:byte_at="V";11:byte_at="E";
     12:byte_at="f";13:byte_at="m";14:byte_at="t";15:byte_at=" ";
     16:byte_at=16;20:byte_at=1;22:byte_at=2;
     24:byte_at=8'h80;25:byte_at=8'hbb;29:byte_at=8'hee;30:byte_at=2;
     32:byte_at=4;34:byte_at=16;
     36:byte_at="d";37:byte_at="a";38:byte_at="t";39:byte_at="a";
     40:byte_at=8'h80;41:byte_at=2;
     default:if(offset>=44&&offset<684)begin
      sample_index=(offset-44)/4;
      value=(((offset-44)%4<2)?16'h1100:16'h5500)+song*16'h1000+sample_index;
      byte_at=((offset-44)%2)?value>>8:value;
     end
    endcase
   end else $fatal(1,"unexpected four-song card sector %0d",sector);
  end
 endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin busy<=0;read_done<=0;data_valid<=0;data_addr<=0;data_out<=0;pos<=0;delay<=0;cycles<=0;end
  else begin
   cycles<=cycles+1;read_done<=0;data_valid<=0;
   if(!busy)begin
    if(read_start)begin busy<=1;lba<=read_lba;pos<=0;delay<=5;requests<=requests+1;end
   end else if(delay!=0)delay<=delay-1;
   else if(pos==512)begin read_done<=1;busy<=0;end
   else if(cycles%5!=0)begin
    data_addr<=pos;data_out<=byte_at(lba,pos);data_valid<=1;pos<=pos+1;
   end
  end
 end
endmodule

module tb_music_audio;
 reg sys_clk=0,pix_clk=0,rst_n=0,mode_sw7=1,paused=0,music_request=0;
 reg [1:0] music_index=0;
 wire [1:0] active_music_index;wire [2:0] wav_count;
 wire product_mode,switching,wav_enable,wav_idle,audio_flush_request,audio_flush_done,mode_change;
 wire wav_valid,wav_ready,wav_playing,wav_error,catalog_ready,wav_found,audio_only,video_started;
 wire [47:0] wav_data;wire audio_urgent,audio_fault,de,hs,vs;
 wire [23:0] rgb;wire [9:0] red,green,blue;
 integer packets=0,reads=0,writes=0,head=0,tail=0,stops=0,old_count=0,loops=0;
 reg [47:0] queue[0:131071],expected;
 always #10 sys_clk=~sys_clk;always #20 pix_clk=~pix_clk;
 media_mode_control #(.DEBOUNCE_CYCLES(3),.MUSIC_SELECT(1)) control(
  .clk(sys_clk),.rst_n(rst_n),.mode_sw7(mode_sw7),.wav_idle(wav_idle),.audio_flush_done(audio_flush_done),
  .product_mode(product_mode),.switching(switching),.wav_enable(wav_enable),.audio_flush_request(audio_flush_request),
  .mode_change(mode_change),.music_request(music_request),.music_index(music_index),.active_music_index(active_music_index));
 sd_media_player #(.MODE_CONTROL(1),.MAX_IMAGES(32),.MAX_WAVS(4),.SLIDE_TRANSITIONS(1)) player(
  .clk(sys_clk),.pix_clk(pix_clk),.rst_n(rst_n),.sd_miso(1'b1),.next_pulse(1'b0),.prev_pulse(1'b0),
  .pause(paused),.audio_urgent(audio_urgent),.wav_ready(wav_ready),.wav_valid(wav_valid),.wav_data(wav_data),
  .wav_playing(wav_playing),.wav_error(wav_error),.catalog_ready(catalog_ready),.wav_found(wav_found),
  .audio_only(audio_only),.video_started(video_started),.de(de),.hsync(hs),.vsync(vs),.rgb(rgb),
  .transition_ready(1'b1),.auto_enable(1'b0),.wav_enable(wav_enable),.wav_idle(wav_idle),
  .wav_index(active_music_index),.wav_count(wav_count));
 hdmi_av_output #(.SETTINGS_UI(1),.MODE_CONTROL(1),.CHINESE_SUBTITLE(1),.CHINESE_SETTINGS(1),.SPECTRUM_FFT(1),.MUSIC_MENU(1),.MAX_IMAGES(32)) av(
  .sys_clk(sys_clk),.pix_clk(pix_clk),.rst_n(rst_n),.audio_enable(!switching&&!paused),
  .tone_sel(3'd2),.video_started(video_started),.catalog_ready(catalog_ready),.wav_found(wav_found),.wav_error(wav_error),
  .audio_only(audio_only),.image_valid(1'b0),.image_count(6'd0),.image_index(5'd0),
  .wav_valid(wav_valid),.wav_playing(wav_playing),.wav_data(wav_data),.wav_ready(wav_ready),
  .de(de),.hsync(hs),.vsync(vs),.rgb(rgb),.brightness(9'sd0),.gain_q8(9'd256),
  .loading(1'b0),.fade_enabled(1'b0),.wave_enabled(1'b1),.settings_word(11'd0),
  .red(red),.green(green),.blue(blue),.audio_fault(audio_fault),.audio_urgent(audio_urgent),
  .force_tone(!product_mode),.audio_flush_request(audio_flush_request),.audio_flush_done(audio_flush_done),
  .mode_status({switching,product_mode,2'b00}),.music_status({1'b0,music_index,wav_count,active_music_index}));
 reg [223:0] captured_audio_body;
 reg [23:0] captured_audio_header;
 // Check the accepted packet, independent of private BCH storage.
 always @(posedge pix_clk or negedge rst_n)
  if(!rst_n)begin captured_audio_body<=0;captured_audio_header<=0;end
  else if(av.packet_valid&&av.ar)begin
   captured_audio_body<=av.ab;captured_audio_header<=av.ah;
  end
 always @(negedge av.fifo_rst_n)begin head=0;tail=0;stops=stops+1;end
 always @(posedge sys_clk)if(rst_n)begin
  if(av.fifo.wr_en&&!av.fifo.wr_full)begin
   if(av.use_wav && (av.fifo.wr_data[47:44]!==1+active_music_index || av.fifo.wr_data[23:20]!==5+active_music_index))
    $fatal(1,"wrong song entered audio FIFO track=%0d data=%h",active_music_index,av.fifo.wr_data);
   queue[tail]=av.fifo.wr_data;tail=tail+1;writes=writes+1;
  end
  if(audio_flush_request&&!wav_idle)$fatal(1,"flushed before real card sector completion");
  if(player.u_wav.file_start)loops=loops+1;
 end
 always @(posedge pix_clk)if(rst_n)begin
  if(av.fifo_read)begin
   if(head>=tail)$fatal(1,"audio FIFO consumed unpublished sample");
   expected=queue[head];head=head+1;reads=reads+1;
   #1;if(av.fifo_data!==expected)$fatal(1,"sample order crossed song flush");
  end
  if(audio_fault)$fatal(1,"song switch caused HDMI/audio fault");
  if(av.island&&av.phase==10)for(integer slot=0;slot<2;slot=slot+1)begin
   if(captured_audio_header[8+slot]&&captured_audio_body[slot*56 +:48]!=0&&!wav_error&&product_mode&&!switching)begin
    if(captured_audio_body[slot*56+20 +:4]!==1+active_music_index ||
       captured_audio_body[slot*56+44 +:4]!==5+active_music_index)
     $fatal(1,"old or wrong song reached new HDMI packet track=%0d",active_music_index);
    packets=packets+1;
   end
  end
 end
 task ticks(input integer n);repeat(n)begin @(negedge sys_clk);#1;end endtask
 task select_song(input [1:0] song);begin
  @(negedge sys_clk);music_index=song;music_request=1;ticks(1);music_request=0;
  wait(active_music_index==song&&!switching);ticks(3);
 end endtask
 task played;begin old_count=packets;wait(packets>=old_count+8);end endtask
 always #10000000 $display("PROGRESS music time=%0t packets=%0d catalog=%b count=%0d source=%0d slot=%0d fifo=%0d req=%0d",$time,packets,catalog_ready,wav_count,player.u_wav.state,active_music_index,av.fifo_level,player.u_card.requests);
 initial begin
  ticks(4);rst_n=1;wait(catalog_ready&&!switching);
  $display("PROGRESS real music catalogue ready count=%0d time=%0t",wav_count,$time);
  if(wav_count!=4 || !wav_found || player.image_count!=0)$fatal(1,"real mounted four-song catalogue failed");
  played;$display("PROGRESS song zero reached HDMI");
  for(integer song=1;song<4;song=song+1)begin select_song(song);played;$display("PROGRESS song %0d reached HDMI",song);end
  paused=1;ticks(5);old_count=reads;select_song(0);ticks(200);
  if(!paused || reads!=old_count)$fatal(1,"selecting a song resumed paused output");
  paused=0;played;$display("PROGRESS paused switch recovered");
  player.u_card.bad_track=2;select_song(2);wait(wav_error);ticks(20);
  if(player.wav_valid)$fatal(1,"unvalidated WAV produced samples");
  player.u_card.bad_track=-1;select_song(1);played;$display("PROGRESS invalid-song recovery reached HDMI");
  mode_sw7=0;wait(!switching&&!product_mode);ticks(100);
  mode_sw7=1;wait(!switching&&product_mode);played;
  if(active_music_index!=1 || loops<20 || stops<8)$fatal(1,"loop/flush/mode coverage missing");
  $display("PASS real four-song mount-to-HDMI: packets=%0d FIFO_reads=%0d FIFO_writes=%0d loops=%0d flushes=%0d; all four identities, paused switch, invalid header recovery, SW7, FFT enabled, no stale audio",packets,reads,writes,loops,stops);$finish;
 end
 initial begin #150000000;$fatal(1,"real four-song audio timeout packets=%0d track=%0d catalog=%b count=%0d state=%0d source=%0d req=%0d pending=%b ready=%b",packets,active_music_index,catalog_ready,wav_count,control.state,player.u_wav.state,player.u_card.requests,av.fifo_empty,av.audio_primed);end
endmodule
