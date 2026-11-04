`timescale 1ns/1ps
module tb_bmp_counters;
 parameter integer FRAME_WIDTH=3,FRAME_HEIGHT=2;
 localparam integer STRIDE=(FRAME_WIDTH*3+3)/4*4;
 localparam integer IMAGE_BYTES=STRIDE*FRAME_HEIGHT;
 localparam integer PIXELS=FRAME_WIDTH*FRAME_HEIGHT;
 reg clk=0,rst_n=1,start=0;
 always #5 clk=~clk;
 reg [31:0] file_size=0,byte_offset=0;
 reg [7:0] byte_data=0;
 reg byte_valid=0,stream_done=0,stream_error=0,pixel_ready=1;
 wire byte_ready,pixel_valid,busy,done,error;
 wire [31:0] pixel_addr;
 wire [23:0] pixel_rgb;
 wire [60:0] public_outputs={byte_ready,pixel_valid,pixel_addr,pixel_rgb,busy,done,error};
 bmp_stream_decoder #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT)) dut(.*);
`ifdef COMPARE_BASELINE
 wire old_byte_ready,old_pixel_valid,old_busy,old_done,old_error;
 wire [31:0] old_pixel_addr;
 wire [23:0] old_pixel_rgb;
 wire [60:0] old_public={old_byte_ready,old_pixel_valid,old_pixel_addr,old_pixel_rgb,old_busy,old_done,old_error};
 bmp_stream_decoder_baseline #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT)) old(
  .clk(clk),.rst_n(rst_n),.start(start),.file_size(file_size),.byte_data(byte_data),.byte_offset(byte_offset),
  .byte_valid(byte_valid),.byte_ready(old_byte_ready),.stream_done(stream_done),.stream_error(stream_error),
  .pixel_ready(pixel_ready),.pixel_valid(old_pixel_valid),.pixel_addr(old_pixel_addr),.pixel_rgb(old_pixel_rgb),
  .busy(old_busy),.done(old_done),.error(old_error));
`endif
 reg [7:0] image[0:IMAGE_BYTES+255];
 reg active=0,permit_pixels=0,top_down=0,prior_stall=0,accepted=0;
 reg [31:0] previous_addr=0,random_state=32'h7304ac19;
 reg [23:0] previous_rgb=0;
 integer offset=54,total_length=0,pixels=0,done_seen=0,scenarios=0;
 integer cycles=0,total_pixels=0,completions=0,reset_aborts=0,stall_checks=0,last_pixel_holds=0;
 integer expected_addr=0,i;

 function [23:0] rgb;
  input integer address;
  reg [7:0] red,green,blue;
  begin red=address*7+3;green=address*11+5;blue=address*13+9;rgb={red,green,blue};end
 endfunction

 always @(posedge clk) begin
  if(rst_n && active)begin
   if(pixel_valid && !permit_pixels)$fatal(1,"Unexpected pixel scenario=%0d",scenarios);
   if(prior_stall && !(stream_done&&stream_error) &&
      (!pixel_valid || pixel_addr!==previous_addr || pixel_rgb!==previous_rgb))
    $fatal(1,"Pixel moved while stalled scenario=%0d",scenarios);
   if(prior_stall)stall_checks=stall_checks+1;
   if(pixel_valid && pixel_ready)begin
    expected_addr=(top_down?pixels/FRAME_WIDTH:FRAME_HEIGHT-1-pixels/FRAME_WIDTH)*FRAME_WIDTH+pixels%FRAME_WIDTH;
    if(pixels>=PIXELS || pixel_addr!==expected_addr || pixel_rgb!==rgb(expected_addr))
     $fatal(1,"Pixel oracle scenario=%0d pixel=%0d addr=%0d rgb=%h expected=%0d/%h",scenarios,pixels,
            pixel_addr,pixel_rgb,expected_addr,rgb(expected_addr));
    pixels=pixels+1;total_pixels=total_pixels+1;
   end
   prior_stall=pixel_valid&&!pixel_ready&&!(stream_done&&stream_error);
   previous_addr=pixel_addr;previous_rgb=pixel_rgb;
  end else prior_stall=0;
  #1;cycles=cycles+1;
`ifdef COMPARE_BASELINE
  // Include every public bit on every cycle, even invalid/idle/stale values.
  if(public_outputs!==old_public)$fatal(1,"61-bit cycle mismatch scenario=%0d cycle=%0d new=%h old=%h",
                                        scenarios,cycles,public_outputs,old_public);
`endif
  if(rst_n&&active&&done)done_seen=done_seen+1;
 end

 // eof=2 attaches EOF only to an accepted byte, so source stalls are legal.
 task tick(input reg valid,input integer address,input reg [7:0] value,
           input integer eof,input reg failed,input reg ready,input reg begin_again);
  begin
   @(negedge clk);byte_valid=valid;byte_offset=address;byte_data=value;stream_done=0;
   stream_error=failed;pixel_ready=ready;start=begin_again;
   #1;stream_done=(eof==1 || (eof==2&&valid&&byte_ready));
   @(posedge clk);accepted=byte_valid&&byte_ready;#2;
  end
 endtask
 task idle_tick;
  begin tick(0,0,0,0,0,1,0);end
 endtask
 task reset_decoder;
  begin
   active=0;@(negedge clk);rst_n=0;start=0;byte_valid=0;stream_done=0;stream_error=0;pixel_ready=1;
   repeat(3)idle_tick;
   @(negedge clk);rst_n=1;idle_tick;
   if(busy||done||error||pixel_valid||byte_ready)$fatal(1,"Reset public status");
  end
 endtask
 task put32(input integer address,input reg [31:0] value);
  begin image[address]=value[7:0];image[address+1]=value[15:8];image[address+2]=value[23:16];image[address+3]=value[31:24];end
 endtask
 task make_image(input reg top,input integer skip,input integer tail);
  integer p,row,col,address;
  reg [23:0] value;
  begin
   top_down=top;offset=54+skip;total_length=offset+IMAGE_BYTES+tail;
   for(p=0;p<total_length+8;p=p+1)image[p]=8'hc9;
   for(p=0;p<54;p=p+1)image[p]=0;
   image[0]=8'h42;image[1]=8'h4d;put32(2,total_length);put32(10,offset);put32(14,40);put32(18,FRAME_WIDTH);
   put32(22,top?-FRAME_HEIGHT:FRAME_HEIGHT);image[26]=1;image[28]=24;put32(34,IMAGE_BYTES);
   for(row=0;row<FRAME_HEIGHT;row=row+1)for(col=0;col<FRAME_WIDTH;col=col+1)begin
    address=(top?row:FRAME_HEIGHT-1-row)*FRAME_WIDTH+col;value=rgb(address);p=offset+row*STRIDE+col*3;
    image[p]=value[7:0];image[p+1]=value[15:8];image[p+2]=value[23:16];
   end
  end
 endtask
 task begin_file(input reg permitted);
  begin
   if(busy)$fatal(1,"Previous transaction busy");
   file_size=total_length;pixels=0;done_seen=0;permit_pixels=permitted;active=1;prior_stall=0;scenarios=scenarios+1;
   tick(0,0,0,0,0,1,1);
   if(!busy||done||error||pixel_valid)$fatal(1,"Start status");
  end
 endtask
 task finish(input reg failed,input integer expected_pixels);
  integer guard;
  begin
   guard=0;
   while(done_seen==0&&guard<30)begin idle_tick;guard=guard+1;end
   if(done_seen!=1||busy||error!==failed||pixel_valid||pixels!=expected_pixels)
    $fatal(1,"Completion scenario=%0d done=%0d busy=%b error=%b pixels=%0d expected=%0d/%0d",
           scenarios,done_seen,busy,error,pixels,failed,expected_pixels);
   idle_tick;
   if(done||byte_ready||done_seen!=1)$fatal(1,"Completion pulse/idle ready");
   active=0;completions=completions+1;
  end
 endtask
 task send_image(input integer count,input reg eof_same,input reg hold_last,input integer bad_offset);
  integer index,spins,last_red,address;
  reg ready;
  begin
   index=0;spins=0;last_red=offset+(FRAME_HEIGHT-1)*STRIDE+(FRAME_WIDTH-1)*3+2;
   while(index<count)begin
    random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
    ready=random_state[5]||random_state[9];
    if(hold_last&&index==last_red)begin
     // Settle any earlier pixel, then hold exactly the final generated pixel.
     while(pixel_valid)idle_tick;
     tick(1,index,image[index],eof_same&&index==count-1?2:0,0,0,0);
     if(!accepted||!pixel_valid||pixels!=PIXELS-1)$fatal(1,"Final-pixel setup");
     repeat(7)begin
      tick(0,0,0,0,0,0,0);
      if(done_seen||!busy||!pixel_valid||byte_ready)$fatal(1,"Final pixel completed while held");
     end
     last_pixel_holds=last_pixel_holds+1;index=index+1;
    end else begin
     address=(bad_offset>=0&&index==bad_offset)?index+1:index;
     tick(random_state[3:0]!=0,address,image[index],eof_same&&index==count-1?2:0,0,ready,
          index==14||index==offset+1);
     if(accepted)index=index+1;
    end
    spins=spins+1;
    if(done_seen||!busy)$fatal(1,"Premature completion index=%0d",index);
    if(spins>count*8+100)$fatal(1,"Input stalled indefinitely");
   end
   if(!eof_same)tick(0,0,0,1,0,1,0);
  end
 endtask
 task good_file(input reg top,input integer skip,input integer tail,input reg hold_last);
  begin make_image(top,skip,tail);begin_file(1);send_image(total_length,1,hold_last,-1);finish(0,PIXELS);end
 endtask

 initial begin
  reset_decoder;
  // The production 640x480 configuration always decodes a complete frame.
  good_file(0,0,0,1);
  if(FRAME_WIDTH<10)begin
   good_file(1,7,3,1);good_file(0,1,0,0);
   // All input bytes drain after rejection, followed by a clean no-reset start.
   make_image(0,0,0);image[0]=0;begin_file(0);
   send_image(total_length,1,0,-1);finish(1,0);good_file(1,0,0,1);
   make_image(0,0,0);begin_file(0);
   send_image(total_length,1,0,10);finish(1,0);
   make_image(0,0,0);begin_file(1);
   send_image(offset+2,1,0,-1);finish(1,0);
   // stream_error alone must not be interpreted as a transport completion.
   make_image(0,0,0);begin_file(1);tick(0,0,0,0,1,1,0);
   send_image(total_length,1,1,-1);finish(0,PIXELS);
   // Transport abort with a verified pixel held at the output.
   make_image(0,0,0);begin_file(1);
   for(i=0;i<54;i=i+1)tick(1,i,image[i],0,0,1,0);
   idle_tick;
   for(i=54;i<57;i=i+1)tick(1,i,image[i],0,0,0,0);
   if(!pixel_valid)$fatal(1,"Expected held first pixel");
   repeat(4)tick(0,0,0,0,0,0,0);
   tick(0,0,0,1,1,0,0);finish(1,0);good_file(1,0,0,0);
   // Reset the same pending pixel, then verify all counters restart cleanly.
   make_image(0,0,0);begin_file(1);
   for(i=0;i<54;i=i+1)tick(1,i,image[i],0,0,1,0);
   idle_tick;
   for(i=54;i<57;i=i+1)tick(1,i,image[i],0,0,0,0);
   if(!pixel_valid)$fatal(1,"Expected pending pixel before reset");
   reset_aborts=reset_aborts+1;reset_decoder;good_file(0,0,0,1);
  end
  $display("PASS BMP counters %0dx%0d pad=%0d scenarios=%0d completions=%0d reset_aborts=%0d pixels=%0d last_holds=%0d stall_checks=%0d cycles=%0d public_bits=61",
           FRAME_WIDTH,FRAME_HEIGHT,STRIDE-FRAME_WIDTH*3,scenarios,completions,reset_aborts,total_pixels,
           last_pixel_holds,stall_checks,cycles);
  $finish;
 end
 initial begin #100000000;$fatal(1,"BMP counter regression deadline");end
endmodule
