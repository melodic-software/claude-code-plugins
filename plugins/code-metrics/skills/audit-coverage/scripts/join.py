#!/usr/bin/env python3
"""Join parsed coverage artifacts to the functions in scope (design T7).

    join.py --complexity <complexity.json> --scope <scope-files.txt>
            --root <repo root> [--artifacts <format>:<parsed.json>]...
            [--prefix-strip <prefix>]... [--searched <path>]...
            [--measures-out <rows.jsonl>] [--run-out <run.jsonl>]
    join.py --self-test

Prints `{"measures": [...], "run": [...]}` to stdout; the two `--*-out`
options write the same rows as JSON lines for `report.py assemble`.

`--complexity` is one `code-metrics/v1` document from the sibling
`audit-complexity` skill. Its per-function rows supply the cyclomatic
complexity and the line range; `--artifacts` are the mappings the parsers
under `../../../scripts/parsers/` print, each tagged with the format it came
from, so a reason can name it.

What comes out:

  * one row per file in scope that an artifact covers: `coverage_pct`,
    `lines_executable`, `lines_hit`.
  * one row per function that has a cyclomatic row with a real end line:
    `coverage_pct`, `cyclomatic`, `crap`, plus `cov_source` and `hit`.
    `cov_source` is `artifact-region` when the artifact carried the function's
    own region and `line-range` when the range came from the complexity
    collector, in which case the ranges of nested functions are subtracted
    from the parent first. A function-hit flag of 0 reports 0 percent, because
    a declaration line that ran at import is not the function running. A
    function with no executable lines reports `coverage_pct: null` and
    `crap: null`, never 0, which would be a fabricated maximal CRAP.
  * one `<lane>/coverage` and one `<lane>/crap` run row per lane. A lane whose
    files are missing from every artifact is `unavailable` and says which
    paths were searched; a lane matched in part carries
    `partial, N of M scope files present in the artifacts`, so a total miss
    never reads as "no executable lines". A lane whose cyclomatic collector
    reports no function end lines (Bash in V1) gets a `not-applicable` CRAP
    row rather than a null that would hide the whole lane.

Path normalization runs on both sides before the join: forward slashes, `./`
removed, then the repository root and each `coverage.path_prefix_strip`
prefix, then a component-wise suffix match (an absolute `SF:` path or a
Cobertura `<source>` prefix), then a basename match when exactly one file in
scope carries that basename (a Go profile names files by module path).

Exit 0 on success, 2 on a usage error or an unreadable input.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import sys
from typing import Any

MIN_PYTHON = (3, 9)
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

_spec = importlib.util.spec_from_file_location(
    "crap", os.path.join(SCRIPT_DIR, "crap.py")
)
assert _spec is not None and _spec.loader is not None
crap_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(crap_module)

NO_END_LINES = "the resolved collector reports no function end lines"


def normalize(path: str) -> str:
    """Forward slashes, no leading `./`, no doubled separators."""
    text = str(path).strip().replace("\\", "/")
    while text.startswith("./"):
        text = text[2:]
    while "//" in text:
        text = text.replace("//", "/")
    return text


def _candidates(path: str, root: str, prefixes: list[str]) -> list[str]:
    out = [path]
    for prefix in [p for p in prefixes if p] + ([root] if root else []):
        stripped = normalize(prefix).rstrip("/")
        if stripped and path.startswith(stripped + "/"):
            out.append(path[len(stripped) + 1 :])
    return out


def resolve(path: str, scope: list[str], root: str, prefixes: list[str]) -> str | None:
    """The file in `scope` an artifact path refers to, or `None`."""
    candidates = _candidates(normalize(path), root, prefixes)
    for candidate in candidates:
        if candidate in scope:
            return candidate
    best: tuple[int, str] | None = None
    for candidate in candidates:
        parts = candidate.split("/")
        for target in scope:
            wanted = target.split("/")
            if len(wanted) <= len(parts) and parts[-len(wanted) :] == wanted:
                if best is None or len(wanted) > best[0]:
                    best = (len(wanted), target)
    if best:
        return best[1]
    for candidate in candidates:
        parts = candidate.split("/")
        for target in scope:
            wanted = target.split("/")
            if len(parts) < len(wanted) and wanted[-len(parts) :] == parts:
                if best is None or len(parts) > best[0]:
                    best = (len(parts), target)
    if best:
        return best[1]
    base = candidates[0].rsplit("/", 1)[-1]
    matches = [t for t in scope if t.rsplit("/", 1)[-1] == base]
    return matches[0] if len(matches) == 1 else None


def _lines(raw: Any) -> dict[int, int]:
    out: dict[int, int] = {}
    for key, value in (raw or {}).items():
        try:
            out[int(key)] = int(value)
        except (TypeError, ValueError):
            continue
    return out


def merge_artifacts(
    artifacts: list[dict[str, Any]], scope: list[str], root: str, prefixes: list[str]
) -> tuple[dict[str, dict], list[str]]:
    """Fold every parsed artifact onto the files in scope. A file covered by
    two artifacts keeps the larger hit count per line, so a line is never
    counted twice."""
    merged: dict[str, dict] = {}
    unmatched: list[str] = []
    for artifact in artifacts:
        fmt = artifact.get("format") or "unknown"
        for raw_path, section in (artifact.get("files") or {}).items():
            target = resolve(raw_path, scope, root, prefixes)
            if target is None:
                unmatched.append(normalize(raw_path))
                continue
            entry = merged.setdefault(
                target, {"lines": {}, "functions": [], "formats": []}
            )
            if fmt not in entry["formats"]:
                entry["formats"].append(fmt)
            for number, hits in _lines(section.get("lines")).items():
                entry["lines"][number] = max(entry["lines"].get(number, 0), hits)
            for function in section.get("functions") or []:
                entry["functions"].append(
                    {
                        "name": function.get("name"),
                        "start_line": function.get("start_line"),
                        "end_line": function.get("end_line"),
                        "hit": function.get("hit"),
                        "lines": _lines(function.get("lines"))
                        if function.get("lines")
                        else None,
                    }
                )
    return merged, unmatched


def _coverage(lines: dict[int, int]) -> tuple[int, int, float | None]:
    executable = len(lines)
    hit = sum(1 for value in lines.values() if value > 0)
    if executable == 0:
        return 0, 0, None
    return executable, hit, round(100.0 * hit / executable, 2)


def _match_function(
    functions: list[dict[str, Any]], name: str | None, start_line: int | None
) -> dict[str, Any] | None:
    tail = (name or "").rsplit(".", 1)[-1]
    for candidate in functions:
        if candidate.get("name") == name:
            return candidate
    for candidate in functions:
        if (candidate.get("name") or "").rsplit(".", 1)[-1] == tail and tail:
            return candidate
    for candidate in functions:
        if start_line is not None and candidate.get("start_line") == start_line:
            return candidate
    return None


def _cyclomatic_rows(document: dict[str, Any]) -> list[dict[str, Any]]:
    rows = []
    for row in document.get("measures") or []:
        values = row.get("values") or {}
        if row.get("function") and values.get("cyclomatic") is not None:
            rows.append(row)
    return rows


def _nested(rows: list[dict[str, Any]], start: int, end: int) -> set[int]:
    covered: set[int] = set()
    for row in rows:
        inner_start, inner_end = row.get("start_line"), row.get("end_line")
        if inner_start is None or inner_end is None:
            continue
        if inner_start < start or inner_end > end:
            continue
        if inner_start == start and inner_end == end:
            continue
        covered.update(range(inner_start, inner_end + 1))
    return covered


def _function_row(
    row: dict[str, Any], entry: dict[str, Any], siblings: list[dict[str, Any]]
) -> dict[str, Any]:
    start, end = row["start_line"], row["end_line"]
    matched = _match_function(entry["functions"], row.get("function"), start)
    hit = matched.get("hit") if matched else None
    if matched and matched.get("lines"):
        region = dict(matched["lines"])
        source = "artifact-region"
    elif (
        matched
        and matched.get("start_line") is not None
        and matched.get("end_line") is not None
    ):
        region = {
            number: hits
            for number, hits in entry["lines"].items()
            if matched["start_line"] <= number <= matched["end_line"]
        }
        source = "artifact-region"
    else:
        skip = _nested(siblings, start, end)
        region = {
            number: hits
            for number, hits in entry["lines"].items()
            if start <= number <= end and number not in skip
        }
        source = "line-range"
    executable, hits, percent = _coverage(region)
    if percent is not None and hit == 0:
        percent = 0.0
    comp = row["values"]["cyclomatic"]
    score = crap_module.crap(comp, percent)
    return {
        "file": row["file"],
        "function": row["function"],
        "start_line": start,
        "end_line": end,
        "lane": row.get("lane"),
        "values": {
            "coverage_pct": percent,
            "lines_executable": executable,
            "lines_hit": hits,
            "cyclomatic": comp,
            "crap": None if score is None else round(score, 3),
        },
        "cov_source": source,
        "hit": hit,
    }


def join(
    complexity: dict[str, Any],
    artifacts: list[dict[str, Any]],
    scope: list[str],
    root: str = "",
    prefixes: list[str] | None = None,
    searched: list[str] | None = None,
) -> dict[str, list[dict[str, Any]]]:
    """The whole join: coverage rows plus the run rows that explain them."""
    prefixes = prefixes or []
    scope = [normalize(path) for path in scope]
    merged, _ = merge_artifacts(artifacts, scope, root, prefixes)
    cyclomatic = _cyclomatic_rows(complexity)
    lane_of: dict[str, str] = {}
    for row in complexity.get("measures") or []:
        if row.get("file"):
            lane_of.setdefault(normalize(row["file"]), row.get("lane") or "*")
    lanes: dict[str, list[str]] = {}
    for path in scope:
        lanes.setdefault(lane_of.get(path, "*"), []).append(path)

    measures: list[dict[str, Any]] = []
    for path in scope:
        entry = merged.get(path)
        if not entry:
            continue
        executable, hits, percent = _coverage(entry["lines"])
        measures.append(
            {
                "file": path,
                "function": None,
                "start_line": None,
                "end_line": None,
                "lane": lane_of.get(path, "*"),
                "values": {
                    "coverage_pct": percent,
                    "lines_executable": executable,
                    "lines_hit": hits,
                },
                "cov_source": "artifact-region",
                "hit": None,
                "labels": ["file-level"],
            }
        )
        siblings = [
            row
            for row in cyclomatic
            if normalize(row["file"]) == path and row.get("end_line") is not None
        ]
        for row in siblings:
            joined = dict(row)
            joined["file"] = path
            measures.append(_function_row(joined, entry, siblings))

    formats: list[str] = []
    for artifact in artifacts:
        name = artifact.get("format") or "unknown"
        if name not in formats:
            formats.append(name)
    where = ", ".join(searched or []) or "nothing"
    run: list[dict[str, Any]] = []
    for lane in sorted(lanes):
        files = lanes[lane]
        matched = [path for path in files if path in merged]
        if not artifacts:
            status, reason = (
                "unavailable",
                f"no coverage artifact found; searched: {where}",
            )
        elif not matched:
            status = "unavailable"
            reason = (
                f"partial, 0 of {len(files)} scope files present in the artifacts "
                f"({', '.join(formats)} read)"
            )
        elif len(matched) < len(files):
            status = "ok"
            reason = (
                f"partial, {len(matched)} of {len(files)} scope files present "
                "in the artifacts"
            )
        else:
            status, reason = "ok", None
        collector = (
            ", ".join(
                sorted({fmt for path in matched for fmt in merged[path]["formats"]})
            )
            or None
        )
        run.append(
            {
                "lane": lane,
                "measure": "coverage",
                "collector": collector,
                "status": status,
                "reason": reason,
            }
        )
        lane_cyclomatic = [
            row for row in cyclomatic if (row.get("lane") or "*") == lane
        ]
        if not lane_cyclomatic:
            crap_status = "not-applicable"
            crap_reason = "no function-level cyclomatic rows in scope for this lane"
        elif all(row.get("end_line") is None for row in lane_cyclomatic):
            crap_status, crap_reason = "not-applicable", NO_END_LINES
        elif status != "ok":
            crap_status, crap_reason = status, reason
        else:
            crap_status, crap_reason = "ok", reason
        run.append(
            {
                "lane": lane,
                "measure": "crap",
                "collector": collector if crap_status == "ok" else None,
                "status": crap_status,
                "reason": crap_reason,
            }
        )
    if not run:
        for measure in ("coverage", "crap"):
            run.append(
                {
                    "lane": "*",
                    "measure": measure,
                    "collector": None,
                    "status": "unavailable",
                    "reason": (
                        "no file in scope carried a measurable row; "
                        f"coverage artifacts searched: {where}"
                    ),
                }
            )
    return {"measures": measures, "run": run}


def _read_json(path: str) -> Any:
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def _read_artifact(spec: str) -> dict[str, Any]:
    fmt, separator, path = spec.partition(":")
    if not separator:
        fmt, path = "unknown", spec
    payload = _read_json(path)
    if not isinstance(payload, dict):
        raise ValueError(f"{path}: a parsed artifact must be a JSON object")
    return {"format": fmt, "files": payload}


def _write_jsonl(path: str | None, rows: list[dict[str, Any]]) -> None:
    if not path:
        return
    with open(path, "w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row) + "\n")


def _outer(artifact: dict[str, Any], lines: dict[int, int]) -> dict[str, Any]:
    """The `outer` row of a one-file join over `lines`, for the self-test."""
    complexity = {
        "measures": [
            {
                "function": "outer",
                "start_line": 1,
                "end_line": 10,
                "values": {"cyclomatic": 4},
            },
            {
                "function": "outer.inner",
                "start_line": 4,
                "end_line": 6,
                "values": {"cyclomatic": 1},
            },
        ]
    }
    for row in complexity["measures"]:
        row.update({"file": "src/a.py", "lane": "python"})
    artifact["files"]["src/a.py"]["lines"] = lines
    result = join(complexity, [artifact], ["src/a.py"])
    return [r for r in result["measures"] if r.get("function") == "outer"][0]


def self_test() -> int:
    """The properties the join must hold, checked without a fixture tree."""
    lines = {1: 1, 2: 0, 4: 1, 5: 1, 6: 1, 8: 0, 10: 0}
    section: dict[str, Any] = {"functions": None}
    outer = _outer({"format": "lcov", "files": {"src/a.py": section}}, lines)
    assert outer["cov_source"] == "line-range", outer
    assert outer["values"]["lines_executable"] == 4, outer  # nested 4..6 subtracted
    assert outer["values"]["lines_hit"] == 1, outer

    flag = {"name": "outer", "start_line": 1, "end_line": None, "hit": 0, "lines": None}
    outer = _outer(
        {"format": "lcov", "files": {"src/a.py": {"functions": [flag]}}}, lines
    )
    assert outer["values"]["coverage_pct"] == 0, outer
    assert outer["values"]["crap"] == 20, outer

    region = {
        "name": "outer",
        "start_line": 2,
        "end_line": 10,
        "hit": 1,
        "lines": {2: 1, 8: 1},
    }
    outer = _outer(
        {"format": "coverage_py_json", "files": {"src/a.py": {"functions": [region]}}},
        lines,
    )
    assert outer["cov_source"] == "artifact-region", outer
    assert outer["values"]["coverage_pct"] == 100.0, outer

    outer = _outer({"format": "lcov", "files": {"src/a.py": {"functions": None}}}, {})
    assert outer["values"]["coverage_pct"] is None, outer
    assert outer["values"]["crap"] is None, outer
    print("join.py --self-test: ok")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="join.py")
    parser.add_argument("--complexity")
    parser.add_argument("--scope")
    parser.add_argument("--root", default="")
    parser.add_argument("--artifacts", action="append", default=[])
    parser.add_argument("--prefix-strip", action="append", default=[])
    parser.add_argument("--searched", action="append", default=[])
    parser.add_argument("--measures-out")
    parser.add_argument("--run-out")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)
    if args.self_test:
        return self_test()
    if not args.complexity or not args.scope:
        print(
            "usage: join.py --complexity <doc> --scope <files> [...]", file=sys.stderr
        )
        return 2
    with open(args.scope, encoding="utf-8") as handle:
        scope = [line.strip() for line in handle if line.strip()]
    result = join(
        _read_json(args.complexity),
        [_read_artifact(spec) for spec in args.artifacts],
        scope,
        normalize(args.root).rstrip("/"),
        args.prefix_strip,
        args.searched,
    )
    _write_jsonl(args.measures_out, result["measures"])
    _write_jsonl(args.run_out, result["run"])
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print("join.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr)
        sys.exit(2)
    try:
        sys.exit(main(sys.argv[1:]))
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"join.py: {exc}", file=sys.stderr)
        sys.exit(2)
