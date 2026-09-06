#!/usr/bin/env python3
"""Assemble and render `code-metrics/v1` report documents (design thread T5).

Three subcommands, all standard library:

  report.py thresholds --config <resolved.json> --measures m1,m2
      Print the `thresholds[]` entries for the named measures: the reference
      value read from the resolved config, its provenance, and the layer that
      supplied it (`_layers` in the config, else "bundled default").

  report.py assemble --skill <name> --scope <scope.json> --run <run.jsonl>
                     --measures <measures.jsonl> --thresholds <thresholds.json>
                     [--excluded <excluded.jsonl>]
      Print the report document: `run[]` is the coverage-of-this-run table,
      `measures[]` gains `over_reference`, `summary` counts, `unavailable[]`
      lists every non-ok lane/measure, and `status` is complete, partial, or
      empty. A value that was not measured is `null`, never zero.

  report.py render [< report.json]
      Print the markdown rendering of a report document read from stdin.

  report.py resummarize [< report.json]
      Recompute `summary` from `measures[]` and print the document; for a
      skill that drops rows after assembly (a duplication registry moving
      clone groups into `excluded[]`). Clone-group rows (`instances[]`) add
      `summary.duplicated_lines` and `summary.clone_groups`.

Exit 0 on success, 2 on a usage error or unreadable input.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import json
import sys
from typing import Any

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


def summarize(measures: list[dict[str, Any]]) -> dict[str, Any]:
    """The `summary` block, derived from `measures[]` alone so a skill that
    drops rows after assembly (a duplication registry exclusion) can recompute
    it through the `resummarize` verb. Counts use each row's `over_reference`
    list as assembled; clone-group rows (those carrying `instances[]`) add
    `duplicated_lines` (sum of `values.lines`, each group counted once) and
    `clone_groups`, and their instance files count toward `files`."""
    files: set[str] = set()
    functions: set[tuple[str, str]] = set()
    over_counts: dict[str, int] = {}
    duplicated_lines = 0
    clone_groups = 0
    for row in measures:
        if row.get("file"):
            files.add(row["file"])
        # One function produces one row per collector that resolves for it
        # (lizard's cyclomatic row and radon's halstead row for the same
        # Python function), so a per-row count reports more functions than the
        # scope holds. A function is its file and its name; a row with no
        # `function` is a file row and is not one.
        if row.get("function"):
            functions.add((row.get("file") or "", row["function"]))
        for measure in row.get("over_reference", []):
            over_counts[measure] = over_counts.get(measure, 0) + 1
        instances = row.get("instances")
        if instances:
            clone_groups += 1
            lines = (row.get("values") or {}).get("lines")
            if isinstance(lines, (int, float)) and not isinstance(lines, bool):
                duplicated_lines += int(lines)
            for instance in instances:
                if instance.get("file"):
                    files.add(instance["file"])
    summary: dict[str, Any] = {
        "files": len(files),
        "functions": len(functions),
        "over_reference": over_counts,
    }
    if clone_groups:
        summary["duplicated_lines"] = duplicated_lines
        summary["clone_groups"] = clone_groups
    return summary


def assemble(
    skill: str,
    scope: dict[str, Any],
    run: list[dict[str, Any]],
    measures: list[dict[str, Any]],
    threshold_entries: list[dict[str, Any]],
    excluded: list[dict[str, Any]],
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
    # measured part of a lane reads as `partial` rather than as `empty`.
    ok_rows = [row for row in run if row.get("status") in ("ok", "partial")]
    settled = [row for row in run if row.get("status") in ("ok", "not-applicable")]
    if not ok_rows or not measures:
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
        "thresholds": [
            {k: v for k, v in entry.items() if k not in ("value_key", "direction")}
            for entry in threshold_entries
        ],
        "measures": measures,
        "summary": summarize(measures),
        "excluded": excluded,
        "unavailable": [
            f"{row.get('lane', '*')}/{row.get('measure', '*')}"
            for row in run
            if row.get("status") == "unavailable"
        ],
    }


def _fmt(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, float):
        return f"{value:.2f}".rstrip("0").rstrip(".")
    return str(value)


def render(doc: dict[str, Any]) -> str:
    lines: list[str] = []
    status = doc.get("status", "empty")
    headline = "Measured nothing" if status == "empty" else f"Status: {status}"
    scope = doc.get("scope", {})
    lines.append(f"# code-metrics: {doc.get('skill', '?')}")
    lines.append("")
    lines.append(
        f"{headline}. Scope: {scope.get('mode', '?')}"
        + (f" against `{scope['base']}`" if scope.get("base") else "")
        + f", {scope.get('files', 0)} file(s)"
        + (f", {scope['unclassified']} in no lane" if scope.get("unclassified") else "")
        + (f", {scope['excluded']} excluded" if scope.get("excluded") else "")
        + "."
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
    measures = doc.get("measures", [])
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
            "| File | Function | Lane | " + " | ".join(keys) + " | Over reference |"
        )
        lines.append(header)
        lines.append("|" + "---|" * (4 + len(keys)))
        shown = 0
        for row in sorted(
            measures,
            key=lambda r: (
                -len(r.get("over_reference", [])),
                r.get("file", ""),
                r.get("start_line") or 0,
            ),
        ):
            if shown >= MAX_RENDERED_ROWS:
                lines.append(
                    f"| ... | | | {' | '.join('' for _ in keys)} | {len(measures) - shown} more rows in the JSON |"
                )
                break
            values = row.get("values", {})
            where = row.get("file") or ""
            if row.get("instances"):
                where = ", ".join(
                    f"{i.get('file', '')}:{i.get('start_line', '?')}-{i.get('end_line', '?')}"
                    for i in row["instances"]
                )
            lines.append(
                f"| {where} | {row.get('function') or ''} | {row.get('lane', '')} | "
                + " | ".join(_fmt(values.get(k)) for k in keys)
                + f" | {', '.join(row.get('over_reference', [])) or ''} |"
            )
            shown += 1
    summary = doc.get("summary", {})
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    lines.append(
        f"Files: {summary.get('files', 0)}. Functions: {summary.get('functions', 0)}. "
        + "Over reference: "
        + (
            ", ".join(f"{k} {v}" for k, v in summary.get("over_reference", {}).items())
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
    if doc.get("unavailable"):
        lines.append("Unavailable: " + ", ".join(doc["unavailable"]) + ".")
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
    sub.add_parser("render")
    sub.add_parser("resummarize")
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
        )
        print(json.dumps(doc, indent=2))
        return 0
    doc = json.load(sys.stdin)
    if args.command == "resummarize":
        doc["summary"] = summarize(doc.get("measures", []))
        print(json.dumps(doc, indent=2))
        return 0
    sys.stdout.write(render(doc))
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
