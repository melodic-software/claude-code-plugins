#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Save-point engine for /session-flow:handoff: new / fill / amend / validate / emit.

Owns every deterministic field of a handoff file so the model writes only the
reasoning slots. `new` writes shape 4 by default: a handoff file plus one archive
file per hop, `handoffs/archive/<chain-root-stem>/h<N>-<session8>.md`, holding
the predecessor sections the handoff file does not carry and any section `fill`
moved; `--shape 3` keeps the shape-3 layout. Shape 2 (`--shape 2`)
stays writable, and shape-1 and shape-2 files validate and read unchanged.
Stdlib only; Python 3.10+. Read-only on the repository except the files `new`
creates (it never writes a `.gitignore` and never rewrites an existing
handoff; it rewrites an archive file only on a retry by the same session), and the
handoff file and archive file `fill` and `amend` rewrite. A new-session
handoff also writes its initial prompt beside the file when emitted.

Usage:
    save_point.py new --topic <slug> (--previous <file> | --no-previous)
                      [--memory-dir <root>] [--session-id <uuid>]
                      [--projects-root <dir>] [--repo-root <dir>] [--now <iso>]
                      [--shape 2|3|4|5] [--purpose <text>]
                      [--start-command [<command>]] [--launch-dir <checkout>]
    save_point.py fill <file> --slots <json>
    save_point.py amend <file> --json <json> [--now <iso>]
    save_point.py validate <file> [--projects-root <dir>] [--strict-transcript]
    save_point.py emit <file> [--shell posix|powershell]
    save_point.py launch <prompt-file> --checkout <directory> [--start-command <command>]
    save_point.py read <file> --section <name>
    save_point.py chain <file> [--json]
    save_point.py memory-root

Exit codes:
    new       0 written (prints the file's absolute forward-slash path)
              1 refused: root-equivalent memory dir, memory root without the
                self-ignore `.gitignore` (`*`), no --memory-dir outside a git
                work tree with no plugin data dir to fall back to (neither
                $CLAUDE_PLUGIN_DATA nor an installed cache layout), no session UUID / bridge-shaped
                id, predecessor outside the handoffs dir or not a handoff file,
                target already exists, a shape-3 or shape-4 predecessor
                continued as an older shape, or
                an archive file owned by another session, or a same-session archive
                file holding `## Amended …` or `## Retired …` content (run
                `amend` instead)
              2 usage (neither or both of --previous / --no-previous, bad slug)
              A --previous file that is missing or unreadable is no refusal:
              the skeleton names it as previous_handoff with previous_status
              missing|unreadable, one WARN line on stderr names it, and fill
              and emit proceed
    fill      0 every slot replaced from the JSON, file written once; shape 2
                and 3 print nothing; shape 4 moves whole movable sections
                (Observations, Suggested skills, Direction changes) to this
                hop's file behind a pointer until the handoff file is under the
                cap, then prints the validate verdict (an OVER-CAP line when
                binding content alone is over it) and the emit output; a launch
                error prints its `No launch command:` line and still exits 0
              1 (shapes 3 and 4) a Resumption brief or below-the-rails note
                over its slot budget on the first try: nothing written, the
                slot and the bytes over named; the next fill writes anyway and
                validate FAILs the slot
              1 refused: a required slot absent from the JSON, a key naming no
                slot in the file, a slot name occurring twice in the file, a
                value carrying the literal `<!-- FILL`, no slot in the file at
                all, or a closing `next` value whose line above is not bare
                `Next:`
              2 usage, target missing or unreadable, not a handoff file, or not
                shape 2, 3 or 4 (only skeletons `new` writes are filled), slots file
                missing or unreadable or not a JSON object, a non-string or
                non-UTF-8-encodable value (names the key), or a failed write
              3 a `handoff_shape` past the shapes `fill` writes: read it, do
                not rewrite it
    amend     0 written; prints the validate verdict, then the emit output (a
                size FAIL never blocks the write; a launch error prints its
                `No launch command:` line and still exits 0)
              1 refused, both files untouched: an unfilled skeleton, a no-op, a
                carried section, an unknown section, a floor lowered, an entry
                this hop added removed without a retire, a FAIL the amend would
                add, or a file that is no longer the chain tip (prints the
                successor's `amend` command)
              2 usage, unreadable, not a shape-3 or shape-4 handoff, a malformed JSON
                object, or a failed write
    validate  0 pass (shape 1, no `handoff_shape` key: one WARN, checks skipped;
                a shape-3 core alone over the byte cap: label UNVALIDATED; a
                shape-4 file never passes UNVALIDATED: binding content over the
                cap FAILs naming the section)
              1 validation failure
              2 usage / unreadable / not a handoff file
              3 `handoff_shape` newer than this validator knows: read it, do
                not rewrite it
    emit      0 printed the `## Resume prompt` section body verbatim (heading
                excluded, surrounding blank lines trimmed); when the stored
                `Read @` path is not this file, a WARN goes to stderr and the
                real path is substituted on stdout only. For a new session,
                write the selected region to the prompt file and print the launch command
              1 section absent (shape 1 says so) or the file still carries a
                `<!-- FILL` slot (unfinished skeleton, never emitted), or a launch
                checkout or prompt is unavailable
              2 usage / unreadable
    read      0 printed the section body; a body that is only a move pointer
                is read from the archive file it names
              1 no such section, or its move pointer names no file or heading
                on disk
              2 usage / unreadable
              3 `handoff_shape` newer than this script knows
    chain     0 printed each handoff file the walk reaches and each hop's
                sections (handoff file, else the next hop's file), and the
                session ids; a missing link is a link, not a failure
              2 usage / unreadable
              3 `handoff_shape` newer than this script knows
    memory-root
              0 printed the absolute forward-slash memory root `new` uses
                without --memory-dir (`.work` in a git work tree, else the
                plugin data dir's `artifacts`)
              1 no git work tree and no plugin data dir

Every write `new` makes is UTF-8 with `\\n` newlines, and `fill` and `amend`
keep each file its own line endings; stdout/stderr are reconfigured to UTF-8 so
the U+2500 rails survive a cp1252 pipe on Windows.
"""

from __future__ import annotations

import argparse
import functools
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
from collections import Counter
from collections.abc import Callable
from dataclasses import dataclass, field, replace
from datetime import datetime, timezone
from enum import Enum
from pathlib import Path

_SCRIPTS_DIR = Path(__file__).resolve().parent
if str(_SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS_DIR))

import plugin_paths  # noqa: E402  (plugin_paths.py beside this script)
from io_streams import utf8_streams  # noqa: E402  (io_streams.py beside this script)
from handoff_chain import (  # noqa: E402  (handoff_chain.py beside this script)
    ARCHIVE_DIR,
    BULLET_RE,
    HANDOFF_NAME_RE,
    HOP_FILE_SHAPES,
    NEWEST_SHAPE,
    RETIRED_PREFIX,
    SHAPES,
    STANDING_INLINE_OK,
    STANDING_PREFIX,
    STANDING_SECTIONS,
    WRITABLE_SHAPES,
    IdSpec,
    MovePointer,
    entry_text,
    fitted,
    fm_value,
    follow,
    hop_file_path,
    id_of,
    journey,
    moved_heading,
    read_chain,
    read_link,
    read_frontmatter,
    retired_in,
    retired_listings,
    section_of,
    section_spans,
    standing_pointer,
    standing_rel,
    standing_rels,
)
import dialect  # noqa: E402  (dialect.py beside this script)
import handoff_fit  # noqa: E402  (handoff_fit.py beside this script)
from handoff_fit import PURPOSE_PREFIX, REOPEN_PREFIX  # noqa: E402

HANDOFF_SHAPE = 5
CHECKS = 3
CONTENT_ONLY_DOWNGRADE_FROM = 2
ID_REUSE_FROM = 3
UNVERIFIED_SETTLE_FROM = 3
SLOT_SIZE_FROM = 3

S3 = SHAPES[3]
ID_SPECS = SHAPES[NEWEST_SHAPE].id_specs
RULES = S3.id_spec("R")
REMINDERS = SHAPES[NEWEST_SHAPE].id_spec("M")
REMINDER_RE = re.compile(
    r"^\[M\d+\] (?:user|agent|peer \S[^·]*?) · (?:at close|at \S+|when [^·]+?) · .+ · added h\d+(?: \d{4}-\d{2}-\d{2})?(?: Rewritten h\d+: \S.*)?$"
)
RETIRED_RULES = RULES.retired_heading
AMENDMENT_RE = re.compile(r"^(?:- )?\*\*Amended.*?:\*\*")
TRAIL_TAG_RE = re.compile(r"^- \[(h\d+(?:-h?\d+)?)\]")
DIRECTION_HOPS_KEPT = 3
FOLD_PREFIX = "- Folded: "
REWRITE_MARK = "Rewritten"
REWRITE_MARK_RE = re.compile(rf"\b{REWRITE_MARK} h(\d+): \S")
DECISION_TAG_RE = re.compile(r"^\[(security|design)\]")
DECISION_FIELDS = ("buys", "surface", "cost")
DECISION_TAG_SHAPE = (
    "a security or design decision is tagged after its id and ends with its rationale, "
    "'- [D<n>] [security|design] <decision> (<reason>) buys: <what it gains>; "
    "surface: <the surface exposed today, or none>; cost: <measured cost so far, or none yet>'"
)
REMINDER_SHAPE = "'- [M<n>] <actor> · <trigger> · <what to do> · added h<k> <YYYY-MM-DD>', actor 'user', 'agent' or 'peer <session or lane>', trigger 'at <ISO-8601 time with UTC offset>', 'when <condition>' (optionally '; check `<read-only command>`') or 'at close', a command verbatim in one backtick span"
CODIFIED_RE = re.compile(r"\bcodified in \[R(\d+)\]")
POINTED_HEADINGS = (
    *(spec.retired_heading for spec in ID_SPECS if spec != RULES),
    *S3.retired_entry_sections.values(),
)
RETIRE_HEADINGS = (RETIRED_RULES, *POINTED_HEADINGS)
HOP_NAME_RE = re.compile(r"\bh\d+-[0-9a-f]{8}\.md\b")
RETIRE_REF_RE = re.compile(
    rf"^\[(?P<prefix>[{''.join(s.prefix for s in ID_SPECS)}])(?P<n>\d+)\]$"
    r"|^\[(?P<tag>h\d+(?:-h?\d+)?)\](?:#(?P<tag_ord>\d+))?$"
    r"|^amendment#(?P<ord>\d+)$"
)
NEW_HOME_RE = re.compile(
    r"\[R\d+\]|\b(?:promoted|moved|codified) (?:to|in|into)\b|/|\.md\b"
)
FRONTMATTER_KEYS_3 = (
    "type",
    "handoff_shape",
    "checks",
    "date",
    "topic",
    "session_id",
    "transcript",
    "previous_handoff",
    "previous_status",
    "chain_root",
    "hop",
    "archive",
    "archive_from",
    "standing_rules",
    "launch",
    *(spec.floor_key for spec in ID_SPECS),
    "repo",
)
PRIOR_ROWS_KEPT = 3
ARCHIVE_TYPE = "handoff-archive"
# Hot-file byte cap: 10,000 tokens at 2.46 bytes per token, the median of 94
# Read truncation banners that state a real handoff file's token count (range
# 2.34-2.52; the handoff-efficiency audit of 274 handoffs, 2026-10). PROVISIONAL,
# not eval-set: the eval that was to choose 5K, 10K or 20K tokens was not run.
HOT_FILE_MAX_BYTES = S3.cap_bytes
# The Read tool's page cap, 25,000 tokens ("cap 25000" in its truncation banner),
# at the lowest audited density above (2.34 bytes per token), so no audited file
# under it overflows one default Read; past it the Read returns only the first page
# unless the reader passes allow_large. A hot file over it FAILs even when its core alone
# passes the hot-file cap: the core's UNVALIDATED pass ends here.
READ_CAP_BYTES = 58_500
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

SECTIONS_17 = SHAPES[2].names
SECTIONS_14 = SECTIONS_17[:-3]
CUMULATIVE = (
    "Constraints that must hold",
    "Side effects already applied",
    "Decisions already settled",
    "Approaches tried and abandoned",
    "Findings that cost effort to discover",
)
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
        "fully-qualified skills (plugin:skill, 'if enabled') each tied to a concrete "
        "remaining item, or 'None. Remaining work runs inline'",
    ),
}
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
SLUG_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
TAG_RE = re.compile(r"^\[h(\d+)\]\s*")
# Keeps a save-point within one Read call at about 70 tokens a line; the per-call cap
# pointer is in reference/structure.md#cumulative-sections-and-provenance-tags ("Size").
# As of 2026-10-11. Recheck when that "Size" entry changes its pointer or threshold.
MAX_READABLE_LINES = 300
UNVERIFIED_PRED_RE = re.compile(r"^UNVERIFIED \(predecessor failed validation\):\s*")
UNVERIFIED_RE = re.compile(r"\bUNVERIFIED\b")
SETTLE_RE = re.compile(r"\(settle: [^\n]*\S[^\n]*\)")
TRAILING_SETTLE_RE = re.compile(r"\s*\(settle: [^\n]*\)\s*$")
CARRY_SETTLE = "<!-- UNVERIFIED (predecessor failed validation) marks in this section: {settle} -->"
CARRY_SETTLE_RE = re.compile(
    r"^<!-- UNVERIFIED \(predecessor failed validation\) marks in this section: \(settle: .+\) -->$"
)
FILL_MARK = "<!-- FILL"
FILL_SLOT_RE = re.compile(r"<!-- FILL: (\S+) — (.*?) -->")
VERBATIM_SLOTS = frozenset(
    {
        "goal", "opening-ask", "intent", "vision", "amended", "goal-new",
        "commands", "rules", "rules-new", "preferences", "preferences-new",
        "goal-first", "goal-after", "below-rail",
    }
)
VERBATIM_SECTIONS = frozenset(
    {"Original goal", "Current rules", "Standing preferences", "Pending commands"}
)
COPY_LINE = "`/clear`, then copy everything between the dashed lines:"
LAUNCH_CHECKOUT = "New session checkout: "
LAUNCH_COMMAND = "New session command: "
PROFILE_RELAUNCH_RE = re.compile(
    r"The next phase runs in another plugin profile: exit this session, "
    r"start the next one with `([^`]+)`, then in it:"
)
GOAL_COPY_LINE = (
    "Type `/goal ` (with a trailing space), then paste everything between the dashed "
    "lines. Confirm the `◎ /goal active` indicator appears after you send it; if it "
    "is missing, redo it:"
)
MD_COPY_LINE = "Run `/clear`, then paste this:"
MD_GOAL_COPY_LINE = (
    "Type `/goal ` (with a trailing space), then paste this. Confirm the `◎ /goal active` "
    "indicator appears after you send it; if it is missing, redo it:"
)
GOAL_CONDITION_MAX = 4000
DIRECTIVE_CLAUSE = "invoke /session-flow:handoff via the Skill tool"
DIRECTIVE_TAIL = (
    "confirm its Original goal still governs the remaining next steps, raise its due "
    "Reminders, then continue them and re-establish its Environment last. For the next "
    "save-point invoke /session-flow:handoff via the Skill tool; never write a handoff "
    "file free-hand."
)
RECURRING_RE = re.compile(r"^- \[(loop|cron|monitor|off-thread)\] ")
LOOP_COUNT_RE = re.compile(r"prompt \((\d+) lines\):$")
RESTORE_MANUAL = "restore: manual"
SINCE_RE = re.compile(r" · since (\S+) ·")
HANDOFF_TS_RE = re.compile(r"^(\d{8}T\d{6}Z)-handoff-")
REDACTED_MARK = "<REDACTED"
RECURRING_SHAPE = (
    "one entry per recurring item: '- [loop] every <interval|self-paced> · since <UTC ISO> · "
    "prompt (<L> lines):' or '- [cron] <expression> · recurring|once · since <UTC ISO> · "
    "prompt (<L> lines):' with the prompt verbatim on the next <L> indented lines, "
    "'- [monitor] <description> · since <UTC ISO> · command: `<cmd>`', and "
    "'- [off-thread] <kind> <name>: <state read this turn> · kept because <why>' or the single "
    "line '- Off-thread work: none recorded.'; a command or prompt that lost text to redaction "
    "ends with '· restore: manual (held a secret; re-create from <source>)'; prefer an "
    "environment-variable reference to a secret in a command"
)
STANDING_THEN = " then @"
STANDING_PAGED = " in pages with the Read tool's offset and limit (over one Read page)"
STANDING_TYPE = "handoff-standing-rules"
POINTER_PREFIX = "- Retired entries: "
INDEX_FILE = "retired-index.md"
INDEX_PREFIX = "- Retired entries index: "
INDEX_TYPE = "handoff-retired-index"
INDEX_NOTE = "Each line names a hop file and the heading in it that lists retired entries, each with its reason."
PRIOR_SESSION_RE = re.compile(r"^Prior session: ([0-9A-Fa-f-]{36})\.$")
THEN_RE = re.compile(r"^Then: /[A-Za-z0-9_:.-]+$")
THIS_SESSION_RE = re.compile(r"^did: .+ · left: .+$")
RESCAN_PREFIX = "Re-scan: "
NEXT_CLOSED = "Next: none (closed)"
PREVIOUS_GONE = ("missing", "unreadable")
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


def _die(code: int, message: str) -> int:
    print(f"error: {message}", file=sys.stderr)
    return code


def _universal(text: str) -> str:
    """`text` as `Path.read_text` returns it: every `\\r\\n` and lone `\\r` a `\\n`."""
    return text.replace("\r\n", "\n").replace("\r", "\n")


def _text_lines(text: str) -> list[str]:
    return _universal(text).splitlines()


def _read_lines(path: Path) -> list[str]:
    return _text_lines(path.read_text(encoding="utf-8"))


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
    size: int | None = None

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


def legacy_chain(pred: Doc, limit: int = 1000) -> list[str]:
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
    return _doc_from_lines(path, _read_lines(path))


def _doc_from_lines(path: Path, lines: list[str]) -> Doc:
    fm = read_frontmatter(lines)
    return Doc(
        path=path,
        lines=lines,
        frontmatter=fm.values,
        chain=fm.chain,
        has_frontmatter=fm.present,
        body_start=fm.body_start,
        sections=section_spans(lines, fm.body_start),
    )


def _trim_blank(lines: list[str]) -> list[str]:
    start, end = 0, len(lines)
    while start < end and not lines[start].strip():
        start += 1
    while end > start and not lines[end - 1].strip():
        end -= 1
    return lines[start:end]


def _ends_opening_ask(line: str) -> bool:
    return line.startswith("**") or bool(BULLET_RE.match(line))


@dataclass
class Entry:
    first_index: int
    lines: list[str]
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
        text = self.text
        return not text or text.startswith(("None.", "None ("))

    @property
    def normalized(self) -> str:
        text = TAG_RE.sub("", self.text)
        if UNVERIFIED_PRED_RE.match(text):
            text = TRAILING_SETTLE_RE.sub("", UNVERIFIED_PRED_RE.sub("", text))
        return " ".join(text.split())


def parse_entries(body: list[str]) -> list[Entry]:
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


class CheckKind(Enum):
    SIZE = "size"
    ORDER = "order"
    CARRY = "carry"
    POINTER = "pointer"
    ID_REUSE = "id_reuse"
    UNVERIFIED = "unverified"
    MALFORMED = "malformed"
    TRANSCRIPT = "transcript"
    OVER_CAP_BINDING = "over_cap_binding"
    SLOT_SIZE = "slot_size"


CONTENT_KINDS = frozenset({CheckKind.ORDER, CheckKind.MALFORMED})
SIZE_KINDS = frozenset(
    {CheckKind.SIZE, CheckKind.OVER_CAP_BINDING, CheckKind.SLOT_SIZE}
)


@dataclass(frozen=True)
class Finding:
    level: str
    kind: CheckKind
    text: str


class Findings:
    def __init__(self) -> None:
        self.items: list[Finding] = []
        self.unvalidated = False

    def carry(self, soft: bool) -> Callable[[str], None]:
        """The reporter for a predecessor-derived check: WARN when `soft`."""
        return functools.partial(self.warn if soft else self.fail, kind=CheckKind.CARRY)

    def warn(self, message: str, kind: CheckKind = CheckKind.MALFORMED) -> None:
        self.items.append(Finding("WARN", kind, message))

    def fail(self, message: str, kind: CheckKind = CheckKind.MALFORMED) -> None:
        self.items.append(Finding("FAIL", kind, message))

    @property
    def fails(self) -> list[Finding]:
        return [x for x in self.items if x.level == "FAIL"]

    @property
    def failed(self) -> bool:
        return bool(self.fails)


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


def _directive_paths(directive: str) -> tuple[str | None, str]:
    head = directive[len("Read @") :].split(",", 1)[0].strip()
    if STANDING_THEN not in head:
        return None, head
    first, hot = head.split(STANDING_THEN, 1)
    return first.removesuffix(STANDING_PAGED).strip(), hot.strip()


def _check_standing_directive(doc: Doc, f: Findings, standing: str | None) -> None:
    held = doc.frontmatter.get("standing_rules")
    if held and standing is None:
        f.fail(
            f"Resume prompt: standing_rules is set, so the 'Read @' directive loads {held} first ('Read @<standing-rules file>{STANDING_THEN}<this file>, …')"
        )
    elif standing is not None and not held:
        f.fail(
            "Resume prompt: the 'Read @' directive loads a standing-rules file, but no standing_rules frontmatter key names one"
        )
    elif standing is not None and not _same_file(standing, doc.path.parent / held):
        if standing.endswith("/" + held):
            f.warn(
                f"Resume prompt: 'Read @' standing-rules path {standing!r} is under another directory (relocated chain; emit substitutes the real path)"
            )
        else:
            f.fail(
                f"Resume prompt: 'Read @' standing-rules path {standing!r} does not name this chain's {held}"
            )


def _rail_regions(body: list[str], rails: list[int]):
    previous = 0
    for top, bottom in zip(rails[::2], rails[1::2]):
        yield [line.strip() for line in body[previous:top]], body[top + 1 : bottom], bottom
        previous = bottom + 1


def _check_rails_block(doc: Doc, f: Findings, session_id: str) -> None:
    body = doc.section("Resume prompt")
    if body is None:
        return
    rails = [i for i, line in enumerate(body) if RAIL_RE.match(line.strip())]
    if len(rails) not in (2, 4):
        detail = f"found {len(rails)}"
        ascii_rails = sum(1 for line in body if ASCII_RAIL_RE.match(line.strip()))
        if ascii_rails:
            detail += f", plus {ascii_rails} ASCII rail line(s); rails are U+2500 only"
        f.fail(
            f"Resume prompt: two U+2500 rails (resume region) or four (goal region plus resume region) required ({detail})"
        )
        return
    between: list[str] | None = None
    resume_bottom = 0
    goals: list[list[str]] = []
    for above, region, bottom in _rail_regions(body, rails):
        if any(not line.strip() for line in region):
            f.fail("Resume prompt: blank line between the rails")
        region = [line for line in region if line.strip()]
        if any(line.lstrip().startswith("/goal") for line in region):
            f.fail(
                "Resume prompt: a line between the rails starts with '/goal'; the user types the command, the region holds the condition only"
            )
        if COPY_LINE in above:
            if between is not None:
                f.fail("Resume prompt: more than one resume region")
            between, resume_bottom = region, bottom
        elif GOAL_COPY_LINE in above:
            goals.append(region)
        else:
            f.fail(
                f"Resume prompt: no copy instruction line above a top rail (resume region {COPY_LINE!r}, goal region {GOAL_COPY_LINE!r})"
            )
    if len(goals) > 1:
        f.fail("Resume prompt: more than one goal region")
    if between is None:
        f.fail(
            f"Resume prompt: copy instruction line {COPY_LINE!r} missing above the resume region's top rail"
        )
        return
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
    if not between or not between[0].startswith("Read @"):
        f.fail(
            "Resume prompt: first line between the resume region's rails must be the 'Read @' directive"
        )
        return
    directive = between[0]
    standing_part, path_part = _directive_paths(directive)
    _check_standing_directive(doc, f, standing_part)
    if "\\" in path_part or not (
        path_part.startswith("/") or re.match(r"^[A-Za-z]:/", path_part)
    ):
        f.fail(
            f"Resume prompt: 'Read @' path must be absolute and forward-slash (got {path_part!r})"
        )
    elif not _same_file(path_part, doc.path):
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
    pos = 1
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
    if not any(resume_line in line for line in body[resume_bottom + 1 :]):
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
                f.carry(pred_soft)(
                    f"{title}: predecessor entry dropped (keep it in place or under "
                    f"'Superseded:', never delete): {entry.text[:60]!r}"
                )


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
    hop_text: str | None = None,
    standing: str | None = None,
    index: str | None = None,
) -> tuple[Findings, int]:
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
    if shape > NEWEST_SHAPE:
        f.fail(
            f"handoff_shape {shape} is newer than this validator knows ({NEWEST_SHAPE}): read it, do not rewrite it; update session-flow to validate it"
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
    gone = fm.get("previous_status")
    if gone is not None and (previous is None or gone not in PREVIOUS_GONE):
        f.fail(
            f"frontmatter: previous_status is {' or '.join(PREVIOUS_GONE)} beside a previous_handoff (got {gone!r})"
        )
        gone = None
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
            elif (
                gone is not None
                and _readable(pred_path)
                and not _starts_afresh(doc, previous)
            ):
                f.fail(
                    f"frontmatter: previous_status says predecessor {previous!r} was {gone}, but it is beside this file and readable, and this file does not start a fresh chain the way `new` does at a broken link; drop previous_status so the checks against the predecessor run"
                )
            elif gone is not None:
                f.warn(
                    f"frontmatter: predecessor {previous!r} was {gone} when this file was written (previous_status), so the checks against it are skipped; the chain is broken at that link"
                )
            elif not pred_path.is_file():
                copy = _shrunk_copy(doc, previous)
                if copy is None:
                    f.fail(
                        f"frontmatter: previous_handoff {previous!r} not found beside this file"
                    )
                else:
                    f.warn(
                        f"frontmatter: predecessor {previous!r} was removed from this finished chain; its copy is in this hop's file {copy}, so the checks against it are skipped"
                    )
            elif not shallow:
                try:
                    pred = parse_doc(pred_path)
                except (OSError, UnicodeDecodeError) as exc:
                    f.fail(f"predecessor {previous!r} unreadable: {exc}")
    content = doc
    if shape in HOP_FILE_SHAPES:
        content = _validate_shape3(
            doc, f, previous, pred, projects_root, hop_text, standing, index
        )
    else:
        _validate_shape2(doc, f, previous, pred, projects_root)
    if (_fm_int(doc, "checks") or 0) >= UNVERIFIED_SETTLE_FROM:
        unread = shallow and previous is not None and gone is None
        _check_unverified(content, f, SHAPES[shape].carried, pred, unread, hop_text)

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
                f.fail(
                    f"transcript: {transcript}{located} (--strict-transcript)",
                    CheckKind.TRANSCRIPT,
                )
            else:
                f.warn(f"transcript: {transcript}{located}", CheckKind.TRANSCRIPT)
        elif not Path(transcript).is_file():
            f.fail(
                f"transcript: stated path does not exist: {transcript}",
                CheckKind.TRANSCRIPT,
            )

    for i, line in enumerate(doc.lines, 1):
        for pattern, marker in SECRET_SHAPES:
            if pattern.search(line):
                f.warn(
                    f"line {i}: secret-shaped string ({marker}); redact to a shape marker or rule it benign"
                )
                break

    return f, 1 if f.failed else 0


def _shrunk_copy(doc: Doc, previous: str) -> str | None:
    if doc.shape not in HOP_FILE_SHAPES or _successor(doc.path) is not None:
        return None
    span = _next_span(doc)
    root, hop = doc.frontmatter.get("chain_root", ""), _fm_int(doc, "hop")
    if span is None or doc.lines[span[0]] != NEXT_CLOSED:
        return None
    if not HANDOFF_NAME_RE.match(root) or hop is None:
        return None
    own = hop_file_path(
        doc.path.parent, root, hop, doc.frontmatter.get("session_id", "")
    )
    try:
        held = parse_doc(own)
    except (OSError, UnicodeDecodeError):
        return None
    fm = held.frontmatter
    if (
        fm.get("type") != ARCHIVE_TYPE
        or fm.get("moved_from") != previous
        or not held.sections
    ):
        return None
    return own.relative_to(doc.path.parent).as_posix()


def _validate_shape2(
    doc: Doc,
    f: Findings,
    previous: str | None,
    pred: Doc | None,
    projects_root: Path | None,
) -> None:
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
            pred_soft = _pred_failed(doc, pred, previous, projects_root, f)
            expected_chain = pred.chain + [doc.basename]
            if doc.chain != expected_chain:
                message = f"frontmatter: chain must be the predecessor's chain plus this file ({expected_chain})"
                f.carry(pred_soft)(message)
        else:
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
                report = f.carry(pred_soft)
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
            f"size: {len(doc.lines)} lines exceeds {MAX_READABLE_LINES}; a single Read may truncate it (cumulative sections are carried verbatim, so trim by moving resolved entries under Superseded or promoting them to a committed doc)",
            CheckKind.SIZE,
        )


def _check_headings(doc: Doc, f: Findings, expected: tuple[str, ...]) -> None:
    titles = doc.titles
    if titles != list(expected):
        for i, want in enumerate(expected):
            found = titles[i] if i < len(titles) else "<missing>"
            if found != want:
                f.fail(
                    f"headings: expected '## {want}' at position {i + 1}, found '## {found}' ({len(expected)} sections in order, '## Resume prompt' last)",
                    CheckKind.ORDER,
                )
                break
        else:
            f.fail(
                f"headings: extra section(s) after '## Resume prompt': {titles[len(expected) :]}",
                CheckKind.ORDER,
            )
    for title, start, end in doc.sections:
        if title in expected and not any(
            line.strip() for line in doc.lines[start + 1 : end]
        ):
            f.fail(f"{title}: empty; write 'None.' plus a reason")


def _moved_lines(
    doc: Doc, title: str, start: int, end: int, hop_text: str | None
) -> tuple[list[str], int, int, str] | None:
    held = [line for line in doc.lines[start + 1 : end] if line.strip()]
    pointer = MovePointer.parse(held[0]) if len(held) == 1 else None
    if pointer is None or not pointer.moves(title):
        return None
    base = doc.path.parent
    fm = doc.frontmatter
    own = hop_file_path(
        base,
        fm.get("chain_root", ""),
        _fm_int(doc, "hop") or 0,
        fm.get("session_id", ""),
    )
    if hop_text is not None and base / pointer.file == own:
        text = hop_text
    else:
        try:
            text = (base / pointer.file).read_text(encoding="utf-8", errors="replace")
        except OSError:
            return None
    lines = text.splitlines()
    at, stop = next(
        ((a, e) for name, a, e in section_spans(lines, 0) if name == pointer.heading),
        (None, None),
    )
    if at is None or stop is None:
        return None
    return lines, at + 1, stop, f" of {pointer.file}"


def _check_unverified(
    doc: Doc,
    f: Findings,
    carried: tuple[str, ...],
    pred: Doc | None,
    unread: bool = False,
    hop_text: str | None = None,
) -> None:
    hop = (_fm_int(doc, "hop") or 0) if doc.shape in HOP_FILE_SHAPES else len(doc.chain)
    for title, start, end in doc.sections:
        if title in carried:
            continue
        lines, first, place = doc.lines, start + 1, ""
        moved = _moved_lines(doc, title, start, end, hop_text)
        if moved is not None:
            lines, first, end, place = moved
        body = lines[first:end]
        exempt: set[int] = set()
        if any(CARRY_SETTLE_RE.match(line.strip()) for line in body):
            held = (
                None
                if unread
                else {
                    e.normalized
                    for e in parse_entries(
                        (
                            pred
                            and follow(
                                pred.section(title) or [], title, pred.path.parent
                            )
                        )
                        or []
                    )
                }
            )
            for entry in parse_entries(body):
                rest = TAG_RE.sub("", entry.text)
                if (
                    entry.tag is not None
                    and entry.tag < hop
                    and UNVERIFIED_PRED_RE.match(rest)
                    and (held is None or entry.normalized in held)
                ):
                    exempt.add(first + entry.first_index)
        for i in range(first, end):
            line = lines[i]
            if i in exempt:
                rest = TAG_RE.sub("", BULLET_RE.sub("", line.strip(), count=1))
                line = UNVERIFIED_PRED_RE.sub("", rest)
            if any(
                not SETTLE_RE.search(line, m.end())
                for m in UNVERIFIED_RE.finditer(line)
            ):
                f.fail(
                    f"{title}: line {i + 1}{place} marks a claim UNVERIFIED without naming what settles it; end that line with '(settle: <command or URL>)': {lines[i].strip()[:60]!r}",
                    CheckKind.UNVERIFIED,
                )


def _downgrading_fail(findings: Findings, checks: int) -> Finding | None:
    return next(
        (
            x
            for x in findings.fails
            if checks < CONTENT_ONLY_DOWNGRADE_FROM or x.kind in CONTENT_KINDS
        ),
        None,
    )


def _pred_failed(
    doc: Doc,
    pred: Doc,
    previous: str | None,
    projects_root: Path | None,
    f: Findings,
) -> bool:
    findings, _ = validate_doc(pred, projects_root, False, shallow=True)
    culprit = _downgrading_fail(findings, _fm_int(doc, "checks") or 0)
    if culprit is not None:
        f.warn(
            f"predecessor {previous!r} failed validation ({culprit.text}); predecessor-derived checks downgraded to WARN"
        )
    return culprit is not None


def _fm_int(doc: Doc, key: str) -> int | None:
    try:
        return int(doc.frontmatter.get(key, ""))
    except ValueError:
        return None


def _stem(name: str) -> str:
    return name[: -len(".md")] if name.endswith(".md") else name


def _readable(path: Path) -> bool:
    try:
        parse_doc(path)
    except (OSError, UnicodeDecodeError):
        return False
    return True


def _starts_afresh(doc: Doc, previous: str) -> bool:
    return (
        doc.shape in HOP_FILE_SHAPES
        and doc.frontmatter.get("chain_root") == doc.basename
        and _fm_int(doc, "hop") == 1
        and _fm_int(doc, "archive_from") == 1
        and previous != doc.basename
    )


def _chain_position(pred: Doc | None, name: str) -> tuple[str, int, int]:
    if pred is None:
        return name, 1, 1
    if pred.shape in HOP_FILE_SHAPES:
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


def _id_entries(doc: Doc, spec: IdSpec) -> list[tuple[int | None, Entry, str]]:
    return [
        (id_of(spec.prefix, entry.text)[0], entry, title)
        for title in spec.sections
        for entry in parse_entries(doc.section(title) or [])
        if not entry.exempt
    ]


def _retired_ids(archived: str, spec: IdSpec) -> dict[int, str]:
    found: dict[int, str] = {}
    for lines, reason in retired_listings(archived, spec.retired_heading):
        n, rest = id_of(spec.prefix, BULLET_RE.sub("", lines[0].strip(), count=1))
        if n is not None:
            found[n] = rest.strip() if reason is None else reason
    return found


def _next_id(pred: Doc | None, spec: IdSpec) -> int:
    if pred is None:
        return 1
    floor, ids = None, []
    if pred.shape in HOP_FILE_SHAPES:
        floor = _fm_int(pred, spec.floor_key)
        ids = [n for n, _, _ in _id_entries(pred, spec) if n is not None]
    if floor is None and spec != RULES:
        text = "\n".join(pred.lines)
        ids += [int(n) for n in re.findall(rf"\b{spec.prefix}(\d+)\b", text)]
    return max(floor or 1, max(ids, default=0) + 1)


def _amendment_spans(
    lines: list[str],
) -> tuple[list[tuple[int, int]], list[str]]:
    spans: list[list[int]] = []
    plain: list[str] = []
    inside = False
    for i, line in enumerate(lines):
        if AMENDMENT_RE.match(line):
            spans.append([i, i + 1])
            inside = True
        elif inside and line.strip() and not line.startswith(("**", "Opening ask:")):
            spans[-1][1] = i + 1
        else:
            inside = False
            if line.strip():
                plain.append(line)
    return [(a, b) for a, b in spans], plain


def _entry_units(doc: Doc, title: str) -> tuple[list[tuple[str, ...]], list[str]]:
    lines = follow(doc.section(title) or [], title, doc.path.parent) or []
    if title == "Original goal":
        spans, plain = _amendment_spans(lines)
        return [tuple(lines[a:b]) for a, b in spans], plain
    return [
        (line,) for line in lines if line.strip() and not line.startswith(FOLD_PREFIX)
    ], []


def _folds(line: str, hop: int) -> bool:
    m = TRAIL_TAG_RE.match(line)
    newest = int(re.findall(r"\d+", m.group(1))[-1]) if m else None
    return newest is not None and hop - newest >= DIRECTION_HOPS_KEPT


def _id_specs(shape: int | None) -> tuple[IdSpec, ...]:
    """The id families a file of `shape` holds; shape 3's for a shape with none."""
    spec = SHAPES.get(shape) if isinstance(shape, int) else None
    return spec.id_specs if spec is not None and spec.id_specs else S3.id_specs


def _family(prefix: str) -> IdSpec:
    return next(spec for spec in ID_SPECS if spec.prefix == prefix)


def _converted_commands(pred: Doc | None, hop: int, date: str) -> list[str]:
    """A shape-4 predecessor's Pending commands as `user · when now` reminders,
    `None.` lines left out, so no command drops when a chain moves to shape 5."""
    if pred is None or REMINDERS in _id_specs(pred.shape):
        return []
    held = [
        entry.text
        for entry in parse_entries(pred.section("Pending commands") or [])
        if not entry.exempt
    ]
    return [
        f"- [M{n}] user · when now · {text} · added h{hop} {date[:10]}"
        for n, text in enumerate(held, start=1)
    ]


def _check_reminders(doc: Doc, f: Findings) -> None:
    if REMINDERS not in _id_specs(doc.shape):
        return
    open_ids: list[str] = []
    for n, entry, _ in _id_entries(doc, REMINDERS):
        if n is None:
            continue
        open_ids.append(f"[M{n}]")
        if not REMINDER_RE.match(entry.text):
            f.fail(
                f"Reminders: [M{n}] is not {REMINDER_SHAPE}: {entry.text[:60]!r}"
            )
    span = _next_span(doc)
    if open_ids and span is not None and doc.lines[span[0]] == NEXT_CLOSED:
        f.warn(
            f"Reminders: this handoff is closed ({NEXT_CLOSED}) but {', '.join(open_ids)} are not retired; raise each in the closing turn, then retire it 'raised at chain close', or on an unattended run list each user or 'at close' entry under Needs you"
        )


def _recurring_entries(lines: list[str]) -> list[list[str]]:
    """Each `[loop]`, `[cron]`, `[monitor]` or `[off-thread]` entry with its indented body."""
    entries: list[list[str]] = []
    current: list[str] | None = None
    for line in lines:
        if RECURRING_RE.match(line):
            current = [line]
            entries.append(current)
        elif current is not None and line.startswith((" ", "\t")) and line.strip():
            current.append(line)
        else:
            current = None
    return entries


def _written_at(name: str) -> datetime | None:
    match = HANDOFF_TS_RE.match(name)
    if match is None:
        return None
    return datetime.strptime(match.group(1), "%Y%m%dT%H%M%SZ").replace(
        tzinfo=timezone.utc
    )


def _check_recurring(doc: Doc, f: Findings) -> None:
    previous_at = _written_at(doc.frontmatter.get("previous_handoff") or "")
    for entry in _recurring_entries(doc.section("Environment to re-establish") or []):
        head = entry[0]
        text = "\n".join(entry)
        if REDACTED_MARK in text and RESTORE_MANUAL not in text:
            f.fail(
                f"Environment to re-establish: {head[:60]!r} lost text to redaction and must end with '· {RESTORE_MANUAL} (held a secret; re-create from <source>)', so the resumed session never re-arms it"
            )
        if head.startswith(("- [loop] ", "- [cron] ")):
            count = LOOP_COUNT_RE.search(head)
            if count is None or int(count.group(1)) != len(entry) - 1:
                f.warn(
                    f"Environment to re-establish: {head[:60]!r} needs 'prompt (<L> lines):' with the prompt on exactly the next <L> indented lines"
                )
        since = SINCE_RE.search(head)
        started = _parse_now(since.group(1)) if since else None
        if previous_at and started and started < previous_at:
            f.warn(
                f"Environment to re-establish: {head[:60]!r} runs since before the previous handoff was written, so it was carried across more than one hop; the resumed session shows it and re-arms it only after the user confirms"
            )


def _carries(pred: Doc | None, spec: IdSpec) -> bool:
    if spec == RULES or pred is None or pred.shape not in HOP_FILE_SHAPES:
        return False
    entries = _id_entries(pred, spec)
    return (
        _fm_int(pred, spec.floor_key) is not None
        and bool(entries)
        and all(n is not None for n, _, _ in entries)
    )


def _chain_hop_paths(pred: Doc, start: int):
    cursor: Doc | None = pred
    seen: set[str] = set()
    while (
        cursor is not None
        and cursor.shape in HOP_FILE_SHAPES
        and cursor.basename not in seen
    ):
        seen.add(cursor.basename)
        hop = _fm_int(cursor, "hop")
        root = cursor.frontmatter.get("chain_root", "")
        if hop is None or hop < start or not HANDOFF_NAME_RE.match(root):
            break
        yield (
            cursor,
            hop_file_path(
                cursor.path.parent, root, hop, cursor.frontmatter.get("session_id", "")
            ),
        )
        previous = cursor.frontmatter.get("previous_handoff")
        cursor = _sibling(cursor.path.parent, previous) if previous else None


def _retire_reasons(archived: str) -> list[str]:
    return [
        reason
        for heading in POINTED_HEADINGS
        for _, reason in retired_listings(archived, heading)
        if reason
    ]


def _check_retired_entries(
    doc: Doc,
    f: Findings,
    pred: Doc,
    start: int,
    rel: str,
    archived: str | None,
    report,
) -> None:
    text = archived or ""
    hop = _fm_int(doc, "hop") or 0

    def fold_pointed(d: Doc) -> bool:
        title = "Direction changes"
        body = follow(d.section(title) or [], title, d.path.parent) or []
        return any(line.startswith(FOLD_PREFIX) for line in body)

    folded = fold_pointed(doc)
    if fold_pointed(pred) and not folded:
        report(
            f"Direction changes: the predecessor's '{FOLD_PREFIX.strip()}' pointer line is missing; keep the line `new` wrote, so the folded lines stay reachable"
        )
    for title, heading in S3.retired_entry_sections.items():
        pred_units, pred_plain = _entry_units(pred, title)
        own_units, own_plain = _entry_units(doc, title)
        remaining = iter(own_plain)
        for line in pred_plain:
            if not any(line == own for own in remaining):
                report(
                    f"{title}: the predecessor's goal lines (quote, intent, vision, opening ask) stay byte for byte and in order; missing or changed: {line[:60]!r}"
                )
                break
        listed = retired_listings(text, heading)
        reasoned = Counter(lines for lines, reason in listed if reason)
        unreasoned = {lines for lines, reason in listed if reason == ""}
        cursor = 0
        for unit in pred_units:
            at = next(
                (i for i in range(cursor, len(own_units)) if own_units[i] == unit),
                None,
            )
            if at is not None:
                cursor = at + 1
            elif reasoned[unit]:
                reasoned[unit] -= 1
            elif unit in own_units:
                report(
                    f"{title}: predecessor entry moved out of order (carried entries keep their order): {unit[0][:60]!r}"
                )
            elif title == "Direction changes" and _folds(unit[0], hop):
                if not folded:
                    report(
                        f"{title}: predecessor line folded out without the '{FOLD_PREFIX.strip()}' pointer line `new` writes; keep that line: {unit[0][:60]!r}"
                    )
            elif unit in unreasoned:
                report(
                    f"{title}: predecessor entry listed under '## {heading}' in {rel} with an empty 'Retired:' reason: {unit[0][:60]!r}"
                )
            else:
                report(
                    f"{title}: predecessor entry left this file without a retirement; keep it here, or retire it through the 'retire' list of fill or amend, which lists it in {rel} under '## {heading}' with its reason: {unit[0][:60]!r}"
                )
    rules = {rid for rid, _, _ in _id_entries(doc, RULES) if rid is not None}
    for reason in _retire_reasons(text):
        m = CODIFIED_RE.search(reason)
        if m and int(m.group(1)) not in rules:
            f.fail(
                f"archive: a retirement in {rel} reads 'codified in [R{m.group(1)}]', but [R{m.group(1)}] is not in this file",
                CheckKind.POINTER,
            )
    retired_rules = {
        rid: reason
        for rid, reason in _retired_ids(text, RULES).items()
        if not NEW_HOME_RE.search(reason)
    }
    if not retired_rules:
        return
    pointed: set[int] = set()
    for _, path in _chain_hop_paths(pred, start):
        try:
            earlier = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for reason in _retire_reasons(earlier):
            pointed.update(int(n) for n in re.findall(r"\[R(\d+)\]", reason))
    for rid in sorted(pointed & set(retired_rules)):
        f.warn(
            f"archive: [R{rid}] is retired in {rel}, but an earlier retired entry points at it; name the rule's new home in its reason (another [R<n>], 'promoted to <file>', or a path)"
        )


def _squash(text: str) -> str:
    return " ".join(text.split())


def _section_lines(doc: Doc, title: str) -> list[str]:
    return _trim_blank(doc.section(title) or [])


def _section_bytes(doc: Doc, titles: tuple[str, ...]) -> int:
    return sum(
        len(line.encode("utf-8")) + 1
        for name, start, end in doc.sections
        if name in titles
        for line in doc.lines[start:end]
    )


def _cap_state(doc: Doc) -> tuple[int, int]:
    size = len(doc.path.read_bytes()) if doc.size is None else doc.size
    return size, _section_bytes(doc, SHAPES.get(doc.shape, S3).binding)


def _size_parts(doc: Doc) -> tuple[int, int, int, int]:
    size, core = _cap_state(doc)
    fence = sum(
        len(line.encode("utf-8")) + 1
        for line in doc.lines[: doc.body_start]
        if line.strip() == "---" or line.split(":", 1)[0] in FRONTMATTER_KEYS_3
    )
    carried = fence + _section_bytes(doc, S3.carried)
    return size, core, carried, size - core - carried


def _size_text(core: int, carried: int, written: int) -> str:
    return f"core {core} bytes, carried {carried} bytes (frontmatter, {', '.join(S3.carried)}), written non-core {written} bytes"


CORE_NEVER_MOVES = (
    f"the core ({', '.join(S3.binding)}) never moves and no rule leaves to meet the cap"
)


def _size_finding_4(doc: Doc, rel: str) -> tuple[str, str] | None:
    size, core, carried, written = _size_parts(doc)
    spec = SHAPES[doc.shape]
    cap = spec.cap_bytes or HOT_FILE_MAX_BYTES
    if core + carried > cap:
        name, held = max(
            ((title, _section_bytes(doc, (title,))) for title in spec.binding),
            key=lambda pair: pair[1],
        )
        return (
            "OVER-CAP",
            f"OVER-CAP: {name} holds {held} bytes, and the binding and carried sections alone are over the {cap}-byte hot-file cap ({_size_text(core, carried, written)}); shrink {name}: retire what no longer binds through the 'retire' list, and leave settled history in {rel} with a pointer from Review before you continue",
        )
    if size > cap:
        return (
            "FAIL",
            f"size: {size} bytes is over the {cap}-byte hot-file cap; move {', '.join(spec.movable)} content into {rel} with a pointer ({_size_text(core, carried, written)})",
        )
    return None


def _size_finding(doc: Doc, rel: str) -> tuple[str, str] | None:
    if fitted(doc.shape):
        return _size_finding_4(doc, rel)
    size, core, carried, written = _size_parts(doc)
    parts = _size_text(core, carried, written)
    if size > READ_CAP_BYTES:
        fix = (
            f"move written non-core content into {rel}"
            if core + carried <= READ_CAP_BYTES
            else "the core and carried sections alone are over it, so no edit the writer may make passes"
        )
        return (
            "FAIL",
            f"size: {size} bytes is over the {READ_CAP_BYTES}-byte Read page cap, so the resume prompt's default Read returns only the first page, with a PARTIAL view notice; {fix} ({parts})",
        )
    if size <= HOT_FILE_MAX_BYTES:
        return None
    if core > HOT_FILE_MAX_BYTES:
        return (
            "UNVALIDATED",
            f"the core sections alone are over the {HOT_FILE_MAX_BYTES}-byte hot-file cap ({parts}); {CORE_NEVER_MOVES}, so this file stands unvalidated",
        )
    if core + carried > HOT_FILE_MAX_BYTES:
        return (
            "UNVALIDATED",
            f"the core plus carried content is over the {HOT_FILE_MAX_BYTES}-byte hot-file cap ({parts}); the carried sections are written by `new` and {CORE_NEVER_MOVES}, so this file stands unvalidated; do not cut written sections for it",
        )
    return (
        "FAIL",
        f"size: {size} bytes is over the {HOT_FILE_MAX_BYTES}-byte hot-file cap; move written non-core content into {rel} before validating ({parts}); {CORE_NEVER_MOVES}",
    )


def _sibling(directory: Path, name: str) -> Doc | None:
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


def _check_decision_fields(doc: Doc, f: Findings) -> None:
    spec = S3.id_spec("D")
    for n, entry, title in _id_entries(doc, spec):
        rest = id_of(spec.prefix, entry.text)[1]
        tag = DECISION_TAG_RE.match(rest)
        if not tag:
            continue
        fields = rest.split(f" {REWRITE_MARK} h")[0]
        labels = "|".join(DECISION_FIELDS)
        missing = [
            name
            for name in DECISION_FIELDS
            if not re.search(rf"\b{name}:\s*(?!(?:{labels}):)[^;\s]", fields)
        ]
        if missing:
            ref = f"D{n}" if n is not None else repr(entry.text[:60])
            f.fail(
                f"{title}: [{tag.group(1)}] decision lacks "
                f"{', '.join(name + ':' for name in missing)}; "
                f"add buys:/surface:/cost: to {ref}"
            )


def _standing_pointed(doc: Doc) -> dict[str, tuple[str, str]]:
    found: dict[str, tuple[str, str]] = {}
    for title, start, end in doc.sections:
        if title not in STANDING_SECTIONS:
            continue
        pointer = standing_pointer(doc.lines[start + 1 : end])
        if pointer is not None:
            found[title] = pointer
    return found


def _standing_doc(doc: Doc, text: str) -> Doc | None:
    pointed = _standing_pointed(doc)
    if not pointed:
        return doc
    lines = list(doc.lines)
    for title, start, end in sorted(doc.sections, key=lambda s: -s[1]):
        if title not in pointed:
            continue
        held = section_of(text, title)
        if held is None:
            return None
        lines[start + 1 : end] = ["", *_trim_blank(held), ""]
    return replace(_doc_from_lines(doc.path, lines), size=doc.size)


def _standing_text(doc: Doc) -> tuple[str | None, str]:
    handoffs = doc.path.parent
    successor = _successor(doc.path)
    nxt = None
    if successor is not None:
        try:
            nxt = parse_doc(successor)
        except (OSError, UnicodeDecodeError):
            nxt = None
    if nxt is not None and nxt.shape in HOP_FILE_SHAPES:
        source = hop_file_path(
            handoffs,
            nxt.frontmatter.get("chain_root", ""),
            _fm_int(nxt, "hop") or 0,
            nxt.frontmatter.get("session_id", ""),
        )
    else:
        source = handoffs / doc.frontmatter.get("standing_rules", "")
    rel = source.relative_to(handoffs).as_posix()
    try:
        return source.read_text(encoding="utf-8"), rel
    except (OSError, UnicodeDecodeError):
        return None, rel


def _standing_header(doc: Doc) -> list[str]:
    fm = doc.frontmatter
    return [
        "---",
        f"type: {STANDING_TYPE}",
        f"chain_root: {fm.get('chain_root', '')}",
        f"hop: {fm.get('hop', '')}",
        f"written_by: {doc.basename}",
        "---",
    ]


def _split_standing(
    hot: list[str], rel: str, term: str, header: list[str]
) -> tuple[list[str], str]:
    content = [_line_parts(line)[0] for line in hot]
    out = list(hot)
    held: dict[str, list[str]] = {}
    for title, at, end in sorted(section_spans(content, 0), key=lambda s: -s[1]):
        if title not in STANDING_SECTIONS:
            continue
        held[title] = _trim_blank(content[at + 1 : end])
        out[at + 1 : end] = [term, f"{STANDING_PREFIX}{rel}#{title}{term}", term]
    text = list(header)
    for title in STANDING_SECTIONS:
        text += ["", f"## {title}", "", *held.get(title, [])]
    return out, "\n".join(text) + "\n"


def _join_standing(hot: list[str], text: str, term: str) -> list[str] | None:
    content = [_line_parts(line)[0] for line in hot]
    out = list(hot)
    for title, at, end in sorted(section_spans(content, 0), key=lambda s: -s[1]):
        if title not in STANDING_SECTIONS:
            continue
        if standing_pointer(content[at + 1 : end]) is None:
            continue
        held = section_of(text, title)
        if held is None:
            return None
        out[at + 1 : end] = [
            term,
            *(line + term for line in _trim_blank(held)),
            term,
        ]
    return out


def _page_standing(hot: list[str], held: int) -> list[str]:
    content = [_line_parts(line)[0] for line in hot]
    span = next(
        (
            (at, end)
            for name, at, end in section_spans(content, 0)
            if name == "Resume prompt"
        ),
        None,
    )
    if span is None:
        return hot
    out = list(hot)
    for i in range(span[0] + 1, span[1]):
        line = content[i]
        if not line.startswith("Read @") or STANDING_THEN not in line:
            continue
        line = line.replace(STANDING_PAGED + STANDING_THEN, STANDING_THEN, 1)
        if held > READ_CAP_BYTES:
            line = line.replace(STANDING_THEN, STANDING_PAGED + STANDING_THEN, 1)
        out[i] = line + _line_parts(hot[i])[1]
    return out


def _check_standing(doc: Doc, f: Findings, root: str, standing: str | None) -> Doc:
    held = doc.frontmatter.get("standing_rules")
    pointed = _standing_pointed(doc)
    if not held and not pointed:
        return doc
    if held and root and held not in standing_rels(root):
        f.fail(
            f"frontmatter: standing_rules must be '{standing_rel(root)}' (got {held!r})"
        )
        return doc
    if not held:
        f.fail(
            f"frontmatter: {', '.join(pointed)} point at a standing-rules file, but no standing_rules key names one"
        )
        return doc
    for title in STANDING_SECTIONS:
        if title not in doc.titles or pointed.get(title) == (held, title):
            continue
        if title not in pointed and title in STANDING_INLINE_OK:
            continue
        f.fail(
            f"{title}: standing_rules is set, so this section holds only '{STANDING_PREFIX}{held}#{title}'",
            CheckKind.POINTER,
        )
        return doc
    if standing is not None:
        text, rel = standing, held
    else:
        text, rel = _standing_text(doc)
    resolved = _standing_doc(doc, text) if text is not None else None
    if resolved is None:
        f.fail(
            f"standing rules: {rel} is not on disk or lacks {' or '.join(f'## {t}' for t in pointed)}",
            CheckKind.POINTER,
        )
        return doc
    return resolved


def index_rel(chain_root: str) -> str:
    """`archive/<chain-root-stem>/retired-index.md`: a role chain's
    retired-entries index, relative to the handoffs directory."""
    return f"{ARCHIVE_DIR}/{_stem(chain_root)}/{INDEX_FILE}"


def _is_pointer(line: str) -> bool:
    """A line naming an archive file and a retire heading."""
    return bool(HOP_NAME_RE.search(line)) and any(h in line for h in RETIRE_HEADINGS)


def _index_lines(text: str) -> list[str]:
    """The retire pointers an index's text holds, in file order."""
    return [line for line in text.splitlines() if line.startswith(POINTER_PREFIX)]


def _index_pointer(doc: Doc) -> str | None:
    """The index file Review before you continue names, or None."""
    return next(
        (
            line[len(INDEX_PREFIX) :].strip()
            for line in doc.section("Review before you continue") or []
            if line.startswith(INDEX_PREFIX)
        ),
        None,
    )


def _read_index(doc: Doc) -> tuple[str | None, str | None]:
    """The index `doc` names and its text (None when unreadable or not this
    chain's index); `(None, None)` when it names none."""
    rel = _index_pointer(doc)
    if rel is None:
        return None, None
    if rel != index_rel(doc.frontmatter.get("chain_root", "")):
        return rel, None
    try:
        return rel, (doc.path.parent / rel).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return rel, None


def _index_doc(doc: Doc, text: str) -> Doc:
    """`doc` with its index line replaced by the index's pointers."""
    lines = list(doc.lines)
    for i, line in enumerate(lines):
        if line.startswith(INDEX_PREFIX):
            lines[i : i + 1] = _index_lines(text)
            return replace(_doc_from_lines(doc.path, lines), size=doc.size)
    return doc


def _index_header(root: str) -> list[str]:
    return ["---", f"type: {INDEX_TYPE}", f"chain_root: {root}", "---", "", INDEX_NOTE]


def _split_index(
    hot: list[str], rel: str, term: str, prior: str | None, header: list[str]
) -> tuple[list[str], str | None]:
    """Move each retire pointer line out of Review before you continue into
    the index's text: the prior text kept verbatim, then each pointer it does
    not hold appended once, verbatim, leaving one index
    line where the first pointer stood. Returns the hot lines unchanged and
    `prior` when neither holds a pointer."""
    content = [_line_parts(line)[0] for line in hot]
    span = next(
        (
            (at, end)
            for name, at, end in section_spans(content, 0)
            if name == "Review before you continue"
        ),
        None,
    )
    if span is None:
        return hot, prior
    found = [
        i
        for i in range(span[0] + 1, span[1])
        if content[i].startswith(INDEX_PREFIX)
        or (content[i].startswith(POINTER_PREFIX) and _is_pointer(content[i]))
    ]
    known = set(_index_lines(prior or ""))
    added: list[str] = []
    for i in found:
        line = content[i]
        if not line.startswith(INDEX_PREFIX) and line not in known:
            known.add(line)
            added.append(line)
    if not known:
        return hot, prior
    out = list(hot)
    for i in reversed(found):
        del out[i]
    at = found[0] if found else _section_end(_content_doc(out), "Review before you continue")
    out.insert(at, f"{INDEX_PREFIX}{rel}{term}")
    if prior is None:
        return out, "\n".join([*header, "", *added]) + "\n"
    if not added:
        return out, prior
    return out, prior.rstrip("\n") + "\n" + "\n".join(added) + "\n"


def _index_split(
    hot: list[str], handoffs: Path, doc: Doc, term: str
) -> tuple[list[str], Path, str | None, bytes | None] | int:
    """`_split_index` against the chain's index on disk: the hot lines, the
    index path, its new text (None when nothing is indexed) and its prior
    bytes (None when absent); an exit code when it cannot be read."""
    root = doc.frontmatter.get("chain_root", "")
    rel = index_rel(root)
    target = handoffs / rel
    try:
        prior: bytes | None = target.read_bytes()
        prior_text = prior.decode("utf-8")
    except FileNotFoundError:
        prior, prior_text = None, None
    except (OSError, UnicodeDecodeError) as exc:
        return _die(
            1, f"cannot read the retired-entries index {rel} ({exc}); nothing written"
        )
    out, text = _split_index(hot, rel, term, prior_text, _index_header(root))
    return out, target, text, prior


def _validate_shape3(
    doc: Doc,
    f: Findings,
    previous: str | None,
    pred: Doc | None,
    projects_root: Path | None,
    hop_text: str | None = None,
    standing: str | None = None,
    index: str | None = None,
) -> Doc:
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
    spec = SHAPES[doc.shape]
    if doc.titles == list(spec.legacy_names) != list(spec.names):
        f.warn(
            "headings: written before '## Suggested skills' joined shape 3; the next hop adds it"
        )
        _check_headings(doc, f, spec.legacy_names)
    else:
        _check_headings(doc, f, spec.names)
    if spec.fitted:
        _check_moves(doc, f, spec)
    _check_original_goal(doc, f, hop or 1)
    raw = doc
    doc = _check_standing(doc, f, root, standing)

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

    for spec in _id_specs(doc.shape):
        seen: set[int] = set()
        required = (
            spec == RULES
            or previous is None
            or (
                pred is not None
                and pred.shape in HOP_FILE_SHAPES
                and (
                    _fm_int(pred, spec.floor_key) is not None
                    or spec not in _id_specs(pred.shape)
                )
            )
        )
        for n, entry, title in _id_entries(doc, spec):
            if n is None:
                if required:
                    f.fail(
                        f"{title}: entry without a [{spec.prefix}<n>] id: {entry.text[:60]!r}"
                    )
            elif n in seen:
                f.fail(f"{title}: duplicate id [{spec.prefix}{n}]")
            else:
                seen.add(n)
    _check_decision_fields(doc, f)
    _check_reminders(doc, f)
    _check_recurring(doc, f)

    _check_github_claims(doc, f)
    _check_dated_observations(doc, f)
    if hop is None or start is None or not root:
        return doc

    handoffs = doc.path.parent
    own = hop_file_path(handoffs, root, hop, fm.get("session_id", ""))
    rel = own.relative_to(handoffs).as_posix()
    archived: str | None = None
    if not own.is_file():
        f.fail(f"archive: this hop's file {rel} is missing", CheckKind.POINTER)
    elif hop_text is not None:
        archived = hop_text
    else:
        try:
            archived = own.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            f.fail(
                f"archive: this hop's file {rel} is unreadable: {exc}",
                CheckKind.POINTER,
            )

    if (_fm_int(doc, "checks") or 0) >= ID_REUSE_FROM:
        _check_id_reuse(doc, f, pred, archived)

    report = f.carry(False)
    if previous is None:
        if (root, hop, start) != (doc.basename, 1, 1):
            f.fail(
                "frontmatter: a first hop (no previous_handoff) has chain_root its own name, hop 1 and archive_from 1"
            )
    elif pred is not None:
        if pred.shape not in (None, 1) and _pred_failed(
            doc, pred, previous, projects_root, f
        ):
            report = f.carry(True)
        want = _chain_position(pred, doc.basename)
        if (root, hop, start) != want:
            report(
                f"frontmatter: after {previous!r} (chain_root, hop, archive_from) is {want} (got {(root, hop, start)})"
            )
        held = pred
        if archived is not None and _standing_pointed(pred):
            held = _standing_doc(pred, archived)
            if held is None:
                f.fail(
                    f"standing rules: {rel} holds no copy of the predecessor's {' and '.join(_standing_pointed(pred))}, so its carried entries cannot be checked",
                    CheckKind.POINTER,
                )
                held = pred
        _check_carry_3(doc, f, held, start, hop == start, rel, archived, report)
        _check_hop_path(f, pred, start)
    _check_retire_pointers(doc, f, pred, rel, archived, report, index)
    _check_prior_rows_3(doc, f, previous, pred, rel, archived, report)

    slots = _check_slot_sizes(raw, f)
    if fitted(raw.shape) and _cap_state(raw)[0] > READ_CAP_BYTES:
        f.warn(
            f"size: {_cap_state(raw)[0]} bytes is over the {READ_CAP_BYTES}-byte Read page cap; the resume prompt directs a paged Read (offset and limit)",
            CheckKind.SIZE,
        )
    verdict = _size_finding(raw, rel)
    if verdict is None:
        return doc
    level, message = verdict
    if level == "FAIL":
        f.fail(message, CheckKind.SIZE)
    elif level == "OVER-CAP":
        f.fail(message, CheckKind.OVER_CAP_BINDING)
    elif slots:
        f.warn(f"size: {message}", CheckKind.SIZE)
    else:
        f.unvalidated = True
        f.warn(f"UNVALIDATED: {message}", CheckKind.SIZE)
    return doc


def _check_slot_sizes(doc: Doc, f: Findings) -> int:
    if (_fm_int(doc, "checks") or 0) < SLOT_SIZE_FROM:
        return 0
    held = handoff_fit.written_slot_bytes(
        doc.section("Resumption brief"), doc.section("Resume prompt")
    )
    overruns = [
        (name, held[name], budget)
        for name, budget in handoff_fit.SLOT_BUDGETS.items()
        if held.get(name, 0) > budget
    ]
    for name, size, budget in overruns:
        f.fail(handoff_fit.overrun_text(name, size, budget), CheckKind.SLOT_SIZE)
    return len(overruns)


def _check_moves(doc: Doc, f: Findings, spec) -> None:
    base = doc.path.parent
    for title, start, end in doc.sections:
        if title in spec.carried:
            continue
        for i in range(start + 1, end):
            pointer = MovePointer.parse(doc.lines[i])
            if pointer is None:
                continue
            if title in spec.binding and pointer.moves(title):
                f.fail(
                    f"{title}: a binding section stays whole in the hot file; line {i + 1} moves it to {pointer.file}",
                    CheckKind.POINTER,
                )
            elif pointer.target(base) is None:
                f.fail(
                    f"{title}: line {i + 1} points at '{pointer.file}#{pointer.heading}', which is not on disk (no such hop file, or no '## {pointer.heading}' in it)",
                    CheckKind.POINTER,
                )


def _check_id_reuse(
    doc: Doc, f: Findings, pred: Doc | None, archived: str | None
) -> None:
    retired = read_chain(pred.path, strict=True).retired_ids() if pred else {}
    for prefix, ids in retired_in(archived or "", SHAPES.get(doc.shape, S3)).items():
        for n, text in ids.items():
            retired.setdefault(prefix, {}).setdefault(n, text)
    for spec in _id_specs(doc.shape):
        spent = retired.get(spec.prefix, {})
        for n, entry, title in _id_entries(doc, spec):
            was = spent.get(n) if n is not None else None
            if was is not None and entry_text(spec.prefix, entry.lines)[1] != was:
                f.fail(
                    f"{title}: [{spec.prefix}{n}] was retired earlier in this chain for a different entry ({was[:60]!r}), so this entry reuses a spent id (id_reuse); give it the next unused id, {spec.floor_key} in the frontmatter",
                    CheckKind.ID_REUSE,
                )


def _check_carry_3(
    doc: Doc,
    f: Findings,
    pred: Doc,
    start: int,
    first_split: bool,
    rel: str,
    archived: str | None,
    report,
) -> None:
    arch = _squash(archived or "")
    if pred.shape in HOP_FILE_SHAPES:
        _check_retired_entries(doc, f, pred, start, rel, archived, report)
        if archived is None:
            return
        hop = _fm_int(doc, "hop")
        for spec in _id_specs(doc.shape):
            own = {n: e for n, e, _ in _id_entries(doc, spec) if n is not None}
            retired = _retired_ids(archived, spec)
            marked = _carries(pred, spec)
            for n, entry, title in _id_entries(pred, spec):
                if n is None:
                    continue
                ref = f"[{spec.prefix}{n}]"
                prior = _squash(entry.text)
                if n in own:
                    if _squash(own[n].text) == prior:
                        continue
                    if prior not in arch:
                        report(
                            f"{title}: changed entry {ref} has no prior text in {rel}; an entry rewritten in place keeps its predecessor text there"
                        )
                    elif marked and not any(
                        int(m.group(1)) == hop
                        for m in REWRITE_MARK_RE.finditer(own[n].text)
                    ):
                        report(
                            f"{title}: carried entry {ref} changed without a retire or a rewrite mark; keep the text `new` copied, end a rewrite with '{REWRITE_MARK} h{hop}: <why>' (the prior text stays in {rel}), or retire it through the 'retire' list"
                        )
                elif prior not in arch:
                    report(
                        f"{title}: predecessor entry {ref} is in neither this file nor {rel}"
                    )
                elif not retired.get(n) or _squash(
                    id_of(spec.prefix, entry.text)[1]
                ).startswith(_squash(retired[n])):
                    report(
                        f"{title}: predecessor entry {ref} left this file without a retirement; keep it here, or retire it through the 'retire' list of fill or amend as {{'ref': '{ref}', 'reason': ...}}, which lists it in {rel} under '## {spec.retired_heading}'. An entry never leaves to meet the size cap"
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


def _retire_pointers(doc: Doc) -> list[str]:
    return [
        line
        for line in doc.section("Review before you continue") or []
        if _is_pointer(line)
    ]


def _check_retire_pointers(
    doc: Doc,
    f: Findings,
    pred: Doc | None,
    rel: str,
    archived: str | None,
    report,
    index: str | None = None,
) -> None:
    """A role chain's pointers may sit in its retired-entries index (`index`
    stands in for it on disk); when this file or the predecessor names an
    index, the predecessor's pointers include the ones this hop's file copied
    from it, each compared verbatim."""
    review = doc.section("Review before you continue") or []
    reach = list(review)
    held = _index_pointer(doc)
    if held is not None:
        want = index_rel(doc.frontmatter.get("chain_root", ""))
        if held != want:
            f.fail(
                f"Review before you continue: the retired-entries index is {want} (got {held!r})",
                CheckKind.POINTER,
            )
        elif (text := index if index is not None else _read_index(doc)[1]) is None:
            f.fail(
                f"Review before you continue: the retired-entries index {held} is not on disk",
                CheckKind.POINTER,
            )
        else:
            reach += _index_lines(text)
    name = rel.rsplit("/", 1)[-1]
    for heading in POINTED_HEADINGS:
        listed = retired_listings(archived or "", heading)
        if listed and not any(name in line and heading in line for line in reach):
            f.fail(
                f"Review before you continue: {rel} retires entries under '## {heading}'; add a line naming {name} and '{heading}'",
                CheckKind.POINTER,
            )
    if pred is None or pred.shape not in HOP_FILE_SHAPES:
        return
    carried = _retire_pointers(pred)
    indexed = held is not None or _index_pointer(pred) is not None
    if indexed:
        copy = section_of(archived or "", "Review before you continue") or []
        carried = list(dict.fromkeys([*carried, *filter(_is_pointer, copy)]))
    for line in carried:
        if line not in reach:
            report(
                f"Review before you continue: the predecessor's retire pointer is missing; carry it verbatim: {line[:60]!r}"
            )


def _check_hop_path(f: Findings, pred: Doc, start: int) -> None:
    for cursor, path in _chain_hop_paths(pred, start):
        if not path.is_file():
            f.fail(
                f"archive: hop file {path.relative_to(cursor.path.parent).as_posix()} of predecessor {cursor.basename!r} is missing",
                CheckKind.POINTER,
            )


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


_BARE_PRESENT = re.compile(r"(?i)\b(?:currently|now)\b")
_CLAIM_ANCHOR = re.compile(r"\b\d{4}-\d{2}-\d{2}\b|@[0-9a-f]{7,40}\b")


def _check_dated_observations(doc: Doc, f: Findings) -> None:
    for name, start, end in doc.sections:
        if name != "Observations":
            continue
        for i in range(start, end):
            line = doc.lines[i]
            if _BARE_PRESENT.search(line) and not _CLAIM_ANCHOR.search(line):
                f.warn(
                    f"line {i + 1}: Observations: bare 'currently' or 'now' with no date or commit; date the claim (save-point.md, 'Write history, not the present')"
                )


def _open_handoff(file: str) -> tuple[Doc | None, int]:
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
    _print_verdict(doc, findings, code)
    return code


def _print_verdict(doc: Doc, findings: Findings, code: int) -> None:
    for x in findings.items:
        print(f"{x.level}: {x.text}")
    if code == 3:
        label = "UNSUPPORTED-SHAPE"
    elif code != 0:
        label = "FAIL"
    elif findings.unvalidated:
        label = "UNVALIDATED"
    else:
        label = "WARN" if findings.items else "PASS"
    count = f" ({len(findings.items)})" if findings.items else ""
    print(f"validate: {label}{count} {_posix(doc.path)}")


def _readable_link(file: str):
    path = Path(file)
    if not path.is_file():
        return None, _die(2, f"not a file: {path}")
    link = read_link(path)
    if link.status == "unreadable":
        return None, _die(2, f"cannot read {path}")
    if link.status == "unsupported_shape":
        return None, _die(
            3,
            f"handoff_shape {link.shape} is newer than this script knows ({NEWEST_SHAPE}): read the file itself, or update session-flow: {_posix(path)}",
        )
    return link, 0


def cmd_read(args: argparse.Namespace) -> int:
    link, code = _readable_link(args.file)
    if link is None:
        return code
    body = link.section(args.section)
    if body is None:
        held = any(title == args.section for title, _ in link.sections)
        return _die(
            1,
            f"'## {args.section}' points at a hop file or heading that is not on disk: {_posix(link.path)}"
            if held
            else f"no '## {args.section}' section: {_posix(link.path)}",
        )
    sys.stdout.write("\n".join(_trim_blank(body)) + "\n")
    return 0


def cmd_chain(args: argparse.Namespace) -> int:
    link, code = _readable_link(args.file)
    if link is None:
        return code
    chain = read_chain(link.path)
    walk = journey(link.path)
    report = {
        "file": _posix(link.path),
        "stop": chain.stop,
        "links": [
            {
                "file": _posix(x.path),
                "status": x.status,
                "shape": x.shape,
                "hop": x.hop,
                **{
                    key: x.frontmatter.get(key)
                    for key in (
                        "session_id",
                        "date",
                        "topic",
                        "previous_handoff",
                        "previous_status",
                        "chain_root",
                    )
                },
                "hop_files": [_posix(p) for p in x.hop_files],
            }
            for x in chain.links
        ],
        "hops": [
            {
                "hop": hop.hop,
                "session_id": hop.session_id,
                "date": hop.date,
                "file": hop.file,
                "source": _posix(hop.source),
                "sections": hop.sections,
            }
            for hop in walk.hops
        ],
        "session_ids": walk.session_ids,
    }
    if args.json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
        return 0
    for x in report["links"]:
        print(f"{x['status']}\thop {x['hop']}\t{x['session_id']}\t{x['file']}")
    for hop in report["hops"]:
        print(f"hop {hop['hop']}\t{hop['session_id']}\t{hop['source']}")
    return 0


def _ps_quote(value: str) -> str:
    return "'" + re.sub("['‘’‚‛]", lambda m: m[0] * 2, value) + "'"


def _launch_command(checkout: Path, command: str, prompt: Path, shell: str | None) -> str:
    if not checkout.is_absolute() or not checkout.is_dir():
        raise ValueError(f"launch checkout is not an existing absolute directory: {checkout}")
    if not command.strip() or any(c in command for c in "`\r\n"):
        raise ValueError("--start-command must be one nonempty line without backticks")
    if shell is None:
        windows = sys.platform == "win32" and not os.environ.get("MSYSTEM")
        powershell = Path(os.environ.get("SHELL", "")).stem.lower() in {"pwsh", "powershell"}
        shell = "powershell" if windows or powershell else "posix"
    prompt_path = prompt.absolute().as_posix()
    if shell == "powershell" or command.startswith("Remove-Item "):
        if command.startswith("env "):
            command = "sh -c " + _ps_quote(command + ' "$1"') + " sh"
        read_ps = f"(Get-Content -LiteralPath {_ps_quote(prompt_path)} -Raw -Encoding UTF8 -ErrorAction Stop)"
        launch_ps = (
            "if ($PSVersionTable.PSVersion -lt [version]'7.3') { throw 'Run this command in pwsh 7.3 or newer.' }; "
            f"$PSNativeCommandArgumentPassing = 'Standard'; {command} {read_ps}"
        )
        if shell == "powershell":
            return f"Set-Location -LiteralPath {_ps_quote(str(checkout))} -ErrorAction Stop; & {{ {launch_ps} }}"
        invocation = f"pwsh -NoProfile -Command {shlex.quote(launch_ps)}"
    else:
        quoted_prompt = shlex.quote(prompt_path)
        invocation = f'{command} "$(cat {quoted_prompt})"'
        if sys.platform == "win32":
            invocation = "MSYS2_ARG_CONV_EXCL='/goal ' " + invocation
        invocation = f": < {quoted_prompt} && {invocation}"
    return f"cd {shlex.quote(checkout.as_posix())} && {invocation}"


def cmd_launch(args: argparse.Namespace) -> int:
    prompt = Path(args.file)
    if not prompt.is_file():
        return _die(1, f"launch prompt file does not exist: {prompt}")
    try:
        print(_launch_command(Path(args.checkout), args.start_command, prompt, args.shell))
    except ValueError as exc:
        return _die(1, str(exc))
    return 0


def _emit_launch(lines: list[str], doc: Doc, shell: str | None, markdown: bool) -> None:
    path = doc.path
    if "launch" in doc.frontmatter:
        match json.loads(doc.frontmatter["launch"]):
            case []:
                return
            case [str(directory), str(command)]:
                checkout = Path(directory)
            case _:
                raise ValueError("launch frontmatter must contain a checkout and command, or an empty list")
        if len(lines) >= 2 and lines[0].startswith(LAUNCH_CHECKOUT) and lines[1].startswith(LAUNCH_COMMAND):
            del lines[:2]
    else:
        copy = lines.index(COPY_LINE) if COPY_LINE in lines else 0
        if not copy or not (old := PROFILE_RELAUNCH_RE.fullmatch(lines[copy - 1])):
            return
        checkout = _git_toplevel(path.parent)
        if checkout is None:
            raise ValueError(f"cannot locate the checkout for the saved profile command in {path}")
        command = old[1]
        del lines[copy - 1]

    prompt_file = path.with_suffix(".prompt.txt")
    try:
        launch = _launch_command(checkout, command, prompt_file, shell)
        rails = [i for i, line in enumerate(lines) if RAIL_RE.match(line.strip())]
        prompt = ""
        for above, region, _ in _rail_regions(lines, rails):
            if GOAL_COPY_LINE in above:
                prompt = "/goal " + "\n".join(region)
                break
            if COPY_LINE in above:
                prompt = "\n".join(region)
        if not prompt:
            raise ValueError("launch prompt has no copy region")
        if exc := _write_atomic(prompt_file, prompt.encode("utf-8")):
            raise ValueError(f"cannot write launch prompt {prompt_file}: {exc}")
    except ValueError:
        lines[:0] = [f"Start command for the new session: {command}"]
        raise
    display = ["```", launch, "```"] if markdown else [launch]
    lines[:0] = [
        "Run this terminal command to start the new session. The copy instructions below are for recovery.",
        *display,
    ]


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
    notices: list[str] = []
    if doc.shape in HOP_FILE_SHAPES and getattr(args, "notice", True):
        verdict = _size_finding(doc, "this hop's file")
        if verdict and (
            verdict[0] in ("UNVALIDATED", "OVER-CAP")
            or _cap_state(doc)[0] > READ_CAP_BYTES
        ):
            level, message = verdict
            tail = (
                "the file was not validated"
                if level == "UNVALIDATED"
                else "`validate` fails it"
            )
            head = message if message.startswith(f"{level}:") else f"{level}: {message}"
            notices.append(f"{head}; {tail}; the prompt is emitted")
    real = _posix(path)
    held = doc.frontmatter.get("standing_rules")
    out: list[str] = []
    for line in _trim_blank(body):
        if line.startswith("Read @"):
            standing, stored = _directive_paths(line)
            if standing is not None and held:
                real_standing = _posix(path.parent / held)
                if not _same_file(standing, path.parent / held):
                    notices.append(
                        f"WARN: stored standing-rules path {standing} is not this chain's; substituting {real_standing} on stdout only (file untouched)"
                    )
                    line = line.replace("@" + standing, "@" + real_standing, 1)
            if not _same_file(stored, path):
                notices.append(
                    f"WARN: stored 'Read @' path {stored} is not this file; substituting {real} on stdout only (file untouched)"
                )
                line = line.replace("@" + stored, "@" + real, 1)
        out.append(line)
    markdown = getattr(args, "format", "rails") == "markdown"
    launch_error = None
    try:
        _emit_launch(out, doc, getattr(args, "shell", None), markdown)
    except ValueError as exc:
        launch_error = str(exc)
        out[:0] = [f"No launch command: {exc}. Start the new session by hand with the copy region below."]
    for notice in notices:
        print(notice, file=sys.stderr)
    if markdown:
        out = _markdown_prompt(out)
    sys.stdout.write("\n".join(out) + "\n")
    return _die(1, launch_error) if launch_error else 0


def _markdown_prompt(lines: list[str]) -> list[str]:
    swap = {COPY_LINE: MD_COPY_LINE, GOAL_COPY_LINE: MD_GOAL_COPY_LINE}
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if RAIL_RE.match(line):
            end = next(
                (j for j in range(i + 1, len(lines)) if RAIL_RE.match(lines[j])), None
            )
            if end is not None:
                region = lines[i + 1 : end]
                runs = [len(m) for text in region for m in re.findall(r"`+", text)]
                fence = "`" * max(3, max(runs, default=0) + 1)
                out += [fence + "text", *region, fence]
                i = end + 1
                continue
        out.append(swap.get(line, line))
        i += 1
    return out


def _locate_ref(
    doc: Doc, m: re.Match[str], moved: dict[str, str] | None = None
) -> tuple[str, int, int] | str | None:
    if moved is not None:
        doc = _aliased(doc, moved)
    if m["prefix"]:
        spec = _family(m["prefix"])
        for title in spec.sections:
            base = doc.section_start(title) + 1
            for entry in parse_entries(doc.section(title) or []):
                if not entry.exempt and id_of(spec.prefix, entry.text)[0] == int(
                    m["n"]
                ):
                    at = base + entry.first_index
                    return spec.retired_heading, at, at + len(entry.lines)
        return None
    if m["tag"]:
        title = "Direction changes"
        hits = [
            i
            for i, line in enumerate(doc.section(title) or [])
            if (t := TRAIL_TAG_RE.match(line)) and t.group(1) == m["tag"]
        ]
        if m["tag_ord"]:
            k = int(m["tag_ord"])
            hits = hits[k - 1 : k] if k else []
        elif len(hits) > 1:
            return f"{len(hits)} lines carry [{m['tag']}]; add '#<ordinal>'"
        if not hits:
            return None
        at = doc.section_start(title) + 1 + hits[0]
        return S3.retired_entry_sections[title], at, at + 1
    title = "Original goal"
    spans, _ = _amendment_spans(doc.section(title) or [])
    k = int(m["ord"])
    if not 1 <= k <= len(spans):
        return None
    base = doc.section_start(title) + 1
    return (
        S3.retired_entry_sections[title],
        base + spans[k - 1][0],
        base + spans[k - 1][1],
    )


def _aliased(doc: Doc, moved: dict[str, str]) -> Doc:
    names = {heading: title for title, heading in moved.items()}
    return replace(
        doc,
        sections=[
            (names[name], start, end)
            for name, start, end in doc.sections
            if name in names
        ],
    )


def _moved_here(hot: Doc, rel: str) -> dict[str, str]:
    found: dict[str, str] = {}
    for title, start, end in hot.sections:
        held = [line for line in hot.lines[start + 1 : end] if line.strip()]
        pointer = MovePointer.parse(held[0]) if len(held) == 1 else None
        if pointer is not None and pointer.moves(title) and pointer.file == rel:
            found[title] = pointer.heading
    return found


def _resolved(hot: list[str], hop: list[str], rel: str) -> Doc:
    doc = _content_doc(hot)
    moved = _moved_here(doc, rel)
    if not moved:
        return doc
    hop_doc = _content_doc(hop)
    lines = list(doc.lines)
    for title, start, end in sorted(doc.sections, key=lambda s: -s[1]):
        if title in moved:
            lines[start + 1 : end] = hop_doc.section(moved[title]) or []
    return _doc_from_lines(Path(), lines)


def _content_doc(raw: list[str]) -> Doc:
    return _doc_from_lines(Path(), [_line_parts(line)[0] for line in raw])


def _section_end(doc: Doc, title: str) -> int:
    for name, start, end in doc.sections:
        if name == title:
            while end > start + 1 and not doc.lines[end - 1].strip():
                end -= 1
            return end
    return -1


def _apply_retire(
    hot: list[str], hop: list[str], refs: list[tuple[str, str]], rel: str
) -> tuple[list[str], list[str]] | str:
    hot_doc, hop_doc = _content_doc(hot), _content_doc(hop)
    moved = _moved_here(hot_doc, rel)
    removals: list[tuple[int, int]] = []
    hop_removals: list[tuple[int, int]] = []
    listings: dict[str, list[list[str]]] = {}
    for ref, reason in refs:
        m = RETIRE_REF_RE.match(ref)
        if not m:
            return f"retire ref {ref!r} is not [R<n>], [Q<n>], [D<n>], [h<k>]#<i> or amendment#<i>"
        source, found = hot_doc, _locate_ref(hot_doc, m)
        if found is None and moved:
            found = _locate_ref(hop_doc, m, moved)
            if isinstance(found, tuple):
                source = hop_doc
                hop_removals.append(found[1:])
        if found is None:
            source, found = hop_doc, _locate_ref(hop_doc, m)
        if isinstance(found, str):
            return f"retire ref {ref!r}: {found}"
        if found is None:
            return f"retire ref {ref!r} names nothing in this file or {rel}"
        heading, a, b = found
        entry = source.lines[a:b]
        if any(listed[:-1] == entry for listed in listings.get(heading, [])):
            return f"retire ref {ref!r} repeats an earlier ref"
        if source is hot_doc:
            removals.append((a, b))
        listings.setdefault(heading, []).append([*entry, f"{RETIRED_PREFIX} {reason}"])

    out = list(hot)
    for a, b in sorted(removals, reverse=True):
        del out[a:b]
        if 0 < a < len(out) and not out[a - 1].strip() and not out[a].strip():
            del out[a]
    term = (_line_parts(out[0])[1] if out else "") or "\n"
    review = "Review before you continue"
    name = rel.rsplit("/", 1)[-1]
    for heading in listings:
        doc = _content_doc(out)
        if any(name in line and heading in line for line in doc.section(review) or []):
            continue
        end = _section_end(doc, review)
        if end < 0:
            return f"no '## {review}' section to point at {rel}"
        out.insert(end, f"- Retired entries: {rel} § {heading}{term}")

    new_hop = list(hop)
    for a, b in sorted(hop_removals, reverse=True):
        del new_hop[a:b]
    term = (_line_parts(new_hop[0])[1] if new_hop else "") or "\n"
    if new_hop and not _line_parts(new_hop[-1])[1]:
        new_hop[-1] += term
    for heading, entries in listings.items():
        block: list[str] = []
        for entry in entries:
            block += [term, *(line + term for line in entry)]
        end = _section_end(_content_doc(new_hop), heading)
        if end < 0:
            new_hop += [term, f"## {heading}{term}", *block]
        else:
            new_hop[end:end] = block
    return out, new_hop


RETIRE_SHAPE = 'takes a list of {"ref": ..., "reason": ...} objects, each reason one non-empty line'


def _retire_shape_ok(retire: object) -> bool:
    return isinstance(retire, list) and all(
        isinstance(item, dict)
        and isinstance(item.get("ref"), str)
        and isinstance(item.get("reason"), str)
        and item["reason"].strip()
        and not any(c in item["reason"] for c in "\r\n")
        for item in retire
    )


def _american(items: list[tuple[str, str]], path: Path) -> list[str]:
    """Each `(value, where)` value in American spelling, through one `typos` run."""
    fixed = []
    for (_, where), (value, applied) in zip(
        items, dialect.americanize_all([value for value, _ in items], path.parent), strict=True
    ):
        for typo, correction in applied:
            print(f"NOTE: {where}: {typo!r} written as {correction!r} (American spelling)", file=sys.stderr)
        fixed.append(value)
    return fixed


def _write_atomic(path: Path, payload: bytes) -> OSError | None:
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
        return exc
    return None


def cmd_fill(args: argparse.Namespace) -> int:
    """Replace every slot in one pass and one write. Substitution only, with the
    single exception the closing handoff needs: a `next` value of exactly
    NEXT_CLOSED rewrites the bare `Next:` line above the slot and deletes the
    slot line, which is the only shape `validate` accepts as closed.

    The write path reuses neither `_read_lines` nor `parse_doc`: both apply
    universal-newline translation and would rewrite a CRLF target to LF. A
    translated copy of the same bytes serves the `type: handoff` and shape
    guards alone, read-only, mirroring `cmd_validate` and `cmd_emit`. Every
    refusal happens before the write, so a refused target is byte-identical.
    """
    path = Path(args.file)
    if not path.is_file():
        return _die(2, f"not a file: {path}")
    try:
        text = path.read_bytes().decode("utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        return _die(2, f"cannot read {path}: {exc}")
    doc = _doc_from_lines(path, _text_lines(text))
    if not doc.has_frontmatter or doc.frontmatter.get("type") != "handoff":
        return _die(2, f"not a handoff file (no 'type: handoff' frontmatter): {path}")
    shape = doc.shape
    unsupported = f"fill only writes shape-2, shape-3 and shape-4 skeletons: {path}"
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
    if shape not in WRITABLE_SHAPES:
        return _die(
            3,
            f"handoff_shape {shape} is not a shape fill writes ({', '.join(map(str, WRITABLE_SHAPES))}): read it, do not rewrite it: {path}",
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
    retire = values.pop("retire", None)
    if retire is not None:
        if shape not in HOP_FILE_SHAPES:
            return _die(
                2,
                f"slots key 'retire' applies to shape-3 and shape-4 files only: {path}",
            )
        if not _retire_shape_ok(retire):
            return _die(2, f"slots key 'retire' {RETIRE_SHAPE}")
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
            if match.group(2).startswith("optional:"):
                optional.add(name)
    if not slot_line:
        return _die(
            1,
            f"no {FILL_MARK} slot in {_posix(path)}; a filled file is validated, never filled again; fold a later change in with `save_point.py amend {_posix(path)} --json <path>`",
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

    keys = [key for key in values if key not in VERBATIM_SLOTS]
    fixed = _american(
        [(values[key], f"slot {key!r}") for key in keys]
        + [(item["reason"], "retire reason") for item in retire or []],
        path,
    )
    for key, value in zip(keys, fixed):
        values[key] = value
    for item, value in zip(retire or [], fixed[len(keys) :], strict=True):
        item["reason"] = value

    marker = handoff_fit.over_budget_marker(path)
    overruns = handoff_fit.slot_overruns(values) if shape in HOP_FILE_SHAPES else []
    refused = handoff_fit.refused_slots(marker)
    fresh = [item for item in overruns if item[0] not in refused]
    if fresh:
        recorded = sorted(refused | {name for name, _, _ in fresh})
        try:
            marker.write_text(json.dumps(recorded) + "\n", encoding="utf-8")
        except OSError as exc:
            return _die(2, f"cannot record the attempt in {marker} ({exc})")
        return _die(1, handoff_fit.refusal_text(fresh, marker))

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

    writes: list[tuple[Path, str, bytes | None]] = []
    standing_key = doc.frontmatter.get("standing_rules") if fitted(shape) else None
    root = doc.frontmatter.get("chain_root", "")
    if standing_key and standing_key not in standing_rels(root):
        return _die(
            1,
            f"standing_rules {standing_key!r} is not this chain's standing-rules file ({standing_rel(root)}); nothing written",
        )
    if standing_key and (code := _forked(path, doc)) is not None:
        return code
    if retire or fitted(shape):
        hop_number = _fm_int(doc, "hop") or 0
        own = hop_file_path(
            path.parent,
            doc.frontmatter.get("chain_root", ""),
            hop_number,
            doc.frontmatter.get("session_id", ""),
        )
        rel = own.relative_to(path.parent).as_posix()
        try:
            before = own.read_bytes()
            hop_text = before.decode("utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            return _die(
                1,
                f"{'retire: ' if retire else ''}cannot read this hop's file {rel} ({exc}); nothing written",
            )
        hop_lines = hop_text.splitlines(keepends=True)
        if retire:
            refs = [(item["ref"], item["reason"].strip()) for item in retire]
            moved = _apply_retire(out, hop_lines, refs, rel)
            if isinstance(moved, str):
                return _die(1, f"{moved}; nothing written")
            out, hop_lines = moved
        if fitted(shape):
            term = (_line_parts(lines[0])[1] if lines else "") or "\n"
            if standing_key:
                out, standing = _split_standing(
                    out, standing_key, term, _standing_header(doc)
                )
                target = path.parent / standing_key
                try:
                    prior = target.read_bytes()
                except FileNotFoundError:
                    prior = None
                    try:
                        target.parent.mkdir(parents=True, exist_ok=True)
                    except OSError as exc:
                        return _die(
                            1,
                            f"cannot create the standing-rules folder {target.parent} ({exc}); nothing written",
                        )
                except OSError as exc:
                    return _die(
                        1,
                        f"cannot read the standing-rules file {standing_key} ({exc}); nothing written",
                    )
                writes.append((target, standing, prior))
                indexed = _index_split(out, path.parent, doc, term)
                if isinstance(indexed, int):
                    return indexed
                out, index_path, index_text, index_prior = indexed
                if index_text is not None and index_text.encode() != index_prior:
                    writes.append((index_path, index_text, index_prior))
            out, hop_lines, _ = handoff_fit.fit(
                out,
                hop_lines,
                movable=SHAPES[shape].movable,
                cap=SHAPES[shape].cap_bytes or HOT_FILE_MAX_BYTES,
                rel=rel,
                hop_number=hop_number,
                term=term,
            )
            out = handoff_fit.paged(out, READ_CAP_BYTES)
            if standing_key:
                out = _page_standing(out, len(standing.encode("utf-8")))
        writes.append((own, "".join(hop_lines), before))
    writes.append((path, "".join(out), text.encode("utf-8")))
    done: list[tuple[Path, bytes | None]] = []
    for target, payload, before in writes:
        exc = _write_atomic(target, payload.encode("utf-8"))
        if exc is not None:
            for written, original in done:
                if original is None:
                    written.unlink(missing_ok=True)
                else:
                    _write_atomic(written, original)
            return _die(2, f"cannot write {target} ({exc}); nothing written")
        done.append((target, before))
    try:
        marker.unlink(missing_ok=True)
    except OSError:
        pass
    if not fitted(shape):
        return 0
    written = parse_doc(path)
    findings, code = validate_doc(written, None, False)
    _print_verdict(written, findings, code)
    sys.stdout.flush()
    cmd_emit(argparse.Namespace(file=str(path), format="rails", notice=False))
    return 0


AMEND_KEYS = ("sections", "append", "retire", "next", "floors")
FLOOR_KEYS = tuple(spec.floor_key for spec in ID_SPECS)
AMENDED_HEADING = "Amended"
_SNIPPET_RE = re.compile(r"'(?:[^'\\]|\\.)*'|\"(?:[^\"\\]|\\.)*\"")
_DIGITS_RE = re.compile(rf"(\[[{''.join(s.prefix for s in ID_SPECS)}]\d+\])|\d+")


def _fail_key(message: str) -> str:
    return _DIGITS_RE.sub(lambda m: m.group(1) or "", _SNIPPET_RE.sub("", message))


def _fail_keys(findings: Findings) -> Counter[str]:
    return Counter(
        _fail_key(x.text) for x in findings.fails if x.kind not in SIZE_KINDS
    )


def _previous_of(path: Path) -> str | None:
    try:
        with path.open(encoding="utf-8", errors="replace") as fh:
            if fh.readline().strip() != "---":
                return None
            for line in fh:
                if line.strip() == "---":
                    return None
                if line.startswith("previous_handoff:"):
                    return fm_value(line.split(":", 1)[1])
    except OSError:
        return None
    return None


def _successor(path: Path) -> Path | None:
    for candidate in sorted(path.parent.glob("*.md")):
        if (
            candidate.name != path.name
            and HANDOFF_NAME_RE.match(candidate.name)
            and _previous_of(candidate) == path.name
        ):
            return candidate
    return None


def _fork_sibling(path: Path, doc: Doc) -> Path | None:
    previous = doc.frontmatter.get("previous_handoff")
    if not previous:
        return None
    session_id = doc.frontmatter.get("session_id", "").lower()
    for candidate in sorted(path.parent.glob("*.md")):
        if (
            candidate.name in (path.name, previous)
            or not HANDOFF_NAME_RE.match(candidate.name)
            or _previous_of(candidate) != previous
        ):
            continue
        try:
            other = parse_doc(candidate).frontmatter.get("session_id", "").lower()
        except (OSError, UnicodeDecodeError):
            other = ""
        if other != session_id:
            return candidate
    return None


def _forked(path: Path, doc: Doc) -> int | None:
    sibling = _fork_sibling(path, doc)
    if sibling is None:
        return None
    return _die(
        1,
        f"{sibling.name} also follows {doc.frontmatter.get('previous_handoff')}: a role chain keeps one standing-rules file, so it continues from one tip only; nothing written",
    )


def _not_tip(path: Path, successor: Path, payload: str) -> int:
    return _die(
        1,
        f"{path.name} is not the chain tip: {_posix(successor)} names it in previous_handoff; nothing written. Amend the tip instead: python3 {_posix(Path(__file__))} amend {_posix(successor)} --json {payload}",
    )


def _value_lines(value: str) -> list[str]:
    # `\n` only, as in `cmd_fill`: `str.splitlines()` also breaks on a lone `\r`.
    return value.replace("\r\n", "\n").split("\n")


def _next_span(doc: Doc) -> tuple[int, int] | None:
    start = doc.section_start("Resume prompt")
    if start < 0:
        return None
    body = doc.section("Resume prompt") or []
    origin = next(
        (i for i, line in enumerate(body) if line.startswith("Handoff origin: ")), None
    )
    if origin is None or origin + 1 >= len(body):
        return None
    at = origin + 1
    if body[at] not in ("Next:", NEXT_CLOSED):
        return None
    end = at + 1
    while end < len(body) and not RAIL_RE.match(body[end].strip()):
        end += 1
    return start + 1 + at, start + 1 + end


def _held_heading(doc: Doc) -> str | None:
    hop = _fm_int(doc, "hop")
    moved = (
        {moved_heading(name, hop) for name in handoff_fit.MOVE_ORDER} if hop else set()
    )
    for title, start, end in doc.sections:
        if (
            title.startswith(AMENDED_HEADING)
            or title in RETIRE_HEADINGS
            or title in moved
        ) and any(line.strip() for line in doc.lines[start + 1 : end]):
            return title
    return None


def _amend_payload(raw: dict) -> str | None:
    unknown = sorted(key for key in raw if key not in AMEND_KEYS)
    if unknown:
        return f"key {unknown[0]!r} is not one of {', '.join(AMEND_KEYS)}"
    sections, append = raw.get("sections", {}), raw.get("append", {})
    if not isinstance(sections, dict) or not all(
        isinstance(v, str) for v in sections.values()
    ):
        return "'sections' takes an object of section title to new body text"
    if not isinstance(append, dict) or not all(
        isinstance(v, list) and v and all(isinstance(s, str) for s in v)
        for v in append.values()
    ):
        return "'append' takes an object of section title to a non-empty list of lines"
    if "retire" in raw and not _retire_shape_ok(raw["retire"]):
        return f"'retire' {RETIRE_SHAPE}"
    nxt = raw.get("next")
    if "next" in raw and (
        not isinstance(nxt, list) or not nxt or not all(isinstance(s, str) for s in nxt)
    ):
        return "'next' takes a non-empty list of headline lines"
    floors = raw.get("floors", {})
    if not isinstance(floors, dict) or not all(
        type(v) is int and v >= 1 for v in floors.values()
    ):
        return "'floors' takes an object of floor key to an integer from 1 up"
    strings = [
        *sections.values(),
        *(s for v in append.values() for s in v),
        *(raw.get("next") or []),
        *(item["reason"] for item in raw.get("retire") or []),
    ]
    for value in strings:
        try:
            value.encode("utf-8")
        except UnicodeEncodeError as exc:
            return f"a value is not encodable as UTF-8 ({exc})"
    return None


def cmd_amend(args: argparse.Namespace) -> int:
    """Fold a late event into a filled shape-3 handoff file and its archive file.

    Byte rules follow `cmd_fill`: bytes in, each file keeps its own line
    terminators, `\\r\\n` becomes `\\n` in JSON values only, and every refusal
    happens before any write. The result is validated in memory first; it is
    written only when it adds no FAIL beyond the ones the file already had,
    a size FAIL aside, since nothing lossy wins over size.
    """
    path = Path(args.file)
    if not path.is_file():
        return _die(2, f"not a file: {path}")
    try:
        before = path.read_bytes()
        text = before.decode("utf-8")
        doc = parse_doc(path)
    except (OSError, UnicodeDecodeError) as exc:
        return _die(2, f"cannot read {path}: {exc}")
    if not doc.has_frontmatter or doc.frontmatter.get("type") != "handoff":
        return _die(2, f"not a handoff file (no 'type: handoff' frontmatter): {path}")
    if doc.shape not in HOP_FILE_SHAPES:
        return _die(
            2,
            f"amend rewrites shape-3 and shape-4 hot files only (handoff_shape {doc.frontmatter.get('handoff_shape')!r}): {path}",
        )
    if any(FILL_MARK in line for line in doc.lines):
        return _die(
            1,
            f"unfinished skeleton (a {FILL_MARK} slot remains); run `fill`, never `amend`, on it: {_posix(path)}",
        )
    now = _parse_now(args.now)
    if now is None:
        return _die(2, f"--now must be ISO-8601 UTC (got {args.now!r})")
    successor = _successor(path)
    if successor is not None:
        return _not_tip(path, successor, args.json)

    json_path = Path(args.json)
    try:
        raw = json.loads(json_path.read_bytes().decode("utf-8"))
    except (OSError, UnicodeDecodeError) as exc:
        return _die(2, f"cannot read amend file {json_path}: {exc}")
    except ValueError as exc:
        return _die(2, f"amend file is not valid JSON ({exc}): {_posix(json_path)}")
    if not isinstance(raw, dict):
        return _die(2, f"amend file must hold a JSON object: {_posix(json_path)}")
    malformed = _amend_payload(raw)
    if malformed:
        return _die(2, f"{malformed}: {_posix(json_path)}")
    sections: dict[str, str] = raw.get("sections", {})
    append: dict[str, list[str]] = raw.get("append", {})
    retire: list[dict[str, str]] = raw.get("retire") or []
    next_lines: list[str] | None = raw.get("next")
    floors: dict[str, int] = raw.get("floors", {})
    if not (sections or append or retire or next_lines or floors):
        return _die(1, f"nothing to amend in {_posix(json_path)}; no file written")
    values = [
        *sections.values(),
        *(s for v in append.values() for s in v),
        *(next_lines or []),
    ]
    if any(FILL_MARK in value for value in values):
        return _die(1, f"a value carries the literal {FILL_MARK!r}; rewrite it without")
    targets = [
        *((sections, t, f"section {t!r}") for t in sections if t not in VERBATIM_SECTIONS),
        *(
            (lines, j, f"section {t!r}")
            for t, lines in append.items()
            if t not in VERBATIM_SECTIONS
            for j in range(len(lines))
        ),
        *((next_lines, j, "next") for j in range(len(next_lines or []))),
        *((item, "reason", "retire reason") for item in retire),
    ]
    fixed = _american([(box[key], where) for box, key, where in targets], path)
    for (box, key, _), value in zip(targets, fixed, strict=True):
        box[key] = value
    for title in sections:
        if title in S3.carried:
            return _die(
                1,
                f"section {title!r} is carried (written by `new`); amend rewrites only the Resume prompt's Next: headlines, through 'next'",
            )
        if title not in doc.titles:
            return _die(1, f"section {title!r} is not in {_posix(path)}")
    for title in append:
        if title not in S3.retired_entry_sections:
            return _die(
                1,
                f"'append' adds lines to {' or '.join(S3.retired_entry_sections)} only (got {title!r})",
            )
        if title not in doc.titles:
            return _die(1, f"section {title!r} is not in {_posix(path)}")
    for key, n in floors.items():
        if key not in FLOOR_KEYS:
            return _die(
                1,
                f"frontmatter: amend changes only the id floors ({', '.join(FLOOR_KEYS)}), not {key!r}",
            )
        current = _fm_int(doc, key)
        if current is not None and n < current:
            return _die(1, f"frontmatter: {key} only rises ({current} now, {n} asked)")

    fm = doc.frontmatter
    own = hop_file_path(
        path.parent,
        fm.get("chain_root", ""),
        _fm_int(doc, "hop") or 0,
        fm.get("session_id", ""),
    )
    rel = own.relative_to(path.parent).as_posix()
    try:
        hop_before = own.read_bytes()
        hop_text = hop_before.decode("utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        return _die(1, f"cannot read this hop's file {rel} ({exc}); nothing written")

    hot = text.splitlines(keepends=True)
    hop = hop_text.splitlines(keepends=True)
    term = (_line_parts(hot[0])[1] if hot else "") or "\n"
    standing_key = fm.get("standing_rules") if fitted(doc.shape) else None
    standing_path: Path | None = None
    standing_before: bytes | None = None
    standing_text: str | None = None
    if standing_key:
        if standing_key not in standing_rels(fm.get("chain_root", "")):
            return _die(
                1,
                f"standing_rules {standing_key!r} is not this chain's standing-rules file; nothing written",
            )
        if (code := _forked(path, doc)) is not None:
            return code
        standing_path = path.parent / standing_key
        try:
            standing_before = standing_path.read_bytes()
            standing_text = standing_before.decode("utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            return _die(
                1,
                f"cannot read the standing-rules file {standing_key} ({exc}); nothing written",
            )
        joined = _join_standing(hot, standing_text, term)
        if joined is None:
            return _die(
                1,
                f"the standing-rules file {standing_key} lacks a section this file points at; nothing written",
            )
        hot = joined
    if retire:
        refs = [(item["ref"], item["reason"].strip()) for item in retire]
        moved = _apply_retire(hot, hop, refs, rel)
        if isinstance(moved, str):
            return _die(1, f"{moved}; nothing written")
        hot, hop = moved
    retired_doc = _resolved(hot, hop, rel)
    moved_to = _moved_here(_content_doc(hot), rel)
    hop_term = (_line_parts(hop[0])[1] if hop else "") or "\n"

    replaced: list[tuple[str, list[str]]] = []
    for title, value in sections.items():
        target, heading, eol = hot, title, term
        if title in moved_to:
            target, heading, eol = hop, moved_to[title], hop_term
        current = _content_doc(target)
        start = current.section_start(heading)
        if start < 0:
            return _die(
                1,
                f"section {title!r} moved to {rel}#{heading}, which that file does not hold; nothing written",
            )
        end = next(e for name, _, e in current.sections if name == heading)
        filled = [i for i in range(start + 1, end) if current.lines[i].strip()] or [
            start
        ]
        old = current.lines[filled[0] : filled[-1] + 1] if filled != [start] else []
        new = _trim_blank(_value_lines(value))
        if not new:
            return _die(1, f"section {title!r}: an empty body is never written")
        if new == old:
            return _die(
                1, f"section {title!r} already holds that text; nothing written"
            )
        if target is hop and end == len(hop) and not _line_parts(hop[-1])[1]:
            hop[-1] += hop_term
        if old:
            target[filled[0] : filled[-1] + 1] = [line + eol for line in new]
            replaced.append((title, old))
        else:
            target[start + 1 : end] = [eol, *(line + eol for line in new), eol]

    for title, items in append.items():
        lines = [line for item in items for line in _value_lines(item)]
        current = _content_doc(hot)
        held = [line for line in current.section(title) or [] if line.strip()]
        pointer = MovePointer.parse(held[0]) if len(held) == 1 else None
        if pointer is not None and pointer.moves(title):
            end = _section_end(_content_doc(hop), pointer.heading)
            if pointer.file != rel or end < 0:
                return _die(
                    1,
                    f"section {title!r} moved to {pointer.file}#{pointer.heading}, which this hop's file {rel} does not hold; nothing written",
                )
            if end == len(hop) and hop and not _line_parts(hop[-1])[1]:
                hop[-1] += hop_term
            hop[end:end] = [line + hop_term for line in lines]
            continue
        end = _section_end(current, title)
        lead = [term] if title == "Original goal" else []
        hot[end:end] = [*lead, *(line + term for line in lines)]

    if next_lines is not None:
        span = _next_span(_content_doc(hot))
        if span is None:
            return _die(
                1,
                f"no 'Next:' line after 'Handoff origin:' in the resume region of {_posix(path)}",
            )
        a, b = span
        old = _content_doc(hot).lines[a:b]
        new = [line for item in next_lines for line in _value_lines(item)]
        new = [NEXT_CLOSED] if new == [NEXT_CLOSED] else ["Next:", *new]
        if new == old:
            return _die(1, "the Next: headlines already read that way; nothing written")
        hot[a:b] = [line + term for line in new]
        replaced.append(("Resume prompt Next:", old))

    raised = dict(floors)
    for item in retire:
        m = RETIRE_REF_RE.match(item["ref"])
        if m and m["prefix"]:
            key = _family(m["prefix"]).floor_key
            raised[key] = max(raised.get(key, 0), int(m["n"]) + 1)
    current = _content_doc(hot)
    for key, n in raised.items():
        have = _fm_int(current, key)
        if have is not None and n <= have:
            continue
        at = next(
            (
                i
                for i in range(1, current.body_start)
                if current.lines[i].startswith(f"{key}:")
            ),
            None,
        )
        if at is None:
            hot.insert(current.body_start - 1, f"{key}: {n}{term}")
        else:
            hot[at] = f"{key}: {n}{_line_parts(hot[at])[1]}"
        current = _content_doc(hot)

    pred = (
        _sibling(path.parent, fm["previous_handoff"])
        if fm.get("previous_handoff")
        else None
    )
    if pred is not None:
        pred = _standing_doc(pred, _universal(hop_text)) or pred
    amended = _resolved(hot, hop, rel)
    for title in sections:
        if title in S3.retired_entry_sections:
            kept = set(_entry_units(amended, title)[0])
            prior = set(_entry_units(pred, title)[0]) if pred else set()
            for unit in _entry_units(retired_doc, title)[0]:
                if unit not in kept and unit not in prior:
                    return _die(
                        1,
                        f"section {title!r}: the rewrite removes an entry added this hop; retire it in the same call: {unit[0][:60]!r}",
                    )
        for spec in ID_SPECS:
            if title not in spec.sections:
                continue
            kept_ids = {n for n, _, _ in _id_entries(amended, spec) if n is not None}
            prior_ids = (
                {n for n, _, _ in _id_entries(pred, spec) if n is not None}
                if pred
                else set()
            )
            for n, _, where in _id_entries(retired_doc, spec):
                if where == title and n is not None and n not in kept_ids | prior_ids:
                    return _die(
                        1,
                        f"section {title!r}: the rewrite removes [{spec.prefix}{n}], added this hop; retire it in the same call",
                    )

    if replaced:
        if hop and not _line_parts(hop[-1])[1]:
            hop[-1] += hop_term
        stamp = now.strftime("%Y-%m-%dT%H:%M:%SZ")
        for title, old in replaced:
            hop += [
                hop_term,
                f"## {AMENDED_HEADING} {stamp} {title}{hop_term}",
                hop_term,
                *(line + hop_term for line in old),
            ]
    new_standing = standing_text
    index_path: Path | None = None
    index_prior: bytes | None = None
    new_index: str | None = None
    if standing_key:
        hot, new_standing = _split_standing(
            hot, standing_key, term, _standing_header(doc)
        )
        indexed = _index_split(hot, path.parent, doc, term)
        if isinstance(indexed, int):
            return indexed
        hot, index_path, new_index, index_prior = indexed
        hot = _page_standing(hot, len(new_standing.encode("utf-8")))
    index_changed = new_index is not None and new_index.encode() != index_prior
    new_hot, new_hop = "".join(hot), "".join(hop)
    if (
        new_hot == text
        and new_hop == hop_text
        and new_standing == standing_text
        and not index_changed
    ):
        return _die(1, f"nothing to amend: {_posix(path)} would not change")

    old_findings, _ = validate_doc(doc, None, False)
    built = _doc_from_lines(path, _text_lines(new_hot))
    built.size = len(new_hot.encode("utf-8"))
    findings, code = validate_doc(
        built,
        None,
        False,
        hop_text=_universal(new_hop),
        standing=_universal(new_standing) if new_standing is not None else None,
        index=new_index,
    )
    introduced = _fail_keys(findings) - _fail_keys(old_findings)
    if introduced:
        for x in findings.fails:
            if _fail_key(x.text) in introduced:
                print(f"FAIL: {x.text}", file=sys.stderr)
        return _die(
            1,
            f"the amend adds a FAIL the file did not have; nothing written: {_posix(path)}",
        )

    originals: dict[Path, bytes | None] = {own: hop_before, path: before}
    changed = [(own, new_hop, hop_text)]
    if standing_path is not None and new_standing is not None:
        originals[standing_path] = standing_before
        changed.append((standing_path, new_standing, standing_text))
    if index_path is not None and index_changed and new_index is not None:
        originals[index_path] = index_prior
        changed.append((index_path, new_index, None))
    changed.append((path, new_hot, text))
    writes = [
        (target, payload.encode("utf-8"))
        for target, payload, original in changed
        if payload != original
    ]
    staged: list[tuple[Path, str]] = []
    try:
        for target, payload in writes:
            handle, tmp = tempfile.mkstemp(
                dir=target.parent, prefix=".amend-", suffix=".tmp"
            )
            staged.append((target, tmp))
            with os.fdopen(handle, "wb") as stream:
                stream.write(payload)
    except OSError as exc:
        _unstage(staged)
        return _die(2, f"cannot stage a write ({exc}); nothing written")
    successor = _successor(path)
    if successor is not None:
        _unstage(staged)
        return _not_tip(path, successor, args.json)
    for index, (target, tmp) in enumerate(staged):
        try:
            os.replace(tmp, target)
        except OSError as exc:
            for written, _ in staged[:index]:
                original = originals[written]
                if original is not None:
                    _write_atomic(written, original)
                else:
                    written.unlink(missing_ok=True)
            _unstage(staged[index:])
            return _die(2, f"cannot write {target} ({exc}); nothing written")
    _print_verdict(built, findings, code)
    sys.stdout.flush()
    cmd_emit(
        argparse.Namespace(
            file=str(path), format=getattr(args, "format", "rails"), notice=False
        )
    )
    return 0


def _unstage(staged: list[tuple[Path, str]]) -> None:
    for _, tmp in staged:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def _git_stdout(directory: Path, *args: str) -> str | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(directory), *args],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return None
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


def _git_toplevel(start: Path) -> Path | None:
    probe = start
    while not probe.exists() and probe.parent != probe:
        probe = probe.parent
    top = _git_stdout(probe, "rev-parse", "--show-toplevel")
    return Path(top).resolve() if top else None


def _default_memory_dir() -> Path | None:
    if _git_toplevel(Path.cwd()) is not None:
        return Path(".work")
    data_root = plugin_paths.data_root(os.environ, _SCRIPTS_DIR.parent)
    return data_root / "artifacts" if data_root is not None else None


def _git_origin(repo_root: Path) -> str | None:
    return _git_stdout(repo_root, "remote", "get-url", "origin")


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


def _settle_validate(pred: Doc) -> str:
    return f"(settle: save_point.py validate {pred.basename})"


def _tag_carried(
    body: list[str], default_hop: int, unverified: bool, settle: str
) -> list[str]:
    lines = _trim_blank(body)
    marked = False
    for entry in parse_entries(body):
        if entry.exempt:
            continue
        idx = _shift_index(body, entry.first_index)
        line = lines[idx]
        if line.strip().startswith("Superseded:"):
            continue
        marker = entry.marker
        rest = line[len(marker) :]
        if m := TAG_RE.match(rest):
            tag, rest = m.group(0).rstrip(), rest[m.end() :]
        else:
            tag = f"[h{default_hop}]"
        if unverified and not UNVERIFIED_PRED_RE.match(rest):
            rest = "UNVERIFIED (predecessor failed validation): " + rest
        marked = marked or bool(UNVERIFIED_PRED_RE.match(rest))
        lines[idx] = f"{marker}{tag} {rest}"
    if marked and not any(CARRY_SETTLE_RE.match(line.strip()) for line in lines):
        lines = [CARRY_SETTLE.format(settle=settle), "", *lines]
    return lines


def _splice_new_slot(carried: list[str], slot: str) -> list[str]:
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
    if pred.shape in (None, 1):
        did_left = f"UNVERIFIED (shape-1 predecessor; brief: {_first_line(pred.section('Resumption brief'))}) (settle: read {pred.basename} § Resumption brief)"
    else:
        this = [line for line in (pred.section("This session") or []) if line.strip()]
        did_left = (
            this[0].strip()
            if this
            else f"UNVERIFIED (predecessor had no This session line) (settle: read {pred.basename})"
        )
    return (
        f"| {pred.frontmatter.get('date', 'unknown')} | {pred.frontmatter.get('session_id', 'unknown')} "
        f"| {pred_transcript} | {did_left} | {pred.basename} |"
    )


def _gone_row(name: str, status: str) -> str:
    return (
        f"| unknown | unknown | unresolved (predecessor {status}) "
        f"| UNVERIFIED (predecessor {status} when this file was written) "
        f"(settle: /session-flow:find-handoff {name}) | {name} |"
    )


def _this_session_lines() -> list[str]:
    return [
        "did: "
        + _fill("did", "what landed this session, past tense, no '|'")
        + " · left: "
        + _fill("left", "what is still open, past tense, no 'next', no '|'"),
        RESCAN_PREFIX
        + _fill(
            "rescan",
            "one line: the constraints re-scan read the lossless on-disk transcript, or 'visible conversation only; a compaction occurred this session, so pre-compaction turns were NOT re-scanned for buried constraints'",
        ),
    ]


def _launch_frontmatter(launch: tuple[str, ...]) -> str:
    json_without_inline_comments = json.dumps(launch).replace(" #", r" \u0023")
    return f"launch: {json_without_inline_comments}"


def _resume_prompt(
    target: Path,
    session_id: str,
    origin: str,
    origin_path: str,
    settings_file: str | None = None,
    launch: tuple[str, ...] = (),
    standing: Path | None = None,
) -> list[str]:
    read_path = _posix(target)
    if standing is not None:
        read_path = f"{_posix(standing)}{STANDING_THEN}{read_path}"
    settings = f' --settings "{settings_file}"' if settings_file else ""
    instructions = [LAUNCH_CHECKOUT + launch[0], LAUNCH_COMMAND + launch[1]] if launch else []
    return [
        *instructions,
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
        f"{REOPEN_PREFIX}`claude --resume {session_id}{settings}`.",
        _fill(
            "below-rail",
            "optional: the /goal and plugin-reload notes save-point.md prescribes below the bottom rail; recurring /loop, cron and monitor items go under Environment to re-establish, never here; delete this line when none applies",
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
    settings_file: str | None = None,
    launch: tuple[str, ...] = (),
    gone: tuple[str, str] | None = None,
) -> str:
    previous = pred.basename if pred is not None else (gone[0] if gone else None)
    if pred is None:
        chain = [*([gone[0]] if gone else []), target.name]
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
        f"checks: {CHECKS}",
        f"date: {date}",
        f"topic: {slug}",
        f"session_id: {session_id}",
        f"transcript: {transcript}",
        _launch_frontmatter(launch),
    ]
    if previous is not None:
        fm.append(f"previous_handoff: {previous}")
    if gone is not None:
        fm.append(f"previous_status: {gone[1]}")
    fm.append("chain:")
    fm.extend(f"  - {item}" for item in chain)
    fm.append("---")

    body: list[str] = []

    def section(title: str, lines: list[str]) -> None:
        body.extend(["", f"## {title}", "", *_trim_blank(lines)])

    goal: list[str] = []
    pred_goal = pred.section("Original goal") if pred is not None else None
    amended = "**Amended:** " + _fill(
        "amended",
        "'None.' until the goal changes; otherwise a new dated verbatim quote with the prior goal kept above it",
    )
    if pred_goal is None:
        if pred is None:
            goal += [
                "**Goal (verbatim):**",
                _fill(
                    "goal",
                    "the user's goal statement quoted as they wrote it, with the date they stated it; RECONSTRUCTED (and settled with the user) when it was never put in one sentence",
                ),
                "",
                amended,
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
                amended,
                "",
                f"Opening ask: see {chain[0]} § Original goal (shape-1 root, no verbatim ask recorded)",
            ]
    else:
        kept: list[str] = []
        skip = False
        for line in pred_goal:
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
                    lines.extend(
                        _tag_carried(
                            pred_body, pred_hop, pred_failed, _settle_validate(pred)
                        )
                    )
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

    section("This session", _this_session_lines())

    if gone is not None:
        section("Prior sessions", [PRIOR_HEADER, PRIOR_SEPARATOR, _gone_row(*gone)])
    elif pred is None:
        section("Prior sessions", [FIRST_HOP_PRIOR])
    else:
        rows = _parse_prior_rows(pred.section("Prior sessions"))
        own_row = _pred_row(pred, pred_transcript)
        section("Prior sessions", [PRIOR_HEADER, PRIOR_SEPARATOR, *rows, own_row])

    section(
        "Resume prompt",
        _resume_prompt(
            target, session_id, origin, origin_path, settings_file, launch
        ),
    )

    return "\n".join(fm + body) + "\n"


def hop_file_text(
    *, chain_root: str, hop: int, session_id: str, pred: Doc | None
) -> str:
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
    skip = {"Resume prompt"} | (
        {"Original goal"} if pred.shape in HOP_FILE_SHAPES else set()
    )
    for title, start, end in pred.sections:
        if title not in skip:
            lines += ["", f"## {title}", "", *_trim_blank(pred.lines[start + 1 : end])]
    return "\n".join(lines) + "\n"


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
    settings_file: str | None = None,
    launch: tuple[str, ...] = (),
    gone: tuple[str, str] | None = None,
    shape: int = 3,
    standing: bool = False,
) -> str:
    root, hop, start = _chain_position(pred, target.name)
    hop_rel = hop_file_path(Path(), root, hop, session_id).as_posix()
    carried = pred is not None and pred.shape in HOP_FILE_SHAPES
    converted = (
        _converted_commands(pred, hop, date) if REMINDERS in _id_specs(shape) else []
    )
    floors = {
        spec.floor_key: (
            len(converted) + 1
            if pred is not None
            and pred.shape in HOP_FILE_SHAPES
            and spec not in _id_specs(pred.shape)
            else _next_id(pred, spec)
        )
        for spec in _id_specs(shape)
    }
    next_id = floors[RULES.floor_key]
    fm = [
        "---",
        "type: handoff",
        f"handoff_shape: {shape}",
        f"checks: {CHECKS}",
        f"date: {date}",
        f"topic: {slug}",
        f"session_id: {session_id}",
        f"transcript: {transcript}",
        _launch_frontmatter(launch),
    ]
    if pred is not None:
        fm.append(f"previous_handoff: {pred.basename}")
    elif gone is not None:
        fm += [f"previous_handoff: {gone[0]}", f"previous_status: {gone[1]}"]
    fm += [
        f"chain_root: {root}",
        f"hop: {hop}",
        f"archive: {ARCHIVE_DIR}/{_stem(root)}/",
        f"archive_from: {start}",
        *([f"standing_rules: {standing_rel(root)}"] if standing else []),
        *(f"{key}: {value}" for key, value in floors.items()),
        f"repo: {origin}",
        "---",
    ]
    bodies: dict[str, list[str]] = {}

    def section(title: str, lines: list[str]) -> None:
        bodies[title] = ["", f"## {title}", "", *_trim_blank(lines)]

    amended = _fill(
        "amended",
        "'None.' until the owner amends the goal; otherwise the dated verbatim amendment",
    )
    goal_new = _fill(
        "goal-new",
        f"optional: a new dated verbatim owner amendment, or the owner's intent and vision lines when this section lacks them, appended below; the lines above are copied off disk and never rewritten here: an amendment that no longer binds leaves only through the slots' 'retire' list as {{'ref': 'amendment#<i>', 'reason': ...}} (i counts amendment units from the top), which lists it in {hop_rel} under '## {S3.retired_entry_sections['Original goal']}'; a unit with any clause still binding stays whole, or that clause is first written as an [R<n>] rule and the unit retired 'codified in [R<n>]'; delete this line when nothing changes",
    )
    if pred is None or pred.section("Original goal") is None:
        goal = [
            "**Goal (verbatim):**",
            _fill(
                "goal",
                "the user's goal statement quoted as they wrote it, with the date they stated it"
                if pred is None
                else "RECONSTRUCTED from the transcript; settle with the user (the shape-1 predecessor recorded no Original goal)",
            ),
            "",
            "**Intent (verbatim):** "
            + _fill(
                "intent",
                "why the work exists, in the owner's words; 'None stated.' when they gave none",
            ),
            "",
            "**Vision (verbatim):** "
            + _fill(
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
                _fill(
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
            *(_retire_pointers(pred) if carried else []),
            _fill(
                "review",
                f"what to read before the next action, tailored to it: each archive section by file and heading (this hop's moved sections are in {hop_rel}), each instruction file a preference points at, and each command that re-reads live state; 'None.' plus a reason when this file suffices",
            ),
        ],
    )

    trail_line = f"one line per change of direction, '- [h<k>] <change> (<cause>)', the cause owner-directed (quoting the owner) or agent-initiated; flag a remaining action that serves no recorded goal or detour as '- [h{hop}] DRIFT: <action>'"
    trail_retire = f"; a carried line that no longer bears on the work leaves only through the slots' 'retire' list as {{'ref': '[h<k>]#<i>', 'reason': ...}} (i counts the lines tagged [h<k>]), which lists it in {hop_rel} under '## {S3.retired_entry_sections['Direction changes']}'"
    if carried:
        pointer, kept, folded = None, [], False
        held = follow(
            pred.section("Direction changes") or [],
            "Direction changes",
            pred.path.parent,
        )
        for line in _trim_blank(held or []):
            if line.startswith(FOLD_PREFIX):
                pointer = line
            elif _folds(line, hop):
                folded = True
            else:
                kept.append(line)
        if folded:
            pointer = f"{FOLD_PREFIX}lines {DIRECTION_HOPS_KEPT} or more hops old are verbatim under '## Direction changes' in the hop file of the hop that folded them, the newest {hop_rel}"
        trail = [
            *([pointer] if pointer else []),
            *_trim_blank(kept),
            "",
            _fill(
                "trail-new",
                f"optional: this hop's lines below the carried ones, {trail_line}{trail_retire}; `new` folds a line out once it is {DIRECTION_HOPS_KEPT} hops old, and the '{FOLD_PREFIX.strip()}' line pointing at the folded lines stays; delete this line when the direction did not change",
            ),
        ]
    elif pred is None:
        trail = [
            _fill(
                "trail",
                f"'- [h1] start: <where the work starts> (<cause>)', then {trail_line}",
            )
        ]
    else:
        trail = [
            _fill(
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

    def id_body(title: str, name: str, instruction: str) -> list[str]:
        spec = next(
            (s for s in ID_SPECS if s != RULES and title in s.sections), None
        )
        if spec == REMINDERS and converted:
            carried_lines = converted
        elif spec is None or not _carries(pred, spec):
            return [_fill(name, instruction)]
        else:
            carried_lines = _section_lines(pred, title)
        ref = f"[{spec.prefix}<n>]"
        entry_shape = {
            "Q": f"'- {ref} <question>' with its options, a recommendation and what it unblocks",
            "D": f"'- {ref} <decision> (<reason>)', a decision the remaining actions depend on; {DECISION_TAG_SHAPE}",
            "M": f"{REMINDER_SHAPE}",
        }[spec.prefix]
        return [
            *carried_lines,
            "",
            _fill(
                f"{name}-new",
                f"optional: new entries below the carried ones, one per line, {entry_shape}, new ids from {spec.prefix}{floors[spec.floor_key]}; a carried entry is copied off disk and keeps its text, or is rewritten in place under its id ending with '{REWRITE_MARK} h{hop}: <why>', its prior text staying in {hop_rel}; one that no longer bears on the work leaves only through the slots' 'retire' list as {{'ref': '{ref}', 'reason': ...}}, which lists it in {hop_rel} under '## {spec.retired_heading}'; write 'None.' plus a reason here when that list empties the section; delete this line when nothing changes",
            ),
        ]

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
            f"one per line, '- [Q<n>] <question>' with its options, a recommendation and what it unblocks, new ids from Q{floors['next_question_id']}; a carried question keeps its id; one that is answered or no longer bears on the work leaves only through the slots' 'retire' list as {{'ref': '[Q<n>]', 'reason': ...}}, which lists it in {hop_rel} under '## {S3.id_spec('Q').retired_heading}'; 'None.' plus a reason when there are none",
        ),
    ):
        section(title, id_body(title, name, instruction))

    rule_line = f"one per line, '- [R<n>] <the rule's current text, verbatim>', new ids from R{next_id}; a rule binding beyond this chain's goal goes under Standing preferences"
    if carried:
        rules = [
            *_section_lines(pred, "Current rules"),
            "",
            _fill(
                "rules-new",
                f"optional: new rules, {rule_line}; a changed rule is rewritten in place under its id, its prior text staying in {hop_rel}; one that no longer binds leaves only through the slots' 'retire' list as {{'ref': '[R<n>]', 'reason': ...}}, which lists it in {hop_rel} under '## {RETIRED_RULES}'; no rule leaves to meet the size cap; delete this line when nothing changes",
            ),
        ]
    else:
        source = (
            ""
            if pred is None
            else f" (the predecessor's constraints are in {hop_rel} § Constraints that must hold)"
        )
        rules = [
            _fill(
                "rules",
                f"every goal-scoped rule in force{source}, {rule_line}; 'None.' plus a reason when none applies",
            )
        ]
    section("Current rules", rules)

    for title, name, instruction in (
        (
            "Observations",
            "observations",
            f"session-wide observations, summarized, one line each, each claim about code or state dated and a code claim citing its commit (save-point.md, 'Write history, not the present'); detail stays in {hop_rel} or the transcript; no live GitHub state, list its re-read command under Review before you continue",
        ),
        (
            "Pending commands",
            "commands",
            "every command waiting on the user, verbatim; 'None.' plus a reason when none waits",
        ),
        (
            "Reminders",
            "reminders",
            f"one per line, {REMINDER_SHAPE}, new ids from M{floors.get(REMINDERS.floor_key, 1)}; every item that affects a later session: a user-run command gated on a condition, a timed reminder, a point to raise at chain close; one that is done leaves only through the slots' 'retire' list as {{'ref': '[M<n>]', 'reason': ...}}, which lists it in {hop_rel} under '## {REMINDERS.retired_heading}'; 'None.' plus a reason when nothing waits",
        ),
        (
            "Environment to re-establish",
            "environment",
            f"branch and worktree, services, env vars, background tasks and the live task list with literal recreate calls, or a line that there is nothing to recreate; {RECURRING_SHAPE}",
        ),
        (
            "Decisions in force",
            "decisions",
            f"one per line, '- [D<n>] <decision> (<reason>)', the decisions the remaining actions depend on, a claim about code or state in one dated (save-point.md, 'Write history, not the present'), new ids from D{floors['next_decision_id']}; {DECISION_TAG_SHAPE}; a carried decision keeps its id; one that no longer bears on the work leaves only through the slots' 'retire' list as {{'ref': '[D<n>]', 'reason': ...}}, which lists it in {hop_rel} under '## {S3.id_spec('D').retired_heading}'; settled history stays in the archive",
        ),
        (
            "Suggested skills",
            REWRITTEN["Suggested skills"][0],
            REWRITTEN["Suggested skills"][1] + (PURPOSE_SKILLS if purpose else ""),
        ),
    ):
        section(title, id_body(title, name, instruction))

    section("This session", _this_session_lines())

    if gone is not None:
        section("Prior sessions", [PRIOR_HEADER, PRIOR_SEPARATOR, _gone_row(*gone)])
    elif pred is None:
        section("Prior sessions", [FIRST_HOP_PRIOR])
    else:
        rows = [
            *_parse_prior_rows(pred.section("Prior sessions")),
            _pred_row(pred, pred_transcript),
        ]
        section(
            "Prior sessions", [PRIOR_HEADER, PRIOR_SEPARATOR, *rows[-PRIOR_ROWS_KEPT:]]
        )

    pref_line = f"one per line, '- [R<n>] <the preference, verbatim> (pending promotion: <instruction file>)', ids shared with Current rules; a preference its instruction file already holds leaves only through the slots' 'retire' list as {{'ref': '[R<n>]', 'reason': 'promoted to <instruction file>'}}, which lists it in {hop_rel} under '## {RETIRED_RULES}'"
    if carried:
        prefs = [
            *_section_lines(pred, "Standing preferences"),
            "",
            _fill(
                "preferences-new",
                f"optional: new standing preferences, {pref_line}; delete this line when nothing changes",
            ),
        ]
    else:
        prefs = [
            _fill(
                "preferences",
                f"each standing preference not yet in its instruction file, {pref_line}; 'None.' plus a reason when none is pending",
            )
        ]
    section("Standing preferences", prefs)

    section(
        "Resume prompt",
        _resume_prompt(
            target,
            session_id,
            origin,
            origin_path,
            settings_file,
            launch,
            target.parent / standing_rel(root) if standing else None,
        ),
    )
    body = [line for title in SHAPES[shape].names for line in bodies[title]]
    return "\n".join(fm + body) + "\n"


NO_MEMORY_ROOT = "no project root (cwd has no git top level) and no plugin data dir: CLAUDE_PLUGIN_DATA is unset and this script is not running from an installed plugin cache"


def cmd_memory_root(args: argparse.Namespace) -> int:
    root = _default_memory_dir()
    if root is None:
        return _die(1, NO_MEMORY_ROOT)
    print(root.expanduser().resolve().as_posix())
    return 0


def cmd_new(args: argparse.Namespace) -> int:
    slug = args.topic
    if not SLUG_RE.match(slug):
        return _die(2, f"topic slug {slug!r} must match {SLUG_RE.pattern}")

    purpose = " ".join((args.purpose or "").split()) or None
    if purpose and ("<!--" in purpose or "-->" in purpose):
        return _die(2, "--purpose must not carry '<!--' or '-->'; rewrite it without")
    for name, held, budget in handoff_fit.slot_overruns({"brief": purpose or ""}):
        print(
            f"WARN: --purpose is {held} bytes, over the {budget}-byte budget of slot '{name}' it opens; shorten it",
            file=sys.stderr,
        )

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

    settings_file = args.settings_file or None
    if settings_file and any(c in settings_file for c in '"`\n\r'):
        return _die(
            2,
            "--settings-file must not carry a double quote, a backtick or a line break",
        )
    start_command = args.start_command or None
    if start_command and any(c in start_command for c in "`\n\r"):
        return _die(2, "--start-command must not carry a backtick or a line break")

    if args.memory_dir:
        memory_dir = Path(args.memory_dir).expanduser().resolve()
    elif args.repo_root:
        memory_dir = Path(".work").resolve()
    else:
        default = _default_memory_dir()
        if default is None:
            return _die(1, f"{NO_MEMORY_ROOT}; pass --memory-dir <root> explicitly")
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
    gone: tuple[str, str] | None = None
    if args.previous:
        pred_path = Path(args.previous).expanduser()
        if not _same_file(str(pred_path.parent), handoffs):
            return _die(
                1,
                f"predecessor must live in the handoffs dir the new file is written to ({handoffs.as_posix()}); got {_posix(pred_path)}",
            )
        if not pred_path.is_file():
            gone = (pred_path.name, "missing")
        else:
            try:
                pred = parse_doc(pred_path)
            except (OSError, UnicodeDecodeError):
                gone = (pred_path.name, "unreadable")
        if gone is not None and not HANDOFF_NAME_RE.match(gone[0]):
            return _die(
                1,
                f"predecessor {gone[1]} and {gone[0]!r} is not a <TS>-handoff-<topic>.md name: {_posix(pred_path)}",
            )
        if gone is not None:
            print(
                f"WARN: predecessor {gone[0]} is {gone[1]}; the new handoff names it as previous_handoff with previous_status: {gone[1]} and starts its checks afresh",
                file=sys.stderr,
            )
    if pred is not None:
        pred_path = pred.path
        if not pred.has_frontmatter or pred.frontmatter.get("type") != "handoff":
            return _die(
                1,
                f"predecessor is not a handoff file (no 'type: handoff' frontmatter): {pred_path}",
            )
        if isinstance(pred.shape, int) and pred.shape > NEWEST_SHAPE:
            return _die(
                1,
                f"predecessor carries handoff_shape {pred.shape}, newer than this script knows ({NEWEST_SHAPE}): read it, do not build on it; update session-flow, then re-run",
            )
        if args.shape is None and pred.shape in HOP_FILE_SHAPES:
            args.shape = max(HANDOFF_SHAPE, pred.shape)
        if pred.shape in HOP_FILE_SHAPES and args.shape < pred.shape:
            return _die(
                1,
                f"predecessor is shape {pred.shape}; a shape-{pred.shape} chain is never continued as shape {args.shape}",
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
    if args.shape is None:
        args.shape = HANDOFF_SHAPE
    standing = bool(args.standing_rules) or (
        pred is not None
        and fitted(pred.shape)
        and bool(pred.frontmatter.get("standing_rules"))
    )
    if standing and not fitted(args.shape):
        return _die(
            2,
            f"a standing-rules file belongs to a shape-4 chain; this hop is shape {args.shape}",
        )
    if pred is not None and _standing_pointed(pred):
        text, rel = _standing_text(pred)
        resolved = _standing_doc(pred, text) if text is not None else None
        if resolved is None:
            return _die(
                1,
                f"predecessor's standing rules are unreadable: {rel} is not on disk or lacks a section the predecessor points at; restore it, then re-run",
            )
        pred = resolved
    if pred is not None and pred.shape in HOP_FILE_SHAPES:
        rel, text = _read_index(pred)
        if rel is not None and text is None:
            return _die(
                1,
                f"predecessor's retired-entries index {rel} is not on disk or is not its chain's; restore it, then re-run",
            )
        if text is not None:
            pred = _index_doc(pred, text)

    if repo_root is not None:
        origin = origin_identity(_git_origin(repo_root), repo_root.name)
        try:
            origin_path = target.resolve().relative_to(repo_root).as_posix()
        except ValueError:
            origin_path = _posix(target)
    else:
        origin = memory_dir.parent.name or memory_dir.name
        origin_path = _posix(target)

    launch = ()
    if start_command or args.launch_dir:
        checkout = (
            Path(args.launch_dir).expanduser().resolve()
            if args.launch_dir else repo_root or _git_toplevel(Path.cwd()) or Path.cwd()
        )
        if checkout.as_posix().splitlines() != [checkout.as_posix()]:
            return _die(2, "the launch checkout must fit on one line")
        launch = (checkout.as_posix(), start_command or "claude")
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
        settings_file=settings_file,
        launch=launch,
        gone=gone,
    )
    if args.shape == 2:
        content = build_skeleton(**common, pred_failed=pred_failed)
    else:
        content = build_skeleton_3(**common, shape=args.shape, standing=standing)
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
            try:
                existing = parse_doc(hop_path)
            except (OSError, UnicodeDecodeError):
                existing = None
            owner = existing.frontmatter.get("session_id", "") if existing else ""
            if existing is None or owner.lower() != session_id:
                return _die(
                    1,
                    f"hop file {_posix(hop_path)} belongs to session {owner or 'unknown'}, not {session_id}; never overwritten",
                )
            held = _held_heading(existing)
            if held:
                return _die(
                    1,
                    f"hop file {_posix(hop_path)} holds '## {held}' content a rewrite would erase; fold a late event in with `save_point.py amend <hot file> --json <path>`, never a second `new`",
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
    try:
        handoff_fit.over_budget_marker(target).unlink(missing_ok=True)
    except OSError:
        pass
    print(_posix(target))
    if fitted(args.shape):
        skeleton = content
        if standing:
            split, _ = _split_standing(
                content.splitlines(keepends=True), standing_rel(root), "\n", []
            )
            split, _ = _split_index(split, index_rel(root), "\n", None, [])
            skeleton = "".join(split)
        print(_budget_line(skeleton, args.shape), file=sys.stderr)
    return 0


def _budget_line(skeleton: str, shape: int) -> str:
    cap = SHAPES[shape].cap_bytes or HOT_FILE_MAX_BYTES
    fixed = len(FILL_SLOT_RE.sub("", skeleton).encode("utf-8"))
    slots = ", ".join(
        f"{name} {n} bytes" for name, n in handoff_fit.SLOT_BUDGETS.items()
    )
    return f"budget: {cap - fixed} bytes for the written slots ({cap}-byte cap, {fixed} bytes written by new); slot budgets: {slots}; movable sections ({', '.join(handoff_fit.MOVE_ORDER)}) move to this hop's file past the cap"


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


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="save_point.py",
        description="Handoff save-point engine: new / fill / amend / validate / emit.",
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
    p_new.add_argument(
        "--settings-file",
        help='the session\'s plugin profile settings file (the `file` of `/plugin-profiles:profile launch --json`); the resume line then carries --settings "<file>"',
    )
    p_new.add_argument(
        "--start-command",
        nargs="?",
        const="claude",
        help="emit a new-session launch using the plugin-profiles command, or plain claude when given without a value",
    )
    p_new.add_argument("--launch-dir", help="destination checkout for a new session (default: the producing checkout)")
    p_new.add_argument("--now", help="ISO-8601 UTC timestamp override (tests)")
    p_new.add_argument(
        "--shape",
        type=int,
        choices=WRITABLE_SHAPES,
        default=None,
        help=f"shape to write (default {HANDOFF_SHAPE}, or the predecessor's shape when newer; shape 2 builds no hot file or archive)",
    )
    p_new.add_argument(
        "--standing-rules",
        action="store_true",
        help="role chain: `fill` keeps Current rules, Standing preferences and Decisions in force in the chain's standing-rules/<chain>.md and the retire pointers in archive/<chain>/retired-index.md, the hot file holds a pointer to each, and the resume prompt loads the standing-rules file first; a successor of such a hop keeps it without the flag (shape 4 only)",
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
        help="path to a JSON file holding an object keyed by slot name, plus an optional retire [{ref, reason}]; an optional slot left out has its line deleted",
    )
    p_fill.set_defaults(func=cmd_fill)

    p_amend = sub.add_parser(
        "amend",
        help="fold a late event into a filled shape-3 hot file and its hop file",
    )
    p_amend.add_argument("file")
    p_amend.add_argument(
        "--json",
        required=True,
        help="path to a JSON file holding an object with any of: sections {title: body}, append {title: [lines]}, retire [{ref, reason}], next [lines], floors {key: n}",
    )
    p_amend.add_argument("--now", help="ISO-8601 UTC timestamp override (tests)")
    p_amend.add_argument(
        "--format",
        choices=("rails", "markdown"),
        default="rails",
        help="the format of the prompt printed after the verdict, as emit takes it",
    )
    p_amend.set_defaults(func=cmd_amend)

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

    p_emit = sub.add_parser("emit", help="print the stored copy regions and any new-session launch command")
    p_emit.add_argument("file")
    p_emit.add_argument("--shell", choices=("posix", "powershell"), help="override the platform's launch shell")
    p_emit.add_argument(
        "--format",
        choices=("rails", "markdown"),
        default="rails",
        help="markdown: fenced blocks for a surface that renders markdown (Desktop, web); the file is untouched",
    )
    p_emit.set_defaults(func=cmd_emit)

    p_launch = sub.add_parser("launch", help="print a new-session command for a prepared prompt-only file")
    p_launch.add_argument("file")
    p_launch.add_argument("--checkout", required=True, help="absolute destination checkout")
    p_launch.add_argument("--start-command", default="claude", help="the command returned by plugin-profiles")
    p_launch.add_argument("--shell", choices=("posix", "powershell"))
    p_launch.set_defaults(func=cmd_launch)

    p_read = sub.add_parser(
        "read",
        help="print one section's body; a section moved to its hop file is read from there",
    )
    p_read.add_argument("file")
    p_read.add_argument("--section", required=True, help="the heading, without '## '")
    p_read.set_defaults(func=cmd_read)

    p_chain = sub.add_parser(
        "chain",
        help="the file's chain: each hot file reached, and each hop's sections from hot or hop files",
    )
    p_chain.add_argument("file")
    p_chain.add_argument("--json", action="store_true", help="print JSON")
    p_chain.set_defaults(func=cmd_chain)

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
