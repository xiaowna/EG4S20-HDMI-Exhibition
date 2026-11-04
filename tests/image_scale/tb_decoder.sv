`timescale 1ns/1ps
// Black-box nearest-neighbor oracle: every target address is visited once and
// its color is computed from logical source x/y, independently of write order.
module tb_bmp_scale;
 parameter integer W=6,H=4;
 localparam MAX_BYTES=W*H*3+256;
 reg clk=0,rst_n=0,start=0,byte_valid=0,stream_done=0,stream_error=0,pixel_ready=1;
 reg [31:0] file_size=0,byte_offset=0;
 reg [7:0] byte_data=0;
 wire byte_ready,pixel_valid,busy,done,error;
 wire [31:0] pixel_addr;wire [23:0] pixel_rgb;
 always #5 clk=~clk;
 bmp_stream_decoder #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.ALLOW_HALF(1)) dut(.*);
 reg [7:0] image[0:MAX_BYTES-1];reg seen[0:W*H-1];
 reg active=0,permit_pixels=1,top=0,prior_stall=0,accepted=0;
 reg [31:0] old_addr=0,lfsr=32'hbe910ae7;
 reg [23:0] old_rgb=0;
 integer sw,sh,stride,scale=1,offset,length,seed=0,pixels=0,total_pixels=0,done_seen=0;
 integer scenarios=0,checks=0,stalls=0,aborts=0,holds=0,cycles=0,i,x,y,n;
 function automatic [23:0] color(input integer sx,sy,s);
  reg [7:0] r,g,b;
  begin r=3+sx*7+sy*13+s*3;g=5+sx*11+sy*19+s*5;b=9+sx*17+sy*23+s*7;color={r,g,b};end
 endfunction
 always @(posedge clk)begin
  if(rst_n&&active)begin
   if(pixel_valid&&!permit_pixels)$fatal(1,"rejected header emitted pixels scenario=%0d",scenarios);
   if(prior_stall&&!(stream_done&&stream_error) &&
     (!pixel_valid||pixel_addr!==old_addr||pixel_rgb!==old_rgb))$fatal(1,"pixel changed during backpressure");
   if(prior_stall)stalls=stalls+1;
   if(pixel_valid&&pixel_ready)begin
    if(pixel_addr>=W*H || seen[pixel_addr])$fatal(1,"duplicate/out-of-bounds output %0d",pixel_addr);
    if(pixel_rgb!==color((pixel_addr%W)/scale,(pixel_addr/W)/scale,seed))
     $fatal(1,"scale oracle scenario=%0d addr=%0d rgb=%h expected=%h",scenarios,pixel_addr,pixel_rgb,color((pixel_addr%W)/scale,(pixel_addr/W)/scale,seed));
    seen[pixel_addr]=1;pixels=pixels+1;total_pixels=total_pixels+1;
   end
   prior_stall=pixel_valid&&!pixel_ready&&!(stream_done&&stream_error);
   old_addr=pixel_addr;old_rgb=pixel_rgb;
  end else prior_stall=0;
  #1;cycles=cycles+1;
  if(rst_n&&active&&done)done_seen=done_seen+1;
 end
 task tick(input bit valid,input integer addr,input [7:0] data,input integer eof,
           input bit failed,ready,begin_file);
  begin
   @(negedge clk);byte_valid=valid;byte_offset=addr;byte_data=data;stream_error=failed;
   pixel_ready=ready;start=begin_file;stream_done=0;
   #1;stream_done=eof==1||(eof==2&&valid&&byte_ready);
   @(posedge clk);accepted=valid&&byte_ready;#2;
  end
 endtask
 task idle;begin tick(0,0,0,0,0,1,0);end endtask
 task reset;begin
  active=0;@(negedge clk);rst_n=0;start=0;byte_valid=0;stream_done=0;stream_error=0;
  repeat(3)idle;@(negedge clk);rst_n=1;idle;
  if(busy||done||error||pixel_valid||byte_ready)$fatal(1,"reset status");
 end endtask
 task put32(input integer a,input [31:0] d);begin
  image[a]=d;image[a+1]=d>>8;image[a+2]=d>>16;image[a+3]=d>>24;
 end endtask
 task make(input bit half_size,top_down,input integer skip,tail);
  integer row,col,p,logical_y;reg [23:0] c;
  begin
   scale=half_size?2:1;sw=W/scale;sh=H/scale;stride=(sw*3+3)/4*4;
   top=top_down;offset=54+skip;length=offset+stride*sh+tail;seed=seed+1;
   for(p=0;p<length;p=p+1)image[p]=(p<54)?0:8'hc9;
   image[0]=8'h42;image[1]=8'h4d;put32(2,length);put32(10,offset);put32(14,40);
   put32(18,sw);put32(22,top_down?-sh:sh);image[26]=1;image[28]=24;put32(34,stride*sh);
   for(row=0;row<sh;row=row+1)for(col=0;col<sw;col=col+1)begin
    logical_y=top_down?row:sh-1-row;c=color(col,logical_y,seed);p=offset+row*stride+col*3;
    image[p]=c[7:0];image[p+1]=c[15:8];image[p+2]=c[23:16];
   end
  end
 endtask
 task begin_image(input bit permitted);begin
  if(busy)$fatal(1,"start before prior completion");
  for(integer p=0;p<W*H;p=p+1)seen[p]=0;
  pixels=0;done_seen=0;permit_pixels=permitted;active=1;prior_stall=0;
  file_size=length;scenarios=scenarios+1;tick(0,0,0,0,0,1,1);
 end endtask
 task send(input integer count,input bit hold_last,input integer bad_offset);
  integer p,guard,last_red;bit ready;
  begin
   p=0;guard=0;last_red=offset+(sh-1)*stride+(sw-1)*3+2;
   while(p<count)begin
    lfsr={lfsr[30:0],lfsr[31]^lfsr[21]^lfsr[1]^lfsr[0]};ready=lfsr[5]||lfsr[9];
    if(hold_last&&p==last_red)begin
     while(pixel_valid)idle;
     tick(1,p,image[p],p==count-1?2:0,0,0,0);
     if(!accepted||!pixel_valid)$fatal(1,"final source pixel not held");
     repeat(9)begin tick(0,0,0,0,0,0,0);if(done_seen||!busy||!pixel_valid||byte_ready)$fatal(1,"completed during held final output block");end
     holds=holds+1;p=p+1;
    end else begin
     tick(lfsr[3:0]!=0,(p==bad_offset)?p+1:p,image[p],p==count-1?2:0,0,ready,0);
     if(accepted)p=p+1;
    end
    if(done_seen||!busy)$fatal(1,"completed before all bytes accepted");
    guard=guard+1;if(guard>count*12+100)$fatal(1,"source stalled indefinitely");
   end
  end
 endtask
 task finish(input bit failed,input integer expected_count);
  integer guard;
  begin
   guard=0;while(done_seen==0&&guard<40)begin idle;guard=guard+1;end
   if(done_seen!=1||busy||error!==failed||pixel_valid||(expected_count>=0&&pixels!=expected_count))
    $fatal(1,"completion scenario=%0d done=%0d err=%b pixels=%0d expected=%0d/%0d",scenarios,done_seen,error,pixels,failed,expected_count);
   if(!failed)for(integer p=0;p<W*H;p=p+1)if(!seen[p])$fatal(1,"missing target pixel %0d",p);
   idle;if(done||byte_ready||done_seen!=1)$fatal(1,"done pulse/idle state");active=0;checks=checks+1;
  end
 endtask
 task good(input bit half_size,top_down,input integer skip,tail);begin
  make(half_size,top_down,skip,tail);begin_image(1);send(length,1,-1);finish(0,W*H);
 end endtask
 initial begin
  reset;good(0,0,0,0);good(1,1,7,3);good(0,1,1,0);good(1,0,0,0);
  if(W<10)begin
   // Width/height must describe the same supported size, including all high bytes.
   for(n=0;n<15;n=n+1)begin
    make(n<13,0,0,0);
    case(n)
     0:put32(18,W);1:put32(22,H);2:put32(18,32'h80000000|sw);
     3:put32(22,32'h80000000);4:image[0]=0;5:put32(14,108);
     6:image[26]=2;7:image[28]=32;8:put32(30,1);9:put32(10,53);
     10:put32(10,32'hfffffff0);11:put32(2,length-1);12:put32(18,sw+1);
     13:put32(18,W+1);14:put32(18,32'h80000000|W);
    endcase
    begin_image(0);send(length,0,-1);finish(1,0);
   end
   make(1,1,0,0);begin_image(1);send(offset+2,0,-1);finish(1,0);
   make(1,1,0,0);begin_image(0);send(length,0,10);finish(1,0);
   // Abort at each of the four replicated output positions, then reuse
   // the decoder without reset. No partial image can report success.
   for(n=0;n<4;n=n+1)begin
    make(1,1,0,0);begin_image(1);
    for(i=0;i<54;i=i+1)begin tick(1,i,image[i],0,0,1,0);if(!accepted)$fatal(1,"header acceptance");end
    idle;
    for(i=54;i<57;i=i+1)begin tick(1,i,image[i],0,0,0,0);if(!accepted)$fatal(1,"first source pixel acceptance");end
    repeat(n)tick(0,0,0,0,0,1,0);
    tick(0,0,0,1,1,0,0);aborts=aborts+1;finish(1,n);
    good(1,1,0,0);
   end
   make(1,0,0,0);begin_image(1);
   for(i=0;i<54;i=i+1)tick(1,i,image[i],0,0,1,0);idle;
   for(i=54;i<57;i=i+1)tick(1,i,image[i],0,0,0,0);
   tick(0,0,0,0,0,1,0);reset;aborts=aborts+1;good(0,0,0,0);good(1,0,0,0);
  end
  $display("PASS runtime scale decoder W=%0d H=%0d checks=%0d pixels=%0d stalls=%0d final_holds=%0d aborts=%0d cycles=%0d",W,H,checks,total_pixels,stalls,holds,aborts,cycles);$finish;
 end
 initial begin #180000000;$fatal(1,"runtime scaler deadline");end
endmodule
