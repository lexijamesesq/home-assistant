"""Exercise the script's documented Pyscript configuration boundary offline."""

from pathlib import Path
import runpy
import types
import unittest
from unittest.mock import Mock, patch


class SonosConfigurationTests(unittest.TestCase):
    def test_native_configuration_supplies_endpoint(self):
        requests = types.ModuleType("requests")
        requests.get = Mock(return_value=Mock(json=lambda: {"status": "success"}))
        task = types.SimpleNamespace(executor=lambda fn, *args, **kwargs: fn(*args, **kwargs))
        config = types.SimpleNamespace(config={"global": {"sonos_api_url": "https://example.invalid/sonos/"}})
        with patch.dict("sys.modules", {"requests": requests}):
            script = runpy.run_path(str(Path(__file__).parents[1] / "pyscript/sonos_group.py"),
                                   init_globals={"pyscript": config, "service": lambda fn: fn,
                                                 "task": task, "log": Mock()})
            self.assertTrue(script["_api_call"]("Bedroom/leave"))
        requests.get.assert_called_once_with("https://example.invalid/sonos/Bedroom/leave", timeout=10)

    def test_missing_configuration_has_no_hardcoded_fallback(self):
        with patch.dict("sys.modules", {"requests": types.ModuleType("requests")}):
            with self.assertRaises(KeyError):
                runpy.run_path(str(Path(__file__).parents[1] / "pyscript/sonos_group.py"),
                               init_globals={"pyscript": types.SimpleNamespace(config={}),
                                             "service": lambda fn: fn})
