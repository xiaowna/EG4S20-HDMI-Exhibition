`timescale 1ns/1ps
module tb_home_menu;
 reg clk=0,rst_n=0,de=0,vsync=1;
 reg [9:0] x=0,y=0;reg [23:0] rgb=0;
 reg [10:0] settings_word=0;reg [3:0] mode_status=0;
 wire [23:0] rgb_out;wire overlay_valid;
 reg [24:0] golden[0:307199];reg [14:0] states[0:2];reg [7:0] musics[0:2];reg [7:0] music_status=0;
 integer f,xx,yy,p,preview,checks=0,visible=0;
 reg [23:0] displayed;reg [24:0] expected;string filename;
 always #5 clk=~clk;
 video_chinese_settings #(.SPECTRUM_FFT(1),.MUSIC_MENU(1),.RTC_SETTING(1),.COMPACT_ROWS(1)) dut(.clk(clk),.rst_n(rst_n),.de(de),.vsync(vsync),.x(x),.y(y),
  .rgb_in(rgb),.settings_word(settings_word),.mode_status(mode_status),
  .rgb_out(rgb_out),.overlay_valid(overlay_valid),.music_status(music_status),.rtc_word(49'd0),.rtc_edit_word(54'd0));
 task tick;begin @(posedge clk);#1;@(negedge clk);#1;end endtask
 initial begin
  $readmemh("ui_states.hex",states);$readmemh("ui_musics.hex",musics);
  tick;rst_n=1;
  for(f=0;f<3;f=f+1)begin
   filename=$sformatf("menu_golden_%0d.hex",f);$readmemh(filename,golden);
   {mode_status,settings_word}=states[f];music_status=musics[f];de=0;vsync=0;tick;vsync=1;tick;
   preview=0;
   if(f==0)preview=$fopen("compact_menu.ppm","w");
   if(f==5)preview=$fopen("menu_auto.ppm","w");
   if(f==6)preview=$fopen("menu_demo.ppm","w");
   if(preview)$fwrite(preview,"P3\n640 480\n255\n");
   for(yy=0;yy<480;yy=yy+1)begin
    for(xx=0;xx<640;xx=xx+1)begin
     x=xx;y=yy;de=1;rgb={xx[7:0],yy[7:0],xx[7:0]^yy[7:0]};
     expected=golden[yy*640+xx];tick;
     if(overlay_valid!==expected[24])$fatal(1,"Menu coverage frame=%0d xy=%0d,%0d",f,xx,yy);
     if(overlay_valid&&rgb_out!==expected[23:0])
      $fatal(1,"Menu pixel frame=%0d xy=%0d,%0d expected=%h actual=%h",f,xx,yy,expected[23:0],rgb_out);
     displayed=overlay_valid?rgb_out:rgb;
     if(preview)$fwrite(preview,"%0d %0d %0d\n",displayed[23:16],displayed[15:8],displayed[7:0]);
     if(overlay_valid)visible=visible+1;
     checks=checks+1;
     // Arbitrary coherent changes in mid-frame may not tear the visible page.
     if(xx==400&&yy==200)begin settings_word=0;music_status=~musics[f];mode_status=~states[f][14:11];end
    end
    de=0;tick;
    if(overlay_valid)$fatal(1,"Overlay leaked into blanking");
   end
   if(preview)$fclose(preview);
  end
  // Reset closes an open panel immediately, regardless of ROM contents.
  settings_word=states[0][10:0];mode_status=states[0][14:11];vsync=0;tick;
  vsync=1;x=200;y=180;de=1;tick;if(!overlay_valid)$fatal(1,"Reset test did not open menu");
  rst_n=0;#1;if(overlay_valid)$fatal(1,"Menu not suppressed by reset");
  $display("PASS compact seven-row settings: %0d pixels, %0d painted; five pages/levels, toggles, demo lock, frame atomicity, close/reset/blanking",checks,visible);
  $finish;
 end
 initial begin #40000000;$fatal(1,"Chinese menu timeout");end
endmodule
