"""Security-boundary tests for the two guarded mutation CLIs.

Every assertion here exercises a refusal that must fire BEFORE any network call,
so the tests need no gh stub: a fail-closed guard rejects on argument shape
alone. These encode the trust contract -- an allowlist that is absent fails
closed, an ambiguous head pin is refused, a thread resolve without its TOCTOU
pins is refused -- that nothing else in the suite covers.
"""

import ast
import json
import pathlib
import subprocess
import sys
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent
MERGE = SCRIPTS / "babysit_merge.py"
RESOLVE = SCRIPTS / "babysit_resolve_thread.py"


def run_raw(script, *args):
    """(returncode, stdout, stderr) — argparse reports rejections on stderr only."""
    proc = subprocess.run(
        [sys.executable, str(script), *args],
        capture_output=True,
        text=True,
    )
    return proc.returncode, proc.stdout, proc.stderr


def run(script, *args):
    code, stdout, _ = run_raw(script, *args)
    payload = {}
    if stdout.strip():
        try:
            payload = json.loads(stdout)
        except json.JSONDecodeError:
            payload = {}
    return code, payload


class MergeGuardFailsClosed(unittest.TestCase):
    def test_absent_allowlist_refuses_exit_3(self):
        code, payload = run(MERGE, "owner/repo#1")
        self.assertEqual(code, 3)
        self.assertFalse(payload.get("inScope"))
        self.assertIn("allowed-owners", payload.get("error", ""))

    def test_owner_out_of_scope_refuses_exit_3(self):
        code, payload = run(MERGE, "owner/repo#1", "--allowed-owners", "someone-else")
        self.assertEqual(code, 3)
        self.assertFalse(payload.get("inScope"))

    def test_self_logins_at_me_refuses_out_of_scope_before_resolving(self):
        # '@me' resolution is a network call; passing it with an out-of-scope
        # owner must still refuse at exit 3 (owner check precedes resolution),
        # so this runs with no gh available and must not hang or error.
        code, payload = run(
            MERGE, "owner/repo#1", "--allowed-owners", "someone-else",
            "--self-logins", "@me",
        )
        self.assertEqual(code, 3)
        self.assertFalse(payload.get("inScope"))

    def test_short_expected_head_is_usage_error_exit_2(self):
        code, payload = run(
            MERGE, "owner/repo#1", "--allowed-owners", "owner",
            "--merge", "--expected-head", "abc",
        )
        self.assertEqual(code, 2)
        self.assertIn("expected-head", payload.get("error", ""))

    def test_malformed_ref_is_usage_error_exit_2(self):
        code, _ = run(MERGE, "not-a-ref", "--allowed-owners", "owner")
        self.assertEqual(code, 2)

    def test_autopilot_tier_without_required_sets_refuses_exit_3(self):
        # The tier's fail-closed core: the umbrella flag alone, with none of its
        # three required sets, refuses before any network access.
        code, payload = run(
            MERGE, "owner/repo#1", "--allowed-owners", "owner",
            "--autopilot-merge-tier",
        )
        self.assertEqual(code, 3)
        error = payload.get("error", "")
        for flag in ("--lane-logins", "--approver-bot-logins", "--block-labels"):
            self.assertIn(flag, error)

    def test_autopilot_tier_partial_config_refuses_exit_3(self):
        # Two of three supplied still refuses, naming only the missing set.
        code, payload = run(
            MERGE, "owner/repo#1", "--allowed-owners", "owner",
            "--autopilot-merge-tier", "--lane-logins", "lane",
            "--approver-bot-logins", "bot",
        )
        self.assertEqual(code, 3)
        self.assertIn("--block-labels", payload.get("error", ""))

    def test_tier_params_without_umbrella_are_usage_error_exit_2(self):
        # The parameter sets are meaningless without the umbrella flag; supplying
        # them alone is a usage error, never a silent no-op.
        code, payload = run(
            MERGE, "owner/repo#1", "--allowed-owners", "owner",
            "--lane-logins", "lane",
        )
        self.assertEqual(code, 2)
        self.assertIn("--autopilot-merge-tier", payload.get("error", ""))


class ParsersRefuseAbbreviatedFlags(unittest.TestCase):
    """argparse prefix abbreviation is a guard-bypass surface (#1371).

    With ``allow_abbrev`` at its default ``True``, every long option on these
    parsers has an open-ended set of alternate spellings: ``--allow-unpinned-hea``
    is the same flag as ``--allow-unpinned-head``, and ``--mer`` is the same flag
    as ``--merge``. Any control anchored on a flag's exact text -- the wrapper's
    own refusal, or a consumer permission rule written against the command line
    -- is then bypassable by dropping a character. These assertions pin the
    parsers to exact spellings so that class of bypass stays closed.
    """

    def assert_unrecognized(self, script, *args):
        code, _, stderr = run_raw(script, *args)
        self.assertEqual(code, 2, f"{args!r} was accepted, not rejected")
        self.assertIn("unrecognized arguments", stderr)

    def test_unpinned_head_abbreviations_are_unrecognized(self):
        # The reported bypass: each of these reached the CLI as a valid spelling
        # of --allow-unpinned-head, so the wrapper's equality guard never saw it.
        for spelling in (
            "--allow-unpinned-hea",
            "--allow-unpinned-h",
            "--allow-unpinned",
            "--allow-unpi",
        ):
            with self.subTest(spelling=spelling):
                self.assert_unrecognized(
                    MERGE, "owner/repo#1", "--allowed-owners", "someone-else",
                    spelling,
                )

    def test_merge_abbreviations_are_unrecognized(self):
        # Not just the reported flag: --mer was an accepted spelling of --merge,
        # so a consumer allow rule that grants the wrapper "but not with --merge"
        # was bypassable by the same mechanism.
        for spelling in ("--mer", "--merg"):
            with self.subTest(spelling=spelling):
                self.assert_unrecognized(
                    MERGE, "owner/repo#1", "--allowed-owners", "someone-else",
                    spelling,
                )

    def test_allow_dependency_abbreviation_is_unrecognized(self):
        self.assert_unrecognized(
            MERGE, "owner/repo#1", "--allowed-owners", "someone-else", "--allow-d",
        )

    def test_exact_spellings_still_parse(self):
        # The fix must not cost the real flags: exact spellings still reach the
        # owner-scope refusal (exit 3), never argparse's exit 2.
        code, payload = run(
            MERGE, "owner/repo#1", "--allowed-owners", "someone-else",
            "--merge", "--allow-unpinned-head", "--allow-dependency",
        )
        self.assertEqual(code, 3)
        self.assertFalse(payload.get("inScope"))

    def test_every_lane_parser_disables_abbreviation(self):
        # Systemic, not per-flag: a new lane script that leaves allow_abbrev at
        # its default would reopen the class for its own options, so the whole
        # scripts/ directory is held to the setting rather than this one parser.
        offenders = []
        # rglob, not glob: a parser added in a subdirectory of scripts/ would
        # otherwise escape the check silently. tests/ is excluded -- these files
        # build no CLI.
        for path in sorted(p for p in SCRIPTS.rglob("*.py") if "tests" not in p.parts):
            tree = ast.parse(path.read_text(encoding="utf-8"))
            for node in ast.walk(tree):
                if not isinstance(node, ast.Call):
                    continue
                func = node.func
                name = func.attr if isinstance(func, ast.Attribute) else getattr(func, "id", "")
                if name != "ArgumentParser":
                    continue
                disabled = any(
                    kw.arg == "allow_abbrev"
                    and isinstance(kw.value, ast.Constant)
                    and kw.value.value is False
                    for kw in node.keywords
                )
                if not disabled:
                    offenders.append(f"{path.name}:{node.lineno}")
        self.assertEqual(
            offenders, [],
            "ArgumentParser(...) without allow_abbrev=False: " + ", ".join(offenders),
        )


class ResolveGuardFailsClosed(unittest.TestCase):
    def test_absent_allowlist_refuses_exit_3(self):
        code, payload = run(RESOLVE, "owner/repo#1")
        self.assertEqual(code, 3)
        self.assertFalse(payload.get("inScope"))

    def test_count_pin_without_thread_id_is_usage_error(self):
        code, payload = run(
            RESOLVE, "owner/repo#1", "--allowed-owners", "owner",
            "--expected-comment-count", "3",
        )
        self.assertEqual(code, 2)
        self.assertIn("thread-id", payload.get("error", ""))

    def test_last_updated_pin_without_thread_id_is_usage_error(self):
        code, payload = run(
            RESOLVE, "owner/repo#1", "--allowed-owners", "owner",
            "--expected-last-updated", "2026-07-17T10:00:00Z",
        )
        self.assertEqual(code, 2)
        self.assertIn("thread-id", payload.get("error", ""))

    def test_resolve_thread_id_without_pins_is_refused(self):
        code, payload = run(
            RESOLVE, "owner/repo#1", "--allowed-owners", "owner",
            "--resolve", "--thread-id", "PRRT_abc",
        )
        self.assertEqual(code, 2)
        self.assertIn("expected-comment-count", payload.get("error", ""))
        self.assertIn("expected-last-updated", payload.get("error", ""))

    def test_autonomous_bulk_resolve_without_thread_id_is_refused(self):
        # The bug this guard closes: an unattended worker's own push marks a
        # thread isOutdated, and a bulk (no --thread-id) autonomous resolve would
        # clear it with no proof the finding was addressed. Refused before any
        # network fetch -- the fix-closed contract the docs already describe.
        code, payload = run(
            RESOLVE, "owner/repo#1", "--allowed-owners", "owner",
            "--autonomous", "--resolve",
        )
        self.assertEqual(code, 2)
        self.assertIn("thread-id", payload.get("error", ""))
        self.assertIn("bulk-resolve", payload.get("error", ""))

    def test_autonomous_allow_unpinned_thread_is_refused(self):
        # There is no unpinned autonomous resolve: --allow-unpinned-thread is an
        # interactive-only override and must not open a bypass around the pins in
        # unattended mode, even with a single --thread-id.
        code, payload = run(
            RESOLVE, "owner/repo#1", "--allowed-owners", "owner",
            "--autonomous", "--resolve", "--thread-id", "PRRT_abc",
            "--allow-unpinned-thread",
        )
        self.assertEqual(code, 2)
        self.assertIn("allow-unpinned-thread", payload.get("error", ""))


if __name__ == "__main__":
    unittest.main()
