`timescale 1ns/1ps
// 元数据长度、RIFF 声明、chunk 头、数据和 padding 分别独立越界。
module tb_wav_bounds;
 reg clk=0,rst_n=0,start=0,valid=0;
 reg [7:0] byte_data=0;
 reg [31:0] file_size=48;
 wire byte_ready,sample_valid,playing,error,data_done;
 wire [47:0] sample_data;
 integer mode=0,i,samples=0,limit=48;
 reg [7:0] bytes[0:63];
 always #5 clk=~clk;
 wav_pcm_decoder dut(.clk(clk),.rst_n(rst_n),.start(start),.file_size(file_size),
  .byte_valid(valid),.byte_data(byte_data),.byte_ready(byte_ready),
  .sample_valid(sample_valid),.sample_ready(1'b1),.sample_data(sample_data),
  .playing(playing),.error(error),.data_done(data_done));
 always @(posedge clk)if(rst_n && sample_valid)samples=samples+1;
 initial begin
  if(!$value$plusargs("MODE=%d",mode))mode=0;
  for(i=0;i<64;i=i+1)bytes[i]=0;
  bytes[0]="R";bytes[1]="I";bytes[2]="F";bytes[3]="F";bytes[4]=40;
  bytes[8]="W";bytes[9]="A";bytes[10]="V";bytes[11]="E";
  bytes[12]="f";bytes[13]="m";bytes[14]="t";bytes[15]=" ";bytes[16]=16;
  bytes[20]=1;bytes[22]=2;bytes[24]=8'h80;bytes[25]=8'hbb;
  bytes[29]=8'hee;bytes[30]=2;bytes[32]=4;bytes[34]=16;
  bytes[36]="d";bytes[37]="a";bytes[38]="t";bytes[39]="a";bytes[40]=4;
  case(mode)
   1:bytes[4]=12; // 原缺陷：RIFF 声明 12 字节，实际输入 48 字节。
   2:file_size=47; // 实际文件短于 RIFF 声明。
   3:bytes[4]=8; // 剩余空间不足容纳 chunk 头。
   4:bytes[40]=8; // data 超出 RIFF 边界。
   5:begin // JUNK 数据能放下，但奇数字节 padding 放不下。
    bytes[12]="J";bytes[13]="U";bytes[14]="N";bytes[15]="K";
    bytes[16]=3;bytes[4]=15;file_size=23;limit=23;
   end
   6:begin bytes[4]=8'hff;bytes[5]=8'hff;bytes[6]=8'hff;bytes[7]=8'hff;end
   7:begin bytes[40]=8'hff;bytes[41]=8'hff;bytes[42]=8'hff;bytes[43]=8'hff;end
   8:begin file_size=56;end // RIFF 外尾随数据允许存在，不进入音频 data。
   9:begin bytes[4]=3;end // RIFF 连 WAVE 标识都容纳不了。
   10:begin file_size=11;limit=11;end
   default:;
  endcase
  repeat(3)@(negedge clk);rst_n=1;
  @(negedge clk);start=1;@(negedge clk);start=0;
  for(i=0;i<limit;i=i+1)begin
   @(negedge clk);valid=1;byte_data=bytes[i];
   @(posedge clk);while(!byte_ready && !error && !data_done)@(posedge clk);
   @(negedge clk);valid=0;
   if(error || data_done)i=limit;
  end
  repeat(4)@(negedge clk);
  if(mode==0 || mode==8)begin
   if(error || !data_done || samples!=1)$fatal(1,"valid RIFF rejected mode=%0d",mode);
  end else if(!error || samples!=0)$fatal(1,"malformed RIFF accepted mode=%0d samples=%0d",mode,samples);
  $display("PASS WAV bounds mode=%0d samples=%0d",mode,samples);$finish;
 end
 initial begin #20000;$fatal(1,"WAV bounds timeout mode=%0d",mode);end
endmodule
