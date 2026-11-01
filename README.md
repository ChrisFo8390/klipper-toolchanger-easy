# klipper-toolchanger-easy, Kalico edition

A fork of [jwellman80/klipper-toolchanger-easy](https://github.com/jwellman80/klipper-toolchanger-easy) ("KTC-E"), which
combines the configuration, macros and Python modules of [Viesturz/klipper-toolchanger](https://github.com/viesturz/klipper-toolchanger)
for StealthChanger style toolchangers. This fork makes KTC-E work on **Kalico** as well as on Klipper, without stopping
Mainsail from updating Kalico.

The Kalico support lives in the branch `kalico-plugins` of
[ChrisFo8390/klipper-toolchanger-easy](https://github.com/ChrisFo8390/klipper-toolchanger-easy). The name is historical,
it is the branch you use.

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
| **Updating Kalico in Mainsail** | Stops working. The installer replaces Kalico's own `klippy/extras/tools_calibrate.py` with a symlink, Moonraker sees a changed repository (`-dirty`) and refuses to update it. | Works. The installer never replaces a file that git tracks, and puts back what an old install replaced. |
| **Installer** | Links every module into `klippy/extras`, asks one question. | Same places, but protects tracked files, migrates old installs, and reports at the end whether Moonraker will accept Klipper / Kalico as clean. New options: `--z-probe`, `--no-restart`, `--no-requirements`, `--target`, `--uninstall`, `--check`, `--override-tools-calibrate`. Safe to run again. |
| **Tool probes (TAP per tool) on Kalico** | `tool_probe` and `tool_probe_endstop` do not load: they are written for the probe code of Klipper (2024 and later), Kalico kept the classic one. | They work. On Kalico `[tool_probe_endstop]` is the default probe and hands `PROBE`, bed mesh, Z tilt, QGL, ... to the probe of the active tool. Homing Z on a tool probe sets Z to the `z_offset` of that probe, as Kalico does for `[probe]`. |
| **`tools_calibrate` on Kalico** | Replaces Kalico's module. | Kalico's own module is used (same idea, same commands). Ours can be used instead with `--override-tools-calibrate`. |
| **Offset macros** | Read `tools_calibrate.last_x_result` and friends, which Kalico's module does not have. | Read `last_result[0..2]`, which both modules have. |
| **Example tool configs** | No `sense_resistor` for the toolhead TMC2209. | Set (0.110), Kalico has no default for it. |
| **On Klipper** | | The code for Klipper's probe API is the original code, added next to it is the one for Kalico. The installer behaves as before. |
| **Tests** | None. | Installer tests on fake trees, and klippy against a simulated MCU on Kalico and Klipper, on every push. See [what is tested](#what-is-tested). |

The background, the exact failure messages and the design are in [kalico.md](kalico.md).

## Do I need this?

* **Kalico, installed with the normal KTC-E:** yes. Mainsail does not offer Kalico updates because of it, and if you use
  a tool probe per tool, Kalico does not even start with the `[tool_probe]` sections.
* **Kalico, fresh:** yes, use this fork from the start.
* **Klipper:** no difference in what runs. You can use this fork, nothing to adjust.

## What you have to adjust

### Everyone

* Point your `moonraker.conf` at the fork, if you let Moonraker update this repository:
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
* After an update of this repository that adds a Python module, run `./install.sh --z-probe none` again, as before.

### Kalico only

* **`[tools_calibrate]`:** remove the `probe:` option if you have it. Kalico's module does not read it, and Kalico (like
  Klipper) refuses options that nothing reads. `TOOL_CALIBRATE_PROBE_OFFSET` does not exist in Kalico's module: do you
  need it? Then use `--override-tools-calibrate` (see [kalico.md](kalico.md#tools_calibrate-is-kalicos-own)).
* **Your own macros** that read `printer.tools_calibrate.last_x_result`, `last_y_result`, `last_z_result` or
  `last_probe_offset`: read `printer.tools_calibrate.last_result[0]`, `[1]`, `[2]` instead. The macros of this repository
  already do.
* **TMC drivers:** every `[tmc2209 ...]` (and the other drivers) needs `sense_resistor` on Kalico. Klipper assumes 0.110
  for the TMC2209. If Kalico complains `Option 'sense_resistor' ... must be specified`, add `sense_resistor: 0.110`.
* **If you use a tool probe per tool (TAP):**
  * `z_offset` of every `[tool_probe]` must be reachable by the Z stepper: between its `position_min` and `position_max`.
    Kalico refuses it at start-up otherwise, as for its own `[probe]`.
  * There must be no `[probe]` section next to `[tool_probe_endstop]` (as before).
  * The name of a tool probe is its tool name (`[tool_probe T1]` is `T1`). No `[mcu]` may have that name, otherwise
    Kalico stops with `Duplicate chip name 'T1'`. Name the toolhead board `EBBT1` or similar.
  * Z after homing is now the `z_offset` of the probe that homed, like Kalico's `[probe]`. Check your first layer once.

You do not have to change tool configs, the `toolchanger-config.cfg`, your `printer.cfg` includes or your print start macro.

## Moving from the normal KTC-E to this fork

You have the normal KTC-E in `~/klipper-toolchanger-easy`, installed with its `install.sh`. This keeps your configuration
(`~/printer_data/config/toolchanger/`), tool files and `toolchanger-config.cfg`. Do it while the printer is idle.

1. Switch the clone to this fork:
   ```
   cd ~/klipper-toolchanger-easy
   git remote set-url origin https://github.com/ChrisFo8390/klipper-toolchanger-easy.git
   git fetch origin
   git checkout kalico-plugins
   ```
   If git refuses because of local changes in that clone, run `git stash` first, or better move your changes to
   `toolchanger-config.cfg`, which is meant for that.
2. Run the installer. `--z-probe none` leaves your Z probe configuration alone (otherwise it asks, and links the include and
   example tool files for the option you choose). `--no-restart` so that you decide when Klipper restarts:
   ```
   ./install.sh --z-probe none --no-restart
   ```
   On Kalico expect `[CLEANUP] restored klippy/extras/tools_calibrate.py from git`, then `tools_calibrate.py skipped`
   and `[OK] ... Moonraker / Mainsail can update it`.
3. Check what Moonraker sees. The first command must print nothing, the second must not end in `-dirty`:
   ```
   git -C ~/klipper status --short --untracked-files=no
   git -C ~/klipper describe --always --tags --long --dirty
   ```
4. Do the [adjustments](#what-you-have-to-adjust) above, for Kalico mainly the `moonraker.conf` entry and macros that read
   `last_x_result`.
5. Restart Klipper (`sudo systemctl restart klipper`, or the restart button in Mainsail). If Klipper was in a
   shutdown state before, use `FIRMWARE_RESTART` instead, a plain restart does not reset a stopped MCU.
6. Refresh the Update Manager in Mainsail. Kalico should be updatable again.

`./install.sh --check` shows at any time what is linked where and whether the tree is clean. It changes nothing.

If something else on your printer imports these modules, it keeps working: the modules stay in `klippy/extras`, so
`from extras.toolchanger import ...` (AFC does that) finds them. See [kalico.md](kalico.md#the-plugins-folder) for
the `--target plugins` alternative and why it is not the default.

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

The first command removes the links of this repository and restores files of Klipper / Kalico that were replaced. Your
configuration is kept. On Kalico you are then back at the problem this fork solves.

## What is tested

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push:

* the installer on fake Klipper and Kalico trees (fresh, again, migration, uninstall, ...): checks that git sees no
  change to a tracked file afterwards,
* klippy against a simulated MCU on Kalico `main` (Python 3.9 and 3.12, currently v2026.11.00), with the installed
  configuration: tool probes, Z homing position, probing, bed mesh, Z tilt, tool changes, the macros,
  `multi_fan`, `manual_rail`, `bed_thermal_adjust`, and the `extras.toolchanger` import of add-ons like AFC,
* the same on Klipper `master`, for the code path of Klipper's own probe API,
* what the unmodified upstream does on Kalico (it does not work, the job shows how).

On a real printer, this fork runs on a Kalico printer with a Cartographer as Z probe and AFC: the installer, the
migration from the normal KTC-E, updating Kalico from Mainsail afterwards, and the toolchanger modules loading together
with AFC. **Not tested on a real printer:** the tool probe code on Kalico (TAP per tool), crash detection timing, tool
detection with several tool probes, QGL, and tool changes on Kalico with this version. These are tested in the
simulator only. Please report what you find.

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
