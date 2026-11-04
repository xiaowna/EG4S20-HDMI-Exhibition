// Four commands: [0] right, [1] OK, [2] left, [3] settings/back.
// Every source must supply one-system-clock event pulses, already synchronized
// and debounced/decoded. Priority is physical keys > encoder > infrared.
// Simultaneous lower-priority sources are discarded, never queued for later.
// No state or added cycle latency. Preserve the existing key conflict policy.
module media_control_events(
 input wire enable,
 input wire [3:0] key_press,encoder_event,infrared_event,
 output wire [3:0] control_event);
 wire [3:0] selected_event=(|key_press)?key_press:
  (|encoder_event)?encoder_event:infrared_event;
 assign control_event=!enable?4'b0000:
  selected_event[3]?4'b1000:
  selected_event[1]?4'b0010:
  (selected_event[0]&&!selected_event[2])?4'b0001:
  (selected_event[2]&&!selected_event[0])?4'b0100:4'b0000;
endmodule
