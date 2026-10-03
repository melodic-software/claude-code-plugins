#!/usr/bin/env python3
r"""Vendor gitleaks' default rules into the regex file audit-sessions redaction reads.

Reads gitleaks `config/gitleaks.toml` from a path or an https URL, rewrites the Go RE2 syntax that
Python `re` reads differently, compiles every rule with warnings as errors, and writes
`plugins/session-flow/skills/audit-sessions/vendor/gitleaks/gitleaks-rules.json`: `rules` (id, regex,
keywords), `excluded` (id, reason), `source`, `source_version` and the `vendored` date.

Rewrites:
- a `(?i)` anywhere but the start becomes a scoped `(?i:...)` group that closes where its
  enclosing group closes, which is how far Go applies it. Python 3.11+ rejects a mid-pattern
  global flag, and 3.10 warns and applies it to the whole pattern.
- Go's `\z` becomes Python's `\Z`; 3.10 has no `\z`.
- POSIX classes inside a set (`[[:alnum:]]`) become explicit ASCII ranges.

A rule with no content regex, or one that still fails to compile or warns, is listed under
`excluded` with the reason.

Usage:
    vendor_gitleaks_rules.py <path-or-https-url> --source-version <tag> [--output <file>] [--dry-run]

Refresh on a gitleaks security release:
    python3 scripts/vendor_gitleaks_rules.py \
        https://raw.githubusercontent.com/gitleaks/gitleaks/<tag>/config/gitleaks.toml \
        --source-version <tag>

Exit: 0 written (or counted, with --dry-run); 1 the source yields no usable rule; 2 usage, an
unreadable source, or Python below 3.11 (`tomllib`).
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import re
import sys
import tempfile
import urllib.request
import warnings
from datetime import date
from pathlib import Path

MIN_PYTHON = (3, 11)
DEFAULT_OUTPUT = (
    Path(__file__).resolve().parents[1]
    / "plugins/session-flow/skills/audit-sessions/vendor/gitleaks/gitleaks-rules.json"
)
POSIX_CLASSES = {
    "alnum": "0-9A-Za-z",
    "alpha": "A-Za-z",
    "ascii": r"\x00-\x7F",
    "blank": r"\t ",
    "cntrl": r"\x00-\x1F\x7F",
    "digit": "0-9",
    "graph": "!-~",
    "lower": "a-z",
    "print": " -~",
    "punct": r"!-/:-@\[-`{-~",
    "space": r"\t\n\v\f\r ",
    "upper": "A-Z",
    "word": "0-9A-Za-z_",
    "xdigit": "0-9A-Fa-f",
}
POSIX_CLASS = re.compile(r"\[:(\w+):\]")


def _rewrite_set(pattern: str, i: int) -> tuple[int, str]:
    """Copy the set opening at `i`, expanding POSIX classes; return the index after it."""
    out = ["["]
    i += 1
    if pattern.startswith("^", i):
        out.append("^")
        i += 1
    if pattern.startswith("]", i):
        out.append("]")
        i += 1
    while i < len(pattern) and pattern[i] != "]":
        posix = POSIX_CLASS.match(pattern, i)
        if posix and posix.group(1) in POSIX_CLASSES:
            out.append(POSIX_CLASSES[posix.group(1)])
            i = posix.end()
        elif pattern[i] == "\\":
            out.append(pattern[i : i + 2])
            i += 2
        else:
            out.append(pattern[i])
            i += 1
    out.append(pattern[i : i + 1])
    return i + 1, "".join(out)


def normalize(pattern: str) -> str:
    out: list[str] = []
    # Scoped (?i: groups to close, per open group; [0] is the whole pattern.
    scoped = [0]
    i = 0
    while i < len(pattern):
        char = pattern[i]
        if char == "\\":
            pair = pattern[i : i + 2]
            out.append(r"\Z" if pair == r"\z" else pair)
            i += 2
        elif char == "[":
            i, body = _rewrite_set(pattern, i)
            out.append(body)
        elif i > 0 and pattern.startswith("(?i)", i):
            out.append("(?i:")
            scoped[-1] += 1
            i += 4
        else:
            if char == "(":
                scoped.append(0)
            elif char == ")" and len(scoped) > 1:
                out.append(")" * scoped.pop())
            out.append(char)
            i += 1
    out.append(")" * scoped[0])
    return "".join(out)


def compile_error(regex: str) -> str | None:
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        try:
            re.compile(regex)
        except (re.error, Warning) as exc:
            return f"{type(exc).__name__}: {exc}"
    return None


def vendor(config: dict) -> tuple[list[dict], list[dict]]:
    rules, excluded = [], []
    for rule in config.get("rules", []):
        if "regex" not in rule:
            excluded.append(
                {"id": rule["id"], "reason": "path-only rule: no content regex"}
            )
            continue
        regex = normalize(rule["regex"])
        error = compile_error(regex)
        if error:
            excluded.append({"id": rule["id"], "reason": error})
        else:
            rules.append(
                {"id": rule["id"], "regex": regex, "keywords": rule.get("keywords", [])}
            )
    return rules, excluded


def read_source(source: str) -> bytes:
    if source.startswith("https://"):
        with urllib.request.urlopen(source, timeout=30) as response:
            return response.read()
    return Path(source).read_bytes()


def write_atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument(
        "source", help="path or https URL of gitleaks config/gitleaks.toml"
    )
    parser.add_argument(
        "--source-version",
        required=True,
        help="gitleaks tag or commit the source is from",
    )
    parser.add_argument(
        "--output", type=Path, default=DEFAULT_OUTPUT, help="JSON file to write"
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="print the counts and write nothing"
    )
    args = parser.parse_args(argv)

    if sys.version_info < MIN_PYTHON:
        print(
            f"vendor_gitleaks_rules.py needs Python 3.11+ (tomllib); this is {platform.python_version()}",
            file=sys.stderr,
        )
        return 2
    import tomllib  # 3.11+, gated above

    try:
        config = tomllib.loads(read_source(args.source).decode("utf-8"))
    except (OSError, ValueError) as exc:
        print(f"cannot read {args.source}: {exc}", file=sys.stderr)
        return 2

    rules, excluded = vendor(config)
    print(f"{len(rules)} rules, {len(excluded)} excluded")
    if not rules:
        print("no usable rule; nothing written", file=sys.stderr)
        return 1
    if args.dry_run:
        return 0
    document = {
        "source": args.source,
        "source_version": args.source_version,
        "vendored": date.today().isoformat(),
        "rules": rules,
        "excluded": excluded,
    }
    write_atomic(args.output, json.dumps(document, indent=2) + "\n")
    print(f"wrote {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
