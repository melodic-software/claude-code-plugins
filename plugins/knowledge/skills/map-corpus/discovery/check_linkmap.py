#!/usr/bin/env python3
"""Link-map gate: classification coverage, provenance, and bounds for one slice.

Diffs the agent-authored link map against every script-produced discovery
output plus the seed list. See link-map-format.md for the contract.

Fail-loud discipline: anything unparsable or unrecognized is a non-zero exit
naming the input — never a silent skip. A clean run prints what it exercised.

Exit codes:
  0  all checks passed
  1  one or more named check failures (incl. a bounds breach)
  2  unusable input
  3  internal gate bug

Stdlib only. Python 3.9+.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import NoReturn

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse_discovery import normalize_url  # noqa: E402  (URL identity has ONE owner)

LINKMAP_SCHEMA = "link-map/v1"
DISCOVERY_SCHEMA = "discovery-output/v1"
CLASSIFICATIONS = ("in-corpus", "companion", "referenced-external", "ignore")
DISCOVERY_RUNGS = ("llms-txt", "sitemap-xml", "sitemap-md")
ROW_RUNGS = ("seed",) + DISCOVERY_RUNGS

LINKMAP_KEYS = {"schema", "topic", "seeds", "bounds", "rows"}
ROW_KEYS = {"url", "rungs", "classification", "reason"}
BOUNDS_KEYS = {"max_resources", "notes"}


def fail(code: int, message: str) -> NoReturn:
    sys.stderr.write(f"check_linkmap: ERROR: {message}\n")
    sys.exit(code)


def _reject_duplicate_keys(pairs):
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
        fail(2, f"{what} {path!r} is not parseable JSON: {exc}.")


class Failures:
    def __init__(self):
        self.items = []

    def add(self, message: str):
        self.items.append(message)
        sys.stderr.write(f"check_linkmap: FAIL: {message}\n")


DISCOVERY_KEYS = {"schema", "rung", "snapshot", "base_url", "url_count", "urls"}


def check_discovery_output(path: str, doc) -> tuple:
    """Returns (rung, set-of-urls); anything unrecognized is exit 2."""
    if not isinstance(doc, dict):
        fail(2, f"discovery output {path!r} root is not a JSON object.")
    d_unknown = set(doc) - DISCOVERY_KEYS
    if d_unknown:
        fail(2, f"discovery output {path!r} has unknown keys "
                f"{sorted(d_unknown)}.")
    d_missing = DISCOVERY_KEYS - set(doc)
    if d_missing:
        fail(2, f"discovery output {path!r} missing keys {sorted(d_missing)}.")
    if doc.get("schema") != DISCOVERY_SCHEMA:
        fail(2, f"discovery output {path!r} schema is {doc.get('schema')!r}; "
                f"expected {DISCOVERY_SCHEMA!r}.")
    rung = doc.get("rung")
    if rung not in DISCOVERY_RUNGS:
        fail(2, f"discovery output {path!r} rung {rung!r} is not one of "
                f"{list(DISCOVERY_RUNGS)}.")
    urls = doc.get("urls")
    if not isinstance(urls, list) or not urls \
            or not all(isinstance(u, str) and u for u in urls):
        fail(2, f"discovery output {path!r} 'urls' is not a non-empty list "
                f"of strings.")
    if doc.get("url_count") != len(urls):
        fail(2, f"discovery output {path!r} url_count {doc.get('url_count')!r} "
                f"!= len(urls) {len(urls)}; internally inconsistent.")
    return rung, set(urls)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="check_linkmap.py",
        description="Gate a link map against discovery outputs and seeds.")
    parser.add_argument("--linkmap", required=True)
    parser.add_argument("--discovery", action="append", default=[],
                        help="discovery-output JSON path (repeatable)")
    args = parser.parse_args(argv)

    if not args.discovery:
        fail(2, "at least one --discovery output is required: a link map with "
                "no discovery basis cannot demonstrate coverage. Two cases "
                "land here: (1) an origin seed resolved neither llms.txt nor "
                "a sitemap -- stop loudly (rung 3 is deferred by Q19); "
                "(2) a corpus of resource seeds only -- outside V1 gate scope "
                "by recorded deferral (see link-map-format.md); route those "
                "URLs to direct docpage-digest runs instead.")

    linkmap = load_json(args.linkmap, "link map")
    if not isinstance(linkmap, dict):
        fail(2, f"link map root is a {type(linkmap).__name__}, not a JSON object.")
    unknown = set(linkmap) - LINKMAP_KEYS
    if unknown:
        fail(2, f"link map has unknown top-level keys {sorted(unknown)}.")
    missing = LINKMAP_KEYS - set(linkmap) - {"topic"}
    if missing:
        fail(2, f"link map missing required keys {sorted(missing)}.")
    if linkmap["schema"] != LINKMAP_SCHEMA:
        fail(2, f"link map schema is {linkmap['schema']!r}; this gate checks "
                f"{LINKMAP_SCHEMA!r} only.")

    seeds = linkmap["seeds"]
    if not isinstance(seeds, list) or not seeds \
            or not all(isinstance(s, str) and s for s in seeds):
        fail(2, "link map 'seeds' is not a non-empty list of strings.")
    for seed in seeds:
        normalized_seed = normalize_url(seed)
        if normalized_seed is None:
            fail(2, f"seed {seed!r} is not a normalizable http(s) URL.")
        if normalized_seed != seed:
            fail(2, f"seed {seed!r} is not in normalized form "
                    f"(expected {normalized_seed!r}); run seeds through "
                    f"parse_discovery.py --normalize-url so one resource "
                    f"cannot enter the map under two spellings.")

    bounds = linkmap["bounds"]
    if not isinstance(bounds, dict):
        fail(2, "link map 'bounds' is not an object.")
    b_unknown = set(bounds) - BOUNDS_KEYS
    if b_unknown:
        fail(2, f"link map bounds has unknown keys {sorted(b_unknown)}.")
    max_resources = bounds.get("max_resources")
    if not isinstance(max_resources, int) or isinstance(max_resources, bool) \
            or max_resources < 1:
        fail(2, f"bounds.max_resources {max_resources!r} is not a positive "
                f"integer; bounds must be declared before approval.")

    rows = linkmap["rows"]
    if not isinstance(rows, list) or not rows:
        fail(2, "link map 'rows' is not a non-empty list.")

    # provenance ground truth: url -> set of rungs it actually appeared under
    ground = {}
    for seed in seeds:
        ground.setdefault(seed, set()).add("seed")
    discovery_counts = {}
    for path in args.discovery:
        rung, urls = check_discovery_output(path, load_json(path, "discovery output"))
        discovery_counts[path] = (rung, len(urls))
        for url in urls:
            ground.setdefault(url, set()).add(rung)

    failures = Failures()
    seen = {}
    tally = {c: 0 for c in CLASSIFICATIONS}
    for index, row in enumerate(rows):
        label = f"row[{index}]"
        if not isinstance(row, dict):
            failures.add(f"{label}: not a JSON object.")
            continue
        r_unknown = set(row) - ROW_KEYS
        if r_unknown:
            failures.add(f"{label}: unknown keys {sorted(r_unknown)}.")
            continue
        r_missing = ROW_KEYS - set(row)
        if r_missing:
            failures.add(f"{label}: missing keys {sorted(r_missing)}.")
            continue
        url = row["url"]
        label = f"row[{index}] ({url!r})"
        if not isinstance(url, str) or not url:
            failures.add(f"row[{index}]: url is not a non-empty string.")
            continue
        if normalize_url(url) != url:
            failures.add(f"{label}: url is not in normalized form (expected "
                         f"{normalize_url(url)!r}); one resource must not "
                         f"appear under two spellings.")
            continue
        if url in seen:
            failures.add(f"{label}: duplicate url (first at row[{seen[url]}]); "
                         f"classification is ambiguous.")
            continue
        seen[url] = index
        if row["classification"] not in CLASSIFICATIONS:
            failures.add(f"{label}: classification {row['classification']!r} "
                         f"is not one of {list(CLASSIFICATIONS)}.")
            continue
        if not (isinstance(row["reason"], str) and row["reason"].strip()):
            failures.add(f"{label}: reason is empty; every classification "
                         f"must be argued.")
            continue
        rungs = row["rungs"]
        if not isinstance(rungs, list) or not rungs \
                or not all(r in ROW_RUNGS for r in rungs) \
                or len(set(rungs)) != len(rungs):
            failures.add(f"{label}: rungs {rungs!r} is not a non-empty "
                         f"duplicate-free subset of {list(ROW_RUNGS)}.")
            continue
        if url not in ground:
            failures.add(f"{label}: url appears in no discovery output and is "
                         f"not a seed -- a phantom row.")
            continue
        if set(rungs) != ground[url]:
            failures.add(f"{label}: rungs {sorted(rungs)} != actual provenance "
                         f"{sorted(ground[url])}.")
            continue
        tally[row["classification"]] += 1

    unclassified = [u for u in ground if u not in seen]
    if unclassified:
        failures.add(f"{len(unclassified)} discovered/seed URL(s) have no "
                     f"link-map row (unclassified): "
                     f"{', '.join(sorted(unclassified))}.")

    if tally["in-corpus"] > max_resources:
        failures.add(f"BOUNDS BREACH: {tally['in-corpus']} in-corpus rows "
                     f"exceed declared max_resources {max_resources}; the run "
                     f"must stop and re-ask the user, not proceed.")

    if failures.items:
        print(f"check_linkmap: FAILED -- {len(failures.items)} failure(s) "
              f"across {len(rows)} row(s) / {len(ground)} discovered URL(s).")
        return 1

    discovery_desc = ", ".join(
        f"{path!r} ({rung}: {count} urls)"
        for path, (rung, count) in discovery_counts.items()) or "none"
    print(
        "check_linkmap: PASS -- exercised: link map "
        f"{args.linkmap!r} ({len(rows)} rows), discovery outputs "
        f"{discovery_desc}, {len(seeds)} seed(s); checked both directions "
        f"(row->provenance, discovered->classified), rung sets exact, "
        f"classifications+reasons present, bounds "
        f"(in-corpus {tally['in-corpus']} <= max_resources {max_resources}). "
        f"Tally: {tally['in-corpus']} in-corpus, {tally['companion']} "
        f"companion, {tally['referenced-external']} referenced-external, "
        f"{tally['ignore']} ignore. Nothing outside the listed files and "
        f"fields was checked.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as exc:  # residual bug: documented exit 3, never a traceback
        sys.stderr.write(
            f"check_linkmap: ERROR: internal failure {type(exc).__name__}: "
            f"{exc}. This is a gate bug; the run is NOT clean.\n")
        sys.exit(3)
