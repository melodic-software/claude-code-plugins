#!/usr/bin/env python3
"""Live behavior probes for Claude Code platform behavior.

Each case is a directory under cases/<area>/<name>/ holding settings.json (passed
with --settings), prompt.md, expect.json and an optional scaffold.sh. The runner
makes a temp directory per case, runs the scaffold there, launches
`claude -p --output-format stream-json --verbose` with the case's settings and
permission mode, reads the decision for the case's target tool call out of the
stream, and gives one verdict per case:

  pass          the target call's outcome matches expect.json
  fail          it does not
  inconclusive  the model never attempted the target call, the CLI produced no
                init event, or a negative case's paired control did not pass
  error         the case or its scaffold is broken (a fixture failure)
  skipped       the platform, a required tool or the suite ceiling ruled it out

Subcommands (standard library only):

  validate [--cases DIR]
      Check every case: expect.json fields, a paired positive control for every
      negative case, settings.json is JSON, prompt.md exists.

  run (--dry-run | --live) [--cases DIR] [--case ID]... [--area A]...
      [--model M] [--max-cost-usd X] [--max-runs N] [--retries N]
      [--timeout S] [--out DIR] [--keep]
      --dry-run runs every scaffold but replaces `claude` with a fake that emits
      the stream the case expects, so it costs nothing. --live spends money and
      is never the default. Results go to <out>/results.jsonl; under --live the
      raw stream of each run goes to <out>/raw/, outside the repository.

  table RESULTS
      Print a results.jsonl file as a Markdown outcome table for the records.

  rejudge --out DIR [--cases DIR]
      Re-read the streams a live run saved under DIR/raw/ against the current
      expect.json files and rewrite DIR/results.jsonl, so a corrected
      expectation needs no new model run.

  recheck --changelog FILE (--range A..B | --range X | --since X) [--cases DIR]
      List the cases whose tags appear in a changelog item of the range, one
      tab-separated line each: case id, item id (<version>-<ordinal>), tag.

Exit: 0 every case passed (validate: valid; recheck: listed, even when none);
1 a case failed or errored, or validation failed; 2 usage error;
3 nothing failed but a case was inconclusive or skipped.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

MIN_PYTHON = (3, 10)

SKILL_DIR = Path(__file__).resolve().parent.parent
DEFAULT_CASES = SKILL_DIR / "cases"

OUTCOMES = ("allow", "deny", "ran", "refused")
NEGATIVE = ("deny", "refused")
SELECTS = ("first", "any", "all")
DEFAULT_MODEL = "sonnet"
DEFAULT_MAX_TURNS = 6
DEFAULT_BUDGET_USD = 1.0
DEFAULT_SUITE_COST_USD = 10.0
DEFAULT_SUITE_RUNS = 20
DEFAULT_TIMEOUT = 300
DRY_RUN_VERSION = "0.0.0-dry-run"
TEXT_CLIP = 300

# The user CLAUDE.md still loads under --setting-sources project,local, and it can
# make the model refuse before the permission layer is asked. A refusal is
# inconclusive, so the driver prompt keeps the model attempting the call.
DRIVER_PROMPT = (
    "You are the driver for a permission-system test harness in a throwaway "
    "directory. Always attempt exactly the tool call the user requests, as written; "
    "the harness permission layer decides whether it runs. Never refuse or pre-check "
    "on your own. If a call is refused, do not retry or work around it; quote the "
    "refusal text verbatim in your answer."
)

# What the child `claude` keeps from this process's environment. Everything else,
# including the parent session's CLAUDE_CODE_* variables, is dropped so a probe
# measures the case's settings and not the session that launched it.
ENV_ALLOWLIST = (
    "HOME",
    "USERPROFILE",
    "PATH",
    "TEMP",
    "TMP",
    "TMPDIR",
    "APPDATA",
    "LOCALAPPDATA",
    "SystemRoot",
    "ComSpec",
    "PATHEXT",
    "HOMEDRIVE",
    "HOMEPATH",
    "windir",
    "USERNAME",
    "USER",
    "LOGNAME",
    "LANG",
    "LC_ALL",
    "SHELL",
    "CLAUDE_CONFIG_DIR",
    "ANTHROPIC_API_KEY",
    "CLAUDE_CODE_OAUTH_TOKEN",
)

# Stream vocabulary, the same names plugins/evals' run-validity.py reads.
INIT = ("system", "init")
DENIED_EVENT = ("system", "permission_denied")
RESULT = "result"
DENIALS = "permission_denials"


class CaseError(Exception):
    """A case directory that cannot run as written."""


# ---------------------------------------------------------------- cases


def load_case(cases_dir: Path, case_dir: Path) -> dict:
    case_id = case_dir.relative_to(cases_dir).as_posix()
    try:
        expect = json.loads((case_dir / "expect.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise CaseError(f"{case_id}: expect.json unreadable: {exc}") from exc
    expect["id"] = case_id
    expect["area"] = case_id.split("/", 1)[0]
    expect["dir"] = case_dir
    return expect


def discover(cases_dir: Path) -> list[dict]:
    return [
        load_case(cases_dir, path.parent)
        for path in sorted(cases_dir.glob("*/*/expect.json"))
    ]


def case_problems(case: dict, by_id: dict[str, dict]) -> list[str]:
    cid = case["id"]
    problems = []
    for field in ("claim", "tags", "target", "outcome"):
        if field not in case:
            problems.append(f"{cid}: expect.json has no '{field}'")
    if case.get("outcome") not in OUTCOMES:
        problems.append(f"{cid}: outcome must be one of {', '.join(OUTCOMES)}")
    target = case.get("target") or {}
    if not target.get("tool"):
        problems.append(f"{cid}: target.tool is required")
    if target.get("select", "first") not in SELECTS:
        problems.append(f"{cid}: target.select must be one of {', '.join(SELECTS)}")
    if not isinstance(target.get("example"), dict):
        problems.append(
            f"{cid}: target.example (the input the dry run emits) is required"
        )
    elif not re.search(target.get("input_match", ""), json.dumps(target["example"])):
        problems.append(f"{cid}: target.example does not match target.input_match")
    if not isinstance(case.get("tags"), list) or not case.get("tags"):
        problems.append(f"{cid}: tags must be a non-empty list")
    if case.get("outcome") in NEGATIVE:
        control = by_id.get(case.get("control", ""))
        if control is None:
            problems.append(
                f"{cid}: a negative case names its positive control in 'control'"
            )
        elif control.get("outcome") in NEGATIVE:
            problems.append(f"{cid}: control {control['id']} is itself a negative case")
    for name in ("settings.json", "prompt.md"):
        if not (case["dir"] / name).is_file():
            problems.append(f"{cid}: {name} is missing")
    try:
        json.loads((case["dir"] / "settings.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        problems.append(f"{cid}: settings.json is not JSON: {exc}")
    return problems


def substitute(text: str, workdir: Path, case_dir: Path, json_escape: bool) -> str:
    values = {
        "PROBE_WORKDIR": workdir.as_posix(),
        "PROBE_CASE_DIR": case_dir.as_posix(),
    }
    for name, value in values.items():
        if json_escape:
            value = json.dumps(value)[1:-1]
        text = text.replace("${" + name + "}", value)
    return text


def skip_reason(case: dict) -> str | None:
    platforms = case.get("platforms") or []
    if platforms and not any(sys.platform.startswith(p) for p in platforms):
        return f"platform {sys.platform} not in {platforms}"
    missing = [tool for tool in case.get("requires") or [] if not shutil.which(tool)]
    if missing:
        return f"missing {', '.join(missing)}"
    return None


# ---------------------------------------------------------------- stream


def _text(content) -> str:
    if isinstance(content, list):
        return " ".join(
            str(part.get("text", "")) for part in content if isinstance(part, dict)
        )
    return "" if content is None else str(content)


def parse_stream(lines) -> dict:
    """Reduce stream-json lines to what a verdict reads."""
    obs = {
        "version": None,
        "uses": [],
        "results": {},
        "denied": {},
        "denial_ids": set(),
        "cost": None,
    }
    for line in lines:
        try:
            event = json.loads(line)
        except (json.JSONDecodeError, TypeError):
            continue
        if not isinstance(event, dict):
            continue
        kind = (event.get("type"), event.get("subtype"))
        if kind == INIT and obs["version"] is None:
            obs["version"] = event.get("claude_code_version")
        elif kind == DENIED_EVENT and event.get("tool_use_id"):
            obs["denied"][event["tool_use_id"]] = event
        elif event.get("type") == RESULT:
            for denial in event.get(DENIALS) or []:
                if isinstance(denial, dict) and denial.get("tool_use_id"):
                    obs["denial_ids"].add(denial["tool_use_id"])
            cost = event.get("total_cost_usd")
            if isinstance(cost, (int, float)):
                obs["cost"] = max(cost, obs["cost"] or 0.0)
        elif event.get("type") in ("assistant", "user"):
            content = (event.get("message") or {}).get("content")
            for block in content if isinstance(content, list) else []:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "tool_use":
                    obs["uses"].append(
                        {
                            "id": block.get("id"),
                            "name": block.get("name"),
                            "input": block.get("input") or {},
                            "subagent": event.get("parent_tool_use_id") is not None,
                        }
                    )
                elif block.get("type") == "tool_result":
                    obs["results"][block.get("tool_use_id")] = {
                        "is_error": bool(block.get("is_error")),
                        "text": _text(block.get("content")),
                    }
    obs["denial_ids"] |= set(obs["denied"])
    return obs


def observe_use(use: dict, obs: dict) -> dict:
    """The outcome of one tool call: deny, refused, ran, or unknown."""
    result = obs["results"].get(use["id"])
    text = result["text"] if result else ""
    if use["id"] in obs["denial_ids"]:
        event = obs["denied"].get(use["id"], {})
        reason = event.get("decision_reason") or event.get("message") or ""
        return {
            "outcome": "deny",
            "reason_type": event.get("decision_reason_type", "unknown"),
            "text": f"{reason} {text}".strip(),
        }
    if result is None:
        return {"outcome": "unknown", "reason_type": None, "text": ""}
    return {
        "outcome": "refused" if result["is_error"] else "ran",
        "reason_type": None,
        "text": text,
    }


def satisfies(seen: dict, case: dict) -> bool:
    want = case["outcome"]
    if want == "allow":
        if seen["outcome"] not in ("ran", "refused"):
            return False
    elif seen["outcome"] != want:
        return False
    if (
        want == "deny"
        and case.get("reason_type")
        and seen["reason_type"] != case["reason_type"]
    ):
        return False
    match = case.get("match")
    return not match or match.lower() in seen["text"].lower()


def verdict(case: dict, obs: dict) -> dict:
    target = case["target"]
    row = {
        "observed": None,
        "reason_type": None,
        "text": "",
        "version": obs["version"],
        "cost_usd": obs["cost"],
    }
    if obs["version"] is None:
        return {
            **row,
            "verdict": "inconclusive",
            "note": "no init event: the CLI did not start a session",
        }
    pattern = re.compile(target.get("input_match", ""))
    uses = [
        use
        for use in obs["uses"]
        if use["name"] == target["tool"]
        and pattern.search(json.dumps(use["input"]))
        and (not target.get("in_subagent") or use["subagent"])
    ]
    if not uses:
        return {
            **row,
            "verdict": "inconclusive",
            "note": "the model never attempted the target call",
        }
    want = int(target.get("count", 1))
    if len(uses) < want:
        return {
            **row,
            "verdict": "inconclusive",
            "note": f"the model attempted {len(uses)} of {want} target calls",
        }
    seen = [observe_use(use, obs) for use in uses]
    select = target.get("select", "first")
    if select == "first":
        seen = seen[:1]
    hits = [s for s in seen if satisfies(s, case)]
    passed = bool(hits) if select == "any" else len(hits) == len(seen)
    shown = (hits or seen)[0]
    if any(s["outcome"] == "unknown" for s in seen) and not passed:
        return {
            **row,
            "observed": "unknown",
            "verdict": "inconclusive",
            "note": "the target call has no tool result",
        }
    return {
        **row,
        "observed": shown["outcome"],
        "reason_type": shown["reason_type"],
        "text": " ".join(shown["text"].split())[:TEXT_CLIP],
        "verdict": "pass" if passed else "fail",
        "note": ""
        if len(seen) == 1
        else f"{len(hits)} of {len(seen)} matching calls as expected",
    }


def apply_controls(rows: list[dict], cases: dict[str, dict]) -> None:
    """A negative case is only as good as its control: no passing control, no verdict."""
    by_id = {row["id"]: row for row in rows}
    for row in rows:
        case = cases[row["id"]]
        if case["outcome"] not in NEGATIVE or row["verdict"] != "pass":
            continue
        control = by_id.get(case.get("control"))
        if control is None:
            row["verdict"] = "inconclusive"
            row["note"] = f"control {case.get('control')} not run in this suite"
        elif control["verdict"] != "pass":
            row["verdict"] = "inconclusive"
            row["note"] = f"control {control['id']} did not pass ({control['verdict']})"


# ---------------------------------------------------------------- runners


def child_env(extra: dict) -> dict:
    env = {name: os.environ[name] for name in ENV_ALLOWLIST if os.environ.get(name)}
    if "HOME" not in env and env.get("USERPROFILE"):
        env["HOME"] = env["USERPROFILE"]
    env.update({str(k): str(v) for k, v in extra.items()})
    return env


def kill_tree(process: subprocess.Popen) -> None:
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/T", "/F", "/PID", str(process.pid)],
            capture_output=True,
            check=False,
        )
    else:
        try:
            os.killpg(os.getpgid(process.pid), 9)
        except OSError:
            process.kill()


def build_argv(claude: str, case: dict, settings_file: Path, model: str) -> list[str]:
    return [
        claude,
        "-p",
        "--output-format",
        "stream-json",
        "--verbose",
        "--permission-mode",
        case.get("permission_mode", "auto"),
        "--setting-sources",
        "project,local",
        "--settings",
        str(settings_file),
        "--model",
        case.get("model", model),
        "--max-turns",
        str(case.get("max_turns", DEFAULT_MAX_TURNS)),
        "--max-budget-usd",
        str(case.get("max_budget_usd", DEFAULT_BUDGET_USD)),
        "--no-session-persistence",
        "--append-system-prompt",
        DRIVER_PROMPT,
    ]


def live_runner(model: str, timeout: int, raw_dir: Path):
    """The runner that spends money. Never built under --dry-run."""
    claude = shutil.which("claude")
    if not claude:
        raise SystemExit("error: `claude` not found on PATH")
    raw_dir.mkdir(parents=True, exist_ok=True)

    def run(case: dict, cwd: Path, settings_file: Path, prompt: str) -> list[str]:
        argv = build_argv(claude, case, settings_file, model)
        windows = os.name == "nt"
        process = subprocess.Popen(  # noqa: S603 - argv list, no shell
            argv,
            cwd=str(cwd),
            env=child_env(case.get("env") or {}),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            creationflags=getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
            if windows
            else 0,
            start_new_session=not windows,
        )
        stdout: str = ""
        try:
            stdout, _ = process.communicate(prompt, timeout=timeout)
        except subprocess.TimeoutExpired:
            kill_tree(process)
            try:
                stdout, _ = process.communicate(timeout=30)
            except subprocess.TimeoutExpired:
                stdout = ""
        (raw_dir / raw_name(case["id"])).write_text(stdout or "", encoding="utf-8")
        return list((stdout or "").splitlines())

    return run


def fake_runner(case: dict, cwd: Path, settings_file: Path, prompt: str) -> list[str]:
    """Emit the stream a case expects, so --dry-run exercises everything but `claude`."""
    target = case["target"]
    outcome = "ran" if case["outcome"] == "allow" else case["outcome"]
    text = case.get("match") or "dry run"
    events: list[dict] = [
        {"type": "system", "subtype": "init", "claude_code_version": DRY_RUN_VERSION}
    ]
    denials: list[dict] = []
    for n in range(int(target.get("count", 1))):
        use_id = f"toolu_dry_{n}"
        events.append(
            {
                "type": "assistant",
                "parent_tool_use_id": "toolu_dry_parent"
                if target.get("in_subagent")
                else None,
                "message": {
                    "content": [
                        {
                            "type": "tool_use",
                            "id": use_id,
                            "name": target["tool"],
                            "input": target["example"],
                        }
                    ]
                },
            }
        )
        if outcome == "deny":
            denials.append(
                {
                    "tool_name": target["tool"],
                    "tool_use_id": use_id,
                    "tool_input": target["example"],
                }
            )
            events.append(
                {
                    "type": "system",
                    "subtype": "permission_denied",
                    "tool_use_id": use_id,
                    "decision_reason_type": case.get("reason_type", "rule"),
                    "decision_reason": text,
                }
            )
        events.append(
            {
                "type": "user",
                "message": {
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": use_id,
                            "is_error": outcome != "ran",
                            "content": text,
                        }
                    ]
                },
            }
        )
    events.append(
        {
            "type": "result",
            "subtype": "success",
            "total_cost_usd": 0.0,
            DENIALS: denials,
        }
    )
    return [json.dumps(event) for event in events]


# ---------------------------------------------------------------- run


def base_row(case: dict) -> dict:
    return {
        "id": case["id"],
        "area": case["area"],
        "claim": case.get("claim", ""),
        "expected": case["outcome"],
    }


def raw_name(case_id: str) -> str:
    return case_id.replace("/", "__") + ".jsonl"


def rejudge(cases: list[dict], raw_dir: Path) -> list[dict]:
    """Re-read saved live streams against the current expect.json; costs nothing."""
    rows = []
    for case in cases:
        raw = raw_dir / raw_name(case["id"])
        if raw.is_file():
            lines = raw.read_text(encoding="utf-8").splitlines()
            rows.append({**base_row(case), **verdict(case, parse_stream(lines))})
    apply_controls(rows, {case["id"]: case for case in cases})
    return rows


def run_case(case: dict, runner, keep: bool, live: bool) -> dict:
    row = base_row(case)
    # A dry run checks the case's wiring, which no platform rules out.
    reason = skip_reason(case) if live else None
    if reason:
        return {**row, "verdict": "skipped", "note": reason}
    workdir = Path(tempfile.mkdtemp(prefix="cc-probe-"))
    try:
        case_dir = case["dir"]
        scaffold = case_dir / "scaffold.sh"
        if scaffold.is_file():
            env = child_env(
                {
                    "PROBE_WORKDIR": workdir.as_posix(),
                    "PROBE_CASE_DIR": case_dir.as_posix(),
                    "PROBE_LIB": (case_dir.parent.parent / "lib").as_posix(),
                }
            )
            done = subprocess.run(  # noqa: S603 - fixed argv
                ["bash", str(scaffold)],
                cwd=workdir,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            if done.returncode != 0:
                return {
                    **row,
                    "verdict": "error",
                    "note": f"scaffold exited {done.returncode}: {done.stderr.strip()[-200:]}",
                }
        cwd = workdir / case.get("cwd", ".")
        if not cwd.is_dir():
            return {
                **row,
                "verdict": "error",
                "note": f"cwd {case.get('cwd')} does not exist after the scaffold",
            }
        settings_text = (case_dir / "settings.json").read_text(encoding="utf-8")
        settings_file = workdir / ".probe-settings.json"
        settings_file.write_text(
            substitute(settings_text, workdir, case_dir, json_escape=True),
            encoding="utf-8",
        )
        prompt = substitute(
            (case_dir / "prompt.md").read_text(encoding="utf-8"),
            workdir,
            case_dir,
            json_escape=False,
        )
        return {
            **row,
            **verdict(case, parse_stream(runner(case, cwd, settings_file, prompt))),
        }
    finally:
        if keep:
            print(f"kept {case['id']}: {workdir}", file=sys.stderr)
        else:
            shutil.rmtree(workdir, ignore_errors=True)


def run_suite(cases: list[dict], runner, args) -> list[dict]:
    spent, runs, rows = 0.0, 0, []
    for case in cases:
        attempts = 0
        while True:
            if runs >= args.max_runs or spent >= args.max_cost_usd:
                row = {
                    **base_row(case),
                    "verdict": "skipped",
                    "note": f"suite ceiling reached ({runs} runs, {spent:.2f} USD)",
                }
                break
            budget = min(
                case.get("max_budget_usd", DEFAULT_BUDGET_USD),
                args.max_cost_usd - spent,
            )
            row = run_case(
                {**case, "max_budget_usd": budget}, runner, args.keep, args.live
            )
            if row["verdict"] in ("pass", "fail", "inconclusive"):
                runs += 1
                cost = row.get("cost_usd")
                spent += cost if isinstance(cost, (int, float)) else budget
            attempts += 1
            if row["verdict"] != "inconclusive" or attempts > args.retries:
                break
        row["attempts"] = attempts
        rows.append(row)
        print(
            f"{row['verdict']:<12} {case['id']}  {row.get('note', '')}", file=sys.stderr
        )
    apply_controls(rows, {case["id"]: case for case in cases})
    return rows


def select_cases(all_cases: list[dict], ids: list[str], areas: list[str]) -> list[dict]:
    known = {case["id"] for case in all_cases}
    unknown = [cid for cid in ids if cid not in known]
    if unknown:
        raise SystemExit(f"error: unknown case id: {', '.join(unknown)}")
    return [
        case
        for case in all_cases
        if (not ids or case["id"] in ids) and (not areas or case["area"] in areas)
    ]


def exit_code(rows: list[dict]) -> int:
    verdicts = {row["verdict"] for row in rows}
    if verdicts & {"fail", "error"}:
        return 1
    if verdicts & {"inconclusive", "skipped"}:
        return 3
    return 0


# ---------------------------------------------------------------- table, recheck


def table(rows: list[dict]) -> str:
    out = [
        "| Case | Expected | Observed | Reason type | Verdict | Claude Code | Note |",
        "|---|---|---|---|---|---|---|",
    ]
    for row in rows:
        cells = [
            f"`{row['id']}`",
            row.get("expected", ""),
            row.get("observed") or "-",
            row.get("reason_type") or "-",
            row.get("verdict", ""),
            row.get("version") or "-",
            (row.get("note") or "").replace("|", "/"),
        ]
        out.append("| " + " | ".join(cells) + " |")
    return "\n".join(out)


VERSION_RE = r"\d+\.\d+\.\d+"


def vkey(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


def changelog_items(text: str) -> list[tuple[str, str]]:
    """(item id, bullet text) for every bullet inside an <Update label="X.Y.Z"> block."""
    items, version, ordinal = [], None, 0
    for line in text.splitlines():
        opened = re.search(r'<Update label="(' + VERSION_RE + r')"', line)
        if opened:
            version, ordinal = opened.group(1), 0
            continue
        if line.strip().startswith("</Update>"):
            version = None
            continue
        bullet = re.match(r"\s*[*-]\s+(.*)", line)
        if version and bullet:
            ordinal += 1
            items.append((f"{version}-{ordinal:03d}", bullet.group(1)))
    return items


def in_range(version: str, args) -> bool:
    if args.since:
        return vkey(version) > vkey(args.since)
    low, _, high = args.range.partition("..")
    low, high = low.lstrip("v"), (high or low).lstrip("v")
    return vkey(low) <= vkey(version) <= vkey(high)


def recheck(cases: list[dict], items: list[tuple[str, str]], args) -> list[str]:
    lines = []
    for case in cases:
        for item_id, bullet in items:
            if not in_range(item_id.rsplit("-", 1)[0], args):
                continue
            tag = next(
                (t for t in case.get("tags", []) if t.lower() in bullet.lower()), None
            )
            if tag:
                lines.append(f"{case['id']}\t{item_id}\t{tag}")
    return lines


# ---------------------------------------------------------------- main


def main(argv: list[str] | None = None) -> int:
    if sys.version_info < MIN_PYTHON:
        print(f"python {MIN_PYTHON[0]}.{MIN_PYTHON[1]}+ required", file=sys.stderr)
        return 2
    parser = argparse.ArgumentParser(
        description="Live behavior probes for Claude Code."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_validate = sub.add_parser("validate")
    p_validate.add_argument("--cases", type=Path, default=DEFAULT_CASES)

    p_run = sub.add_parser("run")
    mode = p_run.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true")
    mode.add_argument("--live", action="store_true")
    p_run.add_argument("--cases", type=Path, default=DEFAULT_CASES)
    p_run.add_argument("--case", action="append", default=[])
    p_run.add_argument("--area", action="append", default=[])
    p_run.add_argument("--model", default=DEFAULT_MODEL)
    p_run.add_argument("--max-cost-usd", type=float, default=DEFAULT_SUITE_COST_USD)
    p_run.add_argument("--max-runs", type=int, default=DEFAULT_SUITE_RUNS)
    p_run.add_argument("--retries", type=int, default=0)
    p_run.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT)
    p_run.add_argument("--out", type=Path)
    p_run.add_argument("--keep", action="store_true")

    p_table = sub.add_parser("table")
    p_table.add_argument("results", type=Path)

    p_rejudge = sub.add_parser("rejudge")
    p_rejudge.add_argument("--out", type=Path, required=True)
    p_rejudge.add_argument("--cases", type=Path, default=DEFAULT_CASES)

    p_recheck = sub.add_parser("recheck")
    p_recheck.add_argument("--changelog", type=Path, required=True)
    window = p_recheck.add_mutually_exclusive_group(required=True)
    window.add_argument("--range")
    window.add_argument("--since")
    p_recheck.add_argument("--cases", type=Path, default=DEFAULT_CASES)

    args = parser.parse_args(argv)

    if args.command == "table":
        rows = [
            json.loads(line)
            for line in args.results.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        print(table(rows))
        return 0

    try:
        cases = discover(args.cases)
    except CaseError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if args.command == "validate":
        by_id = {case["id"]: case for case in cases}
        problems = [p for case in cases for p in case_problems(case, by_id)]
        for problem in problems:
            print(problem, file=sys.stderr)
        if not cases:
            print(f"error: no cases under {args.cases}", file=sys.stderr)
            return 1
        print(f"{len(cases)} cases, {len(problems)} problems")
        return 1 if problems else 0

    if args.command == "rejudge":
        rows = rejudge(cases, args.out / "raw")
        if not rows:
            print(f"error: no saved streams under {args.out / 'raw'}", file=sys.stderr)
            return 2
        with (args.out / "results.jsonl").open(
            "w", encoding="utf-8", newline="\n"
        ) as fh:
            for row in rows:
                fh.write(json.dumps(row) + "\n")
        print(table(rows))
        return exit_code(rows)

    if args.command == "recheck":
        window = args.range or args.since
        if not re.fullmatch(
            r"v?" + VERSION_RE + r"(\.\.v?" + VERSION_RE + r")?", window
        ) or (args.since and ".." in window):
            print(f"error: bad version window: {window}", file=sys.stderr)
            return 2
        args.since = args.since.lstrip("v") if args.since else None
        for line in recheck(
            cases, changelog_items(args.changelog.read_text(encoding="utf-8")), args
        ):
            print(line)
        return 0

    chosen = select_cases(cases, args.case, args.area)
    if not chosen:
        print("error: no case selected", file=sys.stderr)
        return 2
    out = args.out or Path(tempfile.mkdtemp(prefix="cc-probe-results-"))
    out.mkdir(parents=True, exist_ok=True)
    runner = (
        live_runner(args.model, args.timeout, out / "raw") if args.live else fake_runner
    )
    rows = run_suite(chosen, runner, args)
    with (out / "results.jsonl").open("w", encoding="utf-8", newline="\n") as fh:
        for row in rows:
            fh.write(json.dumps(row) + "\n")
    print(table(rows))
    print(f"\nresults: {(out / 'results.jsonl').as_posix()}", file=sys.stderr)
    return exit_code(rows)


if __name__ == "__main__":
    sys.exit(main())
