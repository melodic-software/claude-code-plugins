"""Per-target-repository resolution of the babysit repository-policy keys.

Covers each merge mode, the fail-closed fetch contract (only a gh-reported 404
means "no file"), the default-branch-only read, and the once-per-process
deprecation note. The gh seam is a fake runner; no real gh process is spawned.
"""

from __future__ import annotations

import base64
import contextlib
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import types
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_repo_config as rc
from repo_config_fake import RepoConfigFake

YAML_CALL = ["api", f"repos/o/r/contents/{rc.YAML_CONFIG_PATH}"]
LEGACY_CALL = ["api", f"repos/o/r/contents/{rc.CONFIG_PATH}"]


def _ok(text: str) -> subprocess.CompletedProcess[str]:
    body = {
        "type": "file",
        "encoding": "base64",
        "content": base64.encodebytes(text.encode()).decode(),
    }
    return subprocess.CompletedProcess([], 0, json.dumps(body), "")


def _fail(stderr: str, stdout: str = "") -> subprocess.CompletedProcess[str]:
    return subprocess.CompletedProcess([], 1, stdout, stderr)


class FakeGh:
    def __init__(
        self,
        responses: dict[str, subprocess.CompletedProcess[str]],
        roots: dict[str, subprocess.CompletedProcess[str]] | None = None,
    ) -> None:
        self.responses = responses
        self.roots = roots or {}
        self.calls: list[list[str]] = []

    def __call__(self, args: list[str]) -> subprocess.CompletedProcess[str]:
        self.calls.append(args)
        repo = "/".join(args[1].split("/")[1:3])
        if args[1].endswith("/contents"):
            return self.roots.get(repo, subprocess.CompletedProcess([], 0, "[]", ""))
        return self.responses[repo]


def _resolve(
    repo: str, fallback: dict[str, str | None], gh: FakeGh
) -> tuple[rc.EffectiveConfig, str]:
    err = io.StringIO()
    with contextlib.redirect_stderr(err):
        effective = rc.resolve(repo, fallback, gh)
    return effective, err.getvalue()


class MergeModeTests(unittest.TestCase):
    def test_hold_lists_union_and_never_drop_a_userconfig_entry(self) -> None:
        repo = rc.parse_repo_config(
            "## babysit_merge_block_labels\n- repo-hold\n\n"
            "## babysit_extra_dependency_manager_logins\n- Dep-Bot[bot]\n\n"
            "## babysit_approval_downgrade_logins\nreview-a, review-b\n"
        )
        eff = rc.merge_repo_config(
            repo,
            {
                "babysit_merge_block_labels": "do-not-merge,hold",
                "babysit_extra_dependency_manager_logins": "my-dep",
                "babysit_approval_downgrade_logins": "mine",
            },
        )
        self.assertEqual(eff.merge_block_labels, {"do-not-merge", "hold", "repo-hold"})
        self.assertEqual(eff.extra_dependency_manager_logins, {"my-dep", "dep-bot"})
        self.assertEqual(
            eff.approval_downgrade_logins, {"mine", "review-a", "review-b"}
        )
        self.assertTrue(set(rc.UNION_KEYS) <= eff.fallback_keys_used)

    def test_hold_list_labels_keep_a_bot_suffix(self) -> None:
        repo = rc.parse_repo_config("## babysit_merge_block_labels\n- wait[bot]\n")
        self.assertEqual(
            rc.merge_repo_config(repo, {}).merge_block_labels, {"wait[bot]"}
        )

    def test_repo_review_pair_is_ignored_and_userconfig_pair_passes_through(
        self,
    ) -> None:
        pair = (
            "## babysit_review_bot_logins\n- github-actions\n\n"
            "## babysit_review_settle_minutes\n60\n"
        )
        for body in (
            pair,
            "## babysit_review_bot_logins\n- github-actions\n",
            "## babysit_review_settle_minutes\n60\n",
        ):
            for fallback, bots, settle in (
                (
                    {
                        "babysit_review_bot_logins": "Claude[bot], other",
                        "babysit_review_settle_minutes": "10",
                    },
                    {"claude", "other"},
                    "10",
                ),
                ({"babysit_review_settle_minutes": "10"}, None, "10"),
                ({}, None, None),
            ):
                with self.subTest(body=body, fallback=fallback):
                    eff = rc.merge_repo_config(rc.parse_repo_config(body), fallback)
                    self.assertEqual(eff.review_bot_logins, bots)
                    self.assertEqual(eff.review_settle_minutes, settle)
                    self.assertEqual(len(eff.notes), 1)
                    self.assertFalse(
                        {rc.REVIEW_BOTS, rc.REVIEW_SETTLE} & eff.fallback_keys_used
                    )

    def test_userconfig_review_pair_is_not_deprecated(self) -> None:
        eff = rc.merge_repo_config(
            {},
            {
                "babysit_review_bot_logins": "mine",
                "babysit_review_settle_minutes": "10",
            },
        )
        self.assertEqual(eff.review_bot_logins, {"mine"})
        self.assertEqual(eff.review_settle_minutes, "10")
        self.assertEqual(eff.notes, ())
        self.assertFalse(eff.fallback_keys_used)

    def test_half_set_userconfig_pair_passes_through_for_the_gate_to_refuse(
        self,
    ) -> None:
        eff = rc.merge_repo_config({}, {"babysit_review_settle_minutes": "10"})
        self.assertIsNone(eff.review_bot_logins)
        self.assertEqual(eff.review_settle_minutes, "10")

    def test_skip_downgrade_repo_list_removes_but_cannot_add(self) -> None:
        repo = rc.parse_repo_config(
            "## babysit_skip_downgrade_logins\n- Keep[bot]\n- intruder\n"
        )
        eff = rc.merge_repo_config(repo, {"babysit_skip_downgrade_logins": "keep,drop"})
        self.assertEqual(eff.skip_downgrade_logins, {"keep"})
        self.assertNotIn(rc.SKIP_DOWNGRADE, eff.fallback_keys_used)

    def test_skip_downgrade_repo_list_with_no_userconfig_adds_nothing(self) -> None:
        repo = rc.parse_repo_config("## babysit_skip_downgrade_logins\n- intruder\n")
        self.assertEqual(
            rc.merge_repo_config(repo, {}).skip_downgrade_logins, frozenset()
        )

    def test_skip_downgrade_undeclared_keeps_userconfig_without_a_note(self) -> None:
        eff = rc.merge_repo_config({}, {"babysit_skip_downgrade_logins": "a,b"})
        self.assertEqual(eff.skip_downgrade_logins, {"a", "b"})
        self.assertNotIn(rc.SKIP_DOWNGRADE, eff.fallback_keys_used)

    def test_override_and_context_keys_repo_wins_else_userconfig(self) -> None:
        repo = rc.parse_repo_config(
            "## babysit_merge_method\nrebase\n\n"
            "## babysit_review_gate_context\n`ci-status`\n\n"
            "## babysit_ci_gateway_context\ngateway\n"
        )
        fallback: dict[str, str | None] = {key: "mine" for key in rc.OVERRIDE_KEYS}
        eff = rc.merge_repo_config(repo, fallback)
        self.assertEqual(
            (eff.merge_method, eff.review_gate_context, eff.ci_gateway_context),
            ("rebase", "ci-status", "gateway"),
        )
        self.assertFalse(set(rc.OVERRIDE_KEYS) & eff.fallback_keys_used)

        eff = rc.merge_repo_config({}, fallback)
        self.assertEqual(eff.review_gate_context, "mine")
        self.assertEqual(set(rc.OVERRIDE_KEYS), eff.fallback_keys_used)

    def test_trigger_phrase_is_userconfig_only(self) -> None:
        repo = rc.parse_repo_config("## babysit_review_trigger_phrase\nrepo phrase\n")
        for fallback, phrase in (
            ({"babysit_review_trigger_phrase": "mine"}, "mine"),
            ({}, None),
        ):
            with self.subTest(fallback=fallback):
                eff = rc.merge_repo_config(repo, fallback)
                self.assertEqual(eff.review_trigger_phrase, phrase)
                self.assertEqual(len(eff.notes), 1)
                self.assertIn(rc.TRIGGER_PHRASE, eff.notes[0])
                self.assertFalse(eff.fallback_keys_used)

    def test_userconfig_trigger_phrase_is_not_deprecated(self) -> None:
        eff = rc.merge_repo_config({}, {"babysit_review_trigger_phrase": "mine"})
        self.assertEqual(eff.review_trigger_phrase, "mine")
        self.assertEqual(eff.notes, ())
        self.assertFalse(eff.fallback_keys_used)

    def test_blank_userconfig_values_are_unset(self) -> None:
        eff = rc.merge_repo_config({}, {key: "" for key in rc.KEYS})
        self.assertIsNone(eff.merge_method)
        self.assertIsNone(eff.review_bot_logins)
        self.assertEqual(eff.fallback_keys_used, frozenset())


class ParseTests(unittest.TestCase):
    def test_ignores_other_sections_and_fenced_headings(self) -> None:
        layer = rc.parse_repo_config(
            "﻿# Source control\r\n\r\n## subject_pattern\r\nConventional Commits\r\n\r\n"
            "## babysit_loop_merge\r\nhuman-only\r\n\r\n"
            "## babysit_merge_method\r\n```\r\nsquash\r\n```\r\n\r\n"
            "```\r\n## babysit_merge_block_labels\r\n```\r\n"
        )
        self.assertEqual(layer, {"babysit_merge_method": "squash"})

    def test_rejects_malformed_sections(self) -> None:
        for body in (
            "## babysit_merge_method\n",
            "## babysit_merge_method\nsquash\n## babysit_merge_method\nmerge\n",
            "## Babysit_Merge_Block_Labels\n- x\n",
            "### babysit_merge_block_labels\n- x\n",
            "## babysit_merge_method\nfast-forward\n",
            "## babysit_review_settle_minutes\ninf\n",
            "## babysit_review_settle_minutes\n0.001\n",
        ):
            with self.subTest(body=body), self.assertRaises(rc.RepoConfigError):
                rc.parse_repo_config(body)


class ResolveTests(unittest.TestCase):
    def setUp(self) -> None:
        rc.reset_cache()

    def test_contents_call_has_no_ref_and_reads_no_local_file(self) -> None:
        gh = FakeGh({"o/r": _ok("## babysit_merge_method\nrebase\n")})
        with tempfile.TemporaryDirectory() as tmp:
            local = pathlib.Path(tmp, ".claude")
            local.mkdir()
            (local / "source-control.md").write_text("## babysit_merge_method\nmerge\n")
            cwd = os.getcwd()
            os.chdir(tmp)
            try:
                eff, _ = _resolve("o/r", {}, gh)
            finally:
                os.chdir(cwd)
        self.assertEqual(eff.merge_method, "rebase")
        self.assertEqual(
            gh.calls, [["api", "repos/o/r/contents/.claude/source-control.md"]]
        )

    def test_injected_repo_raises_without_calling_gh(self) -> None:
        gh = FakeGh({})
        for repo in ("o/r?ref=evil", "o/..", "o", "o/r/x"):
            with self.subTest(repo=repo), self.assertRaises(rc.RepoConfigError):
                _resolve(repo, {}, gh)
        self.assertEqual(gh.calls, [])

    def test_404_falls_back_to_userconfig(self) -> None:
        gh = FakeGh(
            {"o/r": _fail("gh: Not Found (HTTP 404)", '{"message":"Not Found"}')}
        )
        eff, _ = _resolve("o/r", {"babysit_merge_method": "merge"}, gh)
        self.assertEqual(eff.merge_method, "merge")

    def test_auto_merge_method_reads_as_unset(self) -> None:
        for method, expected in (("auto", None), ("rebase", "rebase"), (None, None)):
            with self.subTest(method=method):
                args = types.SimpleNamespace(method=method)
                fallback = rc.fallback_from_args(args)
                self.assertEqual(fallback["babysit_merge_method"], expected)

    def test_404_with_unreadable_root_is_an_error(self) -> None:
        cases = {
            "404": _fail("gh: Not Found (HTTP 404)"),
            "403": _fail("gh: Forbidden (HTTP 403)"),
            "no status": _fail("connection reset"),
        }
        for name, root in cases.items():
            rc.reset_cache()
            gh = FakeGh({"o/r": _fail("gh: Not Found (HTTP 404)")}, {"o/r": root})
            with self.subTest(name=name), self.assertRaises(rc.RepoConfigError):
                _resolve("o/r", {"babysit_merge_block_labels": "hold"}, gh)
            self.assertEqual(gh.calls[-1], ["api", "repos/o/r/contents"])

    def test_root_probe_runner_exception_is_an_error(self) -> None:
        def flaky(args: list[str]) -> subprocess.CompletedProcess[str]:
            if args[1].endswith("/contents"):
                raise RuntimeError("gh timed out")
            return _fail("gh: Not Found (HTTP 404)")

        with self.assertRaises(rc.RepoConfigError):
            rc.resolve("o/r", {}, flaky)

    def test_other_failures_are_errors(self) -> None:
        cases = {
            "5xx": _fail("gh: Server Error (HTTP 502)"),
            "403": _fail("gh: Forbidden (HTTP 403)"),
            "no status": _fail("connection reset"),
            "array": subprocess.CompletedProcess([], 0, "[]", ""),
            "too large": subprocess.CompletedProcess(
                [],
                0,
                json.dumps({"type": "file", "encoding": "none", "content": ""}),
                "",
            ),
            "bad json": subprocess.CompletedProcess([], 0, "{", ""),
            "bad parse": _ok("## babysit_merge_method\n"),
        }
        for name, response in cases.items():
            rc.reset_cache()
            with self.subTest(name=name), self.assertRaises(rc.RepoConfigError):
                _resolve(
                    "o/r", {"babysit_merge_method": "merge"}, FakeGh({"o/r": response})
                )

    def test_runner_exception_is_an_error(self) -> None:
        def boom(args: list[str]) -> subprocess.CompletedProcess[str]:
            raise RuntimeError("gh timed out")

        with self.assertRaises(rc.RepoConfigError):
            rc.resolve("o/r", {}, boom)

    def test_fetch_is_cached_per_repo(self) -> None:
        gh = FakeGh({"o/r": _ok("## babysit_merge_method\nrebase\n")})
        _resolve("o/r", {}, gh)
        _resolve("O/R", {}, gh)
        self.assertEqual(len(gh.calls), 1)

    def test_deprecation_note_once_per_key_per_process(self) -> None:
        gh = FakeGh({"o/a": _fail("(HTTP 404)"), "o/b": _fail("(HTTP 404)")})
        fallback: dict[str, str | None] = {
            "babysit_merge_method": "squash",
            "babysit_skip_downgrade_logins": "x",
        }
        _, first = _resolve("o/a", fallback, gh)
        _, second = _resolve("o/b", fallback, gh)
        _, third = _resolve("o/a", fallback, gh)
        self.assertEqual(first.count("babysit_merge_method is deprecated"), 1)
        self.assertNotIn("babysit_skip_downgrade_logins", first)
        self.assertEqual(second + third, "")

    def test_two_repos_resolve_independently(self) -> None:
        gh = FakeGh(
            {
                "o/a": _ok(
                    "## babysit_merge_method\nrebase\n\n## babysit_merge_block_labels\n- a-hold\n"
                ),
                "o/b": _ok("## babysit_merge_method\nmerge\n"),
            }
        )
        fallback: dict[str, str | None] = {"babysit_merge_block_labels": "hold"}
        a, _ = _resolve("o/a", fallback, gh)
        b, _ = _resolve("o/b", fallback, gh)
        self.assertEqual(
            (a.merge_method, a.merge_block_labels), ("rebase", {"hold", "a-hold"})
        )
        self.assertEqual((b.merge_method, b.merge_block_labels), ("merge", {"hold"}))


class LoopKeyTests(unittest.TestCase):
    """The four loop keys: the YAML first, the legacy file for a key the YAML
    lacks, then the defaults, all read from the default branch."""

    def fake(
        self, legacy: str | int | None = None, yaml: str | int | None = None
    ) -> RepoConfigFake:
        return RepoConfigFake(
            {} if legacy is None else {"o/r": legacy},
            {} if yaml is None else {"o/r": yaml},
        ).install(self)

    def test_a_remote_yaml_value_wins_over_the_legacy_file(self) -> None:
        gh = self.fake(
            legacy="## babysit_loop_merge\n\nc3-autonomous\n\n"
            "## babysit_loop_stop_mode\n\ndrain\n",
            yaml="babysit_loop_merge: human-only\nbabysit_loop_tier: autopilot\n",
        )
        loop = rc.resolve_loop_keys("o/r")
        self.assertEqual(
            dict(loop.values),
            {
                "babysit_loop_stop_mode": "drain",
                "babysit_loop_tier": "autopilot",
                "babysit_loop_merge": "human-only",
                "babysit_loop_grace_window_minutes": "30",
            },
        )
        self.assertEqual(
            dict(loop.sources),
            {
                "babysit_loop_stop_mode": rc.LEGACY_LAYER,
                "babysit_loop_tier": rc.YAML_CONFIG_PATH,
                "babysit_loop_merge": rc.YAML_CONFIG_PATH,
                "babysit_loop_grace_window_minutes": rc.DEFAULT_LAYER,
            },
        )
        self.assertTrue(loop.adopted)
        self.assertEqual(gh.calls, [YAML_CALL, LEGACY_CALL])

    def test_a_remote_repo_with_only_the_legacy_file_still_resolves(self) -> None:
        self.fake(
            legacy="# source-control configuration\n\n"
            "## pr_body_required_sections\n\n- Summary\n\n"
            "## babysit_loop_stop_mode\n\nstanding\n\n"
            "## babysit_loop_tier\n\nworker\n\n"
            "## babysit_loop_merge\n\nc2-mechanical\n\n"
            "## babysit_loop_grace_window_minutes\n\n45\n"
        )
        loop = rc.resolve_loop_keys("o/r")
        self.assertEqual(
            dict(loop.values),
            {
                "babysit_loop_stop_mode": "standing",
                "babysit_loop_tier": "worker",
                "babysit_loop_merge": "c2-mechanical",
                "babysit_loop_grace_window_minutes": "45",
            },
        )
        self.assertEqual(set(loop.sources.values()), {rc.LEGACY_LAYER})
        self.assertTrue(loop.adopted)

    def test_neither_file_yields_the_defaults(self) -> None:
        self.fake()
        loop = rc.resolve_loop_keys("o/r")
        self.assertEqual(
            dict(loop.values),
            {
                "babysit_loop_stop_mode": "standing",
                "babysit_loop_tier": "safe",
                "babysit_loop_merge": "human-only",
                "babysit_loop_grace_window_minutes": "30",
            },
        )
        self.assertEqual(set(loop.sources.values()), {rc.DEFAULT_LAYER})
        self.assertFalse(loop.adopted)

    def test_a_yaml_carrying_every_key_reads_no_legacy_file(self) -> None:
        gh = self.fake(
            legacy="## babysit_loop_merge\n\nc3-autonomous\n",
            yaml="babysit_loop_stop_mode: drain\nbabysit_loop_tier: worker\n"
            "babysit_loop_merge: c2-mechanical\n"
            "babysit_loop_grace_window_minutes: 15\n",
        )
        loop = rc.resolve_loop_keys("o/r")
        self.assertEqual(loop.values["babysit_loop_merge"], "c2-mechanical")
        self.assertEqual(loop.values["babysit_loop_grace_window_minutes"], "15")
        self.assertEqual(set(loop.sources.values()), {rc.YAML_CONFIG_PATH})
        self.assertEqual(gh.calls, [YAML_CALL])

    def test_adoption_without_a_merge_key_defaults_to_the_baseline(self) -> None:
        for legacy, yaml in (
            ("## babysit_loop_fixing\n\nworker\n", None),
            (None, "babysit_loop_tier: worker\n"),
        ):
            with self.subTest(legacy=legacy, yaml=yaml):
                loop = rc.resolve_loop_keys("o/r", self.fake(legacy, yaml))
                self.assertEqual(loop.values["babysit_loop_merge"], "c2-mechanical")
                self.assertEqual(loop.sources["babysit_loop_merge"], rc.DEFAULT_LAYER)
                self.assertTrue(loop.adopted)

    def test_a_rejected_yaml_stops_instead_of_reading_the_legacy_file(self) -> None:
        gh = self.fake(
            legacy="## babysit_loop_merge\n\nc2-mechanical\n",
            yaml="babysit_loop_merge: c2-mechanical\n",
        )
        with self.assertRaises(rc.RepoConfigError):
            rc.resolve_loop_keys("o/r", yaml_values=lambda text, keys: None)
        self.assertEqual(gh.calls, [YAML_CALL])

    def test_an_invalid_value_or_section_raises(self) -> None:
        for legacy, yaml in (
            (None, "babysit_loop_merge: c3-this-run\n"),
            (None, "babysit_loop_grace_window_minutes: 0\n"),
            ("## babysit_loop_merge\n\nc3-autonomous\n", "babysit_loop_merge:\n"),
            (None, "babysit_loop_tier:\n  - worker\n"),
            ("## babysit_loop_stop_mode\n\npause\n", None),
            ("## babysit_loop_tier\n\n", None),
            ("## babysit_loop_tier\n\nsafe\n\n## babysit_loop_tier\n\nworker\n", None),
        ):
            with self.subTest(legacy=legacy, yaml=yaml):
                self.fake(legacy, yaml)
                with self.assertRaises(rc.RepoConfigError):
                    rc.resolve_loop_keys("o/r")

    def test_a_legacy_value_the_yaml_overrides_is_not_checked(self) -> None:
        self.fake(
            legacy="## babysit_loop_tier\n\nturbo\n",
            yaml="babysit_loop_tier: safe\n",
        )
        self.assertEqual(rc.resolve_loop_keys("o/r").values["babysit_loop_tier"], "safe")

    def test_a_failed_yaml_fetch_raises(self) -> None:
        self.fake(legacy="## babysit_loop_merge\n\nc2-mechanical\n", yaml=502)
        with self.assertRaises(rc.RepoConfigError):
            rc.resolve_loop_keys("o/r")

    def test_cli_prints_values_and_layers_or_exits_one(self) -> None:
        self.fake(yaml="babysit_loop_tier: worker\n")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(rc.main(["loop-keys", "o/r"]), 0)
        report = json.loads(out.getvalue())
        self.assertEqual(report["values"]["babysit_loop_tier"], "worker")
        self.assertEqual(report["sources"]["babysit_loop_tier"], rc.YAML_CONFIG_PATH)
        self.assertTrue(report["adopted"])

        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            self.assertEqual(rc.main(["loop-keys", "o/.."]), 1)
        self.assertIn("not an owner/repo pair", err.getvalue())


if __name__ == "__main__":
    unittest.main()
