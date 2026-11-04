`timescale 1ns/1ps
module tb_sd_sector_arbiter;
 reg clk=0,rn=0;always #5 clk=~clk;
 reg is=0,as=0;reg [31:0] il=0,al=0;
 wire ir,id,ie,iv,ar,ad,ae,av,cs;
 wire [31:0] cl;wire [8:0] ia,aa;wire [7:0] ib,ab;
 reg cd=0,ce=0,cv=0;reg [8:0] ca=0;reg [7:0] cb=0;
 reg busy=0;wire cr=!busy;
 sd_sector_arbiter dut(.clk(clk),.rst_n(rn),.card_ready(cr),.audio_urgent(1'b0),
  .card_done(cd),.card_error(ce),.card_addr(ca),.card_data(cb),.card_valid(cv),
  .card_start(cs),.card_lba(cl),.image_start(is),.image_lba(il),
  .image_ready(ir),.image_done(id),.image_error(ie),.image_addr(ia),
  .image_data(ib),.image_valid(iv),.audio_start(as),.audio_lba(al),
  .audio_ready(ar),.audio_done(ad),.audio_error(ae),.audio_addr(aa),
  .audio_data(ab),.audio_valid(av));
 integer iq=0,aq=0,ic=0,ac=0,ivc=0,avc=0,step=0;
 reg [31:0] active_lba=0;
 always @(posedge clk)begin
  if(!rn)begin is<=0;as<=0;il<=0;al<=0;iq<=0;aq<=0;end
  else begin
   is<=0;as<=0;
   if(ir&&iq<4)begin il<=32'h100+iq;is<=1;iq<=iq+1;end
   if(ar&&aq<4)begin al<=32'h200+aq;as<=1;aq<=aq+1;end
  end
 end
 always @(posedge clk)begin
  if(!rn)begin busy<=0;cd<=0;cv<=0;ca<=0;cb<=0;step<=0;active_lba<=0;end
  else begin
   cd<=0;cv<=0;
   if(cs)begin
    if(busy)$fatal(1,"overlapped sector requests");
    busy<=1;step<=0;active_lba<=cl;
   end else if(busy)begin
    ca<=step;cb<=active_lba[7:0]+step;cv<=1;
    if(step==3)begin busy<=0;cd<=1;end else step<=step+1;
   end
  end
 end
 always @(posedge clk)if(rn)begin
  if(iv)begin
   if(av||ib!==active_lba[7:0]+ia||active_lba[9:8]!=1)$fatal(1,"image data crossed owner");
   ivc=ivc+1;
  end
  if(av)begin
   if(iv||ab!==active_lba[7:0]+aa||active_lba[9:8]!=2)$fatal(1,"audio data crossed owner");
   avc=avc+1;
  end
  if(id)ic=ic+1;
  if(ad)ac=ac+1;
 end
 initial begin
  repeat(4)@(negedge clk);rn=1;
  wait(ic==4&&ac==4);repeat(3)@(negedge clk);
  if(ivc!=16||avc!=16||ie||ae)$fatal(1,"lost sectors/image=%0d audio=%0d",ivc,avc);
  $display("PASS SD arbiter: four image and four audio sectors, exclusive ownership and data routing");$finish;
 end
 initial begin #100000;$fatal(1,"arbiter timeout image=%0d audio=%0d",ic,ac);end
endmodule
