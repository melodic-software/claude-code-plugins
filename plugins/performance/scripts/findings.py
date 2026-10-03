"""Record keeper for /performance:go-faster: every read and write of its data folder.

The sweeper agent has no Write tool, so each file go-faster keeps is written here, under the data
folder passed as a literal argument. Subcommands:

    run-start --data <dir> --session <id> --mode attended|unattended --session-evidence true|false
                                        create runs/<UTC-stamp>/findings.json, print the run dir
    add --run <run-dir>                 append the finding(s) on stdin; refuse any that break a rule
    finish --run <run-dir>              validate the whole run, write report.md, print its path
    validate <findings.json>            exit 1 naming each rule a finding breaks
    rank <findings.json>                one `<section>\t<id>` line per finding, in report order
    render <findings.json>              the markdown report
    lint-catalog <dir|file>...          exit 1 naming each catalog row that breaks the grammar
    lock acquire|heartbeat|release|status --data <dir> --session <id>
    adopt --data <dir> --session <id> --findings <findings.json> --id <id> --route-taken <route>
    adopted --data <dir> --session <id> this session's adoptions, one JSON object per line
    compare --data <dir> --findings <findings.json> --id <id>
    transcript-counts <transcript.jsonl>
    status-timing --data <dir> [--runs N]  time git status in the current repository via trace2
    ci-timing --repo OWNER/REPO [--runs N] [--job-runs M]
                                        list N completed runs (default 20), fetch jobs for the M
                                        newest (default 5), print queue wait, run length, slowest
                                        step, test steps and re-runs as JSON
    pr-timing [--limit N]               list N merged PRs (default 20), print open to first
                                        review, open to merge and PR size as JSON

ci-timing and pr-timing run gh with the caller's environment (GH_CONFIG_DIR included), keep its
output in memory and write nothing to disk. Each number is an object with value, unit, samples
and command, the gh line(s) to cite; value is null when samples is 0, and excluded counts the
items left out because a timestamp it needs is missing or unparseable. Skipped jobs and steps
count toward no queue wait or step duration. Median: the middle of the sorted samples; with an
even count, the mean of the two middle ones. A gh call that fails, is missing, or prints
something other than JSON exits 1 with one line naming the call.

Field names are the finding record in agents/go-faster-sweeper.md. Exit 0 is success, 1 a refusal
the caller acts on (an invalid finding, a held lock, a failed gh call), 2 a usage or input error.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from collections.abc import Sequence
from pathlib import Path
from typing import NoReturn

AREAS = (
    "session-work",
    "how-you-work",
    "skills",
    "orchestration",
    "instructions",
    "hooks",
    "plugins-startup",
    "model-cache",
    "permissions",
    "gates",
    "ci-cd",
    "pr-review",
    "git",
    "bash-windows",
    "machine",
    "tests",
)
STATUSES = ("measured", "candidate", "flag-only", "not-checked")
TIERS = ("E1", "E2", "E3", "E4")
UNITS = ("elapsed-ms", "wait-ms", "turns", "tokens", "ci-minutes", "count")
REASON_CODES = (
    "no-data",
    "owner-unavailable",
    "needs-elevation",
    "needs-setting",
    "auth-gap",
    "refused-by-guard",
)
HORIZONS = ("now", "later")
ROUTES = ("performance-chain", "next-run")
CONFIDENCES = ("HIGH", "MEDIUM", "LOW", "judgment")
SOURCE_KINDS = ("session-count", "repo-count", "cited")
LOWERING = ("lower-verification", "lower-effort", "lower-model")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
OVERENGINEERING = "/overengineering:audit"


def die(message: str) -> NoReturn:
    print(f"error: {message}", file=sys.stderr)
    sys.exit(2)


def load(path: str) -> dict:
    try:
        doc = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        die(f"cannot read {path}: {exc}")
    if not isinstance(doc, dict) or not isinstance(doc.get("findings"), list):
        die(f"{path}: want an object with a findings array")
    return doc


def finding_errors(f: dict) -> list[str]:
    fid = f.get("id") or "<no id>"
    errors = []

    def need(cond: object, what: str) -> None:
        if not cond:
            errors.append(f"{fid}: {what}")

    for field in ("id", "key", "area", "title", "status"):
        need(isinstance(f.get(field), str) and f[field], f"{field} required")
    need(f.get("area") in AREAS, f"area must be one of {', '.join(AREAS)}")
    status = f.get("status")
    need(status in STATUSES, f"status must be one of {', '.join(STATUSES)}")
    if status in ("flag-only", "not-checked"):
        need(isinstance(f.get("reason"), str) and f["reason"], "reason required")
    if status == "not-checked":
        need(
            f.get("reason_code") in REASON_CODES,
            f"reason_code must be one of {', '.join(REASON_CODES)}",
        )
    if status in ("measured", "candidate"):
        need(f.get("tier") in TIERS, f"tier must be one of {', '.join(TIERS)}")
        need(f.get("unit") in UNITS, f"unit must be one of {', '.join(UNITS)}")
        need(isinstance(f.get("command"), str) and f["command"], "command required")
        need(
            isinstance(f.get("fix_owner"), str) and f["fix_owner"], "fix_owner required"
        )
        need(
            f.get("horizon") in HORIZONS,
            f"horizon must be one of {', '.join(HORIZONS)}",
        )
        need(f.get("route") in ROUTES, f"route must be one of {', '.join(ROUTES)}")
    if status == "measured":
        value = f.get("value")
        need(
            isinstance(value, (int, float)) and not isinstance(value, bool),
            "value must be a number",
        )
        need(isinstance(f.get("conditions"), dict), "conditions required")
    if f.get("fix_owner") == "steps-for-you":
        steps = f.get("fix_steps")
        need(
            isinstance(steps, list)
            and steps
            and all(isinstance(s, str) and s for s in steps),
            "fix_steps required",
        )
    effect = f.get("effect")
    if effect in ("fewer-checks", "drops-check"):
        need(
            isinstance(f.get("guard_metric"), str) and f["guard_metric"],
            "guard_metric required",
        )
    if effect == "drops-check":
        need(
            f.get("fix_owner") == OVERENGINEERING,
            f"drops-check findings route to {OVERENGINEERING}",
        )
    if f.get("horizon") == "now" and status != "flag-only":
        need(status == "measured", "horizon now needs a measured finding")
        need(f.get("tier") in ("E1", "E2"), "horizon now needs tier E1 or E2")
        need(
            isinstance(f.get("guard_metric"), str) and f["guard_metric"],
            "horizon now needs guard_metric",
        )
        need(
            isinstance(f.get("revert_if"), str) and f["revert_if"],
            "horizon now needs revert_if",
        )
        confidence = f.get("confidence", "HIGH")
        need(confidence == "HIGH", f"horizon now cannot rest on a {confidence} row")
        need(effect not in LOWERING, f"{effect} is flag-only")
        need(
            effect != "drops-check",
            f"drops-check cannot be horizon now; it goes to {OVERENGINEERING}",
        )
        need(
            not f.get("conflicts_instruction"),
            "a change that conflicts with a loaded instruction is flag-only",
        )
    if "confidence" in f:
        need(
            f["confidence"] in CONFIDENCES,
            f"confidence must be one of {', '.join(CONFIDENCES)}",
        )
    size = f.get("expected_size")
    if status == "candidate" and size is not None:
        size = size if isinstance(size, dict) else {}
        count = size.get("count")
        need(
            isinstance(count, (int, float)) and not isinstance(count, bool),
            "expected_size count must be a number",
        )
        need(
            size.get("source_kind") in SOURCE_KINDS,
            f"expected_size source_kind must be one of {', '.join(SOURCE_KINDS)}",
        )
        need(
            isinstance(size.get("source"), str) and size["source"],
            "expected_size source required",
        )
    for c in f.get("citations") or []:
        c = c if isinstance(c, dict) else {}
        need(
            isinstance(c.get("url"), str) and c["url"].startswith("http"),
            "citation url required",
        )
        need(
            isinstance(c.get("as_of"), str) and bool(DATE_RE.match(c["as_of"])),
            "citation as_of must be YYYY-MM-DD",
        )
        need(
            isinstance(c.get("recheck"), str) and c["recheck"],
            "citation recheck required",
        )
    return errors


def doc_errors(doc: dict) -> list[str]:
    errors = []
    ids = set()
    for f in doc["findings"]:
        if not isinstance(f, dict):
            errors.append("a finding is not an object")
            continue
        errors += finding_errors(f)
        if f.get("id") in ids:
            errors.append(f"{f['id']}: duplicate id")
        ids.add(f.get("id"))
    covered = {f.get("area") for f in doc["findings"] if isinstance(f, dict)}
    errors += [f"area not covered: {a}" for a in AREAS if a not in covered]
    return errors


def cmd_validate(args: argparse.Namespace) -> int:
    errors = doc_errors(load(args.file))
    for e in errors:
        print(e)
    return 1 if errors else 0


# Report order (Brief Q23, Q28). Elapsed and wait time are both wall-clock milliseconds, so they
# share the headline band; every other unit keeps a band of its own and is never converted.
OTHER_UNITS = tuple(u for u in UNITS if u not in ("elapsed-ms", "wait-ms"))


def section(f: dict) -> tuple[str, int]:
    status = f.get("status")
    if status == "measured":
        if f.get("unit") in ("elapsed-ms", "wait-ms"):
            return "elapsed", 0
        return f"unit:{f.get('unit')}", 1 + OTHER_UNITS.index(f["unit"])
    if status == "candidate":
        size = f.get("expected_size")
        if isinstance(size, dict) and size.get("source_kind") in SOURCE_KINDS:
            return f"candidate:{size['source_kind']}", 10 + SOURCE_KINDS.index(
                size["source_kind"]
            )
        return "candidate:unsized", 20
    return status or "unknown", 30 if status == "flag-only" else 40


def size_of(f: dict) -> float:
    if f.get("status") == "measured":
        return f.get("value") or 0
    size = f.get("expected_size")
    return size.get("count") or 0 if isinstance(size, dict) else 0


def ranked(doc: dict) -> list[tuple[str, dict]]:
    keyed = [(section(f), -size_of(f), i, f) for i, f in enumerate(doc["findings"])]
    keyed.sort(key=lambda k: (k[0][1], k[1], k[2]))
    return [(k[0][0], k[3]) for k in keyed]


def cmd_rank(args: argparse.Namespace) -> int:
    for name, f in ranked(load(args.file)):
        print(f"{name}\t{f['id']}")
    return 0


HEADINGS = {
    "elapsed": "Measured: elapsed time",
    "candidate": "Unmeasured candidates (not confirmed problems)",
    "flag-only": "Flagged for you only (guards and unclassifiable checks)",
    "not-checked": "Not checked",
}


def owner(f: dict) -> str:
    if f.get("fix_owner") == "steps-for-you":
        return "steps for you: " + "; ".join(f.get("fix_steps") or [])
    return f.get("fix_owner", "")


def line_for(f: dict) -> str:
    status = f.get("status")
    head = f"- **{f['title']}** ({f['area']}, `{f['id']}`)"
    if status == "measured":
        return (
            f"{head}: {f['value']} {f['unit']}, tier {f['tier']}, horizon {f['horizon']}. "
            f"Reproduce: `{f['command']}`. Fix: {owner(f)}. Route: {f['route']}."
        )
    if status == "candidate":
        size = f.get("expected_size")
        sized = (
            f"{size['count']} ({size['source_kind']}: {size['source']})"
            if isinstance(size, dict)
            else "unsized"
        )
        return f"{head}: tier {f['tier']}, expected size {sized}. Measure first: `{f['command']}`. Fix: {owner(f)}."
    if status == "not-checked":
        return f"- {f['area']}: not checked ({f.get('reason_code')}). {f.get('reason', '')}"
    return f"{head}: {f.get('reason', '')}"


def render(doc: dict) -> str:
    out = ["# go-faster report", ""]
    if not doc.get("session_evidence", True):
        out += ["No session evidence yet: setup scan only.", ""]
    current = None
    for name, f in ranked(doc):
        heading = (
            HEADINGS.get(name.split(":")[0]) or f"Measured: {name.split(':', 1)[1]}"
        )
        if heading != current:
            out += ["", f"## {heading}", ""]
            current = heading
        out.append(line_for(f))
    now = [
        f
        for f in doc["findings"]
        if f.get("horizon") == "now" and f.get("status") == "measured"
    ]
    if now:
        out += [
            "",
            "## Adopt now",
            "",
            "Reply per item. Each changes only how this session works.",
            "",
        ]
        for f in now:
            out.append(
                f"- `{f['id']}` {f['title']}. Guard: {f['guard_metric']}. Revert if: {f['revert_if']}."
            )
    return "\n".join(out) + "\n"


def cmd_render(args: argparse.Namespace) -> int:
    sys.stdout.write(render(load(args.file)))
    return 0


def now() -> float:
    """Epoch seconds; GO_FASTER_NOW pins the clock for tests."""
    pinned = os.environ.get("GO_FASTER_NOW")
    return float(pinned) if pinned else time.time()


def iso(epoch: float) -> str:
    return datetime.fromtimestamp(epoch, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_json(path: Path) -> dict | None:
    try:
        held = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return held if isinstance(held, dict) else None


def write_json(path: Path, data: dict, exclusive: bool = False) -> bool:
    """Write data as JSON; with exclusive, only when the file does not exist yet."""
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        fd = os.open(
            path,
            os.O_WRONLY | os.O_CREAT | (os.O_EXCL if exclusive else os.O_TRUNC),
            0o644,
        )
    except FileExistsError:
        return False
    with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")
    return True


def cmd_lock(args: argparse.Namespace) -> int:
    path = Path(args.data) / "run.lock"
    t = now()
    held: dict | None = read_json(path)
    if held is None and path.exists():
        held = {
            "session_id": "unknown"
        }  # an unreadable lock cannot be live, so it reads stale
    try:
        age = t - float(held["heartbeat"]) if held else None
    except (KeyError, TypeError, ValueError):
        age = float("inf")
    stale = held is not None and age is not None and age > args.stale_minutes * 60
    mine = held is not None and held.get("session_id") == args.session
    if args.action == "status":
        print(
            "free"
            if held is None
            else f"{'stale' if stale else 'held'} session={held.get('session_id')}"
        )
        return 0
    if args.action == "acquire":
        record = {
            "session_id": args.session,
            "started_at": iso(t),
            "heartbeat": t,
            "invocation": args.invocation,
        }
        if held is not None and not stale:
            print(
                f"in-flight session={held.get('session_id')} started_at={held.get('started_at')} heartbeat_age_s={int(age or 0)}"
            )
            return 1
        if stale:
            path.unlink(missing_ok=True)
        if not write_json(path, record, exclusive=True):
            print("in-flight: another run took the lock first")
            return 1
        print(
            f"replaced-stale session={held.get('session_id')}"
            if stale and held
            else "acquired"
        )
        return 0
    if not mine or held is None:
        print(
            f"not held by {args.session}"
            + (f" (held by {held.get('session_id')})" if held else "")
        )
        return 1
    if args.action == "heartbeat":
        held["heartbeat"] = t
        write_json(path, held)
    else:
        path.unlink(missing_ok=True)
    print(args.action)
    return 0


def find(doc: dict, fid: str) -> dict | None:
    return next(
        (f for f in doc["findings"] if isinstance(f, dict) and f.get("id") == fid), None
    )


def cmd_adopt(args: argparse.Namespace) -> int:
    f = find(load(args.findings), args.id)
    if f is None:
        print(f"no finding {args.id}")
        return 1
    if f.get("status") not in ("measured", "candidate"):
        print(
            f"{args.id} is {f.get('status')}: only measured findings and candidates can be adopted"
        )
        return 1
    errors = finding_errors(f)
    if errors:
        print("\n".join(errors))
        return 1
    record = {
        "session_id": args.session,
        "adopted_at": iso(now()),
        "id": f["id"],
        "key": f.get("key"),
        "title": f.get("title"),
        "horizon": f.get("horizon"),
        "guard_metric": f.get("guard_metric"),
        "revert_if": f.get("revert_if"),
        "route_suggested": f.get("route"),
        "route_taken": args.route_taken,
        "route_overridden": args.route_taken != f.get("route"),
    }
    path = Path(args.data) / "adopted.jsonl"
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(record) + "\n")
    print(f"adopted {f['id']}")
    return 0


def cmd_adopted(args: argparse.Namespace) -> int:
    path = Path(args.data) / "adopted.jsonl"
    if not path.exists():
        return 0
    for line in path.read_text(encoding="utf-8").splitlines():
        try:
            record = json.loads(line)
        except ValueError:
            continue
        if isinstance(record, dict) and record.get("session_id") == args.session:
            print(json.dumps(record))
    return 0


CATALOG_COLUMNS = (
    "class",
    "area",
    "cause",
    "measure",
    "remedy",
    "accuracy_guard",
    "fix_owner",
    "confidence",
    "candidate_only",
    "pointer",
    "as_of",
    "recheck_trigger",
)


def cells(line: str) -> list[str]:
    """A markdown table row's cells, honoring escaped pipes."""
    parts = re.split(r"(?<!\\)\|", line.strip())
    return [p.strip().replace("\\|", "|") for p in parts[1:-1]]


def catalog_errors(path: Path) -> tuple[int, list[str]]:
    rows, errors, header = 0, [], None
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.lstrip().startswith("|"):
            header = None
            continue
        row = cells(line)
        if tuple(row) == CATALOG_COLUMNS:
            header = row
            continue
        if header is None or all(set(c) <= set("-: ") for c in row):
            continue
        rows += 1
        r = dict(zip(header, row))
        where = f"{path.name}:{n}: {r.get('class') or '<no class>'}"
        if len(row) != len(header):
            errors.append(f"{where}: want {len(header)} cells, got {len(row)}")
            continue
        confidence = r["confidence"]
        if confidence not in CONFIDENCES:
            errors.append(
                f"{where}: confidence must be one of {', '.join(CONFIDENCES)}"
            )
        elif confidence != "HIGH" and r["candidate_only"] != "yes":
            errors.append(f"{where}: a {confidence} row must be candidate_only yes")
        if r["candidate_only"] not in ("yes", "no"):
            errors.append(f"{where}: candidate_only must be yes or no")
        if not r["pointer"].startswith("http"):
            errors.append(f"{where}: pointer must be a URL")
        if not DATE_RE.match(r["as_of"]):
            errors.append(f"{where}: as_of must be YYYY-MM-DD")
        for field in ("class", "area", "recheck_trigger"):
            if not r[field]:
                errors.append(f"{where}: {field} required")
        unknown = [a for a in r["area"].split(", ") if a not in AREAS]
        if r["area"] and r["area"] != "all" and unknown:
            errors.append(f"{where}: unknown area {', '.join(unknown)}")
    return rows, errors


def cmd_lint_catalog(args: argparse.Namespace) -> int:
    files = []
    for target in map(Path, args.paths):
        files += sorted(target.glob("*.md")) if target.is_dir() else [target]
    total, errors = 0, []
    for path in files:
        rows, errs = catalog_errors(path)
        total += rows
        errors += errs
    if not total:
        errors.append("no catalog rows found under " + ", ".join(args.paths))
    for e in errors:
        print(e)
    return 1 if errors else 0


CONDITION_FIELDS = ("repo", "machine", "harness_version", "model", "workload")


def cmd_compare(args: argparse.Namespace) -> int:
    f = find(load(args.findings), args.id)
    if f is None or f.get("status") != "measured":
        print(f"{args.id}: only a measured finding can be compared")
        return 1
    key = f.get("key") or f["id"]
    path = (
        Path(args.data)
        / "baselines"
        / (re.sub(r"[^A-Za-z0-9._-]", "__", key) + ".json")
    )
    current = {
        "key": key,
        "value": f.get("value"),
        "unit": f.get("unit"),
        "conditions": f.get("conditions") or {},
    }
    base = read_json(path)
    if base is None:
        current["recorded_at"] = iso(now())
        write_json(path, current)
        print(f"baseline-recorded {key}")
        return 0
    differs = ["unit"] if base.get("unit") != current["unit"] else []
    before, after = base.get("conditions") or {}, current["conditions"]
    differs += [
        c for c in CONDITION_FIELDS if not after.get(c) or before.get(c) != after.get(c)
    ]
    if differs:
        # The new conditions become the baseline, so the next run under them can compare;
        # a measurement with an unrecorded condition cannot anchor anything and is not kept.
        complete = all(after.get(c) for c in CONDITION_FIELDS)
        if complete:
            current["recorded_at"] = iso(now())
            write_json(path, current)
        note = "baseline reset" if complete else "baseline kept"
        print(f"cannot-quantify {key}: differs in {', '.join(differs)}; {note}")
        return 0
    delta = current["value"] - base["value"]
    print(
        f"compared {key} before={base['value']} after={current['value']} unit={current['unit']} delta={delta:g}"
    )
    return 0


INVOKED = "<command-name>/performance:go-faster"


def parse_ts(value: object) -> float | None:
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def transcript_counts(path: Path) -> dict:
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
    sys.dont_write_bytecode = True  # the plugin's own tree is not a cache
    import transcript_reader as tr  # noqa: PLC0415  (the generated shared copy in ../lib)

    stats: dict[str, int] = {}
    ledger = tr.UsageLedger()
    seen: set[str] = set()
    calls = 0
    # Tool calls made before the latest go-faster invocation, slash or model-invoked: the
    # session's own work, as opposed to the prompt that triggered the sweep and its setup.
    before_invocation: int | None = None
    uses: dict[str, tuple[str, float | None]] = {}
    tools: dict[str, dict[str, int]] = {}
    reads: dict[str, int] = {}
    commands: dict[str, int] = {}
    skills: dict[str, int] = {}
    stamps: list[float] = []
    typed = 0
    for record in tr.iter_records(path, stats):
        stamp = parse_ts(record.get("timestamp"))
        if stamp is not None:
            stamps.append(stamp)
        typed += tr.is_typed_turn(record)
        ledger.add(record)
        if record.get("type") == "user" and INVOKED in (tr.user_text(record) or ""):
            before_invocation = calls
        content = (
            (record.get("message") or {}).get("content")
            if isinstance(record.get("message"), dict)
            else None
        )
        for block in content if isinstance(content, list) else []:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "tool_use" and str(block.get("id")) not in seen:
                name, args = str(block.get("name")), block.get("input") or {}
                seen.add(str(block.get("id")))
                if name == "Skill" and str(args.get("skill", "")).endswith("go-faster"):
                    before_invocation = calls
                calls += 1
                uses[str(block.get("id"))] = (name, stamp)
                tool = tools.setdefault(name, {"calls": 0, "errors": 0, "wait_ms": 0})
                tool["calls"] += 1
                if name == "Read" and isinstance(args.get("file_path"), str):
                    reads[args["file_path"]] = reads.get(args["file_path"], 0) + 1
                if name == "Bash" and isinstance(args.get("command"), str):
                    commands[args["command"]] = commands.get(args["command"], 0) + 1
                if name == "Skill" and isinstance(args.get("skill"), str):
                    skills[args["skill"]] = skills.get(args["skill"], 0) + 1
            elif (
                block.get("type") == "tool_result" and block.get("tool_use_id") in uses
            ):
                name, started = uses.pop(block["tool_use_id"])
                tools[name]["errors"] += bool(block.get("is_error"))
                if started is not None and stamp is not None:
                    tools[name]["wait_ms"] += round((stamp - started) * 1000)
    return {
        "records": stats.get("records", 0),
        "bad_lines": stats.get("bad_lines", 0),
        "elapsed_ms": round((max(stamps) - min(stamps)) * 1000) if stamps else 0,
        "typed_turns": typed,
        "work_before_invocation": calls
        if before_invocation is None
        else before_invocation,
        "tokens": ledger.totals(),
        "tools": tools,
        "repeated_reads": {k: v for k, v in reads.items() if v > 1},
        "repeated_commands": {k: v for k, v in commands.items() if v > 1},
        "skills": skills,
        "subagents": sum(1 for _ in tr.iter_subagents(path)),
    }


def cmd_transcript_counts(args: argparse.Namespace) -> int:
    path = Path(args.file)
    if not path.is_file():
        die(f"no transcript at {path}")
    print(json.dumps(transcript_counts(path), indent=2, sort_keys=True))
    return 0


def cmd_run_start(args: argparse.Namespace) -> int:
    stamp = datetime.fromtimestamp(now(), timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run = Path(args.data).resolve() / "runs" / stamp
    header = {
        "schema": 1,
        "session_id": args.session,
        "started_at": iso(now()),
        "mode": args.mode,
        "session_evidence": args.session_evidence == "true",
        "findings": [],
    }
    if not write_json(run / "findings.json", header, exclusive=True):
        die(f"{run} already exists")
    print(run.as_posix())
    return 0


def cmd_add(args: argparse.Namespace) -> int:
    path = Path(args.run) / "findings.json"
    doc = load(str(path))
    try:
        new = json.loads(sys.stdin.read())
    except ValueError as exc:
        die(f"stdin is not JSON: {exc}")
    new = new if isinstance(new, list) else [new]
    have = {f.get("id") for f in doc["findings"]}
    errors = []
    for f in new:
        if not isinstance(f, dict):
            errors.append("a finding is not an object")
            continue
        errors += finding_errors(f)
        if f.get("id") in have:
            errors.append(f"{f.get('id')}: duplicate id")
        have.add(f.get("id"))
    if errors:
        print("\n".join(errors))
        return 1
    doc["findings"] += new
    write_json(path, doc)
    print(f"added {len(new)}")
    return 0


def cmd_finish(args: argparse.Namespace) -> int:
    run = Path(args.run)
    doc = load(str(run / "findings.json"))
    errors = doc_errors(doc)
    if errors:
        print("\n".join(errors))
        return 1
    report = run / "report.md"
    report.write_text(render(doc), encoding="utf-8", newline="\n")
    print(report.as_posix())
    return 0


def cmd_status_timing(args: argparse.Namespace) -> int:
    """Time `git status` with no index refresh, from git's own trace2 perf stream (R6)."""
    probe = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True
    )
    if probe.returncode != 0:
        die("not inside a git repository")
    trace = Path(args.data).resolve() / "trace2-status.txt"
    trace.parent.mkdir(parents=True, exist_ok=True)
    trace.unlink(missing_ok=True)
    # The column layout parsed below is the non-brief form; a caller's BRIEF setting would drop it.
    env = {**os.environ, "GIT_TRACE2_PERF": str(trace), "GIT_TRACE2_PERF_BRIEF": "0"}
    for _ in range(args.runs):
        result = subprocess.run(
            ["git", "--no-optional-locks", "status", "--porcelain"],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
        )
        if result.returncode != 0:
            die(f"git status failed ({result.returncode}): {result.stderr.strip()}")
    if not trace.is_file() or not trace.stat().st_size:
        die(f"git wrote no trace to {trace}")
    samples, version = [], ""
    for line in trace.read_text(encoding="utf-8", errors="replace").splitlines():
        cols = [c.strip() for c in line.split("|")]
        if len(cols) > 5 and cols[3] == "version":
            version = cols[-1]
        if len(cols) > 5 and cols[3] == "atexit" and cols[1] == "d0":
            samples.append(round(float(cols[5]) * 1000, 3))
    ordered = sorted(samples)
    print(
        json.dumps(
            {
                "label": "status without index refresh",
                "command": "git --no-optional-locks status --porcelain",
                "git_version": version,
                "samples_ms": samples,
                "median_ms": ordered[len(ordered) // 2] if ordered else None,
                "min_ms": ordered[0] if ordered else None,
                "max_ms": ordered[-1] if ordered else None,
                "trace": trace.as_posix(),
            },
            indent=2,
        )
    )
    return 0


RUN_FIELDS = "databaseId,attempt,createdAt,startedAt,updatedAt,conclusion,workflowName"
JOBS_JQ = (
    "[.jobs[] | {name, conclusion, created_at, started_at, completed_at,"
    " steps: [(.steps // [])[] | {name, conclusion, started_at, completed_at}]}]"
)
PR_FIELDS = "number,createdAt,mergedAt,reviews,additions,deletions,changedFiles"


class GhError(Exception):
    pass


def gh_list(args: list[str]) -> tuple[list[dict], str]:
    """Run gh with the caller's environment; return the JSON array it printed and the line run."""
    line = shlex.join(["gh", *args])
    exe = shutil.which("gh")
    if exe is None:
        raise GhError(f"{line}: gh not found on PATH")
    try:
        result = subprocess.run(
            [exe, *args],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    except OSError as exc:
        raise GhError(f"{line}: {exc}") from exc
    if result.returncode != 0:
        lines = [x.strip() for x in result.stderr.splitlines() if x.strip()]
        raise GhError(
            f"{line} failed ({result.returncode}): {lines[0] if lines else 'no error output'}"
        )
    try:
        doc = json.loads(result.stdout)
    except ValueError as exc:
        raise GhError(f"{line}: output is not JSON ({exc})") from exc
    if not isinstance(doc, list):
        raise GhError(f"{line}: output is not a JSON array")
    return [d for d in doc if isinstance(d, dict)], line


def whole(value: float) -> float:
    return int(value) if float(value).is_integer() else value


def median(samples: Sequence[float]) -> float | None:
    if not samples:
        return None
    ordered, mid = sorted(samples), len(samples) // 2
    return whole(
        ordered[mid] if len(ordered) % 2 else (ordered[mid - 1] + ordered[mid]) / 2
    )


def span_ms(start: object, end: object) -> int | None:
    a, b = parse_ts(start), parse_ts(end)
    return None if a is None or b is None else round((b - a) * 1000)


def stat(samples: Sequence[float], unit: str, command: str, excluded: int = 0) -> dict:
    """One number to record; excluded counts items whose timestamps were missing or unparseable."""
    return {
        "value": median(samples),
        "unit": unit,
        "samples": len(samples),
        "excluded": excluded,
        "command": command,
    }


def ci_timing(repo: str, runs: int, job_runs: int) -> dict:
    listed, list_line = gh_list(
        ["run", "list", "--repo", repo, "--limit", str(runs), "--status", "completed"]
        + ["--json", RUN_FIELDS]
    )
    # A run with no parseable createdAt cannot be ordered, so it is never timed.
    dated = [(t, r) for r in listed if (t := parse_ts(r.get("createdAt"))) is not None]
    dated.sort(key=lambda tr: tr[0], reverse=True)
    newest = [r for _, r in dated[:job_runs]]
    waits: list[int] = []
    lengths: list[int] = []
    tests: list[int] = []
    job_lines: list[str] = []
    no_wait = no_length = no_step = no_test = 0
    by_step: dict[tuple[str, str], list[int]] = {}
    for run in newest:
        path = f"repos/{repo}/actions/runs/{run.get('databaseId')}/jobs"
        jobs, line = gh_list(["api", path, "--jq", JOBS_JQ])
        job_lines.append(line)
        starts = [parse_ts(j.get("started_at")) for j in jobs]
        ends = [parse_ts(j.get("completed_at")) for j in jobs]
        # One ran job with an unknown start or end makes the whole run's length unknown.
        unknown = any(
            None in (s, e)
            for j, s, e in zip(jobs, starts, ends)
            if j.get("conclusion") != "skipped"
        )
        starts = [s for s in starts if s is not None]
        ends = [e for e in ends if e is not None]
        if starts and ends and not unknown:
            lengths.append(round((max(ends) - min(starts)) * 1000))
        else:
            no_length += 1
        for job in jobs:
            if job.get("conclusion") == "skipped":
                continue
            wait = span_ms(job.get("created_at"), job.get("started_at"))
            if wait is None:
                no_wait += 1
            else:
                waits.append(wait)
            for step in job.get("steps") or []:
                if step.get("conclusion") == "skipped":
                    continue
                name = str(step.get("name"))
                took = span_ms(step.get("started_at"), step.get("completed_at"))
                if took is None:
                    no_step += 1
                    no_test += "test" in name.lower()
                    continue
                by_step.setdefault((str(job.get("name")), name), []).append(took)
                if "test" in name.lower():
                    tests.append(took)
    jobs_cite = "; ".join(job_lines)
    length = stat(lengths, "ci-minutes", jobs_cite, no_length)
    if length["value"] is not None:
        length["value"] = whole(round(length["value"] / 60000, 2))
    slowest = stat([], "elapsed-ms", jobs_cite, no_step)
    if by_step:
        (job_name, step_name), took = min(
            by_step.items(), key=lambda kv: (-(median(kv[1]) or 0), kv[0])
        )
        slowest = {
            "job": job_name,
            "step": step_name,
            **stat(took, "elapsed-ms", jobs_cite, no_step),
        }
    reruns = [
        r for r in listed if isinstance(r.get("attempt"), int) and r["attempt"] > 1
    ]
    return {
        "repo": repo,
        "runs_listed": len(listed),
        "runs_timed": len(newest),
        "runs_excluded": len(listed) - len(dated),
        "queue_wait": stat(waits, "wait-ms", jobs_cite, no_wait),
        "run_length": length,
        "slowest_step": slowest,
        "test_steps": stat(tests, "elapsed-ms", jobs_cite, no_test),
        "reruns": {
            "value": len(reruns),
            "unit": "count",
            "samples": len(listed),
            "command": list_line,
        },
        "commands": [list_line, *job_lines],
    }


def pr_timing(limit: int) -> dict:
    prs, line = gh_list(
        ["pr", "list", "--state", "merged", "--limit", str(limit), "--json", PR_FIELDS]
    )
    first: list[int] = []
    merge: list[int] = []
    sizes: list[int] = []
    no_first = no_merge = no_size = 0
    for pr in prs:
        added, deleted = pr.get("additions"), pr.get("deletions")
        if isinstance(added, int) and isinstance(deleted, int):
            sizes.append(added + deleted)
        else:
            no_size += 1
        took = span_ms(pr.get("createdAt"), pr.get("mergedAt"))
        if took is None:
            no_merge += 1
        else:
            merge.append(took)
        created = parse_ts(pr.get("createdAt"))
        if created is None:
            no_first += 1
            continue
        # A pending review has no submittedAt; one stamped before the PR opened is not a wait.
        # An unparseable stamp could be the earliest review, so the PR is left out.
        stamps = [
            r.get("submittedAt")
            for r in pr.get("reviews") or []
            if isinstance(r, dict) and r.get("submittedAt") is not None
        ]
        parsed = [parse_ts(s) for s in stamps]
        if None in parsed:
            no_first += 1
            continue
        submitted = [s for s in parsed if s is not None and s >= created]
        if submitted:
            first.append(round((min(submitted) - created) * 1000))
    return {
        "prs": len(prs),
        "first_review": stat(first, "wait-ms", line, no_first),
        "open_to_merge": stat(merge, "wait-ms", line, no_merge),
        "size": stat(sizes, "count", line, no_size),
        "commands": [line],
    }


def cmd_ci_timing(args: argparse.Namespace) -> int:
    try:
        result = ci_timing(args.repo, args.runs, args.job_runs)
    except GhError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2))
    return 0


def cmd_pr_timing(args: argparse.Namespace) -> int:
    try:
        result = pr_timing(args.limit)
    except GhError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2))
    return 0


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(newline="\n", encoding="utf-8")  # type: ignore[union-attr]
    parser = argparse.ArgumentParser(description=(__doc__ or "").splitlines()[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    for name, fn in (
        ("validate", cmd_validate),
        ("rank", cmd_rank),
        ("render", cmd_render),
        ("transcript-counts", cmd_transcript_counts),
    ):
        p = sub.add_parser(name)
        p.add_argument("file")
        p.set_defaults(fn=fn)
    p = sub.add_parser("lock")
    p.add_argument("action", choices=("acquire", "heartbeat", "release", "status"))
    p.add_argument("--data", required=True)
    p.add_argument("--session", default="")
    p.add_argument("--invocation", default="")
    p.add_argument("--stale-minutes", type=float, default=60)
    p.set_defaults(fn=cmd_lock)
    p = sub.add_parser("adopt")
    p.add_argument("--data", required=True)
    p.add_argument("--session", required=True)
    p.add_argument("--findings", required=True)
    p.add_argument("--id", required=True)
    p.add_argument("--route-taken", required=True, choices=ROUTES)
    p.set_defaults(fn=cmd_adopt)
    p = sub.add_parser("adopted")
    p.add_argument("--data", required=True)
    p.add_argument("--session", required=True)
    p.set_defaults(fn=cmd_adopted)
    p = sub.add_parser("compare")
    p.add_argument("--data", required=True)
    p.add_argument("--findings", required=True)
    p.add_argument("--id", required=True)
    p.set_defaults(fn=cmd_compare)
    p = sub.add_parser("run-start")
    p.add_argument("--data", required=True)
    p.add_argument("--session", required=True)
    p.add_argument("--mode", required=True, choices=("attended", "unattended"))
    p.add_argument("--session-evidence", required=True, choices=("true", "false"))
    p.set_defaults(fn=cmd_run_start)
    p = sub.add_parser("add")
    p.add_argument("--run", required=True)
    p.set_defaults(fn=cmd_add)
    p = sub.add_parser("finish")
    p.add_argument("--run", required=True)
    p.set_defaults(fn=cmd_finish)
    p = sub.add_parser("status-timing")
    p.add_argument("--data", required=True)
    p.add_argument("--runs", type=int, default=5)
    p.set_defaults(fn=cmd_status_timing)
    p = sub.add_parser("ci-timing")
    p.add_argument("--repo", required=True)
    p.add_argument("--runs", type=int, default=20)
    p.add_argument("--job-runs", type=int, default=5)
    p.set_defaults(fn=cmd_ci_timing)
    p = sub.add_parser("pr-timing")
    p.add_argument("--limit", type=int, default=20)
    p.set_defaults(fn=cmd_pr_timing)
    p = sub.add_parser("lint-catalog")
    p.add_argument("paths", nargs="+")
    p.set_defaults(fn=cmd_lint_catalog)
    args = parser.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
