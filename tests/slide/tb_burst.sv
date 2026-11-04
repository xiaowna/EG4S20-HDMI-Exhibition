`timescale 1ns/1ps
// Physical source addresses are checked against a per-pixel geometry oracle.
module tb_slide_burst #(parameter W=640,H=3,MAX_BURST=32);
 localparam N=W*H;
 reg sys_clk=0,pix_clk=0,rst_n=0,start=0,slide_active=0,slide_right=0;
 reg [15:0] slide_offset=0;
 reg [31:0] frame_base=0,burst_data=0;
 reg burst_data_valid=0,burst_last=0,burst_error=0;
 wire start_ready,busy,done,error,burst_valid,pixel_valid,pixel_last;
 wire [31:0] burst_addr,pixel_addr;wire [8:0] burst_words;wire [23:0] pixel_rgb;
 integer cycles=0,pixels=0,cases=0,commands=0,response=0,length=0;
 reg [31:0] command_address=0;
 reg responding=0;
 wire burst_ready=!responding && cycles%7!=0;
 wire pixel_ready=cycles%11!=0;
 always #10 sys_clk=~sys_clk;always #20 pix_clk=~pix_clk;
 always @(posedge sys_clk)cycles<=cycles+1;
 function automatic [23:0] color(input integer a);
  begin color=(a*37)^(a<<7)^24'h5a39c7;end
 endfunction
 frame_burst_prefetch #(.FRAME_PIXELS(N),.MAX_BURST(MAX_BURST),.FIFO_ADDR_BITS(6),
  .SLIDE_TRANSITIONS(1),.LINE_PIXELS(W)) dut(.intro_active(1'b0),.intro_topic(2'd0),.intro_phase(6'd0),.slide_alpha(6'd32),.*);
 always @(negedge sys_clk)begin
  burst_data_valid=0;burst_last=0;
  if(responding)begin
   if(cycles%5!=0)begin
    burst_data_valid=1;burst_data={8'd0,color(command_address+response)};
    burst_last=response==length-1;response=response+1;
    if(response==length)responding=0;
   end
  end
 end
 always @(posedge sys_clk)if(rst_n&&burst_valid&&burst_ready)begin
  if(burst_words==0||burst_words>MAX_BURST||burst_addr+burst_words>2*N||
     burst_addr[7:0]+burst_words>256)$fatal(1,"bad/bank-crossing SDRAM command");
  if(burst_addr/N!=(burst_addr+burst_words-1)/N)$fatal(1,"burst crosses frame bank");
  command_address=burst_addr;length=burst_words;response=0;responding=1;commands=commands+1;
 end
 integer x,y,sx,bank,expected_address;
 always @(posedge pix_clk)if(rst_n&&pixel_valid&&pixel_ready)begin
  x=pixels%W;y=pixels/W;bank=frame_base/N;sx=x;
  if(slide_active&&slide_offset!=0)begin
   if(slide_right)begin
    if(x<slide_offset)begin bank=1-bank;sx=x+W-slide_offset;end
    else sx=x-slide_offset;
   end else begin
    if(x<W-slide_offset)sx=x+slide_offset;
    else begin bank=1-bank;sx=x-(W-slide_offset);end
   end
  end
  expected_address=bank*N+y*W+sx;
  if(pixel_addr!==pixels||pixel_rgb!==color(expected_address)||pixel_last!==(pixels==N-1))
   $fatal(1,"slide geometry w=%0d base=%0d right=%b d=%0d pixel=%0d expected_src=%0d got=%h expected=%h",W,frame_base,slide_right,slide_offset,pixels,expected_address,pixel_rgb,color(expected_address));
  pixels=pixels+1;
 end
 task check(input integer bank_id,right,d,active);
  begin
   wait(start_ready);@(negedge sys_clk);frame_base=bank_id*N;slide_right=right;slide_offset=d;slide_active=active;pixels=0;
   start=1;@(negedge sys_clk);start=0;wait(done);@(negedge sys_clk);
   if(error||pixels!=N)$fatal(1,"incomplete sliding frame");cases=cases+1;
  end
 endtask
 task reject(input integer bad_base,bad_offset);
  integer before_commands;
  begin
   @(negedge sys_clk);rst_n=0;repeat(4)@(negedge sys_clk);rst_n=1;
   wait(start_ready);@(negedge sys_clk);frame_base=bad_base;slide_active=1;
   slide_offset=bad_offset;before_commands=commands;start=1;
   @(negedge sys_clk);start=0;repeat(8)@(negedge sys_clk);
   if(!error || busy || done || commands!=before_commands || pixel_valid)
    $fatal(1,"invalid slide issued memory command base=%0d d=%0d",bad_base,bad_offset);
  end
 endtask
 integer distances[0:9];
 initial begin
  repeat(4)@(negedge sys_clk);rst_n=1;
  distances[0]=0;distances[1]=1;distances[2]=W-1;distances[3]=W/2;
  distances[4]=W/3;distances[5]=(W>33)?31:1;distances[6]=(W>33)?32:1;
  distances[7]=(W>257)?255:1;distances[8]=(W>257)?256:1;distances[9]=(W>257)?257:1;
  for(integer b=0;b<2;b=b+1)begin
   check(b,0,0,0);
   for(integer r=0;r<2;r=r+1)for(integer i=0;i<10;i=i+1)check(b,r,distances[i],1);
  end
  reject(0,W);reject(N,W+1);reject(1,1);reject(2097152,1);
  $display("PASS slide burst W=%0d H=%0d MAX_BURST=%0d cases=%0d pixels=%0d commands=%0d cycles=%0d; independent coordinates/both banks/directions/256-word rows/FIFO stalls/invalid addresses",W,H,MAX_BURST,cases,cases*N,commands,cycles);$finish;
 end
 initial begin #2000000000;$fatal(1,"slide burst timeout");end
endmodule
