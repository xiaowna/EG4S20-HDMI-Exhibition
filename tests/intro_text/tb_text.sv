`timescale 1ns/1ps
`ifdef TEST_NATIVE
`undef __ICARUS__
`endif
module tb_intro_text;
 wire caption_pixel=1'b0;
 wire [5:0] caption_alpha=6'd0;
 parameter N=1;
 reg clk=0,rst_n=0,ce=0,valid_in=0;
 reg [18:0] pixel_addr=0;
 reg [9:0] pixel_x=0;reg [8:0] pixel_y=0;
 reg [23:0] rgb_in=0;reg [1:0] topic=0;
 reg [6:0] text_offset=0;reg [5:0] text_alpha=0;
 wire valid_out;wire [18:0] addr_out;wire [23:0] rgb_out;
 reg [101:0] vectors[0:N-1];
 reg [4:0] expected_valid=0;
 reg [18:0] expected_address[0:4];
 reg [23:0] expected_rgb[0:4];
 reg held_valid;reg [18:0] held_address;reg [23:0] held_rgb;
 integer i,k,checked=0,stalls=0,resets=0;
 reg [31:0] random_state=32'h53a91f0d;
 intro_text_layer dut(.*);
 always #5 clk=~clk;
 task reset_pipeline;
  begin
   @(negedge clk);rst_n=0;ce=0;expected_valid=0;
   repeat(2)begin @(posedge clk);#1;if(valid_out!==0)$fatal(1,"reset did not flush valid");end
   @(negedge clk);rst_n=1;resets=resets+1;
  end
 endtask
 task clock_input;
  input [101:0] vector;
  input enabled;
  begin
   @(negedge clk);
   ce=enabled;
   {valid_in,pixel_addr,text_alpha,text_offset,topic,rgb_in,pixel_y,pixel_x}=vector[77:0];
   held_valid=valid_out;held_address=addr_out;held_rgb=rgb_out;
   @(posedge clk);
   if(enabled)begin
    expected_valid={expected_valid[3:0],valid_in};
    for(k=4;k>0;k=k-1)begin
     expected_address[k]=expected_address[k-1];expected_rgb[k]=expected_rgb[k-1];
    end
    expected_address[0]=pixel_addr;expected_rgb[0]=vector[101:78];
   end
   #1;
   if(valid_out!==expected_valid[4])$fatal(1,"five-enabled-edge valid mismatch at vector %0d",i);
   if(!enabled)begin
    stalls=stalls+1;
    if(valid_out!==held_valid||addr_out!==held_address||rgb_out!==held_rgb)
     $fatal(1,"CE stall changed pipeline output at vector %0d",i);
   end else if(expected_valid[4])begin
    checked=checked+1;
    if(addr_out!==expected_address[4])$fatal(1,"address tag mismatch vector %0d got=%0d expected=%0d",i,addr_out,expected_address[4]);
    if(rgb_out!==expected_rgb[4])$fatal(1,"RGB mismatch vector %0d tag=%0d got=%h expected=%h",i,addr_out,rgb_out,expected_rgb[4]);
   end
  end
 endtask
 initial begin
  $readmemh("vectors.hex",vectors);
  reset_pipeline();
  for(i=0;i<N;i=i+1)begin
   if(i==N/3||i==2*N/3)reset_pipeline();
   random_state=random_state^(random_state<<13);
   random_state=random_state^(random_state>>17);
   random_state=random_state^(random_state<<5);
   if(random_state[0])clock_input(vectors[i],0);
   if(random_state[3:1]==3'b101)repeat(3)clock_input(vectors[i],0);
   clock_input(vectors[i],1);
  end
  for(i=0;i<7;i=i+1)clock_input(102'd0,1);
  $display("PASS intro text checked=%0d vectors=%0d stalls=%0d resets=%0d latency=5 enabled edges",checked,N,stalls,resets);
  $finish;
 end
 initial begin #100000000;$fatal(1,"intro text deadline");end
endmodule
