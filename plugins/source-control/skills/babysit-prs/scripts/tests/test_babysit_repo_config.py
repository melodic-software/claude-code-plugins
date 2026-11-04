# test-scope: plugins/source-control/lib/parse-concern-value.sh
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
RETIRED_PATH = ".claude/source-control.md"


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
    """`responses` answers for the team YAML; any other file path fails the
    test, so a read of the retired `.claude/source-control.md` is visible."""

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
        if not args[1].endswith(f"/contents/{rc.YAML_CONFIG_PATH}"):
            raise AssertionError(f"unexpected read: {args}")
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
        repo = rc.parse_yaml_policy(
            "babysit_merge_block_labels:\n  - repo-hold\n"
            "babysit_extra_dependency_manager_logins:\n  - Dep-Bot[bot]\n"
            "babysit_approval_downgrade_logins:\n  - review-a\n  - review-b\n"
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
        repo = rc.parse_yaml_policy("babysit_merge_block_labels:\n  - wait[bot]\n")
        self.assertEqual(
            rc.merge_repo_config(repo, {}).merge_block_labels, {"wait[bot]"}
        )

    def test_repo_review_pair_is_ignored_and_userconfig_pair_passes_through(
        self,
    ) -> None:
        bots_layer: rc.RepoLayer = {rc.REVIEW_BOTS: frozenset({"github-actions"})}
        settle_layer: rc.RepoLayer = {rc.REVIEW_SETTLE: "60"}
        for layer in ({**bots_layer, **settle_layer}, bots_layer, settle_layer):
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
                with self.subTest(layer=layer, fallback=fallback):
                    eff = rc.merge_repo_config(layer, fallback)
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
        repo = rc.parse_yaml_policy(
            "babysit_skip_downgrade_logins:\n  - Keep[bot]\n  - intruder\n"
        )
        eff = rc.merge_repo_config(repo, {"babysit_skip_downgrade_logins": "keep,drop"})
        self.assertEqual(eff.skip_downgrade_logins, {"keep"})
        self.assertNotIn(rc.SKIP_DOWNGRADE, eff.fallback_keys_used)

    def test_skip_downgrade_repo_list_with_no_userconfig_adds_nothing(self) -> None:
        repo = rc.parse_yaml_policy("babysit_skip_downgrade_logins:\n  - intruder\n")
        self.assertEqual(
            rc.merge_repo_config(repo, {}).skip_downgrade_logins, frozenset()
        )

    def test_skip_downgrade_undeclared_keeps_userconfig_without_a_note(self) -> None:
        eff = rc.merge_repo_config({}, {"babysit_skip_downgrade_logins": "a,b"})
        self.assertEqual(eff.skip_downgrade_logins, {"a", "b"})
        self.assertNotIn(rc.SKIP_DOWNGRADE, eff.fallback_keys_used)

    def test_override_and_context_keys_repo_wins_else_userconfig(self) -> None:
        repo = rc.parse_yaml_policy(
            "babysit_merge_method: rebase\n"
            "babysit_review_gate_context: ci-status\n"
            "babysit_ci_gateway_context: gateway\n"
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
        repo: rc.RepoLayer = {rc.TRIGGER_PHRASE: "repo phrase"}
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


class ParseYamlPolicyTests(unittest.TestCase):
    def test_reads_only_the_policy_keys(self) -> None:
        layer = rc.parse_yaml_policy(
            "subject_pattern: Conventional Commits\n"
            "babysit_loop_merge: human-only\n"
            'babysit_review_trigger_phrase: "@bot review"\n'
            "babysit_review_bot_logins:\n  - github-actions\n"
            "babysit_review_settle_minutes: 60\n"
            "babysit_merge_method: squash\n"
        )
        self.assertEqual(layer, {"babysit_merge_method": "squash"})


class ResolveTests(unittest.TestCase):
    def setUp(self) -> None:
        rc.reset_cache()

    def test_contents_call_has_no_ref_and_reads_no_local_file(self) -> None:
        gh = FakeGh({"o/r": _ok("babysit_merge_method: rebase\n")})
        with tempfile.TemporaryDirectory() as tmp:
            local = pathlib.Path(tmp, rc.YAML_CONFIG_PATH)
            local.parent.mkdir(parents=True)
            local.write_text("babysit_merge_method: merge\n")
            cwd = os.getcwd()
            os.chdir(tmp)
            try:
                eff, _ = _resolve("o/r", {}, gh)
            finally:
                os.chdir(cwd)
        self.assertEqual(eff.merge_method, "rebase")
        self.assertEqual(gh.calls, [YAML_CALL])

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
            "bad parse": _ok("babysit_merge_method:\n"),
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
        gh = FakeGh({"o/r": _ok("babysit_merge_method: rebase\n")})
        _resolve("o/r", {}, gh)
        first = len(gh.calls)
        _resolve("O/R", {}, gh)
        self.assertEqual(len(gh.calls), first)

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
                    "babysit_merge_method: rebase\nbabysit_merge_block_labels:\n  - a-hold\n"
                ),
                "o/b": _ok("babysit_merge_method: merge\n"),
            }
        )
        fallback: dict[str, str | None] = {"babysit_merge_block_labels": "hold"}
        a, _ = _resolve("o/a", fallback, gh)
        b, _ = _resolve("o/b", fallback, gh)
        self.assertEqual(
            (a.merge_method, a.merge_block_labels), ("rebase", {"hold", "a-hold"})
        )
        self.assertEqual((b.merge_method, b.merge_block_labels), ("merge", {"hold"}))


class PolicyYamlTests(unittest.TestCase):
    """The seven repository-policy keys from the YAML alone, read from the
    default branch; the retired `.claude/source-control.md` is never read."""

    def fake(self, yaml: str | int | None = None) -> RepoConfigFake:
        return RepoConfigFake({} if yaml is None else {"o/r": yaml}).install(self)

    def resolve(self, fallback: dict[str, str | None]) -> rc.EffectiveConfig:
        with contextlib.redirect_stderr(io.StringIO()):
            return rc.resolve("o/r", fallback)

    def test_the_yaml_sets_the_policy_keys_by_itself(self) -> None:
        gh = self.fake(
            yaml="babysit_merge_method: rebase\nbabysit_review_gate_context: yaml-gate\n",
        )
        eff = self.resolve({"babysit_ci_gateway_context": "mine"})
        self.assertEqual(
            (eff.merge_method, eff.review_gate_context, eff.ci_gateway_context),
            ("rebase", "yaml-gate", "mine"),
        )
        self.assertEqual(gh.calls, [YAML_CALL])

    def test_a_repo_with_only_the_retired_file_resolves_to_userconfig(self) -> None:
        gh = self.fake()
        eff = self.resolve({"babysit_merge_method": "merge"})
        self.assertEqual(eff.merge_method, "merge")
        self.assertEqual(eff.merge_block_labels, frozenset())
        self.assertNotIn(RETIRED_PATH, json.dumps(gh.calls))

    def test_a_yaml_carrying_every_key_reads_one_file(self) -> None:
        gh = self.fake(
            yaml="babysit_merge_method: rebase\n"
            "babysit_merge_block_labels: [hold]\n"
            "babysit_extra_dependency_manager_logins: [dep-bot]\n"
            "babysit_approval_downgrade_logins: [reviewer]\n"
            "babysit_skip_downgrade_logins: [skipper]\n"
            "babysit_review_gate_context: gate\n"
            "babysit_ci_gateway_context: gateway\n",
        )
        self.assertEqual(self.resolve({}).merge_method, "rebase")
        self.assertEqual(gh.calls, [YAML_CALL])

    def test_a_yaml_hold_list_unions_with_the_userconfig_hold_list(self) -> None:
        self.fake(
            yaml="babysit_merge_block_labels:\n  - yaml-hold\n"
            "babysit_extra_dependency_manager_logins:\n  - Dep-Bot[bot]\n",
        )
        eff = self.resolve(
            {
                "babysit_merge_block_labels": "do-not-merge",
                "babysit_extra_dependency_manager_logins": "mine",
            }
        )
        self.assertEqual(eff.merge_block_labels, {"do-not-merge", "yaml-hold"})
        self.assertEqual(eff.extra_dependency_manager_logins, {"mine", "dep-bot"})

    def test_a_yaml_skip_downgrade_list_only_narrows_the_fallback_set(self) -> None:
        self.fake(yaml="babysit_skip_downgrade_logins:\n  - Keep[bot]\n  - intruder\n")
        eff = self.resolve({"babysit_skip_downgrade_logins": "keep,drop"})
        self.assertEqual(eff.skip_downgrade_logins, {"keep"})
        rc.reset_cache()
        self.assertEqual(self.resolve({}).skip_downgrade_logins, frozenset())

    def test_a_yaml_policy_string_keeps_its_trailing_slash(self) -> None:
        self.fake(
            yaml="babysit_ci_gateway_context: ci/\n"
            "babysit_review_gate_context: 'review/'\n"
            "babysit_merge_block_labels: [hold/]\n"
        )
        eff = self.resolve({})
        self.assertEqual(
            (eff.ci_gateway_context, eff.review_gate_context, eff.merge_block_labels),
            ("ci/", "review/", {"hold/"}),
        )

    def test_a_rejected_yaml_is_an_error(self) -> None:
        gh = self.fake(yaml="babysit_merge_method: squash\n")
        with self.assertRaises(rc.RepoConfigError):
            rc.resolve("o/r", {}, yaml_values=lambda text, keys: None)
        self.assertEqual(gh.calls, [YAML_CALL])

    def test_an_invalid_yaml_value_is_an_error(self) -> None:
        for yaml in (
            "babysit_merge_method: fast-forward\n",
            "babysit_merge_method:\n",
            "babysit_merge_block_labels: hold\n",
            "babysit_review_gate_context:\n  - gate\n",
        ):
            with self.subTest(yaml=yaml):
                self.fake(yaml=yaml)
                with self.assertRaises(rc.RepoConfigError):
                    self.resolve({})


class LoopKeyTests(unittest.TestCase):
    """The four loop keys: the YAML, then the defaults, read from the default
    branch; the retired `.claude/source-control.md` is never read."""

    def fake(self, yaml: str | int | None = None) -> RepoConfigFake:
        return RepoConfigFake({} if yaml is None else {"o/r": yaml}).install(self)

    def test_the_yaml_sets_the_loop_keys_by_itself(self) -> None:
        gh = self.fake(
            yaml="babysit_loop_merge: human-only\nbabysit_loop_tier: autopilot\n",
        )
        loop = rc.resolve_loop_keys("o/r")
        self.assertEqual(
            dict(loop.values),
            {
                "babysit_loop_stop_mode": "standing",
                "babysit_loop_tier": "autopilot",
                "babysit_loop_merge": "human-only",
                "babysit_loop_grace_window_minutes": "30",
            },
        )
        self.assertEqual(
            dict(loop.sources),
            {
                "babysit_loop_stop_mode": rc.DEFAULT_LAYER,
                "babysit_loop_tier": rc.YAML_CONFIG_PATH,
                "babysit_loop_merge": rc.YAML_CONFIG_PATH,
                "babysit_loop_grace_window_minutes": rc.DEFAULT_LAYER,
            },
        )
        self.assertTrue(loop.adopted)
        self.assertEqual(gh.calls, [YAML_CALL])

    def test_a_repo_with_only_the_retired_file_resolves_to_the_defaults(
        self,
    ) -> None:
        gh = self.fake()
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
        self.assertNotIn(RETIRED_PATH, json.dumps(gh.calls))

    def test_a_yaml_carrying_every_key_reads_one_file(self) -> None:
        gh = self.fake(
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
        for yaml in (
            "babysit_loop_tier: worker\n",
            # One of the nine keys outside `LOOP_KEYS` is adoption too.
            "babysit_loop_fixing: worker\n",
            "babysit_loop_trusted_internal_bot_logins:\n  - lane[bot]\n",
        ):
            with self.subTest(yaml=yaml):
                loop = rc.resolve_loop_keys("o/r", self.fake(yaml))
                self.assertEqual(loop.values["babysit_loop_merge"], "c2-mechanical")
                self.assertEqual(loop.sources["babysit_loop_merge"], rc.DEFAULT_LAYER)
                self.assertTrue(loop.adopted)

    def test_a_rejected_yaml_raises(self) -> None:
        gh = self.fake(yaml="babysit_loop_merge: c2-mechanical\n")
        with self.assertRaises(rc.RepoConfigError):
            rc.resolve_loop_keys("o/r", yaml_values=lambda text, keys: None)
        self.assertEqual(gh.calls, [YAML_CALL])

    def test_an_invalid_value_raises(self) -> None:
        for yaml in (
            "babysit_loop_merge: c3-this-run\n",
            "babysit_loop_grace_window_minutes: 0\n",
            "babysit_loop_merge:\n",
            "babysit_loop_tier:\n  - worker\n",
            "babysit_loop_stop_mode: pause\n",
        ):
            with self.subTest(yaml=yaml):
                self.fake(yaml)
                with self.assertRaises(rc.RepoConfigError):
                    rc.resolve_loop_keys("o/r")

    def test_a_failed_yaml_fetch_raises(self) -> None:
        self.fake(yaml=502)
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
