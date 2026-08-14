#!/usr/bin/env python3
"""Tests for parse_discovery.py and check_linkmap.py.
Stdlib unittest; run: python test_discovery.py"""

import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PARSER = os.path.join(HERE, "parse_discovery.py")
GATE = os.path.join(HERE, "check_linkmap.py")

LLMS_TXT = (
    b"# Agent Plugins\n"
    b"\n"
    b"> Docs index\n"
    b"\n"
    b"- [Home](https://agent-plugins.org/)\n"
    b"- [Spec](/spec)\n"
    b"- [Schema](https://agent-plugins.org/schema?version=v1&utm_source=x)\n"
    b"- Autolink: <https://agent-plugins.org/governance>\n"
    b"- Bare https://example.com/external page link.\n"
    b"- Inline code `https://example.com/inline-code` stays backtick-free.\n"
    b"- [Anchor](#section) and [mail](mailto:a@b.c) are not resources\n"
    b"- [Dupe](https://agent-plugins.org/spec/)\n"
)

SITEMAP_XML = (
    b'<?xml version="1.0" encoding="UTF-8"?>\n'
    b'<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
    b'  <url><loc>https://agent-plugins.org/</loc></url>\n'
    b'  <url><loc>https://agent-plugins.org/spec</loc></url>\n'
    b'  <url><loc>https://agent-plugins.org/faq</loc></url>\n'
    b'</urlset>\n'
)


def write(dirpath, name, data):
    path = os.path.join(dirpath, name)
    if isinstance(data, bytes):
        with open(path, "wb") as fh:
            fh.write(data)
    elif isinstance(data, str):
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(data)
    else:
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(data, fh)
    return path


class Base(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp()

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.dir, ignore_errors=True)

    def run_parser_raw(self, snapshot_path, rung, base_url, expect_code):
        proc = subprocess.run(
            [sys.executable, PARSER, snapshot_path, "--rung", rung,
             "--base-url", base_url],
            capture_output=True)
        if proc.returncode != expect_code:
            raise AssertionError(
                f"exit {proc.returncode}, expected {expect_code}; "
                f"stderr: {proc.stderr!r}")
        return proc

    def run_parser(self, snapshot_path, rung, base_url):
        proc = self.run_parser_raw(snapshot_path, rung, base_url, 0)
        return json.loads(proc.stdout)

    def run_gate(self, linkmap_path, discovery_paths, expect_code=0):
        cmd = [sys.executable, GATE, "--linkmap", linkmap_path]
        for p in discovery_paths:
            cmd += ["--discovery", p]
        proc = subprocess.run(cmd, capture_output=True)
        if proc.returncode != expect_code:
            raise AssertionError(
                f"exit {proc.returncode}, expected {expect_code}; "
                f"stdout: {proc.stdout!r} stderr: {proc.stderr!r}")
        return proc


class TestParserLlmsTxt(Base):
    def test_extraction_normalization_dedupe_sort(self):
        snap = write(self.dir, "llms.txt", LLMS_TXT)
        out = self.run_parser(snap, "llms-txt", "https://agent-plugins.org/")
        self.assertEqual(out["schema"], "discovery-output/v1")
        self.assertEqual(out["rung"], "llms-txt")
        urls = out["urls"]
        self.assertEqual(urls, sorted(urls))
        self.assertEqual(out["url_count"], len(urls))
        # relative resolved; trailing slash deduped; tracking param dropped,
        # content param kept; anchors/mailto excluded
        self.assertIn("https://agent-plugins.org/spec", urls)
        self.assertEqual(urls.count("https://agent-plugins.org/spec"), 1)
        self.assertIn("https://agent-plugins.org/schema?version=v1", urls)
        self.assertIn("https://agent-plugins.org/governance", urls)
        self.assertIn("https://example.com/external", urls)
        self.assertNotIn("mailto:a@b.c", urls)
        # inline-code URL: captured, but never with a trailing backtick
        self.assertIn("https://example.com/inline-code", urls)
        for u in urls:
            self.assertNotIn("utm_", u)
            self.assertNotIn("#", u)
            self.assertNotIn("`", u)

    def test_determinism(self):
        snap = write(self.dir, "llms2.txt", LLMS_TXT)
        p1 = subprocess.run([sys.executable, PARSER, snap, "--rung", "llms-txt",
                             "--base-url", "https://agent-plugins.org/"],
                            capture_output=True)
        p2 = subprocess.run([sys.executable, PARSER, snap, "--rung", "llms-txt",
                             "--base-url", "https://agent-plugins.org/"],
                            capture_output=True)
        self.assertEqual(p1.stdout, p2.stdout)
        self.assertGreater(len(p1.stdout), 0)

    def test_empty_snapshot_fails(self):
        snap = write(self.dir, "empty.txt", b"  \n")
        proc = self.run_parser_raw(snap, "llms-txt", "https://x.org/", 2)
        self.assertIn(b"empty", proc.stderr)

    def test_no_urls_fails_loudly(self):
        snap = write(self.dir, "nourls.txt", b"# Just a title\nprose only\n")
        proc = self.run_parser_raw(snap, "llms-txt", "https://x.org/", 2)
        self.assertIn(b"no http(s) URLs", proc.stderr)

    def test_bad_base_url_fails(self):
        snap = write(self.dir, "llms3.txt", LLMS_TXT)
        proc = self.run_parser_raw(snap, "llms-txt", "ftp://x.org/", 2)
        self.assertIn(b"base-url", proc.stderr)


class TestParserSitemap(Base):
    def test_xml_locs(self):
        snap = write(self.dir, "sitemap.xml", SITEMAP_XML)
        out = self.run_parser(snap, "sitemap-xml", "https://agent-plugins.org/")
        self.assertEqual(out["urls"], [
            "https://agent-plugins.org",
            "https://agent-plugins.org/faq",
            "https://agent-plugins.org/spec",
        ])

    def test_malformed_xml_fails_loudly(self):
        snap = write(self.dir, "bad.xml", b"<urlset><url><loc>x</loc>")
        proc = self.run_parser_raw(snap, "sitemap-xml", "https://x.org/", 2)
        self.assertIn(b"does not parse", proc.stderr)

    def test_doctype_rejected(self):
        snap = write(self.dir, "xxe.xml",
                     b'<?xml version="1.0"?><!DOCTYPE foo [<!ENTITY x SYSTEM '
                     b'"file:///etc/passwd">]><urlset><url><loc>'
                     b'https://x.org/&x;</loc></url></urlset>')
        proc = self.run_parser_raw(snap, "sitemap-xml", "https://x.org/", 2)
        self.assertIn(b"DOCTYPE", proc.stderr)

    def test_doctype_rejected_beyond_prefix_window(self):
        # padding the prolog past any prefix window must not smuggle a DTD in
        padding = b"<!-- " + b"x" * 5000 + b" -->\n"
        snap = write(self.dir, "xxe-padded.xml",
                     b'<?xml version="1.0"?>\n' + padding +
                     b'<!DOCTYPE foo [<!ENTITY x "PWNED">]>'
                     b'<urlset><url><loc>https://x.org/&x;</loc></url></urlset>')
        proc = self.run_parser_raw(snap, "sitemap-xml", "https://x.org/", 2)
        self.assertIn(b"DOCTYPE", proc.stderr)

    def test_sitemap_md(self):
        snap = write(self.dir, "sitemap.md",
                     b"# Sitemap\n- [A](/a)\n- [B](/b)\n")
        out = self.run_parser(snap, "sitemap-md", "https://x.org/")
        self.assertEqual(out["urls"], ["https://x.org/a", "https://x.org/b"])


class LinkMapHarness(Base):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.llms_snap = write(cls.dir, "llms.txt", LLMS_TXT)
        cls.xml_snap = write(cls.dir, "sitemap.xml", SITEMAP_XML)
        for name, snap, rung in (("d-llms.json", cls.llms_snap, "llms-txt"),
                                 ("d-xml.json", cls.xml_snap, "sitemap-xml")):
            proc = subprocess.run(
                [sys.executable, PARSER, snap, "--rung", rung,
                 "--base-url", "https://agent-plugins.org/",
                 "--out", os.path.join(cls.dir, name)],
                capture_output=True)
            assert proc.returncode == 0, proc.stderr
        cls.d_llms = os.path.join(cls.dir, "d-llms.json")
        cls.d_xml = os.path.join(cls.dir, "d-xml.json")
        with open(cls.d_llms, encoding="utf-8") as fh:
            llms_urls = set(json.load(fh)["urls"])
        with open(cls.d_xml, encoding="utf-8") as fh:
            xml_urls = set(json.load(fh)["urls"])

        seeds = ["https://agent-plugins.org"]
        ground = {}
        for u in seeds:
            ground.setdefault(u, set()).add("seed")
        for u in llms_urls:
            ground.setdefault(u, set()).add("llms-txt")
        for u in xml_urls:
            ground.setdefault(u, set()).add("sitemap-xml")

        rows = []
        for url in sorted(ground):
            cls_ = ("referenced-external" if "example.com" in url
                    else "in-corpus")
            rows.append({
                "url": url,
                "rungs": sorted(ground[url]),
                "classification": cls_,
                "reason": "fixture classification",
            })
        cls.linkmap = {
            "schema": "link-map/v1",
            "topic": "fixture corpus",
            "seeds": seeds,
            "bounds": {"max_resources": 10},
            "rows": rows,
        }

    def write_map(self, mapping, name="map.json"):
        return write(self.dir, name, mapping)


class TestLinkMapGate(LinkMapHarness):
    def test_clean_pass_names_coverage(self):
        path = self.write_map(self.linkmap)
        proc = self.run_gate(path, [self.d_llms, self.d_xml], expect_code=0)
        out = proc.stdout.decode()
        self.assertIn("PASS", out)
        self.assertIn("both directions", out)
        self.assertIn("max_resources", out)

    def test_unclassified_url_fails(self):
        m = copy.deepcopy(self.linkmap)
        dropped = m["rows"].pop(3)
        path = self.write_map(m, "map-drop.json")
        proc = self.run_gate(path, [self.d_llms, self.d_xml], expect_code=1)
        self.assertIn(b"unclassified", proc.stderr)
        self.assertIn(dropped["url"].encode(), proc.stderr)

    def test_phantom_row_fails(self):
        m = copy.deepcopy(self.linkmap)
        m["rows"].append({"url": "https://phantom.example/x",
                          "rungs": ["llms-txt"],
                          "classification": "ignore", "reason": "r"})
        path = self.write_map(m, "map-phantom.json")
        proc = self.run_gate(path, [self.d_llms, self.d_xml], expect_code=1)
        self.assertIn(b"phantom", proc.stderr)

    def test_wrong_rungs_fail(self):
        m = copy.deepcopy(self.linkmap)
        m["rows"][0]["rungs"] = ["llms-txt"] \
            if m["rows"][0]["rungs"] != ["llms-txt"] else ["sitemap-xml"]
        path = self.write_map(m, "map-rungs.json")
        proc = self.run_gate(path, [self.d_llms, self.d_xml], expect_code=1)
        self.assertIn(b"provenance", proc.stderr)

    def test_bad_classification_fails(self):
        m = copy.deepcopy(self.linkmap)
        m["rows"][0]["classification"] = "maybe-relevant"
        path = self.write_map(m, "map-badclass.json")
        proc = self.run_gate(path, [self.d_llms, self.d_xml], expect_code=1)
        self.assertIn(b"'maybe-relevant'", proc.stderr)

    def test_empty_reason_fails(self):
        m = copy.deepcopy(self.linkmap)
        m["rows"][0]["reason"] = " "
        path = self.write_map(m, "map-noreason.json")
        proc = self.run_gate(path, [self.d_llms, self.d_xml], expect_code=1)
        self.assertIn(b"reason is empty", proc.stderr)

    def test_bounds_breach_fails(self):
        m = copy.deepcopy(self.linkmap)
        m["bounds"]["max_resources"] = 2
        path = self.write_map(m, "map-bounds.json")
        proc = self.run_gate(path, [self.d_llms, self.d_xml], expect_code=1)
        self.assertIn(b"BOUNDS BREACH", proc.stderr)

    def test_missing_bounds_fails(self):
        m = copy.deepcopy(self.linkmap)
        m["bounds"] = {}
        path = self.write_map(m, "map-nobounds.json")
        proc = self.run_gate(path, [self.d_llms, self.d_xml], expect_code=2)
        self.assertIn(b"max_resources", proc.stderr)

    def test_duplicate_url_fails(self):
        m = copy.deepcopy(self.linkmap)
        m["rows"].append(copy.deepcopy(m["rows"][0]))
        path = self.write_map(m, "map-dup.json")
        proc = self.run_gate(path, [self.d_llms, self.d_xml], expect_code=1)
        self.assertIn(b"duplicate url", proc.stderr)

    def test_unparsable_linkmap_fails(self):
        path = write(self.dir, "map-broken.json", "| not | json |")
        proc = self.run_gate(path, [self.d_llms], expect_code=2)
        self.assertIn(b"not parseable JSON", proc.stderr)

    def test_duplicate_json_key_fails(self):
        raw = json.dumps(self.linkmap)
        raw = raw[:-1] + ', "schema": "link-map/v1"}'
        path = write(self.dir, "map-dupkey.json", raw)
        proc = self.run_gate(path, [self.d_llms], expect_code=2)
        self.assertIn(b"duplicate JSON key", proc.stderr)

    def test_inconsistent_discovery_output_fails(self):
        with open(self.d_llms, encoding="utf-8") as fh:
            doc = json.load(fh)
        doc["url_count"] = 999
        path = write(self.dir, "d-lying.json", doc)
        mpath = self.write_map(self.linkmap, "map-ok.json")
        proc = self.run_gate(mpath, [path], expect_code=2)
        self.assertIn(b"internally inconsistent", proc.stderr)

    def test_normalize_url_mode(self):
        proc = subprocess.run(
            [sys.executable, PARSER, "--normalize-url",
             "HTTPS://X.org/path/?utm_source=a&v=1#frag"],
            capture_output=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stdout.strip(), b"https://x.org/path?v=1")

    def test_normalize_url_mode_rejects_non_http(self):
        proc = subprocess.run(
            [sys.executable, PARSER, "--normalize-url", "ftp://x.org/a"],
            capture_output=True)
        self.assertEqual(proc.returncode, 2)

    def test_unnormalized_seed_rejected(self):
        m = copy.deepcopy(self.linkmap)
        m["seeds"] = ["https://agent-plugins.org/"]  # trailing slash
        path = self.write_map(m, "map-rawseed.json")
        proc = self.run_gate(path, [self.d_llms, self.d_xml], expect_code=2)
        self.assertIn(b"not in normalized form", proc.stderr)

    def test_unnormalized_row_url_fails(self):
        m = copy.deepcopy(self.linkmap)
        m["rows"][0]["url"] = m["rows"][0]["url"].upper()
        path = self.write_map(m, "map-rawrow.json")
        proc = self.run_gate(path, [self.d_llms, self.d_xml], expect_code=1)
        self.assertIn(b"not in normalized form", proc.stderr)

    def test_no_discovery_inputs_rejected(self):
        path = self.write_map(self.linkmap, "map-nodisco.json")
        proc = self.run_gate(path, [], expect_code=2)
        self.assertIn(b"at least one --discovery", proc.stderr)

    def test_discovery_unknown_key_rejected(self):
        with open(self.d_llms, encoding="utf-8") as fh:
            doc = json.load(fh)
        doc["extra_key"] = 1
        path = write(self.dir, "d-extra.json", doc)
        mpath = self.write_map(self.linkmap, "map-dextra.json")
        proc = self.run_gate(mpath, [path], expect_code=2)
        self.assertIn(b"unknown keys", proc.stderr)

    def test_discovery_missing_key_rejected(self):
        with open(self.d_llms, encoding="utf-8") as fh:
            doc = json.load(fh)
        del doc["snapshot"]
        path = write(self.dir, "d-missing.json", doc)
        mpath = self.write_map(self.linkmap, "map-dmissing.json")
        proc = self.run_gate(mpath, [path], expect_code=2)
        self.assertIn(b"missing keys", proc.stderr)

    def test_unknown_row_key_fails(self):
        m = copy.deepcopy(self.linkmap)
        m["rows"][0]["not_a_real_key"] = "in-corpus"
        path = self.write_map(m, "map-typo.json")
        proc = self.run_gate(path, [self.d_llms, self.d_xml], expect_code=1)
        self.assertIn(b"not_a_real_key", proc.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
