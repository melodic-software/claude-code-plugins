#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Save-point engine for /session-flow:handoff: new / validate / emit.

Owns every deterministic field of a shape-2 handoff file so the model writes
only the reasoning slots. Stdlib only; Python 3.10+. Read-only on the
repository except the handoff file `new` creates (it never writes a
`.gitignore` and never rewrites an existing handoff).

Usage:
    save_point.py new --topic <slug> (--previous <file> | --no-previous)
                      [--memory-dir <root>] [--session-id <uuid>]
                      [--projects-root <dir>] [--repo-root <dir>] [--now <iso>]
    save_point.py validate <file> [--projects-root <dir>] [--strict-transcript]
    save_point.py emit <file>

Exit codes:
    new       0 written (prints the file's absolute forward-slash path)
              1 refused: root-equivalent memory dir, memory root without the
                self-ignore `.gitignore` (`*`), no session UUID / bridge-shaped
                id, predecessor unreadable or outside the handoffs dir, target
                already exists
              2 usage (neither or both of --previous / --no-previous, bad slug)
    validate  0 pass (shape 1, no `handoff_shape` key: one WARN, checks skipped)
              1 validation failure
              2 usage / unreadable / not a handoff file
              3 `handoff_shape` newer than this validator knows: read it, do
                not rewrite it
    emit      0 printed the `## Resume prompt` section body verbatim (heading
                excluded, surrounding blank lines trimmed); when the stored
                `Read @` path is not this file, a WARN goes to stderr and the
                real path is substituted on stdout only
              1 section absent (shape 1 says so) or the file still carries a
                `<!-- FILL` slot (unfinished skeleton, never emitted)
              2 usage / unreadable

Every write is UTF-8 with `\\n` newlines; stdout/stderr are reconfigured to
UTF-8 so the U+2500 rails survive a cp1252 pipe on Windows.
"""

from __future__ import annotations

import argparse
import io
import os
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

HANDOFF_SHAPE = 2

SECTIONS_14 = (
    "Original goal",
    "Resumption brief",
    "Completion criteria",
    "Constraints that must hold",
    "Environment to re-establish",
    "Side effects already applied",
    "File roles in this work",
    "Decisions already settled",
    "Approaches tried and abandoned",
    "Findings that cost effort to discover",
    "Remaining actions, in order",
    "Open questions to investigate",
    "Blockers needing an outside decision",
    "Suggested skills",
)
SECTIONS_17 = SECTIONS_14 + ("This session", "Prior sessions", "Resume prompt")
CUMULATIVE = (
    "Constraints that must hold",
    "Side effects already applied",
    "Decisions already settled",
    "Approaches tried and abandoned",
    "Findings that cost effort to discover",
)
# Reasoning-only sections rewritten every hop, with the slot instruction.
REWRITTEN = {
    "Resumption brief": (
        "brief",
        "six lines max: when written and against which branch or commit, where the work "
        "stands in one line, the single next concrete action and the section that governs "
        "it; close with the obligation to read Constraints that must hold first",
    ),
    "Completion criteria": (
        "criteria",
        "one line of why the work exists, then each criterion as an observable goal-state "
        "with a met/unmet mark and the command or diff that settles it; process milestones "
        "under a '### Process milestones' sub-heading, never as criteria",
    ),
    "Environment to re-establish": (
        "environment",
        "branch and worktree, services, env vars, background tasks, and the live TaskList "
        "with literal recreate calls, or an explicit line that there is nothing to recreate",
    ),
    "File roles in this work": (
        "file-roles",
        "one line per file: path, one role (modified / still to modify / specification to "
        "obey / reference for understanding / test that must pass / generated, do not "
        "hand-edit), why it matters, one clause of change; uncommitted edits say which part "
        "works and which does not",
    ),
    "Remaining actions, in order": (
        "remaining",
        "every action still to take, numbered and sequenced, the whole remainder not just "
        "the next step; an action waiting on a blocker is listed in place and marked waiting",
    ),
    "Open questions to investigate": (
        "open-questions",
        "unknowns this session can resolve itself, one per entry with the probe that "
        "answers it; 'None.' plus a half-line of reason when there are none",
    ),
    "Blockers needing an outside decision": (
        "blockers",
        "what is stuck, who or what unblocks it, what to do meanwhile; 'None.' plus a "
        "half-line of reason when nothing waits on someone else",
    ),
    "Suggested skills": (
        "skills",
        "fully-qualified skills (plugin:skill, 'if installed') each tied to a concrete "
        "remaining item, or 'None. Remaining work runs inline'",
    ),
}
CUMULATIVE_SLOT = {
    "Constraints that must hold": "constraints",
    "Side effects already applied": "side-effects",
    "Decisions already settled": "decisions",
    "Approaches tried and abandoned": "abandoned",
    "Findings that cost effort to discover": "findings",
}

RAIL_CHAR = "─"
RAIL = RAIL_CHAR * 58
RAIL_RE = re.compile(r"^─{10,}$")
ASCII_RAIL_RE = re.compile(r"^[-=_]{10,}$")
UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", re.IGNORECASE
)
HANDOFF_NAME_RE = re.compile(r"^\d{8}T\d{6}Z-handoff-.+\.md$")
SLUG_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
TAG_RE = re.compile(r"^\[h(\d+)\]\s*")
UNVERIFIED_PRED_RE = re.compile(r"^UNVERIFIED \(predecessor failed validation\):\s*")
BULLET_RE = re.compile(r"^(?:[-*+]|\d+[.)])\s+")
H2_RE = re.compile(r"^## (.+?)\s*$")
FILL_MARK = "<!-- FILL"
COPY_LINE = "`/clear`, then copy everything between the dashed lines:"
DIRECTIVE_CLAUSE = "invoke /session-flow:handoff via the Skill tool"
DIRECTIVE_TAIL = (
    "confirm its Original goal still governs the remaining next steps, then continue "
    "them. For the next save-point invoke /session-flow:handoff via the Skill tool; "
    "never write a handoff file free-hand."
)
PRIOR_SESSION_RE = re.compile(r"^Prior session: ([0-9A-Fa-f-]{36})\.$")
THEN_RE = re.compile(r"^Then: /[A-Za-z0-9_:.-]+$")
THIS_SESSION_RE = re.compile(r"^did: .+ · left: .+$")
NEXT_CLOSED = "Next: none (closed)"
NEXT_MAX = 5
OPENING_ASK_CAP = 15
FIRST_HOP_PRIOR = "None (first hop)."
PRIOR_HEADER = "| date | session id | transcript | did/left | file |"
PRIOR_SEPARATOR = "|---|---|---|---|---|"

# Secret-SHAPE patterns for the WARN-only scan, copied from the running-retro
# observer's ledger-write redaction hop (skills/running-retro/scripts/observer.py,
# `_REDACTIONS`), minus its email pattern: a bare ssh account (`git@github.com`)
# in every `Handoff origin:` line matches it, and this scan is for secrets, not
# PII. Same plugin, so a copy rather than an import: the observer is a script
# with module-level side effects, not a library.
SECRET_SHAPES: tuple[tuple[re.Pattern[str], str], ...] = (
    (re.compile(r"-----BEGIN[^-]+PRIVATE KEY-----"), "private key"),
    (re.compile(r"\b(?:sk|rk|pk)-[A-Za-z0-9_-]{16,}"), "API key"),
    (re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}"), "GitHub token"),
    (re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}"), "Slack token"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "AWS key id"),
    (
        re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"),
        "JWT",
    ),
    (
        re.compile(
            r"(?i)\b(?:bearer|token|api[_-]?key|secret|password|passwd|pwd)"
            r"['\"]?\s*[:=]\s*['\"]?[A-Za-z0-9._+/=-]{8,}"
        ),
        "secret",
    ),
    (
        re.compile(r"\b[a-z][a-z0-9+.-]*://[^\s:@/]+:[^\s:@/]+@[^\s]+"),
        "connection string",
    ),
)


# --- I/O ----------------------------------------------------------------------


def _utf8_streams() -> None:
    for stream in (sys.stdout, sys.stderr):
        if isinstance(stream, io.TextIOWrapper):
            stream.reconfigure(encoding="utf-8", newline="\n")


def _die(code: int, message: str) -> int:
    print(f"error: {message}", file=sys.stderr)
    return code


def _read_lines(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    return [line.rstrip("\r\n") for line in text.splitlines()]


def _posix(path: Path) -> str:
    return path.resolve().as_posix()


def _same_file(a: str, b: Path) -> bool:
    return os.path.normcase(os.path.realpath(a)) == os.path.normcase(os.path.realpath(b))


# --- Document model -------------------------------------------------------------


@dataclass
class Doc:
    path: Path
    lines: list[str]
    frontmatter: dict[str, str] = field(default_factory=dict)
    chain: list[str] = field(default_factory=list)
    has_frontmatter: bool = False
    body_start: int = 0
    sections: list[tuple[str, int, int]] = field(default_factory=list)

    @property
    def basename(self) -> str:
        return self.path.name

    @property
    def shape(self) -> int | None:
        """None when the key is absent (shape 1); the int otherwise; -1 when unparsable."""
        raw = self.frontmatter.get("handoff_shape")
        if raw is None:
            return None
        try:
            return int(raw)
        except ValueError:
            return -1

    @property
    def titles(self) -> list[str]:
        return [title for title, _, _ in self.sections]

    def section(self, title: str) -> list[str] | None:
        for name, start, end in self.sections:
            if name == title:
                return self.lines[start + 1 : end]
        return None

    def section_start(self, title: str) -> int:
        for name, start, _ in self.sections:
            if name == title:
                return start
        return -1


def _fm_value(raw: str) -> str:
    value = raw.strip()
    value = value.split(" #", 1)[0].strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        value = value[1:-1]
    return value


def parse_doc(path: Path) -> Doc:
    doc = Doc(path=path, lines=_read_lines(path))
    lines = doc.lines
    idx = 0
    if lines and lines[0].strip() == "---":
        idx = 1
        while idx < len(lines) and lines[idx].strip() != "---":
            line = lines[idx]
            if line.startswith("chain:"):
                inline = line[len("chain:") :].strip()
                if inline.startswith("[") and inline.endswith("]"):
                    doc.chain = [
                        _fm_value(item) for item in inline[1:-1].split(",") if item.strip()
                    ]
                idx += 1
                while idx < len(lines) and re.match(r"^\s+-\s+", lines[idx]):
                    doc.chain.append(_fm_value(re.sub(r"^\s+-\s+", "", lines[idx])))
                    idx += 1
                continue
            if ":" in line and not line.startswith((" ", "\t")):
                key, raw = line.split(":", 1)
                doc.frontmatter[key.strip()] = _fm_value(raw)
            idx += 1
        if idx < len(lines):
            doc.has_frontmatter = True
            idx += 1
    doc.body_start = idx
    heads = [(m.group(1), i) for i in range(idx, len(lines)) if (m := H2_RE.match(lines[i]))]
    for n, (title, start) in enumerate(heads):
        end = heads[n + 1][1] if n + 1 < len(heads) else len(lines)
        doc.sections.append((title, start, end))
    return doc


def _trim_blank(lines: list[str]) -> list[str]:
    start, end = 0, len(lines)
    while start < end and not lines[start].strip():
        start += 1
    while end > start and not lines[end - 1].strip():
        end -= 1
    return lines[start:end]


# --- Cumulative-section entries ---------------------------------------------------


@dataclass
class Entry:
    first_index: int  # index into the section body
    lines: list[str]  # raw lines, first line still carries its bullet marker
    superseded: bool

    @property
    def marker(self) -> str:
        m = BULLET_RE.match(self.lines[0])
        return m.group(0) if m else ""

    @property
    def text(self) -> str:
        first = self.lines[0][len(self.marker) :]
        parts = [first] + [line.strip() for line in self.lines[1:]]
        return " ".join(part for part in parts if part).strip()

    @property
    def tag(self) -> int | None:
        m = TAG_RE.match(self.text)
        return int(m.group(1)) if m else None

    @property
    def exempt(self) -> bool:
        return self.text.startswith(("None.", "None (")) or self.text == ""

    @property
    def normalized(self) -> str:
        text = TAG_RE.sub("", self.text)
        text = UNVERIFIED_PRED_RE.sub("", text)
        return " ".join(text.split())


def parse_entries(body: list[str]) -> list[Entry]:
    """Entries are top-level bullets (with indented continuation lines) or
    paragraphs. A `Superseded:` marker line flips every later entry to
    superseded; the marker itself is not an entry."""
    entries: list[Entry] = []
    current: Entry | None = None
    superseded = False
    paragraph = False
    for i, line in enumerate(body):
        if not line.strip():
            current = None
            paragraph = False
            continue
        stripped = line.strip()
        if stripped.startswith("Superseded:") and not line.startswith((" ", "\t")):
            superseded = True
            current = None
            rest = stripped[len("Superseded:") :].strip()
            if rest and rest != "None.":
                current = Entry(i, [rest], superseded=True)
                entries.append(current)
                paragraph = True
            continue
        if stripped.startswith("<!--"):
            current = None
            paragraph = False
            continue
        if BULLET_RE.match(line):
            current = Entry(i, [line], superseded)
            entries.append(current)
            paragraph = False
            continue
        if line.startswith((" ", "\t")) and current is not None:
            current.lines.append(line)
            continue
        if paragraph and current is not None:
            current.lines.append(line)
            continue
        current = Entry(i, [line], superseded)
        entries.append(current)
        paragraph = True
    return entries


# --- Findings -------------------------------------------------------------------


class Findings:
    def __init__(self) -> None:
        self.items: list[tuple[str, str]] = []

    def warn(self, message: str) -> None:
        self.items.append(("WARN", message))

    def fail(self, message: str) -> None:
        self.items.append(("FAIL", message))

    @property
    def failed(self) -> bool:
        return any(level == "FAIL" for level, _ in self.items)

    @property
    def first_fail(self) -> str:
        return next((msg for level, msg in self.items if level == "FAIL"), "")


# --- validate -------------------------------------------------------------------


def _parse_prior_rows(body: list[str] | None) -> list[str]:
    if body is None:
        return []
    rows = [line.rstrip() for line in body if line.lstrip().startswith("|")]
    data: list[str] = []
    for row in rows:
        cells = _cells(row)
        if not data and cells and cells[0] == "date":
            continue
        if cells and all(re.fullmatch(r"-+", c) for c in cells):
            continue
        data.append(row.strip())
    return data


def _cells(row: str) -> list[str]:
    parts = [c.strip() for c in row.strip().split("|")]
    if parts and parts[0] == "":
        parts = parts[1:]
    if parts and parts[-1] == "":
        parts = parts[:-1]
    return parts


def _resolve_transcript(session_id: str, projects_root: Path) -> str:
    matches = sorted(projects_root.glob(f"*/{session_id}.jsonl"))
    for match in matches:
        if match.is_file():
            os.stat(match)
            return match.resolve().as_posix()
    return f"unresolved (session {session_id}, projects-root {projects_root.as_posix()})"


def _check_rails_block(doc: Doc, f: Findings, session_id: str) -> None:
    body = doc.section("Resume prompt")
    if body is None:
        return
    rails = [i for i, line in enumerate(body) if RAIL_RE.match(line.strip())]
    ascii_rails = [i for i, line in enumerate(body) if ASCII_RAIL_RE.match(line.strip())]
    if len(rails) != 2:
        detail = f"found {len(rails)}"
        if ascii_rails:
            detail += f", plus {len(ascii_rails)} ASCII rail line(s); rails are U+2500 only"
        f.fail(f"Resume prompt: exactly two U+2500 rails required ({detail})")
        return
    top, bottom = rails
    if not any(line.strip() == COPY_LINE for line in body[:top]):
        f.fail(f"Resume prompt: copy instruction line {COPY_LINE!r} missing above the top rail")
    between = body[top + 1 : bottom]
    if any(not line.strip() for line in between):
        f.fail("Resume prompt: blank line between the rails")
    between = [line for line in between if line.strip()]
    pos = 0
    if between and between[0].startswith("/goal "):
        pos = 1
    if pos >= len(between) or not between[pos].startswith("Read @"):
        f.fail("Resume prompt: first line between the rails (after an optional /goal) must be the 'Read @' directive")
        return
    directive = between[pos]
    path_part = directive[len("Read @") :].split(",", 1)[0].strip()
    if "\\" in path_part or not (path_part.startswith("/") or re.match(r"^[A-Za-z]:/", path_part)):
        f.fail(f"Resume prompt: 'Read @' path must be absolute and forward-slash (got {path_part!r})")
    elif not _same_file(path_part, doc.path):
        f.fail(f"Resume prompt: 'Read @' path {path_part!r} does not name this file ({_posix(doc.path)})")
    if DIRECTIVE_CLAUSE not in directive:
        f.fail(f"Resume prompt: directive lacks the clause {DIRECTIVE_CLAUSE!r}")
    pos += 1
    if pos >= len(between) or not (m := PRIOR_SESSION_RE.match(between[pos])):
        f.fail("Resume prompt: 'Prior session: <UUID>.' line missing after the directive")
        return
    if m.group(1).lower() != session_id.lower():
        f.fail(f"Resume prompt: 'Prior session:' {m.group(1)} differs from session_id {session_id}")
    pos += 1
    if pos >= len(between) or not between[pos].startswith("Handoff origin: "):
        f.fail("Resume prompt: 'Handoff origin:' line missing after 'Prior session:'")
        return
    try:
        slots = shlex.split(between[pos][len("Handoff origin: ") :], posix=True)
    except ValueError:
        slots = []
    if len(slots) != 2:
        f.fail(f"Resume prompt: 'Handoff origin:' must carry exactly two slots (found {len(slots)})")
    pos += 1
    if pos >= len(between) or not between[pos].startswith("Next:"):
        f.fail("Resume prompt: 'Next:' line missing after 'Handoff origin:'")
        return
    next_line = between[pos]
    headlines = between[pos + 1 :]
    if next_line == NEXT_CLOSED:
        if headlines:
            f.fail(f"Resume prompt: {NEXT_CLOSED!r} admits no headline lines (found {len(headlines)})")
    elif next_line.strip() != "Next:":
        f.fail(f"Resume prompt: 'Next:' must be bare or exactly {NEXT_CLOSED!r} (got {next_line!r})")
    else:
        if not headlines:
            f.fail("Resume prompt: 'Next:' needs 1 to 5 headline lines")
        if len(headlines) > NEXT_MAX:
            f.fail(f"Resume prompt: 'Next:' has {len(headlines)} headline lines (max {NEXT_MAX})")
        thens = [i for i, line in enumerate(headlines) if line.startswith("Then:")]
        if len(thens) > 1:
            f.fail("Resume prompt: at most one 'Then: /<skill>' line")
        elif thens and thens[0] != len(headlines) - 1:
            f.fail("Resume prompt: 'Then: /<skill>' must be the last line between the rails")
        for i in thens:
            if not THEN_RE.match(headlines[i]):
                f.fail(f"Resume prompt: 'Then:' must name exactly one skill as /<skill> (got {headlines[i]!r})")
    resume_line = f"claude --resume {session_id}"
    if not any(resume_line in line for line in body[bottom + 1 :]):
        f.fail(f"Resume prompt: below-rail line carrying {resume_line!r} missing")


def _check_original_goal(doc: Doc, f: Findings, hop: int) -> None:
    body = doc.section("Original goal")
    if body is None:
        return
    ask_idx = next((i for i, line in enumerate(body) if line.startswith("Opening ask:")), None)
    if ask_idx is None:
        f.fail("Original goal: 'Opening ask:' line missing")
    goal_lines: list[str] = []
    skip = False
    for line in body:
        if line.startswith("Opening ask:") or line.startswith("**Next action serves it by:**"):
            skip = True
            continue
        if skip:
            if not line.strip():
                skip = False
            continue
        if line.startswith("**Amended:**") or line.startswith("**Goal"):
            continue
        if line.strip():
            goal_lines.append(line.strip())
    first = goal_lines[0].lstrip("> ").strip() if goal_lines else ""
    if not first or first.startswith("None.") or first.lower() in {"tbd", "todo", "n/a"}:
        f.fail("Original goal: the goal quote is empty or 'None.'; work with no statable goal is a defect to raise with the user, not a box to tick")
    if ask_idx is not None and hop == 1:
        block = 0
        for line in body[ask_idx + 1 :]:
            if not line.strip():
                break
            block += 1
        inline = body[ask_idx][len("Opening ask:") :].strip()
        if inline and not inline.startswith("see "):
            block += 1
        if block > OPENING_ASK_CAP:
            f.warn(f"Original goal: 'Opening ask:' runs {block} lines (cap {OPENING_ASK_CAP}); the transcript is the full source")


def _check_cumulative(doc: Doc, f: Findings, hop: int, pred: Doc | None, pred_soft: bool) -> None:
    for title in CUMULATIVE:
        body = doc.section(title)
        if body is None:
            continue
        entries = parse_entries(body)
        for entry in entries:
            if entry.exempt:
                continue
            tag = entry.tag
            if tag is None:
                f.fail(f"{title}: entry without an [hN] provenance tag: {entry.text[:60]!r}")
            elif not 1 <= tag <= hop:
                f.fail(f"{title}: tag [h{tag}] out of range 1..{hop}: {entry.text[:60]!r}")
        if pred is None:
            continue
        pred_body = pred.section(title)
        if pred_body is None:
            continue
        have = {entry.normalized for entry in entries}
        for entry in parse_entries(pred_body):
            if entry.exempt:
                continue
            if entry.normalized not in have:
                message = (
                    f"{title}: predecessor entry dropped (keep it in place or under "
                    f"'Superseded:', never delete): {entry.text[:60]!r}"
                )
                if pred_soft:
                    f.warn(message)
                else:
                    f.fail(message)


def _goal_block(doc: Doc) -> list[str]:
    body = doc.section("Original goal") or []
    out: list[str] = []
    for line in body:
        if line.startswith("**Amended:**") or line.startswith("Opening ask:"):
            break
        if line.strip():
            out.append(line.rstrip())
    return out


def validate_doc(
    doc: Doc,
    projects_root: Path | None,
    strict_transcript: bool,
    shallow: bool = False,
) -> tuple[Findings, int]:
    """Return findings plus the exit code (0/1/3). `shallow` skips the
    predecessor walk (used when a successor validates its own predecessor)."""
    f = Findings()
    fm = doc.frontmatter
    shape = doc.shape
    if shape is None or shape == 1:
        f.warn("shape 1 file (no handoff_shape key): shape checks skipped, rails still emitted by the caller, file never rewritten")
        return f, 0
    if shape == -1:
        f.fail(f"handoff_shape {fm.get('handoff_shape')!r} is not an integer")
        return f, 1
    if shape > HANDOFF_SHAPE:
        f.fail(f"handoff_shape {shape} is newer than this validator knows ({HANDOFF_SHAPE}): read it, do not rewrite it")
        return f, 3

    for key in ("type", "date", "topic", "session_id", "transcript"):
        if not fm.get(key):
            f.fail(f"frontmatter: required key {key!r} missing")
    if fm.get("type") and fm["type"] != "handoff":
        f.fail(f"frontmatter: type must be 'handoff' (got {fm['type']!r})")
    if fm.get("date") and not DATE_RE.match(fm["date"]):
        f.fail(f"frontmatter: date must be ISO-8601 UTC 'YYYY-MM-DDTHH:MM:SSZ' (got {fm['date']!r})")
    session_id = fm.get("session_id", "")
    if session_id and not UUID_RE.match(session_id):
        f.fail(f"frontmatter: session_id {session_id!r} is not a UUID (bridge ids and 'unknown' are refused)")

    previous = fm.get("previous_handoff")
    pred: Doc | None = None
    pred_soft = False
    if previous is not None:
        if not HANDOFF_NAME_RE.match(previous):
            f.fail(f"frontmatter: previous_handoff must be a bare filename matching <TS>-handoff-<topic>.md (got {previous!r})")
        else:
            pred_path = doc.path.parent / previous
            if not pred_path.is_file():
                f.fail(f"frontmatter: previous_handoff {previous!r} not found beside this file")
            elif not shallow:
                try:
                    pred = parse_doc(pred_path)
                except (OSError, UnicodeDecodeError) as exc:
                    f.fail(f"predecessor {previous!r} unreadable: {exc}")
                    pred = None
    if not doc.chain:
        f.fail("frontmatter: chain is missing or empty")
    else:
        if doc.chain[-1] != doc.basename:
            f.fail(f"frontmatter: chain[-1] must be this file's basename {doc.basename!r} (got {doc.chain[-1]!r})")
        if previous is not None:
            if len(doc.chain) < 2 or doc.chain[-2] != previous:
                f.fail(f"frontmatter: chain[-2] must equal previous_handoff {previous!r}")
        elif len(doc.chain) != 1:
            f.fail("frontmatter: a first hop (no previous_handoff) carries a one-entry chain")
    hop = max(len(doc.chain), 1)

    if pred is not None:
        if pred.shape not in (None, 1):
            pred_findings, pred_code = validate_doc(pred, projects_root, False, shallow=True)
            if pred_code != 0:
                pred_soft = True
                f.warn(f"predecessor {previous!r} failed validation ({pred_findings.first_fail}); predecessor-derived checks downgraded to WARN")
            expected_chain = pred.chain + [doc.basename]
            if doc.chain != expected_chain:
                message = f"frontmatter: chain must be the predecessor's chain plus this file ({expected_chain})"
                (f.warn if pred_soft else f.fail)(message)
        else:
            if doc.chain != [previous, doc.basename]:
                f.fail(f"frontmatter: a shape-1 predecessor gives chain [{previous!r}, {doc.basename!r}]")

    titles = doc.titles
    if titles != list(SECTIONS_17):
        for i, expected in enumerate(SECTIONS_17):
            found = titles[i] if i < len(titles) else "<missing>"
            if found != expected:
                f.fail(f"headings: expected '## {expected}' at position {i + 1}, found '## {found}' (17 sections in order, '## Resume prompt' last)")
                break
        else:
            f.fail(f"headings: extra section(s) after '## Resume prompt': {titles[len(SECTIONS_17):]}")

    for i, line in enumerate(doc.lines, 1):
        if FILL_MARK in line:
            f.fail(f"line {i}: leftover {FILL_MARK} slot; fill it or delete it")
            break

    _check_original_goal(doc, f, hop)
    _check_cumulative(doc, f, hop, pred, pred_soft)

    this = doc.section("This session")
    if this is not None:
        content = [line for line in this if line.strip()]
        if len(content) != 1:
            f.fail(f"This session: exactly one line 'did: … · left: …' required (found {len(content)})")
        else:
            line = content[0].strip()
            if "|" in line:
                f.fail("This session: '|' is not allowed (the line becomes a table cell downstream)")
            if not THIS_SESSION_RE.match(line):
                f.fail(f"This session: line must read 'did: … · left: …' (got {line[:60]!r})")

    prior = doc.section("Prior sessions")
    if prior is not None:
        rows = _parse_prior_rows(prior)
        if previous is None:
            if "\n".join(_trim_blank(prior)).strip() != FIRST_HOP_PRIOR:
                f.fail(f"Prior sessions: a first hop reads exactly {FIRST_HOP_PRIOR!r}")
        else:
            bad = [row for row in rows if len(_cells(row)) != 5]
            if bad:
                f.fail(f"Prior sessions: every row carries 5 cells (date · session id · transcript · did/left · file): {bad[0][:60]!r}")
            pred_rows = _parse_prior_rows(pred.section("Prior sessions")) if pred is not None else []
            if pred is not None:
                report = f.warn if pred_soft else f.fail
                if rows[: len(pred_rows)] != pred_rows:
                    report("Prior sessions: the predecessor's rows must be copied verbatim as a prefix")
                if len(rows) != len(pred_rows) + 1:
                    report(f"Prior sessions: this file adds exactly one row (predecessor had {len(pred_rows)}, this file has {len(rows)})")
                elif rows:
                    cells = _cells(rows[-1])
                    if len(cells) == 5 and (cells[1].lower() != pred.frontmatter.get("session_id", "").lower() or cells[4] != previous):
                        report(f"Prior sessions: the added row must describe the predecessor ({pred.frontmatter.get('session_id')} · {previous})")
            elif not rows:
                f.fail("Prior sessions: at least one row required after hop 1")

    if pred is not None and pred.section("Original goal") is not None:
        pred_goal = _goal_block(pred)
        own_goal = _goal_block(doc)
        if pred_goal and pred_goal != own_goal[: len(pred_goal)]:
            f.warn("Original goal: the goal quote differs from the predecessor's (copied off disk, never restated; amendments are appended with the prior goal kept above)")

    if session_id:
        _check_rails_block(doc, f, session_id)

    transcript = fm.get("transcript", "")
    if transcript:
        if transcript.startswith("unresolved ("):
            located = ""
            if projects_root is not None and session_id and UUID_RE.match(session_id):
                found = _resolve_transcript(session_id, projects_root)
                if not found.startswith("unresolved ("):
                    located = f"; present now at {found} (the file still says unresolved)"
            if strict_transcript:
                f.fail(f"transcript: {transcript}{located} (--strict-transcript)")
            else:
                f.warn(f"transcript: {transcript}{located}")
        elif not Path(transcript).is_file():
            f.fail(f"transcript: stated path does not exist: {transcript}")

    for i, line in enumerate(doc.lines, 1):
        for pattern, marker in SECRET_SHAPES:
            if pattern.search(line):
                f.warn(f"line {i}: secret-shaped string ({marker}); redact to a shape marker or rule it benign")
                break

    return f, 1 if f.failed else 0


def cmd_validate(args: argparse.Namespace) -> int:
    path = Path(args.file)
    if not path.is_file():
        return _die(2, f"not a file: {path}")
    try:
        doc = parse_doc(path)
    except (OSError, UnicodeDecodeError) as exc:
        return _die(2, f"cannot read {path}: {exc}")
    if not doc.has_frontmatter or doc.frontmatter.get("type") != "handoff":
        return _die(2, f"not a handoff file (no 'type: handoff' frontmatter): {path}")
    projects_root = Path(args.projects_root).expanduser() if args.projects_root else None
    findings, code = validate_doc(doc, projects_root, args.strict_transcript)
    for level, message in findings.items:
        print(f"{level}: {message}")
    if code == 3:
        label = "UNSUPPORTED-SHAPE"
    else:
        label = "FAIL" if code != 0 else ("WARN" if findings.items else "PASS")
    count = f" ({len(findings.items)})" if findings.items else ""
    print(f"validate: {label}{count} {_posix(path)}")
    return code


# --- emit -------------------------------------------------------------------------


def cmd_emit(args: argparse.Namespace) -> int:
    path = Path(args.file)
    if not path.is_file():
        return _die(2, f"not a file: {path}")
    try:
        doc = parse_doc(path)
    except (OSError, UnicodeDecodeError) as exc:
        return _die(2, f"cannot read {path}: {exc}")
    if not doc.has_frontmatter or doc.frontmatter.get("type") != "handoff":
        return _die(2, f"not a handoff file (no 'type: handoff' frontmatter): {path}")
    if any(FILL_MARK in line for line in doc.lines):
        return _die(1, f"unfinished skeleton (a {FILL_MARK} slot remains); never emitted: {_posix(path)}")
    body = doc.section("Resume prompt")
    if body is None:
        if doc.shape in (None, 1):
            return _die(1, f"shape 1 handoff has no '## Resume prompt' section (legacy file, never rewritten): {_posix(path)}")
        return _die(1, f"'## Resume prompt' section absent: {_posix(path)}")
    real = _posix(path)
    out: list[str] = []
    for line in _trim_blank(body):
        if line.startswith("Read @"):
            stored = line[len("Read @") :].split(",", 1)[0].strip()
            if not _same_file(stored, path):
                print(f"WARN: stored 'Read @' path {stored} is not this file; substituting {real} on stdout only (file untouched)", file=sys.stderr)
                line = "Read @" + real + line[len("Read @") + len(stored) :]
        out.append(line)
    sys.stdout.write("\n".join(out) + "\n")
    return 0


# --- new --------------------------------------------------------------------------


def _git_toplevel(start: Path) -> Path | None:
    probe = start
    while not probe.exists() and probe.parent != probe:
        probe = probe.parent
    try:
        result = subprocess.run(
            ["git", "-C", str(probe), "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return None
    if result.returncode != 0 or not result.stdout.strip():
        return None
    return Path(result.stdout.strip()).resolve()


def _git_origin(repo_root: Path) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(repo_root), "remote", "get-url", "origin"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return None
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


def origin_identity(remote_url: str | None, fallback: str) -> str:
    """The remote URL with credential userinfo stripped; the root directory
    name when there is no remote, the form is SCP-style / unknown, or the
    userinfo boundary is ambiguous. A bare `git@` ssh account is kept."""
    if not remote_url:
        return fallback
    m = re.match(r"^([A-Za-z][A-Za-z0-9+.-]*)://([^/]*)(/.*)?$", remote_url)
    if not m:
        return fallback
    scheme, authority, rest = m.group(1), m.group(2), m.group(3) or ""
    if authority.count("@") > 1:
        return fallback
    if "@" in authority:
        userinfo, host = authority.rsplit("@", 1)
        if not (scheme in ("ssh", "git+ssh", "ssh+git") and userinfo == "git"):
            authority = host
    return f"{scheme}://{authority}{rest}"


def _slot(value: str) -> str:
    return f'"{value}"' if re.search(r"\s", value) else value


def _fill(name: str, instruction: str) -> str:
    return f"<!-- FILL: {name} — {instruction} -->"


def _tag_carried(body: list[str], default_hop: int, unverified: bool) -> list[str]:
    """Carry a predecessor's cumulative section forward verbatim, tagging
    untagged entries `[h<default_hop>]` and, for a predecessor that failed
    validation, marking every entry UNVERIFIED."""
    lines = list(_trim_blank(body))
    for entry in parse_entries(body):
        if entry.exempt:
            continue
        idx = _shift_index(body, entry.first_index)
        line = lines[idx]
        if line.strip().startswith("Superseded:"):
            # Inline text after the marker is an entry, but the marker line
            # itself must stay a marker; tagging it would turn it into one.
            continue
        marker = entry.marker
        rest = line[len(marker) :]
        m = TAG_RE.match(rest)
        tag = m.group(0).rstrip() if m else f"[h{default_hop}]"
        rest = rest[len(m.group(0)) :] if m else rest
        if unverified and not UNVERIFIED_PRED_RE.match(rest):
            rest = "UNVERIFIED (predecessor failed validation): " + rest
        lines[idx] = f"{marker}{tag} {rest}"
    return lines


def _shift_index(body: list[str], index: int) -> int:
    leading = 0
    while leading < len(body) and not body[leading].strip():
        leading += 1
    return index - leading


def _first_line(body: list[str] | None) -> str:
    for line in body or []:
        if line.strip():
            return line.strip().replace("|", "/")
    return "no Resumption brief section"


def build_skeleton(
    *,
    slug: str,
    session_id: str,
    date: str,
    transcript: str,
    target: Path,
    pred: Doc | None,
    pred_failed: bool,
    origin: str,
    origin_path: str,
    pred_transcript: str,
) -> str:
    previous = pred.basename if pred is not None else None
    if pred is None:
        chain = [target.name]
    elif pred.shape in (None, 1):
        chain = [pred.basename, target.name]
    else:
        chain = pred.chain + [target.name]
    hop = len(chain)
    pred_hop = hop - 1

    fm = [
        "---",
        "type: handoff",
        f"handoff_shape: {HANDOFF_SHAPE}",
        f"date: {date}",
        f"topic: {slug}",
        f"session_id: {session_id}",
        f"transcript: {transcript}",
    ]
    if previous is not None:
        fm.append(f"previous_handoff: {previous}")
    fm.append("chain:")
    fm.extend(f"  - {item}" for item in chain)
    fm.append("---")

    body: list[str] = []

    def section(title: str, lines: list[str]) -> None:
        body.append("")
        body.append(f"## {title}")
        body.append("")
        body.extend(_trim_blank(lines))

    # 1. Original goal
    goal: list[str] = []
    pred_goal = pred.section("Original goal") if pred is not None else None
    if pred_goal is None:
        if pred is None:
            goal += [
                "**Goal (verbatim):**",
                _fill("goal", "the user's goal statement quoted as they wrote it, with the date they stated it; RECONSTRUCTED (and settled with the user) when it was never put in one sentence"),
                "",
                "**Amended:** " + _fill("amended", "'None.' until the goal changes; otherwise a new dated verbatim quote with the prior goal kept above it"),
                "",
                "Opening ask:",
                _fill("opening-ask", f"the user's opening message this session, verbatim and redacted, at most {OPENING_ASK_CAP} lines, no bullets; the transcript is the full source"),
            ]
        else:
            goal += [
                _fill("goal", "RECONSTRUCTED from the transcript; settle with the user (the shape-1 predecessor recorded no Original goal)"),
                "",
                "**Amended:** " + _fill("amended", "'None.' until the goal changes; otherwise a new dated verbatim quote with the prior goal kept above it"),
                "",
                f"Opening ask: see {chain[0]} § Original goal (shape-1 root, no verbatim ask recorded)",
            ]
    else:
        kept: list[str] = []
        skip = False
        for line in pred_goal:
            if line.startswith("Opening ask:") or line.startswith("**Next action serves it by:**"):
                skip = True
                continue
            if skip:
                if not line.strip():
                    skip = False
                continue
            kept.append(line.rstrip())
        goal += _trim_blank(kept)
        goal.append("")
        pointer = f"Opening ask: see {chain[0]} § Original goal"
        if pred is not None and pred.shape in (None, 1):
            pointer += " (shape-1 root, no verbatim ask recorded)"
        goal.append(pointer)
    goal.append("")
    goal.append("**Next action serves it by:** " + _fill("drift-check", "one sentence tying the first remaining action back to the goal; cannot state it → that is drift, say so and route it"))
    section("Original goal", goal)

    # 2..14
    for title in SECTIONS_14[1:]:
        if title in CUMULATIVE:
            name = CUMULATIVE_SLOT[title]
            lines: list[str] = []
            if pred is None:
                lines.append(_fill(name, "one [h1]-tagged entry per line ('- [h1] …'), continuation lines indented; 'None.' plus a half-line of reason when nothing applies"))
            else:
                pred_body = pred.section(title)
                if pred_body is None:
                    lines.append(f"None. (shape-1 predecessor had no {title})")
                else:
                    lines.extend(_tag_carried(pred_body, pred_hop, pred_failed))
                lines.append("")
                lines.append(_fill(f"{name}-new", f"optional: append new [h{hop}] entries below the carried ones, move disproved ones under a 'Superseded:' line (never delete), re-tag re-verified ones [h{hop}]; delete this line when nothing changes"))
            section(title, lines)
        else:
            name, instruction = REWRITTEN[title]
            section(title, [_fill(name, instruction)])

    # This session
    section(
        "This session",
        [
            "did: " + _fill("did", "what landed this session, past tense, no '|'")
            + " · left: " + _fill("left", "what is still open, past tense, no 'next', no '|'"),
        ],
    )

    # Prior sessions
    if pred is None:
        section("Prior sessions", [FIRST_HOP_PRIOR])
    else:
        rows = _parse_prior_rows(pred.section("Prior sessions"))
        if pred.shape in (None, 1):
            did_left = f"UNVERIFIED (shape-1 predecessor; brief: {_first_line(pred.section('Resumption brief'))})"
        else:
            this = [line for line in (pred.section("This session") or []) if line.strip()]
            did_left = this[0].strip() if this else "UNVERIFIED (predecessor had no This session line)"
        own_row = (
            f"| {pred.frontmatter.get('date', 'unknown')} | {pred.frontmatter.get('session_id', 'unknown')} "
            f"| {pred_transcript} | {did_left} | {pred.basename} |"
        )
        section("Prior sessions", [PRIOR_HEADER, PRIOR_SEPARATOR, *rows, own_row])

    # Resume prompt
    read_path = _posix(target)
    section(
        "Resume prompt",
        [
            COPY_LINE,
            "",
            RAIL,
            _fill("goal-rearm", "optional: when a /goal is active this session, replace this line with '/goal <condition>' as the FIRST line between the rails; otherwise delete this line"),
            f"Read @{read_path}, {DIRECTIVE_TAIL}",
            f"Prior session: {session_id}.",
            f"Handoff origin: {_slot(origin)} {_slot(origin_path)}",
            "Next:",
            _fill("next", f"1 to {NEXT_MAX} plain headline lines replacing this line, one per line, no bullets, no blank lines; the last may be 'Then: /<one skill>' at a stage boundary; for a closing handoff write '{NEXT_CLOSED}' on the line above and delete this one"),
            RAIL,
            "",
            f"Or reopen the producing session in place: `claude --resume {session_id}`.",
            _fill("below-rail", "optional: the /goal and /loop re-arm notes save-point.md prescribes below the bottom rail; delete this line when none applies"),
        ],
    )

    return "\n".join(fm + body) + "\n"


def cmd_new(args: argparse.Namespace) -> int:
    slug = args.topic
    if not SLUG_RE.match(slug):
        return _die(2, f"topic slug {slug!r} must match {SLUG_RE.pattern}")

    session_id = args.session_id or os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    if not session_id:
        return _die(1, "no session UUID available (CLAUDE_CODE_SESSION_ID unset and --session-id not given); take the prompt-only path with the reason stated")
    if not UUID_RE.match(session_id):
        return _die(1, f"session id {session_id!r} is not a UUID (bridge ids such as cse_… are refused; never read CLAUDE_CODE_BRIDGE_SESSION_ID); take the prompt-only path")
    session_id = session_id.lower()

    memory_dir = Path(args.memory_dir or ".work").expanduser().resolve()
    repo_root = Path(args.repo_root).expanduser().resolve() if args.repo_root else _git_toplevel(memory_dir)
    if repo_root is not None and (memory_dir == repo_root or repo_root not in memory_dir.parents):
        return _die(1, f"Invalid memory_dir: {memory_dir.as_posix()} must resolve to a dedicated directory below the repository root {repo_root.as_posix()}")
    # The self-ignore guard holds on every memory root, inside a repository or
    # not (the no-project-root branch under the plugin data dir included).
    guard = memory_dir / ".gitignore"
    try:
        guarded = guard.is_file() and any(line.strip() == "*" for line in _read_lines(guard))
    except (OSError, UnicodeDecodeError):
        guarded = False
    if not guarded:
        return _die(1, f"memory root {memory_dir.as_posix()} lacks the self-ignore guard: create {guard.as_posix()} containing the single line '*' (the skill's guard step: printf '*\\n' >> {guard.as_posix()}), then re-run; this script never writes it")

    handoffs = memory_dir / "handoffs"
    now = _parse_now(args.now)
    if now is None:
        return _die(2, f"--now must be ISO-8601 UTC (got {args.now!r})")
    stamp = now.strftime("%Y%m%dT%H%M%SZ")
    date = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    target = handoffs / f"{stamp}-handoff-{slug}.md"
    if target.exists():
        return _die(1, f"target already exists, never overwritten: {_posix(target)}")

    projects_root = Path(args.projects_root).expanduser() if args.projects_root else Path.home() / ".claude" / "projects"
    transcript = _resolve_transcript(session_id, projects_root)

    pred: Doc | None = None
    pred_failed = False
    pred_transcript = ""
    if args.previous:
        pred_path = Path(args.previous).expanduser()
        if not pred_path.is_file():
            return _die(1, f"predecessor not found: {pred_path}")
        try:
            pred = parse_doc(pred_path)
        except (OSError, UnicodeDecodeError) as exc:
            return _die(1, f"predecessor unreadable: {exc}")
        if not pred.has_frontmatter or pred.frontmatter.get("type") != "handoff":
            return _die(1, f"predecessor is not a handoff file (no 'type: handoff' frontmatter): {pred_path}")
        if os.path.normcase(os.path.realpath(pred_path.parent)) != os.path.normcase(os.path.realpath(handoffs)):
            return _die(1, f"predecessor must live in the handoffs dir the new file is written to ({handoffs.as_posix()}); got {_posix(pred_path)}")
        if pred.shape is not None and pred.shape > HANDOFF_SHAPE:
            return _die(1, f"predecessor carries handoff_shape {pred.shape}, newer than this script knows ({HANDOFF_SHAPE}): read it, do not build on it")
        if pred.shape not in (None, 1):
            _, code = validate_doc(pred, projects_root, False, shallow=True)
            pred_failed = code != 0
            pred_transcript = pred.frontmatter.get("transcript") or "unresolved (predecessor recorded none)"
        else:
            pred_transcript = _resolve_transcript(pred.frontmatter.get("session_id", ""), projects_root) if UUID_RE.match(pred.frontmatter.get("session_id", "")) else "unresolved (shape-1 predecessor; no session UUID)"

    if repo_root is not None:
        origin = origin_identity(_git_origin(repo_root), repo_root.name)
        try:
            origin_path = target.resolve().relative_to(repo_root).as_posix()
        except ValueError:
            origin_path = _posix(target)
    else:
        origin = memory_dir.parent.name or memory_dir.name
        origin_path = _posix(target)

    content = build_skeleton(
        slug=slug,
        session_id=session_id,
        date=date,
        transcript=transcript,
        target=target,
        pred=pred,
        pred_failed=pred_failed,
        origin=origin,
        origin_path=origin_path,
        pred_transcript=pred_transcript,
    )
    handoffs.mkdir(parents=True, exist_ok=True)
    with target.open("x", encoding="utf-8", newline="\n") as fh:
        fh.write(content)
    print(_posix(target))
    return 0


def _parse_now(raw: str | None) -> datetime | None:
    if not raw:
        return datetime.now(timezone.utc)
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


# --- CLI --------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="save_point.py",
        description="Shape-2 handoff save-point engine: new / validate / emit.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_new = sub.add_parser("new", help="write a shape-2 skeleton with every deterministic field filled")
    p_new.add_argument("--topic", required=True, help="kebab slug for the filename")
    group = p_new.add_mutually_exclusive_group(required=True)
    group.add_argument("--previous", help="predecessor handoff file (same task only; never auto-picked)")
    group.add_argument("--no-previous", action="store_true", help="first hop of a new task")
    p_new.add_argument("--memory-dir", help="memory root (default .work); handoffs go to <root>/handoffs/")
    p_new.add_argument("--session-id", help="session UUID (default: $CLAUDE_CODE_SESSION_ID)")
    p_new.add_argument("--projects-root", help="transcript root (default ~/.claude/projects)")
    p_new.add_argument("--repo-root", help="repository root (default: git top level of the memory dir)")
    p_new.add_argument("--now", help="ISO-8601 UTC timestamp override (tests)")
    p_new.set_defaults(func=cmd_new)

    p_val = sub.add_parser("validate", help="check a handoff file; PASS/WARN/FAIL lines on stdout")
    p_val.add_argument("file")
    p_val.add_argument("--projects-root", help="transcript root; an 'unresolved (…)' transcript is re-globbed here and the located path named in the finding")
    p_val.add_argument("--strict-transcript", action="store_true", help="an 'unresolved (…)' transcript fails instead of warning")
    p_val.set_defaults(func=cmd_validate)

    p_emit = sub.add_parser("emit", help="print the '## Resume prompt' section body verbatim")
    p_emit.add_argument("file")
    p_emit.set_defaults(func=cmd_emit)
    return parser


def main(argv: list[str] | None = None) -> int:
    _utf8_streams()
    args = build_parser().parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    sys.exit(main())
