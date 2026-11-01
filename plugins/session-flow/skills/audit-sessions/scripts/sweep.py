#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Report measured session metrics and threshold findings from the audit-sessions store.

    sweep.py --data-dir D [--since YYYY-MM-DD] [--until YYYY-MM-DD]
             [--scope machine|project] [--state-key K] [--catalog SKILL ...]
             [--canaries FILE] [--min-count N] [--versions N] [--session-floor N]
             [--format json|md] [--write-report] [--judged FILE] [--session ID ...]
    sweep.py --data-dir D --excerpts|--correction-candidates [--since ...] [--until ...] [--scope ...] [--state-key K]
             [--session ID ...]
    sweep.py --data-dir D --tickets PATTERN [--branch NAME] [--since ...] [--until ...] [--scope ...] [--state-key K]
             [--format json|md]

Reads only the `session-record/v1` files `collect.py` wrote; it never opens a transcript. Each
rule in `reference/sweep-rules.json` names one metric: per-session metrics report their median and
raise one finding listing every session above the threshold (the markdown report names the worst
few); a null threshold reports only. Each metric also reports this store's p90 beside the shipped
threshold and is marked `baseline_stale` when that p90 exceeds the rules file's `stale_p90_factor`
times the threshold; the mark is advisory and leaves the exit code unchanged.
Metrics and findings cover interactive sessions: a session whose stored entrypoints are all
headless or Agent SDK ones (`census.session_class`) is set aside and counted, one with no known
entrypoint is kept and counted, and the drift check reads every record. A
metric fed by a lost drift canary (census.py) is withheld. Prints one JSON envelope (or markdown)
on stdout; exit 0 pass, 1 warning (a metric degraded), 2 error, 3 no store under --data-dir.
Without --write-report it writes nothing. Stdlib only; Python 3.10+.

`--excerpts` prints, instead of the report, one JSON line per stored typed-turn excerpt inside the
window and scope (`project`, `session`, `started`, `excerpt`); `--format` and `--write-report` do
not apply. A record collected while redaction failed closed contributes none and makes the exit 1.
`--correction-candidates` prints the same excerpts with a stable `turn_id` and the collector's
`flags`, for the skill's model judge.

`--judged FILE` reads that judge's verdicts (a JSON array of `turn_id`, `verdict` of `correction`
or `not-correction`, and a one-line `reason`) into `data.judged`, the `Judged (unranked)` section:
its findings carry `"confidence": "judged"`, quote their excerpt, and never enter `data.findings`,
`data.suggestions` or the exit code. It refuses `--write-report`, so no saved report holds an excerpt.

`--session ID ...` limits metrics and findings to the named sessions, kept whatever their class,
for the skill's `now` action, and narrows the excerpt modes to them too. Each row's p90 and `baseline_stale` still come
from every interactive session in scope and window, and the drift check still reads every record.
The machine-wide and per-ticket metrics do not describe one session, so they are marked
`not_applicable` and raise no finding. It refuses `--write-report`, so the kept reports stay
machine or project ones.

`--tickets PATTERN` prints, instead of the report, a per-key rollup of the interactive sessions in
scope and window (schema `audit-sessions.tickets/v1`), for the skill's `ticket` action. A session's
key is the pattern's first match in its custom title, generated title, branches, then working
directory; a reused worktree's directory can name an older ticket, so it comes last. Per key: the
sessions, their summed output tokens, the first-start-to-last-end span (a session-side proxy, not
cycle time), the distinct linked PRs, and the gaps between consecutive sessions. `--branch NAME`
keeps only the key the pattern matches in NAME. It refuses `--session` and `--write-report`.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import statistics
import sys
from collections import Counter
from datetime import date, datetime, timezone
from pathlib import Path

import census

SCHEMA = "audit-sessions.sweep/v1"
TICKETS_SCHEMA = "audit-sessions.tickets/v1"
SPAN_LABEL = "session-side proxy, not cycle time"
RULES_SCHEMA = "audit-sessions.sweep-rules/v1"
# Placeholders collect.py stores in place of a path; neither names one file.
PLACEHOLDERS = {"<suppressed>", "<too-long>"}
BUNDLED_RULES = Path(__file__).resolve().parents[1] / "reference" / "sweep-rules.json"
KEEP_REPORTS = 20
# Sessions (or PRs) the markdown report names per finding; the JSON keeps every one.
MAX_LISTED = 5
JUDGED_TITLE = "Judged (unranked)"
JUDGED_NOTE = (
    "A model judged these turns, and no agreement figure against a labeled sample exists yet, so they are not ranked"
    " and change no measured finding."
)
VERDICTS = ("correction", "not-correction")
EXCERPT_KEYS = ("project", "session", "started", "excerpt")
CANDIDATE_KEYS = ("turn_id", "project", "session", "started", "flags", "excerpt")
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
    "time.active_s": lambda r: _get(r, "time", "active_gap_s"),
    "context.clear_commands": lambda r: _get(r, "context", "clear_commands"),
    "human.turns": lambda r: _get(r, "human", "turns"),
    "tools.interrupts": lambda r: _get(r, "tools", "interrupts"),
    "tools.denials": _denials,
    "subagents.count": lambda r: _get(r, "subagents", "count"),
    "hooks.stop_ms": lambda r: _get(r, "stop_hooks", "wait_ms_p90"),
}


def _write_5m_share(records: list[dict]) -> float | None:
    def total(ttl: str) -> float:
        return sum(_get(r, "tokens", side, f"cache_creation_{ttl}") or 0 for r in records for side in ("main", "sub"))

    five, hour = total("5m"), total("1h")
    return five / (five + hour) if five + hour else None


MACHINE_WIDE = {"cache.write_5m_share": _write_5m_share}
# Metrics whose value is not a median over sessions; the report names the statistic.
STATISTIC = {
    "cache.write_5m_share": "machine-wide ratio",
    "hooks.stop_ms": "median of per-session p90",
}


def _churn(records: list[dict]) -> list[tuple[int, dict]]:
    """Edits to one path within one linked PR, summed over the sessions that link only that PR.

    A session linking several PRs is left out: its edits cannot be split between them. Stored paths
    are relative to each session's own working directory, so each is joined back onto it first.
    """
    tickets: dict[tuple[str, int], tuple[Counter, dict]] = {}
    for r in records:
        edits, prs, cwd = r.get("edits"), r.get("prs"), r.get("cwd")
        paths = edits.get("by_relpath") if isinstance(edits, dict) else None
        if not isinstance(paths, dict) or not isinstance(prs, list) or len(prs) != 1 or not isinstance(prs[0], dict):
            continue
        repo, number = prs[0].get("repo"), prs[0].get("number")
        if not isinstance(repo, str) or not isinstance(number, int):
            continue
        counts, sessions = tickets.setdefault((repo, number), (Counter(), {}))
        for path, n in paths.items():
            if path not in PLACEHOLDERS and isinstance(n, int) and n > 0:
                path = Path(cwd, path).as_posix() if isinstance(cwd, str) and cwd else path
                counts[path] += n
                sessions.setdefault(path, set()).add(r["session_id"])
    return [
        (n, {"repo": repo, "number": number, "path": path, "edits": n, "sessions": sorted(sessions[path])})
        for (repo, number), (counts, sessions) in tickets.items()
        for path, n in counts.items()
    ]


PER_TICKET = {"edits.churn_per_pr": _churn}


def _denial_kinds(records: list[dict], sessions: set[str]) -> dict:
    """Denials per kind over the named sessions, most first with ties by kind, and the kind with the most."""
    counts: Counter = Counter()
    for r in records:
        tools = r.get("tools") if r.get("session_id") in sessions else None
        kinds = tools.get("denials") if isinstance(tools, dict) else None
        for kind, n in kinds.items() if isinstance(kinds, dict) else ():
            if isinstance(n, int):
                counts[kind] += n
    counts = +counts
    by_kind = dict(sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])))
    return {"by_kind": by_kind, "dominant_kind": next(iter(by_kind), None)}


# Fields a metric's finding adds, read from the records of the sessions over its threshold.
FINDING_DETAIL = {"tools.denials": _denial_kinds}
NOT_APPLICABLE = "not applicable with --session: this metric describes the machine or a linked PR, not one session"


def load_rules(path: Path) -> dict:
    rules = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(rules, dict) or rules.get("schema") != RULES_SCHEMA:
        raise ValueError(f"{path}: not an {RULES_SCHEMA} file")
    factor = rules.get("stale_p90_factor")
    if not isinstance(factor, (int, float)) or isinstance(factor, bool) or factor < 1:
        raise ValueError(f"{path}: stale_p90_factor must be a number of 1 or more")
    unknown = [r.get("metric") for r in rules["rules"] if r.get("metric") not in {**PER_SESSION, **MACHINE_WIDE, **PER_TICKET}]
    if unknown:
        raise ValueError(f"{path}: no extractor for metrics {unknown}")
    return rules


def p90(values: list[float]) -> float | None:
    """collect.py's `_percentile` rule, so a store p90 reads like a stored one."""
    if not values:
        return None
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(round(0.9 * (len(ordered) - 1))))]


def baseline_stale(store_p90: float | None, threshold: float | None, factor: float) -> bool:
    """The rules file's recheck trigger: one-sided, so a threshold of 0 fires on any p90 above 0."""
    return store_p90 is not None and threshold is not None and store_p90 > factor * threshold


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


def build_data(records, rules, drift, fed, scope, window, catalog, factor, population=None) -> dict:
    """`population`, given with --session, holds the in-scope sessions each row's p90 is taken over."""
    degraded = set(drift["degraded_metrics"])
    metrics, findings, unchecked = {}, [], []
    for rule in rules:
        metric, unit, threshold = rule["metric"], rule["unit"], rule["threshold"]
        if population is not None and metric not in PER_SESSION:
            metrics[metric] = {"value": None, "unit": unit, "n": 0, "p90": None, "threshold": threshold, "baseline_stale": False, "not_applicable": True}
            unchecked.append({"what": metric, "reason": NOT_APPLICABLE})
            continue
        if metric in MACHINE_WIDE:
            per, value = [], MACHINE_WIDE[metric](records)
            n = len(records)
        else:
            if metric in PER_TICKET:
                per = PER_TICKET[metric](records)
            else:
                per = [(v, {"session_id": r["session_id"]}) for r in records if (v := PER_SESSION[metric](r)) is not None]
            value, n = (statistics.median(v for v, _ in per) if per else None), len(per)
        if metric in degraded:
            metrics[metric] = {"value": None, "unit": unit, "n": n, "p90": None, "threshold": threshold, "baseline_stale": False, "degraded": True}
            unchecked.append({"what": metric, "reason": "unavailable: a drift canary feeding it is lost"})
            continue
        if population is None:
            store_p90 = p90([v for v, _ in per])
        else:
            store_p90 = p90([v for r in population if (v := PER_SESSION[metric](r)) is not None])
        stale = baseline_stale(store_p90, threshold, factor)
        metrics[metric] = {"value": value, "unit": unit, "n": n, "p90": store_p90, "threshold": threshold, "baseline_stale": stale}
        if metric not in fed:
            unchecked.append({"what": metric, "reason": "drift not checked: no canary feeds this metric"})
        if rule.get("caveat"):
            unchecked.append({"what": metric, "reason": rule["caveat"]})
        if threshold is None:
            reason = f"reported only, no threshold (basis measured on the reference machine, not this store): {rule['basis']}"
            unchecked.append({"what": metric, "reason": reason})
            continue
        over = sorted(((v, e) for v, e in per if v > threshold), key=lambda p: (-p[0], *_evidence_key(p[1])))
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
                "evidence": [e for _, e in over],
                "impact": impact(unit, sum(v - threshold for v, _ in over)),
                "confidence": rule["confidence"],
                "route": rule["route"],
                "suggested_skill": skill_label(rule["suggested_skill"], catalog),
                "basis": f"sweep-rules.json:{metric}",
                "degraded": False,
                **(FINDING_DETAIL[metric](records, {e["session_id"] for _, e in over}) if metric in FINDING_DETAIL else {}),
            }
        )
    why: dict[str, list[str]] = {}
    for finding in findings:
        why.setdefault(finding["suggested_skill"], []).append(finding["metric"])
    versions = sorted({v for r in records for v in r.get("cc_versions") or [] if isinstance(v, str)}, key=census.version_key)
    return {
        "window": {**window, "sessions": len(records), "cc_versions": versions},
        "scope": scope,
        "stale_p90_factor": factor,
        "metrics": metrics,
        "findings": findings,
        "drift": {k: drift[k] for k in ("window", "counts", "changes", "degraded_metrics")},
        "unchecked": unchecked,
        "suggestions": [{"skill": s, "why": "findings on " + ", ".join(m)} for s, m in why.items()],
    }


def markdown_code(text: str) -> str:
    """One CommonMark code span whose contents cannot close it early.

    Drift keys and model names come from session transcripts. A backtick or a
    line break in one would end the span or the bullet. Line breaks become
    spaces. The fence is one backtick longer than the longest backtick run in
    the text, with a space of padding when that run is non-zero, which is the
    code-span rule. Pointer: https://spec.commonmark.org/0.31.2/#code-spans
    """
    flat = " ".join(text.replace("\r", " ").replace("\n", " ").split())
    run = longest = 0
    for char in flat:
        if char == "`":
            run += 1
            longest = max(longest, run)
        else:
            run = 0
    fence = "`" * (longest + 1)
    if longest:
        return f"{fence} {flat} {fence}"
    return f"{fence}{flat}{fence}"


def drift_key_lines(changes: object) -> list[str]:
    """One markdown bullet per drift change, class then key path.

    The counts line names how many keys moved. These lines name them. A model
    other than the all-models bucket is included so two rows for one key stay
    distinct. No cap: a hidden key is the gap this report exists to close.
    Only the census classes are emitted; the class word is ours, not the
    transcript's.
    """
    if not isinstance(changes, list):
        return []
    order = {cls: index for index, cls in enumerate(census.CLASSES)}
    rows: list[tuple[int, str, str, str, str]] = []
    for change in changes:
        if not isinstance(change, dict):
            continue
        key = change.get("key")
        cls = change.get("class")
        if not isinstance(key, str) or not key or cls not in order:
            continue
        model = change.get("model")
        suffix = ""
        if isinstance(model, str) and model and model != "*":
            suffix = f" ({markdown_code(model)})"
        rows.append((order[cls], key, str(model or ""), cls, suffix))
    rows.sort()
    return [f"- {cls}: {markdown_code(key)}{suffix}" for _, key, _, cls, suffix in rows]


def _fmt(value: object) -> str:
    if value is None:
        return "n/a"
    if isinstance(value, float):
        return f"{value:.2f}" if abs(value) < 10 else f"{value:,.0f}"
    return f"{value:,}" if isinstance(value, int) else str(value)


def _evidence_key(e: dict) -> tuple:
    return (e.get("repo", ""), e.get("number", 0), e.get("path", ""), e.get("session_id", ""))


def evidence_md(e: dict) -> str:
    """A session ID, or a path within a linked PR with its edit count."""
    if "session_id" in e:
        return e["session_id"]
    return f"{markdown_code(e['repo'])}#{e['number']} {markdown_code(e['path'])} ({e['edits']} edits: {', '.join(e['sessions'])})"


def evidence_list_md(evidence: list[dict]) -> str:
    """The worst MAX_LISTED entries, then how many more the JSON report holds."""
    text = ", ".join(evidence_md(e) for e in evidence[:MAX_LISTED])
    more = len(evidence) - MAX_LISTED
    if more > 0:
        text += f", and {more} more (the JSON report lists all {len(evidence)})"
    return text


def judged_md(judged: dict) -> list[str]:
    """The judged section; each excerpt and reason sits in one code span, so stored text opens no markdown."""
    counts = judged["counts"]
    lines = [
        "",
        f"## {judged['title']}",
        "",
        judged["note"],
        "",
        f"Candidates: {counts['candidates']}; judged a correction: {counts['correction']}; judged not a correction:"
        f" {counts['not-correction']}; without a verdict: {counts['unjudged']}; verdicts matching no candidate:"
        f" {counts['unmatched']}.",
    ]
    if judged["findings"]:
        lines.append("")
        lines += [
            f"- {markdown_code(f['turn_id'])}: {markdown_code(f['excerpt'])} (reason: {markdown_code(f['reason'])})"
            for f in judged["findings"]
        ]
    return lines


def render_md(data: dict) -> str:
    window = data["window"]
    span = f"{window['since'] or 'start'} to {window['until'] or 'now'}"
    versions = ", ".join(window["cc_versions"]) or "none"
    sessions = f"Sessions: {window['sessions']} ({span}); Claude Code {versions}"
    if window.get("automated_set_aside"):
        n = window["automated_set_aside"]
        sessions += f"; {n} automated session{'s' * (n != 1)} set aside"
    if window.get("unclassified"):
        n = window["unclassified"]
        sessions += f"; {n} session{'s' * (n != 1)} without an entrypoint kept"
    if window.get("sessions_not_found"):
        sessions += "; named but not in the store: " + ", ".join(markdown_code(s) for s in window["sessions_not_found"])
    lines = [f"# Session audit ({data['scope']})", "", sessions, ""]
    lines += [
        "## Metrics",
        "",
        "| Metric | Value | Statistic | Store p90 | Threshold | Unit | n |",
        "|---|---|---|---|---|---|---|",
    ]
    for metric, row in data["metrics"].items():
        if row.get("not_applicable"):
            value = "not applicable"
        else:
            value = "unavailable (canary lost)" if row.get("degraded") else _fmt(row["value"])
        store_p90 = _fmt(row.get("p90")) + (" (stale baseline)" if row.get("baseline_stale") else "")
        lines.append(
            f"| `{metric}` | {value} | {STATISTIC.get(metric, 'median')} | {store_p90} | {_fmt(row.get('threshold'))} | "
            f"{row['unit']} | {row['n']} |"
        )
    stale = [metric for metric, row in data["metrics"].items() if row.get("baseline_stale")]
    if stale:
        lines += [
            "",
            f"Stale baseline: this store's p90 exceeds {_fmt(data['stale_p90_factor'])} times the shipped threshold for "
            + ", ".join(f"`{m}`" for m in stale)
            + ". The thresholds are a reference machine's baseline (`reference/sweep-rules.json`), so a finding on"
            " these metrics may flag normal use here. Advisory: it does not change the exit code.",
        ]
    lines += ["", "## Findings", ""]
    if data["findings"]:
        lines += ["| Lens | Metric | Worst | Threshold | Over | Route | Suggested |", "|---|---|---|---|---|---|---|"]
        for f in data["findings"]:
            lines.append(
                f"| {f['lens']} | `{f['metric']}` | {_fmt(f['value'])} {f['unit']} | {_fmt(f['threshold'])} | "
                f"{len(f['evidence'])} | {f['route']} | {f['suggested_skill']} |"
            )
        lines += ["", f"Sessions, or linked PRs, over each threshold, worst {MAX_LISTED} first:", ""]
        lines += [f"- `{f['metric']}`: " + evidence_list_md(f["evidence"]) for f in data["findings"]]
        for f in data["findings"]:
            if f.get("by_kind"):
                kinds = ", ".join(f"{markdown_code(kind)} {n:,}" for kind, n in f["by_kind"].items())
                lines += ["", f"`{f['metric']}` by kind over those sessions: {kinds}; dominant: {markdown_code(f['dominant_kind'])}."]
    else:
        lines.append("No session is over a threshold.")
    if "judged" in data:
        lines += judged_md(data["judged"])
    drift = data["drift"]
    counts = ", ".join(f"{n} {cls}" for cls, n in drift["counts"].items() if n) or "none"
    lines += ["", "## Drift", "", f"Changes since the baseline versions: {counts}."]
    named = drift_key_lines(drift.get("changes"))
    if named:
        lines.append("")
        lines.extend(named)
    if drift["degraded_metrics"]:
        if named:
            lines.append("")
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
    for old in sorted(reports.glob("*.json"))[:-KEEP_REPORTS]:
        for path in (old, old.with_suffix(".md")):
            path.unlink(missing_ok=True)


def project_of(record: dict) -> str | None:
    for key in ("repo_identity", "cwd"):
        if isinstance(record.get(key), str) and record[key]:
            return record[key]
    return None


def flagged_turns(records: list[dict]) -> tuple[list[dict], int]:
    """Each stored typed-turn excerpt, and how many records hold none because redaction failed closed.

    `turn_id` is the session ID and the turn's transcript index (`idx`), so a re-collect of the same
    transcript yields the same ID.
    """
    lines, suppressed = [], 0
    for record in records:
        redaction = record.get("redaction")
        if isinstance(redaction, dict) and redaction.get("excerpts_suppressed"):
            suppressed += 1
            continue
        human, start = record.get("human"), record.get("time")
        turns = human.get("flagged") if isinstance(human, dict) else None
        for position, turn in enumerate(turns if isinstance(turns, list) else []):
            text = turn.get("excerpt") if isinstance(turn, dict) else None
            if isinstance(text, str) and text:
                idx, flags = turn.get("idx"), turn.get("flags")
                index = idx if isinstance(idx, int) and not isinstance(idx, bool) else f"n{position}"
                lines.append(
                    {
                        "turn_id": f"{record.get('session_id')}:{index}",
                        "project": project_of(record),
                        "session": record.get("session_id"),
                        "started": start.get("start") if isinstance(start, dict) else None,
                        "flags": [f for f in flags if isinstance(f, str)] if isinstance(flags, list) else [],
                        "excerpt": text,
                    }
                )
    return lines, suppressed


def print_turns(records: list[dict], keys: tuple[str, ...]) -> int:
    """One JSON line per stored typed-turn excerpt; the text stays a JSON string, never a shell word."""
    turns, suppressed = flagged_turns(records)
    for turn in turns:
        sys.stdout.write(json.dumps({key: turn[key] for key in keys}) + "\n")
    if suppressed:
        print(f"sweep.py: {suppressed} records in scope hold no excerpts: redaction failed closed at collect", file=sys.stderr)
        return 1
    return 0


def load_verdicts(path: Path) -> dict[str, dict]:
    entries = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(entries, list):
        raise ValueError(f"{path}: not a JSON array of verdicts")
    verdicts: dict[str, dict] = {}
    for entry in entries:
        turn_id = entry.get("turn_id") if isinstance(entry, dict) else None
        if not isinstance(turn_id, str) or entry.get("verdict") not in VERDICTS or not isinstance(entry.get("reason"), str):
            raise ValueError(f"{path}: each verdict needs a string turn_id, a verdict of {' or '.join(VERDICTS)} and a string reason")
        if turn_id in verdicts:
            raise ValueError(f"{path}: two verdicts for one turn_id")
        verdicts[turn_id] = entry
    return verdicts


def judged_section(turns: list[dict], verdicts: dict[str, dict], scope: str, catalog: set[str] | None) -> dict:
    """The judge's verdicts joined onto this run's candidates; each `correction` verdict is one finding."""
    ids = {turn["turn_id"] for turn in turns}
    findings = [
        {
            "finding_id": hashlib.sha256(f"correction|{turn['turn_id']}|{scope}".encode()).hexdigest()[:16],
            "lens": "correction",
            "turn_id": turn["turn_id"],
            "session_id": turn["session"],
            "project": turn["project"],
            "started": turn["started"],
            "flags": turn["flags"],
            "excerpt": turn["excerpt"],
            "verdict": "correction",
            "reason": " ".join(verdicts[turn["turn_id"]]["reason"].split()),
            "confidence": "judged",
            "route": "retro-codify",
            "suggested_skill": skill_label("/corrections:codify", catalog),
        }
        for turn in turns
        if verdicts.get(turn["turn_id"], {}).get("verdict") == "correction"
    ]
    judged = [verdicts[turn_id]["verdict"] for turn_id in ids if turn_id in verdicts]
    return {
        "title": JUDGED_TITLE,
        "note": JUDGED_NOTE,
        "agreement": None,
        "counts": {
            "candidates": len(ids),
            "correction": judged.count("correction"),
            "not-correction": judged.count("not-correction"),
            "unjudged": len(ids) - len(judged),
            "unmatched": len(set(verdicts) - ids),
        },
        "findings": findings,
    }


def _epoch(value: object) -> float | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return (parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)).timestamp()


def first_match(pattern: re.Pattern, texts: list[object]) -> str | None:
    for text in texts:
        match = pattern.search(text) if isinstance(text, str) else None
        if match and match.group(0):
            return match.group(0)
    return None


def ticket_key(record: dict, pattern: re.Pattern) -> str | None:
    keys = record.get("link_keys") if isinstance(record.get("link_keys"), dict) else {}
    branches = record.get("branches") if isinstance(record.get("branches"), list) else []
    return first_match(pattern, [keys.get("custom_title"), keys.get("ai_title"), *branches, record.get("cwd")])


def ticket_row(key: str, members: list[dict]) -> dict:
    """Sessions in start order; a gap runs from the latest end so far to the next start, never below 0."""
    timed = []
    for r in members:
        times = r.get("time") if isinstance(r.get("time"), dict) else {}
        start = _epoch(times.get("start"))
        timed.append((start, _epoch(times.get("end")) or start, r))
    timed.sort(key=lambda t: (t[0] is None, t[0] or 0, t[2]["session_id"]))
    gaps, latest = [], None
    for start, end, _ in timed:
        if start is None:
            continue
        if latest is not None:
            gaps.append(round(max(0.0, start - latest)))
        latest = end if latest is None else max(latest, end)
    starts = [start for start, _, _ in timed if start is not None]
    prs = {(p.get("repo"), p.get("number")) for r in members for p in r.get("prs") or [] if isinstance(p, dict)}
    return {
        "key": key,
        "sessions": [r["session_id"] for _, _, r in timed],
        "output_tokens": sum(_get(r, "tokens", side, "output") or 0 for r in members for side in ("main", "sub")),
        "span_s": round(latest - min(starts)) if starts else None,
        "prs": len(prs),
        "gaps_s": gaps,
    }


def ticket_data(records: list[dict], pattern: re.Pattern, branch: str | None) -> dict:
    groups: dict[str, list[dict]] = {}
    for r in records:
        if (key := ticket_key(r, pattern)) is not None:
            groups.setdefault(key, []).append(r)
    data = {"pattern": pattern.pattern, "span_label": SPAN_LABEL, "unkeyed": len(records) - sum(map(len, groups.values()))}
    if branch is not None:
        data["branch_key"] = first_match(pattern, [branch])
        groups = {k: v for k, v in groups.items() if k == data["branch_key"]}
    data["tickets"] = [ticket_row(key, groups[key]) for key in sorted(groups)]
    return data


def _hours(seconds: float | None) -> str:
    return "n/a" if seconds is None else f"{seconds / 3600:.1f}"


def tickets_md(data: dict) -> str:
    window = data["window"]
    span = f"{window['since'] or 'start'} to {window['until'] or 'now'}"
    lines = [
        f"# Ticket rollup ({data['scope']})",
        "",
        f"Sessions: {window['sessions']} ({span}); {data['unkeyed']} with no key matching {markdown_code(data['pattern'])};"
        f" {window['automated_set_aside']} automated set aside",
    ]
    if "branch_key" in data:
        lines[-1] += "; branch key: " + (markdown_code(data["branch_key"]) if data["branch_key"] else "none")
    lines += ["", f"Span runs from the first session's start to the last one's end: a {data['span_label']}.", ""]
    if not data["tickets"]:
        return "\n".join(lines + ["No session has a matching key."]) + "\n"
    lines += ["| Key | Sessions | Output tokens | Span (h) | PRs | Gaps between sessions (h) |", "|---|---|---|---|---|---|"]
    for t in data["tickets"]:
        gaps = ", ".join(_hours(g) for g in t["gaps_s"]) or "none"
        lines.append(f"| {markdown_code(t['key'])} | {len(t['sessions'])} | {_fmt(t['output_tokens'])} | {_hours(t['span_s'])} | {t['prs']} | {gaps} |")
    return "\n".join(lines) + "\n"


def _pattern(value: str) -> re.Pattern:
    try:
        return re.compile(value)
    except re.error as exc:
        raise argparse.ArgumentTypeError(f"not a regular expression: {exc}") from exc


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
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--excerpts", action="store_true", help="print stored typed-turn excerpts as JSON lines")
    mode.add_argument("--correction-candidates", action="store_true", help="print the excerpts with a turn_id for the judge")
    mode.add_argument("--judged", help="the judge's verdict file, merged as a separate unranked section")
    mode.add_argument("--tickets", type=_pattern, help="print a per-key rollup, keys matched by this regular expression")
    parser.add_argument("--branch", help="with --tickets, only the key this pattern matches in the branch name")
    parser.add_argument("--session", nargs="+", action="extend", help="only these session ids")
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        if exc.code == 0:
            raise
        return emit("json", "error", "bad arguments", {}, 2)
    if args.judged is not None and args.write_report:
        return emit("json", "error", "--judged findings quote excerpts, so --judged refuses --write-report", {}, 2)
    if args.session and args.write_report:
        return emit("json", "error", "--session reports are not kept, so --session refuses --write-report", {}, 2)
    if args.tickets is not None and (args.session or args.write_report):
        return emit("json", "error", "--tickets refuses --session and --write-report", {}, 2)
    if args.branch is not None and args.tickets is None:
        return emit("json", "error", "--branch needs --tickets", {}, 2)
    if args.scope == "project" and not (args.state_key and STATE_KEY_RE.fullmatch(args.state_key)):
        return emit("json", "error", "--scope project needs --state-key <identity>/<worktree>", {}, 2)
    data_dir = Path(args.data_dir)
    if not census.store_dir(data_dir).is_dir():
        # Its own code, so a consumer can tell "never collected here" from a broken store.
        return emit("json", "error", f"no audit-sessions store under {data_dir}; run collect first", {}, 3)
    try:
        records, skipped = census.load_records(data_dir)
        canaries = census.load_canaries(Path(args.canaries))["canaries"]
        rules_file = load_rules(BUNDLED_RULES)
        verdicts = load_verdicts(Path(args.judged)) if args.judged is not None else None
    except (OSError, ValueError, KeyError, TypeError) as exc:
        return emit("json", "error", str(exc), {}, 2)
    if skipped:
        message = f"{skipped} store files unreadable or not {census.RECORD_SCHEMA}; re-run collect"
        return emit("json", "error", message, {}, 2)
    if args.scope == "project":
        identity = args.state_key.rsplit("/", 1)[0]
        scope, key = f"repo:{identity}", args.state_key
        scoped = [r for r in records if r.get("repo_identity") == identity]
    else:
        scope, key, scoped = "machine", "machine", records
    scoped = [r for r in scoped if in_window(r, args.since, args.until)]
    population = [r for r in scoped if census.session_class(r) != "automated"]
    named = set(args.session or ())
    if named:
        scoped = [r for r in scoped if r.get("session_id") in named]
    if args.excerpts or args.correction_candidates:
        # Typed turns come from people: an automated session's turns are a script's.
        keys = CANDIDATE_KEYS if args.correction_candidates else EXCERPT_KEYS
        return print_turns([r for r in scoped if census.session_class(r) != "automated"], keys)
    if args.tickets is not None:
        data = ticket_data(population, args.tickets, args.branch)
        window = {"since": args.since and args.since.isoformat(), "until": args.until and args.until.isoformat()}
        data.update(scope=scope, window={**window, "sessions": len(population), "automated_set_aside": len(scoped) - len(population)})
        if args.format == "md":
            sys.stdout.write(tickets_md(data))
        else:
            summary = f"{len(data['tickets'])} keys over {len(population)} sessions"
            print(json.dumps({"schema": TICKETS_SCHEMA, "status": "pass", "summary": summary, "data": data}, indent=2))
        return 0
    drift = census.drift(
        records, canaries, min_count=args.min_count, versions=args.versions, session_floor=args.session_floor
    )
    stored = {r.get("session_id") for r in records}
    records = scoped
    classes = Counter(census.session_class(r) for r in records)
    if named:
        # A session named on purpose is measured whatever its class.
        classes["automated"] = 0
    else:
        records = [r for r in records if census.session_class(r) != "automated"]
    window = {
        "since": args.since and args.since.isoformat(),
        "until": args.until and args.until.isoformat(),
        "automated_set_aside": classes["automated"],
        "unclassified": classes["unknown"],
    }
    if named:
        window["session_ids"] = sorted(named)
        window["sessions_not_found"] = sorted(named - stored)
    fed = {metric for canary in canaries for metric in canary["feeds"]}
    catalog = {name.lstrip("/") for name in args.catalog} if args.catalog else None
    factor = rules_file["stale_p90_factor"]
    data = build_data(
        records, rules_file["rules"], drift, fed, scope, window, catalog, factor, population=population if named else None
    )
    summary = f"{len(records)} sessions, {len(data['findings'])} findings"
    if verdicts is not None:
        data["judged"] = judged_section(flagged_turns(records)[0], verdicts, scope, catalog)
        summary += f"; {len(data['judged']['findings'])} judged corrections (unranked)"
    if classes["automated"]:
        summary += f"; {classes['automated']} automated set aside"
    status, code = "pass", 0
    if drift["degraded_metrics"]:
        status, code = "warning", 1
        summary += "; unavailable: " + ", ".join(drift["degraded_metrics"])
    if args.write_report:
        write_report(data_dir, key, {"schema": SCHEMA, "status": status, "summary": summary, "data": data})
    return emit(args.format, status, summary, data, code)


if __name__ == "__main__":
    sys.exit(main())
