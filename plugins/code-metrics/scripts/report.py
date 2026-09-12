#!/usr/bin/env python3
"""Assemble and render `code-metrics/v1` report documents (design thread T5).

Three subcommands, all standard library:

  report.py thresholds --config <resolved.json> --measures m1,m2
      Print the `thresholds[]` entries for the named measures: the reference
      value read from the resolved config, its provenance, and the layer that
      supplied it (`_layers` in the config, else "bundled default").

  report.py assemble --skill <name> --scope <scope.json> --run <run.jsonl>
                     --measures <measures.jsonl> --thresholds <thresholds.json>
                     [--excluded <excluded.jsonl>] [--root <dir>]
      Print the report document: `run[]` is the coverage-of-this-run table,
      `measures[]` gains `over_reference`, `summary` counts, `unavailable[]`
      lists every non-ok lane/measure, and `status` is complete, partial, or
      empty. A value that was not measured is `null`, never zero. A `partial`
      run row counts as measured, so a lane that skipped every file is
      `partial`, not `empty`.

  report.py render [--document <path>] [--rollup-depth <n>] [< report.json]
      Print the markdown rendering of a report document read from stdin. The
      table joins the rows every collector produced for one function into one
      line (the JSON keeps one row per collector), lists rows over a reference
      first by how far past it they sit, and caps itself at MAX_RENDERED_ROWS;
      `--document` names the file the caller persisted the whole document to,
      so the cap line and the summary can point at it. A duplication document
      (clone-group rows, or `skill` audit-duplication) lists groups largest
      first, adds a `## Rollup` section with per-lane and per-directory tables
      (directories to `--rollup-depth`, default 2), and summarizes as
      `Files with clones`; every other document renders as it always has.

  report.py resummarize [--root <dir>] [< report.json]
      Recompute `summary` from `measures[]` and print the document; for a
      skill that drops rows after assembly (a duplication registry moving
      clone groups into `excluded[]`). Clone-group rows (`instances[]`) add
      `summary.duplicated_lines`, `summary.clone_groups`, `summary.by_lane`,
      and `summary.by_directory` (paths made relative to `--root`).

Exit 0 on success, 2 on a usage error or unreadable input.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import sys
from typing import Any

from pathglob import root_relative

MIN_PYTHON = (3, 9)
SCHEMA = "code-metrics/v1"
RUN_STATUSES = ("ok", "partial", "unavailable", "not-applicable", "deferred")
MAX_RENDERED_ROWS = 200


def _read_json(path: str) -> Any:
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def _read_jsonl(path: str | None) -> list[dict[str, Any]]:
    if not path:
        return []
    rows: list[dict[str, Any]] = []
    with open(path, encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise SystemExit(f"{path}:{line_number}: not JSON: {exc}")
    return rows


def _dig(config: dict[str, Any], dotted: str) -> Any:
    node: Any = config
    for part in dotted.split("."):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node


def thresholds(config: dict[str, Any], measures: list[str]) -> list[dict[str, Any]]:
    layers = config.get("_layers") or {}
    out: list[dict[str, Any]] = []
    for entry in config.get("thresholds", []):
        if entry.get("measure") not in measures:
            continue
        key = entry["config_key"]
        out.append(
            {
                "measure": entry["measure"],
                "value_key": entry.get("value_key", entry["measure"]),
                "direction": entry.get("direction", "at_or_above"),
                "reference": _dig(config, key),
                "provenance": entry.get("provenance", ""),
                "layer": layers.get(key, "bundled default"),
            }
        )
    return out


def _over(threshold: dict[str, Any], value: Any) -> bool:
    reference = threshold.get("reference")
    if reference is None or value is None:
        return False
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        return False
    # A reference that is not a number (a quoted number that reached a
    # pre-resolved --config document) is no threshold at all.
    if not isinstance(reference, (int, float)) or isinstance(reference, bool):
        return False
    if threshold.get("direction") == "below":
        return value < reference
    return value >= reference


def _ancestors(path: str) -> list[str]:
    """`.` and every directory above the file, root first."""
    parts = path.split("/")[:-1]
    return ["."] + ["/".join(parts[: index + 1]) for index in range(len(parts))]


def _tally(buckets: dict[str, dict[str, int]], key: str, lines: int) -> None:
    bucket = buckets.setdefault(key, {"groups": 0, "duplicated_lines": 0})
    bucket["groups"] += 1
    bucket["duplicated_lines"] += lines


def summarize(measures: list[dict[str, Any]], root: str = "") -> dict[str, Any]:
    """The `summary` block, derived from `measures[]` alone so a skill that
    drops rows after assembly (a duplication registry exclusion) can recompute
    it through the `resummarize` verb. Counts use each row's `over_reference`
    list as assembled; clone-group rows (those carrying `instances[]`) add
    `duplicated_lines` (sum of `values.lines`, each group counted once) and
    `clone_groups`, and their instance files count toward `files`.

    Clone-group rows also add `by_lane` (lane to `{groups, duplicated_lines}`)
    and `by_directory` (the same shape for `.` and every ancestor directory of
    each group's first instance, made relative to `root`). A group counts once
    per ancestor, so a parent includes its children and the rows cannot be
    summed, while `by_directory["."]` and the per-lane sum both restate the
    totals."""
    files: set[str] = set()
    by_lane: dict[str, dict[str, int]] = {}
    by_directory: dict[str, dict[str, int]] = {}
    # (file, name) -> the distinct start lines reported for it. A name is not an
    # identity: one file can hold two `render` methods. A start line is not one
    # either, because a collector that reports Halstead for a function need not
    # report where it begins, and splitting on a missing line would count that
    # function twice. So the rows for a name are grouped and the group counts as
    # many functions as it has distinct known start lines, and as one when it
    # has none.
    functions: dict[tuple[str, str], set[int]] = {}
    over_counts: dict[str, int] = {}
    duplicated_lines = 0
    clone_groups = 0
    for row in measures:
        if row.get("file"):
            files.add(row["file"])
        # A row that stands for replicated copies was measured for every copy,
        # so each copy is a measured file even though only one row survived.
        for replica in (row.get("replicas") or {}).get("files") or []:
            if replica:
                files.add(replica)
        # One function produces one row per collector that resolves for it
        # (lizard's cyclomatic row and radon's halstead row for the same
        # Python function), so a per-row count reports more functions than the
        # scope holds. A row with no `function` is a file row and is not one.
        if row.get("function"):
            starts = functions.setdefault(
                (row.get("file") or "", row["function"]), set()
            )
            start = row.get("start_line")
            if isinstance(start, int) and not isinstance(start, bool):
                starts.add(start)
        for measure in row.get("over_reference", []):
            over_counts[measure] = over_counts.get(measure, 0) + 1
        instances = row.get("instances")
        if instances:
            clone_groups += 1
            lines = (row.get("values") or {}).get("lines")
            counted = 0
            if isinstance(lines, (int, float)) and not isinstance(lines, bool):
                counted = int(lines)
            duplicated_lines += counted
            for instance in instances:
                if instance.get("file"):
                    files.add(instance["file"])
            _tally(by_lane, str(row.get("lane") or "*"), counted)
            first = root_relative(str(instances[0].get("file") or ""), root)
            for directory in _ancestors(first):
                _tally(by_directory, directory, counted)
    summary: dict[str, Any] = {
        "files": len(files),
        "functions": sum(max(1, len(starts)) for starts in functions.values()),
        "over_reference": over_counts,
    }
    if clone_groups:
        summary["duplicated_lines"] = duplicated_lines
        summary["clone_groups"] = clone_groups
        summary["by_lane"] = by_lane
        summary["by_directory"] = by_directory
    return summary


def assemble(
    skill: str,
    scope: dict[str, Any],
    run: list[dict[str, Any]],
    measures: list[dict[str, Any]],
    threshold_entries: list[dict[str, Any]],
    excluded: list[dict[str, Any]],
    root: str = "",
) -> dict[str, Any]:
    for row in run:
        if row.get("status") not in RUN_STATUSES:
            raise SystemExit(f"run row has an unknown status: {row!r}")
        if row.get("status") != "ok" and not row.get("reason"):
            raise SystemExit(f"non-ok run row without a reason: {row!r}")
    for row in measures:
        values = row.setdefault("values", {})
        row["over_reference"] = [
            threshold["measure"]
            for threshold in threshold_entries
            if _over(threshold, values.get(threshold["value_key"]))
        ]
    # A `not-applicable` row implies nothing to run (the measure does not
    # exist for that lane), so it never withholds `complete`; `unavailable`,
    # `deferred` and `partial` rows do, because something implied was not
    # measured. `partial` still counts as having produced rows, so a run that
    # measured part of a lane reads as `partial` rather than as `empty`, even
    # when it skipped every file and has no row to show: the skip is stated in
    # the run row, and "Measured nothing" would contradict it.
    ok_rows = [row for row in run if row.get("status") in ("ok", "partial")]
    partial_rows = [row for row in run if row.get("status") == "partial"]
    settled = [row for row in run if row.get("status") in ("ok", "not-applicable")]
    if not ok_rows or (not measures and not partial_rows):
        status = "empty"
    elif len(settled) == len(run):
        status = "complete"
    else:
        status = "partial"
    return {
        "schema": SCHEMA,
        "skill": skill,
        "generated_at": _dt.datetime.now(_dt.timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "status": status,
        "scope": scope,
        "run": run,
        # `value_key` and `direction` travel with the document: the renderer
        # orders rows by the primary measure, and a consumer comparing two
        # documents needs to know which value the reference was applied to.
        "thresholds": list(threshold_entries),
        "measures": measures,
        "summary": summarize(measures, root),
        "excluded": excluded,
        "unavailable": [
            f"{row.get('lane', '*')}/{row.get('measure', '*')}"
            for row in run
            if row.get("status") == "unavailable"
        ],
    }


def _primary_threshold(
    thresholds_: list[dict[str, Any]], keys: list[str]
) -> dict[str, Any] | None:
    """The threshold whose value orders the rows that are not over any
    reference: the first one whose `value_key` the rows carry, so a size
    report lists the longest files first and a coverage report the least
    covered, and a document whose rows carry none of them (clone groups)
    keeps its file order."""
    for entry in thresholds_:
        if entry.get("value_key") in keys:
            return entry
    return None


def _primary_rank(primary: dict[str, Any] | None, row: dict[str, Any]) -> tuple:
    """Largest primary value first (smallest first under a `below`
    reference), and a row with no numeric value after every row with one."""
    key = primary.get("value_key") if primary else None
    value = (row.get("values") or {}).get(key) if key else None
    if not _is_number(value):
        return (1, 0)
    return (0, value if primary.get("direction") == "below" else -value)


def _fmt(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, float):
        return f"{value:.2f}".rstrip("0").rstrip(".")
    return str(value)


def _is_duplication(doc: dict[str, Any]) -> bool:
    return doc.get("skill") == "audit-duplication" or any(
        row.get("instances") for row in doc.get("measures", [])
    )


def _depth(directory: str) -> int:
    return 0 if directory == "." else directory.count("/") + 1


def _clone_sort_key(row: dict[str, Any]) -> tuple[int, int, str]:
    values = row.get("values") or {}
    instances = row.get("instances") or [{}]

    def number(value: Any) -> int:
        return int(value) if isinstance(value, (int, float)) else 0

    return (
        -number(values.get("lines")),
        -number(values.get("tokens")),
        str(instances[0].get("file") or ""),
    )


def _is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _merge_into(target: dict[str, Any], row: dict[str, Any]) -> bool:
    """Fold `row` into `target` when their values do not disagree.

    Two rows for one function carry complementary values (a cyclomatic row and
    a Halstead row), so the join fills a null or absent key from the other row.
    A key both rows carry with two different numbers is not the same function
    measured twice; it is two functions the collectors could not tell apart, and
    the join refuses rather than pick one, so the caller keeps the row separate.
    """
    values = target.setdefault("values", {})
    incoming = row.get("values") or {}
    for key, value in incoming.items():
        if value is None or key not in values or values[key] is None:
            continue
        if values[key] != value:
            return False
    for key, value in incoming.items():
        if values.get(key) is None:
            values[key] = value
    for field in ("start_line", "end_line"):
        if target.get(field) is None and row.get(field) is not None:
            target[field] = row[field]
    labels = list(target.get("labels") or [])
    for label in row.get("labels") or []:
        if label not in labels:
            labels.append(label)
    target["labels"] = labels
    collectors = [c for c in str(target.get("collector") or "").split(", ") if c]
    incoming_collector = str(row.get("collector") or "")
    if incoming_collector and incoming_collector not in collectors:
        collectors.append(incoming_collector)
    target["collector"] = ", ".join(collectors)
    over = list(target.get("over_reference") or [])
    for measure in row.get("over_reference") or []:
        if measure not in over:
            over.append(measure)
    target["over_reference"] = over
    if row.get("replicas") and not target.get("replicas"):
        target["replicas"] = row["replicas"]
    return True


def join_rows(measures: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """One rendered row per function, whatever number of collectors measured it.

    The JSON document keeps one row per collector because each row names the
    tool that produced it; a reader of the table wants the function once with
    every number beside it. Rows join on file, function, and start line. A row
    that reports no start line (radon's Halstead rows) joins the one function
    of that name in the file when there is exactly one, and stays its own row
    when the name is ambiguous, which mirrors how `summarize` counts. Clone
    groups (`instances[]`) are never joined.
    """
    starts: dict[tuple[str, str], set[int]] = {}
    for row in measures:
        if row.get("function") and row.get("instances") is None:
            key = (row.get("file") or "", row["function"])
            start = row.get("start_line")
            if isinstance(start, int) and not isinstance(start, bool):
                starts.setdefault(key, set()).add(start)
    joined: list[dict[str, Any]] = []
    by_key: dict[tuple[Any, ...], list[dict[str, Any]]] = {}
    for row in measures:
        if row.get("instances"):
            joined.append(dict(row))
            continue
        file = row.get("file") or ""
        function = row.get("function")
        start = row.get("start_line")
        if function and (not isinstance(start, int) or isinstance(start, bool)):
            known = starts.get((file, function), set())
            start = next(iter(known)) if len(known) == 1 else None
        # The lane is part of the identity: two lane rows (`file` null) from
        # two lanes must never join into one line.
        key = (file, function, start, row.get("lane"))
        candidates = by_key.setdefault(key, [])
        for candidate in candidates:
            if _merge_into(candidate, row):
                break
        else:
            fresh = dict(row)
            fresh["values"] = dict(row.get("values") or {})
            fresh["labels"] = list(row.get("labels") or [])
            fresh["over_reference"] = list(row.get("over_reference") or [])
            if fresh.get("start_line") is None and start is not None:
                fresh["start_line"] = start
            candidates.append(fresh)
            joined.append(fresh)
    return joined


def _over_distance(row: dict[str, Any], references: dict[str, Any]) -> float:
    """How far past its reference the row's worst value sits, for ordering.

    Distance rather than the raw value, because coverage counts values BELOW
    a reference and complexity values above one; the absolute gap orders both
    with the same key, worst first.
    """
    worst = 0.0
    values = row.get("values") or {}
    for measure in row.get("over_reference") or []:
        value = values.get(measure)
        reference = references.get(measure)
        if _is_number(value) and _is_number(reference):
            worst = max(worst, abs(float(value) - float(reference)))
        elif _is_number(value):
            worst = max(worst, float(value))
    return worst


def render(
    doc: dict[str, Any], document_path: str | None = None, rollup_depth: int = 2
) -> str:
    lines: list[str] = []
    status = doc.get("status", "empty")
    headline = "Measured nothing" if status == "empty" else f"Status: {status}"
    scope = doc.get("scope", {})
    duplication = _is_duplication(doc)
    lines.append(f"# code-metrics: {doc.get('skill', '?')}")
    lines.append("")
    # A `not-applicable` row (the `other` lane, which no detector covers) is
    # not a probe that failed, so it neither earns the headline nor blocks it.
    detector_rows = [
        row
        for row in doc.get("run", [])
        if row.get("measure") == "duplication" and row.get("status") != "not-applicable"
    ]
    if (
        duplication
        and detector_rows
        and all(row.get("status") == "unavailable" for row in detector_rows)
    ):
        # One headline for the whole run: the lane rows below still carry
        # each probe's own reason, so this names the fix once, not per lane.
        hint = next((row.get("hint") for row in detector_rows if row.get("hint")), "")
        lines.append(
            "No clone detector ran in any lane"
            + (f": {hint}" if hint else "")
            + ". Run `/code-metrics:setup` to install one."
        )
        lines.append("")
    lines.append(
        f"{headline}. Scope: {scope.get('mode', '?')}"
        + (f" against `{scope['base']}`" if scope.get("base") else "")
        + f", {scope.get('files', 0)} file(s)"
        + (f", {scope['unclassified']} in no lane" if scope.get("unclassified") else "")
        + (f", {scope['excluded']} excluded" if scope.get("excluded") else "")
        + "."
        + (
            # An empty change is the common empty run; the headline says how
            # to widen it, because the skill body is not in front of the
            # reader when the report is.
            " No files differ from that merge-base and none are uncommitted; "
            "pass paths or `--all` to widen the scope."
            if scope.get("mode") == "change" and not scope.get("files")
            else ""
        )
    )
    lines.append("")
    lines.append("## Coverage of this run")
    lines.append("")
    lines.append("| Lane | Measure | Collector | Status | Reason |")
    lines.append("|---|---|---|---|---|")
    for row in doc.get("run", []):
        lines.append(
            f"| {row.get('lane', '*')} | {row.get('measure', '*')} | "
            f"{row.get('collector') or ''} | {row.get('status')} | {row.get('reason') or ''} |"
        )
    thresholds_ = doc.get("thresholds", [])
    if thresholds_:
        lines.append("")
        lines.append("## References")
        lines.append("")
        lines.append("| Measure | Reference | Provenance | Layer |")
        lines.append("|---|---|---|---|")
        for entry in thresholds_:
            lines.append(
                f"| {entry['measure']} | {_fmt(entry.get('reference'))} | "
                f"{entry.get('provenance', '')} | {entry.get('layer', '')} |"
            )
        lines.append("")
        lines.append(
            "A reference is a value to count against, never a bar: no finding, severity, or exit "
            "code follows from it."
        )
    measures = join_rows(doc.get("measures", []))
    references = {entry.get("measure"): entry.get("reference") for entry in thresholds_}
    halstead_zero = False
    if measures:
        keys: list[str] = []
        for row in measures:
            for key in row.get("values", {}):
                if key not in keys:
                    keys.append(key)
        lines.append("")
        lines.append("## Measures")
        lines.append("")
        header = (
            "| File | Function | Lane | Labels | "
            + " | ".join(keys)
            + " | Over reference |"
        )
        lines.append(header)
        lines.append("|" + "---|" * (5 + len(keys)))
        shown = 0
        primary = _primary_threshold(thresholds_, keys)
        if duplication:
            # Largest group first: the reader's question is "what is the
            # biggest copy", not which file sorts first.
            ordered = sorted(measures, key=_clone_sort_key)
        else:
            # Rows over a reference come first, the furthest past it at the
            # top, so the table's opening lines are the ones a reader came
            # for; the rest follow by the primary measure's value, largest
            # first, so a size report reads longest to shortest rather than
            # alphabetically.
            ordered = sorted(
                measures,
                key=lambda r: (
                    # A lane row (`lane-total`) is the lane's figure: it leads
                    # its table and never falls under the row cap.
                    0 if "lane-total" in (r.get("labels") or []) else 1,
                    -len(r.get("over_reference", [])),
                    -_over_distance(r, references),
                    _primary_rank(primary, r),
                    # A lane row (type debt) has `file: null`; `or ""` keeps
                    # it comparable with the file rows it now sorts among.
                    r.get("file") or "",
                    r.get("start_line") or 0,
                ),
            )
        for row in ordered:
            if shown >= MAX_RENDERED_ROWS:
                remaining = len(measures) - shown
                where_full = (
                    f"{remaining} more rows in the JSON document at {document_path}"
                    if document_path
                    else f"{remaining} more rows; re-run with --json for the full document"
                )
                if primary:
                    where_full += (
                        f"; the {MAX_RENDERED_ROWS} shown are those over a reference "
                        f"first, then the top by {primary['value_key']}"
                    )
                lines.append(
                    f"| ... | | | | {' | '.join('' for _ in keys)} | {where_full} |"
                )
                break
            values = row.get("values", {})
            where = row.get("file") or ""
            if row.get("instances"):
                where = ", ".join(
                    f"{i.get('file', '')}:{i.get('start_line', '?')}-{i.get('end_line', '?')}"
                    for i in row["instances"]
                )
            replicas = row.get("replicas") or {}
            if _is_number(replicas.get("count")) and replicas["count"] > 1:
                where += f" (+{int(replicas['count']) - 1} replicas)"
            for key in keys:
                if key.startswith("halstead") and values.get(key) == 0:
                    halstead_zero = True
            lines.append(
                f"| {where} | {row.get('function') or ''} | {row.get('lane', '')} | "
                f"{', '.join(row.get('labels') or [])} | "
                + " | ".join(_fmt(values.get(k)) for k in keys)
                + f" | {', '.join(row.get('over_reference', [])) or ''} |"
            )
            shown += 1
        if halstead_zero:
            lines.append("")
            lines.append(
                "A Halstead value of 0 is a measurement, not a missing one: the collector "
                "found no operators or operands in that function."
            )
    summary = doc.get("summary", {})
    by_lane = summary.get("by_lane") or {}
    by_directory = summary.get("by_directory") or {}
    if duplication and (by_lane or by_directory):
        lines.append("")
        lines.append("## Rollup")
        lines.append("")
        lines.append("| Lane | Clone groups | Duplicated lines |")
        lines.append("|---|---|---|")
        for lane, bucket in sorted(by_lane.items()):
            lines.append(
                f"| {lane} | {bucket.get('groups', 0)} | {bucket.get('duplicated_lines', 0)} |"
            )
        lines.append("")
        lines.append(
            f"| Directory (to depth {rollup_depth}) | Clone groups | Duplicated lines |"
        )
        lines.append("|---|---|---|")
        for directory, bucket in sorted(by_directory.items()):
            if _depth(directory) <= rollup_depth:
                lines.append(
                    f"| {directory} | {bucket.get('groups', 0)} | "
                    f"{bucket.get('duplicated_lines', 0)} |"
                )
        lines.append("")
        lines.append(
            "A group is attributed to every directory above its first instance, so a parent "
            "includes its children and the directory rows cannot be summed; `.` restates the "
            "totals. The JSON carries every directory."
        )
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    if duplication:
        lines.append(f"Files with clones: {summary.get('files', 0)}.")
    else:
        lines.append(
            f"Files: {summary.get('files', 0)}. "
            # A file-level report has no functions to count; the figure is
            # printed only where function rows exist.
            + (
                f"Functions: {summary['functions']}. "
                if summary.get("functions")
                else ""
            )
            + "Over reference: "
            + (
                ", ".join(
                    f"{k} {v}" for k, v in summary.get("over_reference", {}).items()
                )
                or "none"
            )
            + "."
        )
    if "duplicated_lines" in summary:
        lines.append(
            f"Duplicated lines: {summary['duplicated_lines']} in "
            f"{summary.get('clone_groups', 0)} clone group(s)."
        )
    if doc.get("excluded"):
        lines.append(
            f"Excluded by a sanctioned-replication registry: {len(doc['excluded'])}."
        )
    elif duplication:
        lines.append(
            "Excluded by a sanctioned-replication registry: 0 (no registry configured, or "
            "none matched)."
        )
    replicated_rows = [r for r in measures if (r.get("replicas") or {}).get("count")]
    if replicated_rows:
        standing_for = sum(int(r["replicas"]["count"]) for r in replicated_rows)
        lines.append(
            f"Replicated files collapsed by a sanctioned-replication registry: "
            f"{len(replicated_rows)} row(s) standing for {standing_for} files."
        )
    exclusions = scope.get("exclusions") or []
    if exclusions:
        lines.append(
            "Excluded by scope.exclude: "
            + ", ".join(
                f"`{e.get('pattern', '')}` {e.get('files', 0)}" for e in exclusions
            )
            + "."
        )
    if doc.get("unavailable"):
        lines.append("Unavailable: " + ", ".join(doc["unavailable"]) + ".")
    partial = [
        f"{row.get('lane', '*')}/{row.get('measure', '*')}"
        for row in doc.get("run", [])
        if row.get("status") == "partial"
    ]
    if duplication and partial:
        lines.append("Partial: " + ", ".join(partial) + ".")
    if document_path:
        lines.append(f"Full document: {document_path}")
    return "\n".join(lines) + "\n"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="report.py")
    sub = parser.add_subparsers(dest="command", required=True)
    p_thresholds = sub.add_parser("thresholds")
    p_thresholds.add_argument("--config", required=True)
    p_thresholds.add_argument("--measures", required=True)
    p_asm = sub.add_parser("assemble")
    p_asm.add_argument("--skill", required=True)
    p_asm.add_argument("--scope", required=True)
    p_asm.add_argument("--run", required=True)
    p_asm.add_argument("--measures", required=True)
    p_asm.add_argument("--thresholds", required=True)
    p_asm.add_argument("--excluded")
    p_asm.add_argument("--root", default="")
    p_render = sub.add_parser("render")
    p_render.add_argument("--document")
    p_render.add_argument("--rollup-depth", type=int, default=2)
    p_res = sub.add_parser("resummarize")
    p_res.add_argument("--root", default="")
    args = parser.parse_args(argv)
    if args.command == "thresholds":
        config = _read_json(args.config)
        print(json.dumps(thresholds(config, args.measures.split(",")), indent=2))
        return 0
    if args.command == "assemble":
        doc = assemble(
            args.skill,
            _read_json(args.scope),
            _read_jsonl(args.run),
            _read_jsonl(args.measures),
            _read_json(args.thresholds),
            _read_jsonl(args.excluded),
            args.root,
        )
        print(json.dumps(doc, indent=2))
        return 0
    doc = json.load(sys.stdin)
    if args.command == "resummarize":
        doc["summary"] = summarize(doc.get("measures", []), args.root)
        print(json.dumps(doc, indent=2))
        return 0
    sys.stdout.write(render(doc, getattr(args, "document", None), args.rollup_depth))
    return 0


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print("report.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr)
        sys.exit(2)
    try:
        sys.exit(main(sys.argv[1:]))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"report.py: {exc}", file=sys.stderr)
        sys.exit(2)
