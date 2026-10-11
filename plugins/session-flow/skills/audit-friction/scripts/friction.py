#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Deterministic steps of /session-flow:audit-friction, over the audit-sessions store.

    friction.py mine --data-dir D [--since YYYY-MM-DD] [--until YYYY-MM-DD] [--days N] [--project TEXT]
                     [--session ID ...] [--source DIR ...] [--save-baseline] [--out FILE] [--format json|md]
                     [--retention-days N] [--excerpt-chars N] [--excerpt-words N]
    friction.py cause --friction FILE [--merge FILE] [--out FILE] [--format json|md]
    friction.py estimate --inventory FILE [--probes N] [--format json|md]
    friction.py diff --current FILE (--baseline FILE | --data-dir D) [--format json|md]

`mine` filters stored session records (default: the last 7 days, every project) and aggregates their
`friction` blocks into one file: counts per event key and side, a class hint per key, command shapes,
secondary performance signals and the events themselves. `--source DIR` first runs the audit-sessions
collector over DIR (laid out like `~/.claude/projects`) into its own store under
`D/audit-friction/sources/`, so the machine store never mixes in another directory's sessions; the
retention and excerpt options pass through to that collect.
`cause` maps each denial and approved prompt to the permission rules that could match it, read from
`permission-merge.sh` output. `estimate` sizes each verification mode from a claim inventory, with token and wall-clock ranges.
`diff` compares a run with a baseline, per session and per active hour.

Reads the store only, never a transcript. Prints one JSON envelope (or markdown with --format md) on
stdout; exit 0 pass, 1 warning, 2 error. Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import math
import re
import subprocess
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parents[1]
COLLECTOR = SKILL_DIR.parent / "audit-sessions" / "scripts"
sys.path.insert(0, str(COLLECTOR))

import census  # noqa: E402  (the audit-sessions store helpers)

MINE_SCHEMA = "audit-friction.mine/v1"
CAUSE_SCHEMA = "audit-friction.cause/v1"
ESTIMATE_SCHEMA = "audit-friction.estimate/v1"
DIFF_SCHEMA = "audit-friction.diff/v1"
EVENT_LIMIT = 2000
TOP = 25
# Verification sizing: claims per blind verifier batch and recommendations per challenge agent.
BATCH = 12
CHALLENGE_BATCH = 3
WAVE = 8
# Verification usage as (low, high) ranges around one measured run of this audit (2026-10-09, Claude
# Code 2.1.296): a fact-check workflow of 50 agents, 5.53M tokens and 1 h 59 m, and one probe agent
# running 17 headless cases in 0.12M tokens and 64 min. Verify spent 3.26M over 32 batch agents (0.10M
# each) and Challenge 1.95M over 16 (0.12M each); pilot and ledger took 0.32M together. The run was 8
# sequential steps (pilot, 6 waves of 8, ledger), about 15 min each. Probes took 7K tokens and 3.8 min
# per case. The range widths are judgment. Recheck: remeasure from a run's workflow totals when the
# verifier agents, their model, or the batch sizes above change.
AGENT_TOKENS = (100_000, 125_000)
FIXED_TOKENS = 320_000
STEP_MINUTES = (12, 18)
PROBE_TOKENS = (6_000, 9_000)
PROBE_MINUTES = (3, 5)
CLASS_HINTS = (
    ("denied/", "D"),
    ("prompt-approved", "D"),
    ("agent-ask/approve", "C"),
    ("approve-reply", "C"),
    ("handoff/", "B"),
    ("user-command", "B"),
    ("interrupt", "A"),
    ("correction", "A"),
)
RULE_LINE = re.compile(r"^effective (allow|ask|deny) scopes=(\S+) precedence_basis=\S+ (.+)$")
RULE_SPEC = re.compile(r"^([\w*.-]+)(?:\((.*)\))?$", re.S)
SHAPE_FLAGS_MISS = frozenset({"cd-prefix", "env-prefix", "compound", "substitution", "heredoc", "multiline"})


def emit(schema: str, status: str, summary: str, data: dict, code: int, fmt: str = "json", md: str = "") -> int:
    if fmt == "md":
        print(md or summary)
    else:
        print(json.dumps({"schema": schema, "status": status, "summary": summary, "data": data}, indent=2))
    return code


def class_hint(key: str) -> str | None:
    return next((cls for prefix, cls in CLASS_HINTS if key.startswith(prefix)), None)


def _day(value: str) -> datetime:
    return datetime.strptime(value, "%Y-%m-%d").replace(tzinfo=timezone.utc)


def _ts(value: object) -> float | None:
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def source_store(data_dir: Path, source: Path) -> Path:
    digest = hashlib.sha256(str(source.resolve()).encode("utf-8")).hexdigest()[:12]
    return data_dir / "audit-friction" / "sources" / f"s-{digest}"


def collect_source(data_dir: Path, source: Path, since: str, options: list[str]) -> tuple[Path, dict]:
    target = source_store(data_dir, source)
    done = subprocess.run(
        [sys.executable, str(COLLECTOR / "collect.py"), "collect", "--data-dir", str(target),
         "--projects-root", str(source), "--since", since, *options],
        capture_output=True, text=True, encoding="utf-8", timeout=3600,
    )
    try:
        envelope = json.loads(done.stdout)
    except ValueError:
        envelope = {"status": "error", "summary": done.stderr.strip()[-400:]}
    return target, envelope


def selected(record: dict, since: float, until: float, project: str | None, sessions: set[str]) -> bool:
    if sessions and record.get("session_id") not in sessions:
        return False
    block = record.get("time")
    if not isinstance(block, dict):
        block = {}
    start, end = _ts(block.get("start")), _ts(block.get("end"))
    if end is None or end < since or (start is not None and start >= until):
        return False
    if project:
        haystack = " ".join(str(record.get(k) or "") for k in ("repo_identity", "cwd")).lower()
        return project.lower() in haystack
    return True


def aggregate(records: list[dict]) -> dict:
    counts: dict[tuple[str, str], Counter] = defaultdict(Counter)
    shapes: Counter = Counter()
    flags: Counter = Counter()
    perf: Counter = Counter()
    events, dropped, active_s, turns = [], 0, 0, 0
    classes = Counter(census.session_class(r) for r in records)
    for record in records:
        friction = record.get("friction")
        active_s += (record.get("time") or {}).get("active_s") or 0
        turns += (record.get("human") or {}).get("turns") or 0
        perf["usage_limit_notices"] += (record.get("rate_limit") or {}).get("usage_limit_notices") or 0
        perf["stop_hook_ms"] += (record.get("stop_hooks") or {}).get("ms_total") or 0
        if not isinstance(friction, dict):
            continue
        for side, keys in (friction.get("counts") or {}).items():
            for key, n in keys.items():
                counts[(side, key)]["count"] += n
                counts[(side, key)]["sessions"] += 1
        for name, value in (friction.get("perf") or {}).items():
            if name == "max_tool_wait_s":
                perf[name] = max(perf[name], value)
            else:
                perf[name] += value
        dropped += friction.get("events_dropped") or 0
        for event in friction.get("events") or []:
            if event.get("kind") in ("denied", "prompt-approved") and event.get("shape"):
                shapes[(event["kind"], event.get("cause"), event.get("tool"), event["shape"])] += 1
                flags.update(event.get("flags") or [])
            if len(events) < EVENT_LIMIT:
                events.append({"session_id": record.get("session_id"), **event})
            else:
                dropped += 1
    hours = active_s / 3600
    rows = [
        {
            "key": key,
            "side": side,
            "count": c["count"],
            "sessions": c["sessions"],
            "per_session": round(c["count"] / len(records), 3) if records else 0,
            "per_active_hour": round(c["count"] / hours, 3) if hours else None,
            "class_hint": class_hint(key),
        }
        for (side, key), c in counts.items()
    ]
    rows.sort(key=lambda r: (-r["count"], r["side"], r["key"]))
    return {
        "sessions": len(records),
        "session_classes": dict(classes),
        "active_hours": round(hours, 2),
        "typed_turns": turns,
        "rows": rows,
        "class_totals": dict(sum((Counter({r["class_hint"] or "-": r["count"]}) for r in rows), Counter())),
        "shapes": [
            {"kind": k, "cause": c, "tool": t, "shape": s, "count": n} for (k, c, t, s), n in shapes.most_common(TOP * 2)
        ],
        "shape_flags": dict(flags),
        "perf": dict(perf),
        "events": events,
        "events_dropped": dropped,
    }


def render_mine(data: dict) -> str:
    window = data["window"]
    lines = [
        f"# Friction: {window['since']} to {window['until']}",
        "",
        f"{data['sessions']} sessions ({', '.join(f'{v} {k}' for k, v in data['session_classes'].items()) or 'none'}), "
        f"{data['active_hours']} active hours, {data['typed_turns']} typed turns.",
        "",
        "| Class | Side | Key | Count | Sessions | Per active hour |",
        "|---|---|---|---|---|---|",
    ]
    for row in data["rows"][:TOP]:
        key = row["key"].replace("|", "\\|")
        lines.append(
            f"| {row['class_hint'] or '-'} | {row['side']} | {key} | {row['count']} | {row['sessions']} | "
            f"{row['per_active_hour'] if row['per_active_hour'] is not None else '-'} |"
        )
    if len(data["rows"]) > TOP:
        lines.append(f"\n{len(data['rows']) - TOP} more keys in the JSON output.")
    lines += ["", "Shape flags: " + (", ".join(f"{k} {v}" for k, v in sorted(data["shape_flags"].items())) or "none")]
    lines += ["", "Perf: " + (", ".join(f"{k} {v}" for k, v in sorted(data["perf"].items())) or "none")]
    return "\n".join(lines)


def cmd_mine(args: argparse.Namespace) -> int:
    data_dir = Path(args.data_dir)
    now = datetime.now(timezone.utc)
    try:
        since = _day(args.since) if args.since else (now - timedelta(days=args.days)).replace(hour=0, minute=0, second=0, microsecond=0)
        until = _day(args.until) + timedelta(days=1) if args.until else now + timedelta(seconds=1)
    except ValueError:
        return emit(MINE_SCHEMA, "error", "--since and --until take YYYY-MM-DD", {}, 2)
    stores, sources, warnings = [data_dir], [], []
    options = [part for flag in ("retention_days", "excerpt_chars", "excerpt_words") if getattr(args, flag) is not None
               for part in ("--" + flag.replace("_", "-"), str(getattr(args, flag)))]
    for source in args.source or []:
        if not Path(source).is_dir():
            return emit(MINE_SCHEMA, "error", f"--source is not a directory: {source}", {"source": source}, 2)
        store, envelope = collect_source(data_dir, Path(source), since.strftime("%Y-%m-%d"), options)
        sources.append({"source": source, "store": str(store), "status": envelope.get("status"), "summary": envelope.get("summary")})
        if envelope.get("status") == "error":
            warnings.append(f"source {source}: {envelope.get('summary')}")
            continue
        stores.append(store)
    records, skipped = [], 0
    for store in stores:
        try:
            found, bad = census.load_records(store)
        except FileNotFoundError as exc:
            if store == data_dir:
                return emit(MINE_SCHEMA, "error", str(exc), {"data_dir": str(data_dir)}, 2)
            warnings.append(str(exc))
            continue
        records += found
        skipped += bad
    wanted: set[str] = set(args.session or ())
    chosen = [r for r in records if selected(r, since.timestamp(), until.timestamp(), args.project, wanted)]
    unmined = sum(1 for r in chosen if not isinstance(r.get("friction"), dict))
    data = {
        "window": {"since": since.strftime("%Y-%m-%d"), "until": (until - timedelta(seconds=1)).strftime("%Y-%m-%d"),
                   "project": args.project, "sessions_filter": sorted(wanted)},
        "sources": sources,
        "skipped_records": skipped,
        "records_without_friction": unmined,
        **aggregate(chosen),
    }
    if unmined:
        warnings.append(f"{unmined} records predate friction mining; run collect.py collect to refresh them")
    data["warnings"] = warnings
    payload = {"schema": MINE_SCHEMA, "generated_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"), "data": data}
    written = []
    if args.out:
        census.write_atomic(Path(args.out), payload)
        written.append(args.out)
    if args.save_baseline:
        path = data_dir / "audit-friction" / "baselines" / f"{now.strftime('%Y%m%dT%H%M%S%fZ')}.json"
        census.write_atomic(path, payload)
        written.append(str(path))
    data["written"] = written
    summary = f"{sum(r['count'] for r in data['rows'])} friction events over {data['sessions']} sessions"
    status, code = ("warning", 1) if warnings else ("pass", 0)
    return emit(MINE_SCHEMA, status, summary, data, code, args.format, render_mine(data))


def load_payload(path: str) -> dict:
    payload = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(payload, dict) or payload.get("schema") != MINE_SCHEMA:
        raise ValueError(f"{path}: not an {MINE_SCHEMA} file")
    return payload["data"]


def parse_rules(text: str) -> list[dict]:
    rules = []
    for line in text.splitlines():
        match = RULE_LINE.match(line.strip())
        if match:
            spec = RULE_SPEC.match(match.group(3).strip())
            if spec:
                rules.append({"kind": match.group(1), "scopes": match.group(2), "rule": match.group(3).strip(),
                              "tool": spec.group(1), "spec": spec.group(2)})
    return rules


def rule_matches(rule: dict, tool: str | None, text: str | None) -> bool:
    """Whether a rule could match a call: tool name (a trailing `*` or `__*` wildcard allowed), then the
    specifier against the call's stored text, `:*` as a prefix and `*` as any run of characters."""
    if not tool or not fnmatch.fnmatchcase(tool, rule["tool"]):
        return False
    spec = rule["spec"]
    if spec is None or spec in ("", "*"):
        return True
    if text is None:
        return False
    if spec.endswith(":*"):
        return text.startswith(spec[:-2])
    return fnmatch.fnmatchcase(text, spec)


def cause_hint(kind: str, cause: str | None, flags: set[str], matched: list[dict], no_host: bool) -> str:
    kinds = {m["kind"] for m in matched}
    if kind == "prompt-approved":
        if "ask" in kinds:
            return "ask-rule"
        if "allow" in kinds:
            return "allow-rule-now-matches"
        return "shape-defeats-prefix-rules" if flags & SHAPE_FLAGS_MISS else "no-allow-rule"
    if cause == "classifier":
        return "classifier"
    if cause == "hook":
        return "hook"
    if cause == "user-rejected":
        return "person-declined"
    if "deny" in kinds:
        return "deny-rule"
    if "ask" in kinds:
        return "ask-without-prompt-host" if no_host else "ask-rule"
    return "rule-unmatched"


def cmd_cause(args: argparse.Namespace) -> int:
    try:
        data = load_payload(args.friction)
        rules = parse_rules(Path(args.merge).read_text(encoding="utf-8")) if args.merge else []
    except (OSError, ValueError) as exc:
        return emit(CAUSE_SCHEMA, "error", str(exc), {}, 2)
    groups: dict[tuple, dict] = {}
    for event in data["events"]:
        if event.get("kind") not in ("denied", "prompt-approved"):
            continue
        text = event.get("excerpt") or event.get("shape")
        matched = [r for r in rules if rule_matches(r, event.get("tool"), text)]
        flags = set(event.get("flags") or [])
        hint = cause_hint(event["kind"], event.get("cause"), flags, matched, bool(event.get("no_prompt_host")))
        key = (event["kind"], event.get("cause"), event.get("reason") if event.get("cause") != "hook" else event.get("hook"),
               event.get("tool"), event.get("shape"), hint)
        group = groups.setdefault(key, {
            "kind": key[0], "cause": key[1], "reason_or_hook": key[2], "tool": key[3], "shape": key[4], "hint": hint,
            "count": 0, "sides": Counter(), "flags": Counter(), "rules": {}, "sessions": set(),
        })
        group["count"] += 1
        group["sides"][event.get("side")] += 1
        group["flags"].update(flags)
        group["sessions"].add(event.get("session_id"))
        for rule in matched:
            group["rules"][rule["rule"]] = {"kind": rule["kind"], "rule": rule["rule"], "scopes": rule["scopes"]}
    rows = sorted(
        ({**g, "sides": dict(g["sides"]), "flags": dict(g["flags"]), "rules": list(g["rules"].values()),
          "sessions": len(g["sessions"])} for g in groups.values()),
        key=lambda r: (-r["count"], str(r["kind"]), str(r["shape"])),
    )
    out = {"rules_read": len(rules), "merge_input": bool(args.merge), "groups": rows}
    if args.out:
        census.write_atomic(Path(args.out), {"schema": CAUSE_SCHEMA, "data": out})
    md = ["| Count | Kind | Cause | Reason or hook | Shape | Hint | Rules |", "|---|---|---|---|---|---|---|"]
    for row in rows[:TOP]:
        rules_text = "; ".join(f"{r['kind']} {r['rule']}" for r in row["rules"]) or "-"
        cells = [row["count"], row["kind"], row["cause"] or "-", row["reason_or_hook"] or "-", row["shape"] or "-", row["hint"], rules_text]
        md.append("| " + " | ".join(str(c).replace("|", "\\|") for c in cells) + " |")
    status, code = ("pass", 0) if args.merge else ("warning", 1)
    summary = f"{len(rows)} cause groups" + ("" if args.merge else "; no --merge input, so no rule was matched")
    return emit(CAUSE_SCHEMA, status, summary, out, code, args.format, "\n".join(md))


def cmd_estimate(args: argparse.Namespace) -> int:
    try:
        inventory = json.loads(Path(args.inventory).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        return emit(ESTIMATE_SCHEMA, "error", str(exc), {}, 2)
    claims = inventory.get("claims") if isinstance(inventory, dict) else inventory
    if not isinstance(claims, list):
        return emit(ESTIMATE_SCHEMA, "error", "inventory holds no `claims` list", {}, 2)
    consequential = [c for c in claims if isinstance(c, dict) and c.get("consequential")]
    recommendations = [c for c in consequential if c.get("type") == "recommendation"]

    def mode(verify: list, challenge: list, probes: int) -> dict:
        agents = math.ceil(len(verify) / BATCH) + math.ceil(len(challenge) / CHALLENGE_BATCH)
        waves = math.ceil(agents / WAVE) if agents else 0
        steps = waves + 2 if agents else 0  # the pilot and the ledger run alone, before and after the waves
        fixed = FIXED_TOKENS if agents else 0
        return {
            "claims_checked": len(verify), "verifier_agents": agents, "waves": waves, "probe_cases": probes,
            "tokens": [agents * a + fixed + probes * p for a, p in zip(AGENT_TOKENS, PROBE_TOKENS)],
            # Probes run beside the fact-check, so the longer of the two sets the wall-clock time.
            "minutes": [max(steps * s, probes * p) for s, p in zip(STEP_MINUTES, PROBE_MINUTES)],
        }

    all_recs = [c for c in claims if isinstance(c, dict) and c.get("type") == "recommendation"]
    data = {
        "claims": len(claims),
        "consequential": len(consequential),
        "modes": {
            "probes": mode([], [], args.probes),
            "consequential": mode(consequential, recommendations, args.probes),
            "full": mode(claims, all_recs, args.probes),
        },
        "batch": BATCH, "challenge_batch": CHALLENGE_BATCH, "wave": WAVE,
    }
    md = ["| Mode | Claims checked | Agents | Waves | Probe cases | Tokens | Wall-clock |", "|---|---|---|---|---|---|---|"]
    for name, m in data["modes"].items():
        md.append(f"| {name} | {m['claims_checked']} | {m['verifier_agents']} | {m['waves']} | {m['probe_cases']} | "
                  f"{m['tokens'][0] / 1e6:.2f}M-{m['tokens'][1] / 1e6:.2f}M | {m['minutes'][0]}-{m['minutes'][1]} min |")
    summary = f"{len(claims)} claims, {len(consequential)} consequential"
    return emit(ESTIMATE_SCHEMA, "pass", summary, data, 0, args.format, "\n".join(md))


def cmd_diff(args: argparse.Namespace) -> int:
    try:
        current = load_payload(args.current)
        baseline_path = args.baseline
        if baseline_path is None:
            folder = Path(args.data_dir) / "audit-friction" / "baselines"
            older = sorted(p for p in folder.glob("*.json") if p.resolve() != Path(args.current).resolve())
            if not older:
                return emit(DIFF_SCHEMA, "error", f"no saved baseline under {folder}", {}, 2)
            baseline_path = str(older[-1])
        baseline = load_payload(baseline_path)
    except (OSError, ValueError) as exc:
        return emit(DIFF_SCHEMA, "error", str(exc), {}, 2)

    def rates(data: dict) -> dict[tuple[str, str], dict]:
        return {(r["side"], r["key"]): r for r in data["rows"]}

    before, after = rates(baseline), rates(current)
    rows = []
    for side, key in sorted(set(before) | set(after)):
        b, a = before.get((side, key)), after.get((side, key))
        b_rate = b["per_session"] if b else 0.0
        a_rate = a["per_session"] if a else 0.0
        verdict = "new" if not b else "gone" if not a else "fewer" if a_rate < b_rate else "more" if a_rate > b_rate else "same"
        rows.append({"side": side, "key": key, "class_hint": class_hint(key), "baseline_per_session": b_rate,
                     "current_per_session": a_rate, "delta": round(a_rate - b_rate, 3), "verdict": verdict})
    rows.sort(key=lambda r: (-abs(r["delta"]), r["key"]))
    worse = [r for r in rows if r["verdict"] in ("new", "more")]
    data = {
        "baseline": baseline_path,
        "baseline_window": baseline["window"], "current_window": current["window"],
        "sessions": {"baseline": baseline["sessions"], "current": current["sessions"]},
        "rows": rows,
        "worse": len(worse),
    }
    md = [f"Baseline {baseline['window']['since']}..{baseline['window']['until']} ({baseline['sessions']} sessions) vs "
          f"{current['window']['since']}..{current['window']['until']} ({current['sessions']} sessions), events per session.",
          "", "| Verdict | Class | Side | Key | Baseline | Current | Delta |", "|---|---|---|---|---|---|---|"]
    for r in rows[:TOP]:
        md.append(f"| {r['verdict']} | {r['class_hint'] or '-'} | {r['side']} | {r['key'].replace('|', chr(92) + '|')} | "
                  f"{r['baseline_per_session']} | {r['current_per_session']} | {r['delta']:+} |")
    status, code = ("warning", 1) if worse else ("pass", 0)
    return emit(DIFF_SCHEMA, status, f"{len(rows)} keys compared, {len(worse)} new or more frequent", data, code,
                args.format, "\n".join(md))


def _positive(value: str) -> int:
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError("must be 1 or more")
    return number


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    mine = sub.add_parser("mine")
    mine.add_argument("--data-dir", required=True)
    mine.add_argument("--since")
    mine.add_argument("--until")
    mine.add_argument("--days", type=_positive, default=7)
    mine.add_argument("--project")
    mine.add_argument("--session", nargs="+", action="extend")
    mine.add_argument("--source", nargs="+", action="extend")
    mine.add_argument("--save-baseline", action="store_true")
    mine.add_argument("--out")
    mine.add_argument("--format", choices=("json", "md"), default="json")
    # Passed to the collect --source runs, so a source store keeps the machine store's limits.
    for flag in ("--retention-days", "--excerpt-chars", "--excerpt-words"):
        mine.add_argument(flag, type=int)
    mine.set_defaults(func=cmd_mine)
    cause = sub.add_parser("cause")
    cause.add_argument("--friction", required=True)
    cause.add_argument("--merge")
    cause.add_argument("--out")
    cause.add_argument("--format", choices=("json", "md"), default="json")
    cause.set_defaults(func=cmd_cause)
    estimate = sub.add_parser("estimate")
    estimate.add_argument("--inventory", required=True)
    estimate.add_argument("--probes", type=int, default=0)
    estimate.add_argument("--format", choices=("json", "md"), default="json")
    estimate.set_defaults(func=cmd_estimate)
    diff = sub.add_parser("diff")
    diff.add_argument("--current", required=True)
    group = diff.add_mutually_exclusive_group(required=True)
    group.add_argument("--baseline")
    group.add_argument("--data-dir")
    diff.add_argument("--format", choices=("json", "md"), default="json")
    diff.set_defaults(func=cmd_diff)
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        if exc.code == 0:
            raise
        return emit("audit-friction/v1", "error", "bad arguments", {}, 2)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
