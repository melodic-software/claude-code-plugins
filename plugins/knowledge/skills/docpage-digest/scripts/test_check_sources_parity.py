#!/usr/bin/env python3
"""Negative-control suite for check-sources-parity.py.

PASS is not believed until the known-bad slices fail. Each case writes a small
synthetic slice (source.md, SOURCES.md, digests/) into a temp dir.

Run: python test_check_sources_parity.py
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
GATE = os.path.join(HERE, "check-sources-parity.py")

# Line numbers matter: 1-2 introduction, 3 H2 (markdown), 5 H2 (HTML tag),
# 7 H3 (HTML tag), 8-11 a fence holding a fake heading of each form.
SOURCE = (
    "# Title\n"
    "Intro text.\n"
    "## First\n"
    "Body.\n"
    '<h2 id="second">Second</h2>\n'
    "More.\n"
    '<h3 id="deep">Deep</h3>\n'
    "```md\n"
    "## not a heading\n"
    '<h2 id="fake">Fake</h2>\n'
    "```\n"
    "End.\n"
)
HEADINGS = (
    "## Headings\n\n| line | level | text |\n|---|---|---|\n"
    "| 1 | H1 | Title |\n| 3 | H2 | First |\n| 5 | H2 | Second |\n| 7 | H3 | Deep |\n"
)
MAP = (
    "\n## Digest map\n\n| file | lines |\n|---|---|\n"
    "| 01-intro.md | 1-2 |\n| 02-first.md | 3-4 |\n| 03-second.md | 5-12 |\n"
)
STATUS = "\n## Status\n\n- [x] 01-intro.md\n- [x] 02-first.md\n- [ ] 03-second.md\n"
FILES = ("01-intro.md", "02-first.md", "03-second.md")


def run(slice_dir: str):
    return subprocess.run(
        [sys.executable, GATE, slice_dir],
        capture_output=True,
        encoding="utf-8",
        check=False,
    )


class Slice(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = self.tmp.name

    def write(self, rel: str, text: str):
        path = os.path.join(self.dir, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)

    def build(self, source=SOURCE, headings=HEADINGS, map_=MAP, status=STATUS, files=FILES):
        self.write("source.md", source)
        self.write("SOURCES.md", "---\nabstract: x\n---\n\n" + headings + map_ + status)
        for name in files:
            self.write(os.path.join("digests", name), "# digest\n")
        return run(self.dir)

    def assert_fails(self, proc, fragment):
        self.assertEqual(proc.returncode, 1, proc.stdout + proc.stderr)
        self.assertIn(fragment, proc.stdout)


class TestParity(Slice):
    def test_full_parity_passes(self):
        proc = self.build()
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("source: 12 line(s), 4 heading(s) (2 H2)", proc.stdout)
        self.assertIn("PASS heading and unit parity", proc.stdout)

    def test_fenced_headings_are_not_counted(self):
        # The fence at lines 8-11 holds a `##` line and an `<h2 id>` tag; listing
        # either in the Headings table is a mismatch, so they must stay uncounted.
        proc = self.build(headings=HEADINGS + "| 9 | H2 | not a heading |\n| 10 | H2 | Fake |\n")
        self.assert_fails(proc, "SOURCES.md Headings row is no source heading: line 9 H2")
        self.assertIn("line 10 H2", proc.stdout)

    def test_tilde_fence_hides_html_heading(self):
        source = SOURCE.replace("```md", "~~~md").replace("```\n", "~~~\n")
        proc = self.build(source=source)
        self.assertEqual(proc.returncode, 0, proc.stdout)


class TestHeadingForms(Slice):
    def test_seven_hashes_and_data_id_are_not_headings(self):
        source = SOURCE.replace("End.\n", '####### seven\n<h2 class="x" data-id="y">Not</h2>\n#######\nEnd.\n')
        map_ = MAP.replace("5-12", "5-15")
        proc = self.build(source=source, map_=map_)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertIn("4 heading(s) (2 H2)", proc.stdout)


class TestHtmlHeadingOmitted(Slice):
    def test_html_h2_missing_from_headings_and_map(self):
        headings = HEADINGS.replace("| 5 | H2 | Second |\n", "")
        map_ = (
            "\n## Digest map\n\n| file | lines |\n|---|---|\n"
            "| 01-intro.md | 1-2 |\n| 02-first.md | 3-12 |\n"
        )
        status = "\n## Status\n\n- [x] 01-intro.md\n- [x] 02-first.md\n"
        proc = self.build(headings=headings, map_=map_, status=status, files=FILES[:2])
        self.assert_fails(proc, "source heading missing from SOURCES.md Headings: line 5 H2 'Second'")
        self.assertIn("no digest unit starts at line 5 (H2 'Second')", proc.stdout)

    def test_html_h2_in_headings_but_merged_in_map(self):
        map_ = "\n## Digest map\n\n| file | lines |\n|---|---|\n| 01-intro.md | 1-2 |\n| 02-first.md | 3-12 |\n"
        status = "\n## Status\n\n- [x] 01-intro.md\n- [x] 02-first.md\n"
        proc = self.build(map_=map_, status=status, files=FILES[:2])
        self.assert_fails(proc, "no digest unit starts at line 5 (H2 'Second')")
        self.assertNotIn("03-second.md", proc.stdout)


class TestUnitRanges(Slice):
    def test_gap_between_units(self):
        proc = self.build(map_=MAP.replace("3-4", "3-3"))
        self.assert_fails(proc, "digest map gap before 03-second.md: expected line 4, got 5")

    def test_overlap_between_units(self):
        proc = self.build(map_=MAP.replace("1-2", "1-3"))
        self.assert_fails(proc, "digest map overlap before 02-first.md")

    def test_map_stops_short_of_source_end(self):
        proc = self.build(map_=MAP.replace("5-12", "5-11"))
        self.assert_fails(proc, "digest map ends at line 11, source has 12 line(s)")

    def test_unit_starting_off_a_heading(self):
        map_ = MAP.replace("3-4", "3-3").replace("5-12", "4-12")
        proc = self.build(map_=map_)
        self.assert_fails(proc, "digest unit starts at line 4, which is neither line 1 nor an H2")

    def test_source_opening_on_an_h2_has_no_introduction_unit(self):
        source = "## First\nBody.\n## Second\nEnd.\n"
        headings = "## Headings\n\n| line | level |\n|---|---|\n| 1 | 2 |\n| 3 | 2 |\n"
        map_ = "\n## Digest map\n\n| file | lines |\n|---|---|\n| 01-first.md | 1-2 |\n| 02-second.md | 3-4 |\n"
        status = "\n## Status\n\n- [ ] 01-first.md\n- [ ] 02-second.md\n"
        proc = self.build(
            source=source, headings=headings, map_=map_, status=status,
            files=("01-first.md", "02-second.md"),
        )
        self.assertEqual(proc.returncode, 0, proc.stdout)


class TestCounts(Slice):
    def test_digest_file_missing_on_disk(self):
        proc = self.build(files=FILES[:2])
        self.assert_fails(proc, "03-second.md is in digest map but not in digests/")
        self.assertIn("digest map rows: 3, digest files: 2, status rows: 3", proc.stdout)

    def test_extra_digest_file_on_disk(self):
        proc = self.build(files=FILES + ("04-extra.md",))
        self.assert_fails(proc, "04-extra.md is in digests/ but not in digest map")

    def test_status_row_missing(self):
        proc = self.build(status=STATUS.replace("- [ ] 03-second.md\n", ""))
        self.assert_fails(proc, "03-second.md is in digest map but not in Status")

    def test_status_row_names_no_digest(self):
        proc = self.build(status=STATUS + "- [ ] verify everything\n")
        self.assert_fails(proc, "SOURCES.md Status row names no digest file")

    def test_duplicate_map_row(self):
        proc = self.build(map_=MAP + "| 03-second.md | 5-12 |\n")
        self.assert_fails(proc, "digest map names a digest file more than once")


class TestUnparsed(Slice):
    def test_missing_sections_fail(self):
        self.write("source.md", SOURCE)
        self.write("SOURCES.md", "# nothing here\n")
        os.makedirs(os.path.join(self.dir, "digests"))
        proc = run(self.dir)
        self.assert_fails(proc, "SOURCES.md has no '## Headings' section")
        self.assertIn("SOURCES.md has no '## Digest map' section", proc.stdout)
        self.assertIn("SOURCES.md has no '## Status' section", proc.stdout)

    def test_zero_map_rows_fail(self):
        proc = self.build(map_="\n## Digest map\n\n| file | lines |\n|---|---|\n")
        self.assert_fails(proc, "SOURCES.md Digest map parsed zero rows")

    def test_unparsable_headings_row_fails(self):
        proc = self.build(headings=HEADINGS + "| ten | H2 | x |\n")
        self.assert_fails(proc, "SOURCES.md Headings row not parsed")

    def test_unparsable_map_range_fails(self):
        proc = self.build(map_=MAP.replace("3-4", "start"))
        self.assert_fails(proc, "SOURCES.md Digest map row not parsed")


class TestCliSurface(Slice):
    def test_help_exits_zero(self):
        proc = subprocess.run([sys.executable, GATE, "--help"], capture_output=True, encoding="utf-8")
        self.assertEqual(proc.returncode, 0)
        self.assertIn("exit codes:", proc.stdout)

    def test_missing_argument_is_usage_error(self):
        proc = subprocess.run([sys.executable, GATE], capture_output=True, encoding="utf-8")
        self.assertEqual(proc.returncode, 2)

    def test_missing_source_exits_two_without_traceback(self):
        os.makedirs(os.path.join(self.dir, "digests"))
        proc = run(self.dir)
        self.assertEqual(proc.returncode, 2)
        self.assertIn("no source.md or source.txt", proc.stderr)
        self.assertNotIn("Traceback", proc.stderr)

    def test_missing_sources_md_exits_two(self):
        self.write("source.md", SOURCE)
        proc = run(self.dir)
        self.assertEqual(proc.returncode, 2)
        self.assertIn("cannot read", proc.stderr)
        self.assertNotIn("Traceback", proc.stderr)

    def test_missing_digests_dir_exits_two(self):
        self.write("source.md", SOURCE)
        self.write("SOURCES.md", "# x\n")
        proc = run(self.dir)
        self.assertEqual(proc.returncode, 2)
        self.assertIn("cannot list", proc.stderr)


if __name__ == "__main__":
    unittest.main()
