; CALIBRATE_ALL_OFFSETS on Klipper with the hook overridden to brush the hot nozzle.
G28
CALIBRATE_ALL_OFFSETS
ASSERT TEST='{printer.toolchanger.tool_number == 0}'
ASSERT TEST='{printer["gcode_macro AFC_BRUSH"].count == 2}'
ASSERT TEST='{printer["gcode_macro _CALIBRATION_CLEAN_NOZZLE"].calls == "T0=extruder@150,T1=extruder1@150,"}'
