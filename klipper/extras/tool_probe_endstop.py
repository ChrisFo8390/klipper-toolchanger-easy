# Per-tool Z-Probe support
#
# Copyright (C) 2023 Viesturs Zarins <viesturz@gmail.com>
#
# This file may be distributed under the terms of the GNU GPLv3 license.
import pins
try:
    from . import probe
except ImportError:
    # Kalico loads modules of klippy/plugins as klippy.plugins.<name>, so the
    # relative import does not find the modules of klippy/extras.
    from klippy.extras import probe

# Klipper changed the probe code in 2024 (ProbeCommandHelper, ProbeSessionHelper,
# ...). Kalico kept the classic PrinterProbe/ProbeEndstopWrapper design and
# added a list of probes (ProbeList) on top of it. Both are supported, see
# KalicoToolProbeEndstop below for the Kalico one.
KALICO_PROBE_API = (hasattr(probe, 'ProbeList')
                    and not hasattr(probe, 'ProbeCommandHelper'))

# Virtual endstop, using a tool attached Z probe in a toolchanger setup.
# Tool endstop change may be done either via SET_ACTIVE_TOOL_PROBE TOOL=99
# Or via auto-detection of single open tool probe via DETECT_ACTIVE_TOOL_PROBE
class ToolProbeEndstop:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.reactor = self.printer.get_reactor()
        self.name = config.get_name()
        self.tool_probes = {}
        self.last_query = {} # map from tool number to endstop state
        self.active_probe = None
        self.active_tool_number = -1
        self.gcode_macro = self.printer.load_object(config, 'gcode_macro')
        self.crash_detection_active = False
        self.crash_lasttime = 0.
        self.mcu_probe = EndstopRouter(self.printer)
        self.param_helper = probe.ProbeParameterHelper(config)
        self.cmd_helper = probe.ProbeCommandHelper(config, self,
                                                   self.mcu_probe.query_endstop)
        # Current Klipper only uses position_endstop to identify virtual
        # probe homing. The active probe session supplies the actual offset.
        probe.HomingViaProbeHelper(config, 0.0, self.mcu_probe.query_endstop)
        self.probe_session = probe.SampleAveragingHelper(
            config, self.param_helper, self.mcu_probe.start_probe_session)

        # Emulate the probe object, since others rely on this.
        if self.printer.lookup_object('probe', default=None):
            raise self.printer.config_error('Cannot have both [probe] and [tool_probe_endstop].')
        self.printer.add_object('probe', self)

        self.crash_mintime = config.getfloat('crash_mintime', 0.5, above=0.)
        self.crash_gcode = self.gcode_macro.load_template(config, 'crash_gcode', '')
        self.printer.register_event_handler("klippy:connect",
                                            self._handle_connect)
        # Register PROBE/QUERY_PROBE commands
        self.gcode = self.printer.lookup_object('gcode')
        self.gcode.register_command('SET_ACTIVE_TOOL_PROBE', self.cmd_SET_ACTIVE_TOOL_PROBE,
                                    desc=self.cmd_SET_ACTIVE_TOOL_PROBE_help)
        self.gcode.register_command('DETECT_ACTIVE_TOOL_PROBE', self.cmd_DETECT_ACTIVE_TOOL_PROBE,
                                    desc=self.cmd_DETECT_ACTIVE_TOOL_PROBE_help)
        self.gcode.register_command('START_TOOL_PROBE_CRASH_DETECTION', self.cmd_START_TOOL_PROBE_CRASH_DETECTION,
                                    desc=self.cmd_START_TOOL_PROBE_CRASH_DETECTION_help)
        self.gcode.register_command('STOP_TOOL_PROBE_CRASH_DETECTION', self.cmd_STOP_TOOL_PROBE_CRASH_DETECTION,
                                    desc=self.cmd_STOP_TOOL_PROBE_CRASH_DETECTION_help)

    def _handle_connect(self):
        self.toolhead = self.printer.lookup_object('toolhead')
        self._detect_active_tool()

    def get_offsets(self, gcmd=None):
        if self.active_probe:
            return self.active_probe.get_offsets(gcmd)
        return 0.0, 0.0, 0.0

    def get_probe_params(self, gcmd=None):
        if self.active_probe:
            return self.active_probe.get_probe_params(gcmd)
        raise self.printer.command_error("No active tool probe")

    def start_probe_session(self, gcmd):
        if self.active_probe:
            return self.active_probe.start_probe_session(gcmd)
        raise self.printer.command_error("No active tool probe")

    def add_probe(self, config, tool_probe):
        if (tool_probe.tool in self.tool_probes):
            raise config.error("Duplicate tool probe nr: %s" % (tool_probe.tool,))
        self.tool_probes[tool_probe.tool] = tool_probe
        self.mcu_probe.add_mcu(tool_probe.mcu_probe)

    def set_active_probe(self, tool_probe):
        if self.active_probe == tool_probe:
            return
        self.active_probe = tool_probe
        if self.active_probe:
            self.mcu_probe.set_active_mcu(tool_probe.mcu_probe)
            self.active_tool_number = self.active_probe.tool
        else:
            self.mcu_probe.set_active_mcu(None)
            self.active_tool_number = -1

    def _query_open_tools(self):
        print_time = self.toolhead.get_last_move_time()
        self.last_query.clear()
        candidates = []
        for tool_probe in self.tool_probes.values():
            triggered = tool_probe.mcu_probe.query_endstop(print_time)
            self.last_query[tool_probe.tool] = triggered
            if not triggered:
                candidates.append(tool_probe)
        return candidates

    def _describe_tool_detection_issue(self, candidates):
        if len(candidates) == 1 :
            return 'OK'
        elif len(candidates) == 0:
            return "All probes triggered"
        else:
            return  "Multiple probes not triggered: %s" % map(lambda p: p.name, candidates)

    def _ensure_active_tool_or_fail(self, gcode):
        if self.active_probe:
            return
        active_tools = self._query_open_tools()
        if len(active_tools) != 1 :
            raise gcode.error(self._describe_tool_detection_issue(active_tools))
        self.set_active_probe(active_tools[0])

    def _detect_active_tool(self):
        active_tools = self._query_open_tools()
        if len(active_tools) == 1 :
            self.set_active_probe(active_tools[0])

    cmd_SET_ACTIVE_TOOL_PROBE_help = "Set the tool probe that will act as the Z endstop."
    def cmd_SET_ACTIVE_TOOL_PROBE(self, gcmd):
        probe_nr = gcmd.get_int("T")
        if (probe_nr not in self.tool_probes):
            raise gcmd.error("SET_ACTIVE_TOOL_PROBE no tool probe for tool %d" % (probe_nr))
        self.set_active_probe(self.tool_probes[probe_nr])

    cmd_DETECT_ACTIVE_TOOL_PROBE_help = "Detect which tool is active by identifying a probe that is NOT triggered"
    def cmd_DETECT_ACTIVE_TOOL_PROBE(self, gcmd):
        active_tools = self._query_open_tools()
        if len(active_tools) == 1 :
            active = active_tools[0]
            gcmd.respond_info("Found active tool probe: %s" % (active.name))
            self.set_active_probe(active)
        else:
            self.set_active_probe(None)
            gcmd.respond_info(self._describe_tool_detection_issue(active_tools))

    def get_status(self, eventtime):
        status = self.cmd_helper.get_status(eventtime)
        status['last_tools_query'] = self.last_query
        status['active_tool_number'] = self.active_tool_number
        if self.active_probe:
            status['active_tool_probe'] = self.active_probe.name
            status['active_tool_probe_x_offset'] = self.active_probe.get_offsets()[0]
            status['active_tool_probe_y_offset'] = self.active_probe.get_offsets()[1]
            status['active_tool_probe_z_offset'] = self.active_probe.get_offsets()[2]
        else:
            status['active_tool_probe'] = None
            status['active_tool_probe_x_offset'] = 0.0
            status['active_tool_probe_y_offset'] = 0.0
            status['active_tool_probe_z_offset'] = 0.0
        return status

    cmd_START_TOOL_PROBE_CRASH_DETECTION_help = "Start detecting tool crashes"
    def cmd_START_TOOL_PROBE_CRASH_DETECTION(self, gcmd):
        # Detect waits until previous print moves are finished to detect the triggers
        self.cmd_DETECT_ACTIVE_TOOL_PROBE(gcmd)
        expected_tool_number = gcmd.get_int("T", self.active_tool_number)

        if expected_tool_number is None:
            raise gcmd.error("Cannot start probe crash detection - no active tool")
        if expected_tool_number != self.active_tool_number:
            raise gcmd.error("Cannot start probe crash detection - expected tool not active")
        self.crash_lasttime = 0.
        self.crash_detection_active = True

    cmd_STOP_TOOL_PROBE_CRASH_DETECTION_help = "Stop detecting tool crashes"
    def cmd_STOP_TOOL_PROBE_CRASH_DETECTION(self, gcmd):
        # Clear when current print queue is finished
        self.toolhead.register_lookahead_callback(lambda _: self.stop_crash_detection())

    def stop_crash_detection(self):
        self.crash_lasttime = 0.
        self.crash_detection_active = False

    def note_probe_triggered(self, probe, eventtime, is_triggered):
        if not self.crash_detection_active:
            return
        if probe != self.active_probe:
            return
        if is_triggered:
            self.crash_lasttime = eventtime
            self.reactor.register_callback(lambda _: self._probe_triggered_delayed(eventtime),
                                           eventtime + self.crash_mintime)
        else:
            self.crash_lasttime = 0.

    def _probe_triggered_delayed(self, expect_eventtime):
        if self.crash_lasttime != expect_eventtime:
            # The trigger was cancelled
            return
        if self.crash_detection_active:
            self.crash_detection_active = False
            self.crash_gcode.run_gcode_from_command()

# Routes commands to the selected tool probe endstop.
class EndstopRouter:
    def __init__(self, printer):
        self.active_mcu = None
        self._mcus = []
        self._steppers = []
        self.printer = printer

    def add_mcu(self, mcu_probe):
        self._mcus.append(mcu_probe)
        for s in self._steppers:
            mcu_probe.add_stepper(s)

    def set_active_mcu(self, mcu_probe):
        self.active_mcu = mcu_probe

    def add_stepper(self, stepper):
        self._steppers.append(stepper)
        for m in self._mcus:
            m.add_stepper(stepper)
    def get_steppers(self):
        return list(self._steppers)

    def query_endstop(self, print_time):
        if not self.active_mcu:
            raise self.printer.command_error("Cannot query endstop - no active tool probe.")
        return self.active_mcu.query_endstop(print_time)
    def start_probe_session(self, gcmd):
        if not self.active_mcu:
            raise self.printer.command_error("Cannot start probe session - no active tool probe.")
        return self.active_mcu.start_probe_session(gcmd)

# ---------------------------------------------------------------------------
# Kalico
#
# The tool probes are Kalico PrinterProbe objects (see tool_probe.py) that do not
# register as the default probe. This object is the default probe: it hands
# PROBE, bed_mesh, z_tilt, QGL, ... to the probe of the active tool, and the
# Z endstop (probe:z_virtual_endstop) to the endstop of that probe.
# ---------------------------------------------------------------------------

class KalicoToolProbeEndstop:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.reactor = self.printer.get_reactor()
        self.name = config.get_name()
        self.probe_name = 'probe'
        self.is_default_probe = True
        self.tool_probes = {}
        self.last_query = {} # map from tool number to endstop state
        self.active_probe = None
        self.active_tool_number = -1
        self.z_rails = []
        self.gcode_macro = self.printer.load_object(config, 'gcode_macro')
        self.crash_detection_active = False
        self.crash_lasttime = 0.
        self.mcu_probe = KalicoEndstopRouter(self.printer)

        # Emulate the probe object, since others rely on this.
        if self.printer.lookup_object('probe', default=None):
            raise self.printer.config_error(
                'Cannot have both [probe] and [tool_probe_endstop].')
        probe.ProbeList.get_list(self.printer).add_probe_object(self, config)
        # Register z_virtual_endstop pin
        self.printer.lookup_object('pins').register_chip('probe', self)
        self.crash_mintime = config.getfloat('crash_mintime', 0.5, above=0.)
        self.crash_gcode = self.gcode_macro.load_template(config, 'crash_gcode', '')
        # Register homing event handlers
        self.printer.register_event_handler("klippy:connect",
                                            self._handle_connect)
        self.printer.register_event_handler("homing:homing_move_begin",
                                            self._handle_homing_move_begin)
        self.printer.register_event_handler("homing:homing_move_end",
                                            self._handle_homing_move_end)
        self.printer.register_event_handler("homing:home_rails_begin",
                                            self._handle_home_rails_begin)
        self.printer.register_event_handler("homing:home_rails_end",
                                            self._handle_home_rails_end)
        self.gcode = self.printer.lookup_object('gcode')
        self.gcode.register_command('SET_ACTIVE_TOOL_PROBE', self.cmd_SET_ACTIVE_TOOL_PROBE,
                                    desc=self.cmd_SET_ACTIVE_TOOL_PROBE_help)
        self.gcode.register_command('DETECT_ACTIVE_TOOL_PROBE', self.cmd_DETECT_ACTIVE_TOOL_PROBE,
                                    desc=self.cmd_DETECT_ACTIVE_TOOL_PROBE_help)
        self.gcode.register_command('START_TOOL_PROBE_CRASH_DETECTION', self.cmd_START_TOOL_PROBE_CRASH_DETECTION,
                                    desc=self.cmd_START_TOOL_PROBE_CRASH_DETECTION_help)
        self.gcode.register_command('STOP_TOOL_PROBE_CRASH_DETECTION', self.cmd_STOP_TOOL_PROBE_CRASH_DETECTION,
                                    desc=self.cmd_STOP_TOOL_PROBE_CRASH_DETECTION_help)
        # Kalico registers these as mux commands (PROBE=<name> selects a probe),
        # the default one, without PROBE=, belongs to this object.
        for cmd in ('PROBE', 'QUERY_PROBE', 'PROBE_CALIBRATE',
                    'PROBE_ACCURACY', 'Z_OFFSET_APPLY_PROBE'):
            self.gcode.register_mux_command(
                cmd, 'PROBE', None, getattr(self, 'cmd_' + cmd),
                desc=getattr(self, 'cmd_%s_help' % (cmd,)))

    def _handle_connect(self):
        self.toolhead = self.printer.lookup_object('toolhead')
        kin = self.toolhead.get_kinematics()
        self.z_rails = [rail for rail in getattr(kin, 'rails', [])
                        if self.mcu_probe in [es for es, name in rail.get_endstops()]]
        self._check_z_offsets()
        self._detect_active_tool()

    # A rail homes to its position_endstop. For a probe that is the z_offset of
    # the probe, and every tool probe has its own. The rail reads it once when
    # the configuration is loaded, so it is set again when the active probe
    # changes.
    def _check_z_offsets(self):
        for rail in self.z_rails:
            position_min, position_max = rail.get_range()
            for tool_probe in self.tool_probes.values():
                z_offset = tool_probe.get_offsets()[2]
                if not position_min <= z_offset <= position_max:
                    raise self.printer.config_error(
                        "z_offset %.3f of [%s] is outside of position_min "
                        "%.3f and position_max %.3f of the Z stepper" % (
                            z_offset, tool_probe.name, position_min, position_max))
    def _apply_homing_position(self):
        if self.active_probe is None:
            return
        z_offset = self.active_probe.get_offsets()[2]
        for rail in self.z_rails:
            rail.position_endstop = z_offset

    def _handle_homing_move_begin(self, hmove):
        if self.mcu_probe in hmove.get_mcu_endstops():
            if self.active_probe:
                self.active_probe.mcu_probe.probe_prepare(hmove)
            else:
                raise self.printer.command_error("No active tool probe")
    def _handle_homing_move_end(self, hmove):
        if self.mcu_probe in hmove.get_mcu_endstops():
            if self.active_probe:
                self.active_probe.mcu_probe.probe_finish(hmove)
    def _handle_home_rails_begin(self, homing_state, rails):
        endstops = [es for rail in rails for es, name in rail.get_endstops()]
        if self.mcu_probe in endstops:
            self.multi_probe_begin(always_restore_toolhead=True)
    def _handle_home_rails_end(self, homing_state, rails):
        endstops = [es for rail in rails for es, name in rail.get_endstops()]
        if self.mcu_probe in endstops:
            self.multi_probe_end()

    # The interface of Kalico's PrinterProbe, as used by bed_mesh, z_tilt,
    # QGL, ProbePointsHelper, ...
    def _active_or_fail(self):
        if self.active_probe:
            return self.active_probe
        raise self.printer.command_error("No active tool probe")
    def get_offsets(self):
        if self.active_probe:
            return self.active_probe.get_offsets()
        return 0.0, 0.0, 0.0
    def get_lift_speed(self, gcmd=None):
        return self._active_or_fail().get_lift_speed(gcmd)
    def run_probe(self, gcmd, retry_session=None):
        if retry_session is None:
            return self._active_or_fail().run_probe(gcmd)
        return self._active_or_fail().run_probe(gcmd, retry_session)
    def probing_move(self, speed, gcmd):
        return self._active_or_fail().probing_move(speed, gcmd)
    def multi_probe_begin(self, always_restore_toolhead=False):
        return self._active_or_fail().multi_probe_begin(always_restore_toolhead)
    def multi_probe_end(self):
        return self._active_or_fail().multi_probe_end()
    def setup_pin(self, pin_type, pin_params):
        if pin_type != 'endstop' or pin_params['pin'] != 'z_virtual_endstop':
            raise pins.error("Probe virtual endstop only useful as endstop pin")
        if pin_params['invert'] or pin_params['pullup']:
            raise pins.error("Can not pullup/invert probe virtual endstop")
        return self.mcu_probe
    def __getattr__(self, name):
        # Anything else the probe object of the active tool has: speed,
        # z_offset, retry_session, ...
        if name.startswith('_') or name in ('active_probe', 'printer'):
            raise AttributeError(name)
        if self.active_probe is None:
            raise AttributeError(name)
        return getattr(self.active_probe, name)

    def add_probe(self, config, tool_probe):
        if (tool_probe.tool in self.tool_probes):
            raise config.error("Duplicate tool probe nr: %s" % (tool_probe.tool,))
        self.tool_probes[tool_probe.tool] = tool_probe

    def set_active_probe(self, tool_probe):
        if self.active_probe == tool_probe:
            return
        if self.active_probe:
            self.active_probe.multi_probe_end()
        self.active_probe = tool_probe
        if self.active_probe:
            self.mcu_probe.set_active_probe(tool_probe.mcu_probe)
            self.active_tool_number = self.active_probe.tool
            self._apply_homing_position()
        else:
            self.mcu_probe.set_active_probe(None)
            self.active_tool_number = -1

    def _query_open_tools(self):
        print_time = self.toolhead.get_last_move_time()
        self.last_query.clear()
        candidates = []
        for tool_probe in self.tool_probes.values():
            triggered = tool_probe.mcu_probe.query_endstop(print_time)
            self.last_query[tool_probe.tool] = triggered
            if not triggered:
                candidates.append(tool_probe)
        return candidates

    def _describe_tool_detection_issue(self, candidates):
        if len(candidates) == 1 :
            return 'OK'
        elif len(candidates) == 0:
            return "All probes triggered"
        else:
            return "Multiple probes not triggered: %s" % (
                ', '.join(p.name for p in candidates),)

    def _ensure_active_tool_or_fail(self, gcode):
        if self.active_probe:
            return
        active_tools = self._query_open_tools()
        if len(active_tools) != 1 :
            raise gcode.error(self._describe_tool_detection_issue(active_tools))
        self.set_active_probe(active_tools[0])

    def _detect_active_tool(self):
        active_tools = self._query_open_tools()
        if len(active_tools) == 1 :
            self.set_active_probe(active_tools[0])

    cmd_SET_ACTIVE_TOOL_PROBE_help = "Set the tool probe that will act as the Z endstop."
    def cmd_SET_ACTIVE_TOOL_PROBE(self, gcmd):
        probe_nr = gcmd.get_int("T")
        if (probe_nr not in self.tool_probes):
            raise gcmd.error("SET_ACTIVE_TOOL_PROBE no tool probe for tool %d" % (probe_nr))
        self.set_active_probe(self.tool_probes[probe_nr])

    cmd_DETECT_ACTIVE_TOOL_PROBE_help = "Detect which tool is active by identifying a probe that is NOT triggered"
    def cmd_DETECT_ACTIVE_TOOL_PROBE(self, gcmd):
        active_tools = self._query_open_tools()
        if len(active_tools) == 1 :
            active = active_tools[0]
            gcmd.respond_info("Found active tool probe: %s" % (active.name))
            self.set_active_probe(active)
        else:
            self.set_active_probe(None)
            gcmd.respond_info(self._describe_tool_detection_issue(active_tools))

    cmd_PROBE_help = "Probe Z-height at current XY position"
    def cmd_PROBE(self, gcmd):
        self._ensure_active_tool_or_fail(gcmd)
        self.active_probe.cmd_PROBE(gcmd)
    cmd_QUERY_PROBE_help = "Return the status of the z-probe"
    def cmd_QUERY_PROBE(self, gcmd):
        if not self.active_probe:
            gcmd.respond_info("no active tool probe")
            return
        self.active_probe.cmd_QUERY_PROBE(gcmd)
    cmd_PROBE_ACCURACY_help = "Probe Z-height accuracy at current XY position"
    def cmd_PROBE_ACCURACY(self, gcmd):
        self._ensure_active_tool_or_fail(gcmd)
        self.active_probe.cmd_PROBE_ACCURACY(gcmd)
    cmd_PROBE_CALIBRATE_help = "Calibrate the probe's z_offset"
    def cmd_PROBE_CALIBRATE(self, gcmd):
        self._ensure_active_tool_or_fail(gcmd)
        self.active_probe.cmd_PROBE_CALIBRATE(gcmd)
    cmd_Z_OFFSET_APPLY_PROBE_help = "Adjust the probe's z_offset"
    def cmd_Z_OFFSET_APPLY_PROBE(self, gcmd):
        if not self.active_probe:
            gcmd.respond_info("no active tool probe")
            return
        self.active_probe.cmd_Z_OFFSET_APPLY_PROBE(gcmd)

    def get_status(self, eventtime):
        if not self.active_probe:
            return {'name': self.name,
                    'active_tool_probe': None,
                    'active_tool_number': -1,
                    'active_tool_probe_x_offset': 0.0,
                    'active_tool_probe_y_offset': 0.0,
                    'active_tool_probe_z_offset': 0.0,
                    'last_query': False,
                    'last_tools_query': self.last_query,
                    'last_z_result': 0.}
        status = dict(self.active_probe.get_status(eventtime))
        offsets = self.active_probe.get_offsets()
        status['name'] = self.name
        status['active_tool_probe'] = self.active_probe.name
        status['active_tool_number'] = self.active_tool_number
        status['active_tool_probe_x_offset'] = offsets[0]
        status['active_tool_probe_y_offset'] = offsets[1]
        status['active_tool_probe_z_offset'] = offsets[2]
        status['last_tools_query'] = self.last_query
        return status

    cmd_START_TOOL_PROBE_CRASH_DETECTION_help = "Start detecting tool crashes"
    def cmd_START_TOOL_PROBE_CRASH_DETECTION(self, gcmd):
        # Detect waits until previous print moves are finished to detect the triggers
        self.cmd_DETECT_ACTIVE_TOOL_PROBE(gcmd)
        expected_tool_number = gcmd.get_int("T", self.active_tool_number)

        if expected_tool_number is None:
            raise gcmd.error("Cannot start probe crash detection - no active tool")
        if expected_tool_number != self.active_tool_number:
            raise gcmd.error("Cannot start probe crash detection - expected tool not active")
        self.crash_lasttime = 0.
        self.crash_detection_active = True

    cmd_STOP_TOOL_PROBE_CRASH_DETECTION_help = "Stop detecting tool crashes"
    def cmd_STOP_TOOL_PROBE_CRASH_DETECTION(self, gcmd):
        # Clear when current print queue is finished
        self.toolhead.register_lookahead_callback(lambda _: self.stop_crash_detection())

    def stop_crash_detection(self):
        self.crash_lasttime = 0.
        self.crash_detection_active = False

    def note_probe_triggered(self, probe, eventtime, is_triggered):
        if not self.crash_detection_active:
            return
        if probe != self.active_probe:
            return
        if is_triggered:
            self.crash_lasttime = eventtime
            self.reactor.register_callback(lambda _: self._probe_triggered_delayed(eventtime),
                                           eventtime + self.crash_mintime)
        else:
            self.crash_lasttime = 0.

    def _probe_triggered_delayed(self, expect_eventtime):
        if self.crash_lasttime != expect_eventtime:
            # The trigger was cancelled
            return
        if self.crash_detection_active:
            self.crash_detection_active = False
            self.crash_gcode.run_gcode_from_command()

# Endstop that the Z homing talks to; it routes everything to the endstop of the
# probe of the active tool.
class KalicoEndstopRouter:
    def __init__(self, printer):
        self.printer = printer
        self.active_mcu = None
        self._steppers = []
        printer.register_event_handler('klippy:mcu_identify',
                                       self._handle_mcu_identify)

    def _handle_mcu_identify(self):
        # Each tool probe adds the Z steppers to its own endstop, this is only
        # for a tool independent get_steppers.
        kin = self.printer.lookup_object('toolhead').get_kinematics()
        for stepper in kin.get_steppers():
            if stepper.is_active_axis('z'):
                self.add_stepper(stepper)

    def add_stepper(self, stepper):
        if stepper not in self._steppers:
            self._steppers.append(stepper)
    def get_steppers(self):
        return list(self._steppers)

    def set_active_probe(self, mcu_probe):
        self.active_mcu = mcu_probe

    def _active_or_fail(self, what):
        if not self.active_mcu:
            raise self.printer.command_error(
                "Cannot %s - no active tool probe." % (what,))
        return self.active_mcu

    def get_mcu(self):
        return self._active_or_fail("get the MCU").get_mcu()
    def home_start(self, *args, **kwargs):
        return self._active_or_fail("start homing").home_start(*args, **kwargs)
    def home_wait(self, home_end_time):
        return self._active_or_fail("wait for homing").home_wait(home_end_time)
    def query_endstop(self, print_time):
        return self._active_or_fail("query endstop").query_endstop(print_time)
    def get_position_endstop(self):
        if not self.active_mcu:
            # Static value read when the Z rail is set up, the active probe
            # supplies the real offset
            return 0.0
        return self.active_mcu.get_position_endstop()
    def probing_move(self, pos, speed, gcmd):
        return self._active_or_fail("probe").probing_move(pos, speed, gcmd)
    def multi_probe_begin(self, *args):
        return self._active_or_fail("start multi probe").multi_probe_begin(*args)
    def multi_probe_end(self):
        return self._active_or_fail("end multi probe").multi_probe_end()
    def probe_prepare(self, hmove):
        return self._active_or_fail("prepare probe").probe_prepare(hmove)
    def probe_finish(self, hmove):
        return self._active_or_fail("finish probe").probe_finish(hmove)

def load_config(config):
    if KALICO_PROBE_API:
        return KalicoToolProbeEndstop(config)
    return ToolProbeEndstop(config)
