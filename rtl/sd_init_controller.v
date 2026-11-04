// SD v2 high-capacity initialization only. No ready for legacy/SDSC cards.
// One clock domain; external SPI byte master must run at <=400 kHz during init.
module sd_init_controller #(
 parameter integer CLK_HZ=50_000_000, POWER_WAIT_CYCLES=CLK_HZ/1000,
 parameter integer RETRY_WAIT_CYCLES=CLK_HZ/1000,
 parameter integer INIT_TIMEOUT_CYCLES=2*CLK_HZ,
 parameter integer BYTE_TIMEOUT_CYCLES=100_000, MAX_ACMD41=1000)(
 input wire clk,input wire rst_n,input wire spi_busy,input wire spi_done,input wire [7:0] spi_rx,
 output wire spi_start,output wire [7:0] spi_tx,output wire sd_cs,
 output reg ready,output reg error);
 localparam POWER=0,CLOCK_ISSUE=1,CLOCK_WAIT=2,LAUNCH=3,COMMAND_WAIT=4,
            RETRY=5,OK=6,ERR=7;
 reg [2:0] state;
 reg [3:0] clock_bytes;
 reg [5:0] command;
 reg [31:0] argument;
 reg [7:0] crc;
 reg [2:0] extra;
 reg command_start,clock_start;
 localparam integer DELAY_MAX=(POWER_WAIT_CYCLES>RETRY_WAIT_CYCLES)?POWER_WAIT_CYCLES:RETRY_WAIT_CYCLES;
 localparam integer DELAY_BITS=(DELAY_MAX>1)?$clog2(DELAY_MAX):1;
 localparam integer WATCHDOG_BITS=(INIT_TIMEOUT_CYCLES>1)?$clog2(INIT_TIMEOUT_CYCLES):1;
 localparam integer RETRY_BITS=(MAX_ACMD41>1)?$clog2(MAX_ACMD41):1;
 reg [DELAY_BITS-1:0] delay_count;
 reg [WATCHDOG_BITS-1:0] watchdog;
 reg [RETRY_BITS-1:0] retries;
 reg [2:0] cmd0_retries;
 wire engine_start,engine_busy,engine_done,engine_timeout,engine_cs;
 wire [7:0] engine_tx,r1;
 wire [31:0] response_data;
 wire engine_reset_n=rst_n && (state!=ERR);
 wire power_clocks=(state==POWER || state==CLOCK_ISSUE || state==CLOCK_WAIT);
 assign spi_start=(state==ERR || state==OK)?1'b0:(power_clocks?clock_start:engine_start);
 assign spi_tx=power_clocks?8'hff:engine_tx;
 assign sd_cs=(power_clocks || state==ERR || state==OK)?1'b1:engine_cs;
 sd_command_engine #(.BYTE_TIMEOUT_CYCLES(BYTE_TIMEOUT_CYCLES)) u_command(
  .clk(clk),.rst_n(engine_reset_n),.start(command_start),.cmd(command),.arg(argument),
  .crc(crc),.extra_bytes(extra),.spi_busy(spi_busy),.spi_done(spi_done),.spi_rx(spi_rx),
  .spi_start(engine_start),.spi_tx(engine_tx),.busy(engine_busy),.done(engine_done),
  .response(r1),.timeout(engine_timeout),.response_data(response_data),.sd_cs(engine_cs));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=POWER; clock_bytes<=0; command<=0; argument<=0; crc<=8'h95; extra<=0;
   command_start<=0; clock_start<=0; delay_count<=0; watchdog<=0; retries<=0;
   cmd0_retries<=0; ready<=0; error<=0;
  end else begin
   command_start<=0; clock_start<=0;
   if(state!=OK && state!=ERR && watchdog>=INIT_TIMEOUT_CYCLES-1) begin
    state<=ERR; ready<=0; error<=1;
   end else begin
    if(state!=OK && state!=ERR) watchdog<=watchdog+1;
    case(state)
     POWER: if(delay_count>=POWER_WAIT_CYCLES-1) begin delay_count<=0; state<=CLOCK_ISSUE; end
            else delay_count<=delay_count+1;
     CLOCK_ISSUE: if(!spi_busy) begin clock_start<=1; state<=CLOCK_WAIT; end
     CLOCK_WAIT: if(spi_done) begin
      if(clock_bytes==9) state<=LAUNCH;
      else begin clock_bytes<=clock_bytes+1'b1; state<=CLOCK_ISSUE; end
     end
     LAUNCH: if(!engine_busy) begin command_start<=1; state<=COMMAND_WAIT; end
     COMMAND_WAIT: if(engine_done) begin
      if(command==0 && (engine_timeout || r1!=8'h01) && cmd0_retries<7) begin
       cmd0_retries<=cmd0_retries+1; state<=LAUNCH;
      end else if(engine_timeout) begin error<=1; state<=ERR; end
      else case(command)
       0: if(r1==8'h01) begin command<=8; argument<=32'h000001aa; crc<=8'h87; extra<=4; state<=LAUNCH; end
          else begin error<=1; state<=ERR; end
       8: if(r1==8'h01 && response_data==32'h000001aa) begin command<=55; argument<=0; crc<=8'h01; extra<=0; state<=LAUNCH; end
          else begin error<=1; state<=ERR; end
       55: if(r1==8'h01 || r1==0) begin command<=41; argument<=32'h40000000; state<=LAUNCH; end
           else begin error<=1; state<=ERR; end
       41: if(r1==0) begin command<=58; argument<=0; extra<=4; state<=LAUNCH; end
           else if(r1==8'h01 && retries<MAX_ACMD41-1) begin
            retries<=retries+1; delay_count<=0; state<=RETRY;
           end else begin error<=1; state<=ERR; end
       58: if(r1==0 && response_data[31:30]==2'b11 && (response_data & 32'h00300000)!=0) begin
            ready<=1; state<=OK;
           end else begin error<=1; state<=ERR; end
       default: begin error<=1; state<=ERR; end
      endcase
     end
     RETRY: if(delay_count>=RETRY_WAIT_CYCLES-1) begin command<=55; argument<=0; state<=LAUNCH; end
            else delay_count<=delay_count+1;
     OK: ready<=1;
     default: begin ready<=0; error<=1; state<=ERR; end
    endcase
   end
  end
 end
endmodule
