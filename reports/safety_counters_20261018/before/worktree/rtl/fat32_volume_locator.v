// Locate a FAT32 volume from LBA 0. Read-only; supports superfloppy and
// primary MBR type 0B/0C. GPT, extended/logical and hidden partitions unsupported.
// Selects first structurally valid FAT32 entry in table order, not active order.
module fat32_volume_locator #(parameter integer TIMEOUT_CYCLES=50_000_000)(
 input wire clk,rst_n,start,
 input wire rd_ready,rd_done,rd_error,input wire [8:0] rd_addr,
 input wire [7:0] rd_data,input wire rd_valid,
 output reg rd_start,output wire [31:0] rd_lba,
 output reg busy,done,error,valid,output reg [31:0] partition_lba,partition_sectors);
 localparam IDLE=0,PROBE=1,REQUEST=2,RECEIVE=3,CHECK=4;
 reg [2:0] state;
 reg probe_start;
 reg [9:0] count;
 reg order_error;
 reg [7:0] sig0,sig1;
 reg status_ok,fat32_kind;
 reg [31:0] entry_first;
 reg [23:0] entry_length_low;
 integer timer;
 reg picked,protective;
 reg [31:0] selected_lba,selected_len;
 wire [8:0] rel=rd_addr-9'd446;
 wire [31:0] entry_length={rd_data,entry_length_low};
 wire [32:0] entry_end={1'b0,entry_first}+{1'b0,entry_length};
 wire probe_valid,probe_busy,probe_done,probe_error;
 wire [31:0] probe_size;
 assign rd_lba=32'd0;
 fat32_boot_parser #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) u_probe(
  .clk(clk),.rst_n(rst_n),.start(probe_start),.partition_lba(32'd0),
  .byte_addr(rd_addr),.byte_in(rd_data),.byte_valid(rd_valid && state==RECEIVE),
  .fat_lba(),.root_lba(),.root_cluster(),.sectors_per_cluster(),
  .valid(probe_valid),.busy(probe_busy),.done(probe_done),.error(probe_error),
  .data_lba(),.cluster_count(),.volume_sectors(probe_size));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;probe_start<=0;rd_start<=0;busy<=0;done<=0;valid<=0;error<=0;
   partition_lba<=0;partition_sectors<=0;count<=0;order_error<=0;sig0<=0;sig1<=0;timer<=0;
   status_ok<=0;fat32_kind<=0;entry_first<=0;entry_length_low<=0;
   picked<=0;protective<=0;selected_lba<=0;selected_len<=0;
  end else begin
   rd_start<=0;probe_start<=0;done<=0;
   if(state!=IDLE && timer>=TIMEOUT_CYCLES-1) begin state<=IDLE;busy<=0;done<=1;error<=1;valid<=0;end
   else begin
    if(state!=IDLE) timer<=timer+1;
    case(state)
     IDLE:if(start) begin
      busy<=1;valid<=0;error<=0;partition_lba<=0;partition_sectors<=0;
      count<=0;order_error<=0;sig0<=0;sig1<=0;timer<=0;state<=PROBE;
      status_ok<=0;fat32_kind<=0;entry_first<=0;entry_length_low<=0;
      picked<=0;protective<=0;selected_lba<=0;selected_len<=0;
     end
     PROBE:begin probe_start<=1;state<=REQUEST;end
     REQUEST:if(rd_ready && probe_busy) begin rd_start<=1;state<=RECEIVE;end
     RECEIVE:begin
      if(rd_valid) begin
       if(count>=512 || {1'b0,rd_addr}!=count) order_error<=1;
       else count<=count+1'b1;
       if(rd_addr>=446 && rd_addr<510) begin
        case(rel[3:0])
         0:status_ok<=(rd_data==0 || rd_data==8'h80);
         4:begin
          fat32_kind<=(rd_data==8'h0b || rd_data==8'h0c);
          if(rd_data==8'hee) protective<=1;
         end
         8:entry_first[7:0]<=rd_data;9:entry_first[15:8]<=rd_data;
         10:entry_first[23:16]<=rd_data;11:entry_first[31:24]<=rd_data;
         12:entry_length_low[7:0]<=rd_data;13:entry_length_low[15:8]<=rd_data;
         14:entry_length_low[23:16]<=rd_data;
         // Reuse one entry check; publish only after the complete sector passes CHECK.
         15:if(!picked && fat32_kind && status_ok && entry_first!=0 && entry_length!=0 &&
               entry_end<=33'h100000000) begin
          picked<=1;selected_lba<=entry_first;selected_len<=entry_length;
         end
        endcase
       end
       if(rd_addr==510) sig0<=rd_data;
       if(rd_addr==511) sig1<=rd_data;
      end
      if(rd_done) begin
       if(rd_error) begin busy<=0;done<=1;error<=1;state<=IDLE;end
       else state<=CHECK;
      end
     end
     CHECK:begin
      busy<=0;done<=1;state<=IDLE;
      if(count!=512 || order_error || sig0!=8'h55 || sig1!=8'haa) error<=1;
      else if(probe_valid && !probe_error && !probe_busy) begin
       partition_lba<=0;partition_sectors<=probe_size;valid<=1;
      end else if(picked && !protective) begin
       partition_lba<=selected_lba;partition_sectors<=selected_len;valid<=1;
      end else error<=1;
     end
     default:begin busy<=0;done<=1;error<=1;valid<=0;state<=IDLE;end
    endcase
   end
  end
 end
endmodule
