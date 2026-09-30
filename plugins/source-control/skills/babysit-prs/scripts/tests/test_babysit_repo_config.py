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
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_repo_config as rc


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


if __name__ == "__main__":
    unittest.main()
