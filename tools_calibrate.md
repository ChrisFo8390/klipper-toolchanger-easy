# Tools calibrate

An extension to calibrate tool offsets with a nozzle contact probe.
Works by bumping the nozzle into the probe form multiple angles to pinpoint the nozzle location.

See [Nozzle Align](https://github.com/viesturz/NozzleAlign) repo for some sensor ideas.

### Configuration

See the [example](/examples/calibrate-offsets.cfg) folder for a full example.
```
[tools_calibrate]

pin: GPIO pin (e.g., '^PG11')
     The pin Klipper will monitor to detect a probe trigger.
     - depending on probe may require inversion (ie: !PG11)
     - normally closed: nudge (no inversion)
     - normally open: sexball [microswitch type] (inversion)

spread:               (mm)
    X/Y distance from center for probing sequence
    This defines how far the tool moves during the touch pattern.
    - For large pins (≥5mm), use 3.5-4.0 
    - Larger values = more overtravel, takes longer, safer for larger variance in tools or larger pins
    - Smaller values = less overtravel but may hit too early for large variance tools/large pins
    - Example: a 5mm pin, a 2.5mm spread would touch the pins face. (assuming nozzle = cylinder with 0 width)

lower_z:              (mm)
   Distance to lower the nozzle to hit. (0 -> slides over | 3-4 -> hits silicone sock)
   - 0.1-0.2 = minimal travel, may work, usually cleaner nozzle around here
   - 0.4-0.5 = safer hit margin, possibly less accurate.

travel_speed:         (mm/s)
   Move speed between probes 
   - 0.1-infinity (really doesnt matter that much)

speed:                (mm/s)
   move speed during probes 
   - too slow -> takes forever | too fast -> not accurate enough
   - 0.5-10 would be an average/sane range

lift_speed:           (mm/s)
   speed with which to raise Z

final_lift_z:         (mm)
   Distance to raise Z between/after probing.
   Will also the the distance its waiting above the probe.

sample_retract_dist:  (mm)
   Z retract between samples (Z) 
   - too little -> backlash/doesnt untrigger | too much -> moves up too high/takes longer.
   - 0.2-5 

samples: 
    Number of probe samples to take (usually 3-5)

samples_tolerance:    (mm) 
     Max variance allowed between samples (will retry/abort if exceeded)
     a good probe will work with 0.05, altho increasing it has no effect on results.
     more a "sanity check" then anything else.

samples_tolerance_retries: 
     the amount of times to retry the probing when the sample tolerance has been exceeded.

samples_result:       ['median' | 'average']
     output result method 
     
trigger_to_bottom_z:  (mm)
    Used in trigger calibration calculations.
    Defines Z distance from calibration probe *trigger* to mechanical bottom out.
    sort of like the distance from when your keyboard key registers a hit, to where it actually hits the bottom.
    - 0-3 best calibrated by setting it to 0, 
      running TOOL_CALIBRATE_PROBE_OFFSET and substracting the result from your current probe offset.
    - decrease if the nozzle is too high, increase if too low.

probe: probe 
     (optional name of the nozzle probe to use)
```

### On Kalico

Kalico has a `tools_calibrate` of its own, which the installer keeps. It has the same commands, apart from
`TOOL_CALIBRATE_PROBE_OFFSET`, and no `probe` option. To use this one instead, see [kalico.md](kalico.md#tools_calibrate-is-kalicos-own).
In macros read the result as `printer.tools_calibrate.last_result[0]`, `[1]`, `[2]` (x, y, z), that works with both.

### Cleaning the nozzles with a brush in CALIBRATE_ALL_OFFSETS

`CALIBRATE_ALL_OFFSETS` picks up every tool, heats it to 150 C and measures it on the calibration probe. A hook lets you
clean the hot nozzle first. `_CALIBRATION_CLEAN_NOZZLE` is called for every tool once it is picked up and its heater is on,
before it moves over the probe, and does nothing until you override it in `toolchanger-config.cfg`. It gets
`T` (tool number), `EXTRUDER` (name of its extruder) and `TEMP` (150).

```
[gcode_macro _CALIBRATION_CLEAN_NOZZLE]
gcode:
    G90
    G0 Z{printer["gcode_macro _CALIBRATION_SWITCH"].z} F10000
    TEMPERATURE_WAIT SENSOR={params.EXTRUDER} MINIMUM={params.TEMP}
    CLEAN_NOZZLE
```

* Go to a safe Z before moving in XY, the hook does not know where the toolhead is. The height of the calibration switch
  is a good choice, `CALIBRATE_MOVE_OVER_PROBE` moves at that height too.
* Wait for the temperature in the hook, the brush works on a hot nozzle. The macro waits again before measuring,
  which is instant when the nozzle is hot.
* Leave the nozzle at `TEMP` for the measurement. The length of the nozzle depends on its temperature, so all tools must be
  measured at the same one.

### Clean your nozzles 

The calibration accuracy is as good as your nozzles are clean. 
Clean all nozzles thoroughly before calibrating.

### Calibrating tool offsets

- First position the nozzle approximately above the probe - the probe will find the center on it's own within 1-2 mm.

- The first tool has all offsets to 0 and is used as a baseline for other tools. Run ```TOOL_LOCATE_SENSOR``` to calibrate nozzle location for tool 0.

- For every other tool, run ```TOOL_CALIBRATE_TOOL_OFFSET``` to measure the offset from the first tool.

All probing moves and final offsets will be printed in the console.

### Calibrating nozzle bed probe.

- Do the first two steps from above to ensure the probe is precisely under the nozzle.

- Run TOOL_CALIBRATE_PROBE_OFFSET - to measure Z offset from nozzle triggering the probe to tool's nozzle probe activating.

All probing moves and final offsets will be printed in the console.


## Troubleshooting

### Probe triggered prior to movement
- the nozzle is not touching the probe
  - Check if the probe is triggering without touching  
  - use a multimeter to check for continuity and if it changes when pressing down on the probe. (or use `TOOL_CALIBRATE_QUERY_PROBE` to query the status of the probe)
  - Check if the pin is configured correctly. The example configuration is for active low with a pullup. Depending how you have wired it, you might need remove the **^!** for active-high.
  
- the nozzle is touching the probe - (and could have probed a few times already)
  - Likely the initial position was too far off-center. Try to position it more accurately.
  - The probe is lowered too much and/or not enough sideways - tweak `lower_z` and `spread`
