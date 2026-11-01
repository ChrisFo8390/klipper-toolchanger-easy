; KTC-E on Klipper, the code path for the probe API of Klipper: tool probes,
; Z homing, probing, bed mesh, Z tilt and tool changes. The same configuration
; as tests/kalico/ktce_basic.cfg.
ASSERT TEST='{printer.tool_probe_endstop.active_tool_number == -1}'

SET_ACTIVE_TOOL_PROBE T=0
ASSERT TEST='{printer.tool_probe_endstop.active_tool_number == 0}'
ASSERT TEST='{printer.tool_probe_endstop.active_tool_probe == "tool_probe T0"}'
G28
ASSERT TEST='{printer.toolhead.homed_axes == "xyz"}'
G1 X100 Y100 Z10 F6000
M400

QUERY_PROBE
PROBE
PROBE_ACCURACY SAMPLES=3
Z_TILT_ADJUST
BED_MESH_CALIBRATE

SET_ACTIVE_TOOL_PROBE T=1
ASSERT TEST='{printer.tool_probe_endstop.active_tool_number == 1}'
G1 X100 Y100 Z10 F6000
G28 Z
PROBE
G1 Z10 F600

INITIALIZE_TOOLCHANGER T=0
ASSERT TEST='{printer.toolchanger.tool_number == 0}'
ASSERT TEST='{printer.tool_probe_endstop.active_tool_number == 0}'
SELECT_TOOL T=1
ASSERT TEST='{printer.toolchanger.tool_number == 1}'
ASSERT TEST='{printer.tool_probe_endstop.active_tool_number == 1}'
PROBE
SELECT_TOOL T=0
ASSERT TEST='{printer.toolchanger.tool_number == 0}'
ASSERT TEST='{printer.tool_probe_endstop.active_tool_number == 0}'
G28 Z
BED_MESH_CALIBRATE

STOP_TOOL_PROBE_CRASH_DETECTION
DETECT_ACTIVE_TOOL_PROBE
ASSERT TEST='{printer.tool_probe_endstop.active_tool_number == -1}'

; tools_calibrate of this repository
ASSERT TEST='{printer.tools_calibrate.last_x_result is defined}'
SET_ACTIVE_TOOL_PROBE T=0
G1 X100 Y100 Z10 F6000
TOOL_LOCATE_SENSOR
TOOL_CALIBRATE_TOOL_OFFSET
TOOL_CALIBRATE_QUERY_PROBE
TOOL_CALIBRATE_PROBE_OFFSET PROBE="tool_probe T0"
