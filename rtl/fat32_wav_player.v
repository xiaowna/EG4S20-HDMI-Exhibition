// 使用图片目录扫描保留的首个 WAV 文件元数据，不重复挂载或扫描 FAT32。
// 文件读口通过扇区仲裁器与图片读口共享；有效文件循环播放。
module fat32_wav_player #(parameter integer TIMEOUT_CYCLES=50_000_000,
 parameter CONTROLLED_STOP=0)(
 input wire clk,rst_n,volume_ready,file_found,
 input wire [31:0] first_cluster,file_size,fat_lba,data_lba,cluster_count,
 input wire [7:0] sectors_per_cluster,
 input wire rd_ready,rd_done,rd_error,input wire [8:0] rd_addr,
 input wire [7:0] rd_data,input wire rd_valid,
 output wire rd_start,output wire [31:0] rd_lba,
 output wire sample_valid,input wire sample_ready,output wire [47:0] sample_data,
 output reg playing,error,input wire play_enable,output wire idle);
 localparam WAIT_VOLUME=0,FILE_START=1,FILE_WAIT=2,DRAIN=3,NO_FILE=4;
 reg [2:0] state;
 reg file_start,parser_start;
 wire file_done,file_error,file_byte_valid,byte_ready;
 reg byte_pending,file_done_pending;
 reg [7:0] byte_buffer;
 wire [31:0] file_offset;
 wire [7:0] file_byte;
 wire parser_playing,parser_error,parser_data_done,file_busy,parser_sample_valid;
 wire enabled=!CONTROLLED_STOP||play_enable;
 wire sample_allowed=!CONTROLLED_STOP||(enabled&&playing&&!parser_start);
 // One elastic byte breaks the decoder-ready path back into the file FSM.
 // Keep the prefetched next header across parser_start while DRAIN retires
 // the old final sample. Only a new file_start or a stop discards this byte.
 wire file_byte_ready=enabled&&!file_start&&!byte_pending&&(state==FILE_WAIT||state==DRAIN);
 wire parser_byte_valid=enabled&&!parser_start&&byte_pending&&state==FILE_WAIT;
 wire file_completed=file_done||file_done_pending;
 // A stop waits for the file reader's complete sector/CRC boundary. The old
 // decoder is restarted only when a fresh file header is launched later.
 assign idle=!file_busy&&!file_start&&!rd_start&&!playing;
 assign sample_valid=sample_allowed&&parser_sample_valid;
 fat32_file_reader #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) reader(
  .clk(clk),.rst_n(rst_n),.start(file_start),
  .stop(!enabled||((parser_data_done || parser_error) && state==FILE_WAIT && !parser_start)),
  .first_cluster(first_cluster),.file_size(file_size),
  .fat_lba(fat_lba),.data_lba(data_lba),.cluster_count(cluster_count),
  .sectors_per_cluster(sectors_per_cluster),.rd_ready(rd_ready),
  .rd_done(rd_done),.rd_error(rd_error),
  .rd_addr(rd_addr),.rd_data(rd_data),.rd_valid(rd_valid),
  .rd_start(rd_start),.rd_lba(rd_lba),
  .out_ready(file_byte_ready),.out_valid(file_byte_valid),
  .out_data(file_byte),.out_offset(file_offset),
  .busy(file_busy),.done(file_done),.error(file_error),.error_code());
 wav_pcm_decoder parser(.clk(clk),.rst_n(rst_n),.start(parser_start),
  .file_size(file_size),
  .byte_valid(parser_byte_valid),.byte_data(byte_buffer),.byte_ready(byte_ready),
  .sample_valid(parser_sample_valid),.sample_ready(sample_ready&&sample_allowed),
  .sample_data(sample_data),.playing(parser_playing),.error(parser_error),
  .data_done(parser_data_done));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin byte_pending<=0;byte_buffer<=0;file_done_pending<=0;end
  else if(!enabled||file_start)begin byte_pending<=0;file_done_pending<=0;end
  else begin
   if(file_done&&(state==FILE_WAIT||state==DRAIN))file_done_pending<=1;
   if(parser_error||(file_done&&file_error))byte_pending<=0;
   else if(file_byte_valid&&file_byte_ready)begin byte_buffer<=file_byte;byte_pending<=1;end
   else if(parser_byte_valid&&byte_ready)byte_pending<=0;
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=WAIT_VOLUME;file_start<=0;parser_start<=0;playing<=0;error<=0;
  end else begin
   file_start<=0;parser_start<=0;
   if(!enabled)begin state<=WAIT_VOLUME;playing<=0;error<=0;end
   else case(state)
    WAIT_VOLUME:if(volume_ready&&!file_busy&&!file_start&&!rd_start)begin
     if(file_found)state<=FILE_START;else state<=NO_FILE;
    end
    FILE_START:begin file_start<=1;parser_start<=1;state<=FILE_WAIT;end
    // A rejected previous song leaves parser_error high until parser_start
    // is consumed. Do not reject the new song on that restart edge.
    FILE_WAIT:if(!parser_start)begin
     if(parser_error)begin
      // A rejected header must not make the card stream through the whole file.
      playing<=0;error<=1;state<=NO_FILE;
     end else if(file_completed&&(!byte_pending||parser_data_done||file_error))begin
      if(file_error||parser_error||!playing||!parser_data_done)begin
       playing<=0;error<=1;state<=NO_FILE;
      end else begin
       // Begin fetching the next header while the final sample is still pending.
       file_start<=1;state<=DRAIN;
      end
     end else if(parser_playing)playing<=1;
    end
    DRAIN:begin
     if(file_done && file_error)begin
      playing<=0;error<=1;state<=NO_FILE;
     end else if(!sample_valid)begin
      parser_start<=1;state<=FILE_WAIT;
     end
    end
    default:state<=NO_FILE;
   endcase
  end
 end
endmodule
