#!/usr/bin/env python3
"""Detect a duplicate JSON object key in a plugin or marketplace manifest.

#1492 shipped a manifest with two `"version"` members through a fully green
27-context CI suite. Nothing in the pipeline could have caught it:

  * JSON Schema (`check-jsonschema` against the plugin-manifest / marketplace
    schemas, the hygiene job's "Validate plugin manifests" / "Validate
    marketplace manifest" steps) validates the ALREADY-PARSED document — by
    the time a schema sees it, the duplicate is gone. JSON Schema has no
    vocabulary for "this key must not repeat," because a parsed JSON object
    is a mapping, and a mapping cannot represent a repeated key in the first
    place.
  * Standard JSON parsers resolve a duplicate key silently, last-wins.
    ECMA-404 leaves the behavior for a repeated name unspecified, and every
    mainstream implementation (Python's `json`, Node's `JSON.parse`, `jq`)
    converges on last-wins. `scripts/validate-plugins.sh`,
    `scripts/validate-plugin-contracts.mjs`, `scripts/generate-catalog.mjs`,
    and `scripts/check-changelog-parity.sh` (`jq -r '.version'`) all read the
    manifest this way, so every one of them reports the same last-wins value
    whether or not a duplicate is present.

So catching this needs the raw key/value pairs as the parser encounters them,
BEFORE the de-duplicating collapse into a dict. Python's stdlib exposes
exactly that seam: `json.loads(text, object_pairs_hook=...)` calls the hook
once per JSON object literal with the pairs in file order, innermost object
first. Intercepting there sees a duplicate at ANY nesting depth (top-level
`"version"`, or a repeated key buried inside `userConfig`, etc.), not only the
top level a hand-rolled line scanner would have to special-case.

See issue #1498. Scope: `plugins/*/.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json` (the same file set `check-jsonschema`
already validates in the hygiene job) by default; explicit file arguments
override the default set for testing.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Same file set the hygiene job's schema-validation steps already cover
# ("Validate plugin manifests" / "Validate marketplace manifest" in
# .github/workflows/ci.yml) — glob patterns resolved against REPO_ROOT so the
# default scope is correct regardless of the caller's cwd.
DEFAULT_GLOBS = (
    "plugins/*/.claude-plugin/plugin.json",
    ".claude-plugin/marketplace.json",
)


class _DuplicateKeyCollector:
    """`object_pairs_hook` that records duplicate keys without breaking the parse.

    Called once per JSON object literal, innermost first, with that object's
    raw ``(key, value)`` pairs in file order — before any dict collapses them.
    A key seen more than once at THIS level is recorded (each name once, in
    first-seen order) and the pairs are still folded into a normal dict
    (last-wins, the same resolution every other consumer in the pipeline
    applies) so parsing completes and outer objects keep working. Recording
    rather than raising lets one pass report every duplicate in a file
    instead of stopping at the first.
    """

    def __init__(self) -> None:
        self.duplicates: list[str] = []

    def __call__(self, pairs: list[tuple[str, object]]) -> dict[str, object]:
        counts: dict[str, int] = {}
        first_seen: list[str] = []
        for key, _value in pairs:
            if key in counts:
                counts[key] += 1
            else:
                counts[key] = 1
                first_seen.append(key)
        for key in first_seen:
            if counts[key] > 1 and key not in self.duplicates:
                self.duplicates.append(key)
        return dict(pairs)


def find_duplicate_keys(text: str) -> list[str]:
    """Return every key name that repeats within a single JSON object in
    ``text``, at any nesting depth, in first-encountered order.

    Raises ``json.JSONDecodeError`` on malformed JSON — that failure belongs
    to the schema-validation step, not this gate, so callers should let a
    parse error surface separately rather than reporting it as a duplicate.
    """
    collector = _DuplicateKeyCollector()
    json.loads(text, object_pairs_hook=collector)
    return collector.duplicates


def discover_default_files() -> list[Path]:
    paths: list[Path] = []
    for pattern in DEFAULT_GLOBS:
        for match in sorted(REPO_ROOT.glob(pattern)):
            if match.is_file() and match not in paths:
                paths.append(match)
    return paths


def _display(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "files",
        nargs="*",
        help=(
            "manifest files to check (default: every plugins/*/.claude-plugin/"
            "plugin.json plus .claude-plugin/marketplace.json)"
        ),
    )
    args = parser.parse_args(argv)

    paths = [Path(f) for f in args.files] if args.files else discover_default_files()
    if not paths:
        print(
            "error: no manifest files found to check "
            f"(looked for {', '.join(DEFAULT_GLOBS)} under {REPO_ROOT})",
            file=sys.stderr,
        )
        return 2

    failed = False
    for path in paths:
        if not path.is_file():
            print(f"error: {path} does not exist or is not a file", file=sys.stderr)
            failed = True
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as exc:
            print(f"error: could not read {_display(path)}: {exc}", file=sys.stderr)
            failed = True
            continue
        try:
            duplicates = find_duplicate_keys(text)
        except json.JSONDecodeError:
            # Malformed JSON is the schema-validation step's failure to
            # report, not this gate's -- do not double-report it here.
            continue
        if duplicates:
            failed = True
            keys = ", ".join(repr(key) for key in duplicates)
            plural = "s" if len(duplicates) != 1 else ""
            print(
                f"DUPLICATE KEY{plural}: {_display(path)} defines {keys} more "
                "than once in the same JSON object. JSON Schema validation "
                "cannot see this (it runs on the already-parsed document) and "
                "every consumer in this pipeline (json.load / JSON.parse / jq) "
                "silently keeps only the LAST value -- remove the earlier "
                "member(s) instead of keeping both.",
                file=sys.stderr,
            )

    if failed:
        return 1
    print(f"No duplicate JSON object keys found in {len(paths)} manifest file(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
