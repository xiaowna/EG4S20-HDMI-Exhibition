`timescale 1ns/1ps
// Actual 640x480 loader profile, FAT32 chains, CRC-status retries, P1 cache
// control and SD/audio arbitration. The checked RAM sink supplies backpressure
// and delayed draining; the unchanged SDRAM/raster has a separate full test.
module tb_scale_loader;
 localparam W=640,H=480,N=W*H,SIZE0=54+320*240*3,SIZE1=54+640*480*3;
 localparam SECT0=(SIZE0+511)/512,SECT1=(SIZE1+511)/512;
 localparam SPC=128,VOLUME_SECTORS=1232+70000*SPC;
 localparam ROOT_LBA=3280+SPC,BASE0=3280+3*SPC,BASE1=3280+998*SPC;
 localparam CLUST0=(SECT0+SPC-1)/SPC,CLUST1=(SECT1+SPC-1)/SPC;
 reg clk=0,rst_n=0,next_pulse=0,prev_pulse=0,pause=1;
 always #5 clk=~clk;
 wire scan_start,load_start,load_ready,scan_done,image_done,error;
 wire [2:0] image_count;wire [1:0] image_index;
 wire commit_enable,discard_cached,transition_active,frame_prepared;
 wire front_valid,front_bank,frame_committed,frame_rejected,wr_valid;
 wire [31:0] wr_addr,wr_data;
 reg [1:0] display_index=0,loading_index=0;
 integer cycles=0,commits=0,loads=0,rejections=0,writes=0,frame_writes=0,drain=0;
 integer audio_bytes=0,audio_sectors=0,audio_cooldown=0,failed_sectors=0,requests=0;
 reg [31:0] memory[0:2*N-1];reg seen[0:N-1];
 wire wr_ready=cycles%5!=0;
 wire image_start,image_ready,rd_done,rd_error,rd_valid;
 wire [31:0] image_lba;wire [8:0] rd_addr;wire [7:0] rd_data;
 wire card_start;wire [31:0] card_lba;
 reg card_ready=1,card_done=0,card_error=0,card_valid=0;
 reg [8:0] card_addr=0;reg [7:0] card_data=0;
 reg audio_start=0,audio_busy=0,corrupt=0;
 wire audio_ready,audio_done,audio_error,audio_valid;wire [8:0] audio_addr;wire [7:0] audio_data;
 reg [7:0] fixture[0:3583];
 integer bank,k,sector,slot,pos,value,cluster,base_lba,goal,before_commit;
 function automatic [23:0] color(input integer x,y,id);
  reg [7:0] r,g,b;
  begin r=20+x*7+y*13+id*31;g=30+x*11+y*19+id*37;b=40+x*17+y*23+id*41;color={r,g,b};end
 endfunction
 function automatic [7:0] bmp_byte(input integer id,p);
  integer width,height,size,stride,off,row,col,logical_y;reg [31:0] word;reg [23:0] c;
  begin
   width=id?640:320;height=id?480:240;size=id?SIZE1:SIZE0;stride=width*3;word=0;bmp_byte=0;
   if(p<54)begin
    case(p)
     0:bmp_byte=8'h42;1:bmp_byte=8'h4d;26:bmp_byte=1;28:bmp_byte=24;
     default:begin
      if(p>=2&&p<6)begin word=size;bmp_byte=word>>((p-2)*8);end
      else if(p>=10&&p<14)begin word=54;bmp_byte=word>>((p-10)*8);end
      else if(p>=14&&p<18)begin word=40;bmp_byte=word>>((p-14)*8);end
      else if(p>=18&&p<22)begin word=width;bmp_byte=word>>((p-18)*8);end
      else if(p>=22&&p<26)begin word=id?-height:height;bmp_byte=word>>((p-22)*8);end
      else if(p>=34&&p<38)begin word=stride*height;bmp_byte=word>>((p-34)*8);end
     end
    endcase
   end else if(p<size)begin
    off=p-54;row=off/stride;col=(off%stride)/3;logical_y=id?row:height-1-row;
    c=color(col,logical_y,id);case(off%3)0:bmp_byte=c[7:0];1:bmp_byte=c[15:8];2:bmp_byte=c[23:16];endcase
   end
  end
 endfunction
 media_prefetch_control #(.INTERVAL_CYCLES(50000000)) control(
  .clk(clk),.rst_n(rst_n),.card_ready(1'b1),.load_ready(load_ready),.scan_done(scan_done),
  .image_done(image_done),.error(error),.image_count(image_count),.next_pulse(next_pulse),.prev_pulse(prev_pulse),
  .pause(pause),.front_valid(front_valid),.display_index(display_index),.frame_prepared(frame_prepared),
  .frame_committed(frame_committed),.transition_ready(transition_active),.scan_start(scan_start),
  .load_start(load_start),.image_index(image_index),.commit_enable(commit_enable),
  .discard_cached(discard_cached),.transition_active(transition_active));
 fat32_frame_loader #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.TIMEOUT_CYCLES(50000),.CONTROLLED_SWAP(1)) loader(
  .clk(clk),.rst_n(rst_n),.scan_start(scan_start),.load_start(load_start),.image_index(image_index),
  .load_ready(load_ready),.scan_done(scan_done),.image_done(image_done),.error(error),.image_count(image_count),
  .rd_start(image_start),.rd_lba(image_lba),.rd_ready(image_ready),.rd_done(rd_done),.rd_error(rd_error),
  .rd_addr(rd_addr),.rd_data(rd_data),.rd_valid(rd_valid),.wr_valid(wr_valid),.wr_addr(wr_addr),
  .wr_data(wr_data),.wr_ready(wr_ready),.wr_drained(drain==0),.swap_window(cycles%257==0),
  .front_valid(front_valid),.front_bank(front_bank),.frame_committed(frame_committed),
  .frame_rejected(frame_rejected),.swap_pending(frame_prepared),.commit_enable(commit_enable),
  .discard_cached(discard_cached),.read_valid(1'b0),.read_addr(32'd0),.rgb_ready(1'b1),
  .mem_read_ready(1'b0),.mem_response_valid(1'b0),.mem_response_data(32'd0));
 sd_sector_arbiter arbiter(.clk(clk),.rst_n(rst_n),.card_ready(card_ready),.audio_urgent(cycles[15]),
  .card_done(card_done),.card_error(card_error),.card_addr(card_addr),.card_data(card_data),.card_valid(card_valid),
  .card_start(card_start),.card_lba(card_lba),.image_start(image_start),.image_lba(image_lba),.image_ready(image_ready),
  .image_done(rd_done),.image_error(rd_error),.image_addr(rd_addr),.image_data(rd_data),.image_valid(rd_valid),
  .audio_start(audio_start),.audio_lba(32'd900000),.audio_ready(audio_ready),.audio_done(audio_done),
  .audio_error(audio_error),.audio_addr(audio_addr),.audio_data(audio_data),.audio_valid(audio_valid));
 always @(posedge clk)if(rst_n)begin
  cycles<=cycles+1;audio_start<=0;
  if(audio_cooldown>0)audio_cooldown<=audio_cooldown-1;
  if(audio_ready&&!audio_busy&&audio_cooldown==0)begin audio_start<=1;audio_busy<=1;end
  if(audio_done)begin
   if(audio_error||audio_bytes!=512)$fatal(1,"interleaved/damaged audio sector");
   audio_busy<=0;audio_sectors<=audio_sectors+1;audio_bytes<=0;audio_cooldown<=4095;
  end
  if(audio_valid)begin
   if(audio_addr!==audio_bytes || audio_data!==(audio_bytes&255))$fatal(1,"audio byte ownership");audio_bytes<=audio_bytes+1;
  end
  if(drain>0)drain<=drain-1;
  if(load_start&&load_ready)begin
   loading_index<=image_index;loads<=loads+1;frame_writes<=0;
   $display("PROGRESS scale loader start index=%0d cycle=%0d",image_index,cycles);
   for(integer j=0;j<N;j=j+1)seen[j]=0;
  end
  if(wr_valid&&wr_ready)begin
   if(wr_addr>=2*N || (front_valid&&wr_addr/N==front_bank) || seen[wr_addr%N])$fatal(1,"duplicate/unsafe frame write %0d",wr_addr);
   seen[wr_addr%N]=1;
   if(wr_data!=={8'd0,color(((wr_addr%N)%W)/(loading_index==0?2:1),((wr_addr%N)/W)/(loading_index==0?2:1),loading_index)})$fatal(1,"loader scaled pixel mismatch");
   memory[wr_addr]<=wr_data;writes<=writes+1;frame_writes<=frame_writes+1;drain<=8;
  end
  if(frame_committed)begin
   if(drain!=0||frame_writes!=N)$fatal(1,"partial/undrained commit");
   display_index<=loading_index;commits<=commits+1;
   $display("PROGRESS scale loader commit index=%0d writes=%0d cycle=%0d",loading_index,frame_writes,cycles);
  end
  if(frame_rejected)begin rejections<=rejections+1;$display("PROGRESS scale loader rejected writes=%0d cycle=%0d",frame_writes,cycles);end
 end
 initial forever begin
  @(posedge clk);
  if(rst_n&&card_start)begin
   #1;card_ready=0;requests=requests+1;bank=-1;slot=-1;sector=0;base_lba=0;
   case(card_lba)0:bank=0;2048:bank=1;ROOT_LBA:bank=2;900000:bank=8;
    default:begin
     if(card_lba>=2080&&card_lba<2680)begin bank=3;sector=card_lba-2080;end
     else if(card_lba>=BASE0&&card_lba<BASE0+SECT0)begin slot=0;base_lba=BASE0;end
     else if(card_lba>=BASE1&&card_lba<BASE1+SECT1)begin slot=1;base_lba=BASE1;end
     else $fatal(1,"unexpected scaled-file LBA %0d",card_lba);
    end
   endcase
   repeat(3)@(negedge clk);
   for(k=0;k<512;k=k+1)begin
    card_valid=1;card_addr=k;
    if(slot>=0)card_data=bmp_byte(slot,(card_lba-base_lba)*512+k);
    else if(bank==8)card_data=k;
    else if(bank==3)begin
     cluster=sector*128+k/4;value=32'h0fffffff;
     if(cluster>=5&&cluster<5+CLUST0-1)value=cluster+1;
     if(cluster>=1000&&cluster<1000+CLUST1-1)value=cluster+1;
     card_data=value>>((k%4)*8);
    end else card_data=fixture[bank*512+k];
    @(negedge clk);
   end
   card_valid=0;card_error=corrupt&&slot==0&&card_lba==BASE0+100;
   if(card_error)failed_sectors=failed_sectors+1;
   card_done=1;@(negedge clk);card_done=0;card_error=0;card_ready=1;
  end
 end
 task put32(input integer a,input [31:0] d);begin
  fixture[a]=d;fixture[a+1]=d>>8;fixture[a+2]=d>>16;fixture[a+3]=d>>24;
 end endtask
 task check_front(input integer id);
  reg [23:0] c;
  begin
   if(display_index!=id)$fatal(1,"wrong committed index");
   for(integer j=0;j<N;j=j+1)begin
    c=color((j%W)/(id==0?2:1),(j/W)/(id==0?2:1),id);
    if(memory[front_bank*N+j]!=={8'd0,c})$fatal(1,"front frame contents changed at %0d",j);
   end
  end
 endtask
 task press(input bit back);begin
  @(negedge clk);next_pulse=!back;prev_pulse=back;@(negedge clk);next_pulse=0;prev_pulse=0;
 end endtask
 initial begin
  $readmemh("fixture.hex",fixture);
  fixture[512+13]=SPC;put32(512+32,VOLUME_SECTORS);put32(446+12,VOLUME_SECTORS);
  put32(2*512+28,SIZE0);put32(2*512+32+28,SIZE1);
  fixture[2*512+32+26]=8'he8;fixture[2*512+32+27]=3;
  if(loader.u_image.u_decoder.ALLOW_HALF!=1)$fatal(1,"board loader did not enable runtime scaling");
  repeat(4)@(negedge clk);rst_n=1;
  wait(commits==1);#1;check_front(0);
  wait(frame_prepared);repeat(1024)@(negedge clk);
  if(commits!=1||transition_active)$fatal(1,"scaled cache published without request");
  corrupt=1;press(0);wait(commits==2);#1;check_front(1);
  wait(rejections>0);repeat(20)@(negedge clk);before_commit=commits;press(0);repeat(1000)@(negedge clk);
  if(commits!=before_commit||failed_sectors!=3)$fatal(1,"late CRC error/retries allowed partial scaled frame");
  check_front(1);corrupt=0;press(1);repeat(20)@(negedge clk);press(0);
  wait(commits==3);#1;check_front(0);
  if(audio_sectors<8)$fatal(1,"audio concurrency missing");
  $display("PASS runtime scale loader: commits=%0d loads=%0d writes=%0d rejects=%0d failed_sectors=%0d audio_sectors=%0d requests=%0d cycles=%0d; 320-bottom/640-top/mixed-cache/late-CRC/recovery",commits,loads,writes,rejections,failed_sectors,audio_sectors,requests,cycles);$finish;
 end
 initial begin #300000000;$fatal(1,"scaled loader deadline commits=%0d loads=%0d error=%b requests=%0d",commits,loads,error,requests);end
endmodule
