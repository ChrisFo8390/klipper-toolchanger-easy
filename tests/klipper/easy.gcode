; KTC-E easy-additions on Klipper, the same configuration as tests/kalico/ktce_easy.cfg.
ASSERT TEST='{printer.tool_probe_endstop.active_tool_number == 0}'
G28
ASSERT TEST='{printer.toolhead.homed_axes == "xyz"}'
ASSERT TEST='{printer.toolchanger.tool_number == 0}'
ASSERT TEST='{printer.toolchanger.status == "ready"}'
QUERY_PROBE
PROBE
BED_MESH_CALIBRATE
START_CRASH_DETECTION
STOP_CRASH_DETECTION
VERIFY_TOOL_DETECTED T=0
ASSERT TEST='{printer.tool_probe_endstop.active_tool_number == 0}'
SELECT_TOOL T=0
CALIBRATE_MOVE_OVER_PROBE
TOOL_LOCATE_SENSOR
TOOL_CALIBRATE_TOOL_OFFSET
_SAVE_TOOL_OFFSET T=0
_SAVE_Z_TOOL_OFFSET T=0
CALIBRATE_NOZZLE_PROBE_OFFSET
