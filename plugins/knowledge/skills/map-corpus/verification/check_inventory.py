#!/usr/bin/env python3
"""Inventory gate: verdict-coverage and evidence-token checks for one resource.

Diffs a node-inventory (agent judgment) against a node-manifest (deterministic
denominator) and the immutable snapshot both were computed from. See
inventory-format.md for the contract this script enforces.

Fail-loud discipline: anything this gate cannot parse or recognize is a
non-zero exit naming the input — never a silent skip. A clean run prints
exactly what it exercised; a pass covers only what was printed.

Exit codes:
  0  all checks passed
  1  one or more named check failures
  2  unusable input (IO, JSON parse, schema-literal mismatch)
  3  internal invariant violation

Stdlib only. Python 3.9+.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from typing import NoReturn

MANIFEST_SCHEMA = "node-manifest/v1"
INVENTORY_SCHEMA = "node-inventory/v1"
VERDICTS = ("relevant", "not-relevant", "uncertain")

ROW_KEYS = {"node_id", "verdict", "rationale", "evidence"}
EVIDENCE_KEYS = {"quote", "start_byte", "end_byte"}
INVENTORY_KEYS = {"schema", "snapshot_sha256", "rows"}


def fail(code: int, message: str) -> NoReturn:
    sys.stderr.write(f"check_inventory: ERROR: {message}\n")
    sys.exit(code)


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _reject_duplicate_keys(pairs):
    """object_pairs_hook: json.loads is last-wins on duplicate keys, so a
    duplicated field would let unvalidated bytes ride under a validated name
    (parser-differential fail-open). Reject at any depth instead."""
    seen = {}
    for key, value in pairs:
        if key in seen:
            raise ValueError(f"duplicate JSON key {key!r}")
        seen[key] = value
    return seen


def load_json(path: str, what: str):
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except OSError as exc:
        fail(2, f"cannot read {what} {path!r}: {exc}")
    try:
        return json.loads(raw, object_pairs_hook=_reject_duplicate_keys)
    except ValueError as exc:
        fail(2, f"{what} {path!r} is not parseable JSON: {exc}. "
                f"An unparsable {what} is a failed run, not a clean one.")


class Failures:
    def __init__(self):
        self.items = []

    def add(self, message: str):
        self.items.append(message)
        sys.stderr.write(f"check_inventory: FAIL: {message}\n")


def check_manifest(manifest, data: bytes, failures: Failures):
    """Re-verify the manifest against the snapshot; trust nothing on disk."""
    if not isinstance(manifest, dict):
        fail(2, f"manifest root is a {type(manifest).__name__}, not a JSON "
                f"object; this gate checks {MANIFEST_SCHEMA!r} only.")
    if manifest.get("schema") != MANIFEST_SCHEMA:
        fail(2, f"manifest schema is {manifest.get('schema')!r}; "
                f"this gate checks {MANIFEST_SCHEMA!r} only.")
    nodes = manifest.get("nodes")
    if not isinstance(nodes, list) or not nodes:
        fail(2, "manifest has no 'nodes' list; nothing to gate against.")
    node_count = manifest.get("node_count")
    if node_count != len(nodes):
        fail(2, f"manifest node_count {node_count!r} != len(nodes) "
                f"{len(nodes)}; the manifest is internally inconsistent.")

    snap = manifest.get("snapshot", {})
    if not isinstance(snap, dict):
        fail(2, "manifest 'snapshot' is not an object.")
    if snap.get("sha256") != sha256_hex(data):
        failures.add(
            f"manifest snapshot.sha256 {snap.get('sha256')!r} does not match "
            f"the snapshot file ({sha256_hex(data)}); the manifest describes "
            f"different bytes.")
        return None
    if snap.get("byte_length") != len(data):
        failures.add(
            f"manifest snapshot.byte_length {snap.get('byte_length')!r} != "
            f"actual {len(data)}.")
        return None

    cursor = 0
    by_id = {}
    for node in nodes:
        if not isinstance(node, dict):
            fail(2, f"manifest node at partition offset {cursor} is not an object.")
        try:
            nid = node["id"]
            start = node["start_byte"]
            end = node["end_byte"]
            digest = node["content_sha256"]
        except KeyError as exc:
            fail(2, f"manifest node missing key {exc}; regenerate the manifest.")
        if not isinstance(nid, str) or not nid:
            fail(2, f"manifest node id {nid!r} is not a non-empty string.")
        if not (isinstance(start, int) and isinstance(end, int)) \
                or isinstance(start, bool) or isinstance(end, bool):
            fail(2, f"manifest node {nid!r} has non-integer byte range.")
        if start != cursor:
            failures.add(f"manifest partition gap/overlap at node {nid}: "
                         f"expected start {cursor}, got {start}.")
            return None
        if end <= start or end > len(data):
            failures.add(f"manifest node {nid} has invalid span [{start}:{end}].")
            return None
        if sha256_hex(data[start:end]) != digest:
            failures.add(f"manifest node {nid} content_sha256 does not match "
                         f"snapshot bytes [{start}:{end}]; stale manifest.")
            return None
        if nid in by_id:
            fail(2, f"manifest contains duplicate node id {nid!r}.")
        by_id[nid] = node
        cursor = end
    if cursor != len(data):
        failures.add(f"manifest partition ends at {cursor}, snapshot is "
                     f"{len(data)} bytes.")
        return None
    return by_id


def check_inventory_shape(inventory) -> list:
    """Structural strictness; anything unrecognized is exit 2, never skipped."""
    if not isinstance(inventory, dict):
        fail(2, "inventory root is not a JSON object.")
    unknown = set(inventory) - INVENTORY_KEYS
    if unknown:
        fail(2, f"inventory has unknown top-level keys {sorted(unknown)}; "
                f"unknown keys fail loudly so a misspelling cannot be ignored.")
    missing = INVENTORY_KEYS - set(inventory)
    if missing:
        fail(2, f"inventory missing required keys {sorted(missing)}.")
    if inventory["schema"] != INVENTORY_SCHEMA:
        fail(2, f"inventory schema is {inventory['schema']!r}; this gate "
                f"checks {INVENTORY_SCHEMA!r} only.")
    rows = inventory["rows"]
    if not isinstance(rows, list) or not rows:
        fail(2, "inventory 'rows' is not a non-empty list.")
    return rows


def check_row(index: int, row, node, data: bytes, failures: Failures) -> bool:
    """Field and evidence checks for one row; returns True when fully clean."""
    label = f"row[{index}]" + (f" (node_id {row.get('node_id')!r})"
                              if isinstance(row, dict) and "node_id" in row else "")
    if not isinstance(row, dict):
        failures.add(f"{label}: not a JSON object.")
        return False
    unknown = set(row) - ROW_KEYS
    if unknown:
        failures.add(f"{label}: unknown keys {sorted(unknown)}.")
        return False
    missing = ROW_KEYS - set(row)
    if missing:
        failures.add(f"{label}: missing keys {sorted(missing)}.")
        return False
    ok = True
    if row["verdict"] not in VERDICTS:
        failures.add(f"{label}: verdict {row['verdict']!r} is not one of "
                     f"{list(VERDICTS)}.")
        ok = False
    if not (isinstance(row["rationale"], str) and row["rationale"].strip()):
        failures.add(f"{label}: rationale is empty or not a string.")
        ok = False

    ev = row["evidence"]
    if not isinstance(ev, dict):
        failures.add(f"{label}: evidence is not an object.")
        return False
    ev_unknown = set(ev) - EVIDENCE_KEYS
    if ev_unknown:
        failures.add(f"{label}: evidence has unknown keys {sorted(ev_unknown)}.")
        return False
    ev_missing = EVIDENCE_KEYS - set(ev)
    if ev_missing:
        failures.add(f"{label}: evidence missing keys {sorted(ev_missing)}.")
        return False
    quote, start, end = ev["quote"], ev["start_byte"], ev["end_byte"]
    if not (isinstance(quote, str) and quote):
        failures.add(f"{label}: evidence quote is empty or not a string.")
        return False
    if not (isinstance(start, int) and isinstance(end, int)) \
            or isinstance(start, bool) or isinstance(end, bool):
        failures.add(f"{label}: evidence byte offsets are not integers.")
        return False
    if not (node["start_byte"] <= start < end <= node["end_byte"]):
        failures.add(
            f"{label}: evidence span [{start}:{end}] is not inside node span "
            f"[{node['start_byte']}:{node['end_byte']}] -- quote must lie "
            f"within the node it vouches for (straddling is forbidden).")
        return False
    try:
        expected = quote.encode("utf-8")
    except UnicodeEncodeError as exc:
        failures.add(f"{label}: evidence quote is not encodable UTF-8 "
                     f"(lone surrogate?): {exc}.")
        return False
    actual = data[start:end]
    if expected != actual:
        shown = actual.decode("utf-8", errors="replace")
        failures.add(
            f"{label}: evidence quote does not byte-match snapshot "
            f"[{start}:{end}]; quoted {quote!r}, snapshot has {shown!r}.")
        return False
    return ok


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="check_inventory.py",
        description="Gate a node inventory against its manifest and snapshot.")
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--inventory", required=True)
    parser.add_argument("--snapshot", required=True)
    args = parser.parse_args(argv)

    try:
        with open(args.snapshot, "rb") as fh:
            data = fh.read()
    except OSError as exc:
        fail(2, f"cannot read snapshot {args.snapshot!r}: {exc}")
    if not data:
        fail(2, f"snapshot {args.snapshot!r} is empty (0 bytes).")

    manifest = load_json(args.manifest, "manifest")
    inventory = load_json(args.inventory, "inventory")

    failures = Failures()
    nodes_by_id = check_manifest(manifest, data, failures)
    rows = check_inventory_shape(inventory)

    if nodes_by_id is None:
        print(f"check_inventory: FAILED --{len(failures.items)} failure(s); "
              f"manifest did not verify, rows not checked.")
        return 1

    if inventory["snapshot_sha256"] != sha256_hex(data):
        failures.add(
            f"inventory snapshot_sha256 {inventory['snapshot_sha256']!r} does "
            f"not match the snapshot file; these verdicts were formed against "
            f"different bytes.")

    seen = {}
    verdict_counts = {v: 0 for v in VERDICTS}
    rows_clean = 0
    for index, row in enumerate(rows):
        nid = row.get("node_id") if isinstance(row, dict) else None
        if nid is not None and not isinstance(nid, str):
            failures.add(f"row[{index}]: node_id {nid!r} is not a string.")
            continue
        if nid is not None and nid in seen:
            failures.add(f"row[{index}]: duplicate node_id {nid!r} "
                         f"(first at row[{seen[nid]}]); verdict is ambiguous.")
            continue
        if nid is not None:
            seen[nid] = index
        if nid is None or nid not in nodes_by_id:
            failures.add(f"row[{index}]: node_id {nid!r} is not in the "
                         f"manifest; a verdict about nothing.")
            continue
        if check_row(index, row, nodes_by_id[nid], data, failures):
            rows_clean += 1
            verdict_counts[row["verdict"]] += 1

    unrepresented = [nid for nid in nodes_by_id if nid not in seen]
    if unrepresented:
        failures.add(
            f"{len(unrepresented)} manifest node(s) have no inventory row "
            f"(unrepresented content): {', '.join(sorted(unrepresented))}.")

    if failures.items:
        print(f"check_inventory: FAILED --{len(failures.items)} failure(s) "
              f"across {len(rows)} row(s) / {len(nodes_by_id)} node(s).")
        return 1

    print(
        "check_inventory: PASS -- exercised: "
        f"manifest {args.manifest!r} (partition + whole-file and per-node "
        f"sha256 vs snapshot {args.snapshot!r}), inventory {args.inventory!r} "
        f"({len(rows)} rows vs {len(nodes_by_id)} nodes, both directions, "
        f"inventory snapshot_sha256 vs snapshot file, "
        f"fields: node_id, verdict, rationale, evidence.quote/start_byte/"
        f"end_byte with byte-exact match and node containment). "
        f"Verdicts: {verdict_counts['relevant']} relevant, "
        f"{verdict_counts['not-relevant']} not-relevant, "
        f"{verdict_counts['uncertain']} uncertain. "
        f"Nothing outside the listed files and fields was checked.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as exc:  # residual bug: documented exit 3, never a bare traceback
        sys.stderr.write(
            f"check_inventory: ERROR: internal failure "
            f"{type(exc).__name__}: {exc}. This is a gate bug; the run is "
            f"NOT clean.\n")
        sys.exit(3)
