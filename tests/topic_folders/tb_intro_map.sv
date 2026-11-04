`timescale 1ns/1ps
module tb_topic_intro_map;
 reg clk=0,rst_n=0;reg [24:0] info=0;reg [4:0] ordinal=0;
 integer counts[0:3],ends[0:3],checks=0,n=0;
 always #5 clk=~clk;
 sd_media_player #(.MAX_IMAGES(24),.INTRO_ANIMATION(1),.ALBUMS(1),.MODE_CONTROL(1)) dut(
  .clk(clk),.pix_clk(clk),.rst_n(rst_n),.sd_miso(1'b1),.next_pulse(1'b0),.prev_pulse(1'b0),
  .pause(1'b1),.audio_urgent(1'b0),.wav_ready(1'b0),.transition_ready(1'b0),.auto_enable(1'b0),.wav_enable(1'b0),
  .album_request(1'b0),.album_enable(1'b0),.album_first(5'd0),.album_limit(5'd24),.intro_enable(1'b1),.intro_pause(1'b0));
 initial begin
  force dut.folder_info=info;force dut.display_index=ordinal;
  repeat(3)@(negedge clk);rst_n=1;
  for(integer a=0;a<=6;a=a+1)for(integer b=0;b<=6;b=b+1)
   for(integer c=0;c<=6;c=c+1)for(integer d=0;d<=6;d=d+1)begin
    counts[0]=a;counts[1]=b;counts[2]=c;counts[3]=d;n=0;
    for(integer g=0;g<4;g=g+1)begin n=n+counts[g];ends[g]=n;end
    info={1'b1,ends[3][5:0],ends[2][5:0],ends[1][5:0],ends[0][5:0]};n=0;
    for(integer g=0;g<4;g=g+1)for(integer i=0;i<counts[g];i=i+1)begin
     ordinal=n;#1;
     if(dut.display_intro_index!==g*6+((i==counts[g]-1)?5:i))$fatal(1,"wrong caption/summary group=%0d local=%0d ordinal=%0d info=%h",g,i,n,info);
     if(dut.intro_frame!==(i==counts[g]-1))$fatal(1,"last-page introduction identity");
     n=n+1;checks=checks+1;
    end
   end
  info=0;for(integer i=0;i<24;i=i+1)begin ordinal=i;#1;if(dut.display_intro_index!==i)$fatal(1,"flat identity changed");end
  $display("PASS folder caption/last-page mapping:2401 folder-count combinations, %0d valid photo identities and flat24 fallback",checks);$finish;
 end
endmodule
