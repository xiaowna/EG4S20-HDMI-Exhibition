`timescale 1ns/1ps
module tb_data_island;
 reg clk=0,rst_n=0,pv=0,send=0,hs=0,vs=0,ctl=1;
 always #20 clk=~clk;
 reg [23:0] header=0;reg [223:0] body=0;
 wire ready,prepared,valid,last;wire [4:0] index;
 wire [9:0] c0,c1,c2;
 hdmi_data_island_encoder dut(clk,rst_n,pv,ready,header,body,send,hs,vs,ctl,prepared,valid,last,index,c0,c1,c2);
 reg [247:0] inputs[0:7];reg [287:0] golden[0:7];
 reg [3:0] lookup_in;wire [9:0] lookup_out;
 hdmi_terc4 lookup(lookup_in,lookup_out);
 function [9:0] code(input [3:0] n);
 case(n)
 0:code=10'h29c;1:code=10'h263;2:code=10'h2e4;3:code=10'h2e2;
 4:code=10'h171;5:code=10'h11e;6:code=10'h18e;7:code=10'h13c;
 8:code=10'h2cc;9:code=10'h139;10:code=10'h19c;11:code=10'h2c6;
 12:code=10'h28e;13:code=10'h271;14:code=10'h163;15:code=10'h2c3;
 endcase
 endfunction
 integer p,k,j;reg [3:0] even_bits,odd_bits;
 task reset_core;
 begin @(negedge clk);rst_n=0;pv=0;send=0;repeat(2)@(negedge clk);rst_n=1;end
 endtask
 initial begin
  $readmemh("input.hex",inputs);$readmemh("golden.hex",golden);
  for(k=0;k<16;k=k+1)begin lookup_in=k;#1;if(lookup_out!==code(k))$fatal(1,"TERC4 %0d",k);end
  reset_core();
  // 中断一次校验运算，再完整发送八种包，验证复位不会留下旧数据。
  pv=1;header=24'hbadbad;@(negedge clk);pv=0;repeat(9)@(negedge clk);reset_core();
  for(p=0;p<8;p=p+1)begin
   wait(ready);@(negedge clk);{body,header}=inputs[p];pv=1;
   @(negedge clk);pv=0;header=~header;body=~body;send=1;
   @(negedge clk);send=0; // 提前请求发送应被忽略。
   wait(prepared);@(negedge clk);
   repeat(5)begin if(valid||ready||!prepared)$fatal(1,"prepare hold");@(negedge clk);end
   send=1;@(negedge clk);send=0;
   for(k=0;k<32;k=k+1)begin
    hs=k[0];vs=k[1];ctl=k[2];
    for(j=0;j<4;j=j+1)begin even_bits[j]=golden[p][32+64*j+2*k];odd_bits[j]=golden[p][33+64*j+2*k];end
    #1;
    if(!valid||index!=k||last!==(k==31))$fatal(1,"length/index");
    if(c0!==code({ctl,golden[p][k],vs,hs})||c1!==code(even_bits)||c2!==code(odd_bits))
     $fatal(1,"packet %0d symbol %0d BCH/bit-order/TERC4 mismatch",p,k);
    @(negedge clk);
   end
   if(valid||!ready)$fatal(1,"packet termination");
  end
  $display("PASS: 16 TERC4 codes, 8 complete BCH packets, 32-symbol mapping, preparation and reset");$finish;
 end
 initial begin #100000;$fatal(1,"deadline");end
endmodule
