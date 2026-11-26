import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "pi-sync.sh"


def clean_env():
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    env.update(
        GIT_CONFIG_GLOBAL=os.devnull,
        GIT_CONFIG_SYSTEM=os.devnull,
        GIT_AUTHOR_NAME="Fixture",
        GIT_AUTHOR_EMAIL="fixture@example.invalid",
        GIT_COMMITTER_NAME="Fixture",
        GIT_COMMITTER_EMAIL="fixture@example.invalid",
    )
    return env


class PiSyncTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.env = clean_env()
        self.origin = base / "origin.git"
        self.work = base / "work"
        self.pi = base / "pi"
        self.git(
            base,
            "init",
            "--quiet",
            "--bare",
            "--initial-branch=master",
            str(self.origin),
        )
        self.git(base, "clone", "--quiet", str(self.origin), str(self.work))
        self.write(self.work, ".gitignore", "json/*.json\n")
        self.write(self.work, "automations.yaml", "- id: one\n")
        self.write(self.work, "scripts.yaml", "a: 1\n")
        self.write(self.work, "tools/check.py", "old\n")
        self.write(self.work, "tools/retired.sh", "old\n")
        self.git(
            self.work,
            "add",
            "-f",
            ".gitignore",
            "automations.yaml",
            "scripts.yaml",
            "tools",
        )
        self.write(self.work, "json/sun.json", "{}\n")
        self.git(self.work, "add", "-f", "json/sun.json")
        self.git(self.work, "commit", "--quiet", "-m", "base")
        self.git(self.work, "push", "--quiet", "origin", "master")
        self.git(base, "clone", "--quiet", str(self.origin), str(self.pi))

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, cwd, *args):
        return subprocess.run(
            ["git", *args],
            cwd=cwd,
            env=self.env,
            check=True,
            capture_output=True,
            text=True,
        ).stdout

    def write(self, repo, name, text):
        path = repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def upstream(self, edit):
        edit()
        self.git(self.work, "add", "-A")
        self.git(self.work, "commit", "--quiet", "-m", "upstream")
        self.git(self.work, "push", "--quiet", "origin", "master")
        return self.git(self.work, "rev-parse", "HEAD").strip()

    def sync(self):
        return subprocess.run(
            ["bash", str(SCRIPT), str(self.pi)],
            env=self.env,
            capture_output=True,
            text=True,
        )

    def test_brings_in_upstream_and_keeps_what_the_pi_changed(self):
        self.write(self.pi, "automations.yaml", "- id: one\n- id: two\n")
        self.write(self.pi, "json/sun.json", '{"today": 1}\n')

        def edit():
            self.write(self.work, "tools/check.py", "new\n")
            self.write(self.work, "scripts.yaml", "a: 2\n")
            (self.work / "tools/retired.sh").unlink()
            self.git(self.work, "rm", "--quiet", "--cached", "json/sun.json")

        new = self.upstream(edit)
        result = self.sync()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git(self.pi, "rev-parse", "HEAD").strip(), new)
        self.assertEqual((self.pi / "tools/check.py").read_text(), "new\n")
        self.assertEqual((self.pi / "scripts.yaml").read_text(), "a: 2\n")
        self.assertFalse((self.pi / "tools/retired.sh").exists())
        self.assertEqual((self.pi / "json/sun.json").read_text(), '{"today": 1}\n')
        self.assertEqual(
            (self.pi / "automations.yaml").read_text(), "- id: one\n- id: two\n"
        )
        self.assertEqual(
            self.git(self.pi, "status", "--porcelain").strip(), "M automations.yaml"
        )
        self.assertIn("reload or restart", result.stdout)
        self.assertIn("  scripts.yaml", result.stdout.split("reload or restart")[1])

    def test_stops_without_changing_anything_when_both_sides_changed_a_file(self):
        self.write(self.pi, "automations.yaml", "- id: pi\n")
        old = self.git(self.pi, "rev-parse", "HEAD").strip()
        self.upstream(
            lambda: self.write(self.work, "automations.yaml", "- id: upstream\n")
        )

        result = self.sync()

        self.assertEqual(result.returncode, 1)
        self.assertIn("automations.yaml", result.stderr)
        self.assertEqual(self.git(self.pi, "rev-parse", "HEAD").strip(), old)
        self.assertEqual((self.pi / "automations.yaml").read_text(), "- id: pi\n")


if __name__ == "__main__":
    unittest.main()
