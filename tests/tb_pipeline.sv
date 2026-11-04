`timescale 1ns/1ps
module tb_pipeline;
 reg clk=0,pc=0,rst_n=0,scan_start=0,load_start=0;always #10 clk=~clk;always #60 pc=~pc;
 reg [1:0] image_index=0;reg rd_ready=1,rd_done=0,rd_error=0,rd_valid=0;
 reg [8:0] rd_addr=0;reg [7:0] rd_data=0;
 wire req,busy,cat,scan_done,image_done,error,load_ready,commit,reject,front,frontbank;
 wire cv,cw,mfault,pe;wire [2:0] mcode;wire [31:0] ca,cd;reg cr=0;integer mtick=0,wait_cycles=0;reg [31:0] saved_addr,saved_data;reg saved_write;
 wire de,hs,vs,under,wv,mrv;wire [31:0] lba,wa,wd,ma;wire [23:0] rgb;wire [2:0] count;
 reg response=0;reg [31:0] md=0;reg [31:0] ram[0:11];
 integer mode=0,bank,k,requests=0,seen=0,good=0,lit=0,goal=0;reg [7:0] mem[0:3583];
 media_stream_pipeline #(.FRAME_WIDTH(3),.FRAME_HEIGHT(2),.TIMEOUT_CYCLES(5000),
 .H_FP(2),.H_SYNC(2),.H_BP(2),.V_FP(2),.V_SYNC(2),.V_BP(2),.FIFO_ADDR_BITS(3)) dut(
 .clk(clk),.pix_clk(pc),.rst_n(rst_n),.scan_start(scan_start),.load_start(load_start),.image_index(image_index),
 .rd_ready(rd_ready),.rd_done(rd_done),.rd_error(rd_error),.rd_addr(rd_addr),.rd_data(rd_data),.rd_valid(rd_valid),
 .rd_start(req),.rd_lba(lba),.busy(busy),.catalog_ready(cat),.scan_done(scan_done),.image_done(image_done),.error(error),.image_count(count),.load_ready(load_ready),
 .front_valid(front),.front_bank(frontbank),.frame_committed(commit),.frame_rejected(reject),
 .de(de),.hsync(hs),.vsync(vs),.rgb(rgb),.frame_underflow(under),.memory_fault(mfault),.prefetch_error(pe));
 always @(posedge clk)if(rst_n&&(mfault||pe))$fatal(1,"memory fault %d",mcode);
 always @(posedge pc)begin
  #1;
  if(rst_n&&de)begin
   if(rgb!=0)begin
    if(rgb!==(((seen+10)<<16)|((seen+20)<<8)|(seen+30)))$fatal(1,"pipeline pixel mismatch %d %h",seen,rgb);
    lit=lit+1;
   end
   seen=seen+1;
   if(seen==6)begin if(lit==6)good=good+1;else if(lit!=0)$fatal(1,"partial frame without injected display stall");seen=0;lit=0;end
  end
 end
 initial forever begin
  @(negedge clk);
  if(req)begin
   if(!rd_ready)$fatal(1,"overlap");rd_ready=0;rd_error=0;requests=requests+1;
   case(lba)0:bank=0;2048:bank=1;3281:bank=2;2080:bank=3;3283:bank=4;3408:bank=5;3287:bank=6;
    2081:bank=7; // 补齐 FAT 第二扇区：末簇 130 的结束标记。
    default:$fatal(1,"unexpected LBA %d",lba);endcase
   for(k=0;k<512;k=k+1)begin
    rd_valid=1;rd_addr=k;rd_data=(bank==7)?8'hff:mem[bank*512+k];@(negedge clk);
   end
   rd_valid=0;rd_error=(mode==4 && bank==5);rd_done=1;@(negedge clk);rd_done=0;rd_ready=1;
  end
 end
 task load(input [1:0] slot,input bad);
 begin
  wait(load_ready);@(negedge clk);image_index=slot;load_start=1;@(negedge clk);load_start=0;
  wait(image_done);#1;if(error!==bad)$fatal(1,"decode status");
  if(slot<2)begin wait(commit||reject);#1;if(reject!==bad)$fatal(1,"commit status");end
  if(!bad)begin goal=good+2;wait(good>=goal);end
  repeat(3)@(negedge clk);
 end endtask
 initial begin
  if(!$value$plusargs("MODE=%d",mode))mode=0;$readmemh("fixture.hex",mem);
  case(mode)
   1:mem[2048]=0;2:mem[2048+28]=32;3:mem[2048+18]=4;
   5:mem[2048+30]=1;6:begin mem[1024+28]=10;mem[1024+29]=2;end
  endcase
  // Hold reset across both clocks so every clock domain observes it.
  repeat(4)@(negedge pc);rst_n=1;@(negedge clk);scan_start=1;@(negedge clk);scan_start=0;wait(scan_done);#1;
  if(error||!cat||count!=2)$fatal(1,"scan");
  load(0,(mode>=1&&mode<=6));load(1,0);load(3,1);
  if(mode==0||mode==7)load(0,0);
  $display("PASS integrated streaming sector-to-raster mode=%0d good frames=%0d",mode,good);$finish;
 end
 initial begin #3000000;$fatal(1,"pipeline timeout");end
endmodule
