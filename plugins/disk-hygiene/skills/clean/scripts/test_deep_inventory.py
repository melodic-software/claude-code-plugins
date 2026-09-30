#!/usr/bin/env python3
"""Tests for the read-only deep-inventory categories and KEEP-reason validator."""

from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

import deep_inventory as di  # noqa: E402  (path set above)

NOW = 1_800_000_000.0


class TempTree(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()

    def write(self, relative: str, text: str = "x", age_days: float = 0.0) -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        self.age(path, age_days)
        return path

    def mkdir(self, relative: str, age_days: float = 0.0) -> Path:
        path = self.root / relative
        path.mkdir(parents=True, exist_ok=True)
        self.age(path, age_days)
        return path

    @staticmethod
    def age(path: Path, age_days: float) -> None:
        stamp = NOW - age_days * di.DAY
        os.utime(path, (stamp, stamp), follow_symlinks=False)


def by_name(rows: list[dict]) -> dict[str, dict]:
    return {Path(r["name"]).name: r for r in rows}


class RowSchemaTest(TempTree):
    def test_row_carries_every_column_and_measures_a_directory(self) -> None:
        directory = self.mkdir("d")
        (directory / "a.bin").write_bytes(b"12345")
        (directory / "sub").mkdir()
        (directory / "sub" / "b.bin").write_bytes(b"678")
        row = di.make_row(
            directory, producer="p", category="c", disposition="KEEP", reason="r"
        )
        self.assertEqual(set(row), set(di.ROW_COLUMNS) - {"evidence"})
        self.assertEqual((row["size"], row["ext"]), (8, ""))
        self.assertEqual(di.validate_report([row]), [])

    def test_file_row_reports_extension_and_evidence(self) -> None:
        path = self.write("f.tar.gz", "abc")
        row = di.make_row(
            path,
            producer="p",
            category="c",
            disposition="UNKNOWN",
            reason="r",
            evidence={"k": 1},
        )
        self.assertEqual(
            (row["ext"], row["size"], row["evidence"]), (".gz", 3, {"k": 1})
        )


class ValidatorTest(unittest.TestCase):
    @staticmethod
    def row(disposition: str, reason: str, evidence=None) -> dict:
        row = {c: "x" for c in di.ROW_COLUMNS if c != "evidence"}
        row.update(disposition=disposition, reason=reason)
        if evidence is not None:
            row["evidence"] = evidence
        return row

    def failures(
        self, reason: str, evidence=None, disposition: str = "KEEP"
    ) -> list[str]:
        return di.validate_report([self.row(disposition, reason, evidence)])

    def test_specific_keep_reason_passes(self) -> None:
        self.assertEqual(
            self.failures("codex 1.4 is the running binary; pid 42 executes it"), []
        )

    def test_empty_keep_reason_fails(self) -> None:
        for reason in ("", "   ", None):
            with self.subTest(reason=reason):
                self.assertEqual(len(self.failures(reason)), 1)

    def test_category_only_reasons_fail(self) -> None:
        for reason in (
            "tool-managed",
            "Tool managed.",
            "OS-owned",
            "os owned",
            "managed by mise",
            "Managed by the claude code",
            "tool-managed; OS-owned",
            "OS-owned and tool-managed",
        ):
            with self.subTest(reason=reason):
                failures = self.failures(reason)
                self.assertEqual(len(failures), 1)
                self.assertIn("category phrase", failures[0])

    def test_category_phrase_with_more_detail_passes(self) -> None:
        for reason in (
            "managed by mise; trusted-config link for /repo, target exists",
            "OS-owned socket the running X server accepts clients on",
        ):
            with self.subTest(reason=reason):
                self.assertEqual(self.failures(reason), [])

    def test_evidence_that_the_named_tool_references_the_entry_rescues_the_reason(
        self,
    ) -> None:
        evidence = {"tool": "mise", "references": "trusted-configs/abc"}
        self.assertEqual(self.failures("managed by mise", evidence), [])
        self.assertEqual(self.failures("tool-managed; managed by mise", evidence), [])

    def test_a_reason_that_names_no_tool_is_not_rescued_by_evidence(self) -> None:
        evidence = {"tool": "mise", "references": "trusted-configs/abc"}
        for reason in ("tool-managed", "OS-owned", "app owned and vendor-managed"):
            with self.subTest(reason=reason):
                self.assertEqual(len(self.failures(reason, evidence)), 1)

    def test_an_empty_reason_is_not_rescued_by_evidence(self) -> None:
        evidence = {"tool": "npm", "references": "/y"}
        for reason in ("", "   ", None):
            with self.subTest(reason=reason):
                failures = self.failures(reason, evidence)
                self.assertEqual(len(failures), 1)
                self.assertIn("empty", failures[0])

    def test_evidence_for_a_different_tool_does_not_rescue(self) -> None:
        evidence = {"tool": "npm", "references": "package.json"}
        self.assertEqual(len(self.failures("managed by mise", evidence)), 1)
        self.assertEqual(
            len(self.failures("managed by promise", {**evidence, "tool": "mise"})), 1
        )

    def test_incomplete_evidence_does_not_rescue(self) -> None:
        for evidence in (
            {"tool": "mise"},
            {"references": "x"},
            {"tool": "", "references": ""},
            "mise",
        ):
            with self.subTest(evidence=evidence):
                self.assertEqual(len(self.failures("managed by mise", evidence)), 1)

    def test_only_keep_rows_need_a_reason(self) -> None:
        for disposition in ("CANDIDATE", "UNKNOWN"):
            self.assertEqual(self.failures("", disposition=disposition), [])

    def test_bad_disposition_and_missing_columns_fail(self) -> None:
        self.assertEqual(len(self.failures("r", disposition="DELETE")), 1)
        self.assertEqual(
            len(di.validate_report([{"name": "n", "disposition": "KEEP"}])), 1
        )

    def test_every_failure_is_reported(self) -> None:
        rows = [
            self.row("KEEP", ""),
            self.row("KEEP", "OS-owned"),
            self.row("KEEP", "ok reason here"),
        ]
        self.assertEqual(len(di.validate_report(rows)), 2)


class RunningPathsTest(TempTree):
    def test_reads_exe_and_cwd_and_drops_the_deleted_suffix(self) -> None:
        proc = self.mkdir("proc")
        for pid, exe, cwd in (
            ("10", "/opt/tool/1.0/bin (deleted)", "/var/app"),
            ("11", "/opt/tool/2.0/bin", "/srv"),
        ):
            (proc / pid).mkdir()
            os.symlink(exe, proc / pid / "exe")
            os.symlink(cwd, proc / pid / "cwd")
        (proc / "self-note").mkdir()
        self.assertEqual(
            di.running_paths(proc),
            {"/opt/tool/1.0/bin", "/var/app", "/opt/tool/2.0/bin", "/srv"},
        )

    def test_open_descriptors_count_as_use(self) -> None:
        proc = self.mkdir("proc")
        fd = self.mkdir("proc/10/fd")
        os.symlink("/tmp/pytest-of-x/log", fd / "3")
        os.symlink("socket:[123]", fd / "4")
        self.assertEqual(
            di.running_paths(proc), {"/tmp/pytest-of-x/log", "socket:[123]"}
        )

    def test_unreadable_proc_root_is_none_not_empty(self) -> None:
        self.assertIsNone(di.running_paths(self.root / "absent"))
        self.assertEqual(di.running_paths(self.mkdir("proc")), set())


class SupersededVersionsTest(TempTree):
    def setUp(self) -> None:
        super().setUp()
        self.parent = self.mkdir("share/codex/versions")
        for name in ("1.9.0", "1.10.0", "1.2.0", "v1.10.1"):
            (self.parent / name).mkdir()
            (self.parent / name / "bin").write_text("x", encoding="utf-8")
        (self.parent / "current").mkdir()
        (self.parent / "notes.txt").write_text("x", encoding="utf-8")

    def test_keeps_newest_by_numeric_order_and_marks_the_rest(self) -> None:
        rows = by_name(di.superseded_versions([self.parent]))
        self.assertEqual(set(rows), {"1.9.0", "1.10.0", "1.2.0", "v1.10.1"})
        self.assertEqual(rows["v1.10.1"]["disposition"], "KEEP")
        for name in ("1.9.0", "1.10.0", "1.2.0"):
            self.assertEqual(rows[name]["disposition"], "CANDIDATE", name)
        self.assertEqual(rows["1.2.0"]["producer"], "codex")
        self.assertEqual(rows["1.2.0"]["category"], "superseded-version")

    def test_a_version_a_running_process_executes_is_kept(self) -> None:
        exe = str(self.parent / "1.9.0" / "bin")
        rows = by_name(di.superseded_versions([self.parent], {exe, "/elsewhere"}))
        self.assertEqual(rows["1.9.0"]["disposition"], "KEEP")
        self.assertEqual(rows["1.9.0"]["evidence"], {"running": exe})
        self.assertEqual(rows["1.10.0"]["disposition"], "CANDIDATE")

    def test_unread_process_table_leaves_the_superseded_unknown(self) -> None:
        rows = by_name(di.superseded_versions([self.parent], None))
        self.assertEqual(rows["v1.10.1"]["disposition"], "KEEP")
        for name in ("1.9.0", "1.10.0", "1.2.0"):
            self.assertEqual(rows[name]["disposition"], "UNKNOWN", name)
            self.assertIn("process table was not read", rows[name]["reason"])
            self.assertNotIn("no running process", rows[name]["reason"])

    def test_every_keep_passes_the_validator(self) -> None:
        exe = str(self.parent / "1.2.0")
        rows = di.superseded_versions([self.parent], {exe})
        self.assertEqual(di.validate_report(rows), [])

    def test_a_lone_version_yields_no_rows(self) -> None:
        lone = self.mkdir("share/solo")
        (lone / "3.0.0").mkdir()
        self.assertEqual(di.superseded_versions([lone, self.root / "absent"]), [])

    def test_file_versions_and_symlinks(self) -> None:
        parent = self.mkdir("share/claude/versions")
        (parent / "2.1.283").write_text("x", encoding="utf-8")
        (parent / "2.1.284").write_text("x", encoding="utf-8")
        os.symlink(parent / "2.1.284", parent / "9.9.9")
        rows = by_name(di.superseded_versions([parent]))
        self.assertEqual(set(rows), {"2.1.283", "2.1.284"})
        self.assertEqual(rows["2.1.283"]["producer"], "claude")

    def test_a_release_outranks_its_own_prerelease(self) -> None:
        parent = self.mkdir("share/tool/versions")
        for name in ("1.2.0", "1.2.0-beta", "1.1.0"):
            (parent / name).mkdir()
        rows = by_name(di.superseded_versions([parent]))
        self.assertEqual(rows["1.2.0"]["disposition"], "KEEP")
        self.assertEqual(rows["1.2.0-beta"]["disposition"], "CANDIDATE")
        self.assertEqual(rows["1.1.0"]["disposition"], "CANDIDATE")

    def test_a_symlink_beside_the_versions_keeps_the_one_it_names(self) -> None:
        alias = self.parent / "stable"
        os.symlink(self.parent / "1.2.0", alias)
        rows = by_name(di.superseded_versions([self.parent], set()))
        self.assertEqual(rows["1.2.0"]["disposition"], "KEEP")
        self.assertEqual(rows["1.2.0"]["evidence"], {"symlink": str(alias)})
        self.assertEqual(rows["1.9.0"]["disposition"], "CANDIDATE")
        self.assertIn("no symlink", rows["1.9.0"]["reason"])
        self.assertEqual(di.validate_report(rows.values()), [])

    def test_a_launcher_symlink_to_a_file_inside_a_version_keeps_it(self) -> None:
        launchers = self.mkdir("home/.local/bin")
        link = launchers / "codex"
        os.symlink(self.parent / "1.9.0" / "bin", link)
        rows = by_name(di.superseded_versions([self.parent], None, [launchers]))
        self.assertEqual(rows["1.9.0"]["disposition"], "KEEP")
        self.assertEqual(rows["1.9.0"]["evidence"], {"symlink": str(link)})
        self.assertEqual(rows["1.2.0"]["disposition"], "UNKNOWN")
        unlinked = by_name(di.superseded_versions([self.parent], set()))
        self.assertEqual(unlinked["1.9.0"]["disposition"], "CANDIDATE")


class PluginCacheTest(TempTree):
    def registry(self, install_paths: list[str], plugins: dict | None = None) -> None:
        data = plugins
        if data is None:
            data = {
                f"p{i}@m": [{"scope": "user", "installPath": p}]
                for i, p in enumerate(install_paths)
            }
        path = self.root / "plugins" / "installed_plugins.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"version": 2, "plugins": data}), encoding="utf-8")

    def cache(self, *versions: str) -> None:
        for v in versions:
            (self.mkdir(f"plugins/cache/{v}") / "plugin.json").write_text(
                "{}", encoding="utf-8"
            )

    def test_referenced_version_is_kept_with_evidence_and_the_rest_are_candidates(
        self,
    ) -> None:
        self.cache("mkt/alpha/1.0.0", "mkt/alpha/1.1.0", "mkt/beta/0.3.0")
        self.registry(
            [
                str(self.root / "plugins/cache/mkt/alpha/1.1.0"),
                str(self.root / "plugins/cache/mkt/beta/0.3.0"),
            ]
        )
        rows = di.plugin_cache_versions(self.root, NOW)
        by_path = {Path(r["name"]).relative_to(self.root).as_posix(): r for r in rows}
        old = by_path["plugins/cache/mkt/alpha/1.0.0"]
        kept = by_path["plugins/cache/mkt/alpha/1.1.0"]
        self.assertEqual(old["disposition"], "CANDIDATE")
        self.assertEqual(old["producer"], "alpha")
        self.assertEqual(kept["disposition"], "KEEP")
        self.assertEqual(kept["evidence"]["tool"], "claude-code")
        self.assertEqual(by_path["plugins/cache/mkt/beta/0.3.0"]["disposition"], "KEEP")
        self.assertEqual(di.validate_report(rows), [])

    def test_nested_install_paths_count(self) -> None:
        self.cache("mkt/alpha/1.0.0")
        self.registry(
            [],
            {
                "alpha@mkt": [
                    {
                        "scope": "project",
                        "meta": {
                            "installPath": str(
                                self.root / "plugins/cache/mkt/alpha/1.0.0"
                            )
                        },
                    }
                ]
            },
        )
        self.assertEqual(
            di.plugin_cache_versions(self.root, NOW)[0]["disposition"], "KEEP"
        )

    def test_registry_that_cannot_vouch_leaves_every_version_unknown(self) -> None:
        self.cache("mkt/alpha/1.0.0")
        for prepare in (
            lambda: None,
            lambda: (self.root / "plugins" / "installed_plugins.json").write_text(
                "{", encoding="utf-8"
            ),
            lambda: (self.root / "plugins" / "installed_plugins.json").write_text(
                "[]", encoding="utf-8"
            ),
            lambda: self.registry(["/somewhere/else/plugins/cache/mkt/alpha/1.0.0"]),
        ):
            with self.subTest():
                prepare()
                rows = di.plugin_cache_versions(self.root, NOW)
                self.assertEqual([r["disposition"] for r in rows], ["UNKNOWN"])

    def test_empty_registry_leaves_every_version_a_candidate(self) -> None:
        self.cache("mkt/alpha/1.0.0")
        self.registry([], {})
        self.assertEqual(
            di.plugin_cache_versions(self.root, NOW)[0]["disposition"], "CANDIDATE"
        )

    def test_no_cache_yields_no_rows(self) -> None:
        self.assertEqual(di.plugin_cache_versions(self.root, NOW), [])

    def orphan(self, version: str, age_days: float) -> None:
        stamp = int((NOW - age_days * di.DAY) * 1000)
        (self.root / "plugins" / "cache" / version / ".orphaned_at").write_text(
            str(stamp), encoding="utf-8"
        )

    def test_candidate_reports_marker_age_against_the_sweep_window(self) -> None:
        self.cache(
            "mkt/alpha/1.0.0", "mkt/alpha/1.1.0", "mkt/alpha/1.2.0", "mkt/alpha/1.3.0"
        )
        self.registry([str(self.root / "plugins/cache/mkt/alpha/1.3.0")])
        self.orphan("mkt/alpha/1.0.0", di.ORPHAN_SWEEP_DAYS + 6)
        self.orphan("mkt/alpha/1.1.0", 3)
        rows = by_name(di.plugin_cache_versions(self.root, NOW))
        stuck, recent, bare = rows["1.0.0"], rows["1.1.0"], rows["1.2.0"]
        self.assertEqual(stuck["evidence"]["marker_age_days"], di.ORPHAN_SWEEP_DAYS + 6)
        self.assertTrue(stuck["evidence"]["past_sweep_window"])
        self.assertIn("has not been swept", stuck["reason"])
        self.assertEqual(recent["evidence"]["marker_age_days"], 3.0)
        self.assertFalse(recent["evidence"]["past_sweep_window"])
        self.assertIn("removes it itself", recent["reason"])
        self.assertNotIn("evidence", bare)
        self.assertIn("no readable .orphaned_at marker", bare["reason"])
        self.assertEqual(rows["1.3.0"]["disposition"], "KEEP")
        self.assertEqual(di.validate_report(rows.values()), [])

    def test_unparsable_marker_is_the_same_as_none(self) -> None:
        self.cache("mkt/alpha/1.0.0")
        self.registry([], {})
        (self.root / "plugins/cache/mkt/alpha/1.0.0/.orphaned_at").write_text("soon")
        row = di.plugin_cache_versions(self.root, NOW)[0]
        self.assertNotIn("evidence", row)

    def test_a_symlinked_marker_is_not_followed(self) -> None:
        self.cache("mkt/alpha/1.0.0")
        self.registry([], {})
        outside = self.root / "outside.txt"
        outside.write_text(str(int(NOW * 1000)), encoding="utf-8")
        (self.root / "plugins/cache/mkt/alpha/1.0.0/.orphaned_at").symlink_to(outside)
        row = di.plugin_cache_versions(self.root, NOW)[0]
        self.assertNotIn("evidence", row)

    def test_an_empty_registry_means_the_removal_does_not_run(self) -> None:
        self.cache("mkt/alpha/1.0.0")
        self.registry([], {})
        self.orphan("mkt/alpha/1.0.0", 3)
        row = di.plugin_cache_versions(self.root, NOW)[0]
        self.assertEqual(row["disposition"], "CANDIDATE")
        self.assertIn("records no install", row["reason"])
        self.assertNotIn("removes it itself", row["reason"])


class TmpEntriesTest(TempTree):
    def setUp(self) -> None:
        super().setUp()
        self.tmp = self.mkdir("tmp")
        self.mkdir("tmp/pytest-of-kyle", age_days=30)
        self.mkdir("tmp/pytest-of-old", age_days=2)
        self.write("tmp/claude-1000-cache", age_days=40)
        self.mkdir("tmp/systemd-private-abc-svc", age_days=90)
        self.write("tmp/mystery.log", age_days=90)

    def rows(self, running=()) -> dict[str, dict]:
        return by_name(di.tmp_entries(self.tmp, NOW, running))

    def test_old_attributed_entries_are_candidates_by_producer(self) -> None:
        rows = self.rows()
        self.assertEqual(rows["pytest-of-kyle"]["disposition"], "CANDIDATE")
        self.assertEqual(rows["pytest-of-kyle"]["producer"], "pytest")
        self.assertEqual(rows["claude-1000-cache"]["producer"], "claude-code")
        self.assertEqual(rows["claude-1000-cache"]["category"], "tmp-producer")

    def test_recent_entry_is_kept_with_a_reason_naming_the_window(self) -> None:
        row = self.rows()["pytest-of-old"]
        self.assertEqual(row["disposition"], "KEEP")
        self.assertIn("7-day window", row["reason"])

    def test_producer_rule_reason_keeps_regardless_of_age(self) -> None:
        row = self.rows()["systemd-private-abc-svc"]
        self.assertEqual((row["disposition"], row["producer"]), ("KEEP", "systemd"))

    def test_unattributed_entry_is_unknown(self) -> None:
        row = self.rows()["mystery.log"]
        self.assertEqual((row["disposition"], row["producer"]), ("UNKNOWN", "unknown"))

    def test_a_running_process_inside_an_old_entry_keeps_it(self) -> None:
        cwd = str(self.tmp / "pytest-of-kyle" / "run-1")
        self.assertEqual(self.rows({cwd})["pytest-of-kyle"]["disposition"], "KEEP")
        # a sibling whose name only shares the prefix is not the same entry
        self.assertEqual(
            self.rows({str(self.tmp / "pytest-of-kyle-2")})["pytest-of-kyle"][
                "disposition"
            ],
            "CANDIDATE",
        )

    def test_unread_process_table_leaves_an_old_entry_unknown(self) -> None:
        rows = by_name(di.tmp_entries(self.tmp, NOW, None))
        self.assertEqual(rows["pytest-of-kyle"]["disposition"], "UNKNOWN")
        self.assertIn("process table was not read", rows["pytest-of-kyle"]["reason"])
        # an entry kept for other reasons stays kept
        self.assertEqual(rows["pytest-of-old"]["disposition"], "KEEP")
        self.assertEqual(rows["systemd-private-abc-svc"]["disposition"], "KEEP")

    def test_every_keep_passes_the_validator(self) -> None:
        self.assertEqual(di.validate_report(di.tmp_entries(self.tmp, NOW)), [])

    def test_missing_tmp_dir_is_empty(self) -> None:
        self.assertEqual(di.tmp_entries(self.root / "absent", NOW), [])


class TmpRootTest(unittest.TestCase):
    @unittest.skipUnless(os.name == "posix", "POSIX names /tmp, not $TMPDIR")
    def test_posix_covers_tmp_even_when_tmpdir_names_a_subdirectory(self) -> None:
        with mock.patch.object(tempfile, "tempdir", "/tmp/some-subdirectory"):
            self.assertEqual(di.tmp_root(), Path("/tmp").resolve())


class ProjectTranscriptsTest(TempTree):
    def setUp(self) -> None:
        super().setUp()
        self.fs = self.root / "fs"
        self.mkdir("fs/srv/work/my.repo/sub")
        self.mkdir("fs/srv/work/.config")
        self.projects = self.mkdir("claude/projects")

    def rows(self, *names: str) -> dict[str, dict]:
        for name in names:
            self.mkdir(f"claude/projects/{name}")
        return by_name(di.project_transcripts(self.projects, self.fs))

    def test_decodes_by_the_directory_tree_not_by_guessing_separators(self) -> None:
        rows = self.rows(
            "-srv-work-my-repo-sub", "-srv-work--config", "-srv-work-my-repo"
        )
        for name, source in (
            ("-srv-work-my-repo-sub", "/srv/work/my.repo/sub"),
            ("-srv-work--config", "/srv/work/.config"),
            ("-srv-work-my-repo", "/srv/work/my.repo"),
        ):
            self.assertEqual(rows[name]["disposition"], "KEEP", name)
            self.assertEqual(rows[name]["evidence"]["references"], source)
        self.assertEqual(di.validate_report(rows.values()), [])

    def test_a_gone_source_path_is_a_candidate(self) -> None:
        rows = self.rows("-tmp-harness-run-7", "-srv-work-deleted-repo")
        for name in ("-tmp-harness-run-7", "-srv-work-deleted-repo"):
            self.assertEqual(rows[name]["disposition"], "CANDIDATE", name)
            self.assertEqual(rows[name]["producer"], "claude-code")

    def test_a_prefix_only_match_is_not_a_source(self) -> None:
        rows = self.rows("-srv-work-my-repo-sub-gone")
        self.assertEqual(rows["-srv-work-my-repo-sub-gone"]["disposition"], "CANDIDATE")

    def test_undecodable_names_are_unknown(self) -> None:
        rows = self.rows("C--Users-kyle", "-" + "a" * di.PROJECT_NAME_CAP)
        self.assertEqual({r["disposition"] for r in rows.values()}, {"UNKNOWN"})

    def test_decode_project_returns_none_for_missing(self) -> None:
        self.assertIsNone(di.decode_project("-nope", self.fs))
        self.assertEqual(
            di.decode_project("-srv-work-my-repo", self.fs), "/srv/work/my.repo"
        )


class DanglingLinksTest(TempTree):
    def walk(self, target: Path) -> dict[str, dict]:
        rows = di.inventory_rows(
            target,
            deep=True,
            home=self.root / "no-home",
            tmp_dir=self.root / "no-tmp",
            now=NOW,
        )
        return by_name(list(rows))

    def test_a_walk_marks_only_links_whose_target_is_gone(self) -> None:
        home = self.mkdir("home")
        live = self.write("home/real.toml")
        trusted = self.mkdir("home/.local/state/mise/trusted-configs")
        os.symlink(live, trusted / "ok")
        os.symlink(self.root / "gone" / "mise.toml", trusted / "broken")
        os.symlink(self.root / "gone", home / "loose")
        rows = self.walk(home)
        self.assertEqual(rows["ok"]["category"], "unclassified")
        self.assertEqual(rows["broken"]["producer"], "mise")
        self.assertEqual(rows["loose"]["producer"], "unknown")
        for name in ("broken", "loose"):
            self.assertEqual(rows[name]["category"], "dangling-symlink")
            self.assertEqual(rows[name]["disposition"], "CANDIDATE")
            self.assertIn("does not exist", rows[name]["reason"])
        self.assertEqual(di.validate_report(rows.values()), [])

    def test_a_link_to_a_directory_is_not_followed(self) -> None:
        root = self.mkdir("root")
        self.write("root/a/file.txt")
        os.symlink(root, root / "a" / "loop")
        rows = di.inventory_rows(
            root,
            deep=True,
            home=self.root / "no-home",
            tmp_dir=self.root / "no-tmp",
            now=NOW,
        )
        names = [Path(r["name"]).relative_to(root).as_posix() for r in rows]
        self.assertEqual(sorted(names), [".", "a", "a/file.txt", "a/loop"])


class ReadOnlyTest(TempTree):
    def test_categories_leave_the_tree_unchanged(self) -> None:
        self.mkdir("tmp/pytest-of-x", age_days=30)
        self.mkdir("v/1.0.0")
        self.mkdir("v/2.0.0")
        self.mkdir("claude/projects/-gone")
        self.mkdir("claude/plugins/cache/m/p/1.0.0")
        os.symlink(self.root / "nowhere", self.root / "tmp" / "dangling")

        def snapshot() -> list[tuple[str, float]]:
            return sorted(
                (str(p), os.lstat(p).st_mtime)
                for p in [self.root, *self.root.rglob("*")]
            )

        before = snapshot()
        di.tmp_entries(self.root / "tmp", NOW)
        di.superseded_versions([self.root / "v"])
        di.project_transcripts(self.root / "claude" / "projects", self.root)
        di.plugin_cache_versions(self.root / "claude", NOW)
        di.dangling_row(self.root / "tmp" / "dangling")
        self.assertEqual(snapshot(), before)


if __name__ == "__main__":
    unittest.main()
