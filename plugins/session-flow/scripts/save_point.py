#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Save-point engine for /session-flow:handoff: new / fill / validate / emit.

Owns every deterministic field of a handoff file so the model writes only the
reasoning slots. `new` writes shape 3 by default: a hot file plus one archive
file per hop, `handoffs/archive/<chain-root-stem>/h<N>-<session8>.md`, holding
the predecessor sections the hot file does not carry. Shape 2 (`--shape 2`)
stays writable, and shape-1 and shape-2 files validate and read unchanged.
Stdlib only; Python 3.10+. Read-only on the repository except the files `new`
creates (it never writes a `.gitignore` and never rewrites an existing
handoff; it rewrites a hop file only on a retry by the same session).

Usage:
    save_point.py new --topic <slug> (--previous <file> | --no-previous)
                      [--memory-dir <root>] [--session-id <uuid>]
                      [--projects-root <dir>] [--repo-root <dir>] [--now <iso>]
                      [--shape 2|3] [--purpose <text>]
    save_point.py fill <file> --slots <json>
    save_point.py validate <file> [--projects-root <dir>] [--strict-transcript]
    save_point.py emit <file>
    save_point.py memory-root

Exit codes:
    new       0 written (prints the file's absolute forward-slash path)
              1 refused: root-equivalent memory dir, memory root without the
                self-ignore `.gitignore` (`*`), no --memory-dir outside a git
                work tree with no plugin data dir to fall back to (neither
                $CLAUDE_PLUGIN_DATA nor an installed cache layout), no session UUID / bridge-shaped
                id, predecessor unreadable or outside the handoffs dir, target
                already exists, a shape-3 predecessor continued as shape 2, or
                a hop file owned by another session
              2 usage (neither or both of --previous / --no-previous, bad slug)
    fill      0 every slot replaced from the JSON, file written once, nothing
                printed
              1 refused: a required slot absent from the JSON, a key naming no
                slot in the file, a slot name occurring twice in the file, a
                value carrying the literal `<!-- FILL`, no slot in the file at
                all, or a closing `next` value whose line above is not bare
                `Next:`
              2 usage, target missing or unreadable, not a handoff file, or not
                shape 2 or 3 (only skeletons `new` writes are filled), slots file
                missing or unreadable or not a JSON object, a non-string or
                non-UTF-8-encodable value (names the key), or a failed write
              3 `handoff_shape` newer than `fill` knows: read it, do not
                rewrite it
    validate  0 pass (shape 1, no `handoff_shape` key: one WARN, checks skipped;
                a shape-3 core alone over the byte cap: label UNVALIDATED)
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
    memory-root
              0 printed the absolute forward-slash memory root `new` uses
                without --memory-dir (`.work` in a git work tree, else the
                plugin data dir's `artifacts`)
              1 no git work tree and no plugin data dir

Every write `new` makes is UTF-8 with `\\n` newlines, and `fill` keeps
the target its own line endings; stdout/stderr are reconfigured to UTF-8 so
the U+2500 rails survive a cp1252 pipe on Windows.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

_SCRIPTS_DIR = Path(__file__).resolve().parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

from io_streams import utf8_streams  # noqa: E402  (io_streams.py beside this script)

HANDOFF_SHAPE = 3
# Shapes `new --shape` writes and `fill` fills; shape 2 stays writable so a
# shape-2 chain can still be generated (eval predecessors, size projections).
WRITABLE_SHAPES = (2, 3)

# Shape 3: a hot file in this fixed order, `Original goal` first and
# `Resume prompt` last, plus one immutable archive file per hop.
SECTIONS_3 = (
    "Original goal",
    "Review before you continue",
    "Direction changes",
    "Resumption brief",
    "Completion criteria",
    "Remaining actions, in order",
    "Open questions",
    "Current rules",
    "Observations",
    "Pending commands",
    "Environment to re-establish",
    "Decisions in force",
    "Suggested skills",
    "This session",
    "Prior sessions",
    "Standing preferences",
    "Resume prompt",
)
# Shape 3 files written before `Suggested skills` joined it still validate.
SECTIONS_3_LEGACY = tuple(s for s in SECTIONS_3 if s != "Suggested skills")
# Never moved to the archive to meet the cap.
CORE_3 = (
    "Original goal",
    "Direction changes",
    "Resumption brief",
    "Current rules",
    "Standing preferences",
)
RULE_SECTIONS = ("Current rules", "Standing preferences")
RULE_ID_RE = re.compile(r"^\[R(\d+)\]\s*")
# Shape 3 keeps the predecessor's last rows only; older rows live in hop files.
PRIOR_ROWS_KEPT = 3
ARCHIVE_DIR = "archive"
ARCHIVE_TYPE = "handoff-archive"
# Hot-file byte cap: 10,000 tokens at 2.46 bytes per token, the median of 94
# Read truncation banners that state a real handoff file's token count (range
# 2.34-2.52; the handoff-efficiency audit of 274 handoffs, 2026-10). PROVISIONAL,
# not eval-set: the eval that was to choose 5K, 10K or 20K tokens was not run.
HOT_FILE_MAX_BYTES = 24_600
# The Read tool's page cap, 25,000 tokens ("cap 25000" in its truncation banner),
# at the lowest audited density above (2.34 bytes per token), so no audited file
# under it overflows one Read. A hot file over it FAILs even when its core alone
# passes the hot-file cap: the core's UNVALIDATED pass ends here.
READ_CAP_BYTES = 58_500
# GitHub state claims in a shape-3 hot file (validate WARNs): an issue or pull
# request reference beside a state word, either order. The hot file lists the
# command that re-reads the state instead.
_GH_REF = r"(?:\bPR\s*#?\d+|#\d+|/(?:pull|issues)/\d+)"
_GH_STATE = (
    r"(?:open|opened|closed|merged|draft|ready|approved|green|red|failing|passing|"
    r"queued|blocked|reverted)"
)
GITHUB_STATE_CLAIMS: tuple[tuple[re.Pattern[str], str], ...] = (
    (
        re.compile(rf"(?i){_GH_REF}[^\n]{{0,40}}?\b{_GH_STATE}\b"),
        "reference then state",
    ),
    (
        re.compile(rf"(?i)\b{_GH_STATE}\b[^\n]{{0,20}}?{_GH_REF}"),
        "state then reference",
    ),
)

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
        "(or the latest TodoWrite list) with literal recreate calls (or, in a session with "
        "neither, a line saying so), or an explicit line that there is nothing to recreate",
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
# `new --purpose` writes the stated purpose as the Resumption brief's first line
# and points the brief and skills slots at it (save-point.md, "The purpose
# argument tailors emphasis only").
PURPOSE_PREFIX = "Purpose: "
PURPOSE_SKILLS = "; selected for the Purpose line in Resumption brief, each serving it"


def _brief_lines(purpose: str | None, instruction: str) -> list[str]:
    if not purpose:
        return [_fill("brief", instruction)]
    return [
        PURPOSE_PREFIX + purpose,
        _fill(
            "brief",
            "five lines max below the Purpose line, framed from it: "
            + instruction.split(": ", 1)[1],
        ),
    ]


# A resolved entry moved into a committed doc leaves `- [hN] Promoted to <ref>: <its leading text>`.
PROMOTED_PREFIX = "Promoted to "
PROMOTED_MIN_QUOTE = 20

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
# A bare filename: `.+` would match a path separator, so a pointer carrying a
# `../` traversal suffix would pass and be joined and parsed.
HANDOFF_NAME_RE = re.compile(r"^\d{8}T\d{6}Z-handoff-[^/\\]+\.md$")
SLUG_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
TAG_RE = re.compile(r"^\[h(\d+)\]\s*")
# Keeps a save-point within one Read call at about 70 tokens a line; the per-call cap
# pointer is in reference/structure.md#cumulative-sections-and-provenance-tags ("Size").
# As of 2026-10-11. Recheck when that "Size" entry changes its pointer or threshold.
MAX_READABLE_LINES = 300
UNVERIFIED_PRED_RE = re.compile(r"^UNVERIFIED \(predecessor failed validation\):\s*")
BULLET_RE = re.compile(r"^(?:[-*+]|\d+[.)])\s+")
H2_RE = re.compile(r"^## (.+?)\s*$")
CHAIN_ITEM_RE = re.compile(r"^\s+-\s+")
FILL_MARK = "<!-- FILL"
# The slot grammar `_fill()` writes, and the only parse of it. Non-greedy on the
# instruction: the `## This session` line carries two slots, and a greedy group
# swallows the first slot's `-->` plus the whole second slot. The separator is
# U+2014.
FILL_SLOT_RE = re.compile(r"<!-- FILL: (\S+) — (.*?) -->")
COPY_LINE = "`/clear`, then copy everything between the dashed lines:"
GOAL_COPY_LINE = (
    "Type `/goal ` (with a trailing space), then paste everything between the dashed "
    "lines. Confirm the `◎ /goal active` indicator appears after you send it; if it "
    "is missing, redo it:"
)
# The condition limit, stated once in reference/save-point.md (goal region).
GOAL_CONDITION_MAX = 4000
DIRECTIVE_CLAUSE = "invoke /session-flow:handoff via the Skill tool"
DIRECTIVE_TAIL = (
    "confirm its Original goal still governs the remaining next steps, then continue "
    "them. For the next save-point invoke /session-flow:handoff via the Skill tool; "
    "never write a handoff file free-hand."
)
PRIOR_SESSION_RE = re.compile(r"^Prior session: ([0-9A-Fa-f-]{36})\.$")
THEN_RE = re.compile(r"^Then: /[A-Za-z0-9_:.-]+$")
THIS_SESSION_RE = re.compile(r"^did: .+ · left: .+$")
RESCAN_PREFIX = "Re-scan: "
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
    (
        # GitHub prefixes from
        # https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/about-authentication-to-github#githubs-token-formats
        # and the ghs_ regex GitHub recommends for current and stateless installation tokens from
        # https://github.blog/changelog/2026-05-15-github-app-installation-tokens-per-request-override-header/
        # (as of 2026-10-21; recheck when GitHub changes a token format or its recommended regex).
        # Alternation takes the first branch that matches, so ghs_ comes first:
        # otherwise a JWT loses only its header. One greedy run of one class with
        # nothing after it matches or fails within 36 characters, so it stays linear.
        re.compile(r"\b(?:ghs_[A-Za-z0-9._-]{36,}|gh[pousr]_[A-Za-z0-9]{20,})"),
        "GitHub token",
    ),
    (re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}"), "Slack token"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "AWS key id"),
    (
        # The bounded JWT header and URL scheme keep each start position's
        # scan short; unbounded, a long run with no `.` or `://` is quadratic.
        re.compile(
            r"\beyJ[A-Za-z0-9_-]{10,512}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"
        ),
        "JWT",
    ),
    (
        # A header past the bound: the whole run, dots included, in one match.
        # After the JWT rule, since a long payload segment also starts `eyJ`.
        re.compile(r"\beyJ[A-Za-z0-9_-]{513}[A-Za-z0-9_.-]*"),
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
        re.compile(r"\b[a-z][a-z0-9+.-]{0,63}://[^\s:@/]+:[^\s:@/]+@[^\s]+"),
        "connection string",
    ),
)


# --- I/O ----------------------------------------------------------------------


def _die(code: int, message: str) -> int:
    print(f"error: {message}", file=sys.stderr)
    return code


def _read_lines(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    return [line.rstrip("\r\n") for line in text.splitlines()]


def _line_parts(line: str) -> tuple[str, str]:
    """One `splitlines(keepends=True)` element split into its content and its own
    terminator, so a substitution reattaches the terminator that line had and a
    CRLF file never goes mixed."""
    for terminator in ("\r\n", "\n", "\r"):
        if line.endswith(terminator):
            return line[: -len(terminator)], terminator
    return line, ""


def _posix(path: Path) -> str:
    return path.resolve().as_posix()


def _same_file(a: str, b: Path) -> bool:
    return os.path.normcase(os.path.realpath(a)) == os.path.normcase(
        os.path.realpath(b)
    )


# --- Document model -------------------------------------------------------------


class _UnparsableShape:
    """The value of `handoff_shape` was not an integer. A class rather than a
    number so no literal shape value can be mistaken for it."""

    __slots__ = ()

    def __repr__(self) -> str:
        return "UNPARSABLE_SHAPE"


UNPARSABLE_SHAPE = _UnparsableShape()


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
    def shape(self) -> int | None | _UnparsableShape:
        """None when the key is absent (shape 1); the int otherwise;
        UNPARSABLE_SHAPE when the value is not an integer at all.

        The marker is an object, not a number: a sentinel of -1 collided with a
        literal `handoff_shape: -1`, which was then reported as 'not an integer'.
        """
        raw = self.frontmatter.get("handoff_shape")
        if raw is None:
            return None
        try:
            return int(raw)
        except ValueError:
            return UNPARSABLE_SHAPE

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


def legacy_chain(pred: Doc, limit: int = 1000) -> list[str]:
    """The chain a shape-1 predecessor implies, oldest first and ending with
    it: its `previous_handoff` pointers walked back to the first file with
    none, or to a shape-2 ancestor whose own `chain:` is taken whole. The walk
    stays in the predecessor's directory, as every pointer must, and stops at a
    pointer it cannot follow or a cycle, so an old chain yields what it can
    rather than refusing the successor."""
    walked = [pred.basename]
    cursor = pred
    here = os.path.normcase(os.path.realpath(pred.path.parent))
    while len(walked) < limit:
        previous = cursor.frontmatter.get("previous_handoff")
        if not previous or not HANDOFF_NAME_RE.match(previous) or previous in walked:
            break
        path = pred.path.parent / previous
        if not path.is_file() or (
            os.path.normcase(os.path.dirname(os.path.realpath(path))) != here
        ):
            break
        try:
            cursor = parse_doc(path)
        except (OSError, UnicodeDecodeError):
            break
        if cursor.shape in (None, 1):
            walked.append(cursor.basename)
            continue
        if cursor.chain and cursor.chain[-1] == cursor.basename:
            ancestors = [name for name in cursor.chain if name not in walked]
            return [*ancestors, *reversed(walked)]
        walked.append(cursor.basename)
        break
    return list(reversed(walked))


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
                        _fm_value(item)
                        for item in inline[1:-1].split(",")
                        if item.strip()
                    ]
                idx += 1
                while idx < len(lines) and CHAIN_ITEM_RE.match(lines[idx]):
                    doc.chain.append(_fm_value(CHAIN_ITEM_RE.sub("", lines[idx])))
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
    heads = [
        (m.group(1), i) for i in range(idx, len(lines)) if (m := H2_RE.match(lines[i]))
    ]
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


def _ends_opening_ask(line: str) -> bool:
    """True when `line` resumes Original-goal content below an `Opening ask:`
    line. A verbatim ask may run several paragraphs, so prose does not end it,
    but the ask carries no bullets: a bullet below the ask is an amendment, and
    a `**` line is the next structural marker."""
    return line.startswith("**") or bool(BULLET_RE.match(line))


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
        # A shape-3 core alone over the byte cap: exit 0, labeled UNVALIDATED.
        self.unvalidated = False

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
    return (
        f"unresolved (session {session_id}, projects-root {projects_root.as_posix()})"
    )


def _check_rails_block(doc: Doc, f: Findings, session_id: str) -> None:
    body = doc.section("Resume prompt")
    if body is None:
        return
    rails = [i for i, line in enumerate(body) if RAIL_RE.match(line.strip())]
    ascii_rails = [
        i for i, line in enumerate(body) if ASCII_RAIL_RE.match(line.strip())
    ]
    if len(rails) not in (2, 4):
        detail = f"found {len(rails)}"
        if ascii_rails:
            detail += (
                f", plus {len(ascii_rails)} ASCII rail line(s); rails are U+2500 only"
            )
        f.fail(
            f"Resume prompt: two U+2500 rails (resume region) or four (goal region plus resume region) required ({detail})"
        )
        return
    # Each rail pair is a region, classified by the instruction line above its
    # top rail. Order is a producer rule, so either order passes.
    resume: list[str] | None = None
    resume_bottom = 0
    goals: list[list[str]] = []
    prev_end = 0
    for top, bottom in zip(rails[0::2], rails[1::2]):
        above = [line.strip() for line in body[prev_end:top]]
        prev_end = bottom + 1
        region = body[top + 1 : bottom]
        if any(not line.strip() for line in region):
            f.fail("Resume prompt: blank line between the rails")
        region = [line for line in region if line.strip()]
        if any(line.lstrip().startswith("/goal") for line in region):
            f.fail(
                "Resume prompt: a line between the rails starts with '/goal'; the user types the command, the region holds the condition only"
            )
        if COPY_LINE in above:
            if resume is not None:
                f.fail("Resume prompt: more than one resume region")
            resume, resume_bottom = region, bottom
        elif GOAL_COPY_LINE in above:
            goals.append(region)
        else:
            f.fail(
                f"Resume prompt: no copy instruction line above a top rail (resume region {COPY_LINE!r}, goal region {GOAL_COPY_LINE!r})"
            )
    if len(goals) > 1:
        f.fail("Resume prompt: more than one goal region")
    if resume is None:
        f.fail(
            f"Resume prompt: copy instruction line {COPY_LINE!r} missing above the resume region's top rail"
        )
        return
    between, bottom = resume, resume_bottom
    for goal in goals:
        size = len("\n".join(goal))
        if size > GOAL_CONDITION_MAX:
            f.fail(
                f"Resume prompt: goal region holds {size} characters (max {GOAL_CONDITION_MAX}); shorten the condition text"
            )
        if len(goal) < 2 or not goal[-1].startswith("Read @"):
            f.fail(
                "Resume prompt: goal region must be condition text ending in the 'Read @' directive line"
            )
        elif between and goal[-1] != between[0]:
            f.fail(
                "Resume prompt: goal region's last line must equal the resume region's 'Read @' directive line"
            )
    pos = 0
    if not between or not between[0].startswith("Read @"):
        f.fail(
            "Resume prompt: first line between the resume region's rails must be the 'Read @' directive"
        )
        return
    directive = between[pos]
    path_part = directive[len("Read @") :].split(",", 1)[0].strip()
    if "\\" in path_part or not (
        path_part.startswith("/") or re.match(r"^[A-Za-z]:/", path_part)
    ):
        f.fail(
            f"Resume prompt: 'Read @' path must be absolute and forward-slash (got {path_part!r})"
        )
    elif not _same_file(path_part, doc.path):
        # A stored path naming this file's own basename under another directory
        # is a relocated save-point, not a misidentified one: the basename
        # carries the save-point's identity (its UTC timestamp and topic), and
        # `cmd_emit` already substitutes the real path on stdout. Warn so the
        # relocation stays visible; fail only when the stored path names a
        # different save-point.
        if path_part.rsplit("/", 1)[-1] == doc.basename:
            f.warn(
                f"Resume prompt: 'Read @' path {path_part!r} names this file's basename under another directory; this file is {_posix(doc.path)} (relocated chain; emit substitutes the real path)"
            )
        else:
            f.fail(
                f"Resume prompt: 'Read @' path {path_part!r} does not name this file ({_posix(doc.path)})"
            )
    if DIRECTIVE_CLAUSE not in directive:
        f.fail(f"Resume prompt: directive lacks the clause {DIRECTIVE_CLAUSE!r}")
    pos += 1
    if pos >= len(between) or not (m := PRIOR_SESSION_RE.match(between[pos])):
        f.fail(
            "Resume prompt: 'Prior session: <UUID>.' line missing after the directive"
        )
        return
    if m.group(1).lower() != session_id.lower():
        f.fail(
            f"Resume prompt: 'Prior session:' {m.group(1)} differs from session_id {session_id}"
        )
    pos += 1
    if pos >= len(between) or not between[pos].startswith("Handoff origin: "):
        f.fail("Resume prompt: 'Handoff origin:' line missing after 'Prior session:'")
        return
    try:
        slots = shlex.split(between[pos][len("Handoff origin: ") :], posix=True)
    except ValueError:
        slots = []
    if len(slots) != 2:
        f.fail(
            f"Resume prompt: 'Handoff origin:' must carry exactly two slots (found {len(slots)})"
        )
    pos += 1
    if pos >= len(between) or not between[pos].startswith("Next:"):
        f.fail("Resume prompt: 'Next:' line missing after 'Handoff origin:'")
        return
    next_line = between[pos]
    headlines = between[pos + 1 :]
    if next_line == NEXT_CLOSED:
        if headlines:
            f.fail(
                f"Resume prompt: {NEXT_CLOSED!r} admits no headline lines (found {len(headlines)})"
            )
    elif next_line.strip() != "Next:":
        f.fail(
            f"Resume prompt: 'Next:' must be bare or exactly {NEXT_CLOSED!r} (got {next_line!r})"
        )
    else:
        if not headlines:
            f.fail("Resume prompt: 'Next:' needs 1 to 5 headline lines")
        if len(headlines) > NEXT_MAX:
            f.fail(
                f"Resume prompt: 'Next:' has {len(headlines)} headline lines (max {NEXT_MAX})"
            )
        for line in headlines:
            # Headlines are bare lines: a bullet reads as a list in the pasted
            # prompt, and the contract refuses it.
            if BULLET_RE.match(line):
                f.fail(
                    f"Resume prompt: 'Next:' headline must not be a bullet (got {line!r})"
                )
        thens = [i for i, line in enumerate(headlines) if line.startswith("Then:")]
        if len(thens) > 1:
            f.fail("Resume prompt: at most one 'Then: /<skill>' line")
        elif thens and thens[0] != len(headlines) - 1:
            f.fail(
                "Resume prompt: 'Then: /<skill>' must be the last line between the rails"
            )
        for i in thens:
            if not THEN_RE.match(headlines[i]):
                f.fail(
                    f"Resume prompt: 'Then:' must name exactly one skill as /<skill> (got {headlines[i]!r})"
                )
    resume_line = f"claude --resume {session_id}"
    if not any(resume_line in line for line in body[bottom + 1 :]):
        f.fail(f"Resume prompt: below-rail line carrying {resume_line!r} missing")


def _check_original_goal(doc: Doc, f: Findings, hop: int) -> None:
    body = doc.section("Original goal")
    if body is None:
        return
    ask_idx = next(
        (i for i, line in enumerate(body) if line.startswith("Opening ask:")), None
    )
    if ask_idx is None:
        f.fail("Original goal: 'Opening ask:' line missing")
    goal_lines: list[str] = []
    skip = False
    for line in body:
        # The skip ends at the next structural marker, not at the first blank
        # line: a verbatim opening ask may run several paragraphs, and every
        # one of them belongs to the ask rather than to the goal quote.
        if skip:
            if _ends_opening_ask(line):
                skip = False
            else:
                continue
        if line.startswith(("Opening ask:", "**Next action serves it by:**")):
            skip = True
            continue
        if line.startswith(("**Amended:**", "**Goal")):
            continue
        if line.strip():
            goal_lines.append(line.strip())
    first = goal_lines[0].lstrip("> ").strip() if goal_lines else ""
    if (
        not first
        or first.startswith("None.")
        or first.lower() in {"tbd", "todo", "n/a"}
    ):
        f.fail(
            "Original goal: the goal quote is empty or 'None.'; work with no statable goal is a defect to raise with the user, not a box to tick"
        )
    if ask_idx is not None and hop == 1:
        # Count to the next structural marker, matching the skip above: a
        # blank-line stop undercounts a multi-paragraph ask against the cap.
        block = 0
        for line in body[ask_idx + 1 :]:
            if _ends_opening_ask(line):
                break
            if line.strip():
                block += 1
        inline = body[ask_idx][len("Opening ask:") :].strip()
        if inline and not inline.startswith("see "):
            block += 1
        if block > OPENING_ASK_CAP:
            f.warn(
                f"Original goal: 'Opening ask:' runs {block} lines (cap {OPENING_ASK_CAP}); the transcript is the full source"
            )


def _check_cumulative(
    doc: Doc, f: Findings, hop: int, pred: Doc | None, pred_soft: bool
) -> None:
    for title in CUMULATIVE:
        body = doc.section(title)
        if body is None:
            continue
        entries = parse_entries(body)
        seen: set[str] = set()
        for entry in entries:
            if entry.exempt:
                continue
            key = entry.normalized.casefold()
            if key in seen:
                f.warn(
                    f"{title}: duplicate of an earlier entry (keep the oldest tag, "
                    f"drop this copy): {entry.text[:60]!r}"
                )
            seen.add(key)
            tag = entry.tag
            if tag is None:
                f.fail(
                    f"{title}: entry without an [hN] provenance tag: {entry.text[:60]!r}"
                )
            elif not 1 <= tag <= hop:
                f.fail(
                    f"{title}: tag [h{tag}] out of range 1..{hop}: {entry.text[:60]!r}"
                )
        if pred is None:
            continue
        pred_body = pred.section(title)
        if pred_body is None:
            continue
        have = {entry.normalized for entry in entries}
        pointers = []
        for entry in entries:
            head, _, rest = entry.normalized.partition(": ")
            ref = head[len(PROMOTED_PREFIX) :].strip()
            if head.startswith(PROMOTED_PREFIX) and ref and rest:
                pointers.append((entry.tag, rest))
        for entry in parse_entries(pred_body):
            if entry.exempt or entry.normalized in have:
                continue
            # Each pointer stands in for one dropped entry only.
            match = next(
                (
                    i
                    for i, (tag, rest) in enumerate(pointers)
                    if tag == entry.tag
                    and len(rest) >= min(PROMOTED_MIN_QUOTE, len(entry.normalized))
                    and entry.normalized.startswith(rest)
                ),
                None,
            )
            if match is not None:
                pointers.pop(match)
            else:
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
        if line.startswith(("**Amended:**", "Opening ask:")):
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
    if isinstance(shape, _UnparsableShape):
        f.fail(f"handoff_shape {fm.get('handoff_shape')!r} is not an integer")
        return f, 1
    if shape is None or shape == 1:
        f.warn(
            "shape 1 file (no handoff_shape key): shape checks skipped, rails still emitted by the caller, file never rewritten"
        )
        return f, 0
    if shape < 1:
        f.fail(f"handoff_shape {shape} is not a shape: shapes are integers from 1 up")
        return f, 1
    if shape > HANDOFF_SHAPE:
        f.fail(
            f"handoff_shape {shape} is newer than this validator knows ({HANDOFF_SHAPE}): read it, do not rewrite it"
        )
        return f, 3

    for key in ("type", "date", "topic", "session_id", "transcript"):
        if not fm.get(key):
            f.fail(f"frontmatter: required key {key!r} missing")
    if fm.get("type") and fm["type"] != "handoff":
        f.fail(f"frontmatter: type must be 'handoff' (got {fm['type']!r})")
    if fm.get("date") and not DATE_RE.match(fm["date"]):
        f.fail(
            f"frontmatter: date must be ISO-8601 UTC 'YYYY-MM-DDTHH:MM:SSZ' (got {fm['date']!r})"
        )
    session_id = fm.get("session_id", "")
    if session_id and not UUID_RE.match(session_id):
        f.fail(
            f"frontmatter: session_id {session_id!r} is not a UUID (bridge ids and 'unknown' are refused)"
        )

    previous = fm.get("previous_handoff")
    pred: Doc | None = None
    if previous is not None:
        if not HANDOFF_NAME_RE.match(previous):
            f.fail(
                f"frontmatter: previous_handoff must be a bare filename matching <TS>-handoff-<topic>.md (got {previous!r})"
            )
        else:
            pred_path = doc.path.parent / previous
            # Belt to the regex's braces, and the check `cmd_new` already makes
            # for `--previous`: resolve the real path and hold it to the
            # directory this file lives in, so no pointer (nor a symlink
            # standing in for one) reaches a file outside it to be parsed.
            here = os.path.normcase(os.path.realpath(doc.path.parent))
            there = os.path.normcase(os.path.dirname(os.path.realpath(pred_path)))
            if there != here:
                f.fail(
                    f"frontmatter: previous_handoff {previous!r} resolves outside this file's directory ({here}); a predecessor lives beside its successor"
                )
            elif not pred_path.is_file():
                f.fail(
                    f"frontmatter: previous_handoff {previous!r} not found beside this file"
                )
            elif not shallow:
                try:
                    pred = parse_doc(pred_path)
                except (OSError, UnicodeDecodeError) as exc:
                    f.fail(f"predecessor {previous!r} unreadable: {exc}")
                    pred = None
    if shape == 3:
        _validate_shape3(doc, f, previous, pred, projects_root)
    else:
        _validate_shape2(doc, f, previous, pred, projects_root)

    for i, line in enumerate(doc.lines, 1):
        if FILL_MARK in line:
            f.fail(f"line {i}: leftover {FILL_MARK} slot; fill it or delete it")
            break

    this = doc.section("This session")
    if this is not None:
        content = [line for line in this if line.strip()]
        rescan = content[1:]
        if (
            not content
            or len(rescan) > 1
            or any(not line.strip().startswith(RESCAN_PREFIX) for line in rescan)
        ):
            f.fail(
                f"This session: one line 'did: … · left: …', optionally followed by one '{RESCAN_PREFIX}…' line, required (found {len(content)})"
            )
        else:
            line = content[0].strip()
            if "|" in line:
                f.fail(
                    "This session: '|' is not allowed (the line becomes a table cell downstream)"
                )
            if not THIS_SESSION_RE.match(line):
                f.fail(
                    f"This session: line must read 'did: … · left: …' (got {line[:60]!r})"
                )

    if session_id:
        _check_rails_block(doc, f, session_id)

    transcript = fm.get("transcript", "")
    if transcript:
        if transcript.startswith("unresolved ("):
            located = ""
            if projects_root is not None and session_id and UUID_RE.match(session_id):
                found = _resolve_transcript(session_id, projects_root)
                if not found.startswith("unresolved ("):
                    located = (
                        f"; present now at {found} (the file still says unresolved)"
                    )
            if strict_transcript:
                f.fail(f"transcript: {transcript}{located} (--strict-transcript)")
            else:
                f.warn(f"transcript: {transcript}{located}")
        elif not Path(transcript).is_file():
            f.fail(f"transcript: stated path does not exist: {transcript}")

    for i, line in enumerate(doc.lines, 1):
        for pattern, marker in SECRET_SHAPES:
            if pattern.search(line):
                f.warn(
                    f"line {i}: secret-shaped string ({marker}); redact to a shape marker or rule it benign"
                )
                break

    return f, 1 if f.failed else 0


def _validate_shape2(
    doc: Doc,
    f: Findings,
    previous: str | None,
    pred: Doc | None,
    projects_root: Path | None,
) -> None:
    """The shape-2 checks: `chain:`, the 17 sections, cumulative carry-forward,
    the Prior sessions prefix and the line-count WARN."""
    pred_soft = False
    if not doc.chain:
        f.fail("frontmatter: chain is missing or empty")
    else:
        if doc.chain[-1] != doc.basename:
            f.fail(
                f"frontmatter: chain[-1] must be this file's basename {doc.basename!r} (got {doc.chain[-1]!r})"
            )
        if previous is not None:
            if len(doc.chain) < 2 or doc.chain[-2] != previous:
                f.fail(
                    f"frontmatter: chain[-2] must equal previous_handoff {previous!r}"
                )
        elif len(doc.chain) != 1:
            f.fail(
                "frontmatter: a first hop (no previous_handoff) carries a one-entry chain"
            )
    hop = max(len(doc.chain), 1)

    if pred is not None:
        if pred.shape not in (None, 1):
            pred_soft = _pred_failed(pred, previous, projects_root, f)
            expected_chain = pred.chain + [doc.basename]
            if doc.chain != expected_chain:
                message = f"frontmatter: chain must be the predecessor's chain plus this file ({expected_chain})"
                (f.warn if pred_soft else f.fail)(message)
        else:
            # The two-entry form is what `new` wrote before it walked a shape-1
            # predecessor's pointers; files already written that way stay valid.
            walked = legacy_chain(pred) + [doc.basename]
            if doc.chain not in (walked, [previous, doc.basename]):
                f.fail(
                    f"frontmatter: a shape-1 predecessor gives chain {walked} (its previous_handoff walk plus this file)"
                )

    _check_headings(doc, f, SECTIONS_17)
    _check_original_goal(doc, f, hop)
    _check_cumulative(doc, f, hop, pred, pred_soft)

    prior = doc.section("Prior sessions")
    if prior is not None:
        rows = _parse_prior_rows(prior)
        if previous is None:
            if "\n".join(_trim_blank(prior)).strip() != FIRST_HOP_PRIOR:
                f.fail(f"Prior sessions: a first hop reads exactly {FIRST_HOP_PRIOR!r}")
        else:
            bad = [row for row in rows if len(_cells(row)) != 5]
            if bad:
                f.fail(
                    f"Prior sessions: every row carries 5 cells (date · session id · transcript · did/left · file): {bad[0][:60]!r}"
                )
            if pred is not None:
                pred_rows = _parse_prior_rows(pred.section("Prior sessions"))
                report = f.warn if pred_soft else f.fail
                if rows[: len(pred_rows)] != pred_rows:
                    report(
                        "Prior sessions: the predecessor's rows must be copied verbatim as a prefix"
                    )
                if len(rows) != len(pred_rows) + 1:
                    report(
                        f"Prior sessions: this file adds exactly one row (predecessor had {len(pred_rows)}, this file has {len(rows)})"
                    )
                elif rows:
                    cells = _cells(rows[-1])
                    if len(cells) == 5 and (
                        cells[1].lower()
                        != pred.frontmatter.get("session_id", "").lower()
                        or cells[4] != previous
                    ):
                        report(
                            f"Prior sessions: the added row must describe the predecessor ({pred.frontmatter.get('session_id')} · {previous})"
                        )
            elif not rows:
                f.fail("Prior sessions: at least one row required after hop 1")

    if pred is not None and pred.section("Original goal") is not None:
        pred_goal = _goal_block(pred)
        own_goal = _goal_block(doc)
        if pred_goal and pred_goal != own_goal[: len(pred_goal)]:
            f.warn(
                "Original goal: the goal quote differs from the predecessor's (copied off disk, never restated; amendments are appended with the prior goal kept above)"
            )

    if len(doc.lines) > MAX_READABLE_LINES:
        f.warn(
            f"size: {len(doc.lines)} lines exceeds {MAX_READABLE_LINES}; a single Read may truncate it (cumulative sections are carried verbatim, so trim by moving resolved entries under Superseded or promoting them to a committed doc)"
        )


def _check_headings(doc: Doc, f: Findings, expected: tuple[str, ...]) -> None:
    titles = doc.titles
    if titles != list(expected):
        for i, want in enumerate(expected):
            found = titles[i] if i < len(titles) else "<missing>"
            if found != want:
                f.fail(
                    f"headings: expected '## {want}' at position {i + 1}, found '## {found}' ({len(expected)} sections in order, '## Resume prompt' last)"
                )
                break
        else:
            f.fail(
                f"headings: extra section(s) after '## Resume prompt': {titles[len(expected) :]}"
            )
    # A section with nothing to report reads 'None.' plus a half-line of reason,
    # so a cold reader can tell it from a forgotten one (reference/structure.md).
    for title, start, end in doc.sections:
        if title in expected and not any(
            line.strip() for line in doc.lines[start + 1 : end]
        ):
            f.fail(f"{title}: empty; write 'None.' plus a reason")


def _pred_failed(
    pred: Doc, previous: str | None, projects_root: Path | None, f: Findings
) -> bool:
    findings, code = validate_doc(pred, projects_root, False, shallow=True)
    if code != 0:
        f.warn(
            f"predecessor {previous!r} failed validation ({findings.first_fail}); predecessor-derived checks downgraded to WARN"
        )
    return code != 0


# --- shape 3 ----------------------------------------------------------------------


def _fm_int(doc: Doc, key: str) -> int | None:
    try:
        return int(doc.frontmatter.get(key, ""))
    except ValueError:
        return None


def _stem(name: str) -> str:
    return name[: -len(".md")] if name.endswith(".md") else name


def hop_file_path(handoffs: Path, chain_root: str, hop: int, session_id: str) -> Path:
    """`<handoffs>/archive/<chain-root-stem>/h<N>-<session8>.md`."""
    return (
        handoffs
        / ARCHIVE_DIR
        / _stem(chain_root)
        / f"h{hop}-{session_id[:8].lower()}.md"
    )


def _chain_position(pred: Doc | None, name: str) -> tuple[str, int, int]:
    """`(chain_root, hop, archive_from)` for a shape-3 file named `name` that
    follows `pred`. Hops count from the chain root, shape-1 and shape-2 hops
    included; the first shape-3 hop is where hop files start."""
    if pred is None:
        return name, 1, 1
    if pred.shape == 3:
        hop = (_fm_int(pred, "hop") or 0) + 1
        start = _fm_int(pred, "archive_from") or hop
        return pred.frontmatter.get("chain_root") or pred.basename, hop, start
    walked = (
        legacy_chain(pred)
        if pred.shape in (None, 1)
        else (pred.chain or [pred.basename])
    )
    hop = len(walked) + 1
    return walked[0], hop, hop


def _rule_entries(doc: Doc) -> list[tuple[int | None, Entry, str]]:
    found: list[tuple[int | None, Entry, str]] = []
    for title in RULE_SECTIONS:
        for entry in parse_entries(doc.section(title) or []):
            if entry.exempt:
                continue
            m = RULE_ID_RE.match(entry.text)
            found.append((int(m.group(1)) if m else None, entry, title))
    return found


def _squash(text: str) -> str:
    return " ".join(text.split())


def _section_lines(doc: Doc, title: str) -> list[str]:
    """A section body as raw line content (terminators aside, nothing else
    stripped), blank edge lines trimmed."""
    return _trim_blank(doc.section(title) or [])


def _section_bytes(doc: Doc, titles: tuple[str, ...]) -> int:
    return sum(
        len(line.encode("utf-8")) + 1
        for name, start, end in doc.sections
        if name in titles
        for line in doc.lines[start:end]
    )


def _cap_state(doc: Doc) -> tuple[int, int]:
    """The hot file's size on disk and the bytes its core sections hold."""
    return len(doc.path.read_bytes()), _section_bytes(doc, CORE_3)


def _sibling(directory: Path, name: str) -> Doc | None:
    """A handoff file beside `directory`'s files, parsed, or None."""
    if not HANDOFF_NAME_RE.match(name):
        return None
    path = directory / name
    if not path.is_file() or os.path.normcase(
        os.path.dirname(os.path.realpath(path))
    ) != os.path.normcase(os.path.realpath(directory)):
        return None
    try:
        return parse_doc(path)
    except (OSError, UnicodeDecodeError):
        return None


def _verbatim_ask(root: Doc) -> list[str] | None:
    """The root file's `Opening ask:` block, or None when it holds only a
    pointer or nothing."""
    body = root.section("Original goal") or []
    at = next(
        (i for i, line in enumerate(body) if line.startswith("Opening ask:")), None
    )
    if at is None:
        return None
    inline = body[at][len("Opening ask:") :].strip()
    if inline.startswith("see "):
        return None
    block = [body[at]]
    for line in body[at + 1 :]:
        if _ends_opening_ask(line):
            break
        block.append(line)
    block = _trim_blank(block)
    return block if inline or len(block) > 1 else None


ASK_POINTER = "Opening ask: see "


def _dereferenced_goal(pred: Doc, root: str) -> list[str]:
    """A shape-2 (or shape-1) predecessor's Original goal for the first shape-3
    hop: the drift-check line dropped, and the `Opening ask: see <root>` pointer
    replaced by the root's verbatim ask when the root is on disk and has one."""
    lines = [
        line
        for line in _section_lines(pred, "Original goal")
        if not line.startswith("**Next action serves it by:**")
    ]
    lines = _trim_blank(lines)
    at = next((i for i, line in enumerate(lines) if line.startswith(ASK_POINTER)), None)
    if at is not None:
        root = _sibling(
            pred.path.parent, lines[at][len(ASK_POINTER) :].split(" ", 1)[0]
        )
        ask = _verbatim_ask(root) if root is not None else None
        if ask:
            lines[at : at + 1] = ask
    elif not any(line.startswith("Opening ask:") for line in lines):
        lines += [
            "",
            f"{ASK_POINTER}{root} § Original goal (shape-1 root, no verbatim ask recorded)",
        ]
    return lines


def _validate_shape3(
    doc: Doc,
    f: Findings,
    previous: str | None,
    pred: Doc | None,
    projects_root: Path | None,
) -> None:
    """The shape-3 checks: chain position, the fixed section order, the raw goal
    prefix, rule ids, the hop files on the chain path, nothing dropped between
    the hot file and this hop's file, the last Prior-sessions rows, the byte
    cap, and the GitHub state WARN."""
    fm = doc.frontmatter
    for key in ("chain_root", "hop", "archive", "archive_from", "repo"):
        if not fm.get(key):
            f.fail(f"frontmatter: required key {key!r} missing")
    root = fm.get("chain_root", "")
    hop, start = _fm_int(doc, "hop"), _fm_int(doc, "archive_from")
    if fm.get("hop") and (hop is None or hop < 1):
        f.fail(f"frontmatter: hop must be an integer from 1 up (got {fm['hop']!r})")
        hop = None
    if fm.get("archive_from") and (
        start is None or hop is None or not 1 <= start <= hop
    ):
        f.fail(
            f"frontmatter: archive_from must be an integer from 1 to hop (got {fm['archive_from']!r})"
        )
        start = None
    if root and not HANDOFF_NAME_RE.match(root):
        f.fail(
            f"frontmatter: chain_root must be a bare handoff filename (got {root!r})"
        )
        root = ""
    elif (
        root and fm.get("archive") and fm["archive"] != f"{ARCHIVE_DIR}/{_stem(root)}/"
    ):
        f.fail(
            f"frontmatter: archive must be '{ARCHIVE_DIR}/{_stem(root)}/' (got {fm['archive']!r})"
        )
    if doc.titles == list(SECTIONS_3_LEGACY):
        f.warn(
            "headings: written before '## Suggested skills' joined shape 3; the next hop adds it"
        )
        _check_headings(doc, f, SECTIONS_3_LEGACY)
    else:
        _check_headings(doc, f, SECTIONS_3)
    _check_original_goal(doc, f, hop or 1)

    prompt = doc.section("Resume prompt") or []
    origin = next(
        (line for line in prompt if line.startswith("Handoff origin: ")), None
    )
    if origin and fm.get("repo"):
        try:
            slots = shlex.split(origin[len("Handoff origin: ") :], posix=True)
        except ValueError:
            slots = []
        if slots and slots[0] != fm["repo"]:
            f.fail(
                f"frontmatter: repo {fm['repo']!r} must equal the Handoff origin's first slot {slots[0]!r}"
            )

    seen: set[int] = set()
    for rule_id, entry, title in _rule_entries(doc):
        if rule_id is None:
            f.fail(f"{title}: entry without a [R<n>] id: {entry.text[:60]!r}")
        elif rule_id in seen:
            f.fail(f"{title}: duplicate rule id [R{rule_id}]")
        seen.add(rule_id or 0)

    _check_github_claims(doc, f)
    if hop is None or start is None or not root:
        return

    handoffs = doc.path.parent
    own = hop_file_path(handoffs, root, hop, fm.get("session_id", ""))
    rel = own.relative_to(handoffs).as_posix()
    archived: str | None = None
    if not own.is_file():
        f.fail(f"archive: this hop's file {rel} is missing")
    else:
        try:
            archived = own.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            f.fail(f"archive: this hop's file {rel} is unreadable: {exc}")

    report = f.fail
    if previous is None:
        if (root, hop, start) != (doc.basename, 1, 1):
            f.fail(
                "frontmatter: a first hop (no previous_handoff) has chain_root its own name, hop 1 and archive_from 1"
            )
    elif pred is not None:
        if pred.shape not in (None, 1) and _pred_failed(
            pred, previous, projects_root, f
        ):
            report = f.warn
        want = _chain_position(pred, doc.basename)
        if (root, hop, start) != want:
            report(
                f"frontmatter: after {previous!r} (chain_root, hop, archive_from) is {want} (got {(root, hop, start)})"
            )
        _check_carry_3(doc, f, pred, hop == start, rel, archived, report)
        _check_hop_path(f, pred, start)
    _check_prior_rows_3(doc, f, previous, pred, rel, archived, report)

    size, core = _cap_state(doc)
    if size > READ_CAP_BYTES:
        f.fail(
            f"size: {size} bytes is over the {READ_CAP_BYTES}-byte Read page cap, so one Read cannot hold this file; move non-core content into {rel} (the core holds {core} bytes)"
        )
    elif size > HOT_FILE_MAX_BYTES:
        if core > HOT_FILE_MAX_BYTES:
            f.unvalidated = True
            f.warn(
                f"UNVALIDATED: the core sections ({', '.join(CORE_3)}) alone hold {core} bytes, over the {HOT_FILE_MAX_BYTES}-byte hot-file cap; core never moves to the archive, so this file stands unvalidated"
            )
        else:
            f.fail(
                f"size: {size} bytes is over the {HOT_FILE_MAX_BYTES}-byte hot-file cap; move non-core content into {rel} before validating (the core holds {core} bytes)"
            )


def _check_carry_3(
    doc: Doc,
    f: Findings,
    pred: Doc,
    first_split: bool,
    rel: str,
    archived: str | None,
    report,
) -> None:
    """Nothing the predecessor held is dropped: it stays in this file or is in
    this hop's file."""
    arch = _squash(archived or "")
    if pred.shape == 3:
        pred_goal = _section_lines(pred, "Original goal")
        if _section_lines(doc, "Original goal")[: len(pred_goal)] != pred_goal:
            report(
                "Original goal: does not start with the predecessor's section byte for byte (copy it off disk, append a new owner amendment below it, never rewrite)"
            )
        trail = _section_lines(pred, "Direction changes")
        if _section_lines(doc, "Direction changes")[: len(trail)] != trail:
            report(
                "Direction changes: the predecessor's trail lines stay first, verbatim; append this hop's lines below them"
            )
        if archived is None:
            return
        own = {rid: e for rid, e, _ in _rule_entries(doc) if rid is not None}
        for rule_id, entry, title in _rule_entries(pred):
            if rule_id is None:
                continue
            prior = _squash(entry.text)
            if rule_id in own:
                if _squash(own[rule_id].text) != prior and prior not in arch:
                    report(
                        f"{title}: changed rule [R{rule_id}] has no prior text in {rel}; a rule rewritten in place keeps its predecessor text there"
                    )
            elif prior not in arch:
                report(
                    f"{title}: predecessor rule [R{rule_id}] is in neither this file nor {rel}"
                )
        return
    if first_split:
        lines = _section_lines(doc, "Original goal")
        pointer = next((line for line in lines if line.startswith(ASK_POINTER)), None)
        if pointer is not None:
            target = pointer[len(ASK_POINTER) :].split(" ", 1)[0]
            root = _sibling(doc.path.parent, target)
            if root is not None and _verbatim_ask(root):
                f.fail(
                    f"Original goal: '{ASK_POINTER}{target}' must be replaced by that file's verbatim Opening ask on the first shape-3 hop"
                )
    if pred.section("Original goal") is not None:
        pred_goal = _goal_block(pred)
        if pred_goal and pred_goal != _goal_block(doc)[: len(pred_goal)]:
            f.warn(
                "Original goal: the goal quote differs from the predecessor's (copied off disk, never restated)"
            )
    if archived is None:
        return
    hot = _squash("\n".join(doc.lines))
    for title in CUMULATIVE:
        for entry in parse_entries(pred.section(title) or []):
            text = _squash(entry.text)
            if not entry.exempt and text not in arch and text not in hot:
                report(
                    f"{title}: predecessor entry is in neither this file nor {rel}: {entry.text[:60]!r}"
                )


def _check_hop_path(f: Findings, pred: Doc, start: int) -> None:
    """Every shape-3 predecessor on this file's `previous_handoff` path, from
    `archive_from` on, has its own hop file."""
    cursor: Doc | None = pred
    seen: set[str] = set()
    while cursor is not None and cursor.shape == 3 and cursor.basename not in seen:
        seen.add(cursor.basename)
        hop = _fm_int(cursor, "hop")
        root = cursor.frontmatter.get("chain_root", "")
        if hop is None or hop < start or not HANDOFF_NAME_RE.match(root):
            break
        path = hop_file_path(
            cursor.path.parent, root, hop, cursor.frontmatter.get("session_id", "")
        )
        if not path.is_file():
            f.fail(
                f"archive: hop file {path.relative_to(cursor.path.parent).as_posix()} of predecessor {cursor.basename!r} is missing"
            )
        previous = cursor.frontmatter.get("previous_handoff")
        cursor = _sibling(cursor.path.parent, previous) if previous else None


def _check_prior_rows_3(
    doc: Doc,
    f: Findings,
    previous: str | None,
    pred: Doc | None,
    rel: str,
    archived: str | None,
    report,
) -> None:
    body = doc.section("Prior sessions")
    if body is None:
        return
    rows = _parse_prior_rows(body)
    if previous is None:
        if "\n".join(_trim_blank(body)).strip() != FIRST_HOP_PRIOR:
            f.fail(f"Prior sessions: a first hop reads exactly {FIRST_HOP_PRIOR!r}")
        return
    bad = [row for row in rows if len(_cells(row)) != 5]
    if bad:
        f.fail(
            f"Prior sessions: every row carries 5 cells (date · session id · transcript · did/left · file): {bad[0][:60]!r}"
        )
    if not 1 <= len(rows) <= PRIOR_ROWS_KEPT:
        f.fail(
            f"Prior sessions: 1 to {PRIOR_ROWS_KEPT} rows after hop 1, the last describing the predecessor (found {len(rows)})"
        )
    if pred is None or not rows:
        return
    pred_rows = _parse_prior_rows(pred.section("Prior sessions"))
    if rows[:-1] != pred_rows[max(0, len(pred_rows) - (PRIOR_ROWS_KEPT - 1)) :]:
        report(
            f"Prior sessions: the predecessor's last {PRIOR_ROWS_KEPT - 1} rows come first, verbatim, then one row for the predecessor"
        )
    cells = _cells(rows[-1])
    if len(cells) == 5 and (
        cells[1].lower() != pred.frontmatter.get("session_id", "").lower()
        or cells[4] != previous
    ):
        report(
            f"Prior sessions: the last row must describe the predecessor ({pred.frontmatter.get('session_id')} · {previous})"
        )
    if archived is not None:
        for row in pred_rows:
            if row not in rows and row not in archived:
                report(
                    f"Prior sessions: predecessor row {row[:60]!r} is in neither this file nor {rel}"
                )


def _check_github_claims(doc: Doc, f: Findings) -> None:
    """WARN on a GitHub state claim outside `Original goal` (the owner's words)."""
    goal = next(
        ((s, e) for name, s, e in doc.sections if name == "Original goal"), (0, 0)
    )
    for i, line in enumerate(doc.lines):
        if goal[0] <= i < goal[1]:
            continue
        for pattern, label in GITHUB_STATE_CLAIMS:
            if pattern.search(line):
                f.warn(
                    f"line {i + 1}: GitHub state claim ({label}); state goes stale, so the hot file lists the command that re-reads it instead"
                )
                break


def _open_handoff(file: str) -> tuple[Doc | None, int]:
    """The shared `validate`/`emit` preamble: a readable file carrying
    `type: handoff` frontmatter. `None` plus the exit code when it is not, the
    refusal already printed to stderr."""
    path = Path(file)
    if not path.is_file():
        return None, _die(2, f"not a file: {path}")
    try:
        doc = parse_doc(path)
    except (OSError, UnicodeDecodeError) as exc:
        return None, _die(2, f"cannot read {path}: {exc}")
    if not doc.has_frontmatter or doc.frontmatter.get("type") != "handoff":
        return None, _die(
            2, f"not a handoff file (no 'type: handoff' frontmatter): {path}"
        )
    return doc, 0


def cmd_validate(args: argparse.Namespace) -> int:
    doc, code = _open_handoff(args.file)
    if doc is None:
        return code
    projects_root = (
        Path(args.projects_root).expanduser() if args.projects_root else None
    )
    findings, code = validate_doc(doc, projects_root, args.strict_transcript)
    for level, message in findings.items:
        print(f"{level}: {message}")
    if code == 3:
        label = "UNSUPPORTED-SHAPE"
    else:
        label = "FAIL" if code != 0 else ("WARN" if findings.items else "PASS")
        if code == 0 and findings.unvalidated:
            label = "UNVALIDATED"
    count = f" ({len(findings.items)})" if findings.items else ""
    print(f"validate: {label}{count} {_posix(doc.path)}")
    return code


# --- emit -------------------------------------------------------------------------


def cmd_emit(args: argparse.Namespace) -> int:
    doc, code = _open_handoff(args.file)
    if doc is None:
        return code
    path = doc.path
    if any(FILL_MARK in line for line in doc.lines):
        return _die(
            1,
            f"unfinished skeleton (a {FILL_MARK} slot remains); never emitted: {_posix(path)}",
        )
    body = doc.section("Resume prompt")
    if body is None:
        if doc.shape in (None, 1):
            return _die(
                1,
                f"shape 1 handoff has no '## Resume prompt' section (legacy file, never rewritten): {_posix(path)}",
            )
        return _die(1, f"'## Resume prompt' section absent: {_posix(path)}")
    if doc.shape == 3:
        size, core = _cap_state(doc)
        if size > READ_CAP_BYTES:
            # The prompt is never withheld (save-point.md, "Three failed attempts
            # do not withhold the rails"); the notice says validate fails it.
            print(
                f"FAIL: this hot file holds {size} bytes, over the {READ_CAP_BYTES}-byte Read page cap; `validate` fails it and one Read cannot hold it; the prompt is emitted",
                file=sys.stderr,
            )
        elif size > HOT_FILE_MAX_BYTES and core > HOT_FILE_MAX_BYTES:
            print(
                f"UNVALIDATED: this hot file's core holds {core} bytes, over the {HOT_FILE_MAX_BYTES}-byte cap; the prompt is emitted, the file was not validated",
                file=sys.stderr,
            )
    real = _posix(path)
    out: list[str] = []
    for line in _trim_blank(body):
        if line.startswith("Read @"):
            stored = line[len("Read @") :].split(",", 1)[0].strip()
            if not _same_file(stored, path):
                print(
                    f"WARN: stored 'Read @' path {stored} is not this file; substituting {real} on stdout only (file untouched)",
                    file=sys.stderr,
                )
                line = "Read @" + real + line[len("Read @") + len(stored) :]
        out.append(line)
    sys.stdout.write("\n".join(out) + "\n")
    return 0


# --- fill -------------------------------------------------------------------------


def cmd_fill(args: argparse.Namespace) -> int:
    """Replace every slot in one pass and one write. Substitution only, with the
    single exception the closing handoff needs: a `next` value of exactly
    NEXT_CLOSED rewrites the bare `Next:` line above the slot and deletes the
    slot line, which is the only shape `validate` accepts as closed.

    The write path reuses neither `_read_lines` nor `parse_doc`: both apply
    universal-newline translation and would rewrite a CRLF target to LF.
    `parse_doc` serves the `type: handoff` and shape guards alone, read-only,
    mirroring `cmd_validate` and `cmd_emit`. Every refusal happens before the
    write, so a refused target is byte-identical.
    """
    path = Path(args.file)
    if not path.is_file():
        return _die(2, f"not a file: {path}")
    try:
        text = path.read_bytes().decode("utf-8")
        doc = parse_doc(path)
    except (OSError, UnicodeDecodeError) as exc:
        return _die(2, f"cannot read {path}: {exc}")
    if not doc.has_frontmatter or doc.frontmatter.get("type") != "handoff":
        return _die(2, f"not a handoff file (no 'type: handoff' frontmatter): {path}")
    # `validate_doc`'s shape ladder, in its order and for its reason: a newer
    # shape is read, never rewritten, and `_UnparsableShape` is tested first so
    # no later comparison meets a non-integer.
    shape = doc.shape
    unsupported = f"fill only writes shape-2 and shape-3 skeletons: {path}"
    if isinstance(shape, _UnparsableShape):
        return _die(
            2,
            f"handoff_shape {doc.frontmatter.get('handoff_shape')!r} is not an integer; {unsupported}",
        )
    if shape is None or shape == 1:
        return _die(
            2,
            f"shape 1 handoff ({'no handoff_shape key' if shape is None else 'handoff_shape 1'}), never rewritten; {unsupported}",
        )
    if shape < 1:
        return _die(
            2,
            f"handoff_shape {shape} is not a shape: shapes are integers from 1 up; {unsupported}",
        )
    if shape > HANDOFF_SHAPE:
        return _die(
            3,
            f"handoff_shape {shape} is newer than fill knows ({HANDOFF_SHAPE}): read it, do not rewrite it: {path}",
        )

    slots_path = Path(args.slots)
    try:
        raw = slots_path.read_bytes().decode("utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        return _die(2, f"cannot read slots file {slots_path}: {exc}")
    try:
        values = json.loads(raw)
    except ValueError as exc:
        return _die(2, f"slots file is not valid JSON ({exc}): {_posix(slots_path)}")
    if not isinstance(values, dict):
        return _die(
            2,
            f"slots file must hold a JSON object keyed by slot name, not a {type(values).__name__}: {_posix(slots_path)}",
        )
    # Every exit-2 check runs over every key before the exit-1 check below, so a
    # payload carrying both defects exits 2 whatever order its keys arrive in.
    for key, value in values.items():
        if not isinstance(value, str):
            return _die(
                2,
                f"slots value for {key!r} must be a string, not a {type(value).__name__}",
            )
        try:
            value.encode("utf-8")
        except UnicodeEncodeError as exc:
            return _die(
                2,
                f"slots value for {key!r} is not encodable as UTF-8 ({exc}); rewrite it in {_posix(slots_path)}",
            )
    for key, value in values.items():
        if FILL_MARK in value:
            # Landing this verbatim makes `validate` name the wrong line as an
            # unfilled slot and `emit` refuse the file as a skeleton.
            return _die(
                1,
                f"slots value for {key!r} carries the literal {FILL_MARK!r}; rewrite the value without it",
            )

    lines = text.splitlines(keepends=True)
    slot_line: dict[str, int] = {}
    optional: set[str] = set()
    for index, line in enumerate(lines):
        content, _ = _line_parts(line)
        for match in FILL_SLOT_RE.finditer(content):
            name = match.group(1)
            if name in slot_line:
                return _die(
                    1,
                    f"slot {name!r} occurs twice in {_posix(path)}; one value cannot resolve a duplicated name, so fix the file first",
                )
            slot_line[name] = index
            # Optional-ness is read off the instruction, keeping `_fill()` the
            # single source of the slot shape.
            if match.group(2).startswith("optional:"):
                optional.add(name)
    if not slot_line:
        return _die(
            1,
            f"no {FILL_MARK} slot in {_posix(path)}; a filled file is validated, never filled again",
        )

    unknown = sorted(key for key in values if key not in slot_line)
    if unknown:
        return _die(
            1,
            f"key {unknown[0]!r} names no slot in {_posix(path)}; take the slot names from the skeleton `new` wrote, never from a remembered template",
        )
    absent = sorted(
        name for name in slot_line if name not in values and name not in optional
    )
    if absent:
        return _die(
            1,
            f"required slot {absent[0]!r} is absent from {_posix(slots_path)}; key it with its value and re-run",
        )

    closing = -1
    if values.get("next") == NEXT_CLOSED:
        index = slot_line["next"]
        above = _line_parts(lines[index - 1])[0] if index else ""
        if not index or above != "Next:":
            return _die(
                1,
                f"a {NEXT_CLOSED!r} value rewrites the line above the `next` slot, which must be exactly 'Next:' (got {above!r}); fix the file or pass headline lines instead",
            )
        closing = index

    out: list[str] = []
    for index, line in enumerate(lines):
        content, terminator = _line_parts(line)
        if index == closing:
            continue
        if closing > 0 and index == closing - 1:
            out.append(NEXT_CLOSED + terminator)
            continue
        matches = list(FILL_SLOT_RE.finditer(content))
        if not matches:
            out.append(line)
            continue
        # A line goes only when every slot on it is optional and unkeyed; the
        # `did` / `left` line carries two required slots and can never go.
        if all(m.group(1) in optional and m.group(1) not in values for m in matches):
            continue
        rebuilt = ""
        cursor = 0
        for match in matches:
            rebuilt += content[cursor : match.start()]
            # `\n` only, never `str.splitlines()`, which also breaks on a lone
            # `\r`, a form feed, and U+2028 / U+2029 that a JSON string carries.
            rebuilt += values.get(match.group(1), "").replace("\r\n", "\n")
            cursor = match.end()
        rebuilt += content[cursor:]
        parts = rebuilt.split("\n")
        inner = terminator or "\n"
        for position, part in enumerate(parts):
            out.append(part + (inner if position < len(parts) - 1 else terminator))

    # Every value was encode-checked above and the source decoded cleanly, so
    # the encode below cannot raise. The bytes land in a temporary file in the
    # target's own directory and are replaced into place, so an interrupted
    # write leaves the handoff whole rather than truncated; `find-handoff` globs
    # only `*.md`, so a `.fill-*.tmp` left by a crash is never read as a handoff.
    payload = "".join(out).encode("utf-8")
    tmp = None
    try:
        handle, tmp = tempfile.mkstemp(dir=path.parent, prefix=".fill-", suffix=".tmp")
        with os.fdopen(handle, "wb") as stream:
            stream.write(payload)
        os.replace(tmp, path)
    except OSError as exc:
        if tmp is not None:
            try:
                os.unlink(tmp)
            except OSError:
                pass
        return _die(2, f"cannot write {path} ({exc}); nothing written")
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


def _plugin_data_root() -> Path | None:
    """The plugin's data dir: ``$CLAUDE_PLUGIN_DATA`` when its last path
    segment names session-flow, else derived from this script's install path.
    Bash-tool commands do not receive this plugin's value, so the derivation
    is the normal case in a session (record: ``reference/structure.md``
    "Verification record: plugin data dir"), and another plugin's SessionStart
    hook can export its own data dir under that name, which is ignored.
    An installed plugin runs from ``<config>/plugins/cache/<marketplace>/
    <plugin>/<version>/``, and its data dir is ``<config>/plugins/data/<id>/``
    where ``<id>`` is ``<plugin>@<marketplace>`` with every character other
    than a letter, digit, ``_`` or ``-`` replaced by ``-``. Any other layout
    (``--plugin-dir``, a source checkout) has no derivable id: None.
    Caveat: derivation assumes the cache layout above; a layout change gives None (refusal), recheck per the record."""
    env = os.environ.get("CLAUDE_PLUGIN_DATA", "")
    segment = Path(env.rstrip("/\\")).name if env else ""
    if segment == "session-flow" or segment.startswith("session-flow-"):
        return Path(env).expanduser()
    version_dir = _SCRIPTS_DIR.parent
    plugin_dir = version_dir.parent
    marketplace_dir = plugin_dir.parent
    cache_dir = marketplace_dir.parent
    if cache_dir.name != "cache" or cache_dir.parent.name != "plugins":
        return None
    plugin_id = re.sub(
        r"[^A-Za-z0-9_-]", "-", f"{plugin_dir.name}@{marketplace_dir.name}"
    )
    return cache_dir.parent / "data" / plugin_id


def _default_memory_dir() -> Path | None:
    """``.work`` under a git top level; ``<plugin data>/artifacts`` outside
    one. None when there is no project root and no plugin data dir to fall
    back to."""
    if _git_toplevel(Path.cwd()) is not None:
        return Path(".work")
    data_root = _plugin_data_root()
    return data_root / "artifacts" if data_root is not None else None


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


def _goal_slot_instruction(order: str, edge: str) -> str:
    return (
        "optional: when a goal applies and save-point.md's order rule puts the goal region "
        f"{order} the resume region, the whole goal region as lines: the fixed goal instruction "
        "line, a blank line, the top rail, the condition text, the resume region's Read @ line, "
        f"the bottom rail; {edge}; otherwise delete this line"
    )


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


def _splice_new_slot(carried: list[str], slot: str) -> list[str]:
    """Place the `-new` FILL slot where a filled entry belongs: above a
    top-level `Superseded:` marker when the carried body ends with one, since
    `parse_entries` reads everything below that marker as superseded. With no
    marker the slot appends, which is the same position."""
    marker = next(
        (
            i
            for i, line in enumerate(carried)
            if line.strip().startswith("Superseded:")
            and not line.startswith((" ", "\t"))
        ),
        None,
    )
    if marker is None:
        return [*carried, "", slot]
    above = _trim_blank(carried[:marker])
    return [*above, "", slot, "", *carried[marker:]]


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


def _pred_row(pred: Doc, pred_transcript: str) -> str:
    """The Prior-sessions row describing the predecessor."""
    if pred.shape in (None, 1):
        did_left = f"UNVERIFIED (shape-1 predecessor; brief: {_first_line(pred.section('Resumption brief'))})"
    else:
        this = [line for line in (pred.section("This session") or []) if line.strip()]
        did_left = (
            this[0].strip()
            if this
            else "UNVERIFIED (predecessor had no This session line)"
        )
    return (
        f"| {pred.frontmatter.get('date', 'unknown')} | {pred.frontmatter.get('session_id', 'unknown')} "
        f"| {pred_transcript} | {did_left} | {pred.basename} |"
    )


def _resume_prompt(
    target: Path, session_id: str, origin: str, origin_path: str
) -> list[str]:
    """The `## Resume prompt` skeleton lines, shape 2 and shape 3 alike."""
    read_path = _posix(target)
    return [
        _fill(
            "goal-first",
            _goal_slot_instruction(
                "before",
                "end the value with a newline so a blank line follows the region",
            ),
        ),
        COPY_LINE,
        "",
        RAIL,
        f"Read @{read_path}, {DIRECTIVE_TAIL}",
        f"Prior session: {session_id}.",
        f"Handoff origin: {_slot(origin)} {_slot(origin_path)}",
        "Next:",
        _fill(
            "next",
            f"1 to {NEXT_MAX} plain headline lines replacing this line, one per line, no bullets, no blank lines; the last may be 'Then: /<one skill>' at a stage boundary; for a closing handoff write '{NEXT_CLOSED}' on the line above and delete this one",
        ),
        RAIL,
        _fill(
            "goal-after",
            _goal_slot_instruction(
                "after",
                "start the value with a newline so a blank line precedes the region",
            ),
        ),
        "",
        f"Or reopen the producing session in place: `claude --resume {session_id}`.",
        _fill(
            "below-rail",
            "optional: the /goal and /loop re-arm notes save-point.md prescribes below the bottom rail; delete this line when none applies",
        ),
    ]


def build_skeleton(
    *,
    purpose: str | None = None,
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
        chain = legacy_chain(pred) + [target.name]
    else:
        chain = pred.chain + [target.name]
    hop = len(chain)
    pred_hop = hop - 1

    fm = [
        "---",
        "type: handoff",
        "handoff_shape: 2",
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
                _fill(
                    "goal",
                    "the user's goal statement quoted as they wrote it, with the date they stated it; RECONSTRUCTED (and settled with the user) when it was never put in one sentence",
                ),
                "",
                "**Amended:** "
                + _fill(
                    "amended",
                    "'None.' until the goal changes; otherwise a new dated verbatim quote with the prior goal kept above it",
                ),
                "",
                "Opening ask:",
                _fill(
                    "opening-ask",
                    f"the user's opening message this session, verbatim and redacted, at most {OPENING_ASK_CAP} lines, no bullets; the transcript is the full source",
                ),
            ]
        else:
            goal += [
                _fill(
                    "goal",
                    "RECONSTRUCTED from the transcript; settle with the user (the shape-1 predecessor recorded no Original goal)",
                ),
                "",
                "**Amended:** "
                + _fill(
                    "amended",
                    "'None.' until the goal changes; otherwise a new dated verbatim quote with the prior goal kept above it",
                ),
                "",
                f"Opening ask: see {chain[0]} § Original goal (shape-1 root, no verbatim ask recorded)",
            ]
    else:
        kept: list[str] = []
        skip = False
        for line in pred_goal:
            # Ends at the next structural marker, not at the first blank line;
            # paragraph 2 of a multi-paragraph verbatim ask is still the ask,
            # and copying it here would smuggle it into the successor's
            # immutable goal block instead of leaving the pointer to stand.
            if skip:
                if _ends_opening_ask(line):
                    skip = False
                else:
                    continue
            if line.startswith(("Opening ask:", "**Next action serves it by:**")):
                skip = True
                continue
            kept.append(line.rstrip())
        goal += _trim_blank(kept)
        goal.append("")
        pointer = f"Opening ask: see {chain[0]} § Original goal"
        if pred.shape in (None, 1):
            pointer += " (shape-1 root, no verbatim ask recorded)"
        goal.append(pointer)
    goal.append("")
    goal.append(
        "**Next action serves it by:** "
        + _fill(
            "drift-check",
            "one sentence tying the first remaining action back to the goal; cannot state it → that is drift, say so and route it",
        )
    )
    section("Original goal", goal)

    # 2..14
    for title in SECTIONS_14[1:]:
        if title in CUMULATIVE:
            name = CUMULATIVE_SLOT[title]
            lines: list[str] = []
            if pred is None:
                lines.append(
                    _fill(
                        name,
                        "one [h1]-tagged entry per line ('- [h1] …'), continuation lines indented; 'None.' plus a half-line of reason when nothing applies",
                    )
                )
            else:
                pred_body = pred.section(title)
                if pred_body is None:
                    lines.append(f"None. (shape-1 predecessor had no {title})")
                else:
                    lines.extend(_tag_carried(pred_body, pred_hop, pred_failed))
                slot = _fill(
                    f"{name}-new",
                    f"optional: write new [h{hop}] entries on this line, above any 'Superseded:' marker (entries below one are read as superseded); move disproved ones under a 'Superseded:' line (never delete), re-tag re-verified ones [h{hop}]; delete this line when nothing changes",
                )
                lines = _splice_new_slot(lines, slot)
            section(title, lines)
        elif title == "Resumption brief":
            section(title, _brief_lines(purpose, REWRITTEN[title][1]))
        else:
            name, instruction = REWRITTEN[title]
            if purpose and title == "Suggested skills":
                instruction += PURPOSE_SKILLS
            section(title, [_fill(name, instruction)])

    # This session
    section(
        "This session",
        [
            "did: "
            + _fill("did", "what landed this session, past tense, no '|'")
            + " · left: "
            + _fill("left", "what is still open, past tense, no 'next', no '|'"),
            RESCAN_PREFIX
            + _fill(
                "rescan",
                "one line: the constraints re-scan read the lossless on-disk transcript, or 'visible conversation only; a compaction occurred this session, so pre-compaction turns were NOT re-scanned for buried constraints'",
            ),
        ],
    )

    # Prior sessions
    if pred is None:
        section("Prior sessions", [FIRST_HOP_PRIOR])
    else:
        rows = _parse_prior_rows(pred.section("Prior sessions"))
        own_row = _pred_row(pred, pred_transcript)
        section("Prior sessions", [PRIOR_HEADER, PRIOR_SEPARATOR, *rows, own_row])

    section("Resume prompt", _resume_prompt(target, session_id, origin, origin_path))

    return "\n".join(fm + body) + "\n"


def hop_file_text(
    *, chain_root: str, hop: int, session_id: str, pred: Doc | None
) -> str:
    """The archive file hop N writes: every predecessor section the hot file
    does not carry forward, verbatim and in the predecessor's order (its
    `Original goal` too when the predecessor is shape 1 or 2, since the first
    shape-3 hop re-forms it). Rewritten only by a retry of the same session."""
    lines = [
        "---",
        f"type: {ARCHIVE_TYPE}",
        f"chain_root: {chain_root}",
        f"hop: {hop}",
        f"session_id: {session_id}",
    ]
    if pred is not None:
        lines.append(f"moved_from: {pred.basename}")
    lines.append("---")
    if pred is None:
        return "\n".join([*lines, "", "None (first hop): nothing moved."]) + "\n"
    skip = {"Resume prompt"} | ({"Original goal"} if pred.shape == 3 else set())
    for title, start, end in pred.sections:
        if title not in skip:
            lines += ["", f"## {title}", "", *_trim_blank(pred.lines[start + 1 : end])]
    return "\n".join(lines) + "\n"


def _next_rule_id(pred: Doc | None) -> int:
    """The first rule id this hop may assign. Monotonic along the chain: the
    predecessor's own `next_rule_id` floor, so an id retired from the hot file
    is never offered again, and one past every id the predecessor holds."""
    if pred is None or pred.shape != 3:
        return 1
    ids = [rid for rid, _, _ in _rule_entries(pred) if rid is not None]
    return max(_fm_int(pred, "next_rule_id") or 1, max(ids, default=0) + 1)


def build_skeleton_3(
    *,
    purpose: str | None = None,
    slug: str,
    session_id: str,
    date: str,
    transcript: str,
    target: Path,
    pred: Doc | None,
    origin: str,
    origin_path: str,
    pred_transcript: str,
) -> str:
    root, hop, start = _chain_position(pred, target.name)
    hop_rel = hop_file_path(Path(), root, hop, session_id).as_posix()
    carried = pred is not None and pred.shape == 3
    next_id = _next_rule_id(pred)
    fm = [
        "---",
        "type: handoff",
        "handoff_shape: 3",
        f"date: {date}",
        f"topic: {slug}",
        f"session_id: {session_id}",
        f"transcript: {transcript}",
    ]
    if pred is not None:
        fm.append(f"previous_handoff: {pred.basename}")
    fm += [
        f"chain_root: {root}",
        f"hop: {hop}",
        f"archive: {ARCHIVE_DIR}/{_stem(root)}/",
        f"archive_from: {start}",
        f"next_rule_id: {next_id}",
        f"repo: {origin}",
        "---",
    ]
    body: list[str] = []

    def section(title: str, lines: list[str]) -> None:
        body.extend(["", f"## {title}", "", *_trim_blank(lines)])

    def slot(name: str, instruction: str) -> str:
        return _fill(name, instruction)

    amended = slot(
        "amended",
        "'None.' until the owner amends the goal; otherwise the dated verbatim amendment",
    )
    goal_new = slot(
        "goal-new",
        "optional: a new dated verbatim owner amendment, or the owner's intent and vision lines when this section lacks them, appended below; the lines above are copied off disk and never rewritten; delete this line when nothing changes",
    )
    if pred is None or pred.section("Original goal") is None:
        goal = [
            "**Goal (verbatim):**",
            slot(
                "goal",
                "the user's goal statement quoted as they wrote it, with the date they stated it"
                if pred is None
                else "RECONSTRUCTED from the transcript; settle with the user (the shape-1 predecessor recorded no Original goal)",
            ),
            "",
            "**Intent (verbatim):** "
            + slot(
                "intent",
                "why the work exists, in the owner's words; 'None stated.' when they gave none",
            ),
            "",
            "**Vision (verbatim):** "
            + slot(
                "vision",
                "where the work heads, in the owner's words; 'None stated.' when they gave none",
            ),
            "",
            "**Amended:** " + amended,
            "",
        ]
        if pred is None:
            goal += [
                "Opening ask:",
                slot(
                    "opening-ask",
                    f"the user's opening message this session, verbatim and redacted, at most {OPENING_ASK_CAP} lines, no bullets; the transcript is the full source",
                ),
            ]
        else:
            goal.append(
                f"{ASK_POINTER}{root} § Original goal (shape-1 root, no verbatim ask recorded)"
            )
    elif carried:
        goal = [*_section_lines(pred, "Original goal"), "", goal_new]
    else:
        goal = [*_dereferenced_goal(pred, root), "", goal_new]
    section("Original goal", goal)

    section(
        "Review before you continue",
        [
            slot(
                "review",
                f"what to read before the next action, tailored to it: each archive section by file and heading (this hop's moved sections are in {hop_rel}), each instruction file a preference points at, and each command that re-reads live state; 'None.' plus a reason when this file suffices",
            )
        ],
    )

    trail_line = f"one line per change of direction, '- [h<k>] <change> (<cause>)', the cause owner-directed (quoting the owner) or agent-initiated; flag a remaining action that serves no recorded goal or detour as '- [h{hop}] DRIFT: <action>'"
    if carried:
        trail = [
            *_section_lines(pred, "Direction changes"),
            "",
            slot(
                "trail-new",
                f"optional: this hop's lines below the carried ones, {trail_line}; delete this line when the direction did not change",
            ),
        ]
    elif pred is None:
        trail = [
            slot(
                "trail",
                f"'- [h1] start: <where the work starts> (<cause>)', then {trail_line}",
            )
        ]
    else:
        trail = [
            slot(
                "trail",
                f"the chain's direction so far, read from the predecessor and {hop_rel}: {trail_line}",
            )
        ]
    section("Direction changes", trail)

    section(
        "Resumption brief",
        _brief_lines(
            purpose,
            "six lines max: when written and against which branch or commit, where the work stands, the single next action and the section that governs it; close with the obligation to read Current rules first",
        ),
    )
    for title, name, instruction in (
        (
            "Completion criteria",
            "criteria",
            "each criterion as an observable goal-state with a met/unmet mark and the command or diff that settles it",
        ),
        (
            "Remaining actions, in order",
            "remaining",
            "every action still to take, numbered and sequenced; an action waiting on someone is marked waiting",
        ),
        (
            "Open questions",
            "open-questions",
            "each open question with its options and a recommendation, and what it unblocks; 'None.' plus a reason when there are none",
        ),
    ):
        section(title, [slot(name, instruction)])

    rule_line = f"one per line, '- [R<n>] <the rule's current text, verbatim>', new ids from R{next_id}; a rule binding beyond this chain's goal goes under Standing preferences"
    if carried:
        rules = [
            *_section_lines(pred, "Current rules"),
            "",
            slot(
                "rules-new",
                f"optional: new rules, {rule_line}; a changed rule is rewritten in place under its id and a retired one deleted, its prior text staying in {hop_rel}; delete this line when nothing changes",
            ),
        ]
    else:
        source = (
            ""
            if pred is None
            else f" (the predecessor's constraints are in {hop_rel} § Constraints that must hold)"
        )
        rules = [
            slot(
                "rules",
                f"every goal-scoped rule in force{source}, {rule_line}; 'None.' plus a reason when none applies",
            )
        ]
    section("Current rules", rules)

    for title, name, instruction in (
        (
            "Observations",
            "observations",
            f"session-wide observations, summarized, one line each; detail stays in {hop_rel} or the transcript; no live GitHub state, list its re-read command under Review before you continue",
        ),
        (
            "Pending commands",
            "commands",
            "every command waiting on the user, verbatim; 'None.' plus a reason when none waits",
        ),
        (
            "Environment to re-establish",
            "environment",
            "branch and worktree, services, env vars, background tasks and the live task list with literal recreate calls, or a line that there is nothing to recreate",
        ),
        (
            "Decisions in force",
            "decisions",
            "the decisions the remaining actions depend on, one line each with its reason; settled history stays in the archive",
        ),
        (
            "Suggested skills",
            REWRITTEN["Suggested skills"][0],
            REWRITTEN["Suggested skills"][1] + (PURPOSE_SKILLS if purpose else ""),
        ),
    ):
        section(title, [slot(name, instruction)])

    section(
        "This session",
        [
            "did: "
            + slot("did", "what landed this session, past tense, no '|'")
            + " · left: "
            + slot("left", "what is still open, past tense, no 'next', no '|'"),
            RESCAN_PREFIX
            + slot(
                "rescan",
                "one line: the constraints re-scan read the lossless on-disk transcript, or 'visible conversation only; a compaction occurred this session, so pre-compaction turns were NOT re-scanned for buried constraints'",
            ),
        ],
    )

    if pred is None:
        section("Prior sessions", [FIRST_HOP_PRIOR])
    else:
        rows = [
            *_parse_prior_rows(pred.section("Prior sessions")),
            _pred_row(pred, pred_transcript),
        ]
        section(
            "Prior sessions", [PRIOR_HEADER, PRIOR_SEPARATOR, *rows[-PRIOR_ROWS_KEPT:]]
        )

    pref_line = "one per line, '- [R<n>] <the preference, verbatim> (pending promotion: <instruction file>)', ids shared with Current rules; a preference its instruction file already holds leaves this file"
    if carried:
        prefs = [
            *_section_lines(pred, "Standing preferences"),
            "",
            slot(
                "preferences-new",
                f"optional: new standing preferences, {pref_line}; delete this line when nothing changes",
            ),
        ]
    else:
        prefs = [
            slot(
                "preferences",
                f"each standing preference not yet in its instruction file, {pref_line}; 'None.' plus a reason when none is pending",
            )
        ]
    section("Standing preferences", prefs)

    section("Resume prompt", _resume_prompt(target, session_id, origin, origin_path))
    return "\n".join(fm + body) + "\n"


def cmd_memory_root(args: argparse.Namespace) -> int:
    root = _default_memory_dir()
    if root is None:
        return _die(
            1,
            "no project root (cwd has no git top level) and no plugin data dir: CLAUDE_PLUGIN_DATA is unset and this script is not running from an installed plugin cache",
        )
    print(root.expanduser().resolve().as_posix())
    return 0


def cmd_new(args: argparse.Namespace) -> int:
    slug = args.topic
    if not SLUG_RE.match(slug):
        return _die(2, f"topic slug {slug!r} must match {SLUG_RE.pattern}")

    purpose = " ".join((args.purpose or "").split()) or None
    if purpose and ("<!--" in purpose or "-->" in purpose):
        return _die(2, "--purpose must not carry '<!--' or '-->'; rewrite it without")

    session_id = args.session_id or os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    if not session_id:
        return _die(
            1,
            "no session UUID available (CLAUDE_CODE_SESSION_ID unset and --session-id not given); take the prompt-only path with the reason stated",
        )
    if not UUID_RE.match(session_id):
        return _die(
            1,
            f"session id {session_id!r} is not a UUID (Remote Control bridge ids are refused; never read CLAUDE_CODE_BRIDGE_SESSION_ID); take the prompt-only path",
        )
    session_id = session_id.lower()

    if args.memory_dir:
        memory_dir = Path(args.memory_dir).expanduser().resolve()
    elif args.repo_root:
        memory_dir = Path(".work").resolve()
    else:
        default = _default_memory_dir()
        if default is None:
            return _die(
                1,
                "no project root (cwd has no git top level) and no plugin data dir: CLAUDE_PLUGIN_DATA is unset and this script is not running from an installed plugin cache; pass --memory-dir <root> explicitly",
            )
        memory_dir = default.expanduser().resolve()
    repo_root = (
        Path(args.repo_root).expanduser().resolve()
        if args.repo_root
        else _git_toplevel(memory_dir)
    )
    if repo_root is not None and (
        memory_dir == repo_root or repo_root not in memory_dir.parents
    ):
        return _die(
            1,
            f"Invalid memory_dir: {memory_dir.as_posix()} must resolve to a dedicated directory below the repository root {repo_root.as_posix()}",
        )
    # The self-ignore guard holds on every memory root, inside a repository or
    # not (the no-project-root branch under the plugin data dir included).
    guard = memory_dir / ".gitignore"
    try:
        guarded = guard.is_file() and any(
            line.strip() == "*" for line in _read_lines(guard)
        )
    except (OSError, UnicodeDecodeError):
        guarded = False
    if not guarded:
        return _die(
            1,
            f"memory root {memory_dir.as_posix()} lacks the self-ignore guard: create {guard.as_posix()} containing the single line '*' (the skill's guard step: the Write tool, or the Edit tool when the file exists, never a shell redirect), then re-run; this script never writes it",
        )

    handoffs = memory_dir / "handoffs"
    now = _parse_now(args.now)
    if now is None:
        return _die(2, f"--now must be ISO-8601 UTC (got {args.now!r})")
    stamp = now.strftime("%Y%m%dT%H%M%SZ")
    date = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    target = handoffs / f"{stamp}-handoff-{slug}.md"
    if target.exists():
        return _die(1, f"target already exists, never overwritten: {_posix(target)}")

    projects_root = (
        Path(args.projects_root).expanduser()
        if args.projects_root
        else Path.home() / ".claude" / "projects"
    )
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
            return _die(
                1,
                f"predecessor is not a handoff file (no 'type: handoff' frontmatter): {pred_path}",
            )
        if os.path.normcase(os.path.realpath(pred_path.parent)) != os.path.normcase(
            os.path.realpath(handoffs)
        ):
            return _die(
                1,
                f"predecessor must live in the handoffs dir the new file is written to ({handoffs.as_posix()}); got {_posix(pred_path)}",
            )
        if isinstance(pred.shape, int) and pred.shape > HANDOFF_SHAPE:
            return _die(
                1,
                f"predecessor carries handoff_shape {pred.shape}, newer than this script knows ({HANDOFF_SHAPE}): read it, do not build on it",
            )
        if pred.shape == 3 and args.shape < 3:
            return _die(
                1,
                f"predecessor is shape 3; a shape-3 chain is never continued as shape {args.shape}",
            )
        if pred.shape not in (None, 1):
            _, code = validate_doc(pred, projects_root, False, shallow=True)
            pred_failed = code != 0
            pred_transcript = (
                pred.frontmatter.get("transcript")
                or "unresolved (predecessor recorded none)"
            )
        else:
            pred_sid = pred.frontmatter.get("session_id", "")
            pred_transcript = (
                _resolve_transcript(pred_sid, projects_root)
                if UUID_RE.match(pred_sid)
                else "unresolved (shape-1 predecessor; no session UUID)"
            )

    if repo_root is not None:
        origin = origin_identity(_git_origin(repo_root), repo_root.name)
        try:
            origin_path = target.resolve().relative_to(repo_root).as_posix()
        except ValueError:
            origin_path = _posix(target)
    else:
        origin = memory_dir.parent.name or memory_dir.name
        origin_path = _posix(target)

    common = dict(
        slug=slug,
        session_id=session_id,
        date=date,
        transcript=transcript,
        target=target,
        pred=pred,
        origin=origin,
        origin_path=origin_path,
        pred_transcript=pred_transcript,
        purpose=purpose,
    )
    if args.shape == 2:
        content = build_skeleton(**common, pred_failed=pred_failed)
    else:
        content = build_skeleton_3(**common)
        root, hop, _ = _chain_position(pred, target.name)
        # The root comes from the predecessor's frontmatter: hold it to a bare
        # handoff name so no `../` lands the hop file outside the archive.
        if not HANDOFF_NAME_RE.match(root):
            return _die(
                1,
                f"predecessor's chain_root (or first chain: entry) {root!r} is not a bare <TS>-handoff-<topic>.md name; no hop file written",
            )
        hop_path = hop_file_path(handoffs, root, hop, session_id)
        archive_root = (handoffs / ARCHIVE_DIR).resolve()
        if archive_root not in hop_path.resolve().parents:
            return _die(
                1,
                f"hop file {_posix(hop_path)} resolves outside {archive_root.as_posix()}",
            )
        if hop_path.exists():
            # A retry of the same session rewrites its own hop file; any other
            # session's file, a fork's sibling included, is never touched.
            try:
                owner = parse_doc(hop_path).frontmatter.get("session_id", "")
            except (OSError, UnicodeDecodeError):
                owner = ""
            if owner.lower() != session_id:
                return _die(
                    1,
                    f"hop file {_posix(hop_path)} belongs to session {owner or 'unknown'}, not {session_id}; never overwritten",
                )
        hop_path.parent.mkdir(parents=True, exist_ok=True)
        hop_path.write_text(
            hop_file_text(chain_root=root, hop=hop, session_id=session_id, pred=pred),
            encoding="utf-8",
            newline="\n",
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
        description="Handoff save-point engine: new / fill / validate / emit.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_new = sub.add_parser(
        "new",
        help="write a skeleton (shape 3 by default) with every deterministic field filled",
    )
    p_new.add_argument("--topic", required=True, help="kebab slug for the filename")
    group = p_new.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--previous",
        help="predecessor handoff file (same task only; never auto-picked)",
    )
    group.add_argument(
        "--no-previous", action="store_true", help="first hop of a new task"
    )
    p_new.add_argument(
        "--memory-dir",
        help="memory root (default .work inside a git work tree; outside one, the plugin data dir's artifacts/); handoffs go to <root>/handoffs/",
    )
    p_new.add_argument(
        "--session-id", help="session UUID (default: $CLAUDE_CODE_SESSION_ID)"
    )
    p_new.add_argument(
        "--projects-root", help="transcript root (default ~/.claude/projects)"
    )
    p_new.add_argument(
        "--repo-root", help="repository root (default: git top level of the memory dir)"
    )
    p_new.add_argument(
        "--purpose",
        help="the invocation's purpose text: written as the Resumption brief's first line, and the skills slot is selected for it",
    )
    p_new.add_argument("--now", help="ISO-8601 UTC timestamp override (tests)")
    p_new.add_argument(
        "--shape",
        type=int,
        choices=WRITABLE_SHAPES,
        default=HANDOFF_SHAPE,
        help="shape to write (default %(default)s; shape 2 builds no hot file or archive)",
    )
    p_new.set_defaults(func=cmd_new)

    p_fill = sub.add_parser(
        "fill",
        help="replace every <!-- FILL: … --> slot from one JSON object, in one write",
    )
    p_fill.add_argument("file")
    p_fill.add_argument(
        "--slots",
        required=True,
        help="JSON object keyed by slot name; an optional slot left out has its line deleted",
    )
    p_fill.set_defaults(func=cmd_fill)

    p_val = sub.add_parser(
        "validate", help="check a handoff file; PASS/WARN/FAIL lines on stdout"
    )
    p_val.add_argument("file")
    p_val.add_argument(
        "--projects-root",
        help="transcript root; an 'unresolved (…)' transcript is re-globbed here and the located path named in the finding",
    )
    p_val.add_argument(
        "--strict-transcript",
        action="store_true",
        help="an 'unresolved (…)' transcript fails instead of warning",
    )
    p_val.set_defaults(func=cmd_validate)

    p_emit = sub.add_parser(
        "emit", help="print the '## Resume prompt' section body verbatim"
    )
    p_emit.add_argument("file")
    p_emit.set_defaults(func=cmd_emit)

    p_root = sub.add_parser(
        "memory-root", help="print the memory root `new` uses without --memory-dir"
    )
    p_root.set_defaults(func=cmd_memory_root)
    return parser


def main(argv: list[str] | None = None) -> int:
    utf8_streams()
    args = build_parser().parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    sys.exit(main())
