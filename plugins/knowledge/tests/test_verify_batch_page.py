#!/usr/bin/env python3
"""Suite for skills/docpage-digest/scripts/verify-batch-page.py over real temporary slices.

The standing gates and pin-manifest.py run for real. Each fixture's digest quotes its source.md,
and each verdict states the hashes hashlib computes from the fixture's bytes.

Run: python test_verify_batch_page.py
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent / "skills" / "docpage-digest" / "scripts"
CHECK = SCRIPTS / "verify-batch-page.py"
SLUG = "docs-example-com-page1-35f597d5"
LONG_AGO = "2000-01-01T00:00:00Z"
AWAITING = "unverified: awaiting-check"

SOURCE = "# Page\n\nIntro line one.\n\n## Usage\n\nRun the tool with care.\n"
INVENTORY = """---
abstract: one page
---

## Headings

| line | level | text |
|---|---|---|
| 1 | 1 | Page |
| 5 | 2 | Usage |

## Digest map

| digest file | lines |
|---|---|
| 00-intro.md | 1-4 |
| 01-usage.md | 5-7 |

## Status

- [ ] 00-intro.md
- [ ] 01-usage.md
"""


def digest(quote: str, prose: str = "Prose.") -> str:
    return (
        f"# Unit\n\n{prose}\n\n## Key claims (verbatim)\n\n**C1.** `tag`\n\n```\n{quote}\n```\n\n"
        "## Prompt snippets (exact)\n\nnone\n"
    )


def checklist(status_line: str = f"  - Verification status: {AWAITING}", tick: str = " ") -> str:
    return (
        "# Checklist\n\n## Phases\n\n- [x] Phase 3: Digest fan-out\n"
        f"- [{tick}] Phase 4: Dual verification\n  - Verifier A effort: high\n{status_line}\n"
        "- [ ] Phase 5: Interview handoff\n"
    )


def handoff(status_line: str = f"Verification status: {AWAITING}") -> str:
    return f"{status_line}\n\n# Handoff\n\n## Decisions\n\nNone.\n"


CLEAN_VERDICT = "Verdict: PASS\nFindings: high 0, medium 0, low 0\nEffective effort: high\n"


class BatchPageCase(unittest.TestCase):
    def setUp(self):
        self.base = Path(tempfile.mkdtemp(prefix="verify-batch-page-"))
        self.addCleanup(shutil.rmtree, self.base, True)
        self.root = self.base / "root"
        self.slice = self.root / ".work" / SLUG
        self.put("source.md", SOURCE)
        self.put("SOURCES.md", INVENTORY)
        self.put("digests/00-intro.md", digest("Intro line one."))
        self.put("digests/01-usage.md", digest("Run the tool with care."))
        self.put("docpage-digest-checklist.md", checklist())
        self.put("interview-handoff.md", handoff())
        self.page = {"status": "claimed", "verification": AWAITING, "slug": SLUG, "slice": str(self.slice)}

    def put(self, rel: str, text: str) -> None:
        path = self.slice / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8", newline="\n")

    def read(self, rel: str) -> str:
        return (self.slice / rel).read_text(encoding="utf-8")

    def pin(self) -> None:
        subprocess.run([sys.executable, str(SCRIPTS / "pin-manifest.py"), str(self.slice)], check=True, capture_output=True)

    def hash_block(self) -> str:
        frozen = [self.slice / "SOURCES.md", *self.slice.glob("source.*"), *(self.slice / "digests").glob("*.md")]
        return "\n".join(f"{p.name} {hashlib.sha256(p.read_bytes()).hexdigest()}" for p in frozen) + "\n"

    def verdict(self, arm: str, header: str = CLEAN_VERDICT, name: str = "r1-2026-11-03") -> Path:
        rel = f"verification/verifier-{arm}-{name}.md"
        self.put(rel, header + "\n## Hashes audited\n\n" + self.hash_block())
        return self.slice / rel

    def seal(self) -> None:
        """Pin the tree and write both arms' clean verdicts, as a passing run leaves them."""
        self.pin()
        self.verdict("a")
        self.verdict("b")

    def check(self, *, started_at: str = LONG_AGO, slice_arg=None, root=None, page=None):
        result = self.base / "page.json"
        result.write_text(json.dumps(self.page if page is None else page), encoding="utf-8")
        return subprocess.run(
            [
                sys.executable, str(CHECK),
                "--result", str(result),
                "--slice", str(self.slice if slice_arg is None else slice_arg),
                "--root", str(self.root if root is None else root),
                "--started-at", started_at,
            ],
            capture_output=True, text=True, check=False,
        )

    def assert_ends(self, proc, status: str) -> None:
        """The printed status, the exit code and both files on disk all say this status."""
        self.assertEqual(proc.stdout.strip(), status, proc.stderr)
        self.assertEqual(proc.returncode, 0 if status == "verified" else 1)
        self.assertIn(f"  - Verification status: {status}\n", self.read("docpage-digest-checklist.md"))
        self.assertEqual(self.read("docpage-digest-checklist.md").count("erification status"), 1)
        self.assertEqual(self.read("interview-handoff.md").split("\n")[0], f"Verification status: {status}")
        self.assertEqual(self.read("interview-handoff.md").count("erification status"), 1)
        tick = "x" if status == "verified" else " "
        self.assertIn(f"- [{tick}] Phase 4: Dual verification\n", self.read("docpage-digest-checklist.md"))


class TestPasses(BatchPageCase):
    def test_a_real_slice_ends_verified_on_both_files_with_phase_4_ticked(self):
        self.seal()
        self.assert_ends(self.check(), "verified")

    def test_pass_with_findings_with_no_high_is_a_pass(self):
        self.pin()
        self.verdict("a", "Verdict: PASS-WITH-FINDINGS\nFinding counts: high 0, medium 1, low 1\nFinding: medium: x\n")
        self.verdict("b")
        self.assert_ends(self.check(), "verified")

    def test_a_template_line_wrapped_in_its_parenthesis_counts_and_is_replaced(self):
        wrapped = f"  - Verification status (`verified` or `failed`; the handoff's\n    first line reads it): {AWAITING}"
        self.put("docpage-digest-checklist.md", checklist(wrapped))
        self.seal()
        self.assert_ends(self.check(), "verified")
        self.assertNotIn("first line reads it", self.read("docpage-digest-checklist.md"))

    def test_the_awaiting_status_in_backticks_or_with_a_period_counts(self):
        self.put("docpage-digest-checklist.md", checklist(f"  - Verification status: `{AWAITING}`"))
        self.put("interview-handoff.md", handoff(f"Verification status: {AWAITING}."))
        self.seal()
        self.assert_ends(self.check(), "verified")

    def test_other_checklist_lines_survive_the_rewrite(self):
        self.seal()
        self.check()
        for kept in ["- [x] Phase 3: Digest fan-out\n", "  - Verifier A effort: high\n", "- [ ] Phase 5: Interview handoff\n"]:
            self.assertIn(kept, self.read("docpage-digest-checklist.md"))
        self.assertIn("## Decisions", self.read("interview-handoff.md"))


class TestVerdictFiles(BatchPageCase):
    def test_a_missing_verdict_file(self):
        for arm in ("a", "b"):
            with self.subTest(arm=arm):
                self.seal()
                for path in (self.slice / "verification").glob(f"verifier-{arm}-*.md"):
                    path.unlink()
                self.put("docpage-digest-checklist.md", checklist())
                self.put("interview-handoff.md", handoff())
                self.assert_ends(self.check(), f"unverified: verifier-{arm}-missing")

    def test_a_verdict_older_than_the_pin_is_stale(self):
        self.seal()
        os.utime(self.slice / "verification" / "verifier-a-r1-2026-11-03.md", (1_000_000_000, 1_000_000_000))
        self.assert_ends(self.check(), "unverified: verifier-a-stale")

    def test_a_verdict_not_stating_a_pinned_hash_is_stale(self):
        self.seal()
        self.put("verification/verifier-b-r1-2026-11-03.md", CLEAN_VERDICT + "\nnull hashes\n")
        self.assert_ends(self.check(), "unverified: verifier-b-stale")

    def test_an_earlier_runs_failing_verdict_beside_this_runs_pass_is_ignored(self):
        self.seal()
        old = self.verdict("a", "Verdict: FAIL\nFindings: high 1, medium 0, low 0\n", "r1-2026-10-01")
        os.utime(old, (1_000_000_000, 1_000_000_000))
        self.assert_ends(self.check(), "verified")

    def test_a_retry_cannot_hide_this_runs_fail_behind_a_later_pass(self):
        self.seal()
        self.verdict("a", "Verdict: FAIL\nFindings: high 1, medium 0, low 0\n", "r1-2026-11-03-2")
        self.assert_ends(self.check(), "unverified: verifier-a-fail")

    def test_this_runs_fail_with_no_hashes_is_not_skipped_behind_a_hashed_pass(self):
        self.seal()
        self.put("verification/verifier-a-r1-2026-11-03-2.md", "Verdict: FAIL\nFindings: high 1, medium 0, low 0\n")
        self.assert_ends(self.check(), "unverified: verifier-a-fail")

    def test_a_high_finding_in_any_shape_with_a_pass_verdict(self):
        shapes = [
            "Verdict: PASS\nFindings: high 1, medium 0, low 0\n",
            f"{CLEAN_VERDICT}Finding: high: a fabricated claim\n",
            f"{CLEAN_VERDICT}| A-1 | high | open |\n",
            f"{CLEAN_VERDICT}severity: HIGH\n",
            f"{CLEAN_VERDICT}- [high] a dropped section\n",
            f"{CLEAN_VERDICT}**High:** a contradicted claim\n",
        ]
        for header in shapes:
            with self.subTest(header=header):
                self.seal()
                self.verdict("a", header)
                self.put("docpage-digest-checklist.md", checklist())
                self.put("interview-handoff.md", handoff())
                self.assert_ends(self.check(), "unverified: verifier-a-high")

    def test_prose_about_high_is_not_a_finding(self):
        self.pin()
        self.verdict("a", f"{CLEAN_VERDICT}No high finding is open. High-level summary follows.\nreasoning effort: high\n1. Replayed the checks.\n")
        self.verdict("b")
        self.assert_ends(self.check(), "verified")

    def test_verdict_values_and_malformed_files(self):
        cases = [
            ("Verdict: FAIL\nFindings: high 0, medium 0, low 0\n", "fail"),
            ("Verdict: BLOCKED\nFindings: high 0, medium 0, low 0\n", "blocked"),
            ("Findings: high 0, medium 0, low 0\n", "malformed"),
            ("Verdict: PASS\n", "malformed"),
            ("Verdict: PASS\nVerdict: PASS\nFindings: high 0, medium 0, low 0\n", "malformed"),
            ("Verdict: PASS\nFindings: high 0, medium 1, low 0\n", "malformed"),
            ("Verdict: PASS-WITH-FINDINGS\nFindings: high 0, medium 0, low 0\n", "malformed"),
            ("Verdict: maybe\nFindings: high 0, medium 0, low 0\n", "malformed"),
        ]
        for header, state in cases:
            with self.subTest(header=header):
                self.seal()
                self.verdict("b", header)
                self.put("docpage-digest-checklist.md", checklist())
                self.put("interview-handoff.md", handoff())
                self.assert_ends(self.check(), f"unverified: verifier-b-{state}")


class TestPin(BatchPageCase):
    def test_no_manifest(self):
        self.verdict("a")
        self.verdict("b")
        self.assert_ends(self.check(), "unverified: pin-missing")

    def test_bytes_that_moved_since_the_pin(self):
        self.seal()
        self.put("digests/00-intro.md", digest("Intro line one.", "Edited after the pin."))
        self.assert_ends(self.check(), "unverified: pin-moved")

    def test_a_pin_older_than_this_run(self):
        self.seal()
        self.assert_ends(self.check(started_at="2999-01-01T00:00:00Z"), "unverified: pin-before-run")


class TestGates(BatchPageCase):
    def test_each_failing_gate_is_rerun_and_named(self):
        cases = [
            ("check-fences-exact", "digests/00-intro.md", digest("A fabricated quote.")),
            ("check-prose-terms", "digests/00-intro.md", digest("Intro line one.", "See unit 03 for more.")),
            ("check-sources-parity", "SOURCES.md", INVENTORY.replace("- [ ] 01-usage.md\n", "")),
            (
                "check-snippets",
                "digests/01-usage.md",
                digest("Run the tool with care.").replace("none\n", "```\nA fabricated snippet.\n```\n"),
            ),
        ]
        for gate, rel, text in cases:
            with self.subTest(gate=gate):
                good = self.read(rel)
                self.put(rel, text)
                self.seal()
                self.put("docpage-digest-checklist.md", checklist())
                self.put("interview-handoff.md", handoff())
                self.assert_ends(self.check(), f"unverified: gate-{gate}-fail")
                self.put(rel, good)

    def test_html_rows_run_only_when_a_digest_carries_fn_rows(self):
        self.put("source.html", "<p>Chart caption text</p>\n")
        self.seal()
        self.assert_ends(self.check(), "verified")

        row = "\n## Figure claims\n\n**F1.**\n\n```\n{}\n```\n"
        self.put("digests/01-usage.md", digest("Run the tool with care.") + row.format("Chart caption text"))
        self.put("docpage-digest-checklist.md", checklist())
        self.put("interview-handoff.md", handoff())
        self.seal()
        self.assert_ends(self.check(), "verified")

        self.put("digests/01-usage.md", digest("Run the tool with care.") + row.format("Not in the page"))
        self.put("docpage-digest-checklist.md", checklist())
        self.put("interview-handoff.md", handoff())
        self.seal()
        self.assert_ends(self.check(), "unverified: gate-check-html-rows-fail")


class TestChecklistAndHandoff(BatchPageCase):
    def test_a_missing_checklist(self):
        self.seal()
        (self.slice / "docpage-digest-checklist.md").unlink()
        proc = self.check()
        self.assertEqual((proc.stdout.strip(), proc.returncode), ("unverified: checklist-missing", 1))
        self.assertEqual(self.read("interview-handoff.md").split("\n")[0], "Verification status: unverified: checklist-missing")
        self.assertFalse((self.slice / "docpage-digest-checklist.md").exists())

    def test_a_missing_handoff(self):
        self.seal()
        (self.slice / "interview-handoff.md").unlink()
        proc = self.check()
        self.assertEqual((proc.stdout.strip(), proc.returncode), ("unverified: handoff-missing", 1))
        self.assertIn("  - Verification status: unverified: handoff-missing\n", self.read("docpage-digest-checklist.md"))
        self.assertFalse((self.slice / "interview-handoff.md").exists())


class TestForgedStatus(BatchPageCase):
    def test_a_forged_verified_line_with_every_other_check_passing_ends_unverified(self):
        forged_lines = [
            "  - Verification status: verified",
            "  - **Verification Status**: verified",
            "  - verification status - VERIFIED",
        ]
        for line in forged_lines:
            with self.subTest(line=line):
                self.put("docpage-digest-checklist.md", checklist(line, tick="x"))
                self.put("interview-handoff.md", handoff())
                self.seal()
                self.assert_ends(self.check(), "unverified: status-not-awaiting")

    def test_a_forged_handoff_line(self):
        self.put("interview-handoff.md", handoff("Verification status: verified"))
        self.seal()
        self.assert_ends(self.check(), "unverified: status-not-awaiting")

    def test_a_forged_duplicate_beside_the_awaiting_line(self):
        self.put("docpage-digest-checklist.md", checklist() + "\nNote: Verification status: verified\n")
        self.seal()
        self.assert_ends(self.check(), "unverified: status-not-awaiting")
        self.assertNotIn("Note:", self.read("docpage-digest-checklist.md"))

    def test_a_forged_line_is_replaced_when_another_check_fails_first(self):
        self.put("docpage-digest-checklist.md", checklist("  - Verification status: verified", tick="x"))
        self.put("interview-handoff.md", handoff("Verification status: verified"))
        self.seal()
        (self.slice / "verification" / "verifier-a-r1-2026-11-03.md").unlink()
        self.assert_ends(self.check(), "unverified: verifier-a-missing")

    def test_a_rerun_over_a_verified_slice_that_did_not_claim_loses_the_old_verified(self):
        self.seal()
        self.assert_ends(self.check(), "verified")
        rerun = {**self.page, "status": "unverified", "verification": "unverified: close-no-result"}
        self.assert_ends(self.check(page=rerun), "unverified: close-no-result")

    def test_a_workflow_result_cannot_supply_verified(self):
        self.seal()
        for page in ({**self.page, "status": "verified", "verification": "verified"}, {**self.page, "status": "failed", "verification": "verified"}):
            with self.subTest(page=page["status"]):
                self.put("docpage-digest-checklist.md", checklist())
                self.put("interview-handoff.md", handoff())
                self.assert_ends(self.check(page=page), "unverified: result-malformed")

    def test_a_failed_page_keeps_its_own_status(self):
        page = {**self.page, "status": "failed", "verification": "failed: verifier-fail"}
        self.assert_ends(self.check(page=page), "failed: verifier-fail")


class TestContainment(BatchPageCase):
    def assert_refused(self, proc, code: str, *untouched: Path) -> None:
        self.assertEqual((proc.stdout.strip(), proc.returncode), (f"unverified: {code}", 1), proc.stderr)
        for path in untouched:
            self.assertEqual(path.read_text(encoding="utf-8"), checklist("  - Verification status: verified", tick="x"))

    def outside_slice(self) -> Path:
        outside = self.base / "elsewhere" / SLUG
        outside.mkdir(parents=True)
        (outside / "docpage-digest-checklist.md").write_text(checklist("  - Verification status: verified", tick="x"), encoding="utf-8")
        return outside

    def test_a_slice_outside_the_root_is_refused_and_not_written(self):
        outside = self.outside_slice()
        page = {**self.page, "slice": str(outside)}
        self.assert_refused(self.check(slice_arg=outside, page=page), "slice-outside-root", outside / "docpage-digest-checklist.md")

    def test_a_parent_segment_out_of_the_root_is_refused(self):
        outside = self.outside_slice()
        sneaky = f"{self.root}/.work/../../elsewhere/{SLUG}"
        page = {**self.page, "slice": sneaky}
        self.assert_refused(self.check(slice_arg=sneaky, page=page), "slice-outside-root", outside / "docpage-digest-checklist.md")

    def test_a_slice_that_is_a_symlink_leaving_the_root_is_refused(self):
        outside = self.outside_slice()
        shutil.rmtree(self.slice)
        self.slice.symlink_to(outside, target_is_directory=True)
        self.assert_refused(self.check(), "slice-symlink", outside / "docpage-digest-checklist.md")

    def test_a_work_directory_that_is_a_symlink_leaving_the_root_is_refused(self):
        outside = self.outside_slice()
        shutil.rmtree(self.root / ".work")
        (self.root / ".work").symlink_to(outside.parent, target_is_directory=True)
        self.assert_refused(self.check(), "slice-outside-root", outside / "docpage-digest-checklist.md")

    def test_a_symlink_inside_the_slice_leaving_the_root_ends_unverified(self):
        secret = self.base / "secret.md"
        secret.write_text(digest("Intro line one."), encoding="utf-8")
        self.seal()
        (self.slice / "digests" / "00-intro.md").unlink()
        (self.slice / "digests" / "00-intro.md").symlink_to(secret)
        self.assert_ends(self.check(), "unverified: symlink-leaves-root")
        self.assertEqual(secret.read_text(encoding="utf-8"), digest("Intro line one."))

    def test_a_status_file_linked_out_of_the_root_is_replaced_and_its_target_left_alone(self):
        target = self.base / "linked.md"
        target.write_text(checklist("  - Verification status: verified", tick="x"), encoding="utf-8")
        self.seal()
        path = self.slice / "docpage-digest-checklist.md"
        path.unlink()
        path.symlink_to(target)
        proc = self.check()
        self.assertEqual(proc.stdout.strip(), "unverified: symlink-leaves-root")
        self.assertFalse(path.is_symlink())
        self.assertEqual(path.read_text(encoding="utf-8"), "Verification status: unverified: symlink-leaves-root\n")
        self.assertEqual(target.read_text(encoding="utf-8"), checklist("  - Verification status: verified", tick="x"))

    def test_a_symlink_that_stays_inside_the_root_is_not_refused(self):
        self.put("scratch/note.txt", "kept\n")
        (self.slice / "scratch" / "link.txt").symlink_to(self.slice / "scratch" / "note.txt")
        self.seal()
        self.assert_ends(self.check(), "verified")

    def test_a_result_for_another_slice_is_refused_and_writes_nothing(self):
        self.seal()
        page = {**self.page, "slice": str(self.root / ".work" / "docs-example-com-other-0123abcd")}
        proc = self.check(page=page)
        self.assertEqual((proc.stdout.strip(), proc.returncode), ("unverified: slice-mismatch", 1))
        self.assertEqual(self.read("docpage-digest-checklist.md"), checklist())

    def test_a_slice_directory_that_does_not_exist_is_reported(self):
        shutil.rmtree(self.slice)
        proc = self.check()
        self.assertEqual((proc.stdout.strip(), proc.returncode), ("unverified: slice-missing", 1))


class TestUsage(BatchPageCase):
    def assert_usage(self, proc) -> None:
        self.assertEqual(proc.returncode, 2, proc.stdout)
        self.assertEqual(proc.stdout, "")
        self.assertEqual(self.read("docpage-digest-checklist.md"), checklist())
        self.assertEqual(self.read("interview-handoff.md"), handoff())

    def test_a_bad_start_time(self):
        self.assert_usage(self.check(started_at="yesterday"))

    def test_a_root_that_is_not_a_directory(self):
        self.assert_usage(self.check(root=self.base / "absent"))

    def test_a_result_that_is_not_one_page(self):
        self.assert_usage(self.check(page=[self.page]))

    def test_a_result_that_is_not_json(self):
        result = self.base / "bad.json"
        result.write_text("{", encoding="utf-8")
        proc = subprocess.run(
            [sys.executable, str(CHECK), "--result", str(result), "--slice", str(self.slice), "--root", str(self.root), "--started-at", LONG_AGO],
            capture_output=True, text=True, check=False,
        )
        self.assert_usage(proc)

    def test_missing_arguments(self):
        proc = subprocess.run([sys.executable, str(CHECK), "--slice", str(self.slice)], capture_output=True, text=True, check=False)
        self.assert_usage(proc)


if __name__ == "__main__":
    unittest.main()
