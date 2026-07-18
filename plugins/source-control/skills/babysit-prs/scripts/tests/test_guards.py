"""Security-boundary tests for the two guarded mutation CLIs.

Every assertion here exercises a refusal that must fire BEFORE any network call,
so the tests need no gh stub: a fail-closed guard rejects on argument shape
alone. These encode the trust contract -- an allowlist that is absent fails
closed, an ambiguous head pin is refused, a thread resolve without its TOCTOU
pins is refused -- that nothing else in the suite covers.
"""

import json
import pathlib
import subprocess
import sys
import unittest

SCRIPTS = pathlib.Path(__file__).resolve().parent.parent
MERGE = SCRIPTS / "babysit_merge.py"
RESOLVE = SCRIPTS / "babysit_resolve_thread.py"


def run(script, *args):
    proc = subprocess.run(
        [sys.executable, str(script), *args],
        capture_output=True,
        text=True,
    )
    payload = {}
    if proc.stdout.strip():
        try:
            payload = json.loads(proc.stdout)
        except json.JSONDecodeError:
            payload = {}
    return proc.returncode, payload


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


if __name__ == "__main__":
    unittest.main()
