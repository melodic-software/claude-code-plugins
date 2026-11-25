#!/usr/bin/env python3
"""Join parsed coverage artifacts to the functions in scope (design T7).

    join.py --complexity <complexity.json> --scope <scope-files.txt>
            --root <repo root> [--artifacts <format>:<parsed.json>]...
            [--prefix-strip <prefix>]... [--searched <path>]...
            [--measures-out <rows.jsonl>] [--run-out <run.jsonl>]
    join.py --self-test

Prints `{"measures": [...], "run": [...]}` to stdout; the two `--*-out`
options write the same rows as JSON lines for `report.py assemble`.

`--complexity` is one `code-metrics/v2` document from the `audit` skill's
complexity action. Its per-function rows supply the cyclomatic
complexity and the line range; `--artifacts` are the mappings the parsers
under `../../../scripts/parsers/` print, each tagged with the format it came
from, so a reason can name it.

What comes out:

  * one row per file in scope that an artifact covers: `coverage_pct`,
    `lines_executable`, `lines_hit`, plus the `cov_source` that says which
    measure produced the percentage. A Go cover profile weighs statements
    rather than lines and never says which lines carry them, so a file it
    covers reports `cov_source: statement-ratio`, takes its percentage from
    the merged block table, which is the ratio `go tool cover -func` prints,
    and reports the two line counts as `null` rather than as a count of
    nothing. That ratio is the file's exact native measure and outranks a line
    table for the same file, so an lcov or Cobertura artifact that also names
    a `.go` file cannot replace it; a line-measured file reports
    `cov_source: artifact-region` and its own line counts.
  * one row per function that has a cyclomatic row with a real end line:
    `coverage_pct`, `cyclomatic`, `crap`, plus `cov_source` and `hit`.
    `cov_source` is `artifact-region` when the artifact carried the function's
    own region and `line-range` when the range came from the complexity
    collector, in which case the ranges of nested functions are subtracted
    from the parent first. A function-hit flag of 0 reports 0 percent, because
    a declaration line that ran at import is not the function running. A
    function with no executable lines reports `coverage_pct: null` and
    `crap: null`, never 0, which would be a fabricated maximal CRAP; its line
    counts are 0 when a line-measuring artifact covered the file, whether or
    not it carried any executable line, and `null` when no artifact covering
    the file measures lines at all, which is every function of a file measured
    only by a Go cover profile. `cov_source` is `ambiguous` where an artifact
    recorded a function under a short name that fits more than one function in
    the file and no line range says which; coverage, line counts, `hit`, and
    CRAP are `null` there while cyclomatic from the complexity row is kept,
    and the row carries a `coverage-ambiguous` label, because a missing
    coverage number an operator can see beats a wrong number they cannot.
  * one `<language>/coverage` and one `<language>/crap` run row per language. A language whose
    files are missing from every artifact is `unavailable` and says which
    paths were searched; a language matched in part is `partial` and carries
    `partial, N of M scope files present in the artifacts`, so a total miss
    never reads as "no executable lines" and a document whose own row says
    `N of M` cannot settle as `complete`. A language holding an ambiguous function
    row is `partial` as well, and names the functions it left unjoined. A language
    whose cyclomatic collector reports no function end lines (Bash in V1) gets
    a `not-applicable` CRAP row rather than a null that would hide the whole
    language.

Path normalization runs on both sides before the join: forward slashes, `./`
removed, then the repository root and each `coverage.path_prefix_strip`
prefix, then a component-wise suffix match (an absolute `SF:` path or a
Cobertura `<source>` prefix), then a basename match (a Go profile names files
by module path). A basename is the weakest evidence here, so it must be
unambiguous on both sides: exactly one file in scope carries it AND exactly one
artifact path claims it, counted across every artifact supplied rather than
within one, because the skill discovers one artifact per coverage file.

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
MISSING_SHOWN = 5


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


def resolve(
    path: str,
    scope: list[str],
    root: str,
    prefixes: list[str],
    ambiguous: set[str] | None = None,
) -> str | None:
    """The file in `scope` an artifact path refers to, or `None`.

    `ambiguous` is the set of basenames that more than one distinct artifact
    path claims, across every artifact supplied. A basename is the weakest
    evidence this function accepts, so it has to be unambiguous on both sides:
    unique among the scoped files AND named by one artifact path. Profiles
    listing `service-a/handler.go` and `service-b/handler.go` when only the
    first is in scope would otherwise map both to it, and the union would let
    the unrelated package's coverage report an uncovered file as covered.

    The set counts distinct paths rather than spellings, and spans artifacts
    rather than stopping at one: the coverage skill discovers one artifact per
    coverage file, so two services' profiles arrive as two documents, and two
    keys that normalize to the same path are one file listed twice, not two
    files competing.
    """
    candidates = _candidates(normalize(path), root, prefixes)
    for candidate in candidates:
        if candidate in scope:
            return candidate
    matches: dict[str, int] = {}
    for candidate in candidates:
        parts = candidate.split("/")
        for target in scope:
            wanted = target.split("/")
            if len(wanted) <= len(parts) and parts[-len(wanted) :] == wanted:
                matches[target] = max(matches.get(target, 0), len(wanted))
    if matches:
        return _unique_longest(matches)
    for candidate in candidates:
        parts = candidate.split("/")
        for target in scope:
            wanted = target.split("/")
            if len(parts) < len(wanted) and wanted[-len(parts) :] == parts:
                matches[target] = max(matches.get(target, 0), len(parts))
    if matches:
        return _unique_longest(matches)
    base = candidates[0].rsplit("/", 1)[-1]
    if base in (ambiguous or ()):
        return None
    basename_matches = [t for t in scope if t.rsplit("/", 1)[-1] == base]
    return basename_matches[0] if len(basename_matches) == 1 else None


def _basename(path: str) -> str:
    return normalize(path).rsplit("/", 1)[-1]


def _unique_longest(matches: dict[str, int]) -> str | None:
    if not matches:
        return None
    longest = max(matches.values())
    winners = [target for target, length in matches.items() if length == longest]
    return winners[0] if len(winners) == 1 else None


def _lines(raw: Any) -> dict[int, int]:
    out: dict[int, int] = {}
    for key, value in (raw or {}).items():
        try:
            out[int(key)] = int(value)
        except (TypeError, ValueError):
            continue
    return out


def _int(value: Any) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) else None


def _fold_statements(accumulated: dict[str, Any], incoming: dict[str, Any]) -> None:
    blocks = incoming.get("blocks")
    if isinstance(blocks, dict):
        union = accumulated.setdefault("blocks", {})
        for key, block in blocks.items():
            weight = _int((block or {}).get("statements"))
            count = _int((block or {}).get("count")) or 0
            if weight is None:
                continue
            prior = union.get(str(key))
            union[str(key)] = (
                [weight, count]
                if prior is None
                else [max(prior[0], weight), max(prior[1], count)]
            )
        return
    for key in ("total", "hit"):
        value = _int(incoming.get(key))
        if value is not None:
            accumulated[key] = max(accumulated.get(key, 0), value)


def _statement_totals(statements: dict[str, Any] | None) -> dict[str, int] | None:
    if not statements:
        return None
    blocks = statements.get("blocks") or {}
    if blocks:
        return {
            "total": sum(weight for weight, _ in blocks.values()),
            "hit": sum(weight for weight, count in blocks.values() if count > 0),
        }
    total = _int(statements.get("total"))
    if not total:
        return None
    return {"total": total, "hit": _int(statements.get("hit")) or 0}


def merge_artifacts(
    artifacts: list[dict[str, Any]], scope: list[str], root: str, prefixes: list[str]
) -> dict[str, dict]:
    """Fold every parsed artifact onto the files in scope. A file covered by
    two artifacts keeps the larger hit count per line, so a line is never
    counted twice."""
    merged: dict[str, dict] = {}
    paths_by_basename: dict[str, dict[str, set[str]]] = {}
    for artifact in artifacts:
        by_base = paths_by_basename.setdefault(artifact.get("format") or "unknown", {})
        for raw_path in artifact.get("files") or {}:
            candidate = normalize(raw_path)
            by_base.setdefault(_basename(candidate), set()).add(candidate)
    ambiguous_by_format = {
        fmt_key: {base for base, paths in by_base.items() if len(paths) > 1}
        for fmt_key, by_base in paths_by_basename.items()
    }
    for artifact in artifacts:
        fmt = artifact.get("format") or "unknown"
        claimed: dict[str, set[int]] = {}
        sections = artifact.get("files") or {}
        for raw_path, section in sections.items():
            target = resolve(
                raw_path, scope, root, prefixes, ambiguous_by_format.get(fmt)
            )
            if target is None:
                continue
            entry = merged.setdefault(
                target, {"lines": {}, "functions": [], "formats": [], "statements": {}}
            )
            if fmt not in entry["formats"]:
                entry["formats"].append(fmt)
            if "statements" not in section:
                entry["measures_lines"] = True
            for number, hits in _lines(section.get("lines")).items():
                entry["lines"][number] = max(entry["lines"].get(number, 0), hits)
            _fold_statements(entry["statements"], section.get("statements") or {})
            for function in section.get("functions") or []:
                _fold_function(
                    entry["functions"],
                    {
                        "name": function.get("name"),
                        "start_line": function.get("start_line"),
                        "end_line": function.get("end_line"),
                        "hit": function.get("hit"),
                        "lines": _lines(function.get("lines"))
                        if function.get("lines")
                        else None,
                    },
                    claimed.setdefault(target, set()),
                )
    return merged


def _fold_function(
    functions: list[dict[str, Any]], incoming: dict[str, Any], claimed: set[int]
) -> None:
    name, start = incoming["name"], incoming["start_line"]
    candidates = []
    for index, existing in enumerate(functions):
        if index in claimed:
            continue
        same_name = name is not None and existing["name"] == name
        nameless = existing["name"] is None or name is None
        same_span = start is not None and existing["start_line"] == start
        if same_name or (nameless and same_span):
            candidates.append(index)
    if candidates:
        positioned = [
            index
            for index in candidates
            if start is not None and functions[index]["start_line"] == start
        ]
        index = positioned[0] if positioned else candidates[0]
        existing = functions[index]
        if existing["name"] is None:
            existing["name"] = incoming["name"]
        if existing["start_line"] is None:
            existing["start_line"] = incoming["start_line"]
        if existing["end_line"] is None:
            existing["end_line"] = incoming["end_line"]
        hits = [h for h in (existing["hit"], incoming["hit"]) if h is not None]
        existing["hit"] = max(hits) if hits else None
        if incoming["lines"]:
            folded = dict(existing["lines"] or {})
            for number, count in incoming["lines"].items():
                folded[number] = max(folded.get(number, 0), count)
            existing["lines"] = folded
        claimed.add(index)
        return
    functions.append(incoming)
    claimed.add(len(functions) - 1)


def _coverage(
    lines: dict[int, int],
    statements: dict[str, int] | None = None,
    measures_lines: bool = True,
) -> tuple[int | None, int | None, float | None, str | None]:
    totals = statements or {}
    total = totals.get("total") or 0
    if total:
        ratio = round(100.0 * (totals.get("hit") or 0) / total, 2)
        return None, None, ratio, "statement-ratio"
    executable = len(lines)
    hit = sum(1 for value in lines.values() if value > 0)
    if executable == 0:
        return (0, 0, None, None) if measures_lines else (None, None, None, None)
    return executable, hit, round(100.0 * hit / executable, 2), None


def _tail(name: str | None) -> str:
    return (name or "").rsplit(".", 1)[-1]


def _anchors(candidate: dict[str, Any]) -> list[int]:
    found: set[int] = set()
    for key in ("start_line", "end_line"):
        value = _int(candidate.get(key))
        if value is not None:
            found.add(value)
    found.update(candidate.get("lines") or {})
    return sorted(found)


def _in_range(candidate: dict[str, Any], start: int, end: int) -> bool:
    return any(start <= number <= end for number in _anchors(candidate))


def _match_function(
    functions: list[dict[str, Any]],
    name: str | None,
    start_line: int | None,
    end_line: int | None = None,
    rival: bool = False,
) -> tuple[dict[str, Any] | None, str | None]:
    tail = _tail(name)
    exact = [candidate for candidate in functions if candidate.get("name") == name]
    if len(exact) == 1:
        return exact[0], None
    if exact:
        positioned = [
            candidate
            for candidate in exact
            if candidate.get("start_line") == start_line
        ]
        if start_line is not None and len(positioned) == 1:
            return positioned[0], None
        return None, None
    if tail:
        shared = [
            candidate for candidate in functions if _tail(candidate.get("name")) == tail
        ]
        if shared:
            if start_line is not None:
                positioned = [
                    candidate
                    for candidate in shared
                    if candidate.get("start_line") == start_line
                ]
                if len(positioned) == 1:
                    return positioned[0], None
            placed = [candidate for candidate in shared if _anchors(candidate)]
            if placed and start_line is not None and end_line is not None:
                inside = [
                    candidate
                    for candidate in placed
                    if _in_range(candidate, start_line, end_line)
                ]
                if len(inside) == 1:
                    return inside[0], None
                if len(inside) > 1:
                    return None, (
                        f"{len(inside)} coverage records named `{tail}` fall inside "
                        "this function's line range"
                    )
                if len(placed) == len(shared) and (rival or len(shared) > 1):
                    return None, None
            if len(shared) == 1 and not rival:
                return shared[0], None
            if len(shared) == 1:
                return None, (
                    f"the coverage record named `{tail}` carries no line range, "
                    "and another function here ends in that name"
                )
            return None, (
                f"{len(shared)} coverage records named `{tail}` and no line range "
                "placing one of them in this function"
            )
    if start_line is not None:
        for candidate in functions:
            if candidate.get("start_line") == start_line:
                return candidate, None
    return None, None


def _cyclomatic_rows(document: dict[str, Any]) -> list[dict[str, Any]]:
    return [
        row
        for row in document.get("measures") or []
        if row.get("function")
        and (row.get("values") or {}).get("cyclomatic") is not None
    ]


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


def _measures_lines(entry: dict[str, Any]) -> bool:
    if entry.get("measures_lines"):
        return True
    return (
        bool(entry.get("lines")) or _statement_totals(entry.get("statements")) is None
    )


def _function_row(
    row: dict[str, Any], entry: dict[str, Any], siblings: list[dict[str, Any]]
) -> dict[str, Any]:
    start, end = row["start_line"], row["end_line"]
    identity = {
        "file": row["file"],
        "function": row["function"],
        "start_line": start,
        "end_line": end,
        "language": row.get("language"),
    }
    tail = _tail(row.get("function"))
    rival = sum(1 for other in siblings if _tail(other.get("function")) == tail) > 1
    matched, ambiguity = _match_function(
        entry["functions"], row.get("function"), start, end, rival
    )
    if ambiguity:
        return {
            **identity,
            "values": {
                "coverage_pct": None,
                "lines_executable": None,
                "lines_hit": None,
                "cyclomatic": row["values"]["cyclomatic"],
                "crap": None,
            },
            "cov_source": "ambiguous",
            "hit": None,
            "labels": ["coverage-ambiguous"],
            "reason": ambiguity,
        }
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
    executable, hits, percent, _ = _coverage(
        region, None, measures_lines=_measures_lines(entry)
    )
    if percent is not None and hit == 0:
        percent = 0.0
    comp = row["values"]["cyclomatic"]
    score = crap_module.crap(comp, percent)
    return {
        **identity,
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
    scope_languages: dict[str, str] | None = None,
) -> dict[str, list[dict[str, Any]]]:
    """The whole join: coverage rows plus the run rows that explain them."""
    prefixes = prefixes or []
    scope = [normalize(path) for path in scope]
    merged = merge_artifacts(artifacts, scope, root, prefixes)
    cyclomatic = _cyclomatic_rows(complexity)
    language_of: dict[str, str] = dict(scope_languages or {})
    for row in complexity.get("measures") or []:
        if row.get("file"):
            language_of.setdefault(normalize(row["file"]), row.get("language") or "*")
    languages: dict[str, list[str]] = {}
    for path in scope:
        languages.setdefault(language_of.get(path, "*"), []).append(path)

    measures: list[dict[str, Any]] = []
    unjoined: dict[str, list[dict[str, Any]]] = {}
    for path in scope:
        entry = merged.get(path)
        if not entry:
            continue
        executable, hits, percent, basis = _coverage(
            entry["lines"], _statement_totals(entry.get("statements"))
        )
        measures.append(
            {
                "file": path,
                "function": None,
                "start_line": None,
                "end_line": None,
                "language": language_of.get(path, "*"),
                "values": {
                    "coverage_pct": percent,
                    "lines_executable": executable,
                    "lines_hit": hits,
                },
                "cov_source": basis or "artifact-region",
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
            function_row = _function_row(joined, entry, siblings)
            if "coverage-ambiguous" in (function_row.get("labels") or []):
                unjoined.setdefault(language_of.get(path, "*"), []).append(function_row)
            measures.append(function_row)

    formats = list(dict.fromkeys(a.get("format") or "unknown" for a in artifacts))
    where = ", ".join(searched or []) or "nothing"
    run: list[dict[str, Any]] = []
    for language in sorted(languages):
        files = languages[language]
        if language == "other":
            for measure in ("coverage", "crap"):
                run.append(
                    {
                        "language": language,
                        "measure": measure,
                        "collector": None,
                        "status": "not-applicable",
                        "reason": (
                            "files outside every language; no coverage "
                            "artifact format measures them"
                        ),
                    }
                )
            continue
        matched = [path for path in files if path in merged]
        missing = sorted(path for path in files if path not in merged)
        shown_missing = ", ".join(missing[:MISSING_SHOWN])
        if len(missing) > MISSING_SHOWN:
            shown_missing += f", +{len(missing) - MISSING_SHOWN} more in the JSON"
        missing_note = f"; missing: {shown_missing}" if missing else ""
        if not artifacts:
            status, reason = (
                "unavailable",
                f"no coverage artifact found; searched: {where}",
            )
        elif not matched:
            status = "unavailable"
            reason = (
                f"partial, 0 of {len(files)} scope files present in the artifacts "
                f"({', '.join(formats)} read){missing_note}"
            )
        elif len(matched) < len(files):
            status = "partial"
            reason = (
                f"partial, {len(matched)} of {len(files)} scope files present "
                f"in the artifacts{missing_note}"
            )
        else:
            status, reason = "ok", None
        ambiguous = unjoined.get(language) or []
        if ambiguous:
            detail = sorted(
                {f"{item['function']}: {item['reason']}" for item in ambiguous}
            )
            shown = "; ".join(detail[:3])
            if len(detail) > 3:
                shown += f"; and {len(detail) - 3} more"
            note = f"{len(ambiguous)} function(s) left unjoined: {shown}"
            if status == "ok":
                status = "partial"
            reason = f"{reason}; {note}" if reason else note
        collector = (
            ", ".join(
                sorted({fmt for path in matched for fmt in merged[path]["formats"]})
            )
            or None
        )
        coverage_row: dict[str, Any] = {
            "language": language,
            "measure": "coverage",
            "collector": collector,
            "status": status,
            "reason": reason,
        }
        if artifacts and missing:
            coverage_row["missing"] = missing
        run.append(coverage_row)
        language_cyclomatic = [
            row for row in cyclomatic if (row.get("language") or "*") == language
        ]
        comp_row = next(
            (
                row
                for row in complexity.get("run") or []
                if row.get("language") == language and row.get("measure") == "cyclomatic"
            ),
            None,
        )
        collector_failed = (
            not language_cyclomatic
            and comp_row is not None
            and comp_row.get("status") != "ok"
        )
        if language_cyclomatic and all(
            row.get("end_line") is None for row in language_cyclomatic
        ):
            crap_status, crap_reason = "not-applicable", NO_END_LINES
        elif collector_failed:
            crap_status = "unavailable"
            crap_reason = (
                f"cyclomatic collector {comp_row.get('collector') or 'unresolved'} "
                f"{comp_row.get('status')}: "
                f"{comp_row.get('reason') or 'no reason given'}"
            )
            if status != "ok":
                crap_reason = f"{crap_reason}; coverage {status}: {reason}"
        elif status != "ok":
            crap_status, crap_reason = status, reason
        elif not language_cyclomatic:
            crap_status = "not-applicable"
            crap_reason = "no function-level cyclomatic rows in scope for this language"
        else:
            crap_status, crap_reason = "ok", reason
        run.append(
            {
                "language": language,
                "measure": "crap",
                "collector": collector if crap_status in ("ok", "partial") else None,
                "status": crap_status,
                "reason": crap_reason,
            }
        )
    if not run:
        for measure in ("coverage", "crap"):
            run.append(
                {
                    "language": "*",
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
        row.update({"file": "src/a.py", "language": "python"})
    artifact["files"]["src/a.py"]["lines"] = lines
    result = join(complexity, [artifact], ["src/a.py"])
    return [r for r in result["measures"] if r.get("function") == "outer"][0]


def self_test() -> int:
    """The properties the join must hold, checked without a fixture tree."""
    lines = {1: 1, 2: 0, 4: 1, 5: 1, 6: 1, 8: 0, 10: 0}
    section: dict[str, Any] = {"functions": None}
    outer = _outer({"format": "lcov", "files": {"src/a.py": section}}, lines)
    assert outer["cov_source"] == "line-range", outer
    assert outer["values"]["lines_executable"] == 4, outer
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
    scope: list[str] = []
    scope_languages: dict[str, str] = {}
    with open(args.scope, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            language, tab, path = line.partition("\t")
            if not tab:
                language, path = "", line
            path = normalize(path.strip())
            if not path:
                continue
            scope.append(path)
            if language.strip():
                scope_languages.setdefault(path, language.strip())
    result = join(
        _read_json(args.complexity),
        [_read_artifact(spec) for spec in args.artifacts],
        scope,
        normalize(args.root).rstrip("/"),
        args.prefix_strip,
        args.searched,
        scope_languages,
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
