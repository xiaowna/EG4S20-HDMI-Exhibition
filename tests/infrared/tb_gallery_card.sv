`timescale 1ns/1ps
// Production top, NEC decoder, player, FAT/BMP, SDRAM and RGB raster.
// PLL, SD transport and HDMI output are modeled.
module tb_ir_gallery_card;
 parameter integer PAGES=2;
 reg clk50=0,rst_n=0,sd_miso=1,mode_sw7=1,infrared_n=1;
 reg [15:0] pressed=0;
 tri [3:0] key_col_n,key_row_n;wire rtc_scl,rtc_ce;tri0 rtc_sda;
 wire [3:0] led;wire sd_sck,sd_mosi,sd_cs,hdmi_clk_p,hdmi_d0_p,hdmi_d1_p,hdmi_d2_p;
 always #10 clk50=~clk50;
 dmz_keyboard_model keyboard_model(.*,.row_n(key_row_n),.col_n(key_col_n));
 hdmi_media_board_top #(.VIEW_3D(0)) dut(.*);
 // Small images and expanded blanking make the transaction test practical.
 // The independent raster tests exercise the production 640x480 profile.
 defparam dut.infrared.SAMPLE_CYCLES=1,dut.keyboard.SCAN_CYCLES=4,dut.keys.COUNT=8,
  dut.mode_control.DEBOUNCE_CYCLES=8,dut.u_player.FRAME_WIDTH=4,dut.u_player.FRAME_HEIGHT=2,
  dut.u_player.INTRO_ANIMATION=0,dut.u_player.u_media.H_FP=16,
  dut.u_player.u_media.H_SYNC=8,dut.u_player.u_media.H_BP=12,dut.u_player.u_media.V_BP=5;
 integer commits=0,cuts=0,expected_id=0,pixels=0;
 reg [5:0] seen_slots=0;
 integer before_commit,base_cut,base_reads;
 reg watching=0;
 always @(posedge dut.sys_clk)if(dut.core_rst_n)begin
  if(dut.u_player.frame_committed)begin
   commits<=commits+1;
   seen_slots[dut.u_player.u_media.front_base/8]<=1;
  end
  if(dut.fast_photo)cuts<=cuts+1;
  if(watching&&dut.transition_active)$fatal(1,"manual cut invoked a transition");
  if(dut.mem_error||dut.prefetch_error||dut.underflow||dut.image_error)
   $fatal(1,"media fault mem=%b prefetch=%b underflow=%b image=%b",
          dut.mem_error,dut.prefetch_error,dut.underflow,dut.image_error);
 end
 function automatic [23:0] color(input integer pos,id);
  reg [7:0] r,g,b;
  begin r=17+id*3+pos%4;g=31+id*5+pos/4;b=29+id*7+pos%4+pos/4;color={r,g,b};end
 endfunction
 always @(negedge dut.pix_clk)if(watching&&dut.de&&dut.display_index==expected_id)begin
  if(dut.rgb!==color(pixels%8,expected_id))
   $fatal(1,"wrong front RGB id=%0d pixel=%0d got=%h expected=%h",expected_id,pixels,dut.rgb,color(pixels%8,expected_id));
  pixels=pixels+1;
 end
 task cycles(input integer n);begin repeat(n)@(negedge dut.sys_clk);#2;end endtask
 task level(input bit v,input integer n);begin infrared_n=v;cycles(n);end endtask
 task frame(input [7:0] cmd,input integer gap);
  reg [31:0] word;
  begin
   word={~cmd,cmd,8'hff,8'h00};level(1,gap);level(0,900);level(1,450);
   for(integer i=0;i<32;i=i+1)begin level(0,56);level(1,word[i]?169:56);end
   level(0,56);level(1,100);
  end
 endtask
 task repeat_frame;
  begin level(1,4000);level(0,900);level(1,225);level(0,56);level(1,100);end
 endtask
 task expect_page(input integer id);
  begin
   wait(commits>before_commit);cycles(2);
   if(commits!=before_commit+1||dut.display_index!=id||cuts!=base_cut+1)
    $fatal(1,"manual cut id=%0d shown=%0d commits=%0d cuts=%0d",id,dut.display_index,commits,cuts);
   wait(pixels>=8);watching=0;cycles(2);
  end
 endtask
 initial begin
  cycles(8);rst_n=1;dut.u_pll.lock_enable=1;
  wait(dut.folder_ui_ready&&dut.display_valid&&!dut.mode_switching);
  if(!dut.home_visible||dut.album_limit!=PAGES)$fatal(1,"wrong fixture album range");
  frame(8'h15,19000);wait(!dut.home_visible);
  frame(8'h15,19000); // pause autoplay; manual navigation must stay live.
  if(!dut.paused)$fatal(1,"IR pause did not reach the player");
  wait(dut.u_player.u_control.warm_index==PAGES&&dut.u_player.frame_prepared);
  cycles(2);
  expected_id=1;pixels=0;watching=1;before_commit=commits;base_cut=cuts;base_reads=dut.u_player.u_card.reads;
  frame(8'h09,19000);expect_page(1);
  if(dut.u_player.u_card.reads_at_commit!=base_reads)$fatal(1,"cached cut read the TF card again");
  repeat_frame();
  if(cuts!=base_cut+1||commits!=before_commit+1)$fatal(1,"tap repeat advanced the album twice");
  expected_id=0;pixels=0;watching=1;before_commit=commits;base_cut=cuts;
  frame(8'h07,500);expect_page(0);
  for(integer page=PAGES-1;page>0;page=page-1)begin
   expected_id=page;pixels=0;watching=1;before_commit=commits;base_cut=cuts;
   frame(8'h07,10000);expect_page(page);
  end
  expected_id=2%PAGES;pixels=0;watching=1;before_commit=commits;base_cut=cuts;
  frame(8'h09,500);expect_page(2%PAGES);
  expected_id=3%PAGES;pixels=0;watching=1;before_commit=commits;base_cut=cuts;
  pressed=16'd2;cycles(160);pressed=0;cycles(160);expect_page(3%PAGES);
  if(dut.u_player.u_card.reads!=base_reads)$fatal(1,"cached forward/reverse sequence reread the TF card");
  if(PAGES==6&&seen_slots!=6'b111111)$fatal(1,"did not display all six SDRAM slots");
  $display("PASS infrared to RGB: %0d cached pages, zero TF rereads on forward/reverse, left wrap and physical cut",PAGES);
  $finish;
 end
 always @(posedge dut.sys_clk)if(dut.u_player.frame_committed)
  dut.u_player.u_card.reads_at_commit=dut.u_player.u_card.reads;
 initial begin #14000000;$fatal(1,"gallery timeout shown=%0d commits=%0d cuts=%0d pixels=%0d home=%b state=%0d card=%b cat=%b switching=%b",
  dut.display_index,commits,cuts,pixels,dut.home_visible,dut.u_player.u_control.state,
  dut.card_ready,dut.catalog_ready,dut.mode_switching);end
endmodule

module sd_subsystem #(parameter CLK_HZ=50000000)(
 input wire clk,rst_n,sd_miso,read_start,input wire [31:0] read_lba,
 output wire sd_sck,sd_mosi,sd_cs,ready,error,read_request_ready,
 output reg read_done=0,output wire read_error,
 output reg [8:0] data_addr=0,output reg [7:0] data_out=0,output reg data_valid=0);
 reg busy=0;
 integer reads=0,reads_at_commit=0,pos=0,bank=0;
 reg [7:0] fixture[0:32767];
 initial $readmemh("ir_gallery_card.hex",fixture);
 assign {sd_sck,sd_mosi,sd_cs}=3'b011;
 assign ready=rst_n;assign error=0;assign read_error=0;
 assign read_request_ready=rst_n&&!busy&&!read_done;
 always @(posedge clk)begin
  read_done<=0;data_valid<=0;
  if(!rst_n)busy<=0;
  else if(read_start&&read_request_ready)begin
   case(read_lba)
    0:bank<=0;2048:bank<=1;2080:bank<=2;
    default:begin
     if(read_lba<2680||read_lba>=2741)$fatal(1,"unexpected TF sector %0d",read_lba);
     bank<=3+read_lba-2680;
    end
   endcase
   busy<=1;pos<=0;reads<=reads+1;
  end else if(busy)begin
   if(pos==512)begin busy<=0;read_done<=1;end
   else begin data_valid<=1;data_addr<=pos;data_out<=fixture[bank*512+pos];pos<=pos+1;end
  end
 end
endmodule
