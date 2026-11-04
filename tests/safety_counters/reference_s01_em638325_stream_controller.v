// Custom EM638325: BL1/CL3 with a pipelined READ command each cycle.
// Up to 32 sequential words in one open row; writes remain single-word.
// clk is the system/transaction clock (10..50 MHz supported here).
// SDRAM samples commands on ~clk rising edges, giving half-cycle setup.
// Read capture occurs half a cycle after CL=3 data launch. TD timing must verify.
// Each accepted word command gets one reply AFTER precharge recovery.
module em638325_stream_controller #(parameter integer READ_RESPONSE_CYCLES=3, CLK_HZ=50000000,
 parameter integer POWERUP_CYCLES=(CLK_HZ/5000),
 parameter integer REFRESH_CYCLES=(CLK_HZ/128000))(
 input wire clk,rst_n,cmd_valid,cmd_write,input wire [31:0] cmd_addr,cmd_data,input wire [8:0] cmd_words,
 output wire cmd_ready,output reg backend_valid,backend_error,output reg [31:0] backend_data,
 output reg init_done,output reg data_valid,data_last,
 output wire sd_clk,sd_cke,sd_ras_n,sd_cas_n,sd_we_n,
 output reg [10:0] sd_addr,output wire [1:0] sd_ba,output wire [3:0] sd_dm,
 output wire [31:0] dq_out,output wire dq_oe,input wire [31:0] dq_in);
 localparam integer RP=(64'd30*CLK_HZ+999999999)/1000000000;
 localparam integer RCD=(64'd30*CLK_HZ+999999999)/1000000000;
 localparam integer RFC=(64'd70*CLK_HZ+999999999)/1000000000;
 localparam integer RAS=(64'd50*CLK_HZ+999999999)/1000000000;
 localparam integer WG=(RAS>2)?RAS:2;
 // The age is only compared with the refresh deadline. Keep it at the
 // deadline while a transaction finishes instead of counting to 2^32-1.
 localparam integer REFRESH_BITS=(REFRESH_CYCLES>1)?$clog2(REFRESH_CYCLES+1):1;
 localparam PWR=0,WAKE=1,IPRE=2,IPWAIT=3,IREF=4,IRWAIT=5,MRS=6,MWAIT=7,
 IDLE=8,ACT=9,AWAIT=10,ACCESS=11,RWAIT=12,WWAIT=13,PRE=14,PWAIT=15,
 REFRESH=16,FWAIT=17,REPLY=18,CHECK=19;
 reg [4:0] state;
 localparam integer DELAY_A=(POWERUP_CYCLES>WG)?POWERUP_CYCLES:WG;
 localparam integer DELAY_B=(RFC>RCD)?RFC:RCD;
 localparam integer DELAY_C=(DELAY_A>DELAY_B)?DELAY_A:DELAY_B;
 localparam integer DELAY_D=(DELAY_C>RP)?DELAY_C:RP;
 localparam integer DELAY_MAX=(DELAY_D>2)?DELAY_D:2;
 localparam integer DELAY_BITS=$clog2(DELAY_MAX+1);
 reg [DELAY_BITS-1:0] delay_count;
 reg [31:0] address,write_data;
 reg [REFRESH_BITS-1:0] refresh_age;
 reg [3:0] init_refreshes;
 reg write_op,command_bad;reg [8:0] words,issued,captured;reg [READ_RESPONSE_CYCLES-1:0] read_pipe;
 wire read_issue=state==ACCESS && !write_op && issued<words;
 reg [2:0] command;
 assign sd_clk=~clk;
 assign sd_cke=rst_n && state!=PWR;
 assign sd_dm=init_done?4'b0000:4'b1111;
 assign {sd_ras_n,sd_cas_n,sd_we_n}=command;
 assign sd_ba=address[20:19];
 assign dq_out=write_data;
 assign dq_oe=rst_n && state==ACCESS && write_op;
 assign cmd_ready=rst_n && state==IDLE && refresh_age<REFRESH_CYCLES;
 always @* begin
  command=3'b111;sd_addr=0;
  if(rst_n)case(state)
   IPRE,PRE:begin command=3'b010;sd_addr[10]=1;end
   IREF,REFRESH:command=3'b001;
   MRS:begin command=3'b000;sd_addr=11'h030;end
   ACT:begin command=3'b011;sd_addr=address[18:8];end
   ACCESS:begin
    if(write_op)command=3'b100;else if(issued<words)command=3'b101;
    sd_addr[7:0]=address[7:0]+issued;
   end
  endcase
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=PWR;delay_count<=0;refresh_age<=0;address<=0;write_data<=0;write_op<=0;
   words<=0;issued<=0;captured<=0;command_bad<=0;read_pipe<=0;data_valid<=0;data_last<=0;
   init_refreshes<=0;init_done<=0;backend_valid<=0;backend_error<=0;backend_data<=0;
  end else begin
   backend_valid<=0;backend_error<=0;data_valid<=0;data_last<=0;
   read_pipe<={read_pipe[READ_RESPONSE_CYCLES-2:0],read_issue};
   if(init_done && refresh_age<REFRESH_CYCLES)refresh_age<=refresh_age+1'b1;
   case(state)
    PWR:if(delay_count>=POWERUP_CYCLES-1)begin state<=WAKE;delay_count<=2;end else delay_count<=delay_count+1'b1;
    WAKE:if(delay_count==0)state<=IPRE;else delay_count<=delay_count-1'b1;
    IPRE:begin delay_count<=RP-1;state<=IPWAIT;end
    IPWAIT:if(delay_count==0)state<=IREF;else delay_count<=delay_count-1'b1;
    IREF:begin init_refreshes<=init_refreshes+1'b1;delay_count<=RFC-1;state<=IRWAIT;end
    IRWAIT:if(delay_count==0)state<=(init_refreshes==8)?MRS:IREF;else delay_count<=delay_count-1'b1;
    MRS:begin delay_count<=1;state<=MWAIT;end
    MWAIT:if(delay_count==0)begin init_done<=1;refresh_age<=0;state<=IDLE;end else delay_count<=delay_count-1'b1;
    IDLE:begin
     if(refresh_age>=REFRESH_CYCLES)state<=REFRESH;
     else if(cmd_valid)begin
      // Capture every accepted command before acting on its validation.
      // The address/length carry chain no longer gates SDRAM I/O registers
      // on their half-cycle setup path. CHECK emits only NOP commands.
      command_bad<=cmd_addr[31:21]!=0 || cmd_words==0 || cmd_words>32 ||
         ({1'b0,cmd_addr[7:0]}+cmd_words)>256 || (cmd_write && cmd_words!=1);
      address<=cmd_addr;write_data<=cmd_data;write_op<=cmd_write;words<=cmd_words;
      issued<=0;captured<=0;state<=CHECK;
     end
    end
    CHECK:if(command_bad)begin backend_valid<=1;backend_error<=1;state<=IDLE;end else state<=ACT;
    ACT:begin delay_count<=RCD-1;state<=AWAIT;end
    AWAIT:if(delay_count==0)state<=ACCESS;else delay_count<=delay_count-1'b1;
    ACCESS:begin
     if(write_op)begin delay_count<=WG-1;state<=WWAIT;end
     else begin
      if(read_issue)issued<=issued+1'b1;
      if(read_pipe[READ_RESPONSE_CYCLES-1])begin
       backend_data<=dq_in;data_valid<=1;data_last<=captured==words-1;captured<=captured+1'b1;
       if(captured==words-1)state<=PRE;
      end
     end
    end
    RWAIT:if(delay_count==0)begin backend_data<=dq_in;state<=PRE;end else delay_count<=delay_count-1'b1;
    WWAIT:if(delay_count==0)state<=PRE;else delay_count<=delay_count-1'b1;
    PRE:begin delay_count<=RP-1;state<=PWAIT;end
    PWAIT:if(delay_count==0)state<=REPLY;else delay_count<=delay_count-1'b1;
    REPLY:begin backend_valid<=1;state<=IDLE;end
    REFRESH:begin refresh_age<=0;delay_count<=RFC-1;state<=FWAIT;end
    FWAIT:if(delay_count==0)state<=IDLE;else delay_count<=delay_count-1'b1;
    default:begin state<=PWR;delay_count<=0;init_done<=0;end
   endcase
  end
 end
endmodule
