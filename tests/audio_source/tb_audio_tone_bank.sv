`timescale 1ns/1ps
module tb_audio_tone_bank;
 parameter integer CLK_HZ=480000;
 localparam integer SAMPLES=(CLK_HZ>1000000)?192:4800;
 reg clk=0,rst_n=0,enable=1,ready=1;reg [2:0] sel;
 always #5 clk=~clk;
 wire valid,tick,overflow;wire signed [23:0] l,r;
 audio_tone_bank #(.CLK_HZ(CLK_HZ)) dut(clk,rst_n,enable,sel,ready,valid,l,r,tick,overflow);
 longint cycles=0,previous_ticks=0,nt,step;
 reg [31:0] phase=0;
 reg pending=0,ov=0,et;
 integer expected=0,amplitude,index,freq,ticks=0,drops=0,i;
 real angle;
 function integer frequency(input integer s);
 case(s) 0:frequency=440;1:frequency=880;2:frequency=1000;3:frequency=2000;
 4:frequency=4000;5:frequency=8000;6:frequency=12000;default:frequency=16000;endcase
 endfunction
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   cycles=0;previous_ticks=0;phase=0;pending=0;ov=0;expected=0;ticks=0;drops=0;
   #1;if(valid!==0||tick!==0||overflow!==0||l!==0||r!==0)$fatal(1,"reset");
  end else begin
   cycles=cycles+1;nt=cycles*48000/CLK_HZ;et=(nt!=previous_ticks);previous_ticks=nt;
   if(pending&&ready)pending=0;
   if(et) begin
    ticks=ticks+1;freq=frequency(sel);
    step=$floor(freq*4294967296.0/48000.0+0.5);
    index=phase>>26;angle=6.283185307179586*index/64.0;
    amplitude=$rtoi(1048576.0*$sin(angle)+(($sin(angle)>=0)?0.5:-0.5));
    if(!pending)begin pending=1;expected=enable?amplitude:0;end
    else begin ov=1;drops=drops+1;end
    phase=phase+step;
   end
   #1;
   if(tick!==et||valid!==pending||overflow!==ov)$fatal(1,"cadence/handshake");
   if(l!==expected||r!==expected)$fatal(1,"sample sel=%0d tick=%0d got=%0d expected=%0d",sel,ticks,l,expected);
  end
 end
 task reset_source;
 begin @(negedge clk);rst_n=0;repeat(3)@(negedge clk);rst_n=1;end
 endtask
 task advance(input integer count);
 integer target;
 begin target=ticks+count;wait(ticks>=target);@(negedge clk);end
 endtask
 initial begin
  // Drive the first selection after event controls are active. A declaration
  // initializer alone can leave the DUT's always @* decoder unevaluated.
  #1;
  for(i=0;i<8;i=i+1)begin
   sel=i;reset_source();advance(SAMPLES);
   if(overflow)$fatal(1,"normal overflow");
   $display("PASS clock=%0d frequency=%0d samples=%0d",CLK_HZ,frequency(sel),ticks);
  end
  // 不复位连续切换音调，检查采样节拍、相位连续以及待发样本。
  for(i=0;i<8;i=i+1)begin sel=i;advance(31);end
  ready=0;advance(4);
  if(drops==0||!overflow)$fatal(1,"missing overflow");
  sel=0;enable=0;advance(3); // 阻塞时切换与静音不能修改已有效样本。
  ready=1;advance(3);if(l!==0||r!==0)$fatal(1,"mute");
  enable=1;advance(48);if(!overflow)$fatal(1,"overflow not sticky");
  ready=0;reset_source();ready=1;advance(48);
  if(overflow)$fatal(1,"reset recovery");
  $display("PASS switching, stalled sample stability, mute, overflow and reset");$finish;
 end
 initial begin #1000000000;$fatal(1,"deadline");end
endmodule
