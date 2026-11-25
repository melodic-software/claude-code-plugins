#!/usr/bin/env python3
# test-scope: plugins/code-metrics/scripts/pathglob.py plugins/code-metrics/scripts/yaml_subset.py

from __future__ import annotations

import json
import os
import re
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
DEFAULTS = SCRIPT_DIR / "config-defaults.json"
SCHEMA = SCRIPT_DIR.parent / "schemas" / "code-metrics.schema.json"


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
            d["_provenance"]["size.file_lines"], {"value": 800, "layer": "userConfig"}
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

    def test_personal_override_overrides_per_key(self) -> None:
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
            self.assertNotIn(
                "--scope-default change",
                run(USER, "--format", "dispatch-args").stdout,
            )

    def test_a_value_carrying_a_line_break_cannot_inject_a_second_directive(
        self,
    ) -> None:
        # The output formats are line oriented and the dispatcher reads them
        # with `mapfile`, so a scalar holding a newline would arrive as two
        # directives: one naming a base, one quietly disabling a lane. The
        # YAML subset's double-quoted scalars carry a real \n, so the layer
        # below is writable by hand.
        with tempfile.TemporaryDirectory() as tmp:
            team = Path(tmp) / "team.yaml"
            team.write_text(
                'scope:\n  base: "auto\\n--disable-lane python"\n', encoding="utf-8"
            )
            result = run(str(team), "--format", "dispatch-args")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, "")
            self.assertIn(str(team), result.stderr)
            self.assertIn("scope.base", result.stderr)
            self.assertIn("control character", result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            resolved = Path(tmp) / "resolved.json"
            resolved.write_text(
                json.dumps({"scope": {"base": "auto\n--disable-lane python"}}),
                encoding="utf-8",
            )
            through = run("--from-json", str(resolved), "--format", "dispatch-args")
            self.assertEqual(through.returncode, 2, through.stdout)
            self.assertNotIn("--disable-lane", through.stdout)

    def test_a_tab_in_a_ladder_field_cannot_shift_a_column(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            resolved = Path(tmp) / "resolved.json"
            resolved.write_text(
                json.dumps(
                    {"lanes": {"python": {"collectors": {"cyclomatic\tx": ["radon"]}}}}
                ),
                encoding="utf-8",
            )
            result = run("--from-json", str(resolved), "--format", "ladder-overrides")
            self.assertEqual(result.returncode, 2, result.stdout)
            self.assertIn("tab", result.stderr)

    def test_a_quoted_reference_is_dropped_by_name_and_never_falls_to_a_lower_layer(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            team = Path(tmp) / "team.yaml"
            team.write_text(
                'complexity:\n  cyclomatic:\n    reference: "15"\n',
                encoding="utf-8",
            )
            result = run(USER, str(team))
            self.assertEqual(result.returncode, 0, result.stderr)
            d = json.loads(result.stdout)
            self.assertEqual(
                d["_provenance"]["complexity.cyclomatic.reference"],
                {"value": 20, "layer": "bundled default"},
            )
            self.assertEqual(d["_provenance"]["size.file_lines"]["value"], 800)
            self.assertIn(str(team), result.stderr)
            self.assertIn("complexity.cyclomatic.reference", result.stderr)
            self.assertIn("'15'", result.stderr)
            self.assertIn("number or null", result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            local = Path(tmp) / "local.yaml"
            local.write_text(
                "complexity:\n  cyclomatic:\n    reference: 18\n", encoding="utf-8"
            )
            d = json.loads(run(USER, str(team), str(local)).stdout)
            self.assertEqual(
                d["_provenance"]["complexity.cyclomatic.reference"],
                {"value": 18, "layer": "local"},
            )

    def test_a_scalar_exclude_is_dropped_not_read_as_a_glob_per_character(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            user = Path(tmp) / "user.yaml"
            user.write_text('scope:\n  exclude: ["docs/**"]\n', encoding="utf-8")
            team = Path(tmp) / "team.yaml"
            team.write_text('scope:\n  exclude: "vendor/**"\n', encoding="utf-8")
            result = run(str(user), str(team), "--format", "excludes")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                result.stdout.splitlines(),
                ["**/node_modules/**", "**/vendor/**", "**/dist/**", "**/build/**"],
            )
            self.assertIn("scope.exclude", result.stderr)
            self.assertIn("must be a list", result.stderr)
            self.assertIn(str(team), result.stderr)
            self.assertNotIn("Traceback", result.stderr)
            resolved = Path(tmp) / "resolved.json"
            resolved.write_text(
                json.dumps({"scope": {"exclude": "vendor/**"}}), encoding="utf-8"
            )
            through = run("--from-json", str(resolved), "--format", "excludes")
            self.assertEqual(through.returncode, 2, through.stdout)
            self.assertEqual(through.stdout, "")

    def test_registries_come_from_scope_or_fall_back_to_the_duplication_alias(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            team = Path(tmp) / "team.yaml"
            team.write_text(
                "duplication:\n  registries: [old/registry.txt]\n", encoding="utf-8"
            )
            out = run(USER, str(team), "--format", "registries").stdout.splitlines()
            self.assertEqual(out, ["old/registry.txt"])
            team.write_text(
                "scope:\n  registries: [scripts/reg.txt]\n"
                "duplication:\n  registries: [old/registry.txt]\n",
                encoding="utf-8",
            )
            out = run(USER, str(team), "--format", "registries").stdout.splitlines()
            self.assertEqual(out, ["scripts/reg.txt"])
            self.assertEqual(run(USER, "--format", "registries").stdout, "")
            team.write_text('scope:\n  registries: "one.txt"\n', encoding="utf-8")
            refused = run(USER, str(team), "--format", "registries")
            self.assertEqual(refused.returncode, 0, refused.stderr)
            self.assertEqual(refused.stdout, "")
            self.assertIn("scope.registries", refused.stderr)
            self.assertIn("must be a list", refused.stderr)

    def test_correctness_rules_take_strings_and_an_invalid_layer_never_falls_lower(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            user = Path(tmp) / "user.yaml"
            user.write_text(
                "suppressions:\n  correctness_rules: [no-console]\n", encoding="utf-8"
            )
            team = Path(tmp) / "team.yaml"
            team.write_text(
                "suppressions:\n  correctness_rules: [SC2086, 2086]\n",
                encoding="utf-8",
            )
            local = Path(tmp) / "local.yaml"
            local.write_text(
                "suppressions:\n  correctness_rules: [CA2000]\n", encoding="utf-8"
            )
            result = run(str(user), str(team))
            self.assertEqual(result.returncode, 0, result.stderr)
            doc = json.loads(result.stdout)
            self.assertEqual(doc["suppressions"]["correctness_rules"], [])
            self.assertIn(str(team), result.stderr)
            self.assertIn("suppressions.correctness_rules", result.stderr)
            self.assertIn("2086", result.stderr)
            result = run(str(user), str(team), str(local))
            doc = json.loads(result.stdout)
            self.assertEqual(doc["suppressions"]["correctness_rules"], ["CA2000"])
            self.assertEqual(
                doc["_layers"]["suppressions.correctness_rules"], "local"
            )

    def test_an_unusable_exclude_glob_is_dropped_by_name(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            team = Path(tmp) / "team.yaml"
            team.write_text(
                'scope:\n  exclude: ["gen/**", "[z-a]"]\n', encoding="utf-8"
            )
            result = run(str(team), "--format", "excludes")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("gen/**", result.stdout)
            self.assertIn("**/vendor/**", result.stdout.splitlines())
            self.assertIn("'[z-a]'", result.stderr)
            self.assertIn("scope.exclude", result.stderr)

    def test_a_layer_outside_the_subset_is_named_and_ignored(self) -> None:
        result = run(USER, FLOW)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("flow mapping", result.stderr)
        self.assertIn("line 4", result.stderr)
        self.assertIn(FLOW, result.stderr)
        d = json.loads(result.stdout)
        self.assertEqual(d["_provenance"]["size.file_lines"]["value"], 800)
        self.assertEqual(d["_files"], [USER.replace("\\", "/")])

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


class SchemaTests(unittest.TestCase):
    def test_the_schema_declares_every_bundled_key_and_no_other(self) -> None:
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        defs = schema["$defs"]

        def schema_keys(node: dict, prefix: str, out: set[str]) -> None:
            if "$ref" in node:
                node = defs[node["$ref"].rsplit("/", 1)[-1]]
            props = node.get("properties") or {}
            if not props:
                out.add(prefix)
            for key, child in props.items():
                if key != "$schema":
                    schema_keys(child, f"{prefix}.{key}" if prefix else key, out)

        def default_keys(node: object, prefix: str, out: set[str]) -> None:
            if isinstance(node, dict):
                for key, child in node.items():
                    default_keys(child, f"{prefix}.{key}" if prefix else key, out)
            else:
                out.add(prefix)

        defaults = json.loads(DEFAULTS.read_text(encoding="utf-8"))
        defaults.pop("thresholds")
        lanes = defaults.pop("lanes")
        declared: set[str] = set()
        schema_keys(
            {
                "properties": {
                    k: v for k, v in schema["properties"].items() if k != "lanes"
                }
            },
            "",
            declared,
        )
        bundled: set[str] = set()
        default_keys(defaults, "", bundled)
        self.assertEqual(declared, bundled)
        lanes_schema = schema["properties"]["lanes"]
        self.assertEqual(sorted(lanes_schema["properties"]), sorted(lanes))
        pattern = re.compile(lanes_schema["propertyNames"]["pattern"])
        for lane in [*lanes, "rust", "cross-cutting"]:
            self.assertRegex(lane, pattern)
        for bad in ["Rust", "../x", "a/b", "-x"]:
            self.assertNotRegex(bad, pattern)
        self.assertEqual(
            lanes_schema["additionalProperties"], {"$ref": "#/$defs/lane"}
        )


class DiscoveredLayerTests(unittest.TestCase):
    def test_discovers_layers_and_ecosystem_files_from_home_and_repo_root(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / "home"
            root = Path(tmp) / "repo"
            (home / ".claude" / "ecosystems").mkdir(parents=True)
            (root / ".claude" / "ecosystems").mkdir(parents=True)
            (root / "docs" / "conventions").mkdir(parents=True)
            (home / ".claude" / "code-metrics.yaml").write_text(
                "size:\n  file_lines: 700\n", encoding="utf-8"
            )
            (root / "docs" / "conventions" / "code-metrics.yaml").write_text(
                "complexity:\n  cyclomatic:\n    reference: 12\n", encoding="utf-8"
            )
            (root / ".claude" / "code-metrics.local.yaml").write_text(
                "size:\n  file_lines: 650\n", encoding="utf-8"
            )
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

    def test_reads_ecosystem_records_from_the_convention_home_first(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "repo"
            home_dir = root / "docs" / "conventions" / "ecosystems"
            legacy = root / ".claude" / "ecosystems"
            home_dir.mkdir(parents=True)
            legacy.mkdir(parents=True)
            shell, golang, py = "bash", "go", "python"
            (home_dir / (shell + ".yaml")).write_text(
                'globs: ["*.sh"]\n', encoding="utf-8"
            )
            (legacy / (shell + ".yaml")).write_text(
                'globs: ["*.legacy"]\n', encoding="utf-8"
            )
            (home_dir / (golang + ".yaml")).write_text(
                'globs: ["*.go"]\n', encoding="utf-8"
            )
            (home_dir / (golang + ".local.yaml")).write_text(
                "enabled: false\n", encoding="utf-8"
            )
            (legacy / (py + ".yaml")).write_text(
                'globs: ["*.py"]\n', encoding="utf-8"
            )
            result = run("--home", tmp, "--repo-root", str(root))
            self.assertEqual(result.returncode, 0, result.stderr)
            d = json.loads(result.stdout)
            self.assertEqual(d["_ecosystems"]["bash"]["globs"], ["*.sh"])
            self.assertEqual(d["_ecosystems"]["go"]["enabled"], False)
            self.assertEqual(d["_ecosystems"]["go"]["layer"], "team")
            self.assertEqual(d["_ecosystems"]["python"]["globs"], ["*.py"])
            record = f"ecosystems/{shell}.yaml"
            both = [w for w in d["_warnings"] if record in w]
            self.assertEqual(len(both), 1, d["_warnings"])
            self.assertIn(f"docs/conventions/{record}", both[0])
            self.assertIn(f".claude/{record}", both[0])
            self.assertFalse(
                any(f"ecosystems/{py}." in w for w in d["_warnings"]),
                d["_warnings"],
            )

    def test_only_a_listed_lane_id_reads_its_ecosystem_record(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "repo"
            ecosystems = root / ".claude" / "ecosystems"
            ecosystems.mkdir(parents=True)
            (root / "docs" / "conventions").mkdir(parents=True)
            (root / "docs" / "conventions" / "code-metrics.yaml").write_text(
                "lanes:\n  rust:\n    enabled: true\n  python:\n    enabled: true\n",
                encoding="utf-8",
            )
            extra, shipped, unlisted = "rust", "python", "cross-cutting"
            (ecosystems / (extra + ".yaml")).write_text(
                'globs: ["**/*.rs"]\n', encoding="utf-8"
            )
            (ecosystems / (shipped + ".yaml")).write_text(
                'globs: ["**/*.py"]\n', encoding="utf-8"
            )
            (ecosystems / (unlisted + ".yaml")).write_text(
                'globs: ["**"]\n', encoding="utf-8"
            )
            result = run("--home", tmp, "--repo-root", str(root))
            self.assertEqual(result.returncode, 0, result.stderr)
            d = json.loads(result.stdout)
            self.assertEqual(d["_ecosystems"]["rust"]["globs"], ["**/*.rs"])
            self.assertEqual(d["_ecosystems"]["python"]["globs"], ["**/*.py"])
            self.assertNotIn("cross-cutting", d["_ecosystems"])
            args = run(
                "--home", tmp, "--repo-root", str(root), "--format", "dispatch-args"
            ).stdout.splitlines()
            self.assertEqual(
                args, ["--lane-globs python=**/*.py", "--lane-globs rust=**/*.rs"]
            )

    def test_a_lane_id_outside_kebab_case_is_dropped_by_name(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "repo"
            (root / ".claude" / "ecosystems").mkdir(parents=True)
            (root / "docs" / "conventions").mkdir(parents=True)
            (root / "docs" / "conventions" / "code-metrics.yaml").write_text(
                "lanes:\n  Rust:\n    enabled: true\n", encoding="utf-8"
            )
            (root / ".claude" / "ecosystems" / "Rust.yaml").write_text(
                'globs: ["**/*.rs"]\n', encoding="utf-8"
            )
            result = run("--home", tmp, "--repo-root", str(root))
            self.assertEqual(result.returncode, 0, result.stderr)
            d = json.loads(result.stdout)
            self.assertTrue(
                any("lanes.Rust.enabled" in w and "kebab-case" in w for w in d["_warnings"]),
                d["_warnings"],
            )
            self.assertEqual(d["_ecosystems"], {})

    def test_a_scalar_listed_lane_is_dropped_not_read_as_a_mapping(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "repo"
            (root / "docs" / "conventions").mkdir(parents=True)
            (root / "docs" / "conventions" / "code-metrics.yaml").write_text(
                "lanes:\n  rust: true\n  zig:\n    collectors: true\n", encoding="utf-8"
            )
            result = run(
                "--home", tmp, "--repo-root", str(root), "--ladder", str(LADDER)
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            d = json.loads(result.stdout)
            for key in ("lanes.rust", "lanes.zig.collectors"):
                self.assertTrue(
                    any(f"{key} = True: must be a mapping" in w for w in d["_warnings"]),
                    d["_warnings"],
                )
            args = run(
                "--home", tmp, "--repo-root", str(root), "--format", "dispatch-args"
            )
            self.assertEqual(args.returncode, 0, args.stderr)

    def _team_files(self, root: Path, docs: str | None, retired: str | None) -> None:
        if docs is not None:
            (root / "docs" / "conventions").mkdir(parents=True)
            (root / "docs" / "conventions" / "code-metrics.yaml").write_text(
                docs, encoding="utf-8"
            )
        if retired is not None:
            (root / ".claude").mkdir(parents=True)
            (root / ".claude" / "code-metrics.yaml").write_text(
                retired, encoding="utf-8"
            )

    def test_the_team_layer_reads_the_docs_conventions_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "repo"
            self._team_files(root, "size:\n  file_lines: 640\n", None)
            result = run("--home", tmp, "--repo-root", str(root))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, "")
            d = json.loads(result.stdout)
            self.assertEqual(
                d["_provenance"]["size.file_lines"], {"value": 640, "layer": "team"}
            )
            self.assertEqual(
                d["_files"], [f"{root.as_posix()}/docs/conventions/code-metrics.yaml"]
            )

    def test_a_claude_file_alone_leaves_the_team_layer_absent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "repo"
            self._team_files(root, None, "size:\n  file_lines: 630\n")
            result = run("--home", tmp, "--repo-root", str(root))
            self.assertEqual(result.returncode, 0, result.stderr)
            d = json.loads(result.stdout)
            self.assertEqual(
                d["_provenance"]["size.file_lines"],
                {"value": 1000, "layer": "bundled default"},
            )
            self.assertNotIn("team", d["_layers"].values())
            self.assertEqual(d["_files"], [])
            self.assertEqual(d["_warnings"], [])

    def test_with_both_files_only_the_docs_file_is_read(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "repo"
            self._team_files(
                root,
                "size:\n  file_lines: 640\n",
                "size:\n  file_lines: 630\ncomplexity:\n  cyclomatic:\n    reference: 9\n",
            )
            result = run("--home", tmp, "--repo-root", str(root))
            self.assertEqual(result.returncode, 0, result.stderr)
            d = json.loads(result.stdout)
            self.assertEqual(d["size"]["file_lines"], 640)
            self.assertEqual(d["complexity"]["cyclomatic"]["reference"], 20)
            self.assertEqual(
                d["_files"], [f"{root.as_posix()}/docs/conventions/code-metrics.yaml"]
            )

    def _personal(
        self,
        tmp: str,
        new: str | None,
        old: str | None,
        user: str | None,
        config_file: str | None = None,
        option: str | None = None,
    ):
        home = Path(tmp) / "home"
        root = Path(tmp) / "repo"
        (root / "docs" / "conventions").mkdir(parents=True)
        paths = {
            "new": root / "docs" / "conventions" / "code-metrics.local.yaml",
            "old": root / ".claude" / "code-metrics.local.yaml",
            "user": home / ".claude" / "code-metrics.yaml",
            "config_file": home / "cfg" / "code-metrics.yaml",
        }
        for name, text in (
            ("new", new),
            ("old", old),
            ("user", user),
            ("config_file", config_file),
        ):
            if text is not None:
                paths[name].parent.mkdir(parents=True, exist_ok=True)
                paths[name].write_text(text, encoding="utf-8")
        extra = () if option is None else ("--user-file", option)
        result = run("--home", str(home), "--repo-root", str(root), *extra)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout), result.stderr, paths

    def test_the_personal_layer_reads_the_docs_conventions_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            d, err, paths = self._personal(tmp, "size:\n  file_lines: 610\n", None, None)
            self.assertEqual(
                d["_provenance"]["size.file_lines"], {"value": 610, "layer": "local"}
            )
            self.assertEqual(d["_files"], [paths["new"].as_posix()])
            self.assertEqual(err, "")

    def test_an_old_personal_file_alone_applies_with_a_warning(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            d, err, paths = self._personal(tmp, None, "size:\n  file_lines: 620\n", None)
            self.assertEqual(
                d["_provenance"]["size.file_lines"], {"value": 620, "layer": "local"}
            )
            warnings = [w for w in d["_warnings"] if str(paths["old"]) in w]
            self.assertEqual(len(warnings), 1, d["_warnings"])
            self.assertIn(str(paths["new"]), warnings[0])
            self.assertEqual(err.count(str(paths["old"])), 1)

    def test_with_both_personal_files_the_new_one_wins_and_both_are_named(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            d, _, paths = self._personal(
                tmp, "size:\n  file_lines: 610\n", "size:\n  file_lines: 620\n", None
            )
            self.assertEqual(d["size"]["file_lines"], 610)
            self.assertNotIn(paths["old"].as_posix(), d["_files"])
            self.assertTrue(
                any(
                    str(paths["old"]) in w and str(paths["new"]) in w
                    for w in d["_warnings"]
                ),
                d["_warnings"],
            )

    def test_an_unparsable_new_personal_file_leaves_the_old_one_applied(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            d, _, paths = self._personal(
                tmp, "size: { file_lines: 610 }\n", "size:\n  file_lines: 620\n", None
            )
            self.assertEqual(d["size"]["file_lines"], 620)
            self.assertTrue(
                any(
                    str(paths["old"]) in w and "outside the YAML subset" in w
                    for w in d["_warnings"]
                ),
                d["_warnings"],
            )

    def test_an_old_user_global_file_alone_applies_as_userconfig_with_a_warning(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            d, err, paths = self._personal(
                tmp, None, None, "size:\n  file_lines: 700\n  mode: iso-8.2.115\n"
            )
            self.assertEqual(
                d["_provenance"]["size.file_lines"],
                {"value": 700, "layer": "userConfig"},
            )
            warnings = [w for w in d["_warnings"] if str(paths["user"]) in w]
            self.assertEqual(len(warnings), 1, d["_warnings"])
            self.assertIn("still read as the userConfig layer", warnings[0])
            self.assertIn(
                "the file the config_file userConfig option names", warnings[0]
            )
            self.assertNotIn(str(paths["new"]), warnings[0])
            self.assertEqual(err.count(str(paths["user"])), 1)

    def test_the_userconfig_layer_reads_the_file_the_option_names(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            d, err, paths = self._personal(
                tmp,
                None,
                None,
                None,
                "size:\n  file_lines: 710\n",
                "~/cfg/code-metrics.yaml",
            )
            self.assertEqual(
                d["_provenance"]["size.file_lines"],
                {"value": 710, "layer": "userConfig"},
            )
            self.assertEqual(d["_files"], [paths["config_file"].as_posix()])
            self.assertEqual(err, "")

    def test_the_userconfig_layer_sits_under_team_and_personal(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            d, _, paths = self._personal(
                tmp,
                "size:\n  file_lines: 610\n",
                None,
                None,
                "size:\n  file_lines: 710\n  mode: iso-8.2.115\n",
                "~/cfg/code-metrics.yaml",
            )
            self.assertEqual(
                d["_provenance"]["size.file_lines"], {"value": 610, "layer": "local"}
            )
            self.assertEqual(
                d["_provenance"]["size.mode"],
                {"value": "iso-8.2.115", "layer": "userConfig"},
            )

    def test_the_option_names_a_missing_file_so_the_old_file_applies(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            d, _, paths = self._personal(
                tmp,
                None,
                None,
                "size:\n  file_lines: 700\n",
                None,
                "~/cfg/code-metrics.yaml",
            )
            self.assertEqual(
                d["_provenance"]["size.file_lines"],
                {"value": 700, "layer": "userConfig"},
            )
            warnings = [w for w in d["_warnings"] if str(paths["user"]) in w]
            self.assertEqual(len(warnings), 1, d["_warnings"])
            self.assertIn(f"move it to {paths['config_file']}", warnings[0])

    def test_with_both_user_files_the_option_file_wins_and_both_are_named(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            d, err, paths = self._personal(
                tmp,
                None,
                None,
                "size:\n  file_lines: 700\n  mode: iso-8.2.115\n",
                "size:\n  file_lines: 710\n",
                str(Path(tmp) / "home" / "cfg" / "code-metrics.yaml"),
            )
            self.assertEqual(
                d["_provenance"]["size.file_lines"],
                {"value": 710, "layer": "userConfig"},
            )
            self.assertEqual(
                d["_provenance"]["size.mode"],
                {"value": "file-lines", "layer": "bundled default"},
            )
            self.assertNotIn(paths["user"].as_posix(), d["_files"])
            warnings = [w for w in d["_warnings"] if str(paths["user"]) in w]
            self.assertEqual(len(warnings), 1, d["_warnings"])
            self.assertIn(
                f"is not read because {paths['config_file']} exists", warnings[0]
            )
            self.assertEqual(err.count(str(paths["user"])), 1)

    def test_an_unset_or_relative_option_supplies_no_userconfig_file(self) -> None:
        for option, warned in (
            ("", False),
            ("${user_config.config_file}", False),
            ("cfg/code-metrics.yaml", True),
        ):
            with self.subTest(option=option), tempfile.TemporaryDirectory() as tmp:
                d, _, _ = self._personal(
                    tmp, None, None, None, "size:\n  file_lines: 710\n", option
                )
                self.assertEqual(
                    d["_provenance"]["size.file_lines"],
                    {"value": 1000, "layer": "bundled default"},
                )
                relative = [w for w in d["_warnings"] if "not an absolute path" in w]
                self.assertEqual(len(relative), int(warned), d["_warnings"])

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
