"""Review-order signals: what each reads, legible reasons, and no authority."""

from __future__ import annotations

import copy
import itertools
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import hygiene
import ranking_signals as ranking

SEC = 1_000_000_000
HOUR = 3600 * SEC
DAY = 24 * HOUR
T = 1_700_000_000 * SEC
_INODES = itertools.count(1)


def _entry(
    path: str,
    *,
    kind: str = "file",
    mtime_ns: int = T,
    stat_size: int = 10,
    inode: int | None = None,
    hints: list[dict[str, str]] | None = None,
) -> dict:
    return {
        "path": path,
        "kind": kind,
        "mtime_ns": mtime_ns,
        "stat_size": stat_size,
        "device": 1,
        "inode": inode if inode is not None else next(_INODES),
        "hints": hints or [],
    }


def build_audit_shaped_home(root: Path) -> None:
    """76 entries, one of them hinted: the audit's measured coverage (#3347 F5).

    The audit's own snapshot is not published, so this fixture rebuilds the
    shapes its worked examples describe (a build's output, one HTTP 429 body
    saved four times, a write probe sharing a second with its config, a
    numbered set with gaps, a pid-suffixed staging file, one file copied into
    two sibling folders) beside ordinary user content no signal should reach.
    """
    files: list[tuple[str, int, int]] = []
    directories: list[tuple[str, int]] = []
    for k in range(12):
        files.append((f"site-build/page-{k:02d}.html", 1000 + 10 * k, T + k * SEC // 10))
    directories.append(("site-build", T + 12 * SEC // 10))
    for k in range(1, 5):
        files.append((f"fetch-retry-{k}.json", 187, T + k * HOUR))
    files.append((".write-probe", 0, T + 5 * HOUR))
    files.append(("tool-config.json", 812, T + 5 * HOUR))
    for offset, (name, size) in enumerate(
        (("part-001.csv", 2001), ("part-002.csv", 2003), ("part-004.csv", 2007), ("part-005.csv", 2011))
    ):
        files.append((f"export/{name}", size, T + 6 * HOUR + offset * SEC))
    directories.append(("export", T + 6 * HOUR + 3 * SEC))
    files.append(("settings.json.4242.tmp", 64, T + 7 * HOUR))
    files += [
        ("backup-a/photo.jpg", 5200, T + 8 * HOUR),
        ("backup-a/notes.txt", 3001, T + 30 * DAY),
        ("backup-b/photo.jpg", 5200, T + 9 * HOUR),
        ("backup-b/readme.txt", 3002, T + 40 * DAY),
    ]
    directories += [("backup-a", T + 50 * DAY), ("backup-b", T + 60 * DAY)]
    for day in range(1, 21):
        files.append((f"notes/day-{day:02d}.md", 4000 + day, T - day * DAY))
    directories.append(("notes", T - DAY // 2))
    for k in range(10):
        files.append((f"projects/alpha/file-{k}.txt", 600 + k, T + (100 + k) * DAY))
        files.append((f"projects/beta/file-{k}.txt", 700 + k, T + (200 + k) * DAY))
    directories += [
        ("projects/alpha", T + 71 * DAY),
        ("projects/beta", T + 72 * DAY),
        ("projects", T + 70 * DAY),
    ]
    files.append((".profile", 807, T - 500 * DAY))
    for relative, size, mtime in files:
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"x" * size)
        os.utime(path, ns=(mtime, mtime))
    # Every file exists before any directory time is set: creating a child
    # moves its parent's mtime, setting a child's does not.
    for relative, mtime in directories:
        os.utime(root / relative, ns=(mtime, mtime))


AUDIT_SHAPED_RANKED = {
    **{f"site-build/page-{k:02d}.html": ranking.SIGNAL_MTIME_CLUSTER for k in range(12)},
    **{f"fetch-retry-{k}.json": ranking.SIGNAL_SIZE_COLLISION for k in range(1, 5)},
    ".write-probe": ranking.SIGNAL_MTIME_CLUSTER,
    "tool-config.json": ranking.SIGNAL_MTIME_CLUSTER,
    **{
        f"export/{name}": ranking.SIGNAL_MTIME_CLUSTER
        for name in ("part-001.csv", "part-002.csv", "part-004.csv", "part-005.csv")
    },
    "settings.json.4242.tmp": ranking.SIGNAL_HINT,
    "backup-a/photo.jpg": ranking.SIGNAL_SIZE_COLLISION,
    "backup-b/photo.jpg": ranking.SIGNAL_SIZE_COLLISION,
}


class SignalTests(unittest.TestCase):
    def test_siblings_written_within_the_window_form_one_cluster(self) -> None:
        entries = [
            _entry("out/a.o", mtime_ns=T),
            _entry("out/b.o", mtime_ns=T + SEC),
            _entry("out/c.o", mtime_ns=T + 2 * SEC + SEC // 2),
            _entry("out/late.o", mtime_ns=T + HOUR),
            _entry("other/d.o", mtime_ns=T),
        ]
        groups = ranking.mtime_cluster_groups(entries)
        self.assertEqual(1, len(groups))
        self.assertEqual(["out/a.o", "out/b.o", "out/c.o"], groups[0]["paths"])
        self.assertEqual("out", groups[0]["parent"])

    def test_a_lone_entry_is_no_cluster(self) -> None:
        self.assertEqual([], ranking.mtime_cluster_groups([_entry("x", mtime_ns=T)]))

    def test_links_and_special_entries_never_cluster(self) -> None:
        entries = [_entry("a", kind="link"), _entry("b", kind="other")]
        self.assertEqual([], ranking.mtime_cluster_groups(entries))

    def test_equal_sizes_collide_across_sibling_directories_only(self) -> None:
        entries = [
            _entry("a/x.bin", stat_size=500),
            _entry("b/y.bin", stat_size=500),
            _entry("a/deeper/z.bin", stat_size=500),
        ]
        groups = ranking.size_collision_groups(entries)
        self.assertEqual(1, len(groups))
        self.assertEqual(["a/x.bin", "b/y.bin"], groups[0]["paths"])

    def test_the_targets_own_files_collide_only_among_themselves(self) -> None:
        entries = [
            _entry("x.bin", stat_size=500),
            _entry("a/y.bin", stat_size=500),
            _entry("z.bin", stat_size=500),
        ]
        groups = ranking.size_collision_groups(entries)
        self.assertEqual(1, len(groups))
        self.assertEqual(["x.bin", "z.bin"], groups[0]["paths"])
        self.assertEqual(".", groups[0]["scope"])

    def test_empty_files_and_directories_never_collide(self) -> None:
        entries = [
            _entry("a", stat_size=0),
            _entry("b", stat_size=0),
            _entry("c", kind="directory", stat_size=4096),
            _entry("d", kind="directory", stat_size=4096),
        ]
        self.assertEqual([], ranking.size_collision_groups(entries))

    def test_hard_linked_names_of_one_object_are_not_a_collision(self) -> None:
        entries = [_entry("a", stat_size=9, inode=7), _entry("b", stat_size=9, inode=7)]
        self.assertEqual([], ranking.size_collision_groups(entries))


class AnnotateTests(unittest.TestCase):
    def test_every_ranked_entry_names_its_signal_and_unranked_has_no_position(
        self,
    ) -> None:
        entries = [
            _entry("a.tmp", hints=[{"id": "common-temp-file"}], mtime_ns=T - DAY),
            _entry("b", mtime_ns=T, stat_size=11),
            _entry("c", mtime_ns=T, stat_size=12),
            _entry("lonely", mtime_ns=T + DAY, stat_size=13),
        ]
        summary = ranking.annotate(entries)
        by_path = {entry["path"]: entry["review_rank"] for entry in entries}
        self.assertEqual(
            {"status": "unranked", "position": None, "signals": []}, by_path["lonely"]
        )
        ranked = [rank for rank in by_path.values() if rank["status"] == "ranked"]
        self.assertEqual([1, 2, 3], sorted(rank["position"] for rank in ranked))
        groups = {group["id"]: group for group in summary["groups"]}
        for rank in ranked:
            self.assertTrue(rank["signals"])
            for signal in rank["signals"]:
                self.assertIn(signal["signal"], ranking.SIGNALS)
                group = groups[signal["group"]]
                self.assertEqual(signal["signal"], group["signal"])
                self.assertTrue(group["detail"])
                self.assertGreaterEqual(group["members"], 1)
        self.assertEqual(3, summary["ranked_entries"])
        self.assertEqual(1, summary["unranked_entries"])

    def test_more_distinct_signals_rank_first(self) -> None:
        entries = [
            _entry("a/one", mtime_ns=T, stat_size=40),
            _entry("a/two", mtime_ns=T, stat_size=41),
            _entry("b/three", mtime_ns=T + DAY, stat_size=40),
        ]
        ranking.annotate(entries)
        by_path = {entry["path"]: entry["review_rank"] for entry in entries}
        self.assertEqual(1, by_path["a/one"]["position"])
        self.assertEqual(
            [ranking.SIGNAL_MTIME_CLUSTER, ranking.SIGNAL_SIZE_COLLISION],
            [signal["signal"] for signal in by_path["a/one"]["signals"]],
        )

    def test_annotate_writes_review_rank_and_nothing_else(self) -> None:
        entries = [
            {**_entry("x.tmp", hints=[{"id": "common-temp-file"}]), "preselected": True},
            _entry("y", mtime_ns=T),
            _entry("z", mtime_ns=T + DAY),
        ]
        before = copy.deepcopy(entries)
        ranking.annotate(entries)
        for original, annotated in zip(before, entries):
            self.assertEqual(original, {k: v for k, v in annotated.items() if k != "review_rank"})

    def test_summary_states_what_each_signal_reads(self) -> None:
        summary = ranking.annotate([_entry("a")])
        self.assertEqual(set(ranking.SIGNALS), set(summary["signal_reads"]))
        self.assertIn("mtime_ns", summary["signal_reads"][ranking.SIGNAL_MTIME_CLUSTER])
        self.assertIn("stat_size", summary["signal_reads"][ranking.SIGNAL_SIZE_COLLISION])


class ScanRankingTests(unittest.TestCase):
    def setUp(self) -> None:
        patcher = mock.patch.object(hygiene, "standing_policy_paths", return_value=[])
        self.addCleanup(patcher.stop)
        patcher.start()

    def scan_fixture(self, temporary: str) -> dict:
        root = Path(temporary) / "home"
        root.mkdir()
        build_audit_shaped_home(root)
        return hygiene.scan_tree(root.resolve(), hygiene.load_policy(None))

    def test_signals_read_only_recorded_fields(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "home"
            root.mkdir()
            build_audit_shaped_home(root)
            # The walk's records are the only input: with every filesystem call
            # refused while ranking runs, the rank still comes out whole.
            target = root.resolve()
            policy = hygiene.load_policy(None)
            real_annotate = ranking.annotate

            def annotate_offline(entries: list[dict]) -> dict:
                with (
                    mock.patch("os.stat", side_effect=AssertionError("stat")),
                    mock.patch("os.lstat", side_effect=AssertionError("lstat")),
                    mock.patch("os.scandir", side_effect=AssertionError("scandir")),
                    mock.patch("builtins.open", side_effect=AssertionError("open")),
                ):
                    return real_annotate(entries)

            with mock.patch.object(hygiene.ranking_signals, "annotate", annotate_offline):
                snapshot = hygiene.scan_tree(target, policy)
            self.assertEqual(25, snapshot["review_ranking"]["ranked_entries"])

    def test_coverage_before_and_after_over_the_audit_shaped_snapshot(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            snapshot = self.scan_fixture(temporary)
        entries = snapshot["entries"]
        self.assertEqual(76, len(entries))
        # Before: a discovery hint reached 1 of 76 entries, the audit's figure.
        self.assertEqual(1, sum(1 for entry in entries if entry["hints"]))
        # After: any review signal reached 25 of 76.
        summary = snapshot["review_ranking"]
        self.assertEqual(25, summary["ranked_entries"])
        self.assertEqual(51, summary["unranked_entries"])
        self.assertEqual(
            {
                ranking.SIGNAL_HINT: 1,
                ranking.SIGNAL_MTIME_CLUSTER: 18,
                ranking.SIGNAL_SIZE_COLLISION: 6,
            },
            summary["entries_by_signal"],
        )
        ranked = {
            entry["path"]: [signal["signal"] for signal in entry["review_rank"]["signals"]]
            for entry in entries
            if entry["review_rank"]["status"] == "ranked"
        }
        self.assertEqual(
            AUDIT_SHAPED_RANKED, {path: signals[0] for path, signals in ranked.items()}
        )
        self.assertTrue(all(len(signals) == 1 for signals in ranked.values()))
        for entry in entries:
            if entry["path"] not in ranked:
                self.assertEqual("unranked", entry["review_rank"]["status"])
                self.assertIsNone(entry["review_rank"]["position"])

    def test_one_group_holds_a_builds_output(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            snapshot = self.scan_fixture(temporary)
        groups = {
            group["id"]: group
            for group in snapshot["review_ranking"]["groups"]
            if group["signal"] == ranking.SIGNAL_MTIME_CLUSTER
        }
        build = [group for group in groups.values() if group["parent"] == "site-build"]
        self.assertEqual(1, len(build))
        self.assertEqual(12, build[0]["members"])
        positions = sorted(
            entry["review_rank"]["position"]
            for entry in snapshot["entries"]
            if entry["path"].startswith("site-build/")
        )
        # Members of one group are presented together.
        self.assertEqual(list(range(positions[0], positions[0] + 12)), positions)

    def test_sizes_only_scan_carries_no_ranking(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "home"
            root.mkdir()
            build_audit_shaped_home(root)
            snapshot = hygiene.scan_tree(
                root.resolve(), hygiene.load_policy(None), sizes_only=True
            )
        self.assertNotIn("review_ranking", snapshot)

    def test_rank_never_changes_what_preview_finds_eligible(self) -> None:
        plan_paths = ("settings.json.4242.tmp", "site-build/page-00.html", "notes/day-01.md")
        plan = {
            "version": 1,
            "tier": "low",
            "candidates": [
                {
                    "path": path,
                    "tier": "low",
                    "provenance": "fixture",
                    "reason": "fixture",
                    "evidence": ["fixture"],
                    "why_not_work_product": "fixture",
                    "risk": "low: fixture",
                    "owner": "unmanaged",
                }
                for path in plan_paths
            ],
        }
        with tempfile.TemporaryDirectory() as temporary:
            snapshot = self.scan_fixture(temporary)
            stripped = copy.deepcopy(snapshot)
            stripped.pop("review_ranking")
            for entry in stripped["entries"]:
                entry.pop("review_rank")
            forged = copy.deepcopy(snapshot)
            for entry in forged["entries"]:
                entry["review_rank"] = {
                    "status": "ranked",
                    "position": 1,
                    "signals": [{"signal": "forged", "group": "x"}],
                }
            results = []
            with (
                mock.patch.object(hygiene, "linux_mount_points", return_value=(set(), None)),
                mock.patch.object(hygiene, "execution_blockers", return_value=[]),
                mock.patch.object(hygiene, "tracked_blocker", return_value=None),
                mock.patch.object(
                    hygiene, "candidate_handle_state", return_value=("clear", None)
                ),
            ):
                for variant in (snapshot, stripped, forged):
                    result = hygiene.preview(variant, plan)
                    result.pop("approval_token")
                    results.append(result)
        self.assertEqual("ready-for-explicit-approval", results[0]["status"])
        self.assertEqual(
            list(plan_paths), [candidate["path"] for candidate in results[0]["candidates"]]
        )
        self.assertEqual(results[0], results[1])
        self.assertEqual(results[0], results[2])


if __name__ == "__main__":
    unittest.main()
