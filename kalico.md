# KTC-E on Kalico

[Kalico](https://github.com/KalicoCrew/kalico) is a fork of Klipper. This repository runs on both. On Kalico the
modules are installed into `klippy/plugins` instead of `klippy/extras`, which keeps Kalico updatable from
Mainsail / Moonraker, and the tool probe modules use Kalico's probe code.

* [Install](#install-on-kalico)
* [Already installed with the old installer?](#already-installed-with-the-old-installer)
* [What was wrong](#what-was-wrong-with-ktc-e-on-kalico)
* [What changed](#what-changed)
* [Differences you will notice](#differences-you-will-notice-on-kalico)
* [How it is tested, and what is not](#how-it-is-tested)

## Install on Kalico

The Kalico support is in the branch `kalico-plugins` of
[ChrisFo8390/klipper-toolchanger-easy](https://github.com/ChrisFo8390/klipper-toolchanger-easy), a fork of
[jwellman80/klipper-toolchanger-easy](https://github.com/jwellman80/klipper-toolchanger-easy). Until it is part of
upstream, clone that:

```
cd ~/
git clone -b kalico-plugins https://github.com/ChrisFo8390/klipper-toolchanger-easy.git
cd ~/klipper-toolchanger-easy
./install.sh
```

`install.sh` looks at `~/klipper`: if it has a `klippy/plugins` folder it is Kalico and everything goes there.
It prints at the end whether Moonraker will accept the folder as clean:

```
[OK] /home/pi/klipper has no changes to tracked files: Moonraker / Mainsail can update it
```

Options, all optional (`./install.sh --help`):

| Option | |
| --- | --- |
| `--target auto\|extras\|plugins` | Where the modules go. `auto` (default): `plugins` on Kalico, `extras` on Klipper. |
| `--z-probe tap\|shuttle\|none` | Answer the question about how you probe Z, for scripts. |
| `--override-tools-calibrate` | Kalico only, see [tools_calibrate](#tools_calibrate-is-kalicos-own). |
| `--no-requirements`, `--no-restart` | Skip installing the Python requirements / restarting Klipper. |
| `--uninstall` | Remove the links of the modules, keep your configuration. |
| `--check` | Report what is installed and whether Klipper / Kalico is clean. Changes nothing. |

`KLIPPER_PATH`, `KLIPPY_ENV_PATH`, `INSTALL_PATH`, `CONFIG_PATH` can be set in the environment for other locations.

To keep the repository itself updated from Mainsail use the `[update_manager]` section from the [README](README.md), with
`origin` and `primary_branch` of what you cloned (`kalico-plugins` above).
Updating Kalico does not touch the links, `klippy/plugins` is ignored by git. After an update of this repository that
adds a module, run `./install.sh` again, as before.

## Already installed with the old installer?

The old `install.sh` linked all modules into `klippy/extras`. On Kalico that replaced Kalico's own
`klippy/extras/tools_calibrate.py` by a link: a change to a file git tracks. Moonraker refuses to update a repository
like that (`git describe` ends in `-dirty`), which is why Kalico stopped showing updates in Mainsail.

Get the new version of this repository and run the new installer, it cleans that up:

```
cd ~/klipper-toolchanger-easy
git remote set-url origin https://github.com/ChrisFo8390/klipper-toolchanger-easy.git   # until it is part of upstream
git fetch origin
git checkout kalico-plugins
./install.sh
```

```
[CLEANUP] removed /home/pi/klipper/klippy/extras/tools_calibrate.py
[CLEANUP] restored klippy/extras/tools_calibrate.py from git
...
[OK] /home/pi/klipper has no changes to tracked files: Moonraker / Mainsail can update it
```

It removes the links to this repository from `klippy/extras`, restores tracked files from git and links the modules into
`klippy/plugins`. Links that do not point to this repository are not touched. Afterwards press the refresh button of
the Update Manager in Mainsail. To see for yourself:

```
git -C ~/klipper status --short --untracked-files=no     # prints nothing when it is clean
git -C ~/klipper describe --always --tags --long --dirty  # must not end in -dirty
```

By hand, if you prefer:

```
cd ~/klipper
git checkout -- klippy/extras/tools_calibrate.py        # puts Kalico's own file back
find klippy/extras -maxdepth 1 -type l -lname '*klipper-toolchanger-easy*' -delete
```

and run `./install.sh`.

If you installed these modules by other means (copying files, or a different clone) and `git status` still shows
changes, `git -C ~/klipper checkout -- <file>` restores a file of Kalico. Do not run `git checkout .` or `git clean`
blindly if you changed Kalico yourself.

## What was wrong with KTC-E on Kalico

There were two problems. The first one is the one you see in Mainsail, the second one stops you earlier if you use a
tool probe (TAP) per tool.

### 1. The installer made Kalico "dirty"

Kalico has no `toolchanger.py`, `tool.py` and so on, so those links were harmless. But Kalico ships a `tools_calibrate.py`
of its own (it started as the same code), and the installer's `ln -sfn` replaced that tracked file with a symlink. For
Moonraker, a tracked file that is modified or has changed type means "the repository was changed locally": it will not
update it, and `Recover` would throw the change away. The same would happen with any other module that exists in both.

Kalico has a place for modules that are not part of it: `klippy/plugins`. It is listed in Kalico's `.gitignore` (except
its `__init__.py`), so git and Moonraker do not see what is in there. Kalico loads it like `klippy/extras`. If a plugin
has the name of a module in `klippy/extras`, Kalico stops with `Module '...' found in both extras and plugins!`, unless
`[danger_options] allow_plugin_override: True` is set.

### 2. `tool_probe` and `tool_probe_endstop` do not load

Klipper rewrote `probe.py` in 2024 (`ProbeCommandHelper`, `ProbeParameterHelper`, `ProbeOffsetsHelper`,
`HomingViaProbeHelper`, `start_probe_session`, ...). `tool_probe.py` and `tool_probe_endstop.py` are written for that.
Kalico kept the classic design (`PrinterProbe(config, mcu_probe)`, `ProbeEndstopWrapper(config)`,
`ProbePointsHelper`) and added `ProbeList` (several named probes, `PROBE=<name>`) on top. So with a `[tool_probe]`
section Kalico stops with

```
AttributeError: module 'klippy.extras.probe' has no attribute 'ProbeParameterHelper'
```

and if you link the unmodified modules into `klippy/plugins` to get around problem 1, with

```
ImportError: cannot import name 'probe' from 'klippy.plugins'
```

because a module in `klippy/plugins` is imported as `klippy.plugins.<name>`, so `from . import probe` looks in the wrong
package. Both are reproduced in CI against the unmodified upstream, see the job "Unmodified upstream on Kalico".

If you probe Z with a shuttle mounted probe (Beacon, Cartographer, Eddy, ...) `tool_probe` is not used, and only
problem 1 applies to you.

## What changed

| File | Change |
| --- | --- |
| `install.sh` | On Kalico, link into `klippy/plugins`; keep Kalico's `tools_calibrate`; clean up old installs; report whether the tree is clean; options above. Klipper installs work as before. |
| `klipper/extras/tool_probe.py` | New-Klipper implementation unchanged. On Kalico a tool probe is a `PrinterProbe` that does not register as the default probe. |
| `klipper/extras/tool_probe_endstop.py` | New-Klipper implementation unchanged. On Kalico, `KalicoToolProbeEndstop` is the default probe (`probe`): it gives `PROBE`, `QUERY_PROBE`, bed mesh, Z tilt, QGL, ... to the probe of the active tool, and routes `probe:z_virtual_endstop` to that probe's endstop. |
| `klipper/extras/manual_rail.py`, `multi_fan.py` | Imports that also work from `klippy/plugins`. |
| `klipper/extras/tools_calibrate.py` | `TOOL_CALIBRATE_PROBE_OFFSET` also works with Kalico's probe. Only matters with `--override-tools-calibrate`. |
| `examples/easy-additions/calibrate-offsets.cfg` (and the older `examples/calibrate-offsets.cfg`) | Read the result of `tools_calibrate` as `last_result[0..2]`, which both versions have. |
| `examples/**/example_T*.cfg`, `T0.cfg`, `toolhead_n.cfg` | `sense_resistor: 0.110` for the `[tmc2209 extruder]` sections. Kalico has no default for it (Klipper uses 0.110). |
| `.gitattributes` | Keeps `install.sh` on LF when checked out on Windows. |
| `tests/`, `.github/workflows/ci.yml` | Tests, see below. |

Nothing changes for a Klipper install: the Klipper code path of both probe modules is the original code.

Homing Z on a tool probe sets Z to the `z_offset` of that probe, like Kalico does for its own `[probe]`. The Z stepper
reads where it homes to once, when the configuration is loaded, so the router sets it again whenever the active tool
probe changes. A `z_offset` that the Z stepper can not reach (outside `position_min` .. `position_max`) is refused when
Klipper connects, as Kalico does for `[probe]`.

On Kalico `[tool_probe_endstop]` is the object `probe`, so `printer.probe.*` works in macros (`homing.cfg` uses
`printer.probe.last_query`), as does `printer.tool_probe_endstop.*`. The tool probes are listed by `LIST_PROBES` under
their tool name, and `PROBE PROBE=T1` or `QUERY_PROBE PROBE=T1` address one of them directly. You can not have a
`[probe]` section next to `[tool_probe_endstop]`, as before.

## Differences you will notice on Kalico

### `tools_calibrate` is Kalico's own

The installer does not link our `tools_calibrate.py`, Kalico's is used. It is the same idea with the same commands
(`TOOL_LOCATE_SENSOR`, `TOOL_CALIBRATE_TOOL_OFFSET`, `TOOL_CALIBRATE_SAVE_TOOL_OFFSET`, `TOOL_CALIBRATE_QUERY_PROBE`) and the
same options, plus `spread_x`, `spread_y`, `initial_spread_x`, `initial_spread_y`. Differences:

* No `TOOL_CALIBRATE_PROBE_OFFSET`, and no `probe:` option in `[tools_calibrate]` (Klipper and Kalico refuse options that
  nothing reads: `Option 'probe' is not valid in section 'tools_calibrate'`, so leave it out). `CALIBRATE_NOZZLE_PROBE_OFFSET`
  tells you so instead of failing with an unknown command.
* The status has `last_result` (x, y, z) but not `last_x_result`, `last_y_result`, `last_z_result`, `last_probe_offset`.
  The macros of this repository use `last_result`. Your own macros need the same change if they use the others.
* `last_result` is `None` after the motors were switched off.
* The output of `TOOL_CALIBRATE_TOOL_OFFSET` looks different.

If you want the module of this repository on Kalico (for `TOOL_CALIBRATE_PROBE_OFFSET`, or to keep exactly the behaviour
you had), install it as an override. Both lines are needed:

```
[danger_options]
allow_plugin_override: True
```

```
./install.sh --override-tools-calibrate
```

Without `allow_plugin_override` Kalico does not start (`found in both extras and plugins`), that is why it is not the
default. It does not make Kalico dirty either. Running `./install.sh` again without the option keeps it linked,
`./install.sh --uninstall` removes it with the rest.

### Other Kalico behaviour

* `sense_resistor` is required in every `[tmc2209 ...]` section and the other drivers. Klipper assumes 0.110 for the TMC2209.
* A `[tool_probe]` takes the options of Kalico's `[probe]` too (`drop_first_result`, `lift_speed`, the `retry_*` options, ...).
* A tool probe is a Kalico probe named after the tool (`[tool_probe T1]` is `T1`, also a pin chip name). The name must not
  be the name of an `[mcu]`, otherwise Kalico stops with `Duplicate chip name 'T1'`. Name the board `EBBT1` or similar.
* Moonraker updates Kalico with `git pull`, so the links in `klippy/plugins` survive.

## How it is tested

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push:

* **install.sh**: [`tests/installer/test_install.sh`](tests/installer/test_install.sh) on fake Klipper and Kalico trees:
  fresh install, second run, user files are kept, migration of an old install, `--override-tools-calibrate`, `--uninstall`,
  `--check`, refusing `--target plugins` on Klipper. After each step it checks that git sees no change to a tracked file.
* **Kalico**: [`tests/kalico/run.sh`](tests/kalico/run.sh) takes a real Kalico checkout (`main`, and the version this was
  developed against, Python 3.9 and 3.12), reproduces what the old installer did (Kalico becomes dirty), installs with
  `install.sh`, checks that Kalico is clean, and then runs Kalico's own test harness (klippy against a simulated MCU)
  with these configurations:
  * `ktce_basic`: two tools with a tool probe each. Homing Z with each probe (and that Z ends up at the `z_offset` of
    that probe), `PROBE`, `PROBE_ACCURACY`,
    `PROBE PROBE=T1`, `Z_TILT_ADJUST`, `BED_MESH_CALIBRATE`, switching the active probe, tool changes, crash detection
    commands, `TOOL_LOCATE_SENSOR` / `TOOL_CALIBRATE_TOOL_OFFSET` with Kalico's own `tools_calibrate`.
  * `ktce_easy`: the configuration `install.sh` creates (homing override, tool detection, crash detection, tap activation,
    calibration macros) with a tool on its own board.
  * `ktce_override`: our `tools_calibrate` with `allow_plugin_override`, including `TOOL_CALIBRATE_PROBE_OFFSET`.
  * `ktce_modules`: `multi_fan`, `manual_rail` (homing and moves) and `bed_thermal_adjust`.
  * A `z_offset` outside of the range of the Z stepper is refused.
  * Kalico's own `bed_mesh_default`, `commands` and `tools_calibrate` tests still pass with the modules installed.
  * Without `allow_plugin_override` Kalico really refuses a second `tools_calibrate`.
  * `--uninstall` leaves Kalico clean.
* **Klipper**: [`tests/klipper/run.sh`](tests/klipper/run.sh) installs into a Klipper checkout (`master`) and runs the
  same two configurations with klippy against a simulated MCU. This is the code path for Klipper's own probe API, which
  must keep working.
* **Unmodified upstream on Kalico**: shows problems 1 and 2 above on the original code.

The simulator reports every probe pin as open and every move as completed. So this does **not** test: real triggering
on a printer, the timing of crash detection, tool detection with several tools (the test selects the active probe by
command), QGL (Z tilt uses the same code), and Kalico versions other than the ones in the matrix. The tool probe
code of Kalico's `PrinterProbe` is used as it is; the new part is the router that picks the probe of the active tool.
Please report what you find on a real printer.
