#!/usr/bin/env python3
"""Tests for extract_nodes.py. Stdlib unittest; run: python test_extract_nodes.py"""

import contextlib
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "extract_nodes.py")


def run_cli(args, expect_code=0):
    proc = subprocess.run([sys.executable, SCRIPT] + args, capture_output=True)
    if proc.returncode != expect_code:
        raise AssertionError(
            f"exit {proc.returncode}, expected {expect_code}; "
            f"stderr: {proc.stderr.decode('utf-8', 'replace')}"
        )
    return proc


@contextlib.contextmanager
def temp_snapshot(data: bytes, suffix=".md"):
    """Yield the path of a temp file holding `data`; delete it on exit.

    The handle is CLOSED before the yield: on Windows an open handle blocks the
    child process from reading the file.
    """
    with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as fh:
        fh.write(data)
        path = fh.name
    try:
        yield path
    finally:
        os.unlink(path)


def extract(data: bytes, suffix=".md", extra_args=None):
    with temp_snapshot(data, suffix) as path:
        proc = run_cli([path] + (extra_args or []))
        return json.loads(proc.stdout)


def assert_partition(test, manifest, data: bytes):
    nodes = manifest["nodes"]
    test.assertGreater(len(nodes), 0)
    cursor = 0
    for node in nodes:
        test.assertEqual(node["start_byte"], cursor, f"gap/overlap at {node['id']}")
        test.assertGreater(node["end_byte"], node["start_byte"])
        span = data[node["start_byte"] : node["end_byte"]]
        test.assertEqual(node["content_sha256"], hashlib.sha256(span).hexdigest())
        test.assertEqual(node["byte_length"], len(span))
        cursor = node["end_byte"]
    test.assertEqual(cursor, len(data), "partition does not cover snapshot")
    test.assertEqual(manifest["node_count"], len(nodes))
    test.assertEqual(manifest["snapshot"]["sha256"], hashlib.sha256(data).hexdigest())
    test.assertEqual(manifest["snapshot"]["byte_length"], len(data))


MD_FULL = (
    b"---\n"
    b"title: Test Doc\n"
    b"---\n"
    b"Intro paragraph before any heading.\n"
    b"\n"
    b"# Top\n"
    b"Body of top.\n"
    b"\n"
    b"## Sub A\n"
    b"```python\n"
    b"# not a heading\n"
    b"## also not\n"
    b"```\n"
    b"After fence.\n"
    b"\n"
    b"### Deep\n"
    b"Deep body.\n"
    b"\n"
    b"## Sub B\n"
    b"Setext One\n"
    b"==========\n"
    b"setext h1 body.\n"
    b"Setext Two\n"
    b"----------\n"
    b"setext h2 body.\n"
)


class TestMarkdown(unittest.TestCase):
    def test_partition_and_structure(self):
        m = extract(MD_FULL)
        assert_partition(self, m, MD_FULL)
        kinds = [n["kind"] for n in m["nodes"]]
        self.assertEqual(kinds[0], "frontmatter")
        self.assertEqual(kinds[1], "preamble")
        self.assertTrue(all(k == "section" for k in kinds[2:]))
        titles = [n["title"] for n in m["nodes"] if n["kind"] == "section"]
        self.assertEqual(
            titles, ["Top", "Sub A", "Deep", "Sub B", "Setext One", "Setext Two"]
        )
        levels = [n["level"] for n in m["nodes"] if n["kind"] == "section"]
        self.assertEqual(levels, [1, 2, 3, 2, 1, 2])

    def test_fence_hides_headings(self):
        m = extract(MD_FULL)
        titles = [n["title"] for n in m["nodes"]]
        self.assertNotIn("not a heading", titles)
        self.assertNotIn("also not", titles)

    def test_parent_links(self):
        m = extract(MD_FULL)
        by_title = {n["title"]: n for n in m["nodes"] if n["kind"] == "section"}
        self.assertIsNone(by_title["Top"]["parent_id"])
        self.assertEqual(by_title["Sub A"]["parent_id"], by_title["Top"]["id"])
        self.assertEqual(by_title["Deep"]["parent_id"], by_title["Sub A"]["id"])
        self.assertEqual(by_title["Sub B"]["parent_id"], by_title["Top"]["id"])
        self.assertIsNone(by_title["Setext One"]["parent_id"])
        self.assertEqual(
            by_title["Setext Two"]["parent_id"], by_title["Setext One"]["id"]
        )

    def test_crlf_offsets(self):
        data = MD_FULL.replace(b"\n", b"\r\n")
        m = extract(data)
        assert_partition(self, m, data)
        titles = [n["title"] for n in m["nodes"] if n["kind"] == "section"]
        self.assertIn("Setext Two", titles)

    def test_heading_at_byte_zero_no_empty_preamble(self):
        data = b"# First\nbody\n"
        m = extract(data)
        assert_partition(self, m, data)
        self.assertEqual(m["nodes"][0]["kind"], "section")

    def test_no_headings_whole_document(self):
        data = b"just prose\nno headings here\n"
        m = extract(data)
        assert_partition(self, m, data)
        self.assertEqual(len(m["nodes"]), 1)
        self.assertEqual(m["nodes"][0]["kind"], "document")

    def test_unclosed_fence_runs_to_eof(self):
        data = b"# Real\n```\n# swallowed\n"
        m = extract(data)
        assert_partition(self, m, data)
        titles = [n["title"] for n in m["nodes"] if n["kind"] == "section"]
        self.assertEqual(titles, ["Real"])

    def test_unclosed_frontmatter_is_content(self):
        data = b"---\nkey: value\nno close\n"
        m = extract(data)
        assert_partition(self, m, data)
        self.assertNotIn("frontmatter", [n["kind"] for n in m["nodes"]])

    def test_no_final_newline(self):
        data = b"# A\nbody with no trailing newline"
        m = extract(data)
        assert_partition(self, m, data)

    def test_atx_trailing_hashes_stripped(self):
        data = b"# Title ##\nbody\n"
        m = extract(data)
        self.assertEqual(m["nodes"][0]["title"], "Title")

    def test_indented_code_not_heading(self):
        data = b"para\n\n    # code comment\n\n# Real\n"
        m = extract(data)
        titles = [n["title"] for n in m["nodes"] if n["kind"] == "section"]
        self.assertEqual(titles, ["Real"])


class TestHtml(unittest.TestCase):
    def test_basic_partition(self):
        data = (
            b"<html><body>intro"
            b"<h1 class='x'>One</h1><p>a</p>"
            b"<h2>Two <em>em</em></h2><p>b</p>"
            b"<!-- <h2>ghost</h2> -->"
            b"<pre><h3>preformatted</h3></pre>"
            b"<script>var s = '<h4>js</h4>';</script>"
            b"</body></html>"
        )
        m = extract(data, suffix=".html")
        assert_partition(self, m, data)
        titles = [n["title"] for n in m["nodes"] if n["kind"] == "section"]
        self.assertEqual(titles, ["One", "Two em"])
        self.assertEqual(m["nodes"][0]["kind"], "preamble")

    def test_no_headings(self):
        data = b"<p>plain</p>"
        m = extract(data, suffix=".html")
        self.assertEqual(m["nodes"][0]["kind"], "document")

    def test_unclosed_comment_masks_to_eof(self):
        data = (
            b"<h1>Real</h1><p>a</p><!-- unclosed <h2>Fake heading inside comment</h2>"
        )
        m = extract(data, suffix=".html")
        assert_partition(self, m, data)
        titles = [n["title"] for n in m["nodes"] if n["kind"] == "section"]
        self.assertEqual(titles, ["Real"])


class TestOpaqueAndErrors(unittest.TestCase):
    def test_json_single_node(self):
        data = b'{"$schema": "x", "title": "# not a heading"}\n'
        m = extract(data, suffix=".json")
        assert_partition(self, m, data)
        self.assertEqual(len(m["nodes"]), 1)
        self.assertEqual(m["nodes"][0]["kind"], "document")

    def test_empty_snapshot_fails_loudly(self):
        with temp_snapshot(b"") as path:
            proc = run_cli([path], expect_code=2)
            self.assertIn(b"empty", proc.stderr)

    def test_unknown_extension_fails_loudly(self):
        with temp_snapshot(b"content", suffix=".xyz") as path:
            proc = run_cli([path], expect_code=2)
            self.assertIn(b"unknown snapshot extension", proc.stderr)

    def test_pdf_extension_refused(self):
        with temp_snapshot(b"%PDF-1.4", suffix=".pdf") as path:
            proc = run_cli([path], expect_code=2)
            self.assertIn(b"not node-extractable", proc.stderr)

    def test_missing_file_fails_loudly(self):
        run_cli([os.path.join(HERE, "does-not-exist.md")], expect_code=2)

    def test_format_override(self):
        data = b"# heading\nbody\n"
        m = extract(data, suffix=".md", extra_args=["--format", "opaque"])
        self.assertEqual(len(m["nodes"]), 1)


class TestEncodings(unittest.TestCase):
    def test_utf8_bom_keeps_outline(self):
        data = b"\xef\xbb\xbf# Title\nbody\n"
        m = extract(data)
        assert_partition(self, m, data)
        titles = [n["title"] for n in m["nodes"] if n["kind"] == "section"]
        self.assertEqual(titles, ["Title"])
        # BOM bytes land in a preamble node, not lost, not a heading shift
        self.assertEqual(m["nodes"][0]["kind"], "preamble")
        self.assertEqual(m["nodes"][0]["end_byte"], 3)

    def test_utf8_bom_frontmatter(self):
        data = b"\xef\xbb\xbf---\nk: v\n---\n# H\nbody\n"
        m = extract(data)
        assert_partition(self, m, data)
        kinds = [n["kind"] for n in m["nodes"]]
        self.assertEqual(kinds[0], "frontmatter")
        titles = [n["title"] for n in m["nodes"] if n["kind"] == "section"]
        self.assertEqual(titles, ["H"])

    def test_utf16_bom_rejected(self):
        data = "<h1>Hi</h1>".encode("utf-16")  # LE with BOM
        with temp_snapshot(data, suffix=".html") as path:
            proc = run_cli([path], expect_code=2)
            self.assertIn(b"UTF-16", proc.stderr)

    def test_utf32_bom_rejected(self):
        data = "# Hi\n".encode("utf-32")  # LE with BOM
        with temp_snapshot(data) as path:
            proc = run_cli([path], expect_code=2)
            self.assertIn(b"UTF-32", proc.stderr)

    def test_cr_only_rejected(self):
        with temp_snapshot(b"# A\rbody\r") as path:
            proc = run_cli([path], expect_code=2)
            self.assertIn(b"CR-only", proc.stderr)


class TestDeterminism(unittest.TestCase):
    def test_two_runs_byte_identical(self):
        with temp_snapshot(MD_FULL) as path:
            out1 = run_cli([path]).stdout
            out2 = run_cli([path]).stdout
            self.assertEqual(out1, out2)
            self.assertGreater(len(out1), 0)

    def test_out_file_matches_stdout(self):
        with temp_snapshot(MD_FULL) as spath:
            opath = spath + ".manifest.json"
            try:
                stdout = run_cli([spath]).stdout
                run_cli([spath, "--out", opath])
                with open(opath, "rb") as fh:
                    self.assertEqual(fh.read(), stdout)
            finally:
                if os.path.exists(opath):
                    os.unlink(opath)

    def test_id_shape(self):
        m = extract(MD_FULL)
        for node in m["nodes"]:
            self.assertRegex(node["id"], r"^n\d{4}-[0-9a-f]{8}$")
            self.assertTrue(node["id"].endswith(node["content_sha256"][:8]))


if __name__ == "__main__":
    unittest.main(verbosity=2)
