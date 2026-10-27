#!/usr/bin/env python3
"""Live behavior probes for Claude Code platform behavior.

Each case is a directory under cases/<area>/<name>/ holding settings.json (passed
with --settings), prompt.md, expect.json and an optional scaffold.sh. The runner
makes a temp directory per case, runs the scaffold there, launches
`claude -p --output-format stream-json --verbose` with the case's settings and
permission mode, reads the decision for the case's target tool call out of the
stream, and gives one verdict per case. A `prints` case judges the first line a
slash command prints instead of a tool call:

  pass          the target call's outcome (or printed line) matches expect.json
  fail          it does not
  inconclusive  the model never attempted the target call, the command printed
                nothing, the CLI produced no init event, or a case's paired
                control did not pass
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
      raw stream of each run goes to <out>/raw/, outside the repository, except
      for a verdict-only case, which saves no stream and no tool output text.
      --max-runs defaults to 20 under --live; a dry run has no run ceiling.

  table RESULTS
      Print a results.jsonl file as a Markdown outcome table for the records.

  rejudge --out DIR [--cases DIR]
      Re-read the streams a live run saved under DIR/raw/ against the current
      expect.json files and rewrite DIR/results.jsonl, so a corrected
      expectation needs no new model run. A verdict-only case keeps its row.

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
CHANGELOG_PARSER = SKILL_DIR.parent.parent / "scripts" / "changelog-releases.sh"

PRINTS = "prints"
OUTCOMES = ("allow", "deny", "ran", "refused", PRINTS)
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
# Case fields passed to the CLI as tool rule lists, comma-joined.
TOOL_LISTS = (
    ("allowed_tools", "--allowedTools"),
    ("disallowed_tools", "--disallowedTools"),
)
# The only flags a case's cli_args may pass, each with the shape its value must
# have, so no case can widen the launch.
CLI_FLAGS = {"--autocompact": r"auto|\d+[kKmM]?"}
# Where a `prints` case looks for a slash command's output: a user message
# wrapped in this tag, else the result event's text when no model turn ran.
COMMAND_OUTPUT = re.compile(r"<local-command-stdout>(.*?)</local-command-stdout>", re.S)
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")

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
    shared = expect.get("tool_rules")
    if shared is not None:
        # A list set shared by several cases, kept once in cases/lib/.
        if not isinstance(shared, str) or Path(shared).name != shared:
            raise CaseError(f"{case_id}: tool_rules names a file in cases/lib/")
        try:
            rules = json.loads((cases_dir / "lib" / shared).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise CaseError(
                f"{case_id}: tool_rules {shared} unreadable: {exc}"
            ) from exc
        if not isinstance(rules, dict) or not any(f in rules for f, _ in TOOL_LISTS):
            raise CaseError(f"{case_id}: tool_rules {shared} sets no tool list")
        for field, _ in TOOL_LISTS:
            if field in rules:
                expect.setdefault(field, rules[field])
    expect["id"] = case_id
    expect["area"] = case_id.split("/", 1)[0]
    expect["dir"] = case_dir
    return expect


def discover(cases_dir: Path) -> list[dict]:
    return [
        load_case(cases_dir, path.parent)
        for path in sorted(cases_dir.glob("*/*/expect.json"))
    ]


def first_line(text: str) -> str:
    """The first non-blank line of printed output, without terminal escapes."""
    for line in ANSI.sub("", text).splitlines():
        if line.strip():
            return line.strip()
    return ""


def cli_args_ok(args) -> bool:
    """Flag-value pairs only, each flag in CLI_FLAGS and its value of that flag's shape."""
    return (
        isinstance(args, list)
        and len(args) % 2 == 0
        and all(
            isinstance(flag, str)
            and flag in CLI_FLAGS
            and isinstance(value, str)
            and re.fullmatch(CLI_FLAGS[flag], value) is not None
            for flag, value in zip(args[::2], args[1::2])
        )
    )


def controlled(case: dict) -> bool:
    """A negative case always needs a passing control; a prints case when it names one."""
    return case.get("outcome") in NEGATIVE or (
        case.get("outcome") == PRINTS and "control" in case
    )


def print_problems(case: dict, target: dict, by_id: dict[str, dict]) -> list[str]:
    cid = case["id"]
    try:
        pattern = re.compile(target.get("text_match") or "")
        shape = re.compile(target.get("printed_match") or "")
    except (re.error, TypeError) as exc:
        return [f"{cid}: target.text_match or printed_match is not a regex: {exc}"]
    problems = []
    if not target.get("text_match"):
        problems.append(f"{cid}: target.text_match is required")
    example = target.get("example")
    if not isinstance(example, str) or not first_line(example):
        problems.append(
            f"{cid}: target.example (the output the dry run prints) must be text"
        )
    elif not (pattern.search(first_line(example)) and shape.search(first_line(example))):
        problems.append(
            f"{cid}: target.example's first line does not match text_match "
            "and printed_match"
        )
    if "control" in case:
        control = by_id.get(str(case["control"]))
        if control is None or control is case:
            problems.append(f"{cid}: control {case['control']!r} is not another case")
        elif control.get("outcome") != PRINTS:
            problems.append(f"{cid}: control {control['id']} is not a prints case")
        elif pattern.search(
            first_line(str((control.get("target") or {}).get("example", "")))
        ):
            problems.append(
                f"{cid}: control {control['id']} prints what this case expects"
            )
        seen, link = {cid}, control
        while link is not None and "control" in link:
            if link["id"] in seen:
                problems.append(f"{cid}: its control chain loops at {link['id']}")
                break
            seen.add(link["id"])
            link = by_id.get(str(link["control"]))
    return problems


def case_problems(case: dict, by_id: dict[str, dict]) -> list[str]:
    cid = case["id"]
    problems = []
    for field in ("claim", "tags", "target", "outcome"):
        if field not in case:
            problems.append(f"{cid}: expect.json has no '{field}'")
    if case.get("outcome") not in OUTCOMES:
        problems.append(f"{cid}: outcome must be one of {', '.join(OUTCOMES)}")
    target = case.get("target") or {}
    if case.get("outcome") == PRINTS:
        problems += print_problems(case, target, by_id)
    else:
        if not target.get("tool"):
            problems.append(f"{cid}: target.tool is required")
        if target.get("select", "first") not in SELECTS:
            problems.append(
                f"{cid}: target.select must be one of {', '.join(SELECTS)}"
            )
        if not isinstance(target.get("example"), dict):
            problems.append(
                f"{cid}: target.example (the input the dry run emits) is required"
            )
        elif not re.search(
            target.get("input_match", ""), json.dumps(target["example"])
        ):
            problems.append(f"{cid}: target.example does not match target.input_match")
    if "cli_args" in case and not cli_args_ok(case["cli_args"]):
        problems.append(
            f"{cid}: cli_args must be flag-value pairs, each flag one of "
            f"{', '.join(CLI_FLAGS)}"
        )
    if not isinstance(case.get("tags"), list) or not case.get("tags"):
        problems.append(f"{cid}: tags must be a non-empty list")
    for field, _ in TOOL_LISTS:
        rules = case.get(field)
        if rules is not None and not (
            isinstance(rules, list)
            and all(isinstance(r, str) and r and "," not in r for r in rules)
        ):
            problems.append(f"{cid}: {field} must be a list of rules with no comma")
    if not isinstance(case.get("verdict_only", False), bool):
        problems.append(f"{cid}: verdict_only must be true or false")
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
        "printed": [],
        "result_text": None,
        "model_turn": False,
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
            if isinstance(event.get("result"), str):
                obs["result_text"] = event["result"]
        elif event.get("type") in ("assistant", "user"):
            content = (event.get("message") or {}).get("content")
            if event["type"] == "assistant":
                obs["model_turn"] = True
            else:
                obs["printed"] += COMMAND_OUTPUT.findall(
                    content if isinstance(content, str) else _text(content)
                )
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
    if case["outcome"] == PRINTS:
        return print_verdict(case, obs, row)
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
        # A verdict-only case's tool output may be what its denial should have
        # kept out, so its row carries none.
        "text": ""
        if case.get("verdict_only")
        else " ".join(shown["text"].split())[:TEXT_CLIP],
        "verdict": "pass" if passed else "fail",
        "note": ""
        if len(seen) == 1
        else f"{len(hits)} of {len(seen)} matching calls as expected",
    }


def print_verdict(case: dict, obs: dict, row: dict) -> dict:
    """Judge the first line a slash command printed against target.text_match."""
    outputs = obs["printed"] or (
        [obs["result_text"]] if obs["result_text"] and not obs["model_turn"] else []
    )
    line = next((first_line(o) for o in outputs if first_line(o)), "")
    if not line:
        return {
            **row,
            "verdict": "inconclusive",
            "note": "the command printed nothing"
            + ("; a model turn answered instead" if obs["model_turn"] else ""),
        }
    if not re.search(case["target"].get("printed_match") or "", line):
        # Not the output the case reads, such as an error or a dialog's text.
        return {
            **row,
            "verdict": "inconclusive",
            "note": "the first printed line is not of printed_match's shape",
        }
    passed = re.search(case["target"]["text_match"], line) is not None
    return {
        **row,
        "observed": "printed",
        "text": "" if case.get("verdict_only") else line[:TEXT_CLIP],
        "verdict": "pass" if passed else "fail",
        "note": "",
    }


def apply_controls(rows: list[dict], cases: dict[str, dict]) -> None:
    """A controlled case is only as good as its control: no passing control, no verdict.

    Repeats until nothing changes, since a control can have a control of its own."""
    by_id = {row["id"]: row for row in rows}
    changed = True
    while changed:
        changed = False
        for row in rows:
            case = cases[row["id"]]
            if not controlled(case) or row["verdict"] != "pass":
                continue
            control = by_id.get(str(case.get("control")))
            if control is None:
                row["verdict"] = "inconclusive"
                row["note"] = f"control {case.get('control')} not run in this suite"
                changed = True
            elif control["verdict"] != "pass":
                row["verdict"] = "inconclusive"
                row["note"] = (
                    f"control {control['id']} did not pass ({control['verdict']})"
                )
                changed = True


# ---------------------------------------------------------------- runners


def bash_argv0() -> str:
    """Git for Windows bash by full path; a bare `bash` there may be WSL or a Store alias."""
    if os.name != "nt":
        return "bash"
    git = shutil.which("git")
    for root in Path(git).resolve().parents if git else ():
        for candidate in (root / "bin" / "bash.exe", root / "usr" / "bin" / "bash.exe"):
            if candidate.exists():
                return str(candidate)
    raise RuntimeError(
        "Git for Windows bash is required to run scaffolds: no bin/bash.exe or "
        "usr/bin/bash.exe found above the git on PATH"
    )


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
    argv = [
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
    for field, flag in TOOL_LISTS:
        if case.get(field):
            argv += [flag, ",".join(case[field])]
    return argv + list(case.get("cli_args") or [])


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
        if not case.get("verdict_only"):
            (raw_dir / raw_name(case["id"])).write_text(stdout or "", encoding="utf-8")
        return list((stdout or "").splitlines())

    return run


def fake_runner(case: dict, cwd: Path, settings_file: Path, prompt: str) -> list[str]:
    """Emit the stream a case expects, so --dry-run exercises everything but `claude`."""
    target = case["target"]
    if case["outcome"] == PRINTS:
        printed = target["example"]
        wrapped = f"<local-command-stdout>{printed}</local-command-stdout>"
        return [
            json.dumps(event)
            for event in (
                {
                    "type": "system",
                    "subtype": "init",
                    "claude_code_version": DRY_RUN_VERSION,
                },
                {"type": "user", "message": {"content": wrapped}},
                {
                    "type": "result",
                    "subtype": "success",
                    "result": printed,
                    "total_cost_usd": 0.0,
                    DENIALS: [],
                },
            )
        ]
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


def rejudge(
    cases: list[dict], raw_dir: Path, prior: dict[str, dict] | None = None
) -> list[dict]:
    """Re-read saved live streams against the current expect.json; costs nothing.

    A verdict-only case saved no stream, so it keeps its row from the live run
    (prior, by case id) unchanged."""
    rows = []
    for case in cases:
        if case.get("verdict_only"):
            if case["id"] in (prior or {}):
                print(
                    f"{'kept':<12} {case['id']}  verdict-only: the live run saved "
                    "no stream to re-read, so its row stands",
                    file=sys.stderr,
                )
                rows.append(prior[case["id"]])
            continue
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
    if not cli_args_ok(case.get("cli_args") or []):
        return {**row, "verdict": "error", "note": "cli_args is not allowed flag-value pairs"}
    workdir = Path(tempfile.mkdtemp(prefix="cc-probe-"))
    try:
        case_dir = case["dir"]
        scaffold = case_dir / "scaffold.sh"
        if scaffold.is_file():
            try:
                bash = bash_argv0()
            except RuntimeError as exc:
                return {**row, "verdict": "error", "note": str(exc)}
            env = child_env(
                {
                    "PROBE_WORKDIR": workdir.as_posix(),
                    "PROBE_CASE_DIR": case_dir.as_posix(),
                    "PROBE_LIB": (case_dir.parent.parent / "lib").as_posix(),
                    "PROBE_MODEL": case.get("model", DEFAULT_MODEL),
                }
            )
            done = subprocess.run(  # noqa: S603 - fixed argv
                [bash, scaffold.as_posix()],
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
        resolved = {
            **case,
            **{
                field: [
                    substitute(rule, workdir, case_dir, json_escape=False)
                    for rule in case[field]
                ]
                for field, _ in TOOL_LISTS
                if case.get(field)
            },
        }
        lines = runner(resolved, cwd, settings_file, prompt)
        return {**row, **verdict(case, parse_stream(lines))}
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
            # The model the run uses, so a scaffold's PROBE_MODEL names the same one.
            model = case.get("model", getattr(args, "model", DEFAULT_MODEL))
            row = run_case(
                {**case, "max_budget_usd": budget, "model": model},
                runner,
                args.keep,
                args.live,
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


def read_rows(results: Path) -> list[dict]:
    return [
        json.loads(line)
        for line in results.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


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
    """(item id, bullet text) for every item the plugin's changelog parser reads."""
    rows = subprocess.run(  # noqa: S603 - fixed argv
        [bash_argv0(), CHANGELOG_PARSER.as_posix()],
        input=text,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=True,
    ).stdout
    items, ordinals = [], {}
    for row in rows.splitlines():
        kind, version, *rest = row.split("\t", 2)
        if kind == "item":
            ordinals[version] = ordinals.get(version, 0) + 1
            items.append(
                (f"{version}-{ordinals[version]:03d}", rest[0] if rest else "")
            )
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
    p_run.add_argument("--max-runs", type=int)
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
        print(table(read_rows(args.results)))
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
        results = args.out / "results.jsonl"
        prior = (
            {row["id"]: row for row in read_rows(results)} if results.is_file() else {}
        )
        rows = rejudge(cases, args.out / "raw", prior)
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
    if args.max_runs is None:
        args.max_runs = DEFAULT_SUITE_RUNS if args.live else len(chosen)
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
