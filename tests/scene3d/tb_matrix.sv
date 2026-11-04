`timescale 1ns/1ps
module tb_3d_matrix;
 parameter integer SCAN_CYCLES=4;
 reg clk=0,rst_n=1;
 reg [15:0] pressed=0;
 tri [3:0] row_n,col_n;
 wire [3:0] normal_key_n;wire [4:0] view_key_n;wire [8:0] key_n={view_key_n,normal_key_n};
 wire ready;
 integer i,j,cases=0,cycles=0;
 always #10 clk=~clk;
 dmz_keyboard_model keys(.pressed(pressed),.row_n(row_n),.col_n(col_n));
 board_matrix_keys #(.SCAN_CYCLES(SCAN_CYCLES),.VIEW_KEYS(1)) dut(
  .clk(clk),.rst_n(rst_n),.col_n(col_n),.row_n(row_n),.key_n(normal_key_n),.view_key_n(view_key_n),.ready(ready));
 always @(negedge clk)begin
  cycles=cycles+1;
  if(rst_n)begin
   if((^key_n)===1'bx || (ready!==0 && ready!==1))$fatal(1,"unknown public matrix outputs key_n=%b ready=%b",key_n,ready);
   // A physical passive keyboard cannot tolerate HIGH and LOW row drivers.
   // With keys pressed, external column pullups/ghost paths also reach row
   // pads. Inspect unloaded rows to distinguish high impedance from HIGH.
   if(pressed==0)case(row_n)
     4'bzzz0,4'bzz0z,4'bz0zz,4'b0zzz:;
     default:$fatal(1,"row drivers must be one LOW plus three high impedance: %b",row_n);
    endcase
  end else if((pressed==0 && row_n!==4'bzzzz) || ready!==0 || key_n!==9'h1ff)
   $fatal(1,"reset must disable every row and clear ready/keys");
 end
 function [8:0] single_key(input integer n);
  integer bit_index;begin
   case(n)1:bit_index=0;2:bit_index=1;3:bit_index=2;4:bit_index=3;
    9:bit_index=4;10:bit_index=5;11:bit_index=6;14:bit_index=7;default:bit_index=8;
   endcase
   single_key=~(9'b1<<bit_index);
  end
 endfunction
 task ticks(input integer n);
  begin repeat(n)begin @(negedge clk);#1;end end
 endtask
 task expect_keys(input [8:0] expected);
  begin
   ticks(8*SCAN_CYCLES+4);
   if(!ready || key_n!==expected)
    $fatal(1,"matrix expected=%b actual=%b pressed=%h i=%0d j=%0d",expected,key_n,pressed,i,j);
   cases=cases+1;
  end
 endtask
 task released;
  begin pressed=0;expect_keys(9'h1ff);end
 endtask
 initial begin
  #1;rst_n=0;ticks(3);pressed=16'h0010;rst_n=1;
  while(!ready)begin
   @(negedge clk);#1;
   if(!ready && key_n!==9'h1ff)$fatal(1,"partial scan published before ready");
  end
  if(key_n!==9'h1f7)$fatal(1,"first complete scan lost held KEY4");
  expect_keys(9'h1f7);released;
  for(i=0;i<16;i=i+1)begin
   pressed=16'b1<<i;
   if((i>=1 && i<=4)||i==6||i==9||i==10||i==11||i==14)begin expect_keys(single_key(i));expect_keys(single_key(i));end
   else begin
    expect_keys(9'h1ff);pressed=pressed|2;expect_keys(9'h1ff);pressed=2;expect_keys(9'h1ff);
   end
   released;
  end
  for(i=0;i<16;i=i+1)for(j=i+1;j<16;j=j+1)begin
   pressed=(16'b1<<i)|(16'b1<<j);expect_keys(9'h1ff);
   pressed=pressed|2;expect_keys(9'h1ff);pressed=2;expect_keys(9'h1ff);released;
   pressed=2;expect_keys(9'h1fe);released;
  end
  pressed=16'h0031;expect_keys(9'h1ff); // physical ghost to KEY1
  pressed=2;expect_keys(9'h1ff);released;
  pressed=16'h0032;expect_keys(9'h1ff); // rectangle across the two enabled rows
  released;pressed=16'h0010;expect_keys(9'h1f7);
  rst_n=0;ticks(3);rst_n=1;expect_keys(9'h1f7);released;
  $display("PASS expanded 3D matrix SCAN_CYCLES=%0d cases=%0d cycles=%0d: KEY1..4 and KEY9/10/11/14/6 physical mapping, all 120 pairs, ghost lock, release rearm, open-drain rows and held reset",SCAN_CYCLES,cases,cycles);
  $finish;
 end
 initial begin #2000000000;$fatal(1,"matrix scan test timeout");end
endmodule
