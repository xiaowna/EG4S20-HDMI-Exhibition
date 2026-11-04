// SD v2 high-capacity initialization and read-only CMD17 on one SPI byte master.
// read_start must be a one-cycle pulse with read_request_ready high.
// read_done terminates both successful and failed requests; check read_error.
// Payload bytes must be buffered until read_done && !read_error before display commit.
// Initialization stays below 400 kHz; completed initialization enables faster reads.
module sd_subsystem #(
 parameter integer CLK_HZ=50_000_000,
 parameter integer INIT_CLK_DIV=(CLK_HZ+799999)/800000,
 parameter integer READ_CLK_DIV=2,
 parameter integer READ_TIMEOUT_CYCLES=CLK_HZ,
 parameter integer TOKEN_TIMEOUT_CYCLES=CLK_HZ/4)(
 input wire clk,input wire rst_n,
 output wire sd_sck,output wire sd_mosi,input wire sd_miso,output wire sd_cs,
 output wire ready,output wire error,
 input wire read_start,input wire [31:0] read_lba,
 output wire read_request_ready,output wire read_busy,output wire read_done,
 output wire read_error,output wire [3:0] read_error_code,
 output wire [8:0] data_addr,output wire [7:0] data_out,output wire data_valid);
 wire spi_start,spi_busy,spi_done;
 wire [7:0] spi_tx,spi_rx;
 wire init_start,init_cs,init_error;
 wire [7:0] init_tx;
 wire reader_start,reader_cs;
 wire [7:0] reader_tx;
 assign read_request_ready=ready && !init_error && !read_busy && !spi_busy;
 assign spi_start=ready?reader_start:init_start;
 assign spi_tx=ready?reader_tx:init_tx;
 assign sd_cs=ready?reader_cs:init_cs;
 assign error=init_error | read_error;
 sd_spi_master #(.CLK_DIV(INIT_CLK_DIV),.READ_CLK_DIV(READ_CLK_DIV),.CAPTURE_FALLING(1)) u_spi(
  .clk(clk),.rst_n(rst_n),.start(spi_start),.fast_mode(ready),.tx_data(spi_tx),.rx_data(spi_rx),
  .busy(spi_busy),.done(spi_done),.sd_sck(sd_sck),.sd_mosi(sd_mosi),.sd_miso(sd_miso));
 sd_init_controller #(.CLK_HZ(CLK_HZ),.BYTE_TIMEOUT_CYCLES(32*INIT_CLK_DIV+100)) u_init(
  .clk(clk),.rst_n(rst_n),.spi_busy(spi_busy),.spi_done(spi_done),.spi_rx(spi_rx),
  .spi_start(init_start),.spi_tx(init_tx),.sd_cs(init_cs),.ready(ready),.error(init_error));
 sd_data_block_reader #(.TIMEOUT_CYCLES(READ_TIMEOUT_CYCLES),
  .BYTE_TIMEOUT_CYCLES(32*READ_CLK_DIV+100),.TOKEN_TIMEOUT_CYCLES(TOKEN_TIMEOUT_CYCLES)) u_reader(
  .clk(clk),.rst_n(rst_n && ready),.start(read_start && read_request_ready),.lba(read_lba),
  .spi_busy(spi_busy),.spi_done(spi_done),.spi_rx(spi_rx),
  .spi_start(reader_start),.spi_tx(reader_tx),.sd_cs(reader_cs),
  .busy(read_busy),.done(read_done),.error(read_error),.error_code(read_error_code),
  .data_addr(data_addr),.data_out(data_out),.data_valid(data_valid));
endmodule
