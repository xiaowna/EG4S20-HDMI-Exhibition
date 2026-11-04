`timescale 1ns/1ps
// Real asynchronous status bridge and OSD; independent decimal/font oracle.
module tb_status;
 reg sys=0,pix=0,rst_n=0,vsync=1,de=0,audio_enable=1;
 reg [5:0] count=0;reg [4:0] index=0;
 reg [10:0] settings=0;reg [3:0] mode=0;
 wire [29:0] expected={mode,settings,1'b1,count,index,!audio_enable,2'b11};
 integer checks=0;
 always #7 sys=~sys;
 always #11 pix=~pix;
 hdmi_av_output #(.MAX_IMAGES(32),.SETTINGS_UI(1),.MODE_CONTROL(1)) dut(
  .sys_clk(sys),.pix_clk(pix),.rst_n(rst_n),.audio_enable(audio_enable),.tone_sel(3'd0),
  .video_started(1'b0),.catalog_ready(1'b1),.wav_found(1'b1),.wav_error(1'b0),
  .audio_only(1'b0),.image_valid(1'b1),.image_count(count),.image_index(index),
  .wav_valid(1'b0),.wav_playing(1'b0),.wav_data(48'd0),.de(de),.hsync(1'b1),.vsync(vsync),
  .rgb(24'h804020),.brightness(9'sd0),.gain_q8(9'd256),.loading(1'b1),
  .fade_enabled(1'b1),.wave_enabled(1'b0),.settings_word(settings),.mode_status(mode),
  .force_tone(1'b0),.audio_flush_request(1'b0));
 function automatic [7:0] digit_row(input integer n,row);
  reg [55:0] bits;
  begin
   case(n)
    0:bits=56'h3c42464a52623c;1:bits=56'h1828080808083e;
    2:bits=56'h3c42020c30407e;3:bits=56'h3c42021c02423c;
    4:bits=56'h0c1424447e0404;5:bits=56'h7e407c0202423c;
    6:bits=56'h3c407c4242423c;7:bits=56'h7e020408101010;
    8:bits=56'h3c42423c42423c;9:bits=56'h3c42423e02023c;
    default:bits=0;
   endcase
   digit_row=(row==7)?0:(bits>>((6-row)*8));
  end
 endfunction
 task settle;
  integer n;
  begin
   n=0;
   while(dut.status_pix!==expected && n<80)begin @(negedge pix);n=n+1;end
   if(dut.status_pix!==expected)$fatal(1,"wide CDC dropped/truncated status expected=%h got=%h",expected,dut.status_pix);
  end
 endtask
 task frame;
  begin
   @(negedge pix);vsync=0;
   repeat(2)@(negedge pix);
   vsync=1;@(negedge pix);
   if({dut.osd.mode_frame,dut.osd.settings_frame,dut.osd.status_frame}!==expected)
    $fatal(1,"wide status/settings/mode snapshot mismatch");
  end
 endtask
 task digit(input integer slot,value);
  reg [7:0] row_bits;reg [23:0] wanted;
  begin
   @(negedge pix);de=1;
   // Place raster coordinates as in the existing OSD regression.
   for(integer y=0;y<16;y=y+1)begin
    row_bits=digit_row(value,y/2);
    for(integer x=0;x<16;x=x+1)begin
     dut.osd.active_x=slot*16+x;dut.osd.active_y=440+y;#0.01;
     wanted=row_bits[7-x/2]?24'hb6e7d7:24'h402010;
     if(dut.osd_rgb!==wanted)$fatal(1,"decimal pixel slot=%0d digit=%0d xy=%0d,%0d",slot,value,x,y);
     checks=checks+1;
    end
   end
   de=0;
  end
 endtask
 reg [29:0] before_word;
 initial begin
  repeat(4)@(negedge pix);rst_n=1;settle();frame();
  for(integer n=1;n<=32;n=n+1)begin
   before_word={dut.osd.mode_frame,dut.osd.settings_frame,dut.osd.status_frame};
   @(negedge sys);count=n;index=n-1;mode=n;settings=(n*71)^11'h400;audio_enable=n%2;
   settle();
   if({dut.osd.mode_frame,dut.osd.settings_frame,dut.osd.status_frame}!==before_word)
    $fatal(1,"status changed within displayed frame");
   frame();digit(4,n/10);digit(5,n%10);digit(7,n/10);digit(8,n%10);
   if(settings[10] && dut.fade_level!=32)$fatal(1,"wide settings menu no longer suppresses fade");
  end
  // Coalesced rapid changes must eventually publish the complete final word.
  for(integer n=0;n<100;n=n+1)begin
   @(negedge sys);count=32;index=n%32;settings=n*13;mode=n;audio_enable=n%2;
  end
  settle();frame();digit(4,0);digit(5,4);digit(7,3);digit(8,2);
  $display("PASS gallery32 status: asynchronous count/index/settings/mode, frame atomicity, 01..32 decimal pixels=%0d",checks);
  $finish;
 end
 initial begin #1000000;$fatal(1,"status timeout");end
endmodule
