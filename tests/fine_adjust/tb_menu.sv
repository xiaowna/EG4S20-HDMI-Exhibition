`timescale 1ns/1ps
module tb_fine_menu;
 reg clk=0,rst_n=0,de=0,vsync=1;reg [9:0] x=0,y=0;
 reg [23:0] rgb_in=0;reg [10:0] settings_word=0;reg [14:0] fine_adjust_word=0;
 wire [23:0] rgb_out;wire overlay_valid;
 integer fd,n,b,p,page,points,j,xx,yy,total=0,preview;
 reg [24:0] expected;
 always #5 clk=~clk;
 video_chinese_settings #(.FINE_ADJUST(1),.SPECTRUM_FFT(1),.MUSIC_MENU(1),.RTC_SETTING(1),.COMPACT_ROWS(1)) dut(
  .clk(clk),.rst_n(rst_n),.de(de),.vsync(vsync),.x(x),.y(y),.rgb_in(rgb_in),
  .settings_word(settings_word),.fine_adjust_word(fine_adjust_word),.mode_status(4'b0100),
  .music_status(8'h10),.rtc_word(49'd0),.rtc_edit_word(54'd0),.rgb_out(rgb_out),.overlay_valid(overlay_valid));
 task tick;begin @(posedge clk);#1;@(negedge clk);#1;end endtask
 initial begin
  repeat(3)tick();rst_n=1;repeat(3)tick();
  fd=$fopen("menu_vectors.txt","r");if(!fd)$fatal(1,"missing menu vectors");
  while(!$feof(fd))begin
   n=$fscanf(fd,"%d %d %d %d\n",b,p,page,points);if(n!=4)$fatal(1,"header");
   fine_adjust_word=((b+64)<<7)|(p-50);settings_word=11'h400|(page<<8);
   de=0;vsync=0;tick;vsync=1;tick;
   // Change source during the decimal conversion: both displayed numbers
   // must continue to describe the complete word sampled at frame start.
   fine_adjust_word=15'd0;repeat(24)tick();
   preview=0;if(b==1&&p==101&&points==307200)begin preview=$fopen("fine_menu.ppm","w");$fwrite(preview,"P3\n640 480\n255\n");end
   for(j=0;j<points;j++)begin
    n=$fscanf(fd,"%d %d %h\n",xx,yy,expected);if(n!=3)$fatal(1,"pixel vector");
    x=xx;y=yy;rgb_in={xx[7:0],yy[7:0],xx[7:0]^yy[7:0]};de=1;tick;
    if(overlay_valid!==expected[24]||(overlay_valid&&rgb_out!==expected[23:0]))
     $fatal(1,"fine menu b=%0d p=%0d xy=%0d,%0d got=%h mask=%b wanted=%h",b,p,xx,yy,rgb_out,overlay_valid,expected);
    if(preview)$fwrite(preview,"%0d %0d %0d\n",(overlay_valid?rgb_out[23:16]:rgb_in[23:16]),(overlay_valid?rgb_out[15:8]:rgb_in[15:8]),(overlay_valid?rgb_out[7:0]:rgb_in[7:0]));
    total++;
   end
   if(preview)$fclose(preview);de=0;tick;
   if(overlay_valid)$fatal(1,"menu into blanking");
  end
  rst_n=0;#1;if(overlay_valid)$fatal(1,"reset");
  $display("PASS fine menu: %0d independent pixels, every 129/101 numeric readout and slider position, five full frames, coherent source-word capture and reset/blanking",total);$finish;
 end
 initial begin #100000000;$fatal(1,"menu timeout");end
endmodule
