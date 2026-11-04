// RIFF/WAVE PCM：48 kHz、双声道、16/24 位，小端字节流；输出 24 位有符号样本。
// 支持经典 PCM (1) 和有效位宽等于容器位宽的 PCM extensible (fffe)。
// 跳过未知 chunk 和奇数字节 padding；只播放首个 data chunk。
module wav_pcm_decoder(
 input wire clk,rst_n,start,input wire [31:0] file_size,
 input wire byte_valid,input wire [7:0] byte_data,
 output wire byte_ready,output reg sample_valid,input wire sample_ready,
 output reg [47:0] sample_data,output reg playing,error,output wire data_done);
 localparam RIFF=0,CHUNK_ID=1,CHUNK_SIZE=2,SELECT=3,FMT=4,SKIP=5,PAD=6,DATA=7,REST=8,FAIL=9;
 reg [3:0] state;
 reg [5:0] pos;
 reg [31:0] chunk_id,chunk_size,remaining;
 reg [31:0] riff_size,file_size_latched;
 reg [32:0] consumed;
 wire [32:0] riff_end={1'b0,riff_size}+33'd8;
 wire [32:0] chunk_end=consumed+{1'b0,chunk_size}+chunk_size[0];
 reg [15:0] format,align,bits;
 reg [15:0] ext_bytes,valid_bits;
 reg ext_ok;
 reg [31:0] byte_rate;
 reg bad_common;
 reg fmt_seen,pad_needed;
 reg [2:0] sample_pos;
 reg [7:0] b0,b1,b2,b3,b4;
 wire take=byte_valid&&byte_ready;
 // Hold the next file's first byte until the pending final sample is accepted
 // and start resets the parser to RIFF.
 assign byte_ready=(state!=SELECT)&&(state!=REST)&&(!sample_valid||sample_ready);
 assign data_done=(state==REST);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=RIFF;pos<=0;chunk_id<=0;chunk_size<=0;remaining<=0;
   riff_size<=0;file_size_latched<=0;consumed<=0;
   format<=0;align<=0;bits<=0;byte_rate<=0;bad_common<=1;fmt_seen<=0;pad_needed<=0;
   ext_bytes<=0;valid_bits<=0;ext_ok<=0;
   sample_pos<=0;b0<=0;b1<=0;b2<=0;b3<=0;b4<=0;
   sample_valid<=0;sample_data<=0;playing<=0;error<=0;
  end else begin
   if(sample_valid&&sample_ready)sample_valid<=0;
   if(start)begin
    state<=RIFF;pos<=0;sample_pos<=0;sample_valid<=0;
    fmt_seen<=0;playing<=0;error<=0;chunk_id<=0;chunk_size<=0;
    riff_size<=0;file_size_latched<=file_size;consumed<=0;
    if(file_size<12)begin state<=FAIL;error<=1;end
   end else if(take)begin
    // 所有长度运算保留进位；仅在握手成功时累计消费字节。
    consumed<=consumed+1'b1;
    // RIFF 头已保证 riff_end <= file_size；后续只需比较更紧的 RIFF 边界。
    if((state!=RIFF && consumed>=riff_end) ||
       (state==CHUNK_ID && pos==0 && consumed+33'd8>riff_end))begin
     state<=FAIL;error<=1;playing<=0;
    end else case(state)
     RIFF:begin
      case(pos)
       0:if(byte_data!=8'h52)begin state<=FAIL;error<=1;end
       1:if(byte_data!=8'h49)begin state<=FAIL;error<=1;end
       2:if(byte_data!=8'h46)begin state<=FAIL;error<=1;end
       3:if(byte_data!=8'h46)begin state<=FAIL;error<=1;end
       4:riff_size[7:0]<=byte_data;
       5:riff_size[15:8]<=byte_data;
       6:riff_size[23:16]<=byte_data;
       7:riff_size[31:24]<=byte_data;
       8:if(byte_data!=8'h57)begin state<=FAIL;error<=1;end
       9:if(byte_data!=8'h41)begin state<=FAIL;error<=1;end
       10:if(byte_data!=8'h56)begin state<=FAIL;error<=1;end
       11:if(byte_data!=8'h45)begin state<=FAIL;error<=1;end
      endcase
      if(pos==11)begin
       pos<=0;
       if(byte_data==8'h45)begin
        if(riff_size<4 || riff_end>{1'b0,file_size_latched})begin
         state<=FAIL;error<=1;
        end else state<=CHUNK_ID;
       end
      end
      else pos<=pos+1'b1;
     end
     CHUNK_ID:begin
      chunk_id<={byte_data,chunk_id[31:8]};
      if(pos==3)begin pos<=0;chunk_size<=0;state<=CHUNK_SIZE;end else pos<=pos+1'b1;
     end
     CHUNK_SIZE:begin
      chunk_size<={byte_data,chunk_size[31:8]};
      if(pos==3)begin pos<=0;state<=SELECT;end else pos<=pos+1'b1;
     end
     FMT:begin
      case(pos)
       0:format[7:0]<=byte_data;1:format[15:8]<=byte_data;
       // Ordered fmt bytes establish two channels and 48000 Hz before data.
       // Preserve the error decision at SELECT; only the stored form changes.
       2:if(byte_data!=2)bad_common<=1;
       3,6,7:if(byte_data!=0)bad_common<=1;
       4:if(byte_data!=8'h80)bad_common<=1;
       5:if(byte_data!=8'hbb)bad_common<=1;
       8:byte_rate[7:0]<=byte_data;9:byte_rate[15:8]<=byte_data;
       10:byte_rate[23:16]<=byte_data;11:byte_rate[31:24]<=byte_data;
       12:align[7:0]<=byte_data;13:align[15:8]<=byte_data;
       14:bits[7:0]<=byte_data;15:bits[15:8]<=byte_data;
       16:ext_bytes[7:0]<=byte_data;17:ext_bytes[15:8]<=byte_data;
       18:valid_bits[7:0]<=byte_data;19:valid_bits[15:8]<=byte_data;
       20:if(byte_data!=0 && byte_data!=3)ext_ok<=0;
       21,22,23,25,26,27,28,29,31,33,34,36:
        if(byte_data!=0)ext_ok<=0;
       24:if(byte_data!=8'h01)ext_ok<=0;
       30:if(byte_data!=8'h10)ext_ok<=0;
       32:if(byte_data!=8'h80)ext_ok<=0;
       35:if(byte_data!=8'haa)ext_ok<=0;
       37:if(byte_data!=8'h38)ext_ok<=0;
       38:if(byte_data!=8'h9b)ext_ok<=0;
       39:if(byte_data!=8'h71)ext_ok<=0;
      endcase
      // 40 字节后仍需消费 fmt 扩展，但不用再保存其内容。
      if(pos!=40)pos<=pos+1'b1;
      remaining<=remaining-1'b1;
      if(remaining==1)begin
       state<=pad_needed?PAD:CHUNK_ID;pos<=0;fmt_seen<=1;
      end
     end
     SKIP:begin
      remaining<=remaining-1'b1;
      if(remaining==1)begin state<=pad_needed?PAD:CHUNK_ID;pos<=0;end
     end
     PAD:begin state<=CHUNK_ID;pos<=0;end
     DATA:begin
      remaining<=remaining-1'b1;
      case(sample_pos)
       0:b0<=byte_data;1:b1<=byte_data;
       2:if(bits==24)b2<=byte_data;else b3<=byte_data;
       3:if(bits==24)b3<=byte_data;else begin
         sample_data<={{b1,b0,8'h00},{byte_data,b3,8'h00}};
         sample_valid<=1;sample_pos<=0;
        end
       4:b4<=byte_data;
       5:begin sample_data<={{b2,b1,b0},{byte_data,b4,b3}};
         sample_valid<=1;sample_pos<=0;
        end
      endcase
      if(bits==24)begin if(sample_pos!=5)sample_pos<=sample_pos+1'b1;end
      else if(sample_pos!=3)sample_pos<=sample_pos+1'b1;
      if(remaining==1)state<=REST;
     end
     default:;
    endcase
   end else if(state==SELECT)begin
    remaining<=chunk_size;pad_needed<=chunk_size[0];
    // 在解释 chunk 前检查整个数据区和奇数字节 padding，防止跨界。
    if(chunk_end>riff_end)begin
     state<=FAIL;error<=1;playing<=0;
    end else if(chunk_id==32'h20746d66&&!fmt_seen)begin
     if(chunk_size<16)begin state<=FAIL;error<=1;end
     else begin pos<=0;ext_bytes<=0;valid_bits<=0;bad_common<=0;ext_ok<=(chunk_size>=40);state<=FMT;end
    end else if(chunk_id==32'h61746164)begin
     if(!fmt_seen||!((format==1)||(format==16'hfffe && ext_ok &&
        ext_bytes>=22 && valid_bits==bits))||bad_common||
        !((bits==16&&align==4&&byte_rate==192000)||
          (bits==24&&align==6&&byte_rate==288000))||
        chunk_size==0||((bits==16)?(chunk_size%4!=0):(chunk_size%6!=0)))begin
      state<=FAIL;error<=1;
     end else begin playing<=1;sample_pos<=0;state<=DATA;end
    end else if(chunk_size==0)state<=CHUNK_ID;
    else state<=SKIP;
   end
  end
 end
endmodule
