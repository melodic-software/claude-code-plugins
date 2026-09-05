#!/usr/bin/env python3
"""Output-based tests for resolve-config.py at its command line."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "resolve-config.py"
LADDER = SCRIPT_DIR / "collector-ladder.tsv"
FIXTURES = SCRIPT_DIR / "fixtures" / "config"
USER = str(FIXTURES / "user.yaml")
TEAM = str(FIXTURES / "team.yaml")
LOCAL = str(FIXTURES / "local.yaml")
FLOW = str(FIXTURES / "flow-mapping.yaml")


def run(
    *args: str, env: dict | None = None, cwd: str | None = None
) -> subprocess.CompletedProcess:
    merged = dict(os.environ)
    if env:
        merged.update(env)
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        env=merged,
        cwd=cwd,
        check=False,
    )


class PositionalLayerTests(unittest.TestCase):
    def test_team_overrides_user_per_key_and_provenance_names_the_layer(self) -> None:
        result = run(USER, TEAM, "--ladder", str(LADDER))
        self.assertEqual(result.returncode, 0, result.stderr)
        d = json.loads(result.stdout)
        cyc = d["_provenance"]["complexity.cyclomatic.reference"]
        self.assertEqual(d["complexity"]["cyclomatic"]["reference"], cyc["value"])
        self.assertEqual((cyc["value"], cyc["layer"]), (15, "team"))
        self.assertEqual(
            d["_provenance"]["size.file_lines"], {"value": 800, "layer": "user-global"}
        )
        self.assertEqual(
            d["_provenance"]["size.mode"],
            {"value": "file-lines", "layer": "bundled default"},
        )
        self.assertEqual(d["_layers"]["complexity.cyclomatic.reference"], "team")
        self.assertEqual(
            d["lanes"]["typescript"]["collectors"]["cyclomatic"], ["lizard"]
        )
        self.assertIs(d["lanes"]["dotnet"]["enabled"], False)
        self.assertIs(d["lanes"]["python"]["enabled"], True)
        self.assertEqual(
            d["_files"], [USER.replace("\\", "/"), TEAM.replace("\\", "/")]
        )
        self.assertIn("thresholds", d)

    def test_local_overlay_overrides_per_key(self) -> None:
        d = json.loads(run(USER, TEAM, LOCAL).stdout)
        self.assertEqual(d["scope"]["exclude"], ["vendor/**"])
        self.assertEqual(d["complexity"]["cyclomatic"]["reference"], 15)
        self.assertEqual(d["_layers"]["scope.exclude"], "local")

    def test_unknown_ladder_tool_is_dropped_with_a_warning(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            team = Path(tmp) / "team.yaml"
            team.write_text(
                "lanes:\n  python:\n    collectors:\n      cyclomatic: [radon, nonsense]\n",
                encoding="utf-8",
            )
            result = run(str(team), "--ladder", str(LADDER))
            d = json.loads(result.stdout)
            self.assertEqual(
                d["lanes"]["python"]["collectors"]["cyclomatic"], ["radon"]
            )
            self.assertIn("'nonsense' is not in the ladder", result.stderr)

    def test_scope_defaults_and_an_empty_collector_list_reach_the_dispatcher(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            team = Path(tmp) / "team.yaml"
            team.write_text(
                "scope:\n  default: all\n  base: mark\n"
                "lanes:\n  python:\n    collectors:\n      cyclomatic: []\n",
                encoding="utf-8",
            )
            args = run(
                USER, str(team), "--ladder", str(LADDER), "--format", "dispatch-args"
            ).stdout.splitlines()
            self.assertEqual(args[:2], ["--scope-default all", "--scope-base mark"])
            rows = run(
                USER, str(team), "--ladder", str(LADDER), "--format", "ladder-overrides"
            ).stdout.splitlines()
            self.assertIn("python\tcyclomatic\tnone", rows)
            # The bundled defaults (change, auto) emit no scope lines at all.
            self.assertNotIn(
                "--scope-default change",
                run(USER, "--format", "dispatch-args").stdout,
            )

    def test_a_quoted_reference_is_a_named_type_error(self) -> None:
        # A YAML author who writes `reference: "20"` gets a string scalar, and
        # the assembler would compare a number against it; the resolver names
        # the key and layer instead of letting that reach a traceback.
        with tempfile.TemporaryDirectory() as tmp:
            team = Path(tmp) / "team.yaml"
            team.write_text(
                'complexity:\n  cyclomatic:\n    reference: "20"\n',
                encoding="utf-8",
            )
            result = run(USER, str(team))
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertIn("complexity.cyclomatic.reference", result.stderr)
            self.assertIn("number or null", result.stderr)
            self.assertIn("team", result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            self.assertEqual(result.stdout, "")

    def test_a_layer_outside_the_subset_is_a_named_error(self) -> None:
        result = run(USER, FLOW)
        self.assertEqual(result.returncode, 2)
        self.assertIn("flow mapping", result.stderr)
        self.assertIn("line 4", result.stderr)

    def test_missing_positional_layer_is_a_usage_error(self) -> None:
        self.assertEqual(run(str(FIXTURES / "nope.yaml")).returncode, 2)

    def test_formats(self) -> None:
        out = run(USER, TEAM, "--format", "ladder-overrides").stdout.splitlines()
        self.assertEqual(out, ["typescript\tcyclomatic\tlizard"])
        out = run(USER, TEAM, "--format", "dispatch-args").stdout.splitlines()
        self.assertEqual(out, ["--disable-lane dotnet"])
        out = run(USER, TEAM, LOCAL, "--format", "excludes").stdout.splitlines()
        self.assertEqual(out, ["vendor/**"])

    def test_from_json_derives_formats_from_a_resolved_document(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            resolved = Path(tmp) / "resolved.json"
            resolved.write_text(run(USER, TEAM, LOCAL).stdout, encoding="utf-8")
            self.assertEqual(
                run(
                    "--from-json", str(resolved), "--format", "ladder-overrides"
                ).stdout.splitlines(),
                ["typescript\tcyclomatic\tlizard"],
            )
            self.assertEqual(
                run(
                    "--from-json", str(resolved), "--format", "excludes"
                ).stdout.splitlines(),
                ["vendor/**"],
            )
            self.assertEqual(
                run(
                    "--from-json", str(resolved), "--format", "dispatch-args"
                ).stdout.splitlines(),
                ["--disable-lane dotnet"],
            )
            self.assertEqual(
                json.loads(run("--from-json", str(resolved)).stdout)["_layers"][
                    "scope.exclude"
                ],
                "local",
            )
            self.assertEqual(
                run("--from-json", str(Path(tmp) / "missing.json")).returncode, 2
            )


class DiscoveredLayerTests(unittest.TestCase):
    def test_discovers_layers_and_ecosystem_files_from_home_and_repo_root(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / "home"
            root = Path(tmp) / "repo"
            (home / ".claude" / "ecosystems").mkdir(parents=True)
            (root / ".claude" / "ecosystems").mkdir(parents=True)
            (home / ".claude" / "code-metrics.yaml").write_text(
                "size:\n  file_lines: 700\n", encoding="utf-8"
            )
            (root / ".claude" / "code-metrics.yaml").write_text(
                "complexity:\n  cyclomatic:\n    reference: 12\n", encoding="utf-8"
            )
            (root / ".claude" / "code-metrics.local.yaml").write_text(
                "size:\n  file_lines: 650\n", encoding="utf-8"
            )
            # An ecosystem file's stem IS the lane name, and every lane name
            # this repository knows is also the basename of a committed
            # convention example. A literal `<lane>.yaml` here would make
            # scripts/affected-tests.sh map that unrelated example to this
            # suite, so the fixture names are composed from the lane instead.
            ecosystems = root / ".claude" / "ecosystems"
            shell, golang = "bash", "go"
            (ecosystems / (shell + ".yaml")).write_text(
                'globs: ["*.sh", "*.bats"]\nenabled: true\n', encoding="utf-8"
            )
            (ecosystems / (golang + ".yaml")).write_text(
                'globs: ["*.go"]\n', encoding="utf-8"
            )
            (ecosystems / (golang + ".local.yaml")).write_text(
                "enabled: false\n", encoding="utf-8"
            )
            result = run("--home", str(home), "--repo-root", str(root))
            self.assertEqual(result.returncode, 0, result.stderr)
            d = json.loads(result.stdout)
            self.assertEqual(d["size"]["file_lines"], 650)
            self.assertEqual(d["_layers"]["size.file_lines"], "local")
            self.assertEqual(d["complexity"]["cyclomatic"]["reference"], 12)
            self.assertEqual(
                d["_ecosystems"]["bash"],
                {"globs": ["*.sh", "*.bats"], "enabled": True, "layer": "team"},
            )
            self.assertEqual(d["_ecosystems"]["go"]["enabled"], False)
            self.assertNotIn("python", d["_ecosystems"])
            args = run(
                "--home",
                str(home),
                "--repo-root",
                str(root),
                "--format",
                "dispatch-args",
            ).stdout.splitlines()
            self.assertEqual(
                args, ["--lane-globs bash=*.sh,*.bats", "--disable-lane go"]
            )

    def test_all_layers_absent_is_the_bundled_defaults(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = run("--home", tmp, "--repo-root", tmp)
            d = json.loads(result.stdout)
            self.assertEqual(d["_files"], [])
            self.assertEqual(d["_layers"], {})
            self.assertEqual(d["complexity"]["cyclomatic"]["reference"], 20)
            self.assertEqual(d["_ecosystems"], {})


if __name__ == "__main__":
    unittest.main()
