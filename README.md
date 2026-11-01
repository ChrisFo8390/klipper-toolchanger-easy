# klipper-toolchanger-easy, Kalico edition

A fork of [jwellman80/klipper-toolchanger-easy](https://github.com/jwellman80/klipper-toolchanger-easy) ("KTC-E"), the
configuration, macros and Python modules for StealthChanger style toolchangers in one repository. This fork makes KTC-E
work on **Kalico** as well as on Klipper, and **Kalico stays updatable in Mainsail**.

Use the branch `kalico-plugins` of [ChrisFo8390/klipper-toolchanger-easy](https://github.com/ChrisFo8390/klipper-toolchanger-easy).
The name is historical, it is the branch you use.

* [What is different from the normal KTC-E](#what-is-different-from-the-normal-ktc-e)
* [Do I need this?](#do-i-need-this)
* [What you have to adjust](#what-you-have-to-adjust)
* [Moving from the normal KTC-E to this fork](#moving-from-the-normal-ktc-e-to-this-fork)
* [Fresh install](#fresh-install)
* [Going back](#going-back)
* [What is tested](#what-is-tested)
* [The rest of KTC-E](#the-rest-of-ktc-e): basic configuration, `print_start`, changelog

## What is different from the normal KTC-E

| | Normal KTC-E | This fork |
| --- | --- | --- |
| **Updating Kalico in Mainsail** | Stops working. The installer replaces Kalico's own `klippy/extras/tools_calibrate.py` with a symlink, Moonraker sees a changed repository (`-dirty`) and refuses to update it. | Works. The installer never replaces a file that git tracks, and restores what an old install replaced. |
| **Installer** | Links every module into `klippy/extras`. | Same places. Also migrates old installs, tells you whether Moonraker sees Klipper / Kalico as clean, can be run again, and has options (`--z-probe`, `--no-restart`, `--uninstall`, `--check`, ...: `./install.sh --help`). |
| **Tool probes (TAP per tool) on Kalico** | `tool_probe` and `tool_probe_endstop` do not load: they are written for the probe code of Klipper 2024 and later, Kalico kept the classic one. | They work. `[tool_probe_endstop]` is the default probe and hands `PROBE`, bed mesh, Z tilt, QGL, ... to the probe of the active tool. Homing Z sets Z to the `z_offset` of that probe, as Kalico does for `[probe]`. |
| **`tools_calibrate` on Kalico** | Replaces Kalico's module. | Kalico's own module is used. Ours can be used instead with `--override-tools-calibrate`. |
| **`CALIBRATE_ALL_OFFSETS`** | Reads `tools_calibrate.last_x_result` and friends, which Kalico's module does not have. | Reads `last_result[0..2]`, which both modules have. New hook `_CALIBRATION_CLEAN_NOZZLE` (Klipper and Kalico): clean every hot nozzle on a brush before it is measured. It does nothing unless you override it, see [tools_calibrate.md](tools_calibrate.md#cleaning-the-nozzles-with-a-brush-in-calibrate_all_offsets). |
| **Example tool configs** | No `sense_resistor` for the toolhead TMC2209. | Set to 0.110, Kalico has no default for it. |
| **On Klipper** | | The original code for Klipper's probe API, the code for Kalico next to it. |
| **Tests** | None. | Installer tests and klippy against a simulated MCU on Kalico and Klipper, on every push, see [what is tested](#what-is-tested). |

Background, failure messages and design: [kalico.md](kalico.md).

## Do I need this?

* **Kalico with the normal KTC-E:** yes. Mainsail does not offer Kalico updates, and with a tool probe per tool Kalico
  does not even start.
* **Kalico, fresh:** yes.
* **Klipper:** no difference in what runs, nothing to adjust. You can use the fork, e.g. for the hook.

## What you have to adjust

### Everyone

* If Moonraker updates this repository, point `moonraker.conf` at the fork:
  ```
  [update_manager klipper-toolchanger-easy]
  type: git_repo
  channel: dev
  path: ~/klipper-toolchanger-easy
  origin: https://github.com/ChrisFo8390/klipper-toolchanger-easy.git
  managed_services: klipper
  primary_branch: kalico-plugins
  ```
  then `sudo systemctl restart moonraker` and refresh the Update Manager.

### Kalico only

* **`[tools_calibrate]`:** remove the `probe:` option, Kalico's module does not read it and Kalico refuses options that
  nothing reads. `TOOL_CALIBRATE_PROBE_OFFSET` does not exist in Kalico's module; if you need it, use
  `--override-tools-calibrate` ([kalico.md](kalico.md#tools_calibrate-is-kalicos-own)).
* **Your own macros** that read `printer.tools_calibrate.last_x_result`, `last_y_result`, `last_z_result` or
  `last_probe_offset`: read `last_result[0]`, `[1]`, `[2]` instead. The macros of this repository already do.
* **TMC drivers:** every `[tmc2209 ...]` needs `sense_resistor` on Kalico. If it complains `Option 'sense_resistor' ...
  must be specified`, add `sense_resistor: 0.110` (Klipper's default for the TMC2209).
* **Tool probe per tool (TAP):**
  * `z_offset` of every `[tool_probe]` must be within `position_min` and `position_max` of the Z stepper, Kalico refuses
    it at start-up otherwise.
  * No `[probe]` next to `[tool_probe_endstop]` (as before).
  * No `[mcu]` may be named like a tool (`T1`), Kalico stops with `Duplicate chip name 'T1'`. Call the toolhead board
    `EBBT1` or similar.
  * Z after homing is now the `z_offset` of the probe that homed, like Kalico's `[probe]`. Check your first layer once.

Tool configs, `toolchanger-config.cfg`, the include in `printer.cfg` and your print start macro stay as they are.

### Optional

* **Clean the hot nozzles in `CALIBRATE_ALL_OFFSETS`:** put your brush macro into the hook `_CALIBRATION_CLEAN_NOZZLE`
  in `toolchanger-config.cfg` ([tools_calibrate.md](tools_calibrate.md#cleaning-the-nozzles-with-a-brush-in-calibrate_all_offsets)).
  Without it nothing changes.

## Moving from the normal KTC-E to this fork

You have the normal KTC-E in `~/klipper-toolchanger-easy`, installed with its `install.sh`. Your configuration
(`~/printer_data/config/toolchanger/`, tool files, `toolchanger-config.cfg`) is kept. Do it while the printer is idle.

1. Switch the clone to this fork:
   ```
   cd ~/klipper-toolchanger-easy
   git remote set-url origin https://github.com/ChrisFo8390/klipper-toolchanger-easy.git
   git fetch origin
   git checkout kalico-plugins
   ```
   If git refuses because of local changes in the clone, `git stash` them first, or better move them to
   `toolchanger-config.cfg`, which is meant for that.
2. Run the installer. `--z-probe none` leaves your Z probe configuration alone, `--no-restart` lets you decide when
   Klipper restarts:
   ```
   ./install.sh --z-probe none --no-restart
   ```
   On Kalico expect `[CLEANUP] restored klippy/extras/tools_calibrate.py from git`, `tools_calibrate.py skipped` and
   `[OK] ... Moonraker / Mainsail can update it`.
3. Check what Moonraker sees. The first command must print nothing, the second must not end in `-dirty`:
   ```
   git -C ~/klipper status --short --untracked-files=no
   git -C ~/klipper describe --always --tags --long --dirty
   ```
4. Do the [adjustments](#what-you-have-to-adjust), on Kalico mainly the `moonraker.conf` entry and macros that read
   `last_x_result`.
5. Restart Klipper. If it was in a shutdown state before, use `FIRMWARE_RESTART`, a plain restart does not reset a
   stopped MCU.
6. Refresh the Update Manager in Mainsail. Kalico should be updatable again.

`./install.sh --check` shows at any time what is linked where and whether the tree is clean. It changes nothing.

Add-ons that import these modules (AFC: `from extras.toolchanger import ...`) keep working, the modules stay in
`klippy/extras`. About `--target plugins` and why it is not the default: [kalico.md](kalico.md#the-plugins-folder).

## Fresh install

```
cd ~/
git clone -b kalico-plugins https://github.com/ChrisFo8390/klipper-toolchanger-easy.git
cd ~/klipper-toolchanger-easy
./install.sh
```

Then continue with [Installation](#installation) below for the include in `printer.cfg` and the basic configuration.

## Going back

```
cd ~/klipper-toolchanger-easy
./install.sh --uninstall --no-restart
git remote set-url origin https://github.com/jwellman80/klipper-toolchanger-easy.git
git fetch origin
git checkout main
./install.sh
```

`--uninstall` removes the links of this repository and restores files of Klipper / Kalico that were replaced, your
configuration is kept. On Kalico you are then back at the problem this fork solves.

## What is tested

[`ci.yml`](.github/workflows/ci.yml) runs on every push:

* the installer on fake Klipper and Kalico trees (fresh, again, migration, uninstall): git must see no change to a
  tracked file afterwards,
* klippy against a simulated MCU on Kalico `main` (Python 3.9 and 3.12) and on Klipper `master`, with the installed
  configuration: tool probes, Z homing, probing, bed mesh, Z tilt, tool changes, `CALIBRATE_ALL_OFFSETS` (with and
  without a brush in the hook), `multi_fan`, `manual_rail`, `bed_thermal_adjust`, and the `extras.toolchanger` import
  of add-ons like AFC,
* the unmodified upstream on Kalico (it does not work, the job shows how).

On a real printer (Kalico, Cartographer as Z probe, AFC) this fork was run through: the installer, the migration from the
normal KTC-E, updating Kalico from Mainsail afterwards, and the modules loading together with AFC. **Simulator only:**
the tool probe code on Kalico (TAP per tool), crash detection timing, tool detection with several tool probes, QGL, tool
changes, and the offsets that `CALIBRATE_ALL_OFFSETS` measures. Please report what you find.

## Please Read this before starting!
The purpose of (yet another) fork of the Viesturz/klipper-toolchanger repo is to attempt to simplify the installation for StealthChanger users.  This repo combines the configuration, macros, and Python into a single repo.  It also outlines patterns for overriding configuration to ease installation and allow easier updates. 

All of the documentation for StealthChanger still applies and should be what you're following (except the Installation portion) https://github.com/DraftShift/StealthChanger/wiki

**This assumes you have a WORKING PRINTER and configuration**

Requires Klipper 0.13.0-707 or greater, or Kalico.

## Upgrading from the old Klipper Tool Changer Easy
[Upgrade instructions](upgrade.md)

# The rest of KTC-E

Everything below is as in the normal KTC-E.

## Installation

This is what `install.sh` does, run as shown in [Fresh install](#fresh-install) or [Moving](#moving-from-the-normal-ktc-e-to-this-fork):
- symlinks the needed Python files into `klipper/klippy/extras`, except files that Klipper or Kalico has of its own (Kalico: `tools_calibrate.py`, see [kalico.md](kalico.md))
- symlinks the gcode macros to `~/printer_data/config/toolchanger/readonly-configs`
- copies some example tools into `~/printer_data/config/toolchanger/tools`
- copies user editible config into `~/printer_data/config/toolchanger`

Running `install.sh` multiple times is a safe operation, provided you follow the instructions below about configuration.

Add the following to your `printer.cfg`
```
[include toolchanger/readonly-configs/toolchanger-include.cfg]
```

## Changelog
* 2026.11.2 - `CALIBRATE_ALL_OFFSETS` calls the hook `_CALIBRATION_CLEAN_NOZZLE` for every tool before it is measured, to clean the hot nozzle on a brush, see [tools_calibrate.md](tools_calibrate.md). It does nothing by default. The heater of tool 0 now starts before it moves over the probe, and the macro waits for the extruder of tool 0, not for the one that was active when the macro started.
* 2026.11.1 - Kalico support: the installer no longer replaces Kalico's own `tools_calibrate.py` (Kalico stays updatable), tool probe modules for Kalico's probe code, see [kalico.md](kalico.md).
* 2026.1.25 - Example script for camera tool alignment.
* 2025.12.26 - **Breaking change** Stop using Gcode offset for tool offsets. Uses a dedicated gcode transform instead.
* 2025.12.25 - Use Bezier curves for rounded paths.
* 2025.12.25 - Manual rail update to latest Klipper.

## Updates that add new files

Note that if an update has new klipper files, they **will not** be automatically installed into Klipper.
You will need to run the install script manually to add them:
```commandline
bash ~/klipper-toolchanger-easy/install.sh --z-probe none
```

# VERY BASIC CONFIGURATION
At a minimum you will need to: 
- Set the dock position for each tool in the `toolchanger/tools/Tx.cfg` file
- look through the `toolchanger-config.cfg` and configure the following:
  - `homing_override_config` 
  - `_CALIBRATION_SWITCH` if using a calibration probe set its position here.  Also update the `tools_calibrate`

Tool configs must be named Tx.cfg (T0.cfg, T1.cfg, etc)

Follow the examples in the `example_T0.cfg` and `example_T1.cfg`.  The main difference between the tools is that T0 has a z_offset and other tools will not.  T1 and up will have gcode_offsets set and T0 will not.  Other than that the configuration between T0 and other tools is very similar.  

If using the TAP for Z probing then when starting up you will need a tool on the shuttle or Klipper will shut down.  You should always home, Quad Gantry Level, and bed mesh with T0.  

Highly recommend that you DO NOT EDIT the files in `~/printer_data/config/toolchanger/readonly-configs`
If you need to modify or config something in those files use the `~/printer_data/config/toolchanger/toolchanger-config.cfg` file to override the macro or the setting in the macro.  `toolchanger-config.cfg` has examples of how this is accomplished. 

# Print_Start Macro
Edit your existing print start macro to have the following: 

Top of `print_start` macro
```
    {% set TOOL = params.TOOL | default(-1)| int %}
    {% set TOOL_TEMP = params.TOOL_TEMP | default(0) | int %}
    {% set BED_TEMP = params.BED_TEMP | default(0) | int %}

    STOP_CRASH_DETECTION

    M117 Heating Bed
    M190 S{BED_TEMP}

    M117 Homing
    G28
    T0

    M117 Quad Gantry Level
    QUAD_GANTRY_LEVEL
    G28 Z
```

Bottom of `print_start` macro:
```
    {% if TOOL >= 0 %}
        M104 T0 S0 ; shutdown T0.  If it's up first it will be heated below.
        T{params.TOOL}
        {% set initialToolTemp = 'T' ~ params.TOOL|string ~ '_TEMP' %}
        M117 Waiting on T{params.TOOL} S{params[initialToolTemp]}C
        M109 S{params[initialToolTemp]}
    {% else %}
        M109 S{TOOL_TEMP}
    {% endif %}

    START_CRASH_DETECTION
    
```

Follow the Slicer configuration in the DraftShift Design Wiki:
https://github.com/DraftShift/StealthChanger/wiki/Slicers
