`timescale 1ns/1ps
module tb_hdmi_audio_pacing;
 reg clk=0,rst_n=0,fifo_empty=0;
 always #20 clk=~clk;
 reg [9:0] x=0;
 wire build=(x==0);
 wire fifo_read,packet_valid;
 wire [23:0] audio_header,aux_header;
 wire [223:0] audio_body,aux_body;
 hdmi_audio_packets dut(.clk(clk),.rst_n(rst_n),.build(build),
  .frame_start(1'b0),.fifo_empty(fifo_empty),
  .fifo_data(48'h123456abcdef),.fifo_read(fifo_read),
  .packet_valid(packet_valid),.audio_header(audio_header),
  .aux_header(aux_header),.audio_body(audio_body),.aux_body(aux_body));
 integer lines=0,reads=0,line_reads=0,silent_packets=0,j;
 always @(posedge clk)begin
  if(!rst_n)x<=0;
  else if(x==799)x<=0;
  else x<=x+1'b1;
  if(rst_n)begin
   if(build)begin
    if(lines>0 && !fifo_empty && (line_reads<1 || line_reads>2))
     $fatal(1,"line %0d consumed %0d samples",lines,line_reads);
    lines=lines+1;line_reads=0;
   end
   if(fifo_read)begin
    if(fifo_empty)$fatal(1,"read from empty FIFO");
    reads=reads+1;line_reads=line_reads+1;
   end
   if(packet_valid && fifo_empty)begin
    if(audio_header[11:8]==0)$fatal(1,"missing silence slots");
    for(j=0;j<4;j=j+1)
     if(audio_header[8+j] && audio_body[j*56 +: 48]!==48'd0)
      $fatal(1,"empty FIFO repeated old sample in slot %0d",j);
    silent_packets=silent_packets+1;
   end
  end
 end
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  wait(lines==126);
  if(reads!=192)$fatal(1,"125 lines consumed %0d samples, expected 192",reads);
  @(negedge clk);fifo_empty=1;
  repeat(8000)@(negedge clk);
  if(reads!=192 || silent_packets<8)
   $fatal(1,"empty FIFO pacing failed reads=%0d silence=%0d",reads,silent_packets);
  $display("PASS HDMI audio pacing: 192 samples per 125 lines; empty FIFO emits silence");
  $finish;
 end
 initial begin #5000000;$fatal(1,"audio pacing timeout");end
endmodule
