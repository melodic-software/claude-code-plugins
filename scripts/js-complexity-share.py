#!/usr/bin/env python3
"""Share of production JavaScript functions at cyclomatic complexity 20 or above.

    js-complexity-share.py [--registry FILE]

Run from the repository root. Prints one line,
`lizard=<version> files=<n> functions=<n> over=<n> share=<percent>`, which the
`js-complexity-share` row of .performance/ratchets.json reads (`share`, two
decimals). 20 is the code-metrics plugin's cyclomatic reference (ISO/IEC
5055:2021 section 8.2.117), and lizard is its collector for the lane.

The scope is the one the slope measurement behind this counter used, so the
number stays comparable with it:

- tracked .js .jsx .mjs .cjs files, outside node_modules, vendor, dist and
  build directories;
- vendored files dropped: .github/standards/** and any file whose first 600
  bytes say SYNC-MANAGED FILE, @generated or DO NOT EDIT;
- copies counted once, walking paths outside plugins/ first, then in order:
  byte-identical files, and files the cross-plugin source registry sanctions
  (a plain line is plugins/<plugin>/<line>, a cluster line
  `<canonical> -> <member glob>...` is one copy set);
- test files dropped: a directory named test, tests, __tests__, fixtures,
  evals or testdata, or a name containing .test. or .spec.

Exit 0 with the line printed; 2 when lizard is missing or fails, or measured
no function, because a share of nothing would pass any ceiling.
"""

from __future__ import annotations

import argparse
import csv
import fnmatch
import hashlib
import io
import os
import re
import shutil
import subprocess
import sys

MIN_PYTHON = (3, 9)
EXTENSIONS = (".js", ".jsx", ".mjs", ".cjs")
EXCLUDED_DIRS = {"node_modules", "vendor", "dist", "build"}
TEST_DIRS = {"test", "tests", "__tests__", "fixtures", "evals", "testdata"}
TEST_NAME = re.compile(r"\.test\.|\.spec\.")
VENDORED_MARKERS = ("SYNC-MANAGED FILE", "@generated", "DO NOT EDIT")
REFERENCE = 20


def fail(message: str) -> int:
    print(f"js-complexity-share: {message}", file=sys.stderr)
    return 2


def read_registry(path: str) -> tuple[set[str], list[tuple[str, list[str]]]]:
    plain: set[str] = set()
    clusters: list[tuple[str, list[str]]] = []
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if "->" in line:
                canonical, members = line.split("->", 1)
                clusters.append((canonical.strip(), members.split()))
            else:
                plain.add(line)
    return plain, clusters


def registry_key(rel: str, plain: set[str], clusters) -> str | None:
    for canonical, members in clusters:
        if rel == canonical or any(fnmatch.fnmatchcase(rel, m) for m in members):
            return "cluster:" + canonical
    parts = rel.split("/")
    if len(parts) > 2 and parts[0] == "plugins" and "/".join(parts[2:]) in plain:
        return "plain:" + "/".join(parts[2:])
    return None


def is_test(rel: str) -> bool:
    parts = rel.split("/")
    return bool(TEST_DIRS & set(parts[:-1])) or bool(TEST_NAME.search(parts[-1]))


def production_files(registry: str) -> list[str]:
    listed = subprocess.run(
        ["git", "ls-files", "-z"], capture_output=True, check=True
    ).stdout.decode("utf-8")
    candidates = [
        rel
        for rel in listed.split("\0")
        if rel.endswith(EXTENSIONS)
        and not EXCLUDED_DIRS & set(rel.split("/")[:-1])
        and not rel.startswith(".github/standards/")
        and os.path.isfile(rel)
    ]
    candidates.sort(key=lambda rel: (rel.startswith("plugins/"), rel))
    plain, clusters = read_registry(registry)
    seen: set[str] = set()
    kept: list[str] = []
    for rel in candidates:
        with open(rel, "rb") as handle:
            data = handle.read()
        head = data[:600].decode("utf-8", "replace")
        if any(marker in head for marker in VENDORED_MARKERS):
            continue
        digest = hashlib.sha1(data).hexdigest()
        key = registry_key(rel, plain, clusters)
        if digest in seen or (key and key in seen):
            continue
        seen.add(digest)
        if key:
            seen.add(key)
        # Copies collapse across test and production files alike, as in the
        # measurement; the test split comes after.
        if not is_test(rel):
            kept.append(rel)
    return kept


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--registry", default="scripts/cross-plugin-source-registry.txt"
    )
    args = parser.parse_args()
    lizard = shutil.which("lizard")
    if not lizard:
        return fail("lizard is not on PATH (pinned in .github/requirements-ci.txt).")
    version = subprocess.run(
        [lizard, "--version"], capture_output=True, text=True, check=False
    ).stdout.strip()
    files = production_files(args.registry)
    if not files:
        return fail("no production JavaScript file in scope.")
    # -i -1: exit 0 whatever lizard's own warning threshold says, so a nonzero
    # exit means lizard failed.
    result = subprocess.run(
        [lizard, "--csv", "-i", "-1", *files],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return fail(f"lizard exited {result.returncode}: {result.stderr.strip()}")
    values = [
        int(record[1])
        for record in csv.reader(io.StringIO(result.stdout))
        if len(record) >= 11 and record[1].isdigit()
    ]
    if not values:
        return fail("lizard measured no function.")
    over = sum(1 for value in values if value >= REFERENCE)
    print(
        f"lizard={version or 'unknown'} files={len(files)} functions={len(values)} "
        f"over={over} share={100 * over / len(values):.2f}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
