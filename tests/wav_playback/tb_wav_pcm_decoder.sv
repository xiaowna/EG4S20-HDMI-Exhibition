`timescale 1ns/1ps
module tb_wav_pcm_decoder;
 reg clk=0,rst_n=0,start=0,valid=0,ready=1;reg [7:0] byte_data=0;
 always #5 clk=~clk;
 wire byte_ready,sample_valid,playing,error;wire [47:0] sample_data;
 reg [31:0] file_size=64;
 wav_pcm_decoder dut(.clk(clk),.rst_n(rst_n),.start(start),.byte_valid(valid),
  .file_size(file_size),
  .byte_data(byte_data),.byte_ready(byte_ready),.sample_valid(sample_valid),
  .sample_ready(ready),.sample_data(sample_data),.playing(playing),.error(error));
 integer count=0;reg [47:0] golden[0:5];
 always @(posedge clk)if(rst_n&&sample_valid&&ready)begin
  if(count>5||sample_data!==golden[count])$fatal(1,"PCM[%0d] got=%h expected=%h",count,sample_data,golden[count]);
  count=count+1;
 end
 task send(input [7:0] v);begin
  @(negedge clk);byte_data=v;valid=1;
  @(posedge clk);while(!byte_ready)@(posedge clk);
  @(negedge clk);valid=0;
 end endtask
 task fmt_ext(input [7:0] subformat0);begin
  send(8'h66);send(8'h6d);send(8'h74);send(8'h20);
  send(40);send(0);send(0);send(0);
  send(8'hfe);send(8'hff);send(2);send(0);
  send(8'h80);send(8'hbb);send(0);send(0);
  send(0);send(8'h65);send(4);send(0);
  send(6);send(0);send(24);send(0);
  send(22);send(0);send(24);send(0);
  send(3);send(0);send(0);send(0);
  send(subformat0);send(0);send(0);send(0);
  send(0);send(0);send(8'h10);send(0);
  send(8'h80);send(0);send(0);send(8'haa);
  send(0);send(8'h38);send(8'h9b);send(8'h71);
 end endtask
 task riff;begin
  send(8'h52);send(8'h49);send(8'h46);send(8'h46);
  send(file_size-8);send(0);send(0);send(0);
  send(8'h57);send(8'h41);send(8'h56);send(8'h45);
 end endtask
 task fmt(input [7:0] width,input [7:0] align,input [7:0] rate0,rate1,
          input integer extension_bytes);begin
  send(8'h66);send(8'h6d);send(8'h74);send(8'h20);
  send(16+extension_bytes);send(0);send(0);send(0);
  send(1);send(0);send(2);send(0);
  send(rate0);send(rate1);send(0);send(0);
  if(width==16)begin send(0);send(8'hee);send(2);send(0);end
  else begin send(0);send(8'h65);send(4);send(0);end
  send(align);send(0);send(width);send(0);
  repeat(extension_bytes)send(8'hff);
 end endtask
 task data_header(input [7:0] size);begin
  send(8'h64);send(8'h61);send(8'h74);send(8'h61);
  send(size);send(0);send(0);send(0);
 end endtask
 task restart;begin
  @(negedge clk);start=1;@(negedge clk);start=0;
 end endtask
 initial begin
  golden[0]=48'h123400fedc00;golden[1]=48'h000100800000;
  golden[2]=48'h332211665544;golden[3]=48'h800000ffffff;
  golden[4]=48'h123400fedc00;golden[5]=48'h332211665544;
  repeat(4)@(negedge clk);rst_n=1;restart;
  send(8'h52);send(8'h49);send(8'h46);send(8'h46);
  send(file_size-8);send(0);send(0);send(0);
  send(8'h57);send(8'h41);send(8'h56);send(8'h00);
  repeat(3)@(negedge clk);
  if(!error)$fatal(1,"invalid WAVE form accepted");
  file_size=64;restart;riff;
  // Unknown odd-sized chunk must skip its padding byte.
  send(8'h4a);send(8'h55);send(8'h4e);send(8'h4b);
  send(3);send(0);send(0);send(0);
  send(8'haa);send(8'hbb);send(8'hcc);send(0);
  fmt(16,4,8'h80,8'hbb,0);data_header(8);
  send(8'h34);send(8'h12);send(8'hdc);
  ready=0;send(8'hfe);
  @(negedge clk);byte_data=1;valid=1;
  repeat(4)begin @(posedge clk);if(byte_ready||!sample_valid||sample_data!==golden[0])
    $fatal(1,"backpressure lost sample");end
  @(negedge clk);ready=1;
  @(posedge clk);@(negedge clk);valid=0;
  send(0);send(0);send(8'h80);
  repeat(6)@(negedge clk);
  if(count!=2||!playing||error)$fatal(1,"16-bit WAV failed");
  file_size=56;restart;riff;fmt(24,6,8'h80,8'hbb,0);data_header(12);
  send(8'h11);send(8'h22);send(8'h33);send(8'h44);send(8'h55);send(8'h66);
  send(0);send(0);send(8'h80);send(8'hff);send(8'hff);send(8'hff);
  repeat(6)@(negedge clk);
  if(count!=4||!playing||error)$fatal(1,"24-bit WAV failed");
  file_size=72;restart;riff;fmt(16,4,8'h80,8'hbb,24);data_header(4);
  send(8'h34);send(8'h12);send(8'hdc);send(8'hfe);
  repeat(6)@(negedge clk);
  if(count!=5||!playing||error)$fatal(1,"extended PCM fmt chunk failed count=%0d playing=%0b error=%0b",count,playing,error);
  file_size=74;restart;riff;fmt_ext(8'h01);data_header(6);
  send(8'h11);send(8'h22);send(8'h33);send(8'h44);send(8'h55);send(8'h66);
  repeat(6)@(negedge clk);
  if(count!=6||!playing||error)$fatal(1,"PCM extensible failed count=%0d",count);
  restart;riff;fmt_ext(8'h03);data_header(6);
  repeat(3)@(negedge clk);
  if(!error||playing)$fatal(1,"non-PCM extensible accepted");
  restart;riff;fmt(16,4,8'h44,8'hac,0);
  // Unsupported sample rate is rejected when data chunk begins.
  data_header(4);repeat(3)@(negedge clk);
  if(!error||playing)$fatal(1,"unsupported rate accepted");
  $display("PASS WAV parser: RIFF, padding, 16/24-bit PCM, PCM extensible, invalid GUID/rate");$finish;
 end
 initial begin #200000;$fatal(1,"timeout");end
endmodule
