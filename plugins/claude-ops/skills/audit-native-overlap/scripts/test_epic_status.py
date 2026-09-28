#!/usr/bin/env python3
"""Contract tests for epic_status.py. No network."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("epic_status.py")

DOCTOR = "If /doctor is available in your session ("
SKILL_DOCTOR = "If /skill-doctor is available in your session ("
EXPORT = "If /export is available in your session ("
AXIS = "settings or environment, plan, platform or provider, host surface"
ROUTE = "resolves in your session"


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def row(native: str, plugin: str, skill: str, integration: str, **baked: bool) -> dict[str, object]:
    return {
        "native": {"name": native, "class": "bundled-skill"},
        "component": {"plugin": plugin, "skill": skill},
        "verdict": "complementary",
        "integration": integration,
        "baked": baked,
    }


def plant(root: Path) -> None:
    rows = [
        row("doctor", "claude-ops", "audit-install-state", "suggest", suggest_sentence=True),
        row("doctor", "claude-ops", "audit-performance", "suggest", suggest_sentence=True),
        row("doctor", "claude-ops", "audit-skill-visibility", "suggest", suggest_sentence=True),
        row("skill-doctor", "claude-ops", "audit-skill-visibility", "suggest", suggest_sentence=True),
        row("simplify", "code-tidying", "batch-simplify", "wrap", native_step=True),
        row("run", "testing", "run-e2e", "wrap", native_step=True),
        row("export", "session-flow", "clean-stop", "suggest", suggest_sentence=True),
        row("export", "session-flow", "handoff", "suggest", suggest_sentence=True),
        row("export", "session-flow", "retro", "suggest", suggest_sentence=True),
        {
            "native": {"name": "morning", "class": "session-skill"},
            "component": {"plugin": "claude-ops", "skill": "morning-brief"},
            "verdict": "defer",
            "integration": "route",
            "baked": {},
        },
    ]
    write(root / "docs/native-surfaces/records.json", json.dumps({"rows": rows}))
    write(root / "plugins/claude-ops/skills/audit-install-state/SKILL.md", DOCTOR)
    write(root / "plugins/claude-ops/skills/audit-skill-visibility/SKILL.md", DOCTOR + SKILL_DOCTOR)
    write(root / "plugins/claude-ops/skills/audit-performance/SKILL.md", DOCTOR)
    write(
        root / "plugins/code-tidying/skills/batch-simplify/SKILL.md",
        "## Native step: simplify (bundled skill)\n" + AXIS,
    )
    write(
        root / "plugins/testing/skills/run-e2e/SKILL.md",
        "## Native step: run (bundled skill)\n" + AXIS,
    )
    write(root / "plugins/review/skills/code-review/SKILL.md", ROUTE)
    write(root / "plugins/review/skills/security-review/SKILL.md", ROUTE)
    write(root / "plugins/visualization/skills/visualize/SKILL.md", ROUTE)
    write(root / "plugins/prototype/skills/explore-directions/SKILL.md", ROUTE)
    for name in ("clean-stop", "handoff", "retro"):
        write(root / "plugins/session-flow/skills" / name / "SKILL.md", EXPORT)


def run(root: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--root", str(root)],
        check=False,
        capture_output=True,
        text=True,
    )


class EpicStatusTests(unittest.TestCase):
    def test_a_complete_fixture_is_closed(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            plant(root)
            result = run(root)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("summary open=0 units=none", result.stdout)
        self.assertIn("phase4 issue=4049 status=ok", result.stdout)

    def test_a_missing_doctor_sentence_opens_phase5_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            plant(root)
            target = root / "plugins/claude-ops/skills/audit-install-state/SKILL.md"
            target.write_text("no sentence\n", encoding="utf-8")
            result = run(root)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("phase5 issue=4050 status=open", result.stdout)
        self.assertIn("phase6 issue=4051 status=ok", result.stdout)
        self.assertIn("summary open=1 units=phase5", result.stdout)

    def test_builtin_wrap_opens_phase4(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            plant(root)
            path = root / "docs/native-surfaces/records.json"
            data = json.loads(path.read_text(encoding="utf-8"))
            data["rows"].append(
                {
                    "native": {"name": "export", "class": "builtin-command"},
                    "component": {"plugin": "session-flow", "skill": "clean-stop"},
                    "verdict": "complementary",
                    "integration": "wrap",
                    "baked": {},
                }
            )
            path.write_text(json.dumps(data), encoding="utf-8")
            result = run(root)
        self.assertEqual(result.returncode, 1)
        self.assertIn("phase4 issue=4049 status=open", result.stdout)
        self.assertIn("builtin-command wrap", result.stdout)

    def test_this_checkout_leaves_phase5_and_phase6_open(self) -> None:
        repo = Path(__file__).resolve().parents[5]
        result = run(repo)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        for phase in ("phase4", "phase7", "phase8", "phase9", "phase10", "phase11"):
            self.assertIn(f"{phase} ", result.stdout)
            self.assertRegex(result.stdout, rf"{phase} issue=\d+ status=ok")
        self.assertIn("phase5 issue=4050 status=open", result.stdout)
        self.assertIn("phase6 issue=4051 status=open", result.stdout)


if __name__ == "__main__":
    unittest.main()
