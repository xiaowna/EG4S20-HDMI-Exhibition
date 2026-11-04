// Fair arbitration between display blocks and background single-word writes.
module eg4s20_stream_memory #(parameter CLK_HZ=50000000, READ_CAPTURE_NEGEDGE=1)(
 input wire clk,rst_n,wr_valid,input wire [31:0] wr_addr,wr_data,output wire wr_ready,wr_drained,
 input wire burst_valid,input wire [31:0] burst_addr,input wire [8:0] burst_words,output wire burst_ready,
 output wire burst_data_valid,burst_last,output wire [31:0] burst_data,
 output wire burst_error,output reg fault,output wire init_done);
 wire ready,reply,err,dvalid,dlast,sc,cke,ras,cas,we,oe;
 wire sc_global;
 EG_LOGIC_BUFG sd_clock_buffer(.i(sc),.o(sc_global));
 wire [31:0] data,dout;wire [31:0] dq;wire [10:0] a;wire [1:0] ba;wire [3:0] dm;
 reg prefer_read,inflight,writing;
 // 写请求先寄存，隔离图片地址检查到 SDRAM 半周期命令路径。
 reg write_pending;
 reg [31:0] pending_addr,pending_data;
 wire valid,choose_read;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin write_pending<=0;pending_addr<=0;pending_data<=0;end
  else begin
   if(wr_valid && wr_ready)begin
    write_pending<=1;pending_addr<=wr_addr;pending_data<=wr_data;
   end
   if(valid && ready && !choose_read)write_pending<=0;
  end
 wire [31:0] sampled_dq;
 generate if(READ_CAPTURE_NEGEDGE)begin: input_capture
  // Capture the previous SDRAM word before its next tAC transition.
  // A full memory-clock period is available for the return path.
  reg [31:0] falling_data;
  always @(negedge clk)falling_data<=dq;
  assign sampled_dq=falling_data;
 end else begin: direct_capture
  assign sampled_dq=dq;
 end endgenerate
 assign choose_read=burst_valid && (!write_pending||prefer_read);
 wire accept_ready=ready && !inflight && !fault;
 assign valid=(burst_valid||write_pending)&&!inflight&&!fault;
 assign burst_ready=accept_ready&&choose_read;
 assign wr_ready=!write_pending&&!fault;
 assign wr_drained=!fault&&!wr_valid&&!write_pending&&!(inflight&&writing);
 assign burst_data_valid=dvalid && !writing && !fault;
 assign burst_last=dlast;
 assign burst_data=data;
 assign burst_error=fault;
 assign dq=oe?dout:32'bz;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin prefer_read<=1;inflight<=0;writing<=0;fault<=0;end
  else begin
   if(valid&&ready)begin inflight<=1;writing<=!choose_read;prefer_read<=!choose_read;end
   if(reply)begin inflight<=0;if(err)fault<=1;end
  end
 end
 em638325_stream_controller #(.CLK_HZ(CLK_HZ),.READ_RESPONSE_CYCLES(READ_CAPTURE_NEGEDGE?4:3)) u_ctrl(
 .clk(clk),.rst_n(rst_n),.cmd_valid(valid),.cmd_write(!choose_read),
 .cmd_addr(choose_read?burst_addr:pending_addr),.cmd_data(pending_data),.cmd_words(choose_read?burst_words:9'd1),
 .cmd_ready(ready),.backend_valid(reply),.backend_error(err),.backend_data(data),.data_valid(dvalid),.data_last(dlast),.init_done(init_done),
 .sd_clk(sc),.sd_cke(cke),.sd_ras_n(ras),.sd_cas_n(cas),.sd_we_n(we),.sd_addr(a),.sd_ba(ba),.sd_dm(dm),.dq_out(dout),.dq_oe(oe),.dq_in(sampled_dq));
 EG_PHY_SDRAM_2M_32 u_memory(.clk(sc_global),.ras_n(ras),.cas_n(cas),.we_n(we),.addr(a),.ba(ba),.dq(dq),.cke(cke),
 .cs_n(1'b0),.dm0(dm[0]),.dm1(dm[1]),.dm2(dm[2]),.dm3(dm[3]));
endmodule
