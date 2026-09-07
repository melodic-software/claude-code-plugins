"""Bounded, append-only local record of disk-hygiene guard decisions.

`hook_telemetry` is inert unless `HOOK_TELEMETRY_SINK` names an executable, so
on an ordinary install every guard decision is discarded as it is made and the
questions an operator asks afterwards — why was this denied, has it denied this
all along, did the guard run at all — have no evidence to answer from. This
module is the floor beneath that channel, not a replacement for it: it records
each decision under the plugin's own persistent data root with no configuration,
while a configured sink keeps receiving exactly what it receives today.

Design constraints this module is built to, in order:

1. **The verdict never changes.** Every entry point returns a bool and raises
   nothing. An unwritable path, a full disk, a read-only data root, a path that
   is a file where a directory is needed — each records nothing and reports
   False. Callers ignore the result on the decision path; the guard's verdict is
   computed and emitted before a record is attempted, so no write outcome can
   reach it.
2. **Bounded, enforced.** The live file is rotated to a single previous
   generation once it reaches `MAX_BYTES`, so the record occupies at most
   `2 * MAX_BYTES` plus one line, forever, without an operator pruning anything.
   The bound is enforced on the writing path from the offset the append already
   returns, not advertised and left to a sweeper.
3. **Readable without tooling.** One JSON object per line, UTF-8, newline
   terminated: `cat`, `tail`, `grep` and a JSON-aware reader all work. Each
   record carries its own timestamp, decision, rule, and the command that drove
   it, so a single line explains itself without the ones around it.
4. **Bounded line length.** The command and reason fields are truncated to
   `MAX_TEXT_CHARS`, which keeps a record well under the size at which a
   concurrent `O_APPEND` write from a second hook process could interleave, and
   keeps the record a record of the DECISION rather than a copy of the payload.
5. **No raw secrets.** Command and reason are secret-scrubbed before they are
   clipped. The PowerShell `none` adjudication and the Bash deny-by-default
   catch-all persist length only (`command_chars`), not the command text: those
   branches fire on arbitrary session commands, including credentials.
6. **Owner-only files.** The log directory is `0700` and the live file is
   `0600`. Mode is applied on every write so a leftover world-readable file is
   tightened rather than left. `chmod` is best-effort: a host that cannot set
   POSIX modes still records, and the verdict still does not change.
"""

from __future__ import annotations

import contextlib
import json
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping, TextIO

SCHEMA_VERSION = "1.0"

LOG_DIRNAME = "guard-decisions"
LOG_FILENAME = "decisions.jsonl"
ROTATED_FILENAME = "decisions.previous.jsonl"

# Per generation; two generations are kept, so the bound is about 2 MiB.
MAX_BYTES = 1_048_576
MAX_TEXT_CHARS = 400

FILE_MODE = 0o600
DIR_MODE = 0o700

# Opt-out, not opt-in: absent means recording. Recognised off values are exact
# and lowercase-folded, so a stray value leaves the record ON rather than
# silently disabling the thing the operator is relying on.
DISABLE_ENV = "DISK_HYGIENE_GUARD_DECISION_LOG"
_OFF_VALUES = frozenset({"0", "off", "false", "no"})

# Names a decision record can carry. `none` is a guard that ran and adjudicated
# nothing (it issued no permissionDecision); `not-run` is a guard that never
# produced a decision at all, which only a separate observer can record.
DECISION_NONE = "none"
DECISION_NOT_RUN = "not-run"

# Branches that fire on arbitrary session commands. Persist length, not text.
OMIT_COMMAND_RULES = frozenset(
    {
        "powershell-no-flagged-spelling",
        "not-exact-engine-command",
    }
)

REDACTED = "<redacted>"

# Shape-based secret scrubbing. Same family as session-flow's ledger redaction
# (private keys, cloud tokens, bearer/password assignments, connection strings)
# plus env-var assignments whose names look like credentials, including
# PowerShell `$env:AZURE_CLIENT_SECRET='...'`.
_SECRET_SHAPES: tuple[re.Pattern[str], ...] = (
    re.compile(
        r"-----BEGIN[^-]+PRIVATE KEY-----.*?-----END[^-]+PRIVATE KEY-----",
        re.DOTALL,
    ),
    re.compile(r"\b(?:sk|rk|pk)-[A-Za-z0-9_-]{16,}"),
    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}"),
    re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"),
    re.compile(r"(?i)\bbearer\s+[A-Za-z0-9._+/=-]{8,}"),
    re.compile(
        r"(?i)\b(?:bearer|token|api[_-]?key|secret|password|passwd|pwd)"
        r"['\"]?\s*[:=]\s*['\"]?[A-Za-z0-9._+/=-]{8,}"
    ),
    re.compile(r"\b[a-z][a-z0-9+.-]*://[^\s:@/]+:[^\s:@/]+@[^\s]+"),
    re.compile(
        r"(?i)(?:\$env:)?[A-Za-z_][A-Za-z0-9_]*"
        r"(?:SECRET|KEY|TOKEN|PASSWORD|PASSWD|PWD|CREDENTIAL)[A-Za-z0-9_]*"
        r"\s*[=:]\s*['\"]?[^\s'\"]+"
    ),
)


def enabled() -> bool:
    return os.environ.get(DISABLE_ENV, "").strip().casefold() not in _OFF_VALUES


def omit_command_text(decision: str, rule: str) -> bool:
    return decision == DECISION_NONE or rule in OMIT_COMMAND_RULES


def _timestamp() -> str:
    return (
        datetime.now(timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z")
    )


def _redact_secrets(text: str) -> str:
    for pattern in _SECRET_SHAPES:
        text = pattern.sub(REDACTED, text)
    return text


def _clip(value: object) -> str | None:
    if value is None:
        return None
    text = value if isinstance(value, str) else str(value)
    text = _redact_secrets(text)
    if len(text) > MAX_TEXT_CHARS:
        return text[:MAX_TEXT_CHARS] + "..."
    return text


def build_record(
    *,
    hook: str,
    decision: str,
    rule: str,
    tool: str | None = None,
    mode: str | None = None,
    command: str | None = None,
    reason: str | None = None,
    extra: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    """One decision record. Separate from the write so tests can pin the shape."""
    record: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "timestamp": _timestamp(),
        "hook": hook,
        "decision": decision,
        "rule": rule,
    }
    if tool is not None:
        record["tool"] = tool
    if mode is not None:
        record["mode"] = mode
    if command is not None:
        if omit_command_text(decision, rule):
            record["command_chars"] = len(command)
        else:
            record["command"] = _clip(command)
    if reason is not None:
        record["reason"] = _clip(reason)
    if extra:
        for key, value in extra.items():
            record[key] = _clip(value) if isinstance(value, str) else value
    return record


def log_path(data_root: str) -> Path:
    return Path(data_root) / LOG_DIRNAME / LOG_FILENAME


def _restrict_mode(path: Path, mode: int) -> None:
    with contextlib.suppress(OSError, NotImplementedError):
        os.chmod(path, mode)


def _ensure_log_dir(directory: Path) -> None:
    directory.mkdir(mode=DIR_MODE, parents=True, exist_ok=True)
    _restrict_mode(directory, DIR_MODE)


def _open_append(path: Path) -> TextIO:
    flags = os.O_APPEND | os.O_CREAT | os.O_WRONLY
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    fd = os.open(path, flags, FILE_MODE)
    try:
        return os.fdopen(fd, "a", encoding="utf-8", newline="\n")
    except BaseException:
        os.close(fd)
        raise


def _rotate(path: Path) -> None:
    """Retire the live file to the single previous generation.

    `os.replace` is atomic and overwrites, so the generation before last is what
    the bound discards. A failure here leaves the live file in place: the next
    append then exceeds `MAX_BYTES` by one more line and retries the rotation,
    which is the safe direction (a file slightly over the bound, never a lost
    record and never a raised exception).
    """
    os.replace(path, path.parent / ROTATED_FILENAME)


def record(data_root: str | None, **fields: Any) -> bool:
    """Append one record. Returns True only when a record reached the disk.

    Never raises. `BaseException` rather than `Exception` is deliberate and
    matches `destructive_guard.main`'s own boundary: this runs on the decision
    path of a security guard, and there is no failure of an audit write —
    including one that arrives as a `KeyboardInterrupt` or a `MemoryError` —
    that is worth converting a computed verdict into a different outcome.
    """
    try:
        if not data_root or not enabled():
            return False
        line = json.dumps(
            build_record(**fields), separators=(",", ":"), ensure_ascii=False
        )
        path = log_path(data_root)
        try:
            handle = _open_append(path)
        except (FileNotFoundError, NotADirectoryError):
            _ensure_log_dir(path.parent)
            handle = _open_append(path)
        with handle:
            handle.write(line + "\n")
            handle.flush()
            # Append mode leaves the offset at end-of-file, so the bound is
            # checked from a number the write already produced: no extra stat.
            size = handle.tell()
        _restrict_mode(path, FILE_MODE)
        _restrict_mode(path.parent, DIR_MODE)
        if size >= MAX_BYTES:
            _rotate(path)
        return True
    except BaseException:  # noqa: BLE001 - an audit write never changes a verdict
        return False
