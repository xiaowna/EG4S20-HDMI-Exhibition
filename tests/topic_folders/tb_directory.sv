`timescale 1ns/1ps
module tb_topic_directory;
 reg clk=0,rst_n=0,start=0,rd_valid=0,rd_done=0,rd_error=0;
 reg [8:0] rd_addr=0;reg [7:0] rd_data=0,spc=1;reg [31:0] data_base=1000;
 reg [1:0] wav_index=0;reg [2:0] home_index=0;
 wire rd_start,busy,done,error,found_valid,wav_found;
 wire [31:0] rd_lba,found_cluster,found_size,wav_cluster,wav_size;
 wire [4:0] found_index,found_count,first_image;wire [5:0] image_limit;
 wire [2:0] wav_count;wire [24:0] folder_info;wire [1:0] music_index;
 reg [7:0] directory[0:65535],fat[0:511];
 reg responding=0;integer address=0,position=0,delay=0,requests=0,mode=0;
 integer counts[0:3],expected_cluster[0:23],actual_cluster[0:23],actual_size[0:23];
 integer total=0,provisional=0,checked=0,expected_error=0;
 always #5 clk=~clk;
 // The cached range predicate must equal the original check at every consume.
 always @(negedge clk)if(rst_n&&dut.state==5&&!dut.read_fat&&dut.pos[4:0]==31)
  if(dut.entry_cluster_in_bounds!==(dut.entry_cluster>=2&&dut.entry_cluster<dut.data_cluster_end))
   $fatal(1,"cached entry cluster bound differs at directory consumption");
 fat32_dir_scan #(.MAX_FILES(24),.FIND_WAV(1),.MAX_WAVS(4),.TOPIC_FOLDERS(1),
  .MAX_DIR_CLUSTERS(4),.TIMEOUT_CYCLES(2500)) dut(
  .clk(clk),.rst_n(rst_n),.start(start),.root_lba(32'd1000),.sectors_per_cluster(spc),
  .fat_lba(32'd20),.data_lba(data_base),.root_cluster(32'd2),.cluster_count(32'd1000),
  .rd_ready(!responding),.rd_done(rd_done),.rd_error(rd_error),.rd_start(rd_start),.rd_lba(rd_lba),
  .rd_addr(rd_addr),.rd_data(rd_data),.rd_valid(rd_valid),.found_valid(found_valid),
  .found_index(found_index),.found_first_cluster(found_cluster),.found_size(found_size),
  .busy(busy),.done(done),.error(error),.found_count(found_count),.wav_found(wav_found),
  .wav_first_cluster(wav_cluster),.wav_size(wav_size),.wav_index(wav_index),.wav_count(wav_count),.folder_info(folder_info));
 home_album_config #(.TOPIC_FOLDERS(1)) home(.index(home_index),.first_image(first_image),
  .image_limit(image_limit),.music_index(music_index),.folder_info(folder_info));
 task tick;begin @(negedge clk);#1;end endtask
 function integer sector(input integer cluster);sector=(cluster-2)*spc;endfunction
 task link(input integer cluster,input integer next_cluster);
  begin for(integer j=0;j<4;j=j+1)fat[cluster*4+j]=(next_cluster>>(j*8))&255;end
 endtask
 task entry(input integer sector_index,input integer number,input [87:0] name,
  input integer attribute,input integer cluster,input integer size);
  integer a;
  begin a=sector_index*512+number*32;
   for(integer j=0;j<32;j=j+1)directory[a+j]=0;
   for(integer j=0;j<11;j=j+1)directory[a+j]=(name>>((10-j)*8))&255;
   directory[a+11]=attribute;directory[a+20]=(cluster>>16)&255;directory[a+21]=(cluster>>24)&15;
   directory[a+26]=cluster&255;directory[a+27]=(cluster>>8)&255;
   for(integer j=0;j<4;j=j+1)directory[a+28+j]=(size>>(j*8))&255;
  end
 endtask
 task deleted_tail(input integer s,input integer from);
  begin for(integer j=from;j<16;j=j+1)directory[s*512+j*32]=8'he5;end
 endtask
 task root_music(input integer s,input integer at);
  begin for(integer j=0;j<4;j=j+1)entry(s,at+j,"MUSIC1  WAV"+(j<<40),32,200+j,1000+j);end
 endtask
 task folders(input integer s,input integer at);
  begin
   entry(s,at,"TOPIC3     ",16,9,0);entry(s,at+1,"TOPIC1     ",16,5,0);
   entry(s,at+2,"TOPIC4     ",16,11,0);entry(s,at+3,"TOPIC2     ",16,7,0);
  end
 endtask
 task fill_topics;
  integer s,n;
  begin total=0;
   for(integer g=0;g<4;g=g+1)begin
    s=sector(5+g*2);
    // Real directories include dot entries, which must never be BMPs.
    entry(s,0,".          ",16,5+g*2,0);entry(s,1,"..         ",16,0,0);
    entry(s,2,"PRIVATE WAV",32,400+g,1234);
    for(integer i=0;i<counts[g];i=i+1)begin
     entry(s,3+i,"PIC01   BMP"+(i<<48),32,100+g*10+i,60+g*10+i);
     if(i<6)begin expected_cluster[total]=100+g*10+i;total=total+1;end
    end
   end
  end
 endtask
 always @(posedge clk)if(rst_n)begin
  if(rd_start)begin
   if(responding)$fatal(1,"directory overlaps card requests");
   if(rd_lba!=20&&(rd_lba<1000||rd_lba>=1128))$fatal(1,"out-of-volume test request %h",rd_lba);
   responding=1;address=rd_lba;position=0;delay=3;requests=requests+1;
  end
  if(found_valid)begin
   if(found_index>=24)$fatal(1,"metadata index exceeds24");
   actual_cluster[found_index]=found_cluster;actual_size[found_index]=found_size;provisional=provisional+1;
  end
 end
 always @(negedge clk)begin
  rd_valid=0;rd_done=0;rd_error=0;
  if(responding&&!(mode==13&&address!=1000))begin
   if(delay>0)delay=delay-1;
   else if(position<((mode==12&&address!=1000)?511:512))begin
    rd_valid=1;rd_addr=(mode==11&&address!=1000&&position==100)?99:position;
    rd_data=(address==20)?fat[position]:directory[(address-1000)*512+position];position=position+1;
   end else begin rd_done=1;rd_error=(mode==10&&address!=1000);responding=0;end
  end
 end
 task configure(input integer m);
  begin
   rst_n=0;start=0;responding=0;rd_valid=0;rd_done=0;mode=m;spc=(m==7)?2:1;
   data_base=(m==14)?32'hffffff00:1000;if(m==14)spc=128;
   for(integer j=0;j<65536;j=j+1)directory[j]=0;
   for(integer j=0;j<512;j=j+1)fat[j]=0;
   for(integer j=2;j<100;j=j+1)link(j,32'h0fffffff);
   for(integer j=0;j<24;j=j+1)begin actual_cluster[j]=0;actual_size[j]=0;end
   requests=0;provisional=0;expected_error=m>=8&&m<=16;
   counts[0]=6;counts[1]=6;counts[2]=6;counts[3]=6;
   if(m==2||m==3)begin counts[0]=2;counts[1]=0;counts[2]=3;counts[3]=1;end
   if(m==4)begin counts[0]=0;counts[1]=0;counts[2]=2;counts[3]=0;end
   if(m==5||m==7||m==15||m==16)begin counts[0]=2;counts[1]=0;counts[2]=0;counts[3]=0;end
   if(m==18)begin counts[0]=7;counts[1]=0;counts[2]=0;counts[3]=0;end
   if(m==20)begin counts[0]=0;counts[1]=0;counts[2]=0;counts[3]=0;end
   if(m!=14)fill_topics;
   entry(0,0,"OLD01   BMP",32,300,77);entry(0,1,"OLD02   BMP",32,301,78);
   root_music(0,2);folders(0,6);
   if(m==0||m==17)begin
    entry(0,6,"OLD03   BMP",32,302,79);directory[7*32]=0;total=3;
    for(integer j=0;j<3;j=j+1)expected_cluster[j]=300+j;
    if(m==17)begin entry(0,7,"TOPIC1     ",15,5,0);entry(0,8,"TOPIC2     ",24,7,0);directory[9*32]=0;end
   end
   if(m==3)entry(0,9,"NOTOPIC    ",16,7,0);
   if(m==4)begin
    entry(0,6,"TOPIC3     ",16,9,0);directory[7*32]=0;
   end
   if(m==5||m==7||m==15||m==16)begin
    entry(sector(5),0,"PIC01   BMP",32,100,60);deleted_tail(sector(5),1);
    if(m==7)entry(sector(5)+1,0,"PIC02   BMP",32,101,61);
    else begin
     link(5,17);entry(sector(17),0,"PIC02   BMP",32,101,61);
     if(m==15)begin deleted_tail(sector(17),1);link(17,5);end
     if(m==16)begin
      deleted_tail(sector(17),1);link(17,18);link(18,19);link(19,20);
      deleted_tail(sector(18),0);deleted_tail(sector(19),0);deleted_tail(sector(20),0);
     end
    end
   end
   if(m==6)begin
    for(integer j=0;j<16;j=j+1)entry(0,j,"ROOT00  BMP"+(j<<40),32,300+j,80+j);
    link(2,23);link(23,24);
    for(integer j=0;j<8;j=j+1)entry(sector(23),j,"ROOT00  BMP"+(j<<40),32,316+j,96+j);
    root_music(sector(23),8);deleted_tail(sector(23),12);folders(sector(24),0);
   end
   if(m==8)entry(0,10,"TOPIC1     ",16,13,0);
   if(m==9)entry(0,7,"TOPIC1     ",16,1,0);
   if(m==19)begin
    entry(0,7,"topic1     ",18,5,0);
    entry(sector(5),3,"PIC01   bmp",34,100,60);
   end
   repeat(3)tick;rst_n=1;tick;start=1;tick;start=0;
  end
 endtask
 integer expected_start,expected_end;
 initial begin
  for(integer m=0;m<=20;m=m+1)begin
   configure(m);wait(done);#1;
   if(error!==expected_error)$fatal(1,"folder mode%0d error=%b expected=%b count=%0d state=%0d",m,error,expected_error,found_count,dut.state);
   if(expected_error)begin
    if(folder_info[24])$fatal(1,"failed scan advertises committed folder metadata");
   end else begin
    if(found_count!=total||wav_count!=4)$fatal(1,"counts mode%0d photos=%0d expected=%0d songs=%0d",m,found_count,total,wav_count);
    for(integer j=0;j<total;j=j+1)begin
     if(actual_cluster[j]!=expected_cluster[j])$fatal(1,"group/order mode%0d slot%0d got%0d expected%0d",m,j,actual_cluster[j],expected_cluster[j]);
     if(actual_size[j]!=((m==0||m==17)?77+j:expected_cluster[j]-40))$fatal(1,"file size metadata mode%0d slot%0d",m,j);
    end
    if(m!=0&&m!=17)begin
     if(!folder_info[24])$fatal(1,"folder scan fell back to root");
     expected_start=0;
     for(integer g=0;g<4;g=g+1)begin
      expected_end=expected_start+((counts[g]>6)?6:counts[g]);home_index=g;tick;
      if(first_image!=expected_start||image_limit!=expected_end)$fatal(1,"home range mode%0d group%0d %0d..%0d expected%0d..%0d",m,g,first_image,image_limit,expected_start,expected_end);
      expected_start=expected_end;
     end
    end else if(folder_info!=0)$fatal(1,"flat fallback metadata nonzero");
    for(integer j=0;j<4;j=j+1)begin wav_index=j;repeat(3)tick;
     if(wav_cluster!=200+j||wav_size!=1000+j)$fatal(1,"subdirectory music polluted shared root playlist");
    end
   end
   checked=checked+1;$display("PASS folder case%0d count=%0d error=%b requests=%0d provisional=%0d info=%h",m,found_count,error,requests,provisional,folder_info);
  end
  $display("PASS topic directories %0d cases: flat fallback, root priority, four groups, empty/missing/unequal groups, fragmented root/subdirectories, multi-sector clusters, root-only music, late folders, cap6, CRC/order/length/timeout/bounds/cycle failures",checked);$finish;
 end
 initial begin #100000000;$fatal(1,"folder regression timeout mode%0d",mode);end
endmodule
