#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Report measured session metrics and threshold findings from the audit-sessions store.

    sweep.py --data-dir D [--since YYYY-MM-DD] [--until YYYY-MM-DD]
             [--scope machine|project] [--state-key K] [--catalog SKILL ...]
             [--canaries FILE] [--min-count N] [--versions N] [--session-floor N]
             [--format json|md] [--write-report]

Reads only the `session-record/v1` files `collect.py` wrote; it never opens a transcript. Each
rule in `reference/sweep-rules.json` names one metric: per-session metrics report their median and
raise one finding listing every session above the threshold; a null threshold reports only. A
metric fed by a lost drift canary (census.py) is withheld. Prints one JSON envelope (or markdown)
on stdout; exit 0 pass, 1 warning (a metric degraded), 2 error. Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import statistics
import sys
from datetime import date, datetime, timezone
from pathlib import Path

import census

SCHEMA = "audit-sessions.sweep/v1"
RULES_SCHEMA = "audit-sessions.sweep-rules/v1"
BUNDLED_RULES = Path(__file__).resolve().parents[1] / "reference" / "sweep-rules.json"
KEEP_REPORTS = 20
STATE_KEY_RE = re.compile(r"[a-z0-9][a-z0-9._-]*(/[a-z0-9][a-z0-9._-]*)+")


def _get(record: dict, *path: str) -> float | None:
    value: object = record
    for key in path:
        value = value.get(key) if isinstance(value, dict) else None
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def _denials(record: dict) -> int | None:
    kinds = record.get("tools", {}).get("denials") if isinstance(record.get("tools"), dict) else None
    return sum(n for n in kinds.values() if isinstance(n, int)) if isinstance(kinds, dict) else None


PER_SESSION = {
    "tokens.main": lambda r: _get(r, "tokens", "main", "output"),
    "tokens.sub": lambda r: _get(r, "tokens", "sub", "output"),
    "cache.missed_input_tokens": lambda r: _get(r, "cache_miss", "missed_input_tokens"),
    "time.active_s": lambda r: _get(r, "time", "active_s"),
    "context.clear_commands": lambda r: _get(r, "context", "clear_commands"),
    "human.turns": lambda r: _get(r, "human", "turns"),
    "tools.interrupts": lambda r: _get(r, "tools", "interrupts"),
    "tools.denials": _denials,
    "subagents.count": lambda r: _get(r, "subagents", "count"),
    "hooks.stop_ms": lambda r: _get(r, "stop_hooks", "ms_p90"),
}


def _write_5m_share(records: list[dict]) -> float | None:
    def total(ttl: str) -> float:
        return sum(_get(r, "tokens", side, f"cache_creation_{ttl}") or 0 for r in records for side in ("main", "sub"))

    five, hour = total("5m"), total("1h")
    return five / (five + hour) if five + hour else None


MACHINE_WIDE = {"cache.write_5m_share": _write_5m_share}


def load_rules(path: Path) -> list[dict]:
    rules = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(rules, dict) or rules.get("schema") != RULES_SCHEMA:
        raise ValueError(f"{path}: not an {RULES_SCHEMA} file")
    unknown = [r.get("metric") for r in rules["rules"] if r.get("metric") not in {**PER_SESSION, **MACHINE_WIDE}]
    if unknown:
        raise ValueError(f"{path}: no extractor for metrics {unknown}")
    return rules["rules"]


def in_window(record: dict, since: date | None, until: date | None) -> bool:
    if since is None and until is None:
        return True
    start = record.get("time", {}).get("start") if isinstance(record.get("time"), dict) else None
    try:
        day = date.fromisoformat(start[:10])
    except (TypeError, ValueError):
        return False
    return (since is None or day >= since) and (until is None or day <= until)


def skill_label(skill: str, catalog: set[str] | None) -> str:
    if catalog is None or skill.lstrip("/").split()[0] in catalog:
        return skill
    return f"{skill} (not installed)"


def impact(unit: str, excess: float) -> dict | None:
    if unit == "tokens":
        return {"amount": excess, "unit": "tokens"}
    if unit == "s":
        return {"amount": round(excess / 60, 1), "unit": "min"}
    return None


def build_data(records, rules, drift, fed, scope, window, catalog) -> dict:
    degraded = set(drift["degraded_metrics"])
    metrics, findings, unchecked = {}, [], []
    for rule in rules:
        metric, unit, threshold = rule["metric"], rule["unit"], rule["threshold"]
        if metric in MACHINE_WIDE:
            per, value = [], MACHINE_WIDE[metric](records)
            n = len(records)
        else:
            per = [(v, r["session_id"]) for r in records if (v := PER_SESSION[metric](r)) is not None]
            value, n = (statistics.median(v for v, _ in per) if per else None), len(per)
        if metric in degraded:
            metrics[metric] = {"value": None, "unit": unit, "n": n, "degraded": True}
            unchecked.append({"what": metric, "reason": "unavailable: a drift canary feeding it is lost"})
            continue
        metrics[metric] = {"value": value, "unit": unit, "n": n}
        if metric not in fed:
            unchecked.append({"what": metric, "reason": "drift not checked: no canary feeds this metric"})
        if threshold is None:
            unchecked.append({"what": metric, "reason": f"reported only, no threshold: {rule['basis']}"})
            continue
        over = sorted(((v, sid) for v, sid in per if v > threshold), key=lambda p: (-p[0], p[1]))
        if not over:
            continue
        findings.append(
            {
                "finding_id": hashlib.sha256(f"{rule['lens']}|{metric}|{scope}".encode()).hexdigest()[:16],
                "lens": rule["lens"],
                "metric": metric,
                "scope": scope,
                "value": over[0][0],
                "unit": unit,
                "threshold": threshold,
                "evidence": [{"session_id": sid} for _, sid in over],
                "impact": impact(unit, sum(v - threshold for v, _ in over)),
                "confidence": rule["confidence"],
                "route": rule["route"],
                "suggested_skill": skill_label(rule["suggested_skill"], catalog),
                "basis": f"sweep-rules.json:{metric}",
                "degraded": False,
            }
        )
    why: dict[str, list[str]] = {}
    for finding in findings:
        why.setdefault(finding["suggested_skill"], []).append(finding["metric"])
    versions = sorted({v for r in records for v in r.get("cc_versions") or [] if isinstance(v, str)}, key=census.version_key)
    return {
        "window": {**window, "sessions": len(records), "cc_versions": versions},
        "scope": scope,
        "metrics": metrics,
        "findings": findings,
        "drift": {k: drift[k] for k in ("window", "counts", "degraded_metrics")},
        "unchecked": unchecked,
        "suggestions": [{"skill": s, "why": "findings on " + ", ".join(m)} for s, m in why.items()],
    }


def _fmt(value: object) -> str:
    if value is None:
        return "n/a"
    if isinstance(value, float):
        return f"{value:.2f}" if abs(value) < 10 else f"{value:,.0f}"
    return f"{value:,}" if isinstance(value, int) else str(value)


def render_md(data: dict) -> str:
    window = data["window"]
    span = f"{window['since'] or 'start'} to {window['until'] or 'now'}"
    versions = ", ".join(window["cc_versions"]) or "none"
    lines = [f"# Session audit ({data['scope']})", "", f"Sessions: {window['sessions']} ({span}); Claude Code {versions}", ""]
    lines += ["## Metrics", "", "| Metric | Value (per-session median) | Unit | n |", "|---|---|---|---|"]
    for metric, row in data["metrics"].items():
        value = "unavailable (canary lost)" if row.get("degraded") else _fmt(row["value"])
        lines.append(f"| `{metric}` | {value} | {row['unit']} | {row['n']} |")
    lines += ["", "## Findings", ""]
    if data["findings"]:
        lines += ["| Lens | Metric | Worst session | Threshold | Sessions over | Route | Suggested |", "|---|---|---|---|---|---|---|"]
        for f in data["findings"]:
            lines.append(
                f"| {f['lens']} | `{f['metric']}` | {_fmt(f['value'])} {f['unit']} | {_fmt(f['threshold'])} | "
                f"{len(f['evidence'])} | {f['route']} | {f['suggested_skill']} |"
            )
        lines += ["", "Sessions over each threshold, worst first:", ""]
        lines += [f"- `{f['metric']}`: " + ", ".join(e["session_id"] for e in f["evidence"]) for f in data["findings"]]
    else:
        lines.append("No session is over a threshold.")
    drift = data["drift"]
    counts = ", ".join(f"{n} {cls}" for cls, n in drift["counts"].items() if n) or "none"
    lines += ["", "## Drift", "", f"Changes since the baseline versions: {counts}."]
    if drift["degraded_metrics"]:
        lines.append("Unavailable metrics: " + ", ".join(f"`{m}`" for m in drift["degraded_metrics"]) + ".")
    lines += ["", "## Unchecked", ""] + [f"- `{u['what']}`: {u['reason']}" for u in data["unchecked"]]
    if data["suggestions"]:
        lines += ["", "## Suggestions", ""] + [f"- {s['skill']}: {s['why']}" for s in data["suggestions"]]
    return "\n".join(lines) + "\n"


def write_report(data_dir: Path, key: str, envelope: dict) -> None:
    reports = data_dir / "audit-sessions" / "reports" / Path(*key.split("/"))
    # Microseconds keep two runs in one second from sharing, and overwriting, one report pair.
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    data = envelope["data"]
    if not (census.write_atomic(reports / f"{stamp}.json", envelope) and census.write_atomic(reports / f"{stamp}.md", render_md(data))):
        print(f"sweep.py: report {stamp} not written: the target stayed locked", file=sys.stderr)
        return
    line = {"stamp": stamp, "scope": data["scope"], "sessions": data["window"]["sessions"]}
    line["metrics"] = {m: row["value"] for m, row in data["metrics"].items()}
    fd = os.open(reports / "history.jsonl", os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
    try:
        os.write(fd, (json.dumps(line, sort_keys=True) + "\n").encode("utf-8"))
    finally:
        os.close(fd)
    for old in sorted(reports.glob("*.json"))[:-KEEP_REPORTS]:
        for path in (old, old.with_suffix(".md")):
            path.unlink(missing_ok=True)


def emit(fmt: str, status: str, summary: str, data: dict, code: int) -> int:
    if fmt == "md" and status != "error":
        sys.stdout.write(render_md(data))
    else:
        print(json.dumps({"schema": SCHEMA, "status": status, "summary": summary, "data": data}, indent=2))
    return code


def _positive(value: str) -> int:
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError("must be 1 or more")
    return number


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Report session metrics and findings from the audit-sessions store.")
    parser.add_argument("--data-dir", required=True)
    parser.add_argument("--since", type=date.fromisoformat, help="sessions starting on or after this UTC date")
    parser.add_argument("--until", type=date.fromisoformat, help="sessions starting on or before this UTC date")
    parser.add_argument("--scope", choices=("machine", "project"), default="machine")
    parser.add_argument("--state-key", help="lib/state-key.sh output; required with --scope project")
    parser.add_argument("--catalog", nargs="+", action="extend", help="installed skills; others render (not installed)")
    parser.add_argument("--canaries", default=str(census.BUNDLED_CANARIES))
    parser.add_argument("--min-count", type=_positive, default=census.DEFAULT_MIN_COUNT)
    parser.add_argument("--versions", type=_positive, default=census.DEFAULT_VERSIONS)
    parser.add_argument("--session-floor", type=_positive, default=census.DEFAULT_SESSION_FLOOR)
    parser.add_argument("--format", choices=("json", "md"), default="json")
    parser.add_argument("--write-report", action="store_true")
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        if exc.code == 0:
            raise
        return emit("json", "error", "bad arguments", {}, 2)
    if args.scope == "project" and not (args.state_key and STATE_KEY_RE.fullmatch(args.state_key)):
        return emit("json", "error", "--scope project needs --state-key <identity>/<worktree>", {}, 2)
    data_dir = Path(args.data_dir)
    try:
        records, skipped = census.load_records(data_dir)
        canaries = census.load_canaries(Path(args.canaries))["canaries"]
        rules = load_rules(BUNDLED_RULES)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        return emit("json", "error", str(exc), {}, 2)
    if skipped:
        message = f"{skipped} store files unreadable or not {census.RECORD_SCHEMA}; re-run collect"
        return emit("json", "error", message, {}, 2)
    drift = census.drift(
        records, canaries, min_count=args.min_count, versions=args.versions, session_floor=args.session_floor
    )
    if args.scope == "project":
        identity = args.state_key.rsplit("/", 1)[0]
        scope, key = f"repo:{identity}", args.state_key
        records = [r for r in records if r.get("repo_identity") == identity]
    else:
        scope, key = "machine", "machine"
    records = [r for r in records if in_window(r, args.since, args.until)]
    window = {"since": args.since and args.since.isoformat(), "until": args.until and args.until.isoformat()}
    fed = {metric for canary in canaries for metric in canary["feeds"]}
    catalog = {name.lstrip("/") for name in args.catalog} if args.catalog else None
    data = build_data(records, rules, drift, fed, scope, window, catalog)
    summary = f"{len(records)} sessions, {len(data['findings'])} findings"
    status, code = "pass", 0
    if drift["degraded_metrics"]:
        status, code = "warning", 1
        summary += "; unavailable: " + ", ".join(drift["degraded_metrics"])
    if args.write_report:
        write_report(data_dir, key, {"schema": SCHEMA, "status": status, "summary": summary, "data": data})
    return emit(args.format, status, summary, data, code)


if __name__ == "__main__":
    sys.exit(main())
