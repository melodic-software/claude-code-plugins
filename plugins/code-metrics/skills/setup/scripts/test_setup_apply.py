#!/usr/bin/env python3
# test-scope: plugins/code-metrics/scripts/pathglob.py

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

os.environ.pop("GIT_DIR", None)
os.environ.pop("GIT_WORK_TREE", None)
os.environ.pop("GIT_CONFIG", None)
os.environ.pop("CODE_METRICS_USER_FILE", None)
os.environ.setdefault("GIT_CONFIG_GLOBAL", os.devnull)
os.environ["GIT_CONFIG_NOSYSTEM"] = "1"

SCRIPT_DIR = Path(__file__).resolve().parent
SCRIPT = SCRIPT_DIR / "setup-apply.py"
YAML_SUBSET = SCRIPT_DIR.parents[2] / "scripts" / "yaml_subset.py"
DEFAULTS = SCRIPT_DIR.parents[2] / "scripts" / "config-defaults.json"
RESOLVER = SCRIPT_DIR.parents[2] / "scripts" / "resolve-config.py"

_spec = importlib.util.spec_from_file_location("yaml_subset", YAML_SUBSET)
assert _spec is not None and _spec.loader is not None
yaml_subset = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(yaml_subset)


def run(*args: str, cwd: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
        cwd=cwd,
    )


class SetupApplyTests(unittest.TestCase):
    def test_writes_then_reports_already_configured_byte_identical(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            first = run("--dir", tmp, "size.file_lines=500")
            self.assertEqual(first.returncode, 0, first.stderr)
            target = Path(tmp) / "docs" / "conventions" / "code-metrics.yaml"
            self.assertIn("written", first.stdout)
            written = target.read_bytes()
            self.assertEqual(
                yaml_subset.parse(written.decode()), {"size": {"file_lines": 500}}
            )
            second = run("--dir", tmp, "size.file_lines=500")
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertIn("already configured", second.stdout)
            self.assertEqual(target.read_bytes(), written)

    def test_merges_per_key_and_preserves_unknown_keys(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "cm.yaml"
            target.write_text(
                "# hand-written\ncomplexity:\n  cyclomatic:\n    reference: 10\ncustom_key: keep\n",
                encoding="utf-8",
            )
            result = run(
                "--file",
                str(target),
                "size.file_lines=500",
                'scope.exclude=["vendor/**", "gen/**"]',
                "lanes.dotnet.enabled=false",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            doc = yaml_subset.parse(target.read_text(encoding="utf-8"))
            self.assertEqual(doc["complexity"]["cyclomatic"]["reference"], 10)
            self.assertEqual(doc["custom_key"], "keep")
            self.assertEqual(doc["size"]["file_lines"], 500)
            self.assertEqual(doc["scope"]["exclude"], ["vendor/**", "gen/**"])
            self.assertIs(doc["lanes"]["dotnet"]["enabled"], False)
            self.assertIn(
                "custom_key is not a key the contract declares",
                run("--file", str(target), "custom_key=keep").stderr,
            )

    def test_quoting_round_trips_awkward_strings(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / "cm.yaml"
            run(
                "--file",
                str(target),
                'coverage.artifacts=["a: b.info", "#hash", "true"]',
            )
            doc = yaml_subset.parse(target.read_text(encoding="utf-8"))
            self.assertEqual(
                doc["coverage"]["artifacts"], ["a: b.info", "#hash", "true"]
            )

    def test_no_dir_targets_the_repository_root_from_a_subdirectory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(["git", "init", "-q", tmp], check=True)
            sub = Path(tmp) / "sub"
            sub.mkdir()
            result = run("size.file_lines=500", cwd=str(sub))
            self.assertEqual(result.returncode, 0, result.stderr)
            target = Path(tmp) / "docs" / "conventions" / "code-metrics.yaml"
            self.assertTrue(target.is_file(), "written at the repository root")
            self.assertFalse((sub / "docs").exists())
            outside = Path(tmp) / "plain"
            outside.mkdir()
            result = run("size.file_lines=500", cwd=str(outside))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                Path(result.stdout.split()[-1]).resolve().parents[2],
                Path(tmp).resolve(),
                "inside the repository, a plain subdirectory still resolves to the root",
            )

    def test_a_claude_file_is_carried_whole_into_the_docs_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / "home"
            home.mkdir()
            root = Path(tmp) / "repo"
            (root / ".claude").mkdir(parents=True)
            retired = root / ".claude" / "code-metrics.yaml"
            retired.write_text(
                "complexity:\n  cyclomatic:\n    reference: 12\n"
                'scope:\n  exclude: ["gen/**"]\n'
                "lanes:\n  go:\n    enabled: false\n",
                encoding="utf-8",
            )
            empty_user = home / "empty.yaml"
            empty_user.write_text("", encoding="utf-8")

            def resolved(*args: str) -> dict:
                out = subprocess.run(
                    [sys.executable, str(RESOLVER), *args],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout
                return {
                    k: v for k, v in json.loads(out).items() if not k.startswith("_")
                }

            before = resolved(str(empty_user), str(retired))
            result = run("--dir", str(root), "size.mode=file-lines")
            self.assertEqual(result.returncode, 0, result.stderr)
            target = root / "docs" / "conventions" / "code-metrics.yaml"
            self.assertEqual(
                yaml_subset.parse(target.read_text(encoding="utf-8")),
                {
                    "complexity": {"cyclomatic": {"reference": 12}},
                    "scope": {"exclude": ["gen/**"]},
                    "lanes": {"go": {"enabled": False}},
                    "size": {"mode": "file-lines"},
                },
            )
            self.assertIn(".claude/code-metrics.yaml", result.stdout)
            self.assertIn("delete it", result.stdout)
            self.assertEqual(
                resolved("--home", str(home), "--repo-root", str(root)), before
            )

    def test_with_no_key_a_claude_file_is_moved_and_nothing_else_is_an_error(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.assertEqual(run("--dir", tmp).returncode, 2)
            (root / ".claude").mkdir()
            (root / ".claude" / "code-metrics.yaml").write_text(
                "size:\n  file_lines: 450\n", encoding="utf-8"
            )
            result = run("--dir", tmp)
            self.assertEqual(result.returncode, 0, result.stderr)
            target = root / "docs" / "conventions" / "code-metrics.yaml"
            self.assertEqual(
                yaml_subset.parse(target.read_text(encoding="utf-8")),
                {"size": {"file_lines": 450}},
            )
            again = run("--dir", tmp)
            self.assertEqual(again.returncode, 2)

    def test_errors(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(run("--dir", tmp).returncode, 2)
            self.assertEqual(run("--dir", tmp, "size.file_lines").returncode, 2)
            result = run("--dir", tmp, "lanes.typescript={ enabled: true }")
            self.assertEqual(result.returncode, 2)
            self.assertIn("outside the YAML subset", result.stderr)
            bad = Path(tmp) / "bad.yaml"
            bad.write_text("a: { b: 1 }\n", encoding="utf-8")
            result = run("--file", str(bad), "size.file_lines=1")
            self.assertEqual(result.returncode, 2)
            self.assertIn("fix it by hand", result.stderr)

    def test_a_dangling_target_symlink_is_refused_and_never_written_through(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "repo"
            (root / ".claude").mkdir(parents=True)
            (root / ".claude" / "code-metrics.yaml").write_text(
                "size:\n  file_lines: 450\n", encoding="utf-8"
            )
            (root / "docs" / "conventions").mkdir(parents=True)
            victim = Path(tmp) / "bash_profile"
            (root / "docs" / "conventions" / "code-metrics.yaml").symlink_to(victim)
            result = run("--dir", str(root))
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn("symlink", result.stderr)
            self.assertFalse(victim.exists(), "nothing written outside the repo")

    def test_a_symlinked_legacy_file_is_refused_and_never_carried(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "repo"
            (root / ".claude").mkdir(parents=True)
            secret = Path(tmp) / "hosts.yml"
            secret.write_text("size:\n  file_lines: 450\n", encoding="utf-8")
            (root / ".claude" / "code-metrics.yaml").symlink_to(secret)
            result = run("--dir", str(root))
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn("symlink", result.stderr)
            self.assertFalse(
                (root / "docs" / "conventions" / "code-metrics.yaml").exists()
            )

    def test_a_symlinked_docs_dir_is_refused_and_never_written_through(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "repo"
            root.mkdir()
            outside = Path(tmp) / "outside"
            outside.mkdir()
            (root / "docs").symlink_to(outside)
            result = run("--dir", str(root), "size.file_lines=500")
            self.assertEqual(result.returncode, 1, result.stdout)
            self.assertIn("docs is a symlink", result.stderr)
            self.assertEqual(list(outside.iterdir()), [])

    def test_unknown_carried_keys_are_dropped_and_named(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".claude").mkdir()
            (root / ".claude" / "code-metrics.yaml").write_text(
                "size:\n  file_lines: 450\n  bogus: 1\n"
                "oauth_token: gho_example\n"
                "lanes:\n  go:\n    enabled: false\n",
                encoding="utf-8",
            )
            result = run("--dir", tmp)
            self.assertEqual(result.returncode, 0, result.stderr)
            target = root / "docs" / "conventions" / "code-metrics.yaml"
            self.assertEqual(
                yaml_subset.parse(target.read_text(encoding="utf-8")),
                {"size": {"file_lines": 450}, "lanes": {"go": {"enabled": False}}},
            )
            self.assertIn("oauth_token", result.stderr)
            self.assertIn("size.bogus", result.stderr)
            self.assertNotIn("gho_example", target.read_text(encoding="utf-8"))

    def _old_layout(self, tmp: str) -> tuple[Path, Path, Path]:
        home = Path(tmp) / "home"
        root = Path(tmp) / "repo"
        (home / ".claude").mkdir(parents=True)
        (root / ".claude").mkdir(parents=True)
        (root / "docs" / "conventions").mkdir(parents=True)
        return home, root, root / "docs" / "conventions" / "code-metrics.local.yaml"

    def _git_repo(self, root: Path, ignore: str | None) -> None:
        subprocess.run(["git", "init", "-q", str(root)], check=True)
        if ignore is not None:
            (root / ".gitignore").write_text(ignore, encoding="utf-8")

    def _resolve(
        self, home: Path, root: Path, *extra: str
    ) -> subprocess.CompletedProcess:
        return subprocess.run(
            [
                sys.executable,
                str(RESOLVER),
                "--home",
                str(home),
                "--repo-root",
                str(root),
                *extra,
            ],
            capture_output=True,
            text=True,
            check=True,
        )

    def test_copy_old_sends_each_old_file_to_its_own_layer(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home, root, personal = self._old_layout(tmp)
            self._git_repo(root, "docs/conventions/**/*.local.*\n")
            old_user = home / ".claude" / "code-metrics.yaml"
            old_local = root / ".claude" / "code-metrics.local.yaml"
            user_file = home / "cfg" / "code-metrics.yaml"
            old_user.write_text(
                "size:\n  file_lines: 700\ncomplexity:\n  cyclomatic:\n    reference: 9\n",
                encoding="utf-8",
            )
            old_local.write_text("size:\n  mode: iso-8.2.115\n", encoding="utf-8")
            (root / "docs" / "conventions" / "code-metrics.yaml").write_text(
                "complexity:\n  cognitive:\n    reference: 12\n", encoding="utf-8"
            )
            option = ("--user-file", "~/cfg/code-metrics.yaml")
            before = self._resolve(home, root, *option)
            self.assertIn(str(old_user), before.stderr)
            self.assertIn(str(old_local), before.stderr)

            copy = ("--copy-old", "--dir", str(root), "--home", str(home), *option)
            preview = run(*copy, "--preview")
            self.assertEqual(preview.returncode, 0, preview.stderr)
            self.assertEqual(preview.stdout.count("preview, nothing written"), 2)
            self.assertFalse(personal.exists())
            self.assertFalse(user_file.exists())

            result = run(*copy)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                yaml_subset.parse(user_file.read_text(encoding="utf-8")),
                {
                    "size": {"file_lines": 700},
                    "complexity": {"cyclomatic": {"reference": 9}},
                },
            )
            self.assertEqual(
                yaml_subset.parse(personal.read_text(encoding="utf-8")),
                {"size": {"mode": "iso-8.2.115"}},
            )
            self.assertIn(
                f"copy: complexity.cyclomatic.reference from {old_user} to {user_file}",
                result.stdout,
            )
            self.assertNotIn("not gitignored", result.stderr)
            self.assertTrue(old_user.is_file() and old_local.is_file())
            self.assertIn(f"left in place: {old_user}", result.stdout)
            self.assertIn(f"left in place: {old_local}", result.stdout)

            after = self._resolve(home, root, *option)

            def strip(out: str) -> dict:
                return {
                    k: v for k, v in json.loads(out).items() if not k.startswith("_")
                }

            self.assertEqual(strip(after.stdout), strip(before.stdout))
            provenance = json.loads(after.stdout)["_provenance"]
            self.assertEqual(
                provenance["complexity.cyclomatic.reference"],
                {"value": 9, "layer": "userConfig"},
            )
            self.assertEqual(
                provenance["size.file_lines"], {"value": 700, "layer": "userConfig"}
            )
            self.assertEqual(
                provenance["complexity.cognitive.reference"],
                {"value": 12, "layer": "team"},
            )
            self.assertEqual(
                provenance["size.mode"], {"value": "iso-8.2.115", "layer": "local"}
            )
            self.assertIn(
                f"{old_user} is the old user-global file and is not read", after.stderr
            )
            self.assertIn(
                f"{old_local} is the old personal override and is not read",
                after.stderr,
            )

            again = run(*copy)
            self.assertEqual(again.stdout.count("already configured"), 2)

    def test_copy_old_with_the_option_unset_copies_no_user_global_key(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home, root, personal = self._old_layout(tmp)
            self._git_repo(root, "docs/conventions/**/*.local.*\n")
            (home / ".claude" / "code-metrics.yaml").write_text(
                "complexity:\n  cyclomatic:\n    reference: 9\n", encoding="utf-8"
            )
            (root / ".claude" / "code-metrics.local.yaml").write_text(
                "size:\n  file_lines: 650\n", encoding="utf-8"
            )
            result = run(
                "--copy-old",
                "--dir",
                str(root),
                "--home",
                str(home),
                "--user-file",
                "${user_config.config_file}",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(
                "set the option in /config, then rerun --copy-old", result.stdout
            )
            old_user = home / ".claude" / "code-metrics.yaml"
            self.assertIn(
                f"left in place: {old_user}; keep it until the config_file option "
                "is set and --copy-old has copied its keys",
                result.stdout,
            )
            self.assertNotIn(f"left in place: {old_user}; delete it", result.stdout)
            self.assertEqual(
                yaml_subset.parse(personal.read_text(encoding="utf-8")),
                {"size": {"file_lines": 650}},
            )

    def test_copy_old_warns_when_git_does_not_ignore_the_personal_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home, root, personal = self._old_layout(tmp)
            self._git_repo(root, None)
            (root / ".claude" / "code-metrics.local.yaml").write_text(
                "size:\n  file_lines: 650\n", encoding="utf-8"
            )
            copy = ("--copy-old", "--dir", str(root), "--home", str(home))
            for args, written in ((("--preview",), False), ((), True)):
                result = run(*copy, *args)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f"{personal} is not gitignored", result.stderr)
                self.assertIn("docs/conventions/**/*.local.*", result.stderr)
                self.assertEqual(personal.exists(), written)

    def test_copy_old_keeps_keys_the_user_file_sets(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home, root, _ = self._old_layout(tmp)
            (home / ".claude" / "code-metrics.yaml").write_text(
                "size:\n  file_lines: 700\n  mode: iso-8.2.115\n", encoding="utf-8"
            )
            user_file = home / "code-metrics.yaml"
            user_file.write_text("size:\n  file_lines: 900\n", encoding="utf-8")
            result = run(
                "--copy-old",
                "--dir",
                str(root),
                "--home",
                str(home),
                "--user-file",
                str(user_file),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                yaml_subset.parse(user_file.read_text(encoding="utf-8")),
                {"size": {"file_lines": 900, "mode": "iso-8.2.115"}},
            )
            self.assertIn(f"{user_file} already sets it", result.stdout)

    def test_copy_old_refuses_a_relative_user_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home, root, _ = self._old_layout(tmp)
            (home / ".claude" / "code-metrics.yaml").write_text(
                "size:\n  file_lines: 700\n", encoding="utf-8"
            )
            result = run(
                "--copy-old",
                "--dir",
                str(root),
                "--home",
                str(home),
                "--user-file",
                "cfg/code-metrics.yaml",
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("is not an absolute path", result.stderr)

    def test_copy_old_keeps_keys_the_personal_override_sets(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home, root, personal = self._old_layout(tmp)
            (root / ".claude" / "code-metrics.local.yaml").write_text(
                "size:\n  file_lines: 650\n  mode: iso-8.2.115\n", encoding="utf-8"
            )
            personal.write_text("size:\n  file_lines: 600\n", encoding="utf-8")
            result = run("--copy-old", "--dir", str(root), "--home", str(home))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(
                yaml_subset.parse(personal.read_text(encoding="utf-8")),
                {"size": {"file_lines": 600, "mode": "iso-8.2.115"}},
            )
            self.assertIn("size.file_lines", result.stdout)
            self.assertIn("already sets it", result.stdout)

    def test_copy_old_with_no_old_file_writes_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home, root, personal = self._old_layout(tmp)
            result = run("--copy-old", "--dir", str(root), "--home", str(home))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("no old file found", result.stdout)
            self.assertFalse(personal.exists())
            self.assertEqual(run("--copy-old", "size.file_lines=1").returncode, 2)
            self.assertEqual(run("--preview", "--dir", str(root)).returncode, 2)

    def test_help_prints_usage_even_with_docstrings_stripped(self) -> None:
        result = subprocess.run(
            [sys.executable, "-OO", str(SCRIPT), "--help"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(
            "setup-apply.py [--dir <repo-root> | --file <path>]", result.stdout
        )

    def test_template_is_in_the_subset_and_names_only_contract_keys(self) -> None:
        template = SCRIPT_DIR.parent / "templates" / "config-template.yaml"
        doc = yaml_subset.load(template)
        defaults = json.loads(DEFAULTS.read_text(encoding="utf-8"))
        contract_keys = {k for k in defaults if not k.startswith("_")} - {"thresholds"}
        self.assertTrue(set(doc), "the template names at least one key")
        self.assertLessEqual(set(doc), contract_keys, sorted(set(doc) - contract_keys))
        for key in doc:
            self.assertEqual(
                sorted(doc[key]),
                sorted(defaults[key]),
                "template keys under %s differ from the contract" % key,
            )

        def leaves(node, prefix=""):
            if isinstance(node, dict):
                for k, v in node.items():
                    yield from leaves(v, f"{prefix}{k}.")
            else:
                yield prefix[:-1], node

        template_leaves = dict(leaves(doc))
        default_leaves = dict(leaves(defaults))
        for path, value in template_leaves.items():
            self.assertIn(path, default_leaves, path)
            self.assertEqual(value, default_leaves[path], path)


if __name__ == "__main__":
    unittest.main()
