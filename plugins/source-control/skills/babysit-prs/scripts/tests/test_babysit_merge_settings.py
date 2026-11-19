"""The trust and cost settings (babysit_merge_settings): read only from the
operator's user and managed settings, fail closed when unset, and never widened
by anything in a checkout or the environment.

Expected values come from the contract the module header states and
docs/contracts/hook-config-delivery channel F: the user settings file sits at
the config root above `plugins/cache/<marketplace>/<name>/<version>`, managed
files win, and an install outside the cache sees managed settings only.
"""

from __future__ import annotations

import contextlib
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_merge_settings as ms
from tests import REPO_SETTINGS, REPO_SETTINGS_FILE

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent
PLUGIN = "source-control@melodic-software"


def _write(path: pathlib.Path, data: object) -> pathlib.Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data), encoding="utf-8")
    return path


def _config(options: dict, plugin: str = PLUGIN) -> dict:
    return {"pluginConfigs": {plugin: {"options": options}}}


class ReadsOnlyTheOperatorsSettings(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        self.config = self.root / "home/.claude"
        self.cache_root = (
            self.config / "plugins/cache/melodic-software/source-control/1.2.3"
        )
        _write(
            self.cache_root / ".claude-plugin/plugin.json", {"name": "source-control"}
        )
        self.checkout = self.root / "checkout"
        _write(self.checkout / ".claude-plugin/plugin.json", {"name": "source-control"})

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def read(self, root: pathlib.Path, managed: list[pathlib.Path] = ()) -> dict:
        return ms.read_operator_options(ms.resolve_install(root), list(managed))

    def test_a_cache_install_reads_its_own_user_settings(self) -> None:
        _write(
            self.config / "settings.json",
            _config({"unattended_merge_owners": ["acme"]}),
        )
        self.assertEqual(
            self.read(self.cache_root), {"unattended_merge_owners": ["acme"]}
        )

    def test_another_plugin_or_marketplace_entry_is_not_read(self) -> None:
        _write(
            self.config / "settings.json",
            {
                "pluginConfigs": {
                    "source-control@other": {
                        "options": {"unattended_merge_owners": ["x"]}
                    },
                    "work-items@melodic-software": {
                        "options": {"unattended_merge_owners": ["y"]}
                    },
                }
            },
        )
        self.assertEqual(self.read(self.cache_root), {})

    def test_managed_settings_win_and_a_later_drop_in_wins(self) -> None:
        _write(
            self.config / "settings.json",
            _config({"owner_decisions_record": "a/b/c.md"}),
        )
        first = _write(
            self.root / "m/managed-settings.json",
            _config({"owner_decisions_record": "d/e/f.md"}),
        )
        later = _write(
            self.root / "m/managed-settings.d/50.json",
            _config({"owner_decisions_record": "g/h/i.md"}),
        )
        self.assertEqual(
            self.read(self.cache_root, [first, later]),
            {"owner_decisions_record": "g/h/i.md"},
        )

    def test_a_checkout_install_sees_managed_settings_only(self) -> None:
        _write(
            self.config / "settings.json",
            _config({"unattended_merge_owners": ["acme"]}),
        )
        _write(
            self.checkout / "settings.json",
            _config({"unattended_merge_owners": ["pr"]}),
        )
        self.assertEqual(self.read(self.checkout), {})
        managed = _write(
            self.root / "m/managed-settings.json",
            _config({"unattended_merge_owners": ["ci"]}),
        )
        self.assertEqual(
            self.read(self.checkout, [managed]), {"unattended_merge_owners": ["ci"]}
        )

    def test_a_malformed_source_raises(self) -> None:
        bad = (
            "{not json",
            json.dumps([]),
            json.dumps({"pluginConfigs": []}),
            json.dumps({"pluginConfigs": {PLUGIN: []}}),
            json.dumps({"pluginConfigs": {PLUGIN: {"options": []}}}),
            json.dumps(_config({"owner_decisions_record": ["a/b/c.md"]})),
            json.dumps(_config({"unattended_merge_owners": [1]})),
        )
        for text in bad:
            with self.subTest(text):
                (self.config / "settings.json").write_text(text, encoding="utf-8")
                with self.assertRaises(ms.OptionsError):
                    self.read(self.cache_root)

    def test_an_unreadable_source_leaves_every_setting_unset(self) -> None:
        (self.config / "settings.json").write_text("{not json", encoding="utf-8")
        managed = ms.managed_settings_files
        ms.managed_settings_files = lambda platform=sys.platform: []
        try:
            got = ms.load(self.cache_root)
        finally:
            ms.managed_settings_files = managed
        self.assertEqual(got, ms.Settings(notes=got.notes))
        self.assertIn("every trust and cost setting reads unset", got.notes[0])


class ReadsTheCiDropIn(unittest.TestCase):
    """The CI shape: a checkout run by path, with the default branch's
    settings file written as a managed-settings.d drop-in."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.tmp.name)
        self.managed = self.root / "etc/claude-code"
        self.repo = REPO_SETTINGS_FILE

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_drop_ins_are_read_in_name_order_after_the_base_file(self) -> None:
        _write(self.managed / "managed-settings.json", {"apiKeyHelper": ""})
        _write(self.managed / "managed-settings.d/50-source-control.json", {})
        _write(self.managed / "managed-settings.d/10-other.json", {})
        _write(self.managed / "managed-settings.d/.hidden.json", {})
        _write(self.managed / "managed-settings.d/notes.txt", {})
        self.assertEqual(
            [p.name for p in ms.managed_settings_files(root=self.managed)],
            ["managed-settings.json", "10-other.json", "50-source-control.json"],
        )

    def test_the_repository_file_as_a_drop_in_gives_its_values(
        self,
    ) -> None:
        dropin = self.managed / "managed-settings.d/50-source-control.json"
        dropin.parent.mkdir(parents=True)
        dropin.write_bytes(self.repo.read_bytes())
        checkout = self.root / "work/.base/plugins/source-control"
        _write(checkout / ".claude-plugin/plugin.json", {"name": "source-control"})
        raw = ms.read_operator_options(
            ms.resolve_install(checkout), ms.managed_settings_files(root=self.managed)
        )
        self.assertEqual(ms.parse(raw), REPO_SETTINGS)

    def test_a_later_drop_in_replaces_an_earlier_value(self) -> None:
        _write(
            self.managed / "managed-settings.d/50-source-control.json",
            _config({"unattended_merge_owners": ["a"]}),
        )
        _write(
            self.managed / "managed-settings.d/60-later.json",
            _config({"unattended_merge_owners": ["b"]}),
        )
        checkout = self.root / "co"
        _write(checkout / ".claude-plugin/plugin.json", {"name": "source-control"})
        raw = ms.read_operator_options(
            ms.resolve_install(checkout), ms.managed_settings_files(root=self.managed)
        )
        self.assertEqual(raw, {"unattended_merge_owners": ["b"]})

    def test_the_ci_shape_ignores_the_environment_and_the_checkout(self) -> None:
        dropin = self.managed / "managed-settings.d/50-source-control.json"
        dropin.parent.mkdir(parents=True)
        dropin.write_bytes(self.repo.read_bytes())
        work = self.root / "work"
        wide = _config({"unattended_merge_owners": ["attacker"]})
        _write(work / ".claude/settings.json", wide)
        _write(work / ".github/source-control-settings.json", wide)
        code = (
            "import json, pathlib, babysit_merge_settings as s\n"
            f"root = pathlib.Path({str(self.managed)!r})\n"
            "s.managed_settings_files = lambda platform=None: "
            "s.__dict__['_files'](root=root)\n"
            "print(json.dumps(s.as_json(s.load())))\n"
        )
        env = dict(
            os.environ,
            CLAUDE_PLUGIN_OPTION_UNATTENDED_MERGE_OWNERS="attacker",
            CLAUDE_CONFIG_DIR=str(work / ".claude"),
            HOME=str(work),
        )
        prelude = (
            f"import sys; sys.path.insert(0, {str(SCRIPTS)!r})\n"
            "import babysit_merge_settings as s; s._files = s.managed_settings_files\n"
        )
        out = subprocess.run(
            [sys.executable, "-I", "-c", prelude + code],
            cwd=work,
            env=env,
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        self.assertEqual(json.loads(out), ms.as_json(REPO_SETTINGS))


class APullRequestCannotWidenASetting(unittest.TestCase):
    """What a pull request controls: files in the checkout, a project
    `.claude/settings.json` and, through it, the environment. None is read."""

    def test_checkout_files_and_the_environment_are_not_sources(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            wide = {
                "unattended_merge_owners": ["attacker"],
                "review_lane_checks": ["claude-review:merge=anything"],
                "free_runner_labels": ["*-billed-*"],
            }
            _write(
                root / ".claude/settings.json",
                _config(wide)
                | {"env": {"CLAUDE_PLUGIN_OPTION_UNATTENDED_MERGE_OWNERS": "attacker"}},
            )
            _write(root / ".github/source-control-settings.json", _config(wide))
            code = (
                "import json, babysit_merge_settings as s\n"
                "s.managed_settings_files = lambda platform=None: []\n"
                "print(json.dumps(s.as_json(s.load())))\n"
            )
            env = dict(
                os.environ,
                CLAUDE_PLUGIN_OPTION_UNATTENDED_MERGE_OWNERS="attacker",
                CLAUDE_CONFIG_DIR=str(root / ".claude"),
                HOME=str(root),
            )
            out = subprocess.run(
                [
                    sys.executable,
                    "-I",
                    "-c",
                    f"import sys; sys.path.insert(0, {str(SCRIPTS)!r})\n{code}",
                ],
                cwd=root,
                env=env,
                capture_output=True,
                text=True,
                check=True,
            ).stdout
        self.assertEqual(json.loads(out), ms.as_json(ms.Settings()))


class EveryConsumerFailsClosedWhenUnset(unittest.TestCase):
    def test_the_gate_tables_are_empty(self) -> None:
        code = (
            "import json, babysit_merge_settings as s\n"
            "s.managed_settings_files = lambda platform=None: []\n"
            "import babysit_merge as m, babysit_review_evidence as r, babysit_risk as k, babysit_merge_policy as p\n"
            "print(json.dumps({\n"
            " 'checks': m.AI_REVIEW_CHECKS, 'lanes': r.LANES, 'callers': sorted(r.REVIEW_CALLERS),\n"
            " 'app': p.LANES_APP_LOGIN, 'row': bool(p.DECISION_ROW.search("
            "'https://github.com/melodic-software/architecture/blob/main/docs/owner-decisions.md#L1')),\n"
            " 'free': [bool(k._FREE_RUNNER.fullmatch(l)) for l in ('ubuntu-latest', 'melodic-ubuntu-24.04-x64')],\n"
            " 'model': [bool(k._MODEL_ACTION_NAME.search(n)) for n in ('claude-code-action', 'run-claude-cli')],\n"
            " 'hint': k._decision_record_hint()}))\n"
        )
        env = dict(os.environ, BABYSIT_VERIFY_LEGACY_FAILS="")
        out = subprocess.run(
            [sys.executable, "-c", code],
            cwd=SCRIPTS,
            env=env,
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        got = json.loads(out.splitlines()[-1])
        self.assertEqual(
            got["checks"],
            {"claude-review-status": [], "claude-security-review-status": []},
        )
        self.assertEqual(
            got["lanes"],
            {"claude-review": ["", []], "claude-security-review": ["", []]},
        )
        self.assertEqual(got["callers"], [])
        self.assertEqual(got["app"], "")
        self.assertFalse(got["row"])
        self.assertEqual(got["free"], [True, False])
        self.assertEqual(got["model"], [True, False])
        self.assertIn("no owner-decisions record is set", got["hint"])

    def test_a_lane_with_no_names_matches_no_check(self) -> None:
        import babysit_merge

        self.assertFalse(babysit_merge.is_ai_review_check("PR Review / Status", ()))

    def test_no_decision_row_matches_without_a_record(self) -> None:
        self.assertIsNone(
            ms.decision_row_pattern("").search(
                "https://github.com/a/b/blob/main/c.md#L1"
            )
        )


class ConfiguredValues(unittest.TestCase):
    def test_this_repository_values_parse_whole(self) -> None:
        self.assertEqual(REPO_SETTINGS.notes, ())
        self.assertEqual(REPO_SETTINGS.unattended_merge_owners, ("melodic-software",))
        self.assertEqual(
            REPO_SETTINGS.issue_status_app_login, "melodic-automation-lanes[bot]"
        )
        caller, status, merge = REPO_SETTINGS.review_lane_checks["claude-review"]
        self.assertEqual(caller, ".github/workflows/pr-review-hosted.yml")
        self.assertEqual(status[0], "PR Review / review-status")
        self.assertEqual(merge[0], "claude-review-status")

    def test_the_decision_row_is_the_records_line_link(self) -> None:
        row = ms.decision_row_pattern("acme/records/docs/decisions.md")
        good = "https://github.com/acme/records/blob/main/docs/decisions.md#L4-L9"
        self.assertTrue(row.search(good))
        for other in (
            good.replace("acme/records", "acme/other"),
            good.replace("/main/", "/feature/"),
            good.replace("#L4-L9", ""),
            good.replace("decisions.md", "decisionsXmd"),
        ):
            with self.subTest(other):
                self.assertIsNone(row.search(other))

    def test_a_label_glob_star_spans_letters_digits_and_dashes_only(self) -> None:
        import re

        free = re.compile(ms.glob_regex(("acme-*-x64",), "[a-z0-9-]*"), re.IGNORECASE)
        self.assertTrue(free.fullmatch("acme-big-runner-x64"))
        self.assertTrue(free.fullmatch("ACME-BIG-X64"))
        self.assertFalse(free.fullmatch("acme-a.b-x64"))
        self.assertFalse(free.fullmatch("acme-big-x64-more"))

    def test_a_malformed_entry_drops_the_whole_setting(self) -> None:
        cases = {
            "unattended_merge_owners": ["acme", "not an owner"],
            "review_lane_workflows": [
                "code-review=acme/r/.github/workflows/a.yml",
                "review=acme/r/x.yml",
            ],
            "review_lane_checks": [
                "claude-review:caller=.github/workflows/a.yml",
                "claude-review:caller=.github/workflows/b.yml",
            ],
            "owner_decisions_record": "https://github.com/acme/r/blob/main/x.md",
            "free_runner_labels": ["*"],
            "model_leg_actions": ["run claude"],
            "issue_status_app_login": "someone",
        }
        for key, value in cases.items():
            with self.subTest(key):
                notes: list[str] = []
                got = ms.parse({key: value}, notes)
                self.assertEqual(getattr(got, key), getattr(ms.Settings(), key))
                self.assertIn(key, notes[0])

    def test_the_cli_prints_the_resolved_settings(self) -> None:
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            ms.main(["nope"])


if __name__ == "__main__":
    unittest.main()
