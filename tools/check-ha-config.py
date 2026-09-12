#!/usr/bin/env python3
"""Run HA's native checker, failing on logged integration errors too.

Core 2026.6.3 can disable an invalid automation and return zero errors/exit 0.
Observe standard logging severity rather than reimplementing HA validation or
matching English log text. Run only inside the pinned CI Core container.
"""

import logging
import runpy
import sys


class ErrorCounter(logging.Handler):
    def __init__(self):
        super().__init__(level=logging.ERROR)
        self.count = 0

    def emit(self, record):
        self.count += 1


if __name__ == "__main__":
    logging.basicConfig(stream=sys.stdout, level=logging.INFO)
    errors = ErrorCounter()
    logging.getLogger().addHandler(errors)
    sys.argv = ["homeassistant", "--config", "/config", "--script", "check_config",
                "--fail-on-warnings"]
    status = 0
    try:
        runpy.run_module("homeassistant", run_name="__main__")
    except SystemExit as exc:
        status = exc.code
    finally:
        logging.getLogger().removeHandler(errors)
    if errors.count:
        print(f"Configuration check logged {errors.count} error(s); refusing clearance.",
              file=sys.stderr)
        status = status or 1
    raise SystemExit(status)
