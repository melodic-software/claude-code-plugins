#!/usr/bin/env python3
"""Tests for check_inventory.py. Stdlib unittest; run: python test_check_inventory.py

The fail-loud cases here are why this file exists: the gate is proven to fail
loudly on unparsable and malformed input BEFORE it is made a required artifact.
"""

import copy
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
GATE = os.path.join(HERE, "check_inventory.py")
EXTRACTOR = os.path.join(HERE, "..", "extraction", "extract_nodes.py")

SNAPSHOT = (
    b"Intro before headings.\n"
    b"\n"
    b"# Alpha\n"
    b"Alpha body line.\n"
    b"\n"
    b"## Beta\n"
    b"Beta body with a distinctive token: quicksilver.\n"
    b"\n"
    b"# Gamma\n"
    b"Gamma body.\n"
)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class GateHarness(unittest.TestCase):
    """Builds a valid snapshot+manifest+inventory triple, then mutates."""

    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp()
        cls.snapshot = os.path.join(cls.dir, "source.md")
        with open(cls.snapshot, "wb") as fh:
            fh.write(SNAPSHOT)
        cls.manifest_path = os.path.join(cls.dir, "manifest.json")
        proc = subprocess.run(
            [sys.executable, EXTRACTOR, cls.snapshot, "--out", cls.manifest_path],
            capture_output=True)
        assert proc.returncode == 0, proc.stderr
        with open(cls.manifest_path, "rb") as fh:
            cls.manifest = json.load(fh)

        rows = []
        for node in cls.manifest["nodes"]:
            start = node["start_byte"]
            # evidence: first 10 bytes of the node (ASCII fixture, safe)
            quote = SNAPSHOT[start:start + 10].decode("utf-8")
            rows.append({
                "node_id": node["id"],
                "verdict": "relevant",
                "rationale": "Fixture rationale.",
                "evidence": {
                    "quote": quote,
                    "start_byte": start,
                    "end_byte": start + 10,
                },
            })
        cls.inventory = {
            "schema": "node-inventory/v1",
            "snapshot_sha256": sha(SNAPSHOT),
            "rows": rows,
        }

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.dir, ignore_errors=True)

    def run_gate(self, inventory=None, manifest_path=None, inventory_raw=None,
                 expect_code=0):
        if inventory_raw is None:
            inventory_raw = json.dumps(
                inventory if inventory is not None else self.inventory
            ).encode("utf-8")
        with tempfile.NamedTemporaryFile(
                dir=self.dir, suffix=".json", delete=False) as fh:
            fh.write(inventory_raw)
            inv_path = fh.name
        try:
            proc = subprocess.run(
                [sys.executable, GATE,
                 "--manifest", manifest_path or self.manifest_path,
                 "--inventory", inv_path,
                 "--snapshot", self.snapshot],
                capture_output=True)
            if proc.returncode != expect_code:
                raise AssertionError(
                    f"exit {proc.returncode}, expected {expect_code}; "
                    f"stdout: {proc.stdout!r} stderr: {proc.stderr!r}")
            return proc
        finally:
            os.unlink(inv_path)

    def mutated(self, **kwargs):
        inv = copy.deepcopy(self.inventory)
        inv.update(kwargs)
        return inv


class TestCleanPass(GateHarness):
    def test_valid_triple_passes_and_names_coverage(self):
        proc = self.run_gate(expect_code=0)
        out = proc.stdout.decode()
        self.assertIn("PASS", out)
        # a clean result names what it exercised
        self.assertIn("rows", out)
        self.assertIn("byte-exact", out)
        self.assertIn("relevant", out)

    def test_mixed_verdicts_pass(self):
        inv = copy.deepcopy(self.inventory)
        inv["rows"][0]["verdict"] = "not-relevant"
        inv["rows"][1]["verdict"] = "uncertain"
        proc = self.run_gate(inv, expect_code=0)
        self.assertIn(b"1 uncertain", proc.stdout)


class TestFailLoudUnparsable(GateHarness):
    def test_inventory_not_json(self):
        proc = self.run_gate(inventory_raw=b"# A Markdown Inventory\n| n1 | yes |\n",
                             expect_code=2)
        self.assertIn(b"not parseable JSON", proc.stderr)

    def test_inventory_truncated_json(self):
        good = json.dumps(self.inventory).encode("utf-8")
        proc = self.run_gate(inventory_raw=good[: len(good) // 2], expect_code=2)
        self.assertIn(b"not parseable JSON", proc.stderr)

    def test_manifest_not_json(self):
        bad = os.path.join(self.dir, "bad-manifest.json")
        with open(bad, "wb") as fh:
            fh.write(b"not json either")
        proc = self.run_gate(manifest_path=bad, expect_code=2)
        self.assertIn(b"manifest", proc.stderr)

    def test_wrong_schema_literal(self):
        proc = self.run_gate(self.mutated(schema="node-inventory/v2"),
                             expect_code=2)
        self.assertIn(b"node-inventory/v1", proc.stderr)

    def test_unknown_top_level_key(self):
        proc = self.run_gate(self.mutated(extra_field=1), expect_code=2)
        self.assertIn(b"unknown top-level keys", proc.stderr)

    def test_missing_file(self):
        proc = subprocess.run(
            [sys.executable, GATE, "--manifest", self.manifest_path,
             "--inventory", os.path.join(self.dir, "absent.json"),
             "--snapshot", self.snapshot],
            capture_output=True)
        self.assertEqual(proc.returncode, 2)


class TestFailNamedRow(GateHarness):
    def test_malformed_row_named(self):
        inv = copy.deepcopy(self.inventory)
        del inv["rows"][1]["rationale"]
        proc = self.run_gate(inv, expect_code=1)
        nid = self.inventory["rows"][1]["node_id"]
        self.assertIn(nid.encode(), proc.stderr)
        self.assertIn(b"missing keys", proc.stderr)

    def test_misspelled_field_named(self):
        inv = copy.deepcopy(self.inventory)
        inv["rows"][0]["verdcit"] = inv["rows"][0].pop("verdict")
        proc = self.run_gate(inv, expect_code=1)
        self.assertIn(b"verdcit", proc.stderr)

    def test_unknown_verdict_named(self):
        inv = copy.deepcopy(self.inventory)
        inv["rows"][0]["verdict"] = "maybe"
        proc = self.run_gate(inv, expect_code=1)
        self.assertIn(b"'maybe'", proc.stderr)

    def test_empty_rationale(self):
        inv = copy.deepcopy(self.inventory)
        inv["rows"][0]["rationale"] = "   "
        proc = self.run_gate(inv, expect_code=1)
        self.assertIn(b"rationale", proc.stderr)

    def test_missing_row_unrepresented_node(self):
        inv = copy.deepcopy(self.inventory)
        dropped = inv["rows"].pop(2)
        proc = self.run_gate(inv, expect_code=1)
        self.assertIn(dropped["node_id"].encode(), proc.stderr)
        self.assertIn(b"unrepresented", proc.stderr)

    def test_unknown_node_id(self):
        inv = copy.deepcopy(self.inventory)
        inv["rows"][0]["node_id"] = "n9999-deadbeef"
        proc = self.run_gate(inv, expect_code=1)
        self.assertIn(b"n9999-deadbeef", proc.stderr)

    def test_duplicate_node_id(self):
        inv = copy.deepcopy(self.inventory)
        inv["rows"].append(copy.deepcopy(inv["rows"][0]))
        proc = self.run_gate(inv, expect_code=1)
        self.assertIn(b"duplicate node_id", proc.stderr)


class TestEvidenceToken(GateHarness):
    def test_token_moved_outside_node_range_fails(self):
        # completion criterion: gate exits non-zero when a token is moved
        # outside its node's byte range
        inv = copy.deepcopy(self.inventory)
        row = inv["rows"][1]
        node = self.manifest["nodes"][1]
        shift = node["end_byte"] - row["evidence"]["start_byte"]
        row["evidence"]["start_byte"] += shift
        row["evidence"]["end_byte"] += shift
        proc = self.run_gate(inv, expect_code=1)
        self.assertIn(b"not inside node span", proc.stderr)

    def test_quote_snapshot_mismatch(self):
        inv = copy.deepcopy(self.inventory)
        inv["rows"][0]["evidence"]["quote"] = "fabricated"
        proc = self.run_gate(inv, expect_code=1)
        self.assertIn(b"does not byte-match", proc.stderr)

    def test_straddling_span_fails(self):
        inv = copy.deepcopy(self.inventory)
        row = inv["rows"][0]
        node = self.manifest["nodes"][0]
        row["evidence"]["start_byte"] = node["end_byte"] - 3
        row["evidence"]["end_byte"] = node["end_byte"] + 3
        span = SNAPSHOT[row["evidence"]["start_byte"]:row["evidence"]["end_byte"]]
        row["evidence"]["quote"] = span.decode("utf-8")
        proc = self.run_gate(inv, expect_code=1)
        self.assertIn(b"not inside node span", proc.stderr)

    def test_non_integer_offsets(self):
        inv = copy.deepcopy(self.inventory)
        inv["rows"][0]["evidence"]["start_byte"] = "12"
        proc = self.run_gate(inv, expect_code=1)
        self.assertIn(b"not integers", proc.stderr)

    def test_utf8_multibyte_quote(self):
        data = "# Título\ncafé body — dash.\n".encode("utf-8")
        snap = os.path.join(self.dir, "utf8.md")
        with open(snap, "wb") as fh:
            fh.write(data)
        mpath = os.path.join(self.dir, "utf8-manifest.json")
        subprocess.run([sys.executable, EXTRACTOR, snap, "--out", mpath],
                       capture_output=True, check=True)
        with open(mpath, encoding="utf-8") as fh:
            manifest = json.load(fh)
        node = manifest["nodes"][0]
        quote = "café"
        qbytes = quote.encode("utf-8")
        start = data.index(qbytes)
        inv = {
            "schema": "node-inventory/v1",
            "snapshot_sha256": sha(data),
            "rows": [{
                "node_id": node["id"],
                "verdict": "relevant",
                "rationale": "multibyte fixture",
                "evidence": {"quote": quote, "start_byte": start,
                             "end_byte": start + len(qbytes)},
            }],
        }
        ipath = os.path.join(self.dir, "utf8-inventory.json")
        with open(ipath, "w", encoding="utf-8") as fh:
            json.dump(inv, fh)
        proc = subprocess.run(
            [sys.executable, GATE, "--manifest", mpath,
             "--inventory", ipath, "--snapshot", snap],
            capture_output=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)


class TestParserDifferential(GateHarness):
    """Duplicate JSON keys are last-wins in json.loads; the gate must reject
    them so unvalidated bytes cannot ride under a validated name."""

    def test_duplicate_top_level_key_rejected(self):
        good = json.dumps(self.inventory)
        raw = good[:-1] + ', "schema": "node-inventory/v1"}'
        proc = self.run_gate(inventory_raw=raw.encode("utf-8"), expect_code=2)
        self.assertIn(b"duplicate JSON key", proc.stderr)

    def test_duplicate_evidence_key_smuggle_rejected(self):
        inv = copy.deepcopy(self.inventory)
        row = inv["rows"][0]
        row_json = json.dumps(row)
        # inject a FIRST evidence key with a fabricated quote before the real one
        smuggled = row_json.replace(
            '"evidence":',
            '"evidence": {"quote": "FABRICATED", "start_byte": 0, '
            '"end_byte": 10}, "evidence":', 1)
        assert smuggled != row_json
        full = json.dumps(inv)
        full = full.replace(row_json, smuggled, 1)
        proc = self.run_gate(inventory_raw=full.encode("utf-8"), expect_code=2)
        self.assertIn(b"duplicate JSON key", proc.stderr)

    def test_duplicate_key_in_manifest_rejected(self):
        with open(self.manifest_path, encoding="utf-8") as fh:
            raw = fh.read()
        bad = raw.replace('"schema":', '"schema": "node-manifest/v0", "schema":', 1)
        bad_path = os.path.join(self.dir, "dup-manifest.json")
        with open(bad_path, "w", encoding="utf-8") as fh:
            fh.write(bad)
        proc = self.run_gate(manifest_path=bad_path, expect_code=2)
        self.assertIn(b"duplicate JSON key", proc.stderr)


class TestCrashClasses(GateHarness):
    def test_manifest_root_array_named_exit2(self):
        bad_path = os.path.join(self.dir, "array-manifest.json")
        with open(bad_path, "w", encoding="utf-8") as fh:
            fh.write("[1, 2, 3]")
        proc = self.run_gate(manifest_path=bad_path, expect_code=2)
        self.assertIn(b"not a JSON object", proc.stderr)
        self.assertNotIn(b"Traceback", proc.stderr)

    def test_lone_surrogate_quote_named_row(self):
        inv = copy.deepcopy(self.inventory)
        raw = json.dumps(inv)
        quote = inv["rows"][0]["evidence"]["quote"]
        raw = raw.replace(json.dumps(quote), '"\\ud800bad"', 1)
        proc = self.run_gate(inventory_raw=raw.encode("utf-8"), expect_code=1)
        self.assertIn(b"row[0]", proc.stderr)
        self.assertIn(b"not encodable UTF-8", proc.stderr)
        self.assertNotIn(b"Traceback", proc.stderr)

    def test_node_id_as_list_named_row(self):
        inv = copy.deepcopy(self.inventory)
        inv["rows"][0]["node_id"] = ["a", "b"]
        proc = self.run_gate(inv, expect_code=1)
        self.assertIn(b"not a string", proc.stderr)
        self.assertNotIn(b"Traceback", proc.stderr)

    def test_lying_node_count_rejected(self):
        with open(self.manifest_path, encoding="utf-8") as fh:
            manifest = json.load(fh)
        manifest["node_count"] = 999
        bad_path = os.path.join(self.dir, "lying-count-manifest.json")
        with open(bad_path, "w", encoding="utf-8") as fh:
            json.dump(manifest, fh)
        proc = self.run_gate(manifest_path=bad_path, expect_code=2)
        self.assertIn(b"internally inconsistent", proc.stderr)


class TestStaleness(GateHarness):
    def test_inventory_hash_mismatch(self):
        proc = self.run_gate(self.mutated(snapshot_sha256="0" * 64),
                             expect_code=1)
        self.assertIn(b"different bytes", proc.stderr)

    def test_stale_manifest_against_edited_snapshot(self):
        edited = SNAPSHOT.replace(b"quicksilver", b"QUICKSILVER")
        snap2 = os.path.join(self.dir, "edited.md")
        with open(snap2, "wb") as fh:
            fh.write(edited)
        inv_path = os.path.join(self.dir, "inv-stale.json")
        with open(inv_path, "w", encoding="utf-8") as fh:
            json.dump(self.inventory, fh)
        proc = subprocess.run(
            [sys.executable, GATE, "--manifest", self.manifest_path,
             "--inventory", inv_path, "--snapshot", snap2],
            capture_output=True)
        self.assertEqual(proc.returncode, 1, proc.stderr)
        self.assertIn(b"does not match", proc.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
