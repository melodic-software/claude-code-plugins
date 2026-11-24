#!/usr/bin/env python3
"""The opt-in size check over a change-scoped size report.

  size_check.py add --config <resolved.json> [--registry <file>]... <report.json>
                                     add `size_check` in place; exit 0 pass, 1 fail, 2 cannot decide
  size_check.py render <report.json> print the markdown section for it

The rule is the resolved `size.check`:

  report               nothing fails (the default)
  crossing             a changed file fails when its non-blank lines were below
                       `size.file_lines` at the base and are at or above it now
  crossing-or-growth   a crossing fails, and so does a file already at or above
                       the reference at the base whose count grew

Under `crossing`, a file already over the reference that grew is listed and
does not fail. Both counts use the bundled counter's rule (a line holding a
non-whitespace byte), whichever collector filled the report: the head count on
the working-tree file, the base count on the file as the base commit holds it,
under its earlier name when git sees a rename, and 0 when the base has no such
file. Every copy a replica row stands for is checked on its own. A `file_lines`
run row that did not measure its lane leaves the check undecided.

A file a registry's cluster line `<canonical> -> <member>...` names as a member
(and that is not the canonical itself) is a generated copy measured at its
canonical: a row it would have produced carries `canonical` and never fails.
The canonical keeps the rule. Members are literal root-relative paths or
gitignore-style globs, and the first matching line in file order names the
canonical.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "scripts"))
from pathglob import matches as glob_matches  # noqa: E402

CLUSTER_MARKER = " -> "
RULES = ("report", "crossing", "crossing-or-growth")
GUIDANCE = (
    "Split each failing file along a real responsibility boundary, so each part "
    "holds one concern. Do not delete code or squash lines to get under the "
    "number. Where a file has no such boundary, raise `size.file_lines` or add "
    "the file to `scope.exclude` in the repository's code-metrics config, with "
    "a comment giving the reason."
)


class CannotDecide(RuntimeError):
    """The check has no base or no count to decide from."""


def _git(root: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", root, *args], capture_output=True, check=False)


def non_blank(data: bytes) -> int:
    lines = data.split(b"\n")
    if lines and lines[-1] == b"":
        lines.pop()
    return sum(1 for line in lines if line.strip())


def renames(root: str, base: str) -> dict[str, str]:
    result = _git(root, "diff", "-M", "--name-status", "-z", base, "--")
    if result.returncode != 0:
        raise CannotDecide(
            result.stderr.decode(errors="replace").strip() or "git diff failed"
        )
    fields = result.stdout.decode("utf-8", "surrogateescape").split("\0")
    found: dict[str, str] = {}
    i = 0
    while i < len(fields) and fields[i]:
        status = fields[i]
        if status[:1] in ("R", "C"):
            found[fields[i + 2]] = fields[i + 1]
            i += 3
        else:
            i += 2
    return found


def base_count(root: str, base: str, path: str) -> int:
    probe = _git(root, "rev-parse", "--verify", "--quiet", f"{base}:{path}")
    if probe.returncode != 0:
        return 0
    blob = _git(root, "cat-file", "blob", probe.stdout.decode().strip())
    if blob.returncode != 0:
        raise CannotDecide(f"cannot read {path} at {base}")
    return non_blank(blob.stdout)


def head_count(root: str, path: str) -> int:
    try:
        with open(os.path.join(root, path), "rb") as handle:
            return non_blank(handle.read())
    except OSError as exc:
        raise CannotDecide(f"cannot read {path}: {exc}") from exc


def _unmeasured(document: dict) -> list[str]:
    return [
        f"{row.get('lane')} ({row.get('status')}: {row.get('reason')})"
        for row in document.get("run") or []
        if row.get("measure") == "file_lines"
        and row.get("status") not in ("ok", "not-applicable")
    ]


def _files(row: dict) -> list[str]:
    copies = (row.get("replicas") or {}).get("files") or []
    return list(dict.fromkeys([row["file"], *copies]))


def _clean(path: str) -> str:
    return path.replace("\\", "/").lstrip("/")


def read_clusters(paths: list[str]) -> list[tuple[str, list[str]]]:
    clusters: list[tuple[str, list[str]]] = []
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            for raw in handle:
                line = raw.strip()
                if line.startswith("#") or CLUSTER_MARKER not in line:
                    continue
                canonical, _, rest = line.partition(CLUSTER_MARKER)
                clusters.append(
                    (_clean(canonical.strip()), [_clean(t) for t in rest.split()])
                )
    return clusters


def canonical_of(path: str, clusters: list[tuple[str, list[str]]]) -> str | None:
    path = _clean(path)
    for canonical, members in clusters:
        if path != canonical and any(glob_matches(m, path) for m in members):
            return canonical
    return None


def _reference(document: dict) -> tuple[float | None, str]:
    for entry in document.get("thresholds") or []:
        if entry.get("measure") == "file_lines":
            return entry.get("reference"), entry.get("layer") or "bundled default"
    return None, "bundled default"


def add(
    document: dict, config: dict, clusters: list[tuple[str, list[str]]] | None = None
) -> int:
    clusters = clusters or []
    rule = (config.get("size") or {}).get("check") or "report"
    layer = (config.get("_layers") or {}).get("size.check", "bundled default")
    reference, reference_layer = _reference(document)
    scope = document.get("scope") or {}
    block = {
        "rule": rule,
        "layer": layer,
        "reference": reference,
        "reference_layer": reference_layer,
        "base": scope.get("base"),
        "rows": [],
        "failed": 0,
    }
    document["size_check"] = block
    if rule == "report":
        return 0
    if rule not in RULES:
        raise CannotDecide(
            f"size.check must be one of {', '.join(RULES)}, got {rule!r}"
        )
    root = (document.get("root") or {}).get("path")
    if scope.get("mode") != "change" or not scope.get("base") or not root:
        raise CannotDecide(
            "--check compares the change with its base, so it needs the change scope: "
            "drop --all and explicit paths (use --base <ref> to name the base)"
        )
    if reference is None:
        raise CannotDecide("size.file_lines is null, so there is no reference to cross")
    unmeasured = _unmeasured(document)
    if unmeasured:
        raise CannotDecide(
            "file_lines was not measured for every file in scope: "
            + "; ".join(unmeasured)
        )
    moved = renames(root, scope["base"])
    files = [
        path
        for row in document.get("measures") or []
        if row.get("function") is None and row.get("file")
        for path in _files(row)
    ]
    for path in dict.fromkeys(files):
        head = head_count(root, path)
        if head < reference:
            continue
        old = moved.get(path, path)
        base = base_count(root, scope["base"], old)
        if base < reference:
            kind, fails = "crossed", True
        elif head > base:
            kind, fails = "grew", rule == "crossing-or-growth"
        else:
            continue
        row = {
            "file": path,
            "base_file": old,
            "base_lines": base,
            "head_lines": head,
            "kind": kind,
            "fails": fails,
        }
        canonical = canonical_of(path, clusters)
        if canonical:
            row.update(canonical=canonical, fails=False)
        block["rows"].append(row)
    block["rows"].sort(key=lambda r: (not r["fails"], r["file"]))
    block["failed"] = sum(1 for r in block["rows"] if r["fails"])
    return 1 if block["failed"] else 0


def render(document: dict) -> str:
    block = document.get("size_check")
    if not block:
        return ""
    lines = ["", "## Size check", ""]
    if block["rule"] == "report":
        lines.append(
            f"`size.check` is `report` ({block['layer']}): nothing fails. Set it to "
            "`crossing` or `crossing-or-growth` in a config layer to turn the check on."
        )
        return "\n".join(lines)
    reference = block["reference"]
    lines.append(
        f"Rule `{block['rule']}` ({block['layer']}); `size.file_lines` {reference} "
        f"({block['reference_layer']}); base {block['base']}."
    )
    if block["rows"]:
        lines += ["", "| File | Base | Head | Result |", "|---|---|---|---|"]
        for r in block["rows"]:
            name = (
                r["file"]
                if r["base_file"] == r["file"]
                else f"{r['file']} (was {r['base_file']})"
            )
            if r.get("canonical"):
                result = f"reported: a copy, measured at its canonical {r['canonical']}"
            elif r["kind"] == "crossed":
                result = "fails: crossed the reference"
            elif r["fails"]:
                result = "fails: already over, grew"
            else:
                result = "reported: already over, grew"
            lines.append(
                f"| {name} | {r['base_lines']} | {r['head_lines']} | {result} |"
            )
    lines.append("")
    if block["failed"]:
        lines.append(
            f"FAIL: {block['failed']} file(s) failed the size check against "
            f"`size.file_lines` {reference}. {GUIDANCE}"
        )
    else:
        lines.append(
            f"PASS: no changed file failed the size check against `size.file_lines` {reference}."
        )
    return "\n".join(lines)


def main(argv: list[str]) -> int:
    try:
        pairs = argv[3:-1]
        if (
            len(argv) >= 4
            and argv[:2] == ["add", "--config"]
            and len(pairs) % 2 == 0
            and all(flag == "--registry" for flag in pairs[::2])
        ):
            with open(argv[2], encoding="utf-8") as handle:
                config = json.load(handle)
            clusters = read_clusters(pairs[1::2])
            report = argv[-1]
            with open(report, encoding="utf-8") as handle:
                document = json.load(handle)
            try:
                status = add(document, config, clusters)
            except CannotDecide as exc:
                print(f"size_check.py: {exc}", file=sys.stderr)
                status = 2
            with open(report, "w", encoding="utf-8") as handle:
                json.dump(document, handle, indent=2)
            return status
        if len(argv) == 2 and argv[0] == "render":
            with open(argv[1], encoding="utf-8") as handle:
                print(render(json.load(handle)))
            return 0
    except (OSError, json.JSONDecodeError) as exc:
        print(f"size_check.py: {exc}", file=sys.stderr)
        return 2
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
