import contextlib
import importlib.util
import io
import sys
import types
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]


def load_script(relative_path, module_name, injected_module):
    path = ROOT / relative_path
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    with mock.patch.dict(sys.modules, injected_module):
        spec.loader.exec_module(module)
    return module


class LifxSceneArgumentTests(unittest.TestCase):
    def setUp(self):
        self.lifxlan = types.ModuleType("lifxlan")
        self.lifxlan.MultiZoneLight = mock.Mock()
        self.lifxlan.TileChain = mock.Mock()

    def load_scene(self, filename):
        return load_script(
            Path("python/scenes") / filename,
            f"scene_{filename.removesuffix('.py')}",
            {"lifxlan": self.lifxlan},
        )

    def test_living_room_passes_arguments_and_preserves_scene(self):
        device = self.lifxlan.MultiZoneLight.return_value
        device.get_power.return_value = 0
        module = self.load_scene("living_room_tv_ht_on.py")

        module.main(["synthetic-mac", "example.invalid"])

        self.lifxlan.MultiZoneLight.assert_called_once_with(
            "synthetic-mac", "example.invalid"
        )
        colors = device.set_zone_colors.call_args.args[0]
        self.assertEqual(len(colors), 40)
        self.assertEqual(colors[0], (14017, 3276, 14952, 3500))
        self.assertEqual(colors[-1], (64168, 65535, 26345, 3500))
        device.set_power.assert_called_once_with("on")

    def test_tile_wakeup_passes_arguments(self):
        device = self.lifxlan.TileChain.return_value
        device.get_tilechain_colors.return_value = []
        module = self.load_scene("bedroom_tiles_wakeup.py")

        with contextlib.redirect_stdout(io.StringIO()):
            module.main(["synthetic-mac", "example.invalid"])

        self.lifxlan.TileChain.assert_called_once_with(
            "synthetic-mac", "example.invalid"
        )
        device.get_tilechain_colors.assert_called_once_with()

    def test_diagnostic_scene_passes_arguments(self):
        device = self.lifxlan.MultiZoneLight.return_value
        device.get_color_zones.return_value = []
        device.get_power.return_value = 1
        module = self.load_scene("test.py")

        with contextlib.redirect_stdout(io.StringIO()):
            module.main(["synthetic-mac", "example.invalid"])

        self.lifxlan.MultiZoneLight.assert_called_once_with(
            "synthetic-mac", "example.invalid"
        )
        device.get_color_zones.assert_called_once_with()
        device.set_power.assert_not_called()

    def test_each_scene_requires_both_arguments(self):
        for filename in (
            "bedroom_tiles_wakeup.py",
            "living_room_tv_ht_on.py",
            "test.py",
        ):
            with self.subTest(filename=filename):
                module = self.load_scene(filename)
                with contextlib.redirect_stderr(io.StringIO()):
                    with self.assertRaises(SystemExit) as raised:
                        module.main([])
                self.assertNotEqual(raised.exception.code, 0)


class RestartSonarrArgumentTests(unittest.TestCase):
    def setUp(self):
        self.requests = types.ModuleType("requests")
        self.requests.post = mock.Mock()

    def load_restart(self):
        return load_script(
            "python/restart_sonarr.py",
            "restart_sonarr",
            {"requests": self.requests},
        )

    def test_posts_to_supplied_url(self):
        module = self.load_restart()

        module.main(["https://example.invalid/restart"])

        self.requests.post.assert_called_once_with(
            "https://example.invalid/restart"
        )

    def test_url_is_required(self):
        module = self.load_restart()
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as raised:
                module.main([])
        self.assertNotEqual(raised.exception.code, 0)


if __name__ == "__main__":
    unittest.main()
