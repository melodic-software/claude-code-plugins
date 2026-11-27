#!/usr/bin/env python3

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

    def test_registry_with_invalid_utf8_leaves_every_version_unknown(self) -> None:
        self.cache("mkt/alpha/1.0.0")
        (self.root / "plugins" / "installed_plugins.json").write_bytes(
            b'{"plugins": {"a@mkt": [{"installPath": "/x/\xff"}]}}'
        )
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


class SharedLibDeepeningTest(TempTree):
    """H1 (`plugin_cache_versions`) and H2 (`claude_projects`) regression tests."""

    def test_temp_git_nested_dirs_are_not_misclassified_as_plugin_versions(self) -> None:
        cache = self.mkdir("claude/plugins/cache")
        self.mkdir("claude/plugins/cache/mkt/alpha/1.0.0")
        self.write("claude/plugins/cache/mkt/alpha/1.0.0/plugin.json", "{}")
        self.write(
            "claude/plugins/cache/temp_git_12345_abcd/.git/objects/pack/pack-1.idx",
            "pack",
        )
        registry = self.root / "claude/plugins/installed_plugins.json"
        registry.write_text(
            json.dumps(
                {
                    "version": 2,
                    "plugins": {
                        "alpha@mkt": [
                            {
                                "scope": "user",
                                "installPath": str(cache / "mkt/alpha/1.0.0"),
                            }
                        ]
                    },
                }
            ),
            encoding="utf-8",
        )
        rows = di.plugin_cache_versions(self.root / "claude", NOW)
        rel_paths = [
            Path(r["name"]).relative_to(self.root / "claude").as_posix() for r in rows
        ]
        self.assertEqual(rel_paths, ["plugins/cache/mkt/alpha/1.0.0"])

    def test_plugin_cache_versions_surface_table_and_guarded_readers(self) -> None:
        import plugin_cache_versions as pcv

        self.assertIn("remote", pcv.SURFACE_TABLE)
        self.assertEqual(
            pcv.classify_cache_relpath(
                "plugins/cache/temp_git_99/.git/objects/pack/foo"
            ).kind,
            "temp-git",
        )
        self.assertEqual(
            pcv.classify_cache_relpath("plugins/cache/mkt/plug/1.0.0/index.js").kind,
            "version",
        )

        claude = self.mkdir("custom-claude")
        self.write("custom-claude/.credentials.json", "top-secret")
        self.write("custom-claude/settings.json", "{}")
        (claude / "bad.json").write_bytes(b"\xff\xfe")
        reader = pcv.FsGuardedTextReader(claude)
        with self.assertRaises(pcv.SecretReadRefused):
            reader.read_text(".credentials.json")
        with self.assertRaises(UnicodeDecodeError):
            reader.read_text("bad.json")
        self.assertEqual(reader.read_text("settings.json"), "{}")

        mem = pcv.InMemoryTextReader(
            {
                "plugins/installed_plugins.json": "{}",
                ".credentials.json": "secret",
                "bad": b"\xff",
            }
        )
        self.assertEqual(mem.read_text("plugins/installed_plugins.json"), "{}")
        with self.assertRaises(pcv.SecretReadRefused):
            mem.read_text(".credentials.json")
        with self.assertRaises(UnicodeDecodeError):
            mem.read_text("bad")

        self.assertEqual(
            pcv.resolve_claude_dir(env={"CLAUDE_CONFIG_DIR": str(claude)}),
            claude,
        )

    def test_claude_projects_utf16_windows_hashed_pinned_and_cached_walk(self) -> None:
        import claude_projects as cp

        self.assertEqual(cp.encode_project_slug("José"), "Jos-")
        self.assertEqual(cp.encode_project_slug("a😀b"), "a--b")
        self.assertEqual(cp.encode_project_slug(r"D:\work\my.repo"), "D--work-my-repo")

        self.assertIsNone(
            cp.validated_pinned_dir_name({"CLAUDE_CODE_PROJECT_DIR_NAME": "pinned"})
        )
        self.assertEqual(
            cp.validated_pinned_dir_name(
                {
                    "CLAUDE_CONFIG_DIR": "/cfg",
                    "CLAUDE_CODE_PROJECT_DIR_NAME": "pinned_1",
                }
            ),
            "pinned_1",
        )
        for reserved in ("con", "CON", "nul", "prn", "aux", "com1", "lpt9"):
            self.assertIsNone(
                cp.validated_pinned_dir_name(
                    {
                        "CLAUDE_CONFIG_DIR": "/cfg",
                        "CLAUDE_CODE_PROJECT_DIR_NAME": reserved,
                    }
                )
            )

        d_drive = self.mkdir("d_drive")
        self.mkdir("d_drive/work/my.repo")
        self.mkdir("claude/projects")
        w_exist = self.mkdir("claude/projects/D--work-my-repo")
        w_gone = self.mkdir("claude/projects/D--work-deleted")
        resolver = cp.ProjectSlugResolver(
            fs_root=self.root / "fs",
            drive_roots={"D": d_drive},
            cwd_port=cp.NullTranscriptCwdAdapter(),
        )
        res_exist = resolver.resolve_dir(w_exist)
        res_gone = resolver.resolve_dir(w_gone)
        self.assertEqual(res_exist.status, "exists")
        self.assertEqual(res_exist.source_path, r"D:\work\my.repo")
        self.assertEqual(res_gone.status, "orphan")

        long_path = self.mkdir(f"fs/{'a' * 110}/{'b' * 110}")
        long_posix = "/" + long_path.relative_to(self.root / "fs").as_posix()
        long_enc = cp.encode_project_slug(long_posix)
        hashed_dir = self.mkdir(f"claude/projects/{long_enc[:200]}-abc123")
        cwd_resolver = cp.ProjectSlugResolver(
            fs_root=self.root / "fs",
            cwd_port=cp.InMemoryTranscriptCwdAdapter({hashed_dir: long_posix}),
        )
        res_hash = cwd_resolver.resolve_dir(hashed_dir)
        self.assertEqual(res_hash.status, "exists")
        self.assertEqual(res_hash.source_path, long_posix)

        pinned_dir = self.mkdir("claude/projects/shared-pinned")
        pinned_resolver = cp.ProjectSlugResolver(
            fs_root=self.root / "fs",
            cwd_port=cp.InMemoryTranscriptCwdAdapter(
                {pinned_dir: "/nonexistent/deleted-worktree"}
            ),
            env={
                "CLAUDE_CONFIG_DIR": str(self.root / "claude"),
                "CLAUDE_CODE_PROJECT_DIR_NAME": "shared-pinned",
            },
        )
        res_pinned = pinned_resolver.resolve_dir(pinned_dir)
        self.assertEqual(res_pinned.status, "pinned")
        self.assertEqual(res_pinned.via, "pinned")
        self.assertEqual(res_hash.via, "transcript-cwd")

        bench_fs = self.mkdir("bench_fs")
        bench_projects = self.mkdir("bench_projects")
        for i in range(100):
            self.mkdir(f"bench_fs/srv/work/org/repo-{i}")
            self.mkdir(f"bench_projects/-srv-work-org-repo-{i}")
        scandir_orig = os.scandir
        listdir_orig = os.listdir
        resolve_calls = [0]
        fs_calls = [0]

        def count_scandir(path):
            resolve_calls[0] += 1
            if str(path).startswith(str(bench_fs)):
                fs_calls[0] += 1
            return scandir_orig(path)

        def count_listdir(path):
            resolve_calls[0] += 1
            if str(path).startswith(str(bench_fs)):
                fs_calls[0] += 1
            return listdir_orig(path)

        with (
            mock.patch("os.scandir", side_effect=count_scandir),
            mock.patch("os.listdir", side_effect=count_listdir),
        ):
            bench_resolver = cp.ProjectSlugResolver(
                fs_root=bench_fs, cwd_port=cp.TranscriptReaderCwdAdapter()
            )
            resolutions = bench_resolver.resolve_all(bench_projects)
        self.assertEqual(len(resolutions), 100)
        self.assertTrue(all(r.status == "exists" for r in resolutions))
        self.assertLessEqual(
            resolve_calls[0],
            6,
            f"expected <= 6 total resolve calls, got {resolve_calls[0]}",
        )
        self.assertEqual(fs_calls[0], 4, f"expected 4 fs_root calls, got {fs_calls[0]}")

        fs_calls[0] = 0
        with (
            mock.patch("os.scandir", side_effect=count_scandir),
            mock.patch("os.listdir", side_effect=count_listdir),
        ):
            rows = di.project_transcripts(bench_projects, bench_fs)
        self.assertEqual(len(rows), 100)
        self.assertTrue(all(r["disposition"] == "KEEP" for r in rows))
        self.assertEqual(fs_calls[0], 4, f"expected 4 fs_root calls, got {fs_calls[0]}")


class DeepInventoryArchitectureTest(TempTree):
    """D5 single-pass sizing, subpath targets, read-only locks, and standalone CLI."""

    def test_single_pass_respects_mount_point_inside_categorized_directory(self) -> None:
        claude = self.mkdir("home/.claude")
        ver = self.mkdir("home/.claude/plugins/cache/mkt/plug/1.0.0")
        self.write("home/.claude/plugins/cache/mkt/plug/1.0.0/local.txt", "12345")
        mounted = self.mkdir("home/.claude/plugins/cache/mkt/plug/1.0.0/mnt")
        self.write("home/.claude/plugins/cache/mkt/plug/1.0.0/mnt/big.bin", "x" * 9999)
        self.write(
            "home/.claude/plugins/installed_plugins.json",
            json.dumps({"plugins": {"plug@mkt": [{"installPath": str(ver)}]}}),
        )
        rows = list(
            di.inventory_rows(
                claude,
                deep=True,
                home=self.root / "home",
                tmp_dir=self.root / "no-tmp",
                now=NOW,
                running=set(),
                mounts=frozenset({str(mounted)}),
            )
        )
        by_path = {r["name"]: r for r in rows}
        self.assertEqual(by_path[str(ver)]["category"], "plugin-cache-version")
        self.assertEqual(by_path[str(ver)]["disposition"], "KEEP")
        self.assertEqual(by_path[str(ver)]["size"], 5)
        self.assertEqual(by_path[str(mounted)]["category"], "not-walked")
        self.assertNotIn(str(mounted / "big.bin"), by_path)

    def test_subpath_targets_under_claude_classify_properly(self) -> None:
        claude = self.mkdir("custom-claude")
        ver = self.mkdir("custom-claude/plugins/cache/mkt/plug/1.0.0")
        self.write("custom-claude/plugins/cache/mkt/plug/1.0.0/plugin.json", "{}")
        temp_git = self.mkdir("custom-claude/plugins/cache/temp_git_1234")
        self.write("custom-claude/plugins/cache/temp_git_1234/.git/objects/pack/a", "x")
        stale_ts = NOW - (di.TMP_MIN_AGE_DAYS + 2.0) * di.DAY
        os.utime(temp_git, (stale_ts, stale_ts))
        temp_git_fresh = self.mkdir("custom-claude/plugins/cache/temp_git_fresh")
        self.write("custom-claude/plugins/cache/temp_git_fresh/.git/HEAD", "ref: refs/heads/main\n")
        fresh_ts = NOW - 1.0 * di.DAY
        os.utime(temp_git_fresh, (fresh_ts, fresh_ts))
        self.write(
            "custom-claude/plugins/installed_plugins.json",
            json.dumps({"plugins": {"plug@mkt": [{"installPath": str(ver)}]}}),
        )
        self.mkdir("custom-claude/projects/-definitely-missing-repo-xyz")

        cache_rows = {
            r["name"]: r
            for r in di.inventory_rows(
                claude / "plugins" / "cache",
                deep=True,
                home=self.root / "no-home",
                tmp_dir=self.root / "no-tmp",
                claude_dir=claude,
                now=NOW,
                running=set(),
            )
        }
        self.assertEqual(cache_rows[str(ver)]["category"], "plugin-cache-version")
        self.assertEqual(cache_rows[str(ver)]["disposition"], "KEEP")
        self.assertEqual(cache_rows[str(temp_git)]["category"], "plugin-cache-temp-git")
        self.assertEqual(cache_rows[str(temp_git)]["disposition"], "CANDIDATE")
        self.assertEqual(
            cache_rows[str(temp_git_fresh)]["category"], "plugin-cache-temp-git"
        )
        self.assertEqual(cache_rows[str(temp_git_fresh)]["disposition"], "KEEP")
        self.assertEqual(di.validate_report(cache_rows.values()), [])

        proj_dir = claude / "projects" / "-definitely-missing-repo-xyz"
        proj_rows = {
            r["name"]: r
            for r in di.inventory_rows(
                claude / "projects",
                deep=True,
                home=self.root / "no-home",
                tmp_dir=self.root / "no-tmp",
                claude_dir=claude,
                now=NOW,
                running=set(),
            )
        }
        self.assertEqual(proj_rows[str(proj_dir)]["category"], "transcript-dir")
        self.assertEqual(proj_rows[str(proj_dir)]["disposition"], "CANDIDATE")

    def test_readonly_version_lock_detection_keeps_locked_superseded_version(
        self,
    ) -> None:
        parent = self.mkdir("share/claude/versions")
        v1 = self.write("share/claude/versions/2.1.10", "old")
        self.write("share/claude/versions/2.1.20", "new")
        lock_file = self.write("share/claude/locks/2.1.10.lock", "")
        st = lock_file.lstat()

        proc = self.mkdir("proc")
        (proc / "100").mkdir()
        dev_maj = os.major(st.st_dev)
        dev_min = os.minor(st.st_dev)
        (proc / "locks").write_text(
            f"1: FLOCK  ADVISORY  WRITE 100 {dev_maj:02x}:{dev_min:02x}:{st.st_ino} 0 EOF\n",
            encoding="utf-8",
        )
        liveness = di.ProcLivenessAdapter(proc_root=proc)
        rows = by_name(di.superseded_versions([parent], liveness=liveness))
        self.assertEqual(rows["2.1.10"]["disposition"], "KEEP")
        self.assertEqual(rows["2.1.10"]["evidence"], {"lock": str(lock_file)})
        self.assertEqual(rows["2.1.20"]["disposition"], "KEEP")
        self.assertEqual(di.validate_report(rows.values()), [])

        mem_live = di.InMemoryLivenessAdapter(locked_paths={str(v1): str(lock_file)})
        rows2 = by_name(di.superseded_versions([parent], liveness=mem_live))
        self.assertEqual(rows2["2.1.10"]["disposition"], "KEEP")
        self.assertEqual(rows2["2.1.10"]["evidence"], {"lock": str(lock_file)})

    def test_standalone_cli_streams_validated_jsonl_with_zero_writes(self) -> None:
        import subprocess

        target = self.mkdir("scan-me")
        self.write("scan-me/a/hello.txt", "hello")
        env = {k: v for k, v in os.environ.items() if not k.startswith("CLAUDE_")}
        before = sorted(str(p) for p in self.root.rglob("*"))
        proc = subprocess.run(
            [
                sys.executable,
                str(SCRIPT_DIR / "deep_inventory.py"),
                "--deep",
                "--no-claude",
                str(target),
            ],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        rows = [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]
        self.assertGreaterEqual(len(rows), 3)
        self.assertEqual(di.validate_report(rows), [])
        self.assertEqual(sorted(str(p) for p in self.root.rglob("*")), before)

    def test_claude_projects_safe_exists_handles_oserror(self) -> None:
        import claude_projects as cp

        with mock.patch.object(Path, "exists", side_effect=PermissionError("denied")):
            self.assertIsNone(
                cp.ProjectSlugResolver._safe_exists(Path("/unreadable/mount"))
            )


if __name__ == "__main__":
    unittest.main()
