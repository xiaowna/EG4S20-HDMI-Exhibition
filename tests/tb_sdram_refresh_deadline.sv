`timescale 1ns/1ps
module tb_sdram_refresh_deadline;
 reg clk=0, rst_n=0, cmd_valid=0;
 reg [31:0] cmd_addr=0;
 wire cmd_ready, backend_valid, backend_error, init_done;
 wire ras_n,cas_n,we_n;
 always #10 clk=~clk;
 em638325_stream_controller #(.POWERUP_CYCLES(2),.REFRESH_CYCLES(8)) dut(
  .clk(clk),.rst_n(rst_n),.cmd_valid(cmd_valid),.cmd_write(1'b1),
  .cmd_addr(cmd_addr),.cmd_data(32'h12345678),.cmd_words(9'd1),
  .cmd_ready(cmd_ready),.backend_valid(backend_valid),.backend_error(backend_error),
  .init_done(init_done),.sd_ras_n(ras_n),.sd_cas_n(cas_n),.sd_we_n(we_n),
  .dq_in(32'b0));
 initial begin
  #13 rst_n=1;
  wait(init_done); @(negedge clk);
  if(!cmd_ready) $fatal(1,"initial command not ready");
  cmd_valid=1;
  @(negedge clk); cmd_valid=0;
  wait(dut.refresh_age==8); #1;
  if(dut.state==dut.IDLE || cmd_ready) $fatal(1,"deadline must occur while busy");
  @(negedge clk); cmd_addr=4; cmd_valid=1;
  wait(backend_valid); #1;
  if(dut.state!=dut.IDLE || cmd_ready) $fatal(1,"expired refresh must block pending command");
  @(posedge clk); #1;
  if(dut.state!=dut.REFRESH || {ras_n,cas_n,we_n}!=3'b001)
   $fatal(1,"refresh was not prioritized");
  @(posedge clk); #1;
  if(dut.state!=dut.FWAIT || cmd_ready) $fatal(1,"refresh recovery not enforced");
  wait(cmd_ready); #1;
  @(posedge clk); #1;
  if(dut.state!=dut.CHECK || backend_error || cmd_ready)
   $fatal(1,"pending command not captured after refresh");
  @(negedge clk);cmd_valid=0;
  @(posedge clk);#1;
  if(dut.state!=dut.ACT || backend_error) $fatal(1,"pending command not validated after refresh");
  $display("PASS SDRAM refresh deadline: busy, priority, recovery");
  $finish;
 end
 initial begin #100000; $fatal(1,"timeout"); end
endmodule
