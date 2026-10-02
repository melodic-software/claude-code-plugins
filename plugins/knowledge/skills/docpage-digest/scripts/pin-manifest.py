#!/usr/bin/env python3
"""Write or check a docpage-digest slice's pin manifest.

Usage:
  python3 pin-manifest.py <work-root>          write verification/pin-manifest.json
  python3 pin-manifest.py <work-root> --check  compare the tree with that manifest

The frozen set is every source.* file at the work root, SOURCES.md, and every
digests/*.md file. Writing refuses a slice missing any of the three. --check
exits 1 and names each path whose hash differs, is missing, or is new: that is
a BLOCKED arm, not a content finding. Stdlib only. Python 3.9+.
"""

from __future__ import annotations

import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

SCHEMA = "docpage-pin/v1"
MANIFEST = Path("verification") / "pin-manifest.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for block in iter(lambda: fh.read(1 << 16), b""):
            digest.update(block)
    return digest.hexdigest()


def frozen_paths(root: Path, complete: bool) -> list:
    sources = sorted(p for p in root.glob("source.*") if p.is_file())
    inventory = root / "SOURCES.md"
    digests = sorted(p for p in (root / "digests").glob("*.md") if p.is_file())
    missing = []
    if not sources:
        missing.append("source.*")
    if not inventory.is_file():
        missing.append("SOURCES.md")
    if not digests:
        missing.append("digests/*.md")
    if missing and complete:
        raise ValueError("nothing to pin, missing: " + ", ".join(missing))
    return [*sources, *([inventory] if inventory.is_file() else []), *digests]


def hashes(root: Path, complete: bool) -> dict:
    return {p.relative_to(root).as_posix(): sha256(p) for p in frozen_paths(root, complete)}


def write(root: Path) -> int:
    files = hashes(root, complete=True)
    manifest = {
        "schema": SCHEMA,
        "pinned_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "pinned_on": "agent-reported-completion",
        "files": [{"path": path, "sha256": digest} for path, digest in files.items()],
    }
    out = root / MANIFEST
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"PINNED {len(files)} files -> {MANIFEST.as_posix()}")
    return 0


def check(root: Path) -> int:
    path = root / MANIFEST
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as err:
        print(f"pin-manifest: ERROR: cannot read {MANIFEST.as_posix()}: {err}", file=sys.stderr)
        return 2
    if manifest.get("schema") != SCHEMA:
        print(f"pin-manifest: ERROR: schema is not {SCHEMA}", file=sys.stderr)
        return 2
    pinned = {entry["path"]: entry["sha256"] for entry in manifest.get("files", [])}
    current = hashes(root, complete=False)
    drift = [f"changed {p}" for p in pinned if p in current and current[p] != pinned[p]]
    drift += [f"missing {p}" for p in pinned if p not in current]
    drift += [f"new {p}" for p in current if p not in pinned]
    for line in drift:
        print(f"BLOCKED: {line}")
    if drift:
        return 1
    print(f"MATCH {len(pinned)} files")
    return 0


def main(argv=None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if not args or len(args) > 2 or (len(args) == 2 and args[1] != "--check"):
        print("usage: pin-manifest.py <work-root> [--check]", file=sys.stderr)
        return 2
    root = Path(args[0])
    if not root.is_dir():
        print(f"pin-manifest: ERROR: not a directory: {root}", file=sys.stderr)
        return 2
    try:
        return check(root) if len(args) == 2 else write(root)
    except ValueError as err:
        print(f"pin-manifest: ERROR: {err}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
