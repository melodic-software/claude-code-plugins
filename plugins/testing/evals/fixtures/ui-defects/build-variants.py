#!/usr/bin/env python3
"""Build one variant page per entry in defects.json.

Each variant is the base page with that entry's patches applied, written to
<out>/<id>/index.html beside a copy of the base page's other files. The id is
the first 12 hex digits of the page's SHA-256, so neither the path nor the
markup names the defect. The id-to-defect map goes to a separate file outside
<out>, for graders only.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import sys
from pathlib import Path

MIN_PYTHON = (3, 8)
HERE = Path(__file__).resolve().parent
ID_PATTERN = re.compile(r"^[0-9a-f]{12}$")


def apply_patches(base: str, entry: dict) -> str:
    page = base
    for patch in entry["patches"]:
        hits = page.count(patch["find"])
        if hits != 1:
            raise SystemExit(
                f"{entry['id']}: patch anchor matched {hits} times, expected 1: {patch['find']!r}"
            )
        page = page.replace(patch["find"], patch["replace"])
    return page


def clear_output(out: Path) -> None:
    if not out.exists():
        return
    for child in out.iterdir():
        if not (child.is_dir() and ID_PATTERN.match(child.name)):
            raise SystemExit(f"refusing to clear {out}: unexpected entry {child.name}")
    for child in out.iterdir():
        shutil.rmtree(child)


def build(defects_path: Path, out: Path, map_path: Path) -> dict:
    spec = json.loads(defects_path.read_text(encoding="utf-8"))
    base_path = defects_path.parent / spec["base"]
    site = base_path.parent
    base = base_path.read_text(encoding="utf-8")
    assets = sorted(p for p in site.rglob("*") if p.is_file() and p != base_path)

    # Build into a staging sibling and swap it in only after every variant
    # succeeds, so a failed build leaves the previous variants and map intact.
    staging = out.with_name(out.name + ".tmp")
    shutil.rmtree(staging, ignore_errors=True)
    mapping = {}
    try:
        for entry in spec["defects"]:
            page = apply_patches(base, entry).encode("utf-8")
            variant_id = hashlib.sha256(page).hexdigest()[:12]
            if variant_id in mapping:
                raise SystemExit(
                    f"{entry['id']}: same page as {mapping[variant_id]['id']}"
                )
            target = staging / variant_id
            target.mkdir(parents=True)
            (target / "index.html").write_bytes(page)
            for asset in assets:
                dest = target / asset.relative_to(site)
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(asset.read_bytes())
            mapping[variant_id] = {"id": entry["id"], "name": entry["name"]}
        clear_output(out)
        if out.exists():
            out.rmdir()
        staging.mkdir(parents=True, exist_ok=True)
        staging.rename(out)
    finally:
        shutil.rmtree(staging, ignore_errors=True)

    map_path.write_bytes(
        (json.dumps(mapping, indent=2, sort_keys=True) + "\n").encode("utf-8")
    )
    return mapping


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--defects", type=Path, default=HERE / "defects.json")
    parser.add_argument("--out", type=Path, default=HERE / "variants")
    parser.add_argument("--map", type=Path, default=HERE / "variant-map.json")
    args = parser.parse_args()
    if args.out.resolve() in args.map.resolve().parents:
        raise SystemExit("--map must not be inside --out")
    mapping = build(args.defects, args.out, args.map)
    print(f"wrote {len(mapping)} variants to {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
