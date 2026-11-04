`timescale 1ns/1ps

module tb_spi_divider;
 parameter integer CLK_DIV = 64;
 parameter integer READ_CLK_DIV = 4;
 reg clk = 0;
 always #5 clk = ~clk;
 reg rst_n = 1;
 reg start = 0;
 reg fast_mode = 0;
 reg [7:0] tx_data = 0;
 reg sd_miso = 1;
 wire [7:0] rx_data;
 wire busy, done, sd_sck, sd_mosi;

 sd_spi_master #(.CLK_DIV(CLK_DIV), .READ_CLK_DIV(READ_CLK_DIV)) dut (
  .clk(clk), .rst_n(rst_n), .start(start), .fast_mode(fast_mode),
  .tx_data(tx_data), .rx_data(rx_data), .busy(busy), .done(done),
  .sd_sck(sd_sck), .sd_mosi(sd_mosi), .sd_miso(sd_miso)
 );

`ifdef COMPARE_BASELINE
 wire [7:0] baseline_rx_data;
 wire baseline_busy, baseline_done, baseline_sck, baseline_mosi;
 sd_spi_master_baseline #(.CLK_DIV(CLK_DIV), .READ_CLK_DIV(READ_CLK_DIV)) baseline (
  .clk(clk), .rst_n(rst_n), .start(start), .fast_mode(fast_mode),
  .tx_data(tx_data), .rx_data(baseline_rx_data), .busy(baseline_busy),
  .done(baseline_done), .sd_sck(baseline_sck), .sd_mosi(baseline_mosi),
  .sd_miso(sd_miso)
 );
`endif

 // Public-interface oracle: deadlines are measured from accepted start.
 // No internal counters, widths or implementation signal names are used.
 reg expected_busy = 0, expected_done = 0;
 reg expected_sck = 0, expected_mosi = 1;
 reg [7:0] expected_rx_data = 0, sampled_bits = 0, accepted_tx = 0;
 integer elapsed = 0, half_ticks = CLK_DIV;
 integer checks = 0, accepted = 0, completed = 0, rising_edges = 0;
 integer bit_number;
 always @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
   expected_busy = 0;
   expected_done = 0;
   expected_sck = 0;
   expected_mosi = 1;
   expected_rx_data = 0;
   sampled_bits = 0;
   accepted_tx = 0;
   elapsed = 0;
   half_ticks = CLK_DIV;
  end else begin
   expected_done = 0;
   if (!expected_busy) begin
    expected_sck = 0;
    if (start) begin
     expected_busy = 1;
     accepted_tx = tx_data;
     expected_mosi = tx_data[7];
     sampled_bits = 0;
     elapsed = 0;
     half_ticks = (fast_mode === 1'b1) ? READ_CLK_DIV : CLK_DIV;
     accepted = accepted + 1;
    end
   end else begin
    elapsed = elapsed + 1;
    if ((elapsed % (2 * half_ticks)) == half_ticks) begin
     expected_sck = 1;
     bit_number = (elapsed - 1) / (2 * half_ticks);
     sampled_bits[7 - bit_number] = sd_miso;
     rising_edges = rising_edges + 1;
    end else if ((elapsed % (2 * half_ticks)) == 0) begin
     expected_sck = 0;
     bit_number = elapsed / (2 * half_ticks);
     if (bit_number == 8) begin
      expected_busy = 0;
      expected_done = 1;
      expected_rx_data = sampled_bits;
      expected_mosi = 1;
      completed = completed + 1;
     end else expected_mosi = accepted_tx[7 - bit_number];
    end
   end
  end
  #1;
  checks = checks + 1;
  if ({busy, done, sd_sck, sd_mosi, rx_data} !==
      {expected_busy, expected_done, expected_sck, expected_mosi, expected_rx_data})
   $fatal(1, "SPI mismatch t=%0t div=%0d/%0d elapsed=%0d half=%0d actual=%b/%b/%b/%b/%h expected=%b/%b/%b/%b/%h",
          $time, CLK_DIV, READ_CLK_DIV, elapsed, half_ticks,
          busy, done, sd_sck, sd_mosi, rx_data,
          expected_busy, expected_done, expected_sck, expected_mosi, expected_rx_data);
`ifdef COMPARE_BASELINE
  if ({busy, done, sd_sck, sd_mosi, rx_data} !==
      {baseline_busy, baseline_done, baseline_sck, baseline_mosi, baseline_rx_data})
   $fatal(1, "Baseline output mismatch at t=%0t", $time);
`endif
 end

 task tick(input reg request, input reg mode, input reg [7:0] data,
           input reg miso_value);
  begin
   @(negedge clk);
   start = request;
   fast_mode = mode;
   tx_data = data;
   sd_miso = miso_value;
   @(posedge clk);
   #2;
  end
 endtask

 task transfer(input reg [7:0] data, input reg [7:0] response,
               input reg mode, input integer disturb);
  integer cycle, half, rx_bit, before_completed;
  reg request, changed_mode;
  begin
   if (busy) $fatal(1, "Stimulus attempted transfer while busy");
   half = (mode === 1'b1) ? READ_CLK_DIV : CLK_DIV;
   before_completed = completed;
   tick(1, mode, data, 1);
   if (!busy || done || sd_sck || sd_mosi !== data[7])
    $fatal(1, "Start edge failed to latch byte in mode 0");
   for (cycle = 1; cycle <= 16 * half; cycle = cycle + 1) begin
    rx_bit = 7 - ((cycle - 1) / (2 * half));
    // Busy-time requests and changed TX must not disturb this byte. Leave
    // start high on the last edge; it must not restart until the next clock.
    request = disturb && ((cycle % 7 == 0) || cycle == 16 * half);
    changed_mode = disturb ? ((cycle % 3 == 0) ? 1'bx : !mode) : mode;
    tick(request, changed_mode, data ^ cycle, response[rx_bit]);
   end
   if (busy || !done || sd_sck || !sd_mosi || rx_data !== response ||
       completed != before_completed + 1)
    $fatal(1, "Completion/data failure tx=%h rx=%h expected=%h", data, rx_data, response);
  end
 endtask

 task reset_during_transfer(input reg mode, input integer clocks);
  integer cycle;
  begin
   tick(1, mode, 8'h96, 0);
   for (cycle = 0; cycle < clocks; cycle = cycle + 1)
    tick(0, !mode, 8'h00, cycle[0]);
   // Assert between clocks, checking asynchronous reset as well as recovery.
   @(negedge clk);
   #2 rst_n = 0;
   #2;
   if (busy || done || sd_sck || !sd_mosi || rx_data !== 8'h00)
    $fatal(1, "Asynchronous reset did not clear outputs");
   start = 0;
   @(negedge clk);
   #2 rst_n = 1;
   tick(0, 0, 0, 1);
  end
 endtask

 integer index;
 reg [31:0] pattern = 32'h6d57a3c1;
 initial begin
  if (CLK_DIV < 1 || READ_CLK_DIV < 1) $fatal(1, "Positive divisors required");
  #2 rst_n = 0;
  tick(0, 0, 0, 1);
  @(negedge clk);
  #2 rst_n = 1;
  tick(0, 0, 0, 1);
  transfer(8'h00, 8'hff, 0, 1);
  transfer(8'hff, 8'h00, 1, 1);
  transfer(8'h81, 8'h7e, 0, 1);
  transfer(8'h7e, 8'h81, 1, 1);
  transfer(8'haa, 8'h55, 1'bx, 1);
  tick(0, 0, 0, 1);
  if (done || busy || sd_sck) $fatal(1, "done was not a one-cycle pulse");
  repeat (3) tick(0, 1, 8'hff, 0);

  // Abort once with SCK low and once with SCK high, then recover.
  reset_during_transfer(0, CLK_DIV > 1 ? CLK_DIV - 1 : 0);
  transfer(8'hc3, 8'h3c, 1, 1);
  reset_during_transfer(1, READ_CLK_DIV);
  transfer(8'h3c, 8'hc3, 0, 1);

  for (index = 0; index < 24; index = index + 1) begin
   pattern = {pattern[30:0], pattern[31] ^ pattern[21] ^ pattern[1] ^ pattern[0]};
   transfer(pattern[7:0], pattern[23:16], index[0], 1);
  end
  tick(0, 0, 0, 1);
  if (completed != 31 || accepted != 33 || busy || done)
   $fatal(1, "Transaction accounting failed accepted=%0d completed=%0d", accepted, completed);
  $display("PASS SPI CLK_DIV=%0d READ_CLK_DIV=%0d completed=%0d aborted=2 checks=%0d rising_edges=%0d",
           CLK_DIV, READ_CLK_DIV, completed, checks, rising_edges);
`ifdef COMPARE_BASELINE
  $display("PASS baseline equivalence: all five outputs match for %0d clock/reset checks", checks);
`endif
  $finish;
 end

 initial begin
  #100000000;
  $fatal(1, "SPI test timeout");
 end
endmodule
