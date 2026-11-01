# Helper to run g-code in batch mode on Klipper, like the testing plugin of
# Kalico: an error in the g-code ends the run with an error, and ASSERT checks
# an expression. Loaded by a [testing] section.
import ast
import logging


class Testing:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.gcode = self.printer.lookup_object('gcode')
        self.gcode_macro = self.printer.load_object(config, 'gcode_macro')
        self.printer.register_event_handler("gcode:command_error",
                                            self._command_error)
        self.printer.register_event_handler("gcode:unknown_command",
                                            self._unknown_command)
        self.gcode.register_command("ASSERT", self.cmd_ASSERT)

    def _command_error(self):
        self.printer.request_exit("error_exit")
        self.printer.invoke_shutdown("Exception during testing")

    def _unknown_command(self, cmd):
        logging.error("Unknown command during test execution: %s", cmd)
        self.printer.request_exit("error_exit")
        self.printer.invoke_shutdown(
            "Unknown command during test execution: %s" % (cmd,))

    def cmd_ASSERT(self, gcmd):
        expression = gcmd.get("TEST")
        env = self.gcode_macro.env
        try:
            template = env.from_string(expression)
        except Exception:
            raise gcmd.error("ASSERT: Failed to parse '%s'" % (expression,))
        context = self.gcode_macro.create_template_context()
        statement = template.render(context)
        value = ast.literal_eval(statement) if statement else None
        if not value:
            raise gcmd.error("ASSERT: %s == %s" % (expression, value))


def load_config(config):
    return Testing(config)
