// 同一张卡的两路 CMD17 扇区事务仲裁；整扇区归属固定，不交织数据。
// 请求方必须仅在 *_ready=1 时脉冲 *_start，且保持 LBA 到接受边沿。
module sd_sector_arbiter(
 input wire clk,rst_n,card_ready,audio_urgent,input wire card_done,card_error,
 input wire [8:0] card_addr,input wire [7:0] card_data,input wire card_valid,
 output wire card_start,output wire [31:0] card_lba,
 input wire image_start,input wire [31:0] image_lba,output wire image_ready,image_done,image_error,
 output wire [8:0] image_addr,output wire [7:0] image_data,output wire image_valid,
 input wire audio_start,input wire [31:0] audio_lba,output wire audio_ready,audio_done,audio_error,
 output wire [8:0] audio_addr,output wire [7:0] audio_data,output wire audio_valid);
 localparam IDLE=0,EXPECT=1,BUSY=2;
 reg [1:0] state;reg owner,turn,force_image;
 reg [1:0] audio_run;
 reg [10:0] offer_wait;
 // 低水位时最多连续给音频三个扇区，再留一个完整扇区给图片。
 // 读者只在看到 ready 后发 start，因此空槽要保留足够长时间供其处理上一扇区。
 wire choose_audio=audio_urgent?!(force_image||audio_run==3):turn;
 wire request=owner?audio_start:image_start;
 // 在紧急模式的预留期持续提供 ready；读者可能仍在消化上一扇区，
 // 只在 IDLE 给一拍 ready 会让它错过整段等待时间。
 assign image_ready=card_ready&&((state==IDLE&&!choose_audio)||
  (state==EXPECT&&!owner&&audio_urgent&&offer_wait<11'd2047));
 assign audio_ready=card_ready&&((state==IDLE&&choose_audio)||
  (state==EXPECT&&owner&&audio_urgent&&offer_wait<11'd2047));
 assign card_start=state==EXPECT&&request&&card_ready;
 assign card_lba=owner?audio_lba:image_lba;
 assign image_done=state==BUSY&&!owner&&card_done;
 assign audio_done=state==BUSY&&owner&&card_done;
 assign image_error=image_done&&card_error;
 assign audio_error=audio_done&&card_error;
 assign image_valid=state==BUSY&&!owner&&card_valid;
 assign audio_valid=state==BUSY&&owner&&card_valid;
 assign image_addr=card_addr;assign image_data=card_data;
 assign audio_addr=card_addr;assign audio_data=card_data;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;owner<=0;turn<=0;force_image<=0;audio_run<=0;offer_wait<=0;end
  else case(state)
   IDLE:if(card_ready)begin owner<=choose_audio;offer_wait<=0;state<=EXPECT;end
   EXPECT:if(request&&card_ready)begin state<=BUSY;force_image<=0;end
          else if(audio_urgent&&offer_wait<11'd2047)offer_wait<=offer_wait+1'b1;
          else begin
           state<=IDLE;turn<=!owner;
           if(audio_urgent&&owner)force_image<=1;
           else if(!owner)begin force_image<=0;audio_run<=0;end
          end
   BUSY:if(card_done)begin
    state<=IDLE;turn<=!owner;
    if(owner)begin
     if(audio_urgent&&audio_run<3)audio_run<=audio_run+1'b1;
     else if(!audio_urgent)audio_run<=0;
    end else audio_run<=0;
   end
   default:state<=IDLE;
  endcase
 end
endmodule
