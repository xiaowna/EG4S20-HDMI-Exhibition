`timescale 1ns/1ps
module tb_wav_fields;
 reg clk=0,rst_n=0,start=0,byte_valid=0,sample_ready=1;
 reg [31:0] file_size=128;reg [7:0] byte_data=0;
 wire byte_ready,sample_valid,playing,error,data_done;wire [47:0] sample_data;
 reg [7:0] fmt[0:39];reg [31:0] rng=32'h45830;
 integer c,p,v,n,i,ready_cycles=0,cases=0;
 always #5 clk=~clk;
 always @(negedge clk)begin ready_cycles=ready_cycles+1;sample_ready=(ready_cycles%7!=0);end
 wav_pcm_decoder dut(.*);
 task send;
  input [7:0] b;
  begin
   @(negedge clk);byte_data=b;byte_valid=1;
   @(posedge clk);while(!byte_ready)@(posedge clk);
   @(negedge clk);byte_valid=0;
  end
 endtask
 task prefix;
  input integer ext;
  begin
   @(negedge clk);start=1;@(negedge clk);start=0;
   send("R");send("I");send("F");send("F");send(120);send(0);send(0);send(0);
   send("W");send("A");send("V");send("E");
   send("f");send("m");send("t");send(" ");send(ext?40:16);send(0);send(0);send(0);
  end
 endtask
 task run_case;
  input integer cfg,field,value,field2,value2;
  integer j,width,ext;reg expected_common;
  begin
   width=cfg[0]?24:16;ext=cfg[1];
   for(j=0;j<40;j=j+1)fmt[j]=0;
   fmt[0]=ext?8'hfe:1;fmt[1]=ext?8'hff:0;fmt[2]=2;
   fmt[4]=8'h80;fmt[5]=8'hbb;fmt[9]=cfg[0]?8'h65:8'hee;
   fmt[10]=cfg[0]?4:2;fmt[12]=cfg[0]?6:4;fmt[14]=width;
   fmt[16]=22;fmt[18]=width;fmt[20]=3;fmt[24]=1;
   fmt[30]=8'h10;fmt[32]=8'h80;fmt[35]=8'haa;fmt[37]=8'h38;fmt[38]=8'h9b;fmt[39]=8'h71;
   if(field>=0)fmt[field]=value;
   if(field2>=0)fmt[field2]=value2;
   expected_common=fmt[2]==2&&fmt[3]==0&&fmt[4]==8'h80&&fmt[5]==8'hbb&&fmt[6]==0&&fmt[7]==0;
   prefix(ext);
   for(j=0;j<(ext?40:16);j=j+1)send(fmt[j]);
   send("d");send("a");send("t");send("a");send(12);send(0);send(0);send(0);
   for(j=0;j<12;j=j+1)send(j*37+13);
   repeat(4)@(negedge clk);
   if(!expected_common&&(!error||playing||sample_valid))$fatal(1,"unsupported channel/rate accepted");
   if(field<0&&field2<0&&(error||!playing))$fatal(1,"valid PCM rejected");
   cases=cases+1;
  end
 endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  for(c=0;c<4;c=c+1)begin
   run_case(c,-1,0,-1,0);
   for(p=0;p<(c[1]?20:16);p=p+1)
    for(v=0;v<256;v=v+1)run_case(c,p,v,-1,0);
  end
  for(n=0;n<1024;n=n+1)begin
   rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);
   c=rng%4;p=(rng>>8)%(c[1]?20:16);
   run_case(c,p,rng[7:0],(rng>>20)%(c[1]?20:16),rng[23:16]);
  end
  for(c=0;c<4;c=c+1)begin
   prefix(1);for(i=0;i<c+1;i=i+1)send(8'hff);
   if(c[0])begin @(negedge clk);rst_n=0;@(negedge clk);rst_n=1;end
   run_case(c,-1,0,-1,0);
  end
  // Abort throughout common-field parsing, then restart without a reset.
  for(c=0;c<4;c=c+1)for(n=0;n<8;n=n+1)begin
   prefix(c[1]);for(i=0;i<=n;i=i+1)send(8'hff);
   if(n[0])begin @(negedge clk);rst_n=0;@(negedge clk);rst_n=1;end
   run_case(c,-1,0,-1,0);
  end
  $display("PASS WAV field oracle: %0d cases; every value of each checked header byte, four PCM formats, combined corruptions, restart/reset and backpressure",cases);
  $finish;
 end
 initial begin #100000000;$fatal(1,"WAV field timeout");end
endmodule
