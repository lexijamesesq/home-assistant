#!/usr/bin/env python3
"""Check public network rules using generated, non-operator fixtures."""

import json
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
IP_RULE = "ha-ipv4-address"
MAC_RULE = "ha-mac-address"
cases = [
    ("private-ip", ".".join(map(str, (10, 123, 45, 67))), IP_RULE),
    ("public-ip", ".".join(map(str, (8, 8, 4, 4))), IP_RULE),
    ("hardware-address", ":".join(("a4", "b1", "c2", "d3", "e4", "f5")), MAC_RULE),
    ("hyphenated-hardware-address", "-".join(("a4", "b1", "c2", "d3", "e4", "f5")), MAC_RULE),
    ("documentation-ip", "192.0.2.1", None),
    ("synthetic-mac", "02:00:00:00:00:01", None),
    ("broadcast-mac", ":".join(["ff"] * 6), None),
    ("hostname", "ha.example.invalid", None),
]
if not shutil.which("gitleaks"):
    raise SystemExit("Network-rule tests require gitleaks; refusing to skip.")

with tempfile.TemporaryDirectory(prefix="ha-network-rules-") as directory:
    root = Path(directory)
    source = root / "source"
    source.mkdir()
    report = root / "report.json"
    for name, value, expected in cases:
        (source / "config.txt").write_text(value + "\n")
        result = subprocess.run(
            ["gitleaks", "dir", str(source), "--config", str(ROOT / ".gitleaks.toml"),
             "--redact", "--no-banner", "--report-format", "json", "--report-path", str(report)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        if result.returncode not in (0, 1) or not report.is_file():
            raise SystemExit(f"FAIL: scanner could not complete {name}")
        rules = {finding["RuleID"] for finding in json.loads(report.read_text())}
        if expected:
            if result.returncode != 1 or expected not in rules:
                raise SystemExit(f"FAIL: {name} did not trigger {expected}")
        elif result.returncode != 0 or rules:
            raise SystemExit(f"FAIL: documented safe fixture {name} was rejected")
print(f"PASS: {len(cases)} network-rule fixtures")
