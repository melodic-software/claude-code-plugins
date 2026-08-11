#!/usr/bin/env python3
"""Read-only inventory of a Claude Code installation directory (`~/.claude`).

The engine answers four questions and refuses to answer a fifth:

1. What is actually in this tree, split into an authored surface that is listed
   per file and bulk trees that are rolled up?
2. Which paths does Claude Code's own retention sweep already own, and is that
   sweep running?
3. For every filename that carries a number, what IS that number -- and is a
   process-liveness lookup even a valid question to ask about it?
4. Is this tree in a deliberate, experimental, or mid-restore state that makes
   "looks like decay" the wrong reading?

The fifth question -- "so what should I delete?" -- is deliberately not
answered. This engine never writes to, moves, or removes anything in the target
tree, and it never reads the bytes of a secret-bearing file.

Every emitted claim carries an ``evidence`` tag (``measured`` /
``documented-default`` / ``inferred``) and every count that can move while the
scan runs is emitted as ``{min, max, n}`` rather than a single number. Those two
properties are structural: an unlabeled claim and a bare central tendency are
not representable in the output schema.

Python 3.11+.
"""

from __future__ import annotations

import argparse
import csv
import dataclasses
import fnmatch
import json
import os
import platform
import re
import stat
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path, PurePosixPath

MIN_PYTHON = (3, 11)

# --------------------------------------------------------------------------
# Evidence vocabulary
# --------------------------------------------------------------------------

MEASURED = "measured"
DOCUMENTED_DEFAULT = "documented-default"
INFERRED = "inferred"

# --------------------------------------------------------------------------
# Secrets: paths whose CONTENTS are never opened by this engine.
#
# `stat` is permitted (name, size, mtime are inventory line-items). Reading
# bytes is not. `ide/*.lock` is on this list because its body carries an
# `authToken`; the cost of not reading it is that the real PID inside stays
# unknown, which is the correct answer for a report-only pass -- see
# reference/name-schemes.md.
# --------------------------------------------------------------------------

NEVER_READ_GLOBS = (
    ".credentials.json",
    "daemon/control.key",
    "daemon/pipe.key",
    "ide/*.lock",
    "*.key",
    "*.pem",
)


# The complete set of files inside the target tree whose BYTES this engine
# opens. Everything else -- including every file deposited by a sibling plugin
# -- is stat-only. A plugin owns its own state; this engine inventories such
# paths by name, size and mtime, and does not parse them or attribute an owner.
CONTENT_READ_ALLOWLIST = (
    "settings.json",
    ".last-cleanup",
    "plugins/.last_inuse_sweep",
)


class SecretReadRefused(RuntimeError):
    """Raised when the engine is asked to read the bytes of a secret file."""


def is_never_read(relpath: str) -> bool:
    """True when `relpath` (POSIX-style, relative to the root) is secret-bearing."""
    # `lstrip("./")` would eat the leading dot of a dotfile and turn
    # `.credentials.json` into an unmatched `credentials.json`. Strip the `./`
    # prefix as a prefix, not as a character set.
    rel = relpath.replace("\\", "/")
    while rel.startswith("./"):
        rel = rel[2:]
    return any(fnmatch.fnmatchcase(rel, pat) for pat in NEVER_READ_GLOBS) or any(
        fnmatch.fnmatchcase(PurePosixPath(rel).name, pat) for pat in NEVER_READ_GLOBS
    )


def read_text_guarded(root: Path, relpath: str, limit: int = 2_000_000) -> str:
    """Read a file's text, refusing outright for anything on the never-read list.

    The guard lives in the reader, not in each call site, so a future check
    cannot reach a secret by forgetting to consult the list.
    """
    if is_never_read(relpath) or relpath not in CONTENT_READ_ALLOWLIST:
        raise SecretReadRefused(relpath)
    return (root / relpath).read_text(encoding="utf-8", errors="replace")[:limit]


# --------------------------------------------------------------------------
# Surfaces: what upstream documents about each path under ~/.claude
#
# Basis for every SWEPT / KEPT row: https://code.claude.com/docs/en/claude-directory.md
# ("Application data" -> "Cleaned up automatically" / "Kept until you delete
# them"), read as raw markdown, verified 2026-08-11. See reference/surfaces.md.
# --------------------------------------------------------------------------

SWEPT = "product-managed-swept"  # deleted at startup once older than cleanupPeriodDays
KEPT = "product-managed-kept"  # documented as never age-swept
SESSION_SCOPED = "product-managed-session-scoped"  # removed at session exit, not age-swept
AUTHORED = "authored"  # you wrote it; the product will not remove it
SECRET = "secret"  # never-read list
UNCLASSIFIED = "unclassified"  # not in any upstream table -- the interesting bucket

# name -> (surface, note). Keys are matched case-SENSITIVELY against the literal
# directory entry name; see `classify_entry` for why.
SURFACE_TABLE: dict[str, tuple[str, str]] = {
    # Cleaned up automatically (age-swept at cleanupPeriodDays)
    "projects": (SWEPT, "Transcripts, subagent transcripts, spilled tool results, auto memory"),
    "file-history": (SWEPT, "Pre-edit snapshots for checkpoint restore"),
    "plans": (SWEPT, "Plan files written during plan mode"),
    "debug": (SWEPT, "Per-session debug logs (--debug / /debug only)"),
    "paste-cache": (SWEPT, "Contents of large pastes"),
    "image-cache": (SWEPT, "Attached images"),
    "session-env": (SWEPT, "Per-session environment metadata"),
    "tasks": (SWEPT, "Per-session task lists"),
    "shell-snapshots": (SWEPT, "Shell state captured at startup; removed on clean exit"),
    "backups": (SWEPT, "Timestamped copies of ~/.claude.json taken before config migrations"),
    "feedback-bundles": (SWEPT, "Redacted transcript archives written by /feedback"),
    "todos": (SWEPT, "Legacy; no longer written. Sweep removes contents then the directory"),
    "statsig": (SWEPT, "Legacy; no longer written. Sweep removes contents then the directory"),
    "logs": (SWEPT, "Legacy; no longer written. Sweep removes contents then the directory"),
    # Kept until you delete them
    "history.jsonl": (KEPT, "Every prompt typed, with timestamp and project path"),
    "stats-cache.json": (KEPT, "Aggregated token and cost counts shown by /usage"),
    "remote-settings.json": (KEPT, "Cached server-managed settings for your organization"),
    "policy-limits.json": (KEPT, "Cached feature policy settings for your organization"),
    "cache": (KEPT, "cache/changelog.md is a cached copy of the Claude Code changelog"),
    # Session-scoped, explicitly NOT age-swept
    "sessions": (
        SESSION_SCOPED,
        "One file per running session; removed at session exit, crash leftovers cleared at launch",
    ),
    # Authored / explicitly do-not-delete
    "settings.json": (AUTHORED, "Primary user settings. Upstream: do not delete"),
    "settings.local.json": (AUTHORED, "Personal overrides"),
    "CLAUDE.md": (AUTHORED, "Global memory file"),
    "rules": (AUTHORED, "Topic-scoped instructions"),
    "skills": (AUTHORED, "User-scope skills"),
    "commands": (AUTHORED, "Legacy single-file prompts; same mechanism as skills"),
    "agents": (AUTHORED, "Subagent definitions"),
    "agent-memory": (AUTHORED, "Persistent memory for subagents"),
    "output-styles": (AUTHORED, "Custom system-prompt sections"),
    "workflows": (AUTHORED, "Dynamic workflow scripts saved from /workflows"),
    "themes": (AUTHORED, "Custom color themes"),
    "keybindings.json": (AUTHORED, "Custom keyboard shortcuts"),
    "hooks": (AUTHORED, "Hook scripts referenced from settings.json"),
    "plugins": (
        AUTHORED,
        "Marketplaces, installed versions, per-plugin data. Upstream: do not delete. "
        "Orphaned versions are removed 14 days after update/uninstall",
    ),
    # Secrets
    ".credentials.json": (SECRET, "OAuth/API credentials -- never opened"),
    "daemon": (SECRET, "Contains control.key / pipe.key -- those two are never opened"),
}

# What the sweep's unit of retention actually is, where upstream says so. This
# decides whether a file whose mtime exceeds the window means anything at all.
#
# It usually does not. `file-history/` retains by CHECKPOINT COUNT, and keeps
# each file's first snapshot regardless of age; per-session directories age out
# with their session, not with each contained file. A per-file mtime comparison
# on those paths measures something real and proves nothing about the sweep.
SWEEP_UNIT: dict[str, str] = {
    "projects": (
        "the session transcript; subagent and tool-result directories are removed WITH their "
        "parent transcript, so a contained file's own mtime is not the unit"
    ),
    "file-history": (
        "the 100 most recent checkpoints, per session directory. Snapshots no retained checkpoint "
        "references are deleted -- EXCEPT each file's first snapshot, which is kept regardless of "
        "age. Old mtimes here are expected and are not evidence of a stalled sweep"
    ),
    "session-env": "the per-session directory",
    "tasks": "the per-session entry",
    "debug": "the per-session log",
}

SWEEP_UNIT_UNDOCUMENTED = (
    "not documented upstream at per-file granularity, so it is unknown whether the sweep keys on "
    "each file's mtime or on a containing unit"
)

# Directories whose contents are session-keyed or otherwise churn while a scan
# runs. A clean unanimous small-n count over one of these is a red flag, not a
# confirmation (see reference/evidence-discipline.md).
VOLATILE_DIRS = frozenset({"sessions", "backups", "projects", "shell-snapshots", "ide", "tasks"})

# --------------------------------------------------------------------------
# Deliberate / experimental state
#
# Runs BEFORE any staleness classification. A directory holding one of these
# ledgers is the sole copy of somebody's revert path until proven otherwise.
# --------------------------------------------------------------------------

# Names that mean "somebody's revert path" almost wherever they appear.
STRONG_LEDGER_GLOBS = (
    "RESTORE.md",
    "RESTORE.txt",
    "PLAYBOOK.md",
    "restore*.py",
    "restore*.sh",
)

# Names that mean it only in the right neighbourhood. Scanned across the whole
# tree these are pure noise -- a live run over a real install matched browser
# payloads, plugin-cache test fixtures and subagent directories, and deny-listed
# most of the tree. Restricted to a shallow hotspot they are high signal.
CORROBORATING_LEDGER_GLOBS = (
    "manifest.json",
    "*baseline*.json",
    "*BASELINE*",
)

# Where a revert store is most likely to hide, and least likely to be looked for.
DELIBERATE_STATE_HOTSPOTS = ("plugins/data",)

# Corroborating names count only this many directory levels below a hotspot.
# A real revert store sits at `plugins/data/<plugin-id>/<experiment>/`; vendored
# payloads bury their manifests far deeper.
HOTSPOT_CORROBORATING_MAX_DEPTH = 3

# Vendored upstream payloads. Their `RESTORE.md` or `baseline.json` belongs to
# somebody else's repository, not to this install's state.
LEDGER_SCAN_SKIP_PREFIXES = ("plugins/cache", "plugins/marketplaces")

# --------------------------------------------------------------------------
# Numeric filename schemes -- the PID trap
#
# A number in a filename is NOT reliably a PID. Applying a process lookup to a
# non-PID returns a meaningless miss that reads as "dead" and authorizes a wrong
# deletion. Liveness is attempted for exactly one meaning: PID. Everything else,
# INCLUDING every pattern this table does not recognise, returns
# `not_applicable`.
# --------------------------------------------------------------------------

PID = "pid"
TCP_PORT = "tcp_port"
MSYS_SHELL_PID = "msys_shell_pid"
EPOCH_MS = "epoch_ms"
CONTENT_HASH = "content_hash"
SESSION_UUID = "session_uuid"
NO_NUMBER = "none"
UNKNOWN_MEANING = "unknown"


@dataclasses.dataclass(frozen=True)
class NameScheme:
    pattern: str
    meaning: str
    note: str

    def matches(self, rel: str) -> bool:
        return re.fullmatch(self.pattern, rel) is not None


NAME_SCHEMES: tuple[NameScheme, ...] = (
    NameScheme(
        r"sessions/\d+\.json",
        PID,
        "Genuine OS process id of a running Claude Code session. Liveness is valid here.",
    ),
    NameScheme(
        r"ide/\d+\.lock",
        TCP_PORT,
        "The number is a listening TCP port, not a PID. The real PID is inside the file body, "
        "which also carries an authToken -- this engine does not open it.",
    ),
    NameScheme(
        r"rate-limit-guard/.*\.tmp\.\d+",
        MSYS_SHELL_PID,
        "Git Bash / MSYS2 `$$`, a shell PID in its own namespace, not an OS PID. "
        "Judge by age and zero length instead.",
    ),
    NameScheme(
        r"shell-snapshots/snapshot-[A-Za-z0-9_]+-\d{10,}-[0-9a-zA-Z]+(\.[A-Za-z0-9]+)?",
        EPOCH_MS,
        "Epoch milliseconds plus a random suffix. No PID is present anywhere in the name.",
    ),
    NameScheme(
        r"backups/\.claude\.json\.backup\.\d{10,}",
        EPOCH_MS,
        "Epoch milliseconds. Rotating buffer, retained at 5 by design.",
    ),
    NameScheme(
        r"paste-cache/[0-9a-f]{8,}(\.[A-Za-z0-9]+)?",
        CONTENT_HASH,
        "Hex content hash.",
    ),
    NameScheme(
        r"session-env/[0-9a-fA-F-]{36}(/.*)?",
        SESSION_UUID,
        "Session UUID directory.",
    ),
    NameScheme(
        r"file-history/[0-9a-fA-F-]{36}(/.*)?",
        SESSION_UUID,
        "Session UUID directory.",
    ),
    NameScheme(
        r"tasks/[0-9a-fA-F-]{36}(\.[A-Za-z0-9]+)?",
        SESSION_UUID,
        "Session UUID.",
    ),
    NameScheme(
        r"projects/[^/]+/[0-9a-fA-F-]{36}(\.jsonl|/.*)?",
        SESSION_UUID,
        "Session UUID transcript or per-session directory.",
    ),
)

_HAS_DIGITS = re.compile(r"\d")

# Liveness verdicts. `dead` is reachable ONLY from a successful probe that
# positively reported no such process.
ALIVE = "alive"
DEAD = "dead"
UNVERIFIED = "unverified"
NOT_APPLICABLE = "not_applicable"


@dataclasses.dataclass(frozen=True)
class NameVerdict:
    number_meaning: str
    liveness: str
    reason: str
    evidence: str
    pid: int | None = None


def classify_name(rel: str) -> tuple[str, str]:
    """Return `(number_meaning, note)` for a root-relative POSIX path.

    Unrecognised names carrying digits return `unknown`, never a guess. That
    default is the safety property: a third-party plugin this table has never
    seen fails closed.
    """
    rel = rel.replace("\\", "/")
    for scheme in NAME_SCHEMES:
        if scheme.matches(rel):
            return scheme.meaning, scheme.note
    if _HAS_DIGITS.search(PurePosixPath(rel).name):
        return UNKNOWN_MEANING, "No known scheme matches this name; the number's meaning is unknown."
    return NO_NUMBER, "No number in this name."


def extract_pid(rel: str) -> int | None:
    """Extract the PID from a name already classified as carrying one."""
    match = re.search(r"(\d+)", PurePosixPath(rel).name)
    return int(match.group(1)) if match else None


def probe_pid(pid: int) -> tuple[str, str]:
    """Return `(verdict, reason)` for an OS process-id lookup.

    This is the single OS-specific seam in the engine. Every other check is
    pure `os.walk` + `stat` + regex and behaves identically everywhere.

    A probe that cannot run, or that returns something the caller cannot
    interpret, yields `unverified`. It never yields `dead`.
    """
    if pid <= 0:
        return UNVERIFIED, f"nonsensical pid {pid}"
    if os.name == "nt":
        try:
            import ctypes
            from ctypes import wintypes

            PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
            ERROR_INVALID_PARAMETER = 87
            ERROR_ACCESS_DENIED = 5
            kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
            kernel32.OpenProcess.restype = wintypes.HANDLE
            handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
            if handle:
                kernel32.CloseHandle(handle)
                return ALIVE, "OpenProcess succeeded"
            err = ctypes.get_last_error()
            if err == ERROR_INVALID_PARAMETER:
                return DEAD, "OpenProcess reported ERROR_INVALID_PARAMETER (no such process)"
            if err == ERROR_ACCESS_DENIED:
                return ALIVE, "OpenProcess reported ERROR_ACCESS_DENIED (process exists, not ours)"
            return UNVERIFIED, f"OpenProcess failed with unmapped error {err}"
        except Exception as exc:  # pragma: no cover - platform-dependent
            return UNVERIFIED, f"no usable process probe: {exc!r}"
    try:
        os.kill(pid, 0)
        return ALIVE, "os.kill(pid, 0) succeeded"
    except ProcessLookupError:
        return DEAD, "os.kill reported ProcessLookupError (no such process)"
    except PermissionError:
        return ALIVE, "os.kill reported PermissionError (process exists, not ours)"
    except Exception as exc:  # pragma: no cover - platform-dependent
        return UNVERIFIED, f"no usable process probe: {exc!r}"


def verdict_for(rel: str, probe=probe_pid) -> NameVerdict:
    """Classify a name, then probe liveness only when the number IS a PID.

    `probe` is injectable so the test suite can assert it is never called for a
    non-PID name -- the gate is a tested property, not a convention.
    """
    meaning, note = classify_name(rel)
    if meaning != PID:
        return NameVerdict(
            number_meaning=meaning,
            liveness=NOT_APPLICABLE,
            reason=f"liveness not attempted: number_meaning={meaning}. {note}",
            evidence=MEASURED,
        )
    pid = extract_pid(rel)
    if pid is None:
        return NameVerdict(PID, UNVERIFIED, "name classified as pid but no digits found", MEASURED)
    liveness, reason = probe(pid)
    return NameVerdict(PID, liveness, reason, MEASURED, pid)


# --------------------------------------------------------------------------
# Sampled counts -- a range with its n, never a central tendency
# --------------------------------------------------------------------------


@dataclasses.dataclass
class Sampled:
    """A quantity observed n times on a live tree."""

    values: list[int] = dataclasses.field(default_factory=list)

    def add(self, value: int) -> None:
        self.values.append(value)

    def as_dict(self, volatile: bool) -> dict:
        if not self.values:
            return {"min": None, "max": None, "n": 0, "evidence": UNVERIFIED}
        lo, hi = min(self.values), max(self.values)
        out = {"min": lo, "max": hi, "n": len(self.values), "evidence": MEASURED}
        if volatile and lo == hi and len(self.values) < 3:
            out["flag"] = "unanimous_small_n_on_volatile_path"
            out["flag_note"] = (
                "Agreement across too few samples of a changing quantity is not evidence. "
                "Re-run with --samples 3 or more, spaced across the churn interval."
            )
        return out


# --------------------------------------------------------------------------
# Scan
# --------------------------------------------------------------------------


@dataclasses.dataclass
class FileRow:
    relpath: str
    bytes: int
    mtime: str
    surface: str
    number_meaning: str
    liveness: str
    liveness_reason: str
    deny_listed: bool
    evidence: str


def resolve_root(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit).expanduser()
    env = os.environ.get("CLAUDE_CONFIG_DIR")
    if env:
        return Path(env).expanduser()
    return Path.home() / ".claude"


def iso(ts: float) -> str:
    return datetime.fromtimestamp(ts, tz=timezone.utc).isoformat(timespec="seconds")


def top_level_name(rel: str) -> str:
    return rel.replace("\\", "/").split("/", 1)[0]


def classify_entry(rel: str) -> tuple[str, str]:
    """Map a root-relative path onto a documented surface.

    Matching is case-SENSITIVE on the literal name. Case folding here would
    silently merge entries that the operating system, and the operator, regard
    as distinct -- the same class of error as a case-insensitive comparer
    collapsing three deny rules into one. On a case-insensitive filesystem the
    OS resolves the collision before this function ever sees it; when this
    function does see two spellings, they came from two distinct directory
    entries and stay two.
    """
    head = top_level_name(rel)
    if head in SURFACE_TABLE:
        return SURFACE_TABLE[head]
    return UNCLASSIFIED, "Not listed in the upstream ~/.claude reference tables."


def find_deliberate_state(root: Path) -> list[dict]:
    """Locate revert ledgers anywhere in the tree, hotspots first.

    Returns one record per ledger found. Every directory named here, and its
    whole subtree, is deny-listed for the rest of the run.
    """
    found: list[dict] = []
    seen: set[str] = set()

    def record(full: Path, dirpath: Path, label: str, signal: str) -> None:
        try:
            rel = full.relative_to(root).as_posix()
        except ValueError:  # pragma: no cover - defensive
            return
        if rel in seen:
            return
        seen.add(rel)
        try:
            st = full.stat()
        except OSError:
            return
        found.append(
            {
                "ledger": rel,
                "deny_root": dirpath.relative_to(root).as_posix(),
                "found_via": label,
                "signal": signal,
                "mtime": iso(st.st_mtime),
                "age_days": round((time.time() - st.st_mtime) / 86400, 2),
                "evidence": MEASURED,
                "note": (
                    "A ledger like this is frequently the ONLY copy of a revert path. "
                    "Its own claims are not authoritative -- diff against the stored "
                    "baseline before believing what it says was changed."
                ),
            }
        )

    def walk(base: Path, label: str, corroborating_below: Path | None) -> None:
        if not base.is_dir():
            return
        for dirpath, dirnames, filenames in os.walk(base, followlinks=False):
            dirnames[:] = [d for d in dirnames if d not in {".git", "node_modules"}]
            here = Path(dirpath)
            try:
                rel_dir = here.relative_to(root).as_posix()
            except ValueError:  # pragma: no cover - defensive
                continue
            if any(
                rel_dir == p or rel_dir.startswith(p + "/") for p in LEDGER_SCAN_SKIP_PREFIXES
            ):
                dirnames[:] = []
                continue
            depth_ok = False
            if corroborating_below is not None:
                try:
                    depth = len(here.relative_to(corroborating_below).parts)
                    depth_ok = depth <= HOTSPOT_CORROBORATING_MAX_DEPTH
                except ValueError:  # pragma: no cover - defensive
                    depth_ok = False
            for name in filenames:
                if any(fnmatch.fnmatchcase(name, pat) for pat in STRONG_LEDGER_GLOBS):
                    record(here / name, here, label, "strong")
                elif depth_ok and any(
                    fnmatch.fnmatchcase(name, pat) for pat in CORROBORATING_LEDGER_GLOBS
                ):
                    record(here / name, here, label, "corroborating")

    for hotspot in DELIBERATE_STATE_HOTSPOTS:
        base = root / hotspot
        walk(base, f"hotspot:{hotspot}", base)
    walk(root, "full-tree", None)
    return found


def deny_roots(records: list[dict]) -> list[str]:
    """Exact, case-sensitive deny paths.

    Deliberately NOT deduplicated case-insensitively: two paths differing only
    by case are two directories, and folding them would drop protection from
    one of them.
    """
    out: list[str] = []
    for rec in records:
        root_path = rec["deny_root"]
        if root_path not in out:
            out.append(root_path)
    return out


def under_deny(rel: str, denied: list[str]) -> bool:
    rel = rel.replace("\\", "/")
    for d in denied:
        if d in ("", ".") or rel == d or rel.startswith(d + "/"):
            return True
    return False


DOCUMENTED_MINIMUM_DAYS = 1


def valid_retention_days(value: object) -> int | None:
    """`value` as a usable `cleanupPeriodDays`, or None when it is not one.

    Two ways an `isinstance(value, int)` test alone gets this wrong, both of which
    then drive `effective_days` and therefore every staleness reading in the report:

    * `bool` IS an `int` in Python, so `true` would be read as a one-day window and
      `false` as a zero-day one -- neither of which the setting means;
    * zero and negative values are below the documented minimum of one day, and a
      negative window puts the retention cutoff in the FUTURE, marking effectively
      every swept file as older than retention.

    A value this rejects is reported as invalid and the documented default stands.
    """
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    return value if value >= DOCUMENTED_MINIMUM_DAYS else None


def read_retention(root: Path) -> dict:
    """Determine the retention window that actually governs this tree.

    Three things matter and each is reported separately, because they fail
    independently:

    * the value in user settings (absent is normal -- the default applies);
    * whether that file PARSES, because an unparsable settings file pauses the
      sweep entirely unless managed settings supply the value;
    * whether the sweep has actually run, from its own watermark.
    """
    result: dict = {
        "documented_default_days": 30,
        "documented_minimum_days": DOCUMENTED_MINIMUM_DAYS,
        "user_settings_parse": None,
        "user_setting_days": None,
        "managed_settings_path": None,
        "managed_setting_days": None,
        "effective_days": 30,
        "effective_evidence": DOCUMENTED_DEFAULT,
        "last_cleanup": None,
        "last_cleanup_age_hours": None,
        "plugin_inuse_sweep": None,
        "findings": [],
        "basis": "https://code.claude.com/docs/en/claude-directory.md (Application data)",
    }

    settings_unparsable = False
    settings = root / "settings.json"
    if settings.is_file():
        try:
            data = json.loads(read_text_guarded(root, "settings.json"))
            result["user_settings_parse"] = "ok"
            if isinstance(data, dict) and "cleanupPeriodDays" in data:
                days = valid_retention_days(data["cleanupPeriodDays"])
                if days is None:
                    # Reported, not silently ignored, and it does NOT drive
                    # effective_days -- the documented default stands instead.
                    result["user_setting_days"] = f"invalid: {data['cleanupPeriodDays']!r}"
                else:
                    result["user_setting_days"] = days
                    result["effective_days"] = days
                    result["effective_evidence"] = MEASURED
        except (OSError, json.JSONDecodeError) as exc:
            settings_unparsable = True
            result["user_settings_parse"] = f"failed: {type(exc).__name__}"
            result["findings"].append(
                {
                    "id": "settings-unparsable-pauses-sweep",
                    "severity": "error",
                    "evidence": MEASURED,
                    "claim": (
                        "settings.json does not parse. Upstream documents that Claude Code pauses "
                        "the retention cleanup sweep and warns in /status until the file is fixed, "
                        "unless managed settings supply cleanupPeriodDays. Every staleness reading "
                        "in this report is therefore suspect: nothing is being swept."
                    ),
                }
            )
    else:
        result["user_settings_parse"] = "absent"

    for candidate in managed_settings_paths():
        if candidate.is_file():
            result["managed_settings_path"] = str(candidate)
            try:
                data = json.loads(candidate.read_text(encoding="utf-8", errors="replace"))
                if isinstance(data, dict) and "cleanupPeriodDays" in data:
                    days = valid_retention_days(data["cleanupPeriodDays"])
                    if days is None:
                        result["managed_setting_days"] = (
                            f"invalid: {data['cleanupPeriodDays']!r}"
                        )
                    else:
                        result["managed_setting_days"] = days
                        result["effective_days"] = days
                        result["effective_evidence"] = MEASURED
            except (OSError, json.JSONDecodeError):
                result["managed_setting_days"] = "unparsable"
            break

    # The finding above is raised while reading settings.json, before managed settings
    # have been looked at -- but its own claim names managed settings as the exception
    # that keeps the sweep running. On an enterprise machine that supplies a valid
    # cleanupPeriodDays, leaving it in place told the reader that nothing is being swept
    # and that every staleness reading is suspect, when neither is true. Withdraw it once
    # the exception is measured to apply. The parse failure itself is still reported, in
    # `user_settings_parse`, so no evidence is lost.
    if settings_unparsable and isinstance(result["managed_setting_days"], int):
        result["findings"] = [
            f for f in result["findings"] if f["id"] != "settings-unparsable-pauses-sweep"
        ]

    marker = root / ".last-cleanup"
    if marker.is_file():
        try:
            raw = read_text_guarded(root, ".last-cleanup").strip()
            result["last_cleanup"] = raw
            stamp = datetime.fromisoformat(raw.replace("Z", "+00:00"))
            age = (datetime.now(timezone.utc) - stamp).total_seconds() / 3600
            result["last_cleanup_age_hours"] = round(age, 2)
        except (OSError, ValueError):
            result["last_cleanup"] = "unreadable"

    plugin_marker = root / "plugins" / ".last_inuse_sweep"
    if plugin_marker.is_file():
        try:
            result["plugin_inuse_sweep"] = read_text_guarded(
                root, "plugins/.last_inuse_sweep"
            ).strip()
        except OSError:
            result["plugin_inuse_sweep"] = "unreadable"

    return result


def managed_settings_paths() -> list[Path]:
    """Documented machine-scope managed-settings locations, by platform."""
    system = platform.system()
    if system == "Darwin":
        return [Path("/Library/Application Support/ClaudeCode/managed-settings.json")]
    if system == "Windows":
        program_files = os.environ.get("ProgramFiles", r"C:\Program Files")
        return [Path(program_files) / "ClaudeCode" / "managed-settings.json"]
    return [Path("/etc/claude-code/managed-settings.json")]


def count_files(root: Path, exclude: set[str] | None = None) -> dict[str, int]:
    """Cheap per-top-level-entry file count, for resampling a live tree."""
    exclude = exclude or set()
    counts: dict[str, int] = {}
    for dirpath, _dirnames, filenames in os.walk(root, followlinks=False):
        for name in filenames:
            try:
                rel = (Path(dirpath) / name).relative_to(root).as_posix()
            except ValueError:  # pragma: no cover - defensive
                continue
            if rel in exclude:
                continue
            head = top_level_name(rel)
            counts[head] = counts.get(head, 0) + 1
    return counts


def count_by_entry(rows: list[FileRow]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for row in rows:
        head = top_level_name(row.relpath)
        counts[head] = counts.get(head, 0) + 1
    return counts


def walk_tree(
    root: Path,
    denied: list[str],
    probe=probe_pid,
    exclude: set[str] | None = None,
) -> tuple[list[FileRow], list[dict]]:
    """Enumerate every file once, classifying as it goes."""
    exclude = exclude or set()
    rows: list[FileRow] = []
    errors: list[dict] = []
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False, onerror=errors.append):
        for name in filenames:
            full = Path(dirpath) / name
            try:
                rel = full.relative_to(root).as_posix()
            except ValueError:  # pragma: no cover - defensive
                continue
            if rel in exclude:
                continue
            try:
                st = full.lstat()
            except OSError as exc:
                errors.append({"path": rel, "error": repr(exc)})
                continue
            surface, _note = classify_entry(rel)
            if is_never_read(rel) and surface != SECRET:
                surface = SECRET
            verdict = verdict_for(rel, probe=probe)
            rows.append(
                FileRow(
                    relpath=rel,
                    bytes=st.st_size,
                    mtime=iso(st.st_mtime),
                    surface=surface,
                    number_meaning=verdict.number_meaning,
                    liveness=verdict.liveness,
                    liveness_reason=verdict.reason,
                    deny_listed=under_deny(rel, denied),
                    evidence=MEASURED if not stat.S_ISLNK(st.st_mode) else INFERRED,
                )
            )
    return rows, [e if isinstance(e, dict) else {"error": repr(e)} for e in errors]


def rollup(
    rows: list[FileRow],
    retention_days: int,
    authored_threshold: int,
) -> list[dict]:
    """Group per top-level entry, splitting listed surfaces from rolled-up bulk."""
    groups: dict[str, list[FileRow]] = {}
    for row in rows:
        groups.setdefault(top_level_name(row.relpath), []).append(row)

    # Same precision as FileRow.mtime, so the lexicographic comparison below is
    # exact rather than off by up to a second at the boundary.
    cutoff = (datetime.now(timezone.utc) - timedelta(days=retention_days)).isoformat(
        timespec="seconds"
    )
    out: list[dict] = []
    for name, members in sorted(groups.items()):
        surface, note = classify_entry(name)
        # `classify_entry` consults SURFACE_TABLE and nothing else, so a top-level
        # directory with no table row of its own reads `unclassified` even when the
        # files under it are secret-bearing: `ide/*.lock` is in NEVER_READ_GLOBS and
        # every member row is promoted to SECRET by `walk_tree`, but `ide` has no
        # SURFACE_TABLE key, so the entry summary read `unclassified` -- and its
        # staleness verdict `unclassified-report-only` rather than `keep`. The entry
        # line is what a reader scans first; it must never be less alarming than the
        # rows beneath it, so a SECRET member promotes the entry.
        secret_members = sum(1 for m in members if m.surface == SECRET)
        if surface != SECRET and secret_members:
            surface = SECRET
            # The count, not just the fact: a mixed tree can be promoted by a couple of
            # vendored `*.pem` bundles, and the reader needs it against the `files` field
            # sitting beside it to see the proportion rather than assume the whole entry
            # is secret. Promotion is still the right call -- the verdict it produces is
            # `keep`, and a report-only audit must not summarise a secret-bearing file
            # under a milder line.
            note = (
                f"Contains {secret_members} never-read secret-bearing file(s), so the entry "
                f"is classified by its contents rather than by its own name. "
                f"Own classification: {note}"
            )
        older = [m for m in members if m.mtime < cutoff]
        entry = {
            "entry": name,
            "surface": surface,
            "surface_note": note,
            "surface_evidence": (
                MEASURED if surface != UNCLASSIFIED else "no-upstream-row"
            ),
            "files": len(members),
            "bytes": sum(m.bytes for m in members),
            "oldest": min(m.mtime for m in members),
            "newest": max(m.mtime for m in members),
            "older_than_retention": len(older),
            "deny_listed": any(m.deny_listed for m in members),
            "listing": "rolled-up" if len(members) > authored_threshold else "per-file",
        }
        entry["reading"] = staleness_reading(entry, retention_days)
        if entry["listing"] == "per-file":
            entry["members"] = [dataclasses.asdict(m) for m in sorted(members, key=lambda m: m.relpath)]
        out.append(entry)
    return out


def staleness_reading(entry: dict, retention_days: int) -> dict:
    """The one place a staleness verdict is produced, so it cannot be produced elsewhere."""
    if entry["deny_listed"]:
        return {
            "verdict": "deny-listed",
            "evidence": MEASURED,
            "why": "A revert ledger was found in this subtree. Nothing here is a cleanup candidate.",
        }
    if entry["surface"] == SECRET:
        return {
            "verdict": "keep",
            "evidence": MEASURED,
            "why": "Secret-bearing. Contents were never opened; keep is the only safe default.",
        }
    if entry["surface"] == SWEPT:
        if entry["older_than_retention"] == 0:
            return {
                "verdict": "product-managed-healthy",
                "evidence": MEASURED,
                "why": (
                    f"Every file here is inside the {retention_days}-day retention window the "
                    "product's own sweep enforces. Hand-pruning fights the sweep. The only lever "
                    "that shrinks it is lowering cleanupPeriodDays."
                ),
            }
        unit = SWEEP_UNIT.get(entry["entry"], SWEEP_UNIT_UNDOCUMENTED)
        return {
            "verdict": "age-exceeds-window",
            "evidence": INFERRED,
            "measured": (
                f"{entry['older_than_retention']} file(s) carry an mtime older than the "
                f"{retention_days}-day window."
            ),
            "why": (
                "That count is a measurement of mtimes. It is NOT proof the sweep is failing, and "
                "the step from one to the other is an inference this engine will not make for you: "
                f"the sweep's unit for this path is {unit}. Report the count and investigate; do "
                "not hand-prune, and do not read this as a deletion authorisation."
            ),
        }
    if entry["surface"] == SESSION_SCOPED:
        return {
            "verdict": "keep",
            "evidence": MEASURED,
            "why": (
                "Removed by the product at session exit and on crash recovery, not by age. "
                "Hand-deleting confuses concurrent-session detection."
            ),
        }
    if entry["surface"] in (KEPT, AUTHORED):
        return {
            "verdict": "keep",
            "evidence": MEASURED,
            "why": "Documented as retained until you delete it, or authored by you.",
        }
    return {
        "verdict": "unclassified-report-only",
        "evidence": "no-upstream-row",
        "why": (
            "No upstream table covers this path, so no retention claim can be made about it "
            "either way. Report it; do not infer that unmanaged means disposable."
        ),
    }


def recent_writers(rows: list[FileRow], hours: int) -> list[dict]:
    """Top-level entries written within the window -- behavioural evidence of activity.

    Declared configuration is a poor guide to what is actually running: a
    component recorded as disabled in one file can still be enabled at another
    scope, and enablement is read at session start so a running session keeps
    whatever it loaded. A file written in the last few hours is a measurement.
    """
    # Same precision as FileRow.mtime (`iso()` uses timespec="seconds"), for the same
    # reason `rollup`'s cutoff does: without it the cutoff carries microseconds, `.`
    # (0x2E) sorts after `+` (0x2B), and a file written inside the window but in the
    # cutoff second compares LOWER than the cutoff and is silently dropped.
    cutoff = (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat(timespec="seconds")
    seen: dict[str, str] = {}
    for row in rows:
        if row.mtime >= cutoff:
            head = top_level_name(row.relpath)
            if head not in seen or row.mtime > seen[head]:
                seen[head] = row.mtime
    return [
        {"entry": k, "newest_write": v, "evidence": MEASURED}
        for k, v in sorted(seen.items(), key=lambda kv: kv[1], reverse=True)
    ]


def summarize_numeric(rows: list[FileRow], sample_cap: int = 25) -> dict:
    """Counts per (meaning, liveness), plus a bounded sample of the rows that matter.

    Every PID-typed row is listed, because those are the only ones a liveness
    verdict was even attempted for. Unrecognised numeric names are sampled --
    they are the ones a future version of the scheme table should learn.
    """
    buckets: dict[str, int] = {}
    pid_rows: list[dict] = []
    unknown_sample: list[str] = []
    for row in rows:
        if row.number_meaning == NO_NUMBER:
            continue
        key = f"{row.number_meaning}/{row.liveness}"
        buckets[key] = buckets.get(key, 0) + 1
        if row.number_meaning == PID:
            pid_rows.append(
                {
                    "relpath": row.relpath,
                    "liveness": row.liveness,
                    "reason": row.liveness_reason,
                    "evidence": MEASURED,
                }
            )
        elif row.number_meaning == UNKNOWN_MEANING and len(unknown_sample) < sample_cap:
            unknown_sample.append(row.relpath)
    return {
        "counts_by_meaning_and_liveness": dict(sorted(buckets.items())),
        "pid_typed": sorted(pid_rows, key=lambda r: r["relpath"]),
        "unknown_meaning_sample": unknown_sample,
        "note": (
            "Liveness was attempted for the pid_typed rows only. Every other row reads "
            "not_applicable BY CONSTRUCTION, not because a lookup missed. The full per-file "
            "classification is in the CSV artifact."
        ),
        "evidence": MEASURED,
    }


HOME_ROOT_TMP = re.compile(r"\.claude\.json\.tmp\.(\d+)\.[0-9a-f]+")


def home_root_state(root: Path) -> list[dict]:
    """`~/.claude.json` and its siblings live OUTSIDE the swept tree."""
    home = root.parent
    out: list[dict] = []
    for name in sorted(p.name for p in home.glob(".claude.json*")):
        path = home / name
        try:
            st = path.stat()
        except OSError:
            continue
        record = {
            "path": str(path),
            "bytes": st.st_size,
            "mtime": iso(st.st_mtime),
            "evidence": MEASURED,
        }
        if HOME_ROOT_TMP.fullmatch(name):
            record["number_meaning"] = UNKNOWN_MEANING
            record["liveness"] = NOT_APPLICABLE
            record["number_note"] = (
                "A failed atomic-write remnant. The leading number LOOKS like a PID and has not "
                "been verified to be one, so no liveness lookup was attempted -- an unverified "
                "guess here is exactly the error this engine exists to prevent. Judge by age."
            )
        out.append(
            {
                **record,
                "note": (
                    "Home-root state. Not covered by the ~/.claude retention sweep. Values inside "
                    "are never read by this engine (MCP server configs can carry tokens). The "
                    "supported way to shed project state from it is `claude project purge`."
                ),
            }
        )
    return out


def self_excluded(root: Path, outputs: list[str | None]) -> set[str]:
    """Paths this run writes, removed from its own scan set.

    A run must never measure its own output. This matters more here than it
    normally would: the plugin data directory a report would naturally be
    written to lives at `~/.claude/plugins/data/<id>`, i.e. INSIDE the tree
    being scanned. Anything written there would be counted, classified, and
    possibly reported as an unmanaged leftover by the run that created it.
    """
    excluded: set[str] = set()
    for out in outputs:
        if not out:
            continue
        try:
            rel = Path(out).resolve().relative_to(root.resolve()).as_posix()
        except (ValueError, OSError):
            continue
        excluded.add(rel)
    return excluded


def scan(
    root: Path,
    samples: int,
    interval: float,
    authored_threshold: int,
    recent_hours: int,
    probe=probe_pid,
    exclude: set[str] | None = None,
) -> dict:
    exclude = exclude or set()
    ledgers = find_deliberate_state(root)
    denied = deny_roots(ledgers)
    retention = read_retention(root)
    days = retention["effective_days"]

    rows, errors = walk_tree(root, denied, probe=probe, exclude=exclude)

    counts: dict[str, Sampled] = {}
    for name, value in count_by_entry(rows).items():
        counts.setdefault(name, Sampled()).add(value)

    for _ in range(max(0, samples - 1)):
        time.sleep(interval)
        resample = count_files(root, exclude=exclude)
        for name in counts:
            counts[name].add(resample.get(name, 0))

    entries = rollup(rows, days, authored_threshold)
    for entry in entries:
        entry["file_count_sampled"] = counts[entry["entry"]].as_dict(
            entry["entry"] in VOLATILE_DIRS
        )

    numeric = summarize_numeric(rows)

    return {
        "schema": "claude-install-state/1",
        "generated_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "root": str(root),
        "platform": {
            "system": platform.system(),
            "python": platform.python_version(),
            "liveness_probe": "OpenProcess" if os.name == "nt" else "os.kill(pid, 0)",
            "evidence": MEASURED,
        },
        "quiesced": False,
        "quiesced_note": (
            "The tree was live during the scan. Counts are ranges with their sample count; "
            "any single-instant total is a snapshot, not a reconciled figure."
        ),
        "deliberate_state": ledgers,
        "deny_roots": denied,
        "retention": retention,
        "entries": entries,
        "numeric_names": numeric,
        "recent_writers": recent_writers(rows, recent_hours),
        "home_root_state": home_root_state(root),
        "never_read": list(NEVER_READ_GLOBS),
        "content_reads": {
            "paths": list(CONTENT_READ_ALLOWLIST),
            "note": (
                "The ONLY files whose bytes this engine opens. Everything else in the tree is "
                "stat-only: name, size, mtime. Sibling-plugin state under this root is inventoried "
                "by name and never parsed, and its owner is not attributed."
            ),
        },
        "self_excluded": sorted(exclude),
        "walk_errors": errors,
        "_rows": rows,
        "totals": {
            "files": len(rows),
            "bytes": sum(r.bytes for r in rows),
            "evidence": MEASURED,
            "note": "Snapshot at first sample; see per-entry file_count_sampled for the range.",
        },
    }


def write_csv(rows: list[FileRow], path: Path) -> int:
    """Emit EVERY file as a row, so "every file" literally exists as an artifact.

    This is deliberately independent of `--authored-threshold`. That flag
    controls only how much per-file detail is embedded in the JSON summary; it
    must never decide how much of the tree reaches the artifact, or the report
    silently drops most of the install while its own prose claims completeness.
    """
    written = 0
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(
            [
                "relpath",
                "bytes",
                "mtime_utc",
                "surface",
                "number_meaning",
                "liveness",
                "liveness_reason",
                "deny_listed",
                "evidence",
            ]
        )
        for row in sorted(rows, key=lambda r: r.relpath):
            writer.writerow(
                [
                    row.relpath,
                    row.bytes,
                    row.mtime,
                    row.surface,
                    row.number_meaning,
                    row.liveness,
                    row.liveness_reason,
                    row.deny_listed,
                    row.evidence,
                ]
            )
            written += 1
    return written


def main(argv: list[str] | None = None) -> int:
    if sys.version_info < MIN_PYTHON:
        print(
            f"error: Python {MIN_PYTHON[0]}.{MIN_PYTHON[1]}+ required, "
            f"found {platform.python_version()}",
            file=sys.stderr,
        )
        return 2

    parser = argparse.ArgumentParser(
        prog="install_state.py",
        description="Read-only inventory of a Claude Code installation directory.",
    )
    parser.add_argument("--root", default=None, help="Config dir (default: $CLAUDE_CONFIG_DIR or ~/.claude)")
    parser.add_argument("--samples", type=int, default=2, help="Times to count files (default 2)")
    parser.add_argument("--sample-interval", type=float, default=0.5, help="Seconds between samples")
    parser.add_argument(
        "--authored-threshold",
        type=int,
        default=200,
        help="Entries with more files than this are rolled up instead of listed (default 200)",
    )
    parser.add_argument("--recent-hours", type=int, default=24, help="Recent-writer window")
    parser.add_argument(
        "--csv",
        default=None,
        help="Write the COMPLETE per-file listing here (every file, always)",
    )
    args = parser.parse_args(argv)

    root = resolve_root(args.root)
    if not root.is_dir():
        print(f"error: not a directory: {root}", file=sys.stderr)
        return 2

    report = scan(
        root=root,
        samples=args.samples,
        interval=args.sample_interval,
        authored_threshold=args.authored_threshold,
        recent_hours=args.recent_hours,
        exclude=self_excluded(root, [args.csv]),
    )

    rows: list[FileRow] = report.pop("_rows")
    if args.csv:
        count = write_csv(rows, Path(args.csv))
        report["csv"] = {
            "path": args.csv,
            "rows": count,
            "evidence": MEASURED,
            "note": (
                "Complete: one row per file in the scan set. --authored-threshold affects only "
                "how much per-file detail the JSON summary embeds, never this artifact."
            ),
        }
    else:
        report["csv"] = {
            "path": None,
            "rows": 0,
            "evidence": MEASURED,
            "note": (
                "No --csv given, so no complete per-file artifact was written. The JSON below "
                "lists only the authored surface; bulk trees are rolled up. Do NOT describe this "
                "run as covering every file."
            ),
        }

    for entry in report["entries"]:
        entry.pop("members", None)

    json.dump(report, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
