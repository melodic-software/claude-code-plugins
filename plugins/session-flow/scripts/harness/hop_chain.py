#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Headless hop-chain harness for /session-flow:handoff (PLAN.md Phase 5).

Drives a chain of headless `claude -p` sessions through a throwaway fixture
repository, asserting that each hop reached the handoff skill, produced exactly
one shape-2 save-point file, and carried a resume prompt whose between-rails
bytes match what `save_point.py emit` prints. One TSV row per hop, an `N/N`
summary, non-zero exit on any miss.

Three modes, only one of which spends money:

    hop_chain.py --model <id> [--runs N] [--hops N] ...   live run (spends)
    hop_chain.py --dry-run                                self-test (no spend)
    hop_chain.py --budget [--live-hop1 <file>]            projection (no spend)

`--dry-run` exercises the SAME assertion, TSV, and cleanup code the live mode
uses, against a fake runner that writes a synthetic transcript and result JSON
while calling the real `save_point.py new` / `emit` / `validate`. `--budget`
generates a 20-hop chain through `new` with deterministic filler sized from the
shape-1 corpus median and reports the growth at hops 1, 5, and 20.

Stdlib only; Python 3.10+. Every file is opened UTF-8 and every subprocess runs
with `text=True, encoding="utf-8"`.
"""

from __future__ import annotations

import argparse
import contextlib
import glob
import io
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
SAVE_POINT = HERE.parent / "save_point.py"
DEFAULT_PLUGIN_DIR = HERE.parents[1]

RAIL_RE = re.compile("^─{10,}$")
FILL_RE = re.compile(r"<!-- FILL: ([a-z0-9-]+) .*?-->")
HANDOFF_GLOB = "*-handoff-*.md"
# What counts as touching the save-point surface before the skill was invoked.
# `save_point.py new` is in scope because the skill's own file-creating call
# carries no literal `handoffs/`; `save_point.py validate` on a predecessor is
# legitimate and stays out of it.
HANDOFF_TOUCH_RE = re.compile(r"handoffs[/\\]|save_point\.py\S*\s+new\b")
# Reading the predecessor is what a resume hop does FIRST: the rails text opens
# `Read @<...>/handoffs/<file>.md`. Only a tool that could CREATE the file is
# evidence of a free-hand bypass, so the read-only tools are excluded here.
# Deleting this set restores the spec's literal "ANY tool_use" wording, at the
# cost of failing every hop after the first.
READ_ONLY_TOOLS = frozenset({"Read", "Glob", "Grep"})
# A shell can read or write, and the tool name alone does not say which. Live
# evidence: a resuming hop ran `cat -n <handoff>` through Bash and was scored a
# free-hand bypass. So for these two tools a `handoffs/` mention is a touch only
# when the command could WRITE; otherwise it is recorded as a note and the hop
# still passes.
SHELL_TOOLS = frozenset({"Bash", "PowerShell"})
CREATION_MARKER_RE = re.compile(r"save_point\.py\S*\s+new\b")
WRITE_INDICATOR_RE = re.compile(
    # An output redirect, but not `2>&1`, `&>`, or a `<<` heredoc opener.
    r"(?<![0-9&<])>>?"
    # Mutating coreutils verbs.
    r"|\b(?:cp|mv|rm|touch|mkdir|tee|dd|rsync|install|ln)\b"
    # In-place stream editors, with any flags before the -i.
    r"|\b(?:sed|perl)\s+(?:-\S+\s+)*-i"
    # An interpreter actually invoked, which can write anything. Anchored at a
    # command position so `save_point.py validate` (a legitimate read) does not
    # match on its `.py` suffix.
    r"|(?:^|[\s;|&(])(?:python3?|py|node|pwsh|powershell)(?:\.exe)?\s"
)
WRITE_CMDLET_RE = re.compile(
    r"\b(?:Set-Content|Out-File|Add-Content|New-Item"
    r"|Copy-Item|Move-Item|Remove-Item|Rename-Item)\b",
    re.IGNORECASE,
)


def shell_command_text(tool_input: dict, serialized: str) -> str:
    """The command a shell tool_use will run.

    Classifying the `command` field rather than the whole serialized input
    keeps a `>` inside a prose `description` from reading as a redirect. An
    unexpected input shape falls back to the full serialization, which errs
    toward calling something a write.
    """
    command = tool_input.get("command")
    return command if isinstance(command, str) else serialized


def is_write_indicator(command: str) -> bool:
    return bool(WRITE_INDICATOR_RE.search(command) or WRITE_CMDLET_RE.search(command))
SKILL_NAME = "session-flow:handoff"
MIDDOT = "·"

# Phase 0 baseline: the shape-1 corpus (96 files) had a median of 154 lines and
# 3.2k tokens (chars/4). `--budget` sizes its filler so the generated hop 1
# lands on those medians; see size_filler().
SHAPE1_MEDIAN_LINES = 154
SHAPE1_MEDIAN_TOKENS = 3200
BUDGET_HOPS = 20
BUDGET_REPORT_HOPS = (1, 5, 20)
CUMULATIVE_ENTRIES_PER_HOP = 2
BUDGET_NAMESPACE = uuid.UUID("6f9619ff-8b86-d011-b42d-00c04fc964ff")
BUDGET_EPOCH = datetime(2026, 1, 1, 0, 0, 0, tzinfo=timezone.utc)

# The child environment the spec fixes, plus the five variables the Phase 0
# probe carried and a headless Windows child still needs (PATHEXT to resolve
# `claude` as `claude.cmd`, HOMEDRIVE/HOMEPATH/windir/USERNAME for the native
# tools git and PowerShell). Every other variable, `CLAUDE_*` included, is
# dropped: an allowlist cannot leak the launching session's id or effort.
ENV_ALLOWLIST = (
    "HOME",
    "USERPROFILE",
    "PATH",
    "TEMP",
    "TMP",
    "APPDATA",
    "LOCALAPPDATA",
    "SystemRoot",
    "ComSpec",
    "CLAUDE_CONFIG_DIR",
    "PATHEXT",
    "HOMEDRIVE",
    "HOMEPATH",
    "windir",
    "USERNAME",
)

ALLOWED_TOOLS = "Read,Write,Edit,Bash,PowerShell,Skill,Glob,Grep"

CHECKS = (
    "one_new_file",
    "validate",
    "session_id_match",
    "result_rails",
    "transcript_rails",
    "between_rails_match",
    "skill_order",
)

TSV_HEADER = (
    "run",
    "hop",
    "session_id",
    "model",
    "subtype",
    "num_turns",
    "cost_usd",
    "input_tokens",
    "context_tokens",
    *CHECKS,
    "reason",
)

# A file's creation stamp and a transcript record's timestamp come from two
# different clocks; the ordering claim is "the Skill call came first", not a
# sub-second race, so the disk comparison carries this slack.
DISK_ORDER_GRACE_SECONDS = 2.0


def _utf8_streams() -> None:
    for stream in (sys.stdout, sys.stderr):
        if isinstance(stream, io.TextIOWrapper):
            stream.reconfigure(encoding="utf-8", newline="\n")


# --- small helpers ----------------------------------------------------------


def _clear_readonly(func, path, _error):  # noqa: ANN001 - shutil callback signature
    """Retry a removal that failed because Windows marked the file read-only.

    Git writes its object store read-only, so a plain rmtree over a fixture
    repository fails on Windows. The third argument is an exc_info triple under
    `onerror` and a bare exception under `onexc`; neither is read, so one
    handler serves both.
    """
    try:
        os.chmod(path, stat.S_IWRITE)
        func(path)
    except OSError:
        pass


def rmtree(path: Path) -> None:
    if not path.exists():
        return
    # `onerror` is deprecated from 3.12 and removed in 3.14; `onexc` does not
    # exist before 3.12 and the repo floor is 3.10, so the parameter is chosen
    # at run time rather than pinned to either.
    if sys.version_info >= (3, 12):
        shutil.rmtree(path, onexc=_clear_readonly)
    else:
        shutil.rmtree(path, onerror=_clear_readonly)


def rail_lines(text: str) -> list[int]:
    lines = text.replace("\r\n", "\n").split("\n")
    return [i for i, line in enumerate(lines) if RAIL_RE.match(line.strip())]


def between_rails(text: str) -> str | None:
    """The bytes between the first two rails, CRLF-normalized. None unless the
    text carries exactly two rails."""
    normalized = text.replace("\r\n", "\n")
    lines = normalized.split("\n")
    rails = [i for i, line in enumerate(lines) if RAIL_RE.match(line.strip())]
    if len(rails) != 2:
        return None
    return "\n".join(lines[rails[0] + 1 : rails[1]])


def token_estimate(text: str) -> int:
    return len(text) // 4


def run_save_point(args: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    cmd = [sys.executable, "-X", "utf8", str(SAVE_POINT), *args]
    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=False,
    )


def frontmatter_value(path: Path, key: str) -> str:
    with path.open(encoding="utf-8") as fh:
        if fh.readline().strip() != "---":
            return ""
        for line in fh:
            if line.strip() == "---":
                break
            if line.startswith(f"{key}:"):
                return line[len(key) + 1 :].strip()
    return ""


def handoff_files(handoff_dir: Path) -> set[str]:
    if not handoff_dir.is_dir():
        return set()
    return {p.name for p in handoff_dir.glob(HANDOFF_GLOB)}


def created_at(path: Path) -> float:
    """The file's creation time, for the ordering claim against the Skill call.

    `st_birthtime` is the real thing where the platform exposes it. Windows
    reports creation time in `st_ctime` (the documented behaviour there), so
    that is the fallback; on Linux `st_ctime` is the inode-change time, which
    for a file this harness watches being created is the same moment.
    """
    info = path.stat()
    birthtime = getattr(info, "st_birthtime", None)
    return float(birthtime) if birthtime is not None else float(info.st_ctime)


def parse_iso(stamp: str) -> float | None:
    try:
        return datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp()
    except (ValueError, AttributeError):
        return None


# --- the skeleton filler ----------------------------------------------------
#
# `save_point.py new` leaves one `<!-- FILL: <name> ... -->` slot per model-written
# section. Filling them deterministically is what lets `--budget` measure a
# 20-hop chain and what lets `--dry-run` hand `emit` and `validate` a real file.


DELETED_SLOTS = ("goal-rearm", "below-rail")
CUMULATIVE_SLOTS = ("constraints", "side-effects", "decisions", "abandoned", "findings")
PADDED_SLOTS = (
    "brief",
    "criteria",
    "environment",
    "file-roles",
    "remaining",
    "open-questions",
    "blockers",
    "skills",
    "opening-ask",
)

FILLER_WORDS = (
    "the harness records this line so the section carries measurable weight",
    "each generated line is fixed text so two runs produce identical bytes",
    "no machine path appears here and no secret shape is imitated",
    "the resume budget is measured, not estimated, at hops one five and twenty",
)


def filler_line(slot: str, index: int, width: int) -> str:
    """A deterministic filler sentence of at least `width` characters."""
    seed = FILLER_WORDS[index % len(FILLER_WORDS)]
    text = f"{slot} {index}: {seed}"
    while len(text) < width:
        text = f"{text} {FILLER_WORDS[(index + len(text)) % len(FILLER_WORDS)]}"
    return text[:width].rstrip()


@dataclass
class FillerSize:
    """How much filler each section carries. `pad_lines` is the per-section body
    line count for the rewritten sections; `width` the character width of every
    filler line."""

    pad_lines: int = 2
    width: int = 88


def fill_skeleton(path: Path, hop: int, size: FillerSize) -> None:
    """Replace every FILL slot in a freshly-created skeleton with deterministic
    filler that satisfies validate_doc."""
    lines = path.read_text(encoding="utf-8").split("\n")
    out: list[str] = []
    counter = 0
    for line in lines:
        match = FILL_RE.search(line)
        if match is None:
            out.append(line)
            continue
        slot = match.group(1)
        prefix = line[: match.start()]
        counter += 1
        if slot in DELETED_SLOTS:
            continue
        if slot == "amended":
            out.append(prefix + "None.")
            continue
        if slot == "drift-check":
            out.append(prefix + "the first remaining action writes the next save-point, which is the goal.")
            continue
        if slot == "did":
            rest = line[match.end() :]
            second = FILL_RE.search(rest)
            did = f"generated hop {hop} filler"
            left = f"hops after {hop} still to generate"
            if second is not None:
                out.append(prefix + did + rest[: second.start()] + left + rest[second.end() :])
            else:
                out.append(prefix + did + rest)
            continue
        if slot == "left":
            out.append(prefix + f"hops after {hop} still to generate")
            continue
        if slot == "goal":
            out.append("> Measure what a save-point resume prompt costs to read at hop 20.")
            continue
        if slot == "next":
            out.extend(
                [
                    f"Generate hop {hop + 1} of the measured chain.",
                    "Report lines and chars/4 tokens for the generated file.",
                ]
            )
            continue
        if slot.endswith("-new") and slot[: -len("-new")] in CUMULATIVE_SLOTS:
            base = slot[: -len("-new")]
            out.extend(
                f"- [h{hop}] {filler_line(base, counter + i, size.width)}"
                for i in range(CUMULATIVE_ENTRIES_PER_HOP)
            )
            continue
        if slot in CUMULATIVE_SLOTS:
            out.extend(
                f"- [h{hop}] {filler_line(slot, counter + i, size.width)}"
                for i in range(CUMULATIVE_ENTRIES_PER_HOP)
            )
            continue
        if slot in PADDED_SLOTS:
            out.extend(filler_line(slot, counter + i, size.width) for i in range(size.pad_lines))
            continue
        out.append(prefix + filler_line(slot, counter, size.width))
    path.write_text("\n".join(out), encoding="utf-8", newline="\n")


def size_filler(skeleton_lines: int, skeleton_chars: int, slots: int) -> FillerSize:
    """Size the filler so a generated hop-1 file lands on the shape-1 corpus
    median (154 lines, 3.2k chars/4 tokens; PLAN.md Baseline).

    `skeleton_lines` / `skeleton_chars` measure the skeleton with every FILL
    line removed, `slots` counts the sections that take padded filler. The line
    budget is split evenly across those sections; the character width is then
    whatever makes the total land on the token median, clamped so the filler
    stays readable prose rather than a wall or a stub.
    """
    fixed_lines = len(CUMULATIVE_SLOTS) * CUMULATIVE_ENTRIES_PER_HOP + 2  # +2 = the Next: headlines
    budget = max(SHAPE1_MEDIAN_LINES - skeleton_lines - fixed_lines, slots)
    pad_lines = max(1, budget // max(slots, 1))
    filler_lines = pad_lines * slots + fixed_lines
    want_chars = SHAPE1_MEDIAN_TOKENS * 4 - skeleton_chars
    width = want_chars // max(filler_lines, 1)
    return FillerSize(pad_lines=pad_lines, width=max(40, min(200, width)))


def measure_skeleton(path: Path) -> tuple[int, int, int]:
    """Lines, characters, and padded-slot count of a skeleton, FILL lines aside."""
    text = path.read_text(encoding="utf-8")
    kept = [line for line in text.split("\n") if FILL_RE.search(line) is None]
    slots = sum(
        1
        for line in text.split("\n")
        if (m := FILL_RE.search(line)) is not None and m.group(1) in PADDED_SLOTS
    )
    return len(kept), len("\n".join(kept)), max(slots, 1)


# --- assertions -------------------------------------------------------------


@dataclass
class HopRow:
    run: int
    hop: int
    session_id: str
    model: str
    subtype: str = ""
    num_turns: str = ""
    cost_usd: str = ""
    input_tokens: str = ""
    context_tokens: str = ""
    checks: dict[str, str] = field(default_factory=dict)
    reasons: list[str] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        # A non-success subtype is a miss even when the hop still wrote a file
        # and printed rails: an `error_max_turns` chain is not a passing chain.
        return self.subtype == "success" and all(
            self.checks.get(name) == "PASS" for name in CHECKS
        )

    def cells(self) -> list[str]:
        return [
            str(self.run),
            str(self.hop),
            self.session_id,
            self.model,
            self.subtype,
            self.num_turns,
            self.cost_usd,
            self.input_tokens,
            self.context_tokens,
            *[self.checks.get(name, "FAIL") for name in CHECKS],
            "; ".join(self.reasons) or "-",
        ]


@dataclass
class Transcript:
    path: Path | None
    records: list[dict]

    @property
    def found(self) -> bool:
        return self.path is not None


def load_transcript(session_id: str, projects_root: Path) -> Transcript:
    """Locate the hop's transcript by the same glob `save_point.py new` uses,
    never a cwd slug computed here."""
    hits = sorted(glob.glob(str(projects_root / "*" / f"{session_id}.jsonl")))
    if not hits:
        return Transcript(None, [])
    records: list[dict] = []
    with open(hits[0], encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return Transcript(Path(hits[0]), records)


def _tool_uses(records: list[dict]):
    for index, record in enumerate(records):
        if record.get("type") != "assistant":
            continue
        message = record.get("message") or {}
        content = message.get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_use":
                yield index, record, block


def final_assistant_text(records: list[dict]) -> str:
    text = ""
    for record in records:
        if record.get("type") != "assistant":
            continue
        message = record.get("message") or {}
        content = message.get("content")
        if not isinstance(content, list):
            continue
        parts = [b.get("text") or "" for b in content if isinstance(b, dict) and b.get("type") == "text"]
        if parts:
            text = "\n".join(parts)
    return text


@dataclass
class SkillEvidence:
    skill_index: int | None = None
    skill_timestamp: float | None = None
    touch_index: int | None = None
    touch_name: str = ""
    touch_command: str = ""
    # A shell command that named handoffs/ but could not write: evidence worth
    # keeping in the report, not a failure.
    note_index: int | None = None
    usage: dict = field(default_factory=dict)


def skill_evidence(records: list[dict]) -> SkillEvidence:
    evidence = SkillEvidence()
    for index, record, block in _tool_uses(records):
        block_input = block.get("input") or {}
        serialized = json.dumps(block_input, ensure_ascii=False)
        # The Skill tool's structured input names the skill in its own `skill`
        # key. Matching the serialized input instead would let a call to any
        # other skill pass by merely mentioning this one in its `args`.
        if (
            evidence.skill_index is None
            and block.get("name") == "Skill"
            and block_input.get("skill") == SKILL_NAME
        ):
            evidence.skill_index = index
            evidence.skill_timestamp = parse_iso(record.get("timestamp", ""))
            evidence.usage = (record.get("message") or {}).get("usage") or {}
        name = str(block.get("name"))
        if (
            evidence.touch_index is not None
            or name in READ_ONLY_TOOLS
            or not HANDOFF_TOUCH_RE.search(serialized)
        ):
            continue
        command = shell_command_text(block.get("input") or {}, serialized)
        if (
            name in SHELL_TOOLS
            and not CREATION_MARKER_RE.search(serialized)
            and not is_write_indicator(command)
        ):
            if evidence.note_index is None:
                evidence.note_index = index
            continue
        evidence.touch_index = index
        evidence.touch_name = name
        evidence.touch_command = command[:100]
    return evidence


def assess_hop(
    *,
    run: int,
    hop: int,
    session_id: str,
    model: str,
    result: dict,
    fixture: Path,
    before: set[str],
    projects_root: Path,
) -> tuple[HopRow, str | None]:
    """Score one hop. Returns the TSV row and the between-rails text the next
    hop's prompt is built from (None when it could not be produced)."""
    row = HopRow(run=run, hop=hop, session_id=session_id, model=model)
    row.subtype = str(result.get("subtype", ""))
    row.num_turns = str(result.get("num_turns", ""))
    cost = result.get("total_cost_usd")
    row.cost_usd = f"{cost:.4f}" if isinstance(cost, (int, float)) else ""
    for name in CHECKS:
        row.checks[name] = "FAIL"

    if row.subtype and row.subtype != "success":
        row.reasons.append(f"result subtype {row.subtype}")

    handoff_dir = fixture / ".work" / "handoffs"
    after = handoff_files(handoff_dir)
    new_names = sorted(after - before)
    if len(new_names) == 1:
        row.checks["one_new_file"] = "PASS"
    else:
        row.reasons.append(f"{len(new_names)} new handoff files (want 1)")
    new_file = handoff_dir / new_names[0] if new_names else None

    transcript = load_transcript(session_id, projects_root)
    if not transcript.found:
        row.reasons.append("no transcript for the session id")

    evidence = skill_evidence(transcript.records)
    usage = evidence.usage
    if usage:
        row.input_tokens = str(usage.get("input_tokens", ""))
        row.context_tokens = str(
            int(usage.get("input_tokens") or 0)
            + int(usage.get("cache_creation_input_tokens") or 0)
            + int(usage.get("cache_read_input_tokens") or 0)
        )

    # Skill ordering, on EVERY hop. A handoff file with no preceding Skill call
    # is a FAIL row, never a vacuous pass.
    if evidence.skill_index is None:
        row.reasons.append("no Skill tool_use naming " + SKILL_NAME)
    elif evidence.touch_index is not None and evidence.touch_index < evidence.skill_index:
        row.reasons.append(
            f"{evidence.touch_name} touched handoffs/ at record {evidence.touch_index}"
            f" before the Skill call at {evidence.skill_index}: {evidence.touch_command}"
        )
    elif (
        new_file is not None
        and evidence.skill_timestamp is not None
        and created_at(new_file) + DISK_ORDER_GRACE_SECONDS < evidence.skill_timestamp
    ):
        row.reasons.append("the handoff file predates the Skill call on disk")
    else:
        row.checks["skill_order"] = "PASS"

    # A read-only shell mention of handoffs/ before the Skill call is not a
    # failure, but it is the evidence that made this classifier necessary, so
    # it stays visible in the report.
    if evidence.note_index is not None and (
        evidence.skill_index is None or evidence.note_index < evidence.skill_index
    ):
        row.reasons.append(
            f"note: shell read of handoffs/ at record {evidence.note_index}"
            f" before Skill at {evidence.skill_index}"
        )

    if new_file is None:
        return row, None

    validated = run_save_point(
        ["validate", str(new_file), "--projects-root", str(projects_root), "--strict-transcript"]
    )
    if validated.returncode == 0:
        row.checks["validate"] = "PASS"
    else:
        first = next(
            (line for line in validated.stdout.splitlines() if line.startswith("FAIL:")),
            validated.stderr.strip().splitlines()[:1] or ["validate failed"],
        )
        row.reasons.append(f"validate exit {validated.returncode}: {first if isinstance(first, str) else first[0]}")

    file_sid = frontmatter_value(new_file, "session_id")
    json_sid = str(result.get("session_id", ""))
    if file_sid.lower() == session_id.lower() == json_sid.lower():
        row.checks["session_id_match"] = "PASS"
    else:
        row.reasons.append(f"session id mismatch: file {file_sid}, flag {session_id}, json {json_sid}")

    result_text = str(result.get("result") or "")
    result_rails = rail_lines(result_text)
    if len(result_rails) == 2:
        row.checks["result_rails"] = "PASS"
    else:
        row.reasons.append(f"result text holds {len(result_rails)} rail lines (want 2)")

    transcript_text = final_assistant_text(transcript.records)
    transcript_rails = rail_lines(transcript_text)
    if len(transcript_rails) == 2:
        row.checks["transcript_rails"] = "PASS"
    else:
        row.reasons.append(f"final assistant text holds {len(transcript_rails)} rail lines (want 2)")

    emitted = run_save_point(["emit", str(new_file)])
    emitted_between = between_rails(emitted.stdout) if emitted.returncode == 0 else None
    if emitted_between is None:
        row.reasons.append(f"emit exit {emitted.returncode} produced no rails block")
    else:
        mismatches = []
        if between_rails(result_text) != emitted_between:
            mismatches.append("result")
        if between_rails(transcript_text) != emitted_between:
            mismatches.append("transcript")
        if mismatches:
            row.reasons.append("between-rails bytes differ from emit: " + ", ".join(mismatches))
        else:
            row.checks["between_rails_match"] = "PASS"

    return row, emitted_between


# --- the chain --------------------------------------------------------------


@dataclass
class HopCall:
    run: int
    hop: int
    session_id: str
    prompt: str
    fixture: Path
    projects_root: Path


@dataclass
class ChainOutcome:
    rows: list[HopRow]
    tsv_path: Path
    session_ids: list[str]
    deleted: list[str]
    kept_dir: Path
    transcripts_dir: Path

    @property
    def runs_passed(self) -> int:
        by_run: dict[int, bool] = {}
        for row in self.rows:
            by_run[row.run] = by_run.get(row.run, True) and row.passed
        return sum(1 for ok in by_run.values() if ok)

    @property
    def runs_total(self) -> int:
        return len({row.run for row in self.rows})


TASK_README = """# Hop-chain fixture

Four-step task. Each step appends one line to `notes.md` and commits it:

1. `step 1 done`
2. `step 2 done`
3. `step 3 done`
4. `step 4 done`

## Session protocol (applies to EVERY session, including resumed ones)

- Each session does exactly ONE step (the next unfinished one), commits it, then STOPS
  working on the task.
- After that one step, the session invokes `/session-flow:handoff` via the Skill tool
  (file method) so a fresh session can continue with the next step.
- Never write a handoff file by hand; the skill writes it.
- Do not do more than one step per session, even if the remaining steps look trivial.
"""


def make_fixture(work_dir: Path, run: int, pad_tokens: int) -> Path:
    fixture = Path(tempfile.mkdtemp(prefix=f"ccp-hop-{run}-", dir=str(work_dir)))
    (fixture / ".work" / "handoffs").mkdir(parents=True, exist_ok=True)
    # Pre-created: the skill's self-ignore guard appends through a shell
    # redirect, which a guardrails-equipped child cannot run.
    (fixture / ".work" / ".gitignore").write_text("*\n", encoding="utf-8", newline="\n")
    (fixture / "README.md").write_text(TASK_README, encoding="utf-8", newline="\n")
    if pad_tokens > 0:
        pad = "\n".join(
            filler_line("context-pad", i, 96) for i in range(max(1, pad_tokens * 4 // 97))
        )
        (fixture / "context-pad.md").write_text(
            "# Context pad\n\n" + pad + "\n", encoding="utf-8", newline="\n"
        )
    for command in (
        ["git", "init", "-q", "-b", "main", "."],
        ["git", "config", "user.email", "harness@example.invalid"],
        ["git", "config", "user.name", "hop-chain"],
        # The user's global config signs commits; the child has no signer.
        ["git", "config", "commit.gpgsign", "false"],
        # Kill the LF/CRLF warnings the model otherwise investigates.
        ["git", "config", "core.autocrlf", "false"],
        ["git", "add", "-A"],
        ["git", "commit", "-qm", "fixture: initial"],
    ):
        subprocess.run(
            command, cwd=str(fixture), capture_output=True, text=True, encoding="utf-8", check=True
        )
    return fixture


def hop1_prompt(fixture: Path, pad_tokens: int) -> str:
    lead = ""
    if pad_tokens > 0:
        lead = f"First read {(fixture / 'context-pad.md').as_posix()} in full. "
    return (
        f"You are working in the git repository at {fixture.as_posix()} (the current directory). "
        f"{lead}"
        "Do step 1 of the task in README.md: create notes.md containing the single line "
        "'step 1 done' and commit it with the message 'step 1'. Then STOP working on the task "
        "and, after step 1, invoke /session-flow:handoff via the Skill tool so a fresh session "
        "can do step 2. Do not do steps 2-4 yourself. The session protocol in README.md "
        "(one step per session, then the Skill tool) binds every later session too; make "
        "sure the handoff carries it."
    )


def child_env() -> dict[str, str]:
    env = {name: os.environ[name] for name in ENV_ALLOWLIST if os.environ.get(name)}
    if "HOME" not in env and env.get("USERPROFILE"):
        env["HOME"] = env["USERPROFILE"]
    return env


def kill_tree(process: subprocess.Popen) -> None:
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/T", "/F", "/PID", str(process.pid)],
            capture_output=True,
            text=True,
            encoding="utf-8",
            check=False,
        )
    else:
        try:
            os.killpg(os.getpgid(process.pid), 9)
        except OSError:
            process.kill()


def live_runner(cfg: argparse.Namespace):
    """Build the runner that spends money. Never called from --dry-run."""
    claude = shutil.which("claude")
    if not claude:
        raise SystemExit("error: `claude` not found on PATH")

    def run(call: HopCall) -> dict:
        command = [
            claude,
            "-p",
            "--output-format",
            "json",
            # Phase 0 (CLI 2.1.259) ran `--permission-mode dontAsk --allowedTools`.
            # On 2.1.260 that pair, and the same allow list as project
            # permission rules, left every mutating tool denied ("Permission to
            # use Write has been denied because Claude Code is running in
            # don't ask mode", three hop-1 transcripts, 2026-09-03). The
            # fixture is a throwaway temp repo with a stripped env, so the
            # child bypasses prompts and `--tools` pins the same tool surface
            # the allow list used to grant.
            "--permission-mode",
            "bypassPermissions",
            "--tools",
            ALLOWED_TOOLS,
            "--setting-sources",
            "project",
            "--plugin-dir",
            str(cfg.plugin_dir),
            "--add-dir",
            str(cfg.plugin_dir),
            "--model",
            cfg.model,
            "--max-turns",
            str(cfg.max_turns),
            "--max-budget-usd",
            str(cfg.budget_usd_per_hop),
            "--session-id",
            call.session_id,
        ]
        popen_extra: dict = {}
        if os.name == "nt":
            popen_extra["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
        else:
            popen_extra["start_new_session"] = True
        process = subprocess.Popen(  # noqa: S603 - argv list, no shell
            command,
            cwd=str(call.fixture),
            env=child_env(),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            **popen_extra,
        )
        try:
            stdout, stderr = process.communicate(call.prompt, timeout=cfg.timeout_seconds)
        except subprocess.TimeoutExpired:
            kill_tree(process)
            try:
                process.communicate(timeout=30)
            except subprocess.TimeoutExpired:
                pass
            return {"subtype": "error_timeout", "result": "", "session_id": call.session_id}
        try:
            return json.loads(stdout)
        except json.JSONDecodeError:
            return {
                "subtype": "error_unparsable_output",
                "result": "",
                "session_id": call.session_id,
                "stderr": stderr[-400:],
            }

    return run


def next_prompt(rails_text: str) -> str:
    return rails_text


def execute_chain(cfg: argparse.Namespace, runner, projects_root: Path, work_dir: Path) -> ChainOutcome:
    rows: list[HopRow] = []
    session_ids: list[str] = []
    fixtures: list[Path] = []
    sessions_per_run = cfg.hops + 1

    for run in range(1, cfg.runs + 1):
        fixture = make_fixture(work_dir, run, cfg.pad_context)
        fixtures.append(fixture)
        prompt = hop1_prompt(fixture, cfg.pad_context)
        for hop in range(1, sessions_per_run + 1):
            session_id = str(uuid.uuid4())
            session_ids.append(session_id)
            before = handoff_files(fixture / ".work" / "handoffs")
            call = HopCall(
                run=run,
                hop=hop,
                session_id=session_id,
                prompt=prompt,
                fixture=fixture,
                projects_root=projects_root,
            )
            result = runner(call)
            row, rails_text = assess_hop(
                run=run,
                hop=hop,
                session_id=session_id,
                model=cfg.model or "",
                result=result,
                fixture=fixture,
                before=before,
                projects_root=projects_root,
            )
            rows.append(row)
            _keep_produced_files(fixture, before, work_dir, run, hop)
            if not row.passed:
                _keep_failed_transcript(session_id, projects_root, work_dir, run, hop)
            if rails_text is None:
                rows.extend(_skipped_rows(run, hop, sessions_per_run, cfg.model or ""))
                break
            prompt = next_prompt(rails_text)

    tsv_path = write_tsv(rows, cfg, work_dir)
    deleted: list[str] = []
    if not cfg.keep:
        deleted = cleanup(session_ids, projects_root, fixtures)
    return ChainOutcome(
        rows=rows,
        tsv_path=tsv_path,
        session_ids=session_ids,
        deleted=deleted,
        kept_dir=work_dir / "handoffs",
        transcripts_dir=work_dir / "transcripts",
    )


def _keep_produced_files(fixture: Path, before: set[str], work_dir: Path, run: int, hop: int) -> None:
    """Copy each hop's handoff file out of the fixture before cleanup removes
    the fixture. `--budget --live-hop1` reads the hop-1 copy from here."""
    handoff_dir = fixture / ".work" / "handoffs"
    keep = work_dir / "handoffs"
    keep.mkdir(parents=True, exist_ok=True)
    for name in sorted(handoff_files(handoff_dir) - before):
        shutil.copy2(handoff_dir / name, keep / f"run{run}-hop{hop}-{name}")


def _keep_failed_transcript(session_id: str, projects_root: Path, work_dir: Path, run: int, hop: int) -> None:
    """Copy a failing hop's transcript out before cleanup deletes it.

    A row that fails on transcript evidence is exactly the row someone needs to
    read, and the live acceptance set lost two of them to cleanup. Cleanup of
    `~/.claude/projects` itself is unchanged; this only takes a copy first.
    """
    if not session_id:
        return
    hits = sorted(glob.glob(str(projects_root / "*" / f"{session_id}.jsonl")))
    if not hits:
        return
    keep = work_dir / "transcripts"
    keep.mkdir(parents=True, exist_ok=True)
    shutil.copy2(hits[0], keep / f"run{run}-hop{hop}-{session_id}.jsonl")


def _skipped_rows(run: int, after_hop: int, sessions: int, model: str) -> list[HopRow]:
    """A hop that produced no rails text ends its run: the later hops of that run
    have no prompt, and are recorded as unrun failures rather than dropped."""
    rows = []
    for hop in range(after_hop + 1, sessions + 1):
        row = HopRow(run=run, hop=hop, session_id="", model=model, subtype="not_run")
        row.checks = {name: "FAIL" for name in CHECKS}
        row.reasons.append(f"hop {after_hop} produced no rails text; the chain stopped")
        rows.append(row)
    return rows


def write_tsv(rows: list[HopRow], cfg: argparse.Namespace, work_dir: Path) -> Path:
    path = Path(cfg.report) if cfg.report else work_dir / "hop-chain.tsv"
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as fh:
        fh.write("\t".join(TSV_HEADER) + "\n")
        for row in rows:
            fh.write("\t".join(row.cells()) + "\n")
    return path


def cleanup(session_ids: list[str], projects_root: Path, fixtures: list[Path]) -> list[str]:
    """Delete exactly the transcripts whose session ids this harness created,
    plus the fixture repositories. The install-tree directory the CLI creates
    for a --plugin-dir plugin (~/.claude/plugins/data/session-flow-inline/) is
    left alone, and ~/.claude/settings.json is never touched."""
    deleted: list[str] = []
    for session_id in session_ids:
        if not session_id:
            continue
        for hit in glob.glob(str(projects_root / "*" / f"{session_id}.jsonl")):
            try:
                os.remove(hit)
                deleted.append(hit)
            except OSError:
                pass
        for sibling in glob.glob(str(projects_root / "*" / session_id)):
            path = Path(sibling)
            if path.is_dir():
                rmtree(path)
                deleted.append(sibling)
    for fixture in fixtures:
        rmtree(fixture)
        deleted.append(str(fixture))
    return deleted


def report(outcome: ChainOutcome) -> int:
    print("\t".join(TSV_HEADER))
    for row in outcome.rows:
        print("\t".join(row.cells()))
    passed = outcome.runs_passed
    total = outcome.runs_total
    print(f"summary: {passed}/{total} runs passed ({sum(1 for r in outcome.rows if r.passed)}/{len(outcome.rows)} hops)")
    print(f"tsv: {outcome.tsv_path.as_posix()}")
    print(f"handoff files kept: {outcome.kept_dir.as_posix()} (feed hop 1 to --budget --live-hop1)")
    copies = sorted(outcome.transcripts_dir.glob("*.jsonl")) if outcome.transcripts_dir.is_dir() else []
    print(f"failed-hop transcripts: {outcome.transcripts_dir.as_posix()} ({len(copies)} kept)")
    return 0 if outcome.rows and passed == total else 1


# --- --budget ---------------------------------------------------------------


def generate_chain(root: Path, hops: int) -> list[Path]:
    """Generate `hops` handoff files through the real `save_point.py new`, each
    filled with deterministic filler, each validated strictly."""
    repo = root / "repo"
    memory = repo / ".work"
    (memory / "handoffs").mkdir(parents=True, exist_ok=True)
    (memory / ".gitignore").write_text("*\n", encoding="utf-8", newline="\n")
    projects = root / "projects" / "generated"
    projects.mkdir(parents=True, exist_ok=True)

    files: list[Path] = []
    size = FillerSize()
    previous: Path | None = None
    for hop in range(1, hops + 1):
        session_id = str(uuid.uuid5(BUDGET_NAMESPACE, f"hop-{hop}"))
        (projects / f"{session_id}.jsonl").write_text("", encoding="utf-8", newline="\n")
        when = (BUDGET_EPOCH + timedelta(minutes=hop)).strftime("%Y-%m-%dT%H:%M:%SZ")
        args = [
            "new",
            "--topic",
            "budget-projection",
            "--memory-dir",
            str(memory),
            "--repo-root",
            str(repo),
            "--projects-root",
            str(root / "projects"),
            "--session-id",
            session_id,
            "--now",
            when,
        ]
        args += ["--previous", str(previous)] if previous else ["--no-previous"]
        made = run_save_point(args)
        if made.returncode != 0:
            raise SystemExit(f"budget: `new` failed at hop {hop}: {made.stdout}{made.stderr}")
        path = Path(made.stdout.strip())
        if hop == 1:
            lines, chars, slots = measure_skeleton(path)
            size = size_filler(lines, chars, slots)
        fill_skeleton(path, hop, size)
        checked = run_save_point(
            ["validate", str(path), "--projects-root", str(root / "projects"), "--strict-transcript"]
        )
        if checked.returncode != 0:
            raise SystemExit(f"budget: generated hop {hop} does not validate:\n{checked.stdout}")
        files.append(path)
        previous = path
    return files


def cmd_budget(cfg: argparse.Namespace) -> int:
    work_dir = Path(cfg.work_dir) if cfg.work_dir else Path(tempfile.mkdtemp(prefix="hop-chain-budget-"))
    work_dir.mkdir(parents=True, exist_ok=True)
    root = work_dir / "budget"
    rmtree(root)
    try:
        files = generate_chain(root, BUDGET_HOPS)
        print(f"generated {len(files)} hops through save_point.py new; every hop validates strictly")
        print("hop\tlines\tchars\ttokens_chars_div_4\tsource")
        for hop in BUDGET_REPORT_HOPS:
            text = files[hop - 1].read_text(encoding="utf-8")
            print(f"{hop}\t{len(text.splitlines())}\t{len(text)}\t{token_estimate(text)}\tgenerated")
        if cfg.live_hop1:
            live = Path(cfg.live_hop1)
            if not live.is_file():
                print(f"live-hop1: not a file: {live.as_posix()}", file=sys.stderr)
                return 2
            text = live.read_text(encoding="utf-8")
            print(f"1\t{len(text.splitlines())}\t{len(text)}\t{token_estimate(text)}\tlive {live.name}")
        print(
            f"filler rule: shape-1 corpus median {SHAPE1_MEDIAN_LINES} lines / "
            f"{SHAPE1_MEDIAN_TOKENS} tokens, split across the padded sections at hop 1 and held "
            f"constant; each cumulative section grows {CUMULATIVE_ENTRIES_PER_HOP} entries per hop"
        )
        return 0
    finally:
        if not cfg.keep:
            rmtree(root)
            if not cfg.work_dir:
                rmtree(work_dir)


# --- --dry-run --------------------------------------------------------------
#
# A fake runner replaces the `claude` subprocess: it writes a synthetic
# transcript and result JSON while calling the real save_point.py, so the
# assertion, TSV, and cleanup paths under test are the live ones.


# Shell tool_use blocks injected before the Skill call. Live evidence: a model
# resuming a hop runs `cat -n <handoff>` through Bash, which the first
# classifier scored as a free-hand bypass. A shell command naming handoffs/ is
# a touch only when it could WRITE.
SHELL_PROBES = {
    "shell_read_before_skill": (
        "Bash",
        {"command": 'cat -n "{handoffs}/predecessor.md"', "description": "read the predecessor"},
    ),
    "shell_write_before_skill": (
        "Bash",
        {"command": 'cp notes.md "{handoffs}/free-hand.md"', "description": "copy a file"},
    ),
    "shell_stderr_redirect_before_skill": (
        "Bash",
        {"command": 'grep -c "handoffs/" notes.md 2>&1', "description": "count mentions"},
    ),
    "powershell_write_before_skill": (
        "PowerShell",
        {"command": 'Set-Content -Path "{handoffs}/free-hand.md" -Value "written by hand"'},
    ),
}

DEFECTS = (
    "no_skill",
    "foreign_skill_naming_ours_in_args",
    "write_before_skill",
    *SHELL_PROBES,
    "sid_mismatch",
    "budget_exhausted",
    "turn_limit",
    "one_rail",
    "three_rails",
    "crlf",
)


def _record(session_id: str, when: datetime, content: list[dict], usage: dict | None = None) -> dict:
    return {
        "type": "assistant",
        "timestamp": when.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
        "sessionId": session_id,
        "session_id": session_id,
        "entrypoint": "sdk-cli",
        "uuid": str(uuid.uuid4()),
        "message": {
            "role": "assistant",
            "model": "fake-model",
            "content": content,
            "usage": usage
            or {
                "input_tokens": 1234,
                "cache_creation_input_tokens": 2000,
                "cache_read_input_tokens": 30000,
                "output_tokens": 500,
            },
        },
    }


def _write_jsonl(path: Path, records: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as fh:
        for record in records:
            fh.write(json.dumps(record, ensure_ascii=False) + "\n")


def make_fake_runner(defects: dict[int, set[str]]):
    """Build a runner whose hop N carries the defects in `defects[N]`."""

    def run(call: HopCall) -> dict:
        flags = defects.get(call.hop, set())
        slug = "fake"
        transcript = call.projects_root / slug / f"{call.session_id}.jsonl"
        now = datetime.now(timezone.utc)

        if "budget_exhausted" in flags:
            _write_jsonl(transcript, [_record(call.session_id, now, [{"type": "text", "text": "starting"}])])
            return {
                "type": "result",
                "subtype": "error_max_budget_usd",
                "is_error": True,
                "result": "",
                "session_id": call.session_id,
                "num_turns": 6,
                "total_cost_usd": 3.0,
            }

        memory = call.fixture / ".work"
        previous = sorted((memory / "handoffs").glob(HANDOFF_GLOB))

        prelude: list[dict] = [
            _record(call.session_id, now, [{"type": "text", "text": "doing step 1"}])
        ]
        if previous:
            # What a real resume hop does first: the rails text opens
            # `Read @<...>/handoffs/<file>.md`, before any Skill call.
            prelude.append(
                _record(
                    call.session_id,
                    now,
                    [
                        {
                            "type": "tool_use",
                            "id": "toolu_read_pred",
                            "name": "Read",
                            "input": {"file_path": previous[-1].as_posix()},
                        }
                    ],
                )
            )
        for probe, (tool_name, tool_input) in SHELL_PROBES.items():
            if probe not in flags:
                continue
            handoffs = (call.fixture / ".work" / "handoffs").as_posix()
            prelude.append(
                _record(
                    call.session_id,
                    now,
                    [
                        {
                            "type": "tool_use",
                            "id": f"toolu_{probe}",
                            "name": tool_name,
                            "input": {k: v.format(handoffs=handoffs) for k, v in tool_input.items()},
                        }
                    ],
                )
            )
        if "write_before_skill" in flags:
            prelude.append(
                _record(
                    call.session_id,
                    now,
                    [
                        {
                            "type": "tool_use",
                            "id": "toolu_early",
                            "name": "Write",
                            "input": {
                                "file_path": (call.fixture / ".work" / "handoffs" / "early.md").as_posix(),
                                "content": "free-hand",
                            },
                        }
                    ],
                )
            )
        if "foreign_skill_naming_ours_in_args" in flags:
            # A Skill call to some OTHER skill whose args merely mention this
            # one. Structurally it is not our skill, so it must not satisfy
            # skill_order; only the `skill` key decides.
            prelude.append(
                _record(
                    call.session_id,
                    now,
                    [
                        {
                            "type": "tool_use",
                            "id": "toolu_foreign_skill",
                            "name": "Skill",
                            "input": {"skill": "other:skill", "args": SKILL_NAME},
                        }
                    ],
                )
            )
        elif "no_skill" not in flags:
            prelude.append(
                _record(
                    call.session_id,
                    now,
                    [
                        {
                            "type": "tool_use",
                            "id": "toolu_skill",
                            "name": "Skill",
                            "input": {"skill": SKILL_NAME, "args": f"file hop{call.hop}"},
                        }
                    ],
                )
            )
        # The transcript must exist before `new` runs: `new` resolves it by glob
        # and bakes the path into frontmatter, and --strict-transcript then holds
        # the file to it.
        _write_jsonl(transcript, prelude)

        args = [
            "new",
            "--topic",
            "dry-run",
            "--memory-dir",
            str(memory),
            "--repo-root",
            str(call.fixture),
            "--projects-root",
            str(call.projects_root),
            "--session-id",
            call.session_id,
            # Filename stamps resolve to the second, so a chain generated in one
            # second would collide; space the hops a minute apart.
            "--now",
            (now + timedelta(minutes=call.hop)).strftime("%Y-%m-%dT%H:%M:%SZ"),
        ]
        args += ["--previous", str(previous[-1])] if previous else ["--no-previous"]
        made = run_save_point(args)
        if made.returncode != 0:
            raise SystemExit(f"dry-run: `new` failed at hop {call.hop}: {made.stdout}{made.stderr}")
        path = Path(made.stdout.strip())
        fill_skeleton(path, call.hop, FillerSize())

        emitted = run_save_point(["emit", str(path)])
        if emitted.returncode != 0:
            raise SystemExit(f"dry-run: `emit` failed at hop {call.hop}: {emitted.stdout}{emitted.stderr}")
        resume = emitted.stdout.rstrip("\n")

        after = datetime.now(timezone.utc) + timedelta(seconds=1)
        records = prelude + [
            _record(
                call.session_id,
                after,
                [
                    {
                        "type": "tool_use",
                        "id": "toolu_write",
                        "name": "Write",
                        "input": {"file_path": path.as_posix(), "content": "handoffs/ save-point"},
                    }
                ],
            ),
            _record(call.session_id, after, [{"type": "text", "text": resume}]),
        ]
        _write_jsonl(transcript, records)

        result_text = resume
        if "one_rail" in flags:
            result_text = result_text.replace("─" * 58, "", 1)
        if "three_rails" in flags:
            result_text = result_text + "\n" + "─" * 58
        if "crlf" in flags:
            result_text = result_text.replace("\n", "\r\n")
        session_id = str(uuid.uuid4()) if "sid_mismatch" in flags else call.session_id
        return {
            "type": "result",
            "subtype": "error_max_turns" if "turn_limit" in flags else "success",
            "is_error": False,
            "result": result_text,
            "session_id": session_id,
            "num_turns": 12,
            "total_cost_usd": 0.42,
        }

    return run


@dataclass
class Case:
    name: str
    defects: dict[int, set[str]]
    hops: int
    expect_pass: bool
    expect_reason: str = ""
    expect_check: str = ""
    pad_context: int = 0
    expect_row: int = 0


DRY_RUN_CASES = (
    Case("positive_chain", {}, hops=3, expect_pass=True),
    Case("pad_context_fixture_passes", {}, hops=0, expect_pass=True, pad_context=4000),
    Case("crlf_only_difference_passes", {1: {"crlf"}}, hops=0, expect_pass=True),
    Case(
        "file_without_a_preceding_skill_call_fails",
        {1: {"no_skill"}},
        hops=0,
        expect_pass=False,
        expect_reason="no Skill tool_use",
        expect_check="skill_order",
    ),
    Case(
        "another_skill_naming_ours_in_its_args_fails",
        {1: {"foreign_skill_naming_ours_in_args"}},
        hops=0,
        expect_pass=False,
        expect_reason="no Skill tool_use",
        expect_check="skill_order",
    ),
    Case(
        "write_into_handoffs_before_the_skill_call_fails",
        {1: {"write_before_skill"}},
        hops=0,
        expect_pass=False,
        expect_reason="before the Skill call",
        expect_check="skill_order",
    ),
    Case(
        "shell_read_of_handoffs_before_skill_passes_with_a_note",
        {1: {"shell_read_before_skill"}},
        hops=0,
        expect_pass=True,
        expect_reason="shell read of handoffs/",
    ),
    Case(
        "shell_command_with_only_a_stderr_redirect_passes",
        {1: {"shell_stderr_redirect_before_skill"}},
        hops=0,
        expect_pass=True,
        expect_reason="shell read of handoffs/",
    ),
    Case(
        "shell_copy_into_handoffs_before_skill_fails_with_the_command",
        {1: {"shell_write_before_skill"}},
        hops=0,
        expect_pass=False,
        expect_reason="cp notes.md",
        expect_check="skill_order",
    ),
    Case(
        "powershell_write_into_handoffs_before_skill_fails",
        {1: {"powershell_write_before_skill"}},
        hops=0,
        expect_pass=False,
        expect_reason="Set-Content",
        expect_check="skill_order",
    ),
    Case(
        "mismatched_session_id_fails",
        {1: {"sid_mismatch"}},
        hops=0,
        expect_pass=False,
        expect_reason="session id mismatch",
        expect_check="session_id_match",
    ),
    Case(
        "budget_exhausted_fails_with_the_subtype",
        {1: {"budget_exhausted"}},
        hops=0,
        expect_pass=False,
        expect_reason="error_max_budget_usd",
        expect_check="one_new_file",
    ),
    Case(
        # Reaches the _skipped_rows path: hop 2 yields no rails, so hops 3 and 4
        # have no prompt and are recorded as unrun failures rather than dropped.
        # A row-aggregation defect there (appending the list instead of
        # extending) crashes the TSV write, which this case would surface.
        "a_mid_chain_hop_without_rails_stops_the_run_and_records_the_rest",
        {2: {"budget_exhausted"}},
        hops=3,
        expect_pass=False,
        expect_reason="error_max_budget_usd",
        expect_row=1,
    ),
    Case(
        "non_success_subtype_fails_even_with_every_check_green",
        {1: {"turn_limit"}},
        hops=0,
        expect_pass=False,
        expect_reason="result subtype error_max_turns",
    ),
    Case(
        "one_rail_fails",
        {1: {"one_rail"}},
        hops=0,
        expect_pass=False,
        expect_reason="1 rail lines",
        expect_check="result_rails",
    ),
    Case(
        "three_rails_fails",
        {1: {"three_rails"}},
        hops=0,
        expect_pass=False,
        expect_reason="3 rail lines",
        expect_check="result_rails",
    ),
)


def _case_config(base: argparse.Namespace, case: Case, work_dir: Path) -> argparse.Namespace:
    cfg = argparse.Namespace(**vars(base))
    cfg.runs = 1
    cfg.hops = case.hops
    cfg.model = "dry-run-model"
    cfg.pad_context = case.pad_context
    cfg.keep = False
    cfg.report = str(work_dir / "hop-chain.tsv")
    return cfg


def check_child_env() -> tuple[bool, str]:
    """The child env carries only the allowlist, so no launching-session
    variable (its id, its effort, its plugin-data dir) can reach a hop."""
    env = child_env()
    leaked = sorted(k for k in env if k.startswith("CLAUDE_") and k != "CLAUDE_CONFIG_DIR")
    if leaked:
        return False, f"CLAUDE_* variables leaked into the child env: {leaked}"
    outside = sorted(k for k in env if k not in ENV_ALLOWLIST)
    if outside:
        return False, f"variables outside the allowlist: {outside}"
    if not env.get("PATH"):
        return False, "the child env carries no PATH"
    return True, ""


def _run_case(base: argparse.Namespace, case: Case) -> tuple[bool, str]:
    work_dir = Path(tempfile.mkdtemp(prefix=f"hop-chain-dry-{case.name}-"))
    projects_root = work_dir / "projects"
    (projects_root / "fake").mkdir(parents=True, exist_ok=True)
    decoys = [projects_root / "fake" / f"{uuid.uuid4()}.jsonl" for _ in range(2)]
    for decoy in decoys:
        decoy.write_text("", encoding="utf-8", newline="\n")
    decoy_dir = projects_root / "fake" / str(uuid.uuid4())
    decoy_dir.mkdir(parents=True, exist_ok=True)
    try:
        cfg = _case_config(base, case, work_dir)
        outcome = execute_chain(cfg, make_fake_runner(case.defects), projects_root, work_dir)
        expected_rows = cfg.hops + 1
        if len(outcome.rows) != expected_rows:
            return False, f"expected {expected_rows} rows, got {len(outcome.rows)}"
        if not outcome.tsv_path.is_file():
            return False, "no TSV written"
        tsv = outcome.tsv_path.read_text(encoding="utf-8").splitlines()
        if len(tsv) != expected_rows + 1:
            return False, f"TSV has {len(tsv)} lines, expected {expected_rows + 1}"
        row = outcome.rows[case.expect_row]
        if case.expect_pass:
            if not all(r.passed for r in outcome.rows):
                bad = next(r for r in outcome.rows if not r.passed)
                return False, f"hop {bad.hop} failed: {'; '.join(bad.reasons)}"
            # The produced files outlive the fixtures cleanup removes.
            kept = sorted(outcome.kept_dir.glob(HANDOFF_GLOB))
            if len(kept) != expected_rows:
                return False, f"{len(kept)} handoff files kept, expected {expected_rows}"
            if case.expect_reason and not any(case.expect_reason in r for r in row.reasons):
                return False, f"note {case.expect_reason!r} absent from a passing row: {row.reasons}"
        else:
            if row.passed:
                return False, "row passed but the case injects a defect"
            if case.expect_check and row.checks.get(case.expect_check) != "FAIL":
                return False, f"check {case.expect_check} is {row.checks.get(case.expect_check)}, expected FAIL"
            if case.expect_reason and not any(case.expect_reason in r for r in row.reasons):
                return False, f"reason {case.expect_reason!r} absent from {row.reasons}"
        # A failing hop keeps its transcript for inspection; a passing one does
        # not (cleanup removes it from ~/.claude/projects either way).
        want_copies = sum(1 for r in outcome.rows if not r.passed and r.session_id)
        copies = sorted(outcome.transcripts_dir.glob("*.jsonl")) if outcome.transcripts_dir.is_dir() else []
        if len(copies) != want_copies:
            return False, f"{len(copies)} transcript copies kept, expected {want_copies}"
        # Cleanup deleted exactly the harness's own session ids.
        for session_id in outcome.session_ids:
            if session_id and list(glob.glob(str(projects_root / "*" / f"{session_id}.jsonl"))):
                return False, f"cleanup left transcript {session_id}"
        for decoy in decoys:
            if not decoy.is_file():
                return False, f"cleanup deleted the decoy transcript {decoy.name}"
        if not decoy_dir.is_dir():
            return False, "cleanup deleted the decoy session directory"
        return True, ""
    finally:
        rmtree(work_dir)


def check_main_level_orchestration() -> tuple[bool, str]:
    """Drive the live driver itself, `main()`, with only the `claude`
    subprocess swapped out.

    The per-case runs above call `execute_chain` directly, so they never touch
    argument parsing, projects-root resolution, work-dir creation, the exit
    code, or the `report()` print path. An undefined name or a wrong call
    signature on any of those would first surface mid-spend. This case closes
    that gap for a two-run, three-hop chain.
    """
    work_dir = Path(tempfile.mkdtemp(prefix="hop-chain-main-"))
    projects_root = work_dir / "projects"
    (projects_root / "fake").mkdir(parents=True, exist_ok=True)
    decoys = [projects_root / "fake" / f"{uuid.uuid4()}.jsonl" for _ in range(2)]
    for decoy in decoys:
        decoy.write_text("", encoding="utf-8", newline="\n")
    try:
        argv = [
            "--runs",
            "2",
            "--hops",
            "3",
            "--model",
            "dry-run-model",
            "--projects-root",
            str(projects_root),
            "--work-dir",
            str(work_dir),
        ]
        captured = io.StringIO()
        with contextlib.redirect_stdout(captured):
            code = main(argv, runner_factory=lambda _cfg: make_fake_runner({}))
        output = captured.getvalue()
        if code != 0:
            return False, f"main() returned {code}, expected 0:\n{output}"
        if "summary: 2/2 runs passed" not in output:
            return False, f"summary line missing or wrong:\n{output}"

        tsv = work_dir / "hop-chain.tsv"
        if not tsv.is_file():
            return False, "main() wrote no TSV"
        lines = tsv.read_text(encoding="utf-8").splitlines()
        if lines[0].split("\t") != list(TSV_HEADER):
            return False, "TSV header does not match TSV_HEADER"
        rows = lines[1:]
        if len(rows) != 8:
            return False, f"TSV has {len(rows)} rows, expected 8 (2 runs x 4 sessions)"

        kept = sorted((work_dir / "handoffs").glob("run1-hop1-*handoff*.md"))
        if len(kept) != 1:
            return False, f"{len(kept)} kept hop-1 files for run 1, expected 1"
        if "## Resume prompt" not in kept[0].read_text(encoding="utf-8"):
            return False, "the kept hop-1 file is not a shape-2 handoff"

        session_column = TSV_HEADER.index("session_id")
        session_ids = [row.split("\t")[session_column] for row in rows]
        if len(set(session_ids)) != 8:
            return False, "session ids are not unique per hop"
        for session_id in session_ids:
            if list(glob.glob(str(projects_root / "*" / f"{session_id}.jsonl"))):
                return False, f"cleanup left transcript {session_id}"
        for decoy in decoys:
            if not decoy.is_file():
                return False, f"cleanup deleted the decoy transcript {decoy.name}"
        return True, ""
    finally:
        rmtree(work_dir)


def cmd_dry_run(cfg: argparse.Namespace) -> int:
    failures = 0
    for case in DRY_RUN_CASES:
        ok, detail = _run_case(cfg, case)
        if ok:
            print(f"PASS: {case.name}")
        else:
            failures += 1
            print(f"FAIL: {case.name}: {detail}")
    for name, check in (
        ("child_env_carries_only_the_allowlist", check_child_env),
        ("main_level_live_orchestration", check_main_level_orchestration),
    ):
        ok, detail = check()
        if ok:
            print(f"PASS: {name}")
        else:
            failures += 1
            print(f"FAIL: {name}: {detail}")
    budget_cfg = argparse.Namespace(**vars(cfg))
    budget_cfg.work_dir = None
    budget_cfg.live_hop1 = None
    budget_cfg.keep = False
    try:
        code = cmd_budget(budget_cfg)
        ok = code == 0
    except SystemExit as exc:
        ok = False
        print(f"  budget error: {exc}")
    if ok:
        print("PASS: budget_projection_generates_and_validates_20_hops")
    else:
        failures += 1
        print("FAIL: budget_projection_generates_and_validates_20_hops")
    total = len(DRY_RUN_CASES) + 3
    print(f"dry-run: {total - failures}/{total} cases passed")
    return 1 if failures else 0


# --- CLI --------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="hop_chain.py",
        description="Headless hop-chain harness for /session-flow:handoff.",
    )
    parser.add_argument("--runs", type=int, default=3, help="chains per invocation (default 3)")
    parser.add_argument("--hops", type=int, default=3, help="rails transfers per chain; sessions are hops+1 (default 3)")
    parser.add_argument("--model", help="model id, required for a live run and recorded in the TSV")
    parser.add_argument("--max-turns", type=int, default=40, help="per-hop turn cap (default 40)")
    parser.add_argument("--budget-usd-per-hop", type=float, default=3.0, help="per-hop spend cap (default 3)")
    parser.add_argument("--timeout-seconds", type=int, default=900, help="per-hop wall clock cap (default 900)")
    parser.add_argument("--plugin-dir", default=str(DEFAULT_PLUGIN_DIR), help="session-flow plugin dir to load")
    parser.add_argument("--pad-context", type=int, default=0, help="tokens of filler the hop-1 prompt orders read first")
    parser.add_argument("--projects-root", help="transcript root (default ~/.claude/projects)")
    parser.add_argument("--work-dir", help="scratch root for fixtures and the report (default: a fresh temp dir)")
    parser.add_argument("--report", help="TSV path (default <work-dir>/hop-chain.tsv)")
    parser.add_argument("--dry-run", action="store_true", help="self-test against a fake runner; spends nothing")
    parser.add_argument("--budget", action="store_true", help="generate a 20-hop chain and report its size; spends nothing")
    parser.add_argument("--live-hop1", help="--budget only: a live hop-1 file reported beside the generated hop 1")
    parser.add_argument("--keep", action="store_true", help="keep fixtures and transcripts")
    return parser


def main(argv: list[str] | None = None, runner_factory=live_runner) -> int:
    """The whole driver. `runner_factory` exists so --dry-run can drive THIS
    function with the `claude` subprocess swapped out: every other step, the
    argument parsing, the run loop, row aggregation, the kept-files copy, the
    report write, and cleanup, is then the same code a live run executes."""
    _utf8_streams()
    cfg = build_parser().parse_args(argv)
    if not SAVE_POINT.is_file():
        print(f"error: save_point.py not found at {SAVE_POINT.as_posix()}", file=sys.stderr)
        return 2
    if cfg.dry_run and cfg.budget:
        print("error: --dry-run and --budget are separate modes", file=sys.stderr)
        return 2
    if cfg.dry_run:
        return cmd_dry_run(cfg)
    if cfg.budget:
        return cmd_budget(cfg)
    if not cfg.model:
        print("error: --model is required for a live run (it is recorded in the TSV)", file=sys.stderr)
        return 2
    if cfg.runs < 1 or cfg.hops < 1:
        print("error: --runs and --hops must be at least 1", file=sys.stderr)
        return 2

    projects_root = (
        Path(cfg.projects_root).expanduser() if cfg.projects_root else Path.home() / ".claude" / "projects"
    )
    work_dir = Path(cfg.work_dir) if cfg.work_dir else Path(tempfile.mkdtemp(prefix="hop-chain-"))
    work_dir.mkdir(parents=True, exist_ok=True)
    started = time.time()
    outcome = execute_chain(cfg, runner_factory(cfg), projects_root, work_dir)
    print(f"elapsed: {time.time() - started:.0f}s")
    return report(outcome)


if __name__ == "__main__":
    sys.exit(main())
