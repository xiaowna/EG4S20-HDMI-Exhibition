`timescale 1ns/1ps
module tb_scene_label_lines;
 reg clk=0,rst_n=0,enable=0,scene_mode=0,de=0,inject_deadline=0;
 reg [9:0] x=0,y=0;
 reg [69:0] anchors_x=0,anchors_y=0;
 wire font_request;wire [14:0] font_address;wire [1:0] name_pixel;
 wire font_available=!(x>=464&&x<592)&&!(inject_deadline&&y==167&&x>=420);
 reg font_pixel=0;
 scene_label_line_cache dut(.*);
 always #20 clk=~clk;
 function font_pattern(input [14:0] address);font_pattern=(address%17)<7;endfunction
 always @(posedge clk)font_pixel<=font_pattern(font_request?font_address:15'h7abc);
 integer row,col,n,test_case,left,top,width,dx,dy,base,checked=0;
 reg [1:0] expected;
 reg [14:0] expected_font;
 task setup(input integer which);
 begin
  enable=0;de=0;repeat(8)@(negedge clk);
  scene_mode=which==2;
  for(n=0;n<10;n=n+1)begin
   anchors_x[n*7+:7]=(which==0)?((n*11)%112):60;
   anchors_y[n*7+:7]=(which==2)?(n==2?35:70):40;
  end
  enable=1;
 end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;
  for(test_case=0;test_case<3;test_case=test_case+1)begin
   setup(test_case);
   for(row=0;row<480;row=row+1)begin
    for(col=0;col<800;col=col+1)begin
     @(negedge clk);x=col;y=row;de=col<640;
     @(posedge clk);#1;
     if(de&&x>=16&&x<400&&y>=48&&y<432)begin
      if(!dut.bank_ready[y[0]])$fatal(1,"line cache missed normal 800-clock deadline row=%0d",row);
      expected=0;
      for(n=0;n<10;n=n+1)begin
       left=16+3*anchors_x[n*7+:7];top=48+3*anchors_y[n*7+:7];
       width=(n==6||n==7)?36:24;dx=x-left;dy=y-top;
       if((scene_mode?(n==2||n==9):(n<9))&&dx>=0&&dx<width&&dy>=0&&dy<12)begin
        case(n)
         0:base=24;1:base=44;2:base=64;3:base=84;4:base=104;
         5:base=124;6:base=144;7:base=164;8:base=0;default:base=192;
        endcase
        expected_font=((base+dy)<<7)+4+dx;
        expected={1'b1,font_pattern(expected_font)};
       end
      end
      if(name_pixel!==expected)$fatal(1,"line cache pixel mismatch mode=%0d x=%0d y=%0d got=%b expected=%b",test_case,x,y,name_pixel,expected);
      checked=checked+1;
     end
    end
   end
  end
  // Write part of a name, then deny its font port until the next line.
  // The unfinished cache must remain invisible despite its nonzero contents.
  setup(1);inject_deadline=1;
  for(row=0;row<169;row=row+1)for(col=0;col<800;col=col+1)begin
   @(negedge clk);x=col;y=row;de=col<640;
   @(posedge clk);#1;
   if(row==168&&col>=16&&col<400&&name_pixel!==0)$fatal(1,"partial label line was published");
  end
  if(dut.bank_ready[0]||dut.memory[180][1]!==1)$fatal(1,"deadline stimulus did not leave a partial invalid line");
  enable=0;de=0;repeat(3)@(negedge clk);
  if(name_pixel!==0)$fatal(1,"disabled line cache remained visible");
  $display("PASS name line cache: %0d exact pixels, all nine co-linear labels, last-name overlap priority, both scenes, 128 font-busy clocks/line, missed deadline hides partial data, disable",checked);
  $finish;
 end
 initial begin #100000000;$fatal(1,"label cache test timeout");end
endmodule
