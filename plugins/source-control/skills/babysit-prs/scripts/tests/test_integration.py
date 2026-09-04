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

import babysit_delta as delta
import babysit_state as state_store


def human_comment(comment_id):
    return {
        "id": comment_id,
        "author": {"login": "person", "__typename": "User"},
        "body": "a passing note",
    }


def pr_view(repo, number, merge_state="CLEAN", comments=()):
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
        "comments": list(comments),
        "labels": [],
    }


def classify(
    repo,
    number,
    merge_state="CLEAN",
    observed="2026-07-17T10:00:00+00:00",
    comments=(),
):
    return delta.classify_pr(
        pr_view(repo, number, merge_state, comments), None, [], observed
    )


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
                path,
                snapshot("queue", prs, "2026-07-17T10:00:00+00:00"),
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
                path,
                snapshot("queue", initial, "2026-07-17T10:00:00+00:00"),
                recommend_cadence=delta.recommend_cadence,
            )
            state_store.save_state(
                path,
                snapshot("queue", rescoped, "2026-07-17T10:05:00+00:00"),
                recommend_cadence=delta.recommend_cadence,
                scope_repos=["owner/repoa"],
            )
            keys = set(state_store.load_state(path)["prs"])
        self.assertIn("owner/repob#9", keys, "out-of-scope repo was clobbered")
        self.assertNotIn("owner/repoa#2", keys, "stale in-scope record survived")
        self.assertIn("owner/repoa#1", keys)


class MutationLedgerAccumulatesAcrossCycles(unittest.TestCase):
    """The ledger is the engine's memory of what it has already seen.

    `save_state` folds both the records already on disk and this cycle's
    snapshot into it, and both folds must MERGE. An overwrite at either fold
    forgets the earlier cycle's ids while every other assertion still passes,
    which is what makes a cross-cycle round trip the only place it shows.
    """

    def test_a_second_cycle_keeps_the_first_cycles_seen_ids(self):
        with tempfile.TemporaryDirectory() as td:
            state_dir = state_store.resolve_state_dir(td)
            path = state_store.state_path_for(state_dir)
            state_store.save_state(
                path,
                snapshot(
                    "queue",
                    [classify("owner/repo", 1, comments=[human_comment(11)])],
                    "2026-07-17T10:00:00+00:00",
                ),
                recommend_cadence=delta.recommend_cadence,
            )
            state_store.save_state(
                path,
                snapshot(
                    "queue",
                    [
                        classify(
                            "owner/repo",
                            1,
                            observed="2026-07-17T10:05:00+00:00",
                            comments=[human_comment(22)],
                        )
                    ],
                    "2026-07-17T10:05:00+00:00",
                ),
                recommend_cadence=delta.recommend_cadence,
            )
            entry = state_store.load_state(path)["mutation_ledger"]["owner/repo#1"]
        self.assertEqual(
            entry["seen_human_feedback_ids"],
            ["comment:11", "comment:22"],
            "the first cycle's human feedback id was dropped rather than merged",
        )


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
