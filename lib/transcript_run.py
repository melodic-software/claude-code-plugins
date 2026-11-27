# -*- coding: utf-8 -*-
"""Read one transcript source in a child process, on this host or on another one through its via.

The remote-run protocol. The caller starts `via + [shlex.join(["python3", "-I", "-c", LOADER])]`,
or `[sys.executable, "-I", "-c", LOADER]` for an empty via, from the filesystem root, and writes to its
stdin:

1. one line holding the byte length of a JSON header `{"protocol", "entries", "args"}`, then the
   header; `entries` is the manifest, a list of `[name, kind, size]`;
2. each entry's bytes in manifest order: `module` entries are this module's siblings, loaded one by
   one as `types.ModuleType`s in `sys.modules`; `data` entries are the gitleaks rules and the
   `state-key.sh` text, held in memory and never written;
3. JSON lines of what the caller already holds, `{"project", "session_id", "fingerprint", "policy"}`,
   each at most `MAX_FINGERPRINT_LINE` bytes; `project`, here and on every message, is always
   `session_record.project_segment` of the project directory (`p-<12 hex>`), so no project
   directory name leaves the reading host, and the policy is `session_record.stored_policy` of the stored record, so a
   session is skipped only under `session_record.is_unchanged`.

The header's `args` hold `config_dir`, the record policy (`collector_digest`, `excerpt_chars`,
`excerpt_words`; an unset excerpt limit is 0), `force` (re-read every session, still listing
what is gone), `since` and `cutoff` (epoch seconds: a transcript
modified before `since` is passed over, one before `cutoff` or ending before it is counted
`skipped_expired`; with `retention_floor` set the child moves `cutoff` back to its own
`cleanupPeriodDays`), `sessions` (only these ids), `history`, `v1` (an old store to carry over,
below), `list_only` (list and carry over, read no transcript), and the lock and limit settings.

The child reads all of stdin before it takes the host lock, so a stalled caller holds no lock. It
writes JSON lines to stdout, each discriminated by `kind`: first
`{"kind": "hello", "protocol": 1, ...}` carrying the `HELLO_FIELDS` the host reports about itself
and `mounted_platform` (`session_record.mounted_platform`: `windows` when a WSL reader finds the
configuration directory under its automount root),
then `listing`, `carried_over`, `record`, `history_prompt`, `diag` and `gap` lines, and last a
`diag` line whose `event` is `end`. Before it reads any transcript the child lists them all and
sends one `listing` line: `gone`, the held `[project, session_id]` pairs whose transcript is no
longer there, and `unlisted`, the projects whose directory could not be listed (each also an
`unreadable` gap; no held session in one is named gone). With `v1`
(`{"store", "schema", "own"}`: an old store's sessions directory on the reading host and its
record schema) the child then reads that store, without writing to it, sends each old record the
caller must keep as a `carried_over` line shaped like a `record` line, and accounts for every
file in one `v1` line: the `V1_TALLY` counts, `rebuild_keys` and the `entries` it accounted for
(`v1_entries`; `_carry_over` holds the rule); a
store that is not the caller's own adds a `diag` `info` line, `V1_PENDING`. With `history` set and every
project listed it then sends a `history_prompt` for each `history.jsonl` prompt whose session has no transcript
(`session_record.history_prompts`). Nothing is written on the reading host. A session the child cannot read becomes an `unreadable` gap naming
only the exception type.

Once it holds the lock the child enforces its limits through `apply_limits` (the `limits` arg, a
`transcript_sources.HostLimits` as a dict) and reports them in a `diag` line whose `event` is
`limits`. It checks its resident memory and its own elapsed time at the start of each file and
every `check_every_records` records; past the ceiling, or past `read_timeout_s` since it started,
it stops with a `partial` gap, keeping the records it already sent, and releases its locks, so a
remote reader whose caller is gone still lets go of its host. Where `signal.alarm` exists the
kernel also ends it `HARD_DEADLINE_GRACE_S` after that limit. Where the Unix backstop
(`RLIMIT_AS`) refuses an allocation the child exits `BACKSTOP_EXIT`, which the caller records as a
`backstop_kill` gap, as it does a child ended by a signal.

Public interface:

- `run(sources, consumer, limits=None, *, store_dir, retry_argv, retention_days, lock_name, ...) -> RunResult` reads each
  source of a `transcript_sources.Sources` in turn, one child at a time, under
  `sources.limits_for(host)` unless `limits` overrides them, calling `consumer(entry, message)`
  for each `hello`, `listing`, `carried_over`, `record` and `history_prompt` message, the hello first. Every gap carries the `retry_argv` that re-collects exactly its
  source: `retry_argv + [RETRY_SOURCE_FLAG, name]` for an `ingest` run, `retry_argv` itself for a
  `lookup` (the same skill invocation, verbatim); `only` limits a run to the named sources, and
  `source_options(entry)` adds per-source args. A read
  past `read_timeout_s` is killed, with its process group, and becomes a `partial` gap, or
  `unreachable` when it never said hello; one past `slow_read_s` adds a warning. The run writes one
  `DIAGNOSTICS_SCHEMA` record to `<store_dir>/diagnostics/<run-date>-<run-id>.json` and prunes
  records there older than `retention_days`, the store's own retention (0 keeps every record),
  and staging files a crashed write left behind; a `lookup` with no gap writes nothing. A source's
  ceiling is the highest `peak_rss` the retained records hold for it, times `peak_headroom`, when
  that is below the configured one. Each source's diagnostics carry its `info` lines, its `v1`
  tally and the `cleanup_period_days` its records are judged by, with the basis.
- `last_cleanup_days(diagnostics_dir) -> dict[str, int]` is each source's `cleanupPeriodDays` as its
  reader last reported it in the retained diagnostics.
- `host_locks(data_dir, lock_name=LOCK_NAME, *, wait_s=0) -> list[HostLock] | HostLock` takes, in
  the caller, the two locks a local read takes (the socket alone when `data_dir` is None), retrying
  a busy one until `wait_s` has passed; the refused one when another reader holds either.
  `run`'s `lock_name` names the per-host lock its readers take, `LOCK_NAME` by default, and is its
  one way in: `options` or `source_options` naming it raise `ValueError`. Readers that share a
  name never read at once. `checked_lock_name(value)` returns a name `LOCK_NAME_RE` allows, short
  enough for the socket path, else raises `ValueError`; `lock_refusal(lock, *, waited_s=0)` is the
  gap kind, detail and holder PID a refused lock means.
- `apply_limits(platform, limits, *, prior_peak=None) -> AppliedLimits` enforces in this process
  each limit `ENFORCEMENT` lists for `platform` and declares the rest missing, with the reason.
- `read_remote(entry, *, fingerprints=(), options=None, data_dir=None, timeout_s=None,
  on_message=None) -> RemoteRead` runs the child for one
  `transcript_sources.SourceEntry` (a local read that is not `capped` needs `data_dir`, the
  caller's own, for its lock) and parses its stdout as data: a line that is not a JSON object
  of a known `kind`, a line over `MAX_MESSAGE_BYTES`, a hello of another protocol, or a stream
  without its `end` line becomes a `protocol` gap, and a child that never said hello an
  `unreachable` one. Records read before the fault are kept, in `records` or through `on_message`, which receives
  each `DATA_KINDS` message as it arrives.
  The child's stderr is discarded, so no gap carries host text.
- `command(via)` is the argv that starts the child; `manifest(args)` the stdin bytes before the
  fingerprints.
- `remote_main(header, data, stream)` is the child's entry point, called by `LOADER`.
- `local_lock(name=LOCK_NAME, platform=sys.platform) -> HostLock` is the per-host reader lock,
  per user (the uid is part of the socket name), and `missing` off Linux. The holder accepts and
  closes each probe, and a probe waits at most `PROBE_TIMEOUT_S`, so a waiting reader never hangs.
- `data_dir_lock(path) -> HostLock` is the second lock a local (empty-via) read takes: `flock` on a
  file in the caller's data dir, which readers in other network namespaces share where the abstract
  socket is invisible. A file that cannot be created or locked for a permission or read-only reason
  is a `sandboxed` gap. A local read whose locks another reader holds retries them until the
  limits' `lock_timeout_s` has passed, then reports a `lock_timeout` gap (`busy` when that wait is
  0). A remote read takes the socket only, writes nothing, and reports `busy` at once.

Callers put this directory on `sys.path` and `import transcript_run`. Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import json
import math
import os
import re
import shlex
import shutil
import signal
import socket
import stat
import subprocess
import sys
import threading
import time
from collections.abc import Callable, Iterable, Sequence
from dataclasses import asdict, dataclass, field, replace
from pathlib import Path
from typing import TypeGuard, cast

import redact
import session_record
import transcript_reader
from transcript_sources import (
    DEFAULT_CLEANUP_DAYS,
    DIAGNOSTICS_DIR,
    DIAGNOSTICS_SCHEMA,
    Gap,
    HostLimits,
    SourceEntry,
    Sources,
    iso,
    local_platform,
    read_diagnostics,
    write_diagnostics,
)
from transcript_limits import (
    LOCK_NAME,
    CeilingReached,
    DeadlineReached,
    HostLock,
    _Meter,
    apply_limits,
    data_dir_lock,
    local_lock,
    peak_rss_bytes,
)
from transcript_values import epoch

PROTOCOL = 1
# The abstract socket name `\0<name>.<uid>` must fit sun_path: https://man7.org/linux/man-pages/man7/unix.7.html
LOCK_NAME_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,79}")
MODULES = (
    "transcript_reader",
    "transcript_values",
    "redact",
    "friction_scan",
    "session_record",
    "transcript_sources",
    "transcript_limits",
    "transcript_run",
)
RULES_ENTRY = "gitleaks-rules.json"
STATE_KEY_ENTRY = "state-key.sh"
MESSAGE_KINDS = frozenset({"hello", "record", "carried_over", "v1", "history_prompt", "listing", "diag", "gap"})
DATA_KINDS = frozenset({"hello", "record", "carried_over", "v1", "history_prompt", "listing"})
SESSION_KINDS = frozenset({"record", "carried_over"})
V1_TALLY = (
    "records", "held", "orphans", "aged", "carried", "rebuild", "filtered",
    "unverified", "unreadable", "other_schema", "unrecognized", "set_aside",
)
V1_BLOCKERS = ("unverified", "unreadable", "other_schema", "unrecognized")
V1_PENDING = "old store pending local migration"
SEGMENT = re.compile(r"p-[0-9a-f]{12}")
HISTORY_KEY = re.compile(r"[0-9a-f]{16}")
GAP_KINDS = frozenset(
    {"unreachable", "busy", "partial", "backstop_kill", "lock_timeout", "protocol", "unreadable", "sandboxed"}
)
MAX_FINGERPRINT_LINE = 64 * 1024
MAX_MESSAGE_BYTES = 32 * 1024 * 1024
CC_VERSION_TIMEOUT_S = 10
# ssh's own errors exit 255 (https://man.openbsd.org/ssh#EXIT_STATUS); a shell's command not found, 127
# (https://pubs.opengroup.org/onlinepubs/9799919799/utilities/V3_chap02.html#tag_19_08_02).
UNREACHABLE_EXITS = frozenset({255, 127})
# A shell's exit for a command SIGKILL or SIGSEGV ended: https://pubs.opengroup.org/onlinepubs/9799919799/utilities/V3_chap02.html#tag_19_08_02
SHELL_SIGNAL_EXITS = frozenset({128 + 9, 128 + 11})
BACKSTOP_EXIT = 75
HARD_DEADLINE_GRACE_S = 60
RUN_KINDS = frozenset({"ingest", "lookup"})
RETRY_SOURCE_FLAG = "--source"
DRIFT_KEYS = ("bad_lines", "incomplete", "unknown")
COUNT_KEYS = (
    "scanned", "ingested", "skipped_unchanged", "skipped_expired", "skipped_orphaned", "history_prompts", "files", "bytes", "drift",
)
LOCK_POLL_S = 0.25
DATA_LOCK_FILE = "transcript-run.lock"
SESSION_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,199}")

LOADER = (
    "import json,sys,types\n"
    "r=sys.stdin.buffer\n"
    "h=json.loads(r.read(int(r.readline())))\n"
    "d={}\n"
    'for n,k,s in h["entries"]:\n'
    " b=r.read(s)\n"
    ' if k=="module":\n'
    '  m=types.ModuleType(n);m.__file__="/shipped/lib/"+n+".py";sys.modules[n]=m\n'
    '  exec(compile(b,m.__file__,"exec"),m.__dict__)\n'
    " else:d[n]=b\n"
    'sys.modules["transcript_run"].remote_main(h,d,r)\n'
)


@dataclass(frozen=True)
class RunResult:
    gaps: tuple[Gap, ...]
    diagnostics_path: Path | None
    sources_done: tuple[str, ...]

    @property
    def exit_code(self) -> int:
        return 1 if self.gaps else 0


@dataclass
class RemoteRead:
    hello: dict | None = None
    records: list[dict] = field(default_factory=list)
    gone: list[tuple[str, str]] = field(default_factory=list)
    diags: list[dict] = field(default_factory=list)
    gaps: list[Gap] = field(default_factory=list)
    end: dict | None = None
    v1: dict | None = None
    returncode: int | None = None


def command(via: Iterable[str] | None) -> list[str]:
    if via:
        return [*via, shlex.join(["python3", "-I", "-c", LOADER])]
    return [sys.executable or "python3", "-I", "-c", LOADER]


def _data_entries() -> list[tuple[str, Path]]:
    return [(RULES_ENTRY, redact.RULES_FILE), (STATE_KEY_ENTRY, session_record.STATE_KEY)]


def manifest(args: dict) -> bytes:
    """The header and entry bytes; a data file this copy cannot read is left out, and the child fails closed."""
    here = Path(__file__).resolve().parent
    entries: list[tuple[str, str, bytes]] = [(name, "module", (here / f"{name}.py").read_bytes()) for name in MODULES]
    for name, path in _data_entries():
        try:
            entries.append((name, "data", path.read_bytes()))
        except OSError:
            continue
    header = json.dumps(
        {"protocol": PROTOCOL, "entries": [[n, k, len(b)] for n, k, b in entries], "args": args}
    ).encode("utf-8")
    return b"".join([str(len(header)).encode("ascii"), b"\n", header, *(b for _, _, b in entries)])


def read_remote(
    entry: SourceEntry,
    *,
    fingerprints: Iterable[dict] = (),
    options: dict | None = None,
    data_dir: str | None = None,
    timeout_s: float | None = None,
    on_message: Callable[[dict], None] | None = None,
) -> RemoteRead:
    args = {"config_dir": entry.config_dir, **(options or {})}
    args.pop("data_lock", None)
    if not entry.via and not args.get("capped"):
        if data_dir is None:
            raise ValueError("a local read needs the caller's data dir for its lock")
        args["data_lock"] = str(Path(data_dir) / DATA_LOCK_FILE)
    payload = manifest(args)
    payload += b"".join(json.dumps(fp).encode("utf-8") + b"\n" for fp in fingerprints)
    result = RemoteRead()
    try:
        child = subprocess.Popen(
            command(entry.via),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            cwd=os.path.abspath(os.sep),
            start_new_session=os.name == "posix",
        )
    except OSError as exc:
        result.gaps.append(Gap(entry.name, "unreachable", f"the reader could not start ({type(exc).__name__})"))
        return result
    deadline = None if timeout_s is None else time.monotonic() + timeout_s
    feeder = threading.Thread(target=_feed, args=(child.stdin, payload), daemon=True)
    feeder.start()
    outcome: dict[str, object] = {}
    reader = threading.Thread(target=_read_stream, args=(entry, child.stdout, result, on_message, outcome), daemon=True)
    reader.start()
    expired = False
    try:
        reader.join(_remaining(deadline))
        if reader.is_alive():
            expired = True
            _kill(child)
            reader.join()
        elif "fault" in outcome or "error" in outcome:
            _kill(child)
        try:
            result.returncode = child.wait(timeout=_remaining(deadline))
        except subprocess.TimeoutExpired:
            expired = True
            _kill(child)
    except BaseException:
        _kill(child)
        raise
    finally:
        result.returncode = child.wait()
        feeder.join()
    if "error" in outcome:
        raise cast(BaseException, outcome["error"])
    fault = cast("str | None", outcome.get("fault"))
    closing = _closing_gap(entry, result, fault, timeout_s if expired else None)
    if closing is not None:
        result.gaps.append(closing)
    return result


def _remaining(deadline: float | None) -> float | None:
    return None if deadline is None else max(0.0, deadline - time.monotonic())


def _read_stream(entry: SourceEntry, stdout, result: RemoteRead, on_message, outcome: dict) -> None:
    """Parse on a thread of its own, so only the caller's thread waits on and kills the child."""
    try:
        fault = _parse(entry, stdout, result, on_message)
    except BaseException as exc:
        outcome["error"] = exc
        return
    if fault is not None:
        outcome["fault"] = fault


def _kill(child: subprocess.Popen) -> None:
    """Kill the child's process group, so what a via started (a shell's own children) dies with it."""
    if os.name == "posix":
        try:
            os.killpg(child.pid, signal.SIGKILL)
            return
        except OSError:
            pass
    child.kill()


def _closing_gap(entry: SourceEntry, result: RemoteRead, fault: str | None, expired_after: float | None) -> Gap | None:
    code = result.returncode
    if expired_after is not None and result.end is None:
        kind = "partial" if result.hello is not None else "unreachable"
        return Gap(entry.name, kind, f"the read passed its {expired_after:g} s wall-time limit and was killed")
    if fault is None and result.end is None and code is not None and (code < 0 or code == BACKSTOP_EXIT or code in SHELL_SIGNAL_EXITS):
        return Gap(entry.name, "backstop_kill", f"the reader was ended by its memory backstop or a signal (exit {code})")
    if result.hello is None:
        kind = "unreachable" if fault is None and code in UNREACHABLE_EXITS else "protocol"
        return Gap(entry.name, kind, fault or f"the reader exited {code} before its hello")
    if fault is not None:
        return Gap(entry.name, "protocol", fault)
    if result.end is None:
        return Gap(entry.name, "protocol", f"the stream ended without its end line (exit {code})")
    return None


def _feed(stdin, payload: bytes) -> None:
    try:
        stdin.write(payload)
        stdin.close()
    except (BrokenPipeError, OSError):
        pass


def _parse(entry: SourceEntry, stdout, result: RemoteRead, on_message: Callable[[dict], None] | None) -> str | None:
    """Fill `result` from the child's stdout; the fault that stopped the read, else None."""
    while frame := stdout.readline(MAX_MESSAGE_BYTES + 1):
        if len(frame) > MAX_MESSAGE_BYTES:
            return f"a line over {MAX_MESSAGE_BYTES} bytes"
        if not frame.endswith(b"\n"):
            return "truncated line"
        try:
            message = json.loads(frame)
        except ValueError:
            return "a line that is not JSON"
        kind = message.get("kind") if isinstance(message, dict) else None
        if kind not in MESSAGE_KINDS:
            return f"unknown message kind {kind!r}"
        if result.hello is None:
            if kind != "hello" or message.get("protocol") != PROTOCOL:
                return f"expected hello for protocol {PROTOCOL}, got {kind} protocol {message.get('protocol')!r}"
            result.hello = message
        elif kind in SESSION_KINDS:
            if not (_safe_session_id(message.get("session_id")) and _safe_segment(message.get("project"))):
                return f"a {kind} whose session_id is not a plain name or whose project is not a segment"
            if not isinstance(message.get("record"), dict):
                return f"a {kind} message without its record"
            if kind == "record" and on_message is None:
                result.records.append(message)
        elif kind == "history_prompt":
            prompt = message.get("prompt")
            if not (isinstance(prompt, dict) and isinstance(prompt.get("key"), str) and HISTORY_KEY.fullmatch(prompt["key"])):
                return "a history prompt without a plain key"
        elif kind == "listing":
            gone, unlisted = message.get("gone"), message.get("unlisted")
            if not isinstance(gone, list) or not all(
                isinstance(s, list) and len(s) == 2 and _safe_segment(s[0]) and _safe_session_id(s[1]) for s in gone
            ):
                return "a listing whose gone sessions are not (segment, session_id) pairs"
            if not isinstance(unlisted, list) or not all(_safe_segment(s) for s in unlisted):
                return "a listing whose unlisted projects are not segments"
            result.gone.extend(tuple(s) for s in gone)
        elif kind == "v1":
            keys, entries = message.get("rebuild_keys"), message.get("entries")
            if not all(_is_count(message.get(name)) for name in V1_TALLY) or not isinstance(keys, list) or not all(
                isinstance(k, list) and len(k) == 2 and _safe_segment(k[0]) and _safe_session_id(k[1]) for k in keys
            ):
                return "a v1 tally whose counts are not counts or whose rebuild keys are not (segment, session_id) pairs"
            if not isinstance(entries, list) or not all(
                isinstance(e, list) and len(e) == 2 and all(isinstance(part, str) for part in e) for e in entries
            ):
                return "a v1 tally whose entries are not (path, type) pairs"
            result.v1 = message
        elif kind == "gap":
            gap_kind = message.get("gap")
            pid = message.get("holder_pid")
            result.gaps.append(
                Gap(
                    entry.name,
                    gap_kind if gap_kind in GAP_KINDS else "protocol",
                    str(message.get("detail", "")),
                    holder_pid=pid if isinstance(pid, int) and not isinstance(pid, bool) else None,
                )
            )
        elif kind == "diag":
            result.diags.append(message)
            if message.get("event") == "end":
                result.end = message
        if kind in DATA_KINDS and on_message is not None:
            on_message(message)
    return None


def _safe_session_id(value: object) -> bool:
    return isinstance(value, str) and SESSION_ID.fullmatch(value) is not None and ".." not in value


def _safe_segment(value: object) -> bool:
    return isinstance(value, str) and SEGMENT.fullmatch(value) is not None


class _ShippedFile:
    """A data entry read where `redact.load_redactor` expects a path."""

    def __init__(self, name: str, data: bytes) -> None:
        self.name = name
        self._data = data

    def read_text(self, encoding: str = "utf-8") -> str:
        return self._data.decode(encoding)


def _emit(message: dict) -> None:
    sys.stdout.write(json.dumps(message) + "\n")
    sys.stdout.flush()


def cc_version() -> str | None:
    exe = shutil.which("claude")
    if exe is None:
        return None
    try:
        done = subprocess.run(
            [exe, "--version"], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=CC_VERSION_TIMEOUT_S
        )
    except (OSError, subprocess.SubprocessError):
        return None
    words = done.stdout.split()
    return words[0] if done.returncode == 0 and words else None


def cleanup_period_days(config_dir: Path) -> int | None:
    """The configured `cleanupPeriodDays`, the default when unset, None when settings.json cannot be read."""
    try:
        settings = json.loads((config_dir / "settings.json").read_text(encoding="utf-8"))
    except FileNotFoundError:
        return DEFAULT_CLEANUP_DAYS
    except (OSError, ValueError):
        return None
    if not isinstance(settings, dict) or "cleanupPeriodDays" not in settings:
        return DEFAULT_CLEANUP_DAYS
    days = settings["cleanupPeriodDays"]
    return days if isinstance(days, int) and not isinstance(days, bool) and days >= 1 else None


def _known(stream) -> tuple[dict[tuple[str, str], tuple[dict, dict]], str | None]:
    """What the caller holds, keyed by (project, session_id); the fault that stopped the read, else None."""
    known: dict[tuple[str, str], tuple[dict, dict]] = {}
    while raw := stream.readline(MAX_FINGERPRINT_LINE + 1):
        if len(raw) > MAX_FINGERPRINT_LINE:
            return known, f"a fingerprint line over {MAX_FINGERPRINT_LINE} bytes"
        line = transcript_reader.decode_line(raw.decode("utf-8", "replace"))
        if line is not None and isinstance(line.get("fingerprint"), dict) and isinstance(line.get("policy"), dict):
            known[(str(line.get("project")), str(line.get("session_id")))] = (line["fingerprint"], line["policy"])
    return known, None


HELLO_FIELDS: dict[str, Callable[[Path], object]] = {
    "host": lambda _config_dir: socket.gethostname(),
    "platform": lambda _config_dir: local_platform(),
    "config_dir": str,
    "cc_version": lambda _config_dir: cc_version(),
    "cleanup_period_days": cleanup_period_days,
}


def remote_main(header: dict, data: dict[str, bytes], stream) -> None:
    started = time.monotonic()
    args = header.get("args") or {}
    config_dir = Path(str(args.get("config_dir", ""))).expanduser()
    hello = {key: report(config_dir) for key, report in HELLO_FIELDS.items()}
    hello["mounted_platform"] = session_record.mounted_platform(config_dir, str(hello["platform"]))
    _emit({"kind": "hello", "protocol": PROTOCOL, **hello})
    args = {**args, "cutoff": _floored_cutoff(args, hello["cleanup_period_days"])}
    counts: dict = {key: dict.fromkeys(DRIFT_KEYS, 0) if key == "drift" else 0 for key in COUNT_KEYS}
    limits = HostLimits(**(args.get("limits") or {}))
    if hasattr(signal, "alarm"):
        signal.signal(signal.SIGALRM, signal.SIG_DFL)
        signal.alarm(math.ceil(limits.read_timeout_s) + HARD_DEADLINE_GRACE_S)
    known, fault = _known(stream)
    if fault is not None:
        _emit({"kind": "gap", "gap": "protocol", "detail": fault})
        _end(counts, "not-taken")
        return
    held: list[HostLock] = []
    mechanism = "skipped"
    if not args.get("capped"):
        wait_s = limits.lock_timeout_s if args.get("data_lock") else 0
        taken = _take_locks(args, wait_s)
        if isinstance(taken, HostLock):
            _refused(taken, waited_s=wait_s)
            _end(counts, taken.mechanism)
            return
        held = taken
        mechanism = "+".join(lock.mechanism for lock in held)
        _emit({"kind": "diag", "event": "lock", "mechanism": mechanism})
    platform = str(args.get("limits_platform") or local_platform())
    prior_peak = args.get("prior_peak_rss")
    enforced = apply_limits(platform, limits, prior_peak=prior_peak if isinstance(prior_peak, int) else None)
    _emit({"kind": "diag", "event": "limits", "platform": platform, "applied": enforced.applied, "missing": enforced.missing})
    meter = _Meter(enforced.ceiling, limits.check_every_records, started + limits.read_timeout_s)
    try:
        _ingest(args, config_dir, data, known, counts, meter, limits.read_timeout_s)
    except MemoryError:
        os._exit(BACKSTOP_EXIT)
    finally:
        for lock in held:
            lock.release()
    _end(counts, mechanism)


def _take_locks(args: dict, wait_s: float) -> list[HostLock] | HostLock:
    """Every lock this read needs, or the refused one; a busy lock is retried until `wait_s` has passed."""
    takes = [lambda: local_lock(str(args.get("lock_name") or LOCK_NAME), str(args.get("lock_platform") or sys.platform))]
    if args.get("data_lock"):
        takes.append(lambda: data_dir_lock(str(args["data_lock"])))
    deadline = time.monotonic() + wait_s
    while True:
        held: list[HostLock] = []
        refused = None
        for take in takes:
            lock = take()
            if not lock.acquired:
                refused = lock
                break
            held.append(lock)
        if refused is None:
            return held
        for lock in held:
            lock.release()
        remaining = deadline - time.monotonic()
        if refused.gap is not None or remaining <= 0:
            return refused
        time.sleep(min(LOCK_POLL_S, remaining))


def checked_lock_name(value: str) -> str:
    if not LOCK_NAME_RE.fullmatch(value):
        raise ValueError("a lock name is 1 to 80 letters, digits, '.', '_' or '-', starting with a letter or digit")
    return value


def lock_refusal(lock: HostLock, *, waited_s: float = 0) -> dict:
    if lock.gap is not None:
        return {"gap": lock.gap, "detail": lock.detail, "holder_pid": None}
    pid = f" by pid {lock.holder_pid}" if lock.holder_pid else ""
    detail = lock.detail or f"another reader holds the host lock{pid}"
    if waited_s > 0:
        detail = f"{detail}, still after waiting {waited_s:g} s"
    return {"gap": "lock_timeout" if waited_s > 0 else "busy", "detail": detail, "holder_pid": lock.holder_pid}


def _refused(lock: HostLock, *, waited_s: float = 0) -> None:
    _emit({"kind": "gap", **lock_refusal(lock, waited_s=waited_s)})


def _end(counts: dict, lock: str) -> None:
    _emit({"kind": "diag", "event": "end", "lock": lock, "peak_rss_bytes": peak_rss_bytes(), **counts})


def _ingest(
    args: dict, config_dir: Path, data: dict[str, bytes], known: dict, counts: dict, meter: _Meter, timeout_s: float
) -> None:
    rules = data.get(RULES_ENTRY)
    redactor = (
        redact.load_redactor(cast(Path, _ShippedFile(RULES_ENTRY, rules)))
        if rules is not None
        else redact.Redactor((), {RULES_ENTRY: "not shipped"})
    )
    identity = session_record.RepoIdentity(
        script=data.get(STATE_KEY_ENTRY, b"").decode("utf-8"),
        on_warn=lambda message: _emit({"kind": "diag", "event": "warning", "message": message}),
    )
    digest = str(args.get("collector_digest", ""))
    excerpt_chars = _count_arg(args, "excerpt_chars")
    excerpt_words = _count_arg(args, "excerpt_words")
    since, cutoff = _epoch_arg(args, "since"), _epoch_arg(args, "cutoff")
    floor = max((t for t in (since, cutoff) if t is not None), default=None)
    wanted = {str(s) for s in args.get("sessions") or ()}
    policy = session_record.record_policy(digest, excerpt_chars, excerpt_words, redactor.fail_closed)
    listed = _list_transcripts(config_dir / "projects")
    if listed is None:
        _emit({"kind": "gap", "gap": "unreadable", "detail": "the source's projects directory cannot be read"})
        return
    mains, unlisted = listed
    for _ in unlisted:
        _emit({"kind": "gap", "gap": "unreadable", "detail": "a project directory could not be listed"})
    by_key = {
        (session_record.project_segment(main.parent.name), main.stem): main for main in mains if session_record.ORPHANED not in main.stem
    }
    present = set(by_key)
    gone = sorted(key for key in set(known) - present if key[0] not in unlisted)
    _emit({"kind": "listing", "gone": [list(key) for key in gone], "unlisted": sorted(unlisted)})
    v1 = args.get("v1")
    try:
        if isinstance(v1, dict):
            _carry_over(v1, by_key, set(known), unlisted, Window(cutoff, since, wanted), meter)
    except (CeilingReached, DeadlineReached) as stop:
        _stopped(stop, meter, counts, timeout_s)
        return
    if args.get("list_only"):
        return
    force = args.get("force") is True
    for main in mains:
        if session_record.ORPHANED in main.stem:
            counts["skipped_orphaned"] += 1
            continue
        segment = session_record.project_segment(main.parent.name)
        if wanted and main.stem not in wanted:
            continue
        try:
            meter.check_deadline()
            mtime = main.stat().st_mtime
            if since is not None and mtime < since:
                continue
            counts["scanned"] += 1
            if cutoff is not None and mtime < cutoff:
                counts["skipped_expired"] += 1
                continue
            subagents = list(transcript_reader.iter_subagents(main))
            fp = session_record.fingerprint(main, [s.path for s in subagents])
            if not force and session_record.is_unchanged(known.get((segment, main.stem)), fp, policy):
                counts["skipped_unchanged"] += 1
                continue
            record = session_record.build_record(
                main,
                subagents,
                fp,
                version=str(args.get("collector_version", "unknown")),
                digest=digest,
                redactor=redactor,
                identity=identity,
                excerpt_chars=excerpt_chars,
                excerpt_words=excerpt_words,
                meter=meter,
            )
            end = epoch(record["time"]["end"])
            if cutoff is not None and end is not None and end < cutoff:
                counts["skipped_expired"] += 1
                continue
        except (CeilingReached, DeadlineReached) as stop:
            _stopped(stop, meter, counts, timeout_s)
            return
        except MemoryError:
            raise
        except Exception as exc:
            _emit({"kind": "gap", "gap": "unreadable", "detail": f"a session could not be read ({type(exc).__name__})"})
            continue
        _count(counts, fp, record)
        _emit({"kind": "record", "project": segment, "session_id": main.stem, "record": record})
    if not args.get("history"):
        return
    if unlisted:
        _emit({"kind": "diag", "event": "warning", "message": "history prompts skipped: a project directory could not be listed"})
        return
    scrub = session_record.Scrubber(redactor, excerpt_chars)
    sessions = {session for _, session in present}
    try:
        for prompt in session_record.history_prompts(
            config_dir, sessions, scrub=scrub, excerpt_chars=excerpt_chars, since=floor, meter=meter
        ):
            counts["history_prompts"] += 1
            _emit({"kind": "history_prompt", "prompt": prompt})
    except (CeilingReached, DeadlineReached) as stop:
        _stopped(stop, meter, counts, timeout_s)


def _floored_cutoff(args: dict, cleanup_days: object) -> float | None:
    """The `cutoff`, moved back to this source's own `cleanupPeriodDays` when `retention_floor` is set."""
    cutoff = _epoch_arg(args, "cutoff")
    if cutoff is None or not args.get("retention_floor") or not _is_days(cleanup_days):
        return cutoff
    return min(cutoff, time.time() - cleanup_days * 86400)


@dataclass(frozen=True)
class Window:
    """Which transcripts an ingest reads: none modified before `cutoff` or `since`, and only `sessions` when set."""

    cutoff: float | None
    since: float | None
    sessions: set[str]

    def expires(self, main: Path) -> bool:
        return self.cutoff is not None and _mtime(main) < self.cutoff

    def passes_over(self, main: Path) -> bool:
        return (bool(self.sessions) and main.stem not in self.sessions) or (self.since is not None and _mtime(main) < self.since)


def _mtime(path: Path) -> float:
    try:
        return path.stat().st_mtime
    except OSError:
        return math.inf


def _carry_over(
    v1: dict, mains: dict[tuple[str, str], Path], known: set[tuple[str, str]], unlisted: set[str], window: Window, meter: _Meter
) -> None:
    """Account for every file of the old store at `v1["store"]`, reading only, and send what the caller must keep.

    The one rule for old records: each readable record of `v1["schema"]` the caller does not hold is
    sent as `carried_over` when its transcript is gone (`orphans`) or older than the window
    (`aged`; the caller's retention then prunes it), and is otherwise to be rebuilt from its
    transcript (`rebuild_keys`; `filtered` counts those this ingest passes over by `since` or
    `sessions`). Every other file is counted: `unreadable`, `other_schema`, `unrecognized` (not
    `p-<12 hex>/<session>.json`, any symlink, which is never followed, any directory but a
    `p-<12 hex>` project directory directly under the store, and any directory that could not be
    listed), `unverified` (its project could not be listed), `set_aside` (a record of a
    set-aside transcript, which no collector keeps). A store that is itself a symlink, or whose
    parent (the old store's root) is one, is read no further and counts as one `unrecognized`
    file. The tally goes out as one `v1` line with the `v1_entries` listing it was made from, so the
    caller can tell whether the store changed since; an old store that is not the caller's own
    (`own` unset) also adds the `V1_PENDING` info line.
    """
    store = Path(str(v1.get("store", ""))).expanduser()
    linked = store.is_symlink() or store.parent.is_symlink()
    if not (linked or store.is_dir()):
        return
    if not v1.get("own"):
        _emit({"kind": "diag", "event": "info", "message": V1_PENDING})
    tally = dict.fromkeys(V1_TALLY, 0)
    rebuild: list[list[str]] = []
    if linked:
        tally["unrecognized"] = 1
        _emit({"kind": "v1", **tally, "rebuild_keys": rebuild, "entries": []})
        return
    entries = v1_entries(store)
    for rel, kind in entries:
        meter.tick()
        path = store / rel
        parts = Path(rel).parts
        if kind == "dir" and len(parts) == 1 and _safe_segment(parts[0]):
            continue
        plain = kind == "file" and len(parts) == 2 and path.suffix == ".json"
        key = (parts[0], path.stem) if plain else ("", "")
        if not (_safe_segment(key[0]) and _safe_session_id(key[1])):
            tally["unrecognized"] += 1
            continue
        if session_record.ORPHANED in key[1]:
            tally["set_aside"] += 1
            continue
        try:
            record = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            tally["unreadable"] += 1
            continue
        if not isinstance(record, dict):
            tally["unreadable"] += 1
            continue
        if record.get("schema") != v1.get("schema"):
            tally["other_schema"] += 1
            continue
        tally["records"] += 1
        main = mains.get(key)
        if key in known:
            tally["held"] += 1
        elif main is None and key[0] in unlisted:
            tally["unverified"] += 1
        elif main is not None and not window.expires(main):
            rebuild.append(list(key))
            tally["filtered"] += int(window.passes_over(main))
        else:
            tally["orphans" if main is None else "aged"] += 1
            tally["carried"] += 1
            _emit({"kind": "carried_over", "project": key[0], "session_id": key[1], "record": record})
    tally["rebuild"] = len(rebuild)
    _emit({"kind": "v1", **tally, "rebuild_keys": rebuild, "entries": [list(entry) for entry in entries]})


def v1_entries(store: Path) -> list[tuple[str, str]]:
    """Every entry under `store`, sorted: its POSIX path relative to `store` and its lstat type, `file`,
    `dir`, `link` (to a file or a directory, never followed) or `other`; a directory that cannot be
    listed is also an `unlistable` entry."""
    found: list[tuple[str, str]] = []

    def unlistable(exc: OSError) -> None:
        found.append((Path(str(exc.filename)).relative_to(store).as_posix(), "unlistable"))

    for top, dirs, files in os.walk(store, onerror=unlistable, followlinks=False):
        base = Path(top)
        for name in (*files, *dirs):
            path = base / name
            try:
                mode = path.lstat().st_mode
            except OSError:
                continue
            kind = "link" if stat.S_ISLNK(mode) else "file" if stat.S_ISREG(mode) else "dir" if stat.S_ISDIR(mode) else "other"
            found.append((path.relative_to(store).as_posix(), kind))
    return sorted(found)


def _list_transcripts(projects: Path) -> tuple[list[Path], set[str]] | None:
    """Every `<project>/<session>.jsonl` under `projects`, in path order, and the segments of project
    directories that could not be listed; None when `projects` itself cannot be read."""
    try:
        with os.scandir(projects) as entries:
            dirs = [entry for entry in entries if not entry.name.startswith(".") and entry.is_dir()]
    except OSError:
        return None
    mains: list[Path] = []
    unlisted: set[str] = set()
    for project in dirs:
        try:
            with os.scandir(project.path) as entries:
                mains.extend(
                    Path(entry.path) for entry in entries
                    if entry.name.endswith(".jsonl") and not entry.name.startswith(".") and entry.is_file()
                )
        except OSError:
            unlisted.add(session_record.project_segment(project.name))
    return sorted(mains), unlisted


def _stopped(stop: Exception, meter: _Meter, counts: dict, timeout_s: float) -> None:
    if isinstance(stop, CeilingReached):
        detail = (
            f"stopped at {stop.rss} bytes resident, over the {meter.ceiling}-byte memory ceiling, "
            f"after {counts['ingested']} sessions"
        )
    else:
        detail = f"stopped at its own {timeout_s:g} s read time limit, after {counts['ingested']} sessions"
    _emit({"kind": "gap", "gap": "partial", "detail": detail})


def _count_arg(args: dict, key: str) -> int:
    """A non-negative count the caller sets; 0, which stores no excerpt and flags no turn, when unset."""
    value = args.get(key)
    return value if isinstance(value, int) and not isinstance(value, bool) and value >= 0 else 0


def _epoch_arg(args: dict, key: str) -> float | None:
    value = args.get(key)
    return float(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def _count(counts: dict, fp: dict, record: dict) -> None:
    parse = record.get("parse") or {}
    counts["ingested"] += 1
    counts["files"] += int(parse.get("files", 0))
    counts["bytes"] += int(fp.get("main_size", 0)) + int(fp.get("sub_size", 0))
    for key in DRIFT_KEYS:
        counts["drift"][key] += int(parse.get(key, 0))


def run(
    sources: Sources,
    consumer: Callable[[SourceEntry, dict], None],
    limits: HostLimits | None = None,
    *,
    store_dir: str | Path,
    retry_argv: Sequence[str],
    retention_days: float,
    kind: str = "ingest",
    only: Iterable[str] | None = None,
    fingerprints: Callable[[SourceEntry], Iterable[dict]] | None = None,
    options: dict | None = None,
    source_options: Callable[[SourceEntry], dict] | None = None,
    data_dir: str | Path | None = None,
    lock_name: str = LOCK_NAME,
) -> RunResult:
    if kind not in RUN_KINDS:
        raise ValueError(f"run kind {kind!r} is not one of {', '.join(sorted(RUN_KINDS))}")
    if "lock_name" in (options or {}):
        raise ValueError("pass lock_name as run()'s own parameter, not inside options")
    started = time.time()
    diagnostics_dir = Path(store_dir) / DIAGNOSTICS_DIR
    peaks = _prior_peaks(diagnostics_dir)
    cleanup = last_cleanup_days(diagnostics_dir)
    wanted = None if only is None else set(only)
    warnings = [f"the retry names {name!r}, which no source has" for name in sorted((wanted or set()) - {e.name for e in sources.all()})]
    gaps: list[Gap] = []
    done: list[str] = []
    source_diags: list[dict] = []
    for entry in sources.all():
        if wanted is not None and entry.name not in wanted:
            continue
        host_limits = limits or sources.limits_for(entry.host)
        extra = source_options(entry) if source_options else {}
        if "lock_name" in extra:
            raise ValueError("pass lock_name as run()'s own parameter, not inside source_options")
        began = time.monotonic()
        read = read_remote(
            entry,
            fingerprints=fingerprints(entry) if fingerprints else (),
            options={
                "lock_name": lock_name,
                **(options or {}),
                **extra,
                "limits": asdict(host_limits),
                "prior_peak_rss": peaks.get(entry.name),
            },
            data_dir=str(data_dir or store_dir),
            timeout_s=host_limits.read_timeout_s,
            on_message=lambda message, entry=entry: consumer(entry, message),
        )
        elapsed = time.monotonic() - began
        if elapsed > host_limits.slow_read_s:
            warnings.append(f"{entry.name}: the read took {elapsed:.1f} s, past the {host_limits.slow_read_s:g} s slow-read threshold")
        retry = tuple(retry_argv) if kind == "lookup" else (*retry_argv, RETRY_SOURCE_FLAG, entry.name)
        source_gaps = [replace(gap, retry_argv=retry) for gap in read.gaps]
        gaps.extend(source_gaps)
        if not source_gaps:
            done.append(entry.name)
        source_diags.append(_source_diag(entry, read, elapsed, len(source_gaps), cleanup.get(entry.name)))
    path = None
    if kind == "ingest" or gaps:
        record = {
            "schema": DIAGNOSTICS_SCHEMA,
            "kind": kind,
            "started_at": iso(started),
            "finished_at": iso(time.time(), "microseconds"),
            "duration_s": round(time.time() - started, 3),
            "versions": {"protocol": PROTOCOL, "python": sys.version.split()[0]},
            "sources": source_diags,
            "gaps": [asdict(gap) for gap in gaps],
            "warnings": warnings,
        }
        path = write_diagnostics(diagnostics_dir, record, started, retention_days)
    return RunResult(tuple(gaps), path, tuple(done))


def cleanup_days(read: RemoteRead, last_cleanup: int | None) -> tuple[int, str]:
    """A source's `cleanupPeriodDays` and its basis: its reader's hello, else `last_cleanup` (its latest in
    the retained diagnostics), else `DEFAULT_CLEANUP_DAYS`."""
    reported = (read.hello or {}).get("cleanup_period_days")
    if _is_days(reported):
        return reported, "hello"
    if last_cleanup is not None:
        return last_cleanup, "prior-diagnostics"
    return DEFAULT_CLEANUP_DAYS, "default"


def _source_diag(entry: SourceEntry, read: RemoteRead, elapsed: float, gap_count: int, last_cleanup: int | None) -> dict:
    """One source's diagnostics; the reader's own figures are data from that host, kept as sent.

    `reported` is the reader's own hello, `provenance` what its records are stamped with, and
    `drift.platform_mismatch` is 1 when that stamped platform is not the source's declared one.
    `cleanup_period_days` is the hello's, else `last_cleanup` (the source's latest reported value in
    the retained diagnostics), else `DEFAULT_CLEANUP_DAYS`, with `cleanup_period_days_basis` naming which.
    """
    end = read.end or {}
    cleanup, basis = cleanup_days(read, last_cleanup)
    limits = next((d for d in read.diags if d.get("event") == "limits"), {})
    hello = read.hello or {}
    stamped = session_record.provenance(entry.name, hello, entry.platform) if read.hello is not None else None
    drift = end.get("drift")
    if isinstance(drift, dict):
        drift = {**drift, "platform_mismatch": int(stamped is not None and stamped["platform"] != entry.platform)}
    return {
        "name": entry.name,
        "host": entry.host,
        "platform": entry.platform,
        "remote": entry.via is not None,
        "reported": {key: hello.get(key) for key in (*HELLO_FIELDS, "mounted_platform")},
        "provenance": stamped,
        "duration_s": round(elapsed, 3),
        "lock": end.get("lock"),
        **{key: end.get(key) for key in COUNT_KEYS},
        "drift": drift,
        "peak_rss": end.get("peak_rss_bytes"),
        "limits_applied": limits.get("applied", {}),
        "limits_missing": limits.get("missing", {}),
        "warnings": [str(d.get("message")) for d in read.diags if d.get("event") == "warning"],
        "info": [str(d.get("message")) for d in read.diags if d.get("event") == "info"],
        "v1": {key: read.v1[key] for key in V1_TALLY} if read.v1 else None,
        "cleanup_period_days": cleanup,
        "cleanup_period_days_basis": basis,
        "gaps": gap_count,
    }


def _is_count(value: object) -> TypeGuard[int]:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def _is_days(value: object) -> TypeGuard[int]:
    return isinstance(value, int) and not isinstance(value, bool) and value >= 1


def _prior_sources(diagnostics_dir: Path) -> Iterable[tuple[str, dict]]:
    """(started_at, source) for each named source entry of each retained diagnostics record."""
    for _path, record in read_diagnostics(diagnostics_dir):
        sources = record.get("sources")
        for source in sources if isinstance(sources, list) else ():
            if isinstance(source, dict) and isinstance(source.get("name"), str):
                yield str(record.get("started_at") or ""), source


def _prior_peaks(diagnostics_dir: Path) -> dict[str, int]:
    """The highest `peak_rss` each source reached in the retained diagnostics records."""
    peaks: dict[str, int] = {}
    for _started, source in _prior_sources(diagnostics_dir):
        name, peak = source["name"], source.get("peak_rss")
        if isinstance(peak, int) and not isinstance(peak, bool) and peak > 0:
            peaks[name] = max(peaks.get(name, 0), peak)
    return peaks


def last_cleanup_days(diagnostics_dir: str | Path) -> dict[str, int]:
    """Each source's `cleanupPeriodDays` as its own reader last reported it in the retained diagnostics records."""
    latest: dict[str, tuple[str, int]] = {}
    for started, source in _prior_sources(Path(diagnostics_dir)):
        reported = source.get("reported")
        days = reported.get("cleanup_period_days") if isinstance(reported, dict) else None
        if _is_days(days) and started >= latest.get(source["name"], ("", 0))[0]:
            latest[source["name"]] = (started, days)
    return {name: days for name, (_started, days) in latest.items()}


def host_locks(data_dir: str | Path | None, lock_name: str = LOCK_NAME, *, wait_s: float = 0) -> list[HostLock] | HostLock:
    """The locks a local read takes, held by the caller itself; the refused one when another reader holds either."""
    data_lock = None if data_dir is None else str(Path(data_dir) / DATA_LOCK_FILE)
    return _take_locks({"data_lock": data_lock, "lock_name": lock_name}, wait_s)
