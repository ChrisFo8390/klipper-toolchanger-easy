# Per-tool Z-Probe support
#
# Copyright (C) 2023 Viesturs Zarins <viesturz@gmail.com>
#
# This file may be distributed under the terms of the GNU GPLv3 license.
try:
    from . import probe
except ImportError:
    # Kalico loads modules of klippy/plugins as klippy.plugins.<name>, so the
    # relative import does not find the modules of klippy/extras.
    from klippy.extras import probe

# Klipper changed the probe code in 2024 (ProbeCommandHelper, ProbeSessionHelper,
# ...). Kalico kept the classic PrinterProbe/ProbeEndstopWrapper design and
# added a list of probes (ProbeList) on top of it. The tool probe supports both,
# the class for Kalico is at the end of the file.
KALICO_PROBE_API = (hasattr(probe, 'ProbeList')
                    and not hasattr(probe, 'ProbeCommandHelper'))

class ToolProbe:
    def __init__(self, config):
        self.tool = config.getint('tool')
        self.printer = config.get_printer()
        self.name = config.get_name()
        self.probe_offsets = probe.ProbeOffsetsHelper(config)
        self.param_helper = probe.ProbeParameterHelper(config)
        self.mcu_probe = probe.ProbeEndstopWrapper(
            config, self.probe_offsets, self.param_helper)
        self.probe_session = probe.SampleAveragingHelper(
            config, self.param_helper, self.mcu_probe.start_probe_session)

        # Crash detection stuff
        pin = config.get('pin')
        buttons = self.printer.load_object(config, 'buttons')
        ppins = self.printer.lookup_object('pins')
        ppins.allow_multi_use_pin(pin.replace('^', '').replace('!', ''))
        buttons.register_buttons([pin], self._button_handler)

        #Register with the endstop
        self.endstop = self.printer.load_object(config, "tool_probe_endstop")
        self.endstop.add_probe(config, self)

    def _button_handler(self, eventtime, is_triggered):
        self.endstop.note_probe_triggered(self, eventtime, is_triggered)

    def get_probe_params(self, gcmd=None):
        return self.param_helper.get_probe_params(gcmd)
    def get_offsets(self, gcmd=None):
        return self.probe_offsets.get_offsets(gcmd)
    def start_probe_session(self, gcmd):
        return self.probe_session.start_probe_session(gcmd)

if KALICO_PROBE_API:
    class _NotDefaultProbeConfig:
        """Config of a [tool_probe] for Kalico's PrinterProbe.

        The tool probes do not register as the default probe, the
        [tool_probe_endstop] router does that and hands the work to the probe of
        the active tool. PrinterProbe reads register_as_probe (default True) and
        would otherwise claim the 'probe' object and the 'probe' pin chip."""
        def __init__(self, config):
            object.__setattr__(self, '_config', config)

        def __getattr__(self, name):
            return getattr(self._config, name)

        def getboolean(self, option, *args, **kwargs):
            value = self._config.getboolean(option, *args, **kwargs)
            return False if option == 'register_as_probe' else value

    class ToolProbe(probe.PrinterProbe):
        def __init__(self, config):
            self.tool = config.getint('tool')
            pconfig = _NotDefaultProbeConfig(config)
            super().__init__(pconfig, probe.ProbeEndstopWrapper(pconfig))

            # Crash detection stuff
            pin = config.get('pin')
            buttons = self.printer.load_object(config, 'buttons')
            ppins = self.printer.lookup_object('pins')
            ppins.allow_multi_use_pin(pin.replace('^', '').replace('!', ''))
            buttons.register_buttons([pin], self._button_handler)

            #Register with the endstop
            self.endstop = self.printer.load_object(config, "tool_probe_endstop")
            self.endstop.add_probe(config, self)

        def _button_handler(self, eventtime, is_triggered):
            self.endstop.note_probe_triggered(self, eventtime, is_triggered)

def load_config_prefix(config):
    return ToolProbe(config)
