"""Cross-module integration: classify_pr -> save_state -> load_state end to end.

These exercise the decomposed modules working together (checks + feedback +
delta feeding the state store), rather than any single module in isolation.
Network-free: classify_pr consumes a fully hydrated PR view, exactly what the
discovery/hydration layer would produce.
"""

import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import babysit_delta as delta  # noqa: E402
import babysit_state as state_store  # noqa: E402


def pr_view(repo, number, merge_state="CLEAN"):
    return {
        "repo": repo,
        "number": number,
        "url": f"https://github.com/{repo}/pull/{number}",
        "title": f"PR {number}",
        "state": "OPEN",
        "isDraft": False,
        "mergeable": "MERGEABLE",
        "mergeStateStatus": merge_state,
        "reviewDecision": "APPROVED",
        "headRefOid": "a" * 40,
        "updatedAt": "2026-07-17T09:00:00Z",
        "baseRefName": "main",
        "headRefName": f"feat/{number}",
        "author": {"login": "someone", "__typename": "User"},
        "baseRepositoryArchived": False,
        "statusCheckRollup": [],
        "reviews": [],
        "comments": [],
        "labels": [],
    }


def classify(repo, number, merge_state="CLEAN", observed="2026-07-17T10:00:00+00:00"):
    return delta.classify_pr(pr_view(repo, number, merge_state), None, [], observed)


def snapshot(mode, prs, generated_at):
    return {
        "generated_at": generated_at,
        "mode": mode,
        "complete": True,
        "errors": [],
        "prs": prs,
    }


class ClassifyToStateRoundTrip(unittest.TestCase):
    def test_classify_pr_runs_across_modules(self):
        result = classify("owner/repo", 1)
        self.assertIn("classification", result)
        self.assertEqual(result["key"], "owner/repo#1")

    def test_round_trip_persists_and_reprojects_every_pr(self):
        prs = [classify("owner/repoa", 1), classify("owner/repob", 9)]
        with tempfile.TemporaryDirectory() as td:
            state_dir = state_store.resolve_state_dir(td)
            path = state_store.state_path_for(state_dir)
            state_store.save_state(
                path, snapshot("queue", prs, "2026-07-17T10:00:00+00:00"),
                recommend_cadence=delta.recommend_cadence,
            )
            loaded = state_store.load_state(path)
        self.assertEqual(len(loaded["prs"]), 2)
        self.assertIn("schema_version", loaded)
        self.assertTrue(
            all("classification" in record for record in loaded["prs"].values())
        )


class ScopedRunPreservesOutOfScope(unittest.TestCase):
    """The deployed --repo state-clobber bug: a scoped complete run must clear
    only the in-scope repository's keys, never another repo's records."""

    def test_scoped_complete_run_keeps_other_repos(self):
        initial = [
            classify("owner/repoa", 1),
            classify("owner/repoa", 2),
            classify("owner/repob", 9),
        ]
        rescoped = [classify("owner/repoa", 1, observed="2026-07-17T10:05:00+00:00")]
        with tempfile.TemporaryDirectory() as td:
            state_dir = state_store.resolve_state_dir(td)
            path = state_store.state_path_for(state_dir)
            state_store.save_state(
                path, snapshot("queue", initial, "2026-07-17T10:00:00+00:00"),
                recommend_cadence=delta.recommend_cadence,
            )
            state_store.save_state(
                path, snapshot("queue", rescoped, "2026-07-17T10:05:00+00:00"),
                recommend_cadence=delta.recommend_cadence,
                scope_repos=["owner/repoa"],
            )
            keys = set(state_store.load_state(path)["prs"])
        self.assertIn("owner/repob#9", keys, "out-of-scope repo was clobbered")
        self.assertNotIn("owner/repoa#2", keys, "stale in-scope record survived")
        self.assertIn("owner/repoa#1", keys)


class CorruptStateRecovery(unittest.TestCase):
    def test_corrupt_state_quarantines_and_cold_starts(self):
        with tempfile.TemporaryDirectory() as td:
            state_dir = state_store.resolve_state_dir(td)
            path = state_store.state_path_for(state_dir)
            path.write_text("{ this is not valid json", encoding="utf-8")
            recovered = state_store.load_state(path)
            self.assertEqual(recovered.get("prs", {}), {})
            self.assertEqual(len(list(state_dir.glob("*.corrupt*"))), 1)


if __name__ == "__main__":
    unittest.main()
