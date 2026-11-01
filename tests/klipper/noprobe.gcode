; Printer without tool probes on Klipper: tool changes with the stock pickup and
; dropoff paths, and CALIBRATE_ALL_OFFSETS with the tools_calibrate of this repository.
G28
ASSERT TEST='{printer.toolhead.homed_axes == "xyz"}'
SELECT_TOOL T=0
ASSERT TEST='{printer.toolchanger.tool_number == 0}'
SELECT_TOOL T=1
ASSERT TEST='{printer.toolchanger.tool_number == 1}'
SELECT_TOOL T=0
ASSERT TEST='{printer.toolchanger.tool_number == 0}'
CALIBRATE_ALL_OFFSETS
ASSERT TEST='{printer.toolchanger.tool_number == 0}'
ASSERT TEST='{"tool T1" in printer.configfile.save_config_pending_items}'
ASSERT TEST='{printer["tool T1"].gcode_x_offset == printer.tools_calibrate.last_result[0]}'
ASSERT TEST='{printer["tool T1"].gcode_y_offset == printer.tools_calibrate.last_result[1]}'
ASSERT TEST='{printer["tool T1"].gcode_z_offset == printer.tools_calibrate.last_result[2]}'
