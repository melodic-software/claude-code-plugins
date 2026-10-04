#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Ingest Claude Code transcripts into the audit-sessions store.

    collect.py collect --data-dir D [--projects-root P] [--since YYYY-MM-DD] [--session ID ...]
                       [--force] [--retention-days N] [--excerpt-chars N] [--excerpt-words N]
    collect.py census --data-dir D [--version V] [--model M]
    collect.py drift --data-dir D [--min-count N] [--versions N] [--session-floor N] [--canaries FILE]

Writes one `session-record/v1` file per main session (the main transcript plus its subagents)
under `D/audit-sessions/store/v1/`, the machine-wide store `sweep.py` reads; a transcript Claude
Code set aside (`<session>.orphaned-*.jsonl`) is skipped and counted, not ingested. A session whose
fingerprint matches its stored record is skipped, unless that record was written by another
collector version, under other excerpt limits, or with redaction failing closed where it now
works or the reverse. With a retention window, records of sessions
that ended before it are pruned and such sessions are not ingested. Typed turns of at most
`--excerpt-words` words right after an assistant message keep an excerpt, redacted by redact.py
and then cut to `--excerpt-chars`; when redaction fails closed no excerpt is stored and the run
warns. Every other stored string from a transcript is redacted too, and one longer than
max(4096, 16 x --excerpt-chars) is skipped and counted instead. Repo identity comes from
lib/state-key.sh, run once per distinct cwd.

`census` and `drift` read the store only, through census.py: the per-(version, model) aggregate
and its classified diff between Claude Code versions (exit 1 when drift is found).

Prints one JSON envelope on stdout; exit 0 pass, 1 warning, 2 error. Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import argparse
import bisect
import hashlib
import json
import ntpath
import os
import posixpath
import re
import subprocess
import sys
import time
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parents[3]
_PLUGIN_SCRIPTS = str(PLUGIN_ROOT / "scripts")
if _PLUGIN_SCRIPTS not in sys.path:
    sys.path.insert(0, _PLUGIN_SCRIPTS)

import census  # noqa: E402  (beside this script)
import redact  # noqa: E402  (beside this script)
import transcript_reader  # noqa: E402  (plugin-level scripts/transcript_reader.py)

SCHEMA = "audit-sessions.collect/v1"
CENSUS_SCHEMA = "audit-sessions.census/v1"
DRIFT_SCHEMA = "audit-sessions.drift/v1"
RECORD_SCHEMA = "session-record/v1"
STATE_KEY = PLUGIN_ROOT / "lib" / "state-key.sh"
HEAD_BYTES = 4096

COMMAND_RE = re.compile(r"<command-name>/?([^<\s]+)</command-name>")
EDIT_TOOLS = frozenset({"Edit", "Write", "MultiEdit", "NotebookEdit"})
# System subtypes seen on current versions; any other is counted in `unknown.system_subtypes`.
SYSTEM_SUBTYPES = frozenset(
    {
        "agents_killed",
        "away_summary",
        "bridge_status",
        "compact_boundary",
        "informational",
        "local_command",
        "scheduled_task_fire",
        "stop_hook_summary",
        "turn_duration",
    }
)

# Correction lexicon: high precision, low recall, so it only adds a flag to a turn already kept.
CORRECTION_RE = re.compile(
    r"^(no\b|nope\b|wrong\b|stop\b|wait\b|hold on\b|undo\b|revert\b|don'?t\b|do not\b|not that\b|hmm+,? no)"
    r"|\b(that'?s not|that is not|this is not|isn'?t what|not what i|i said|i asked|i told you|i meant|"
    r"i don'?t think|i thought you|you were supposed|supposed to|why did you|why are you|why would you|why just|"
    r"you didn'?t|you did not|you forgot|you missed|you broke|you shouldn'?t|should not have|shouldn'?t have|"
    r"instead of|rather than|actually,|wrong|incorrect|mistake|not correct|go back|roll back|revert|undo|"
    r"doesn'?t work|didn'?t work|still (broken|failing|wrong)|that'?s not right)\b",
    re.I,
)
CORRECTION_NEG = re.compile(r"never ?mind|stepped away|try again", re.I)
FRUSTRATION_RE = re.compile(r"\b(wtf|god ?damn|damn|shit|crap|ffs|seriously|ugh)\b|!{2,}|\?{3,}", re.I)

# Census: key paths to this depth; keys that are data (ids, paths, question text) fold to <*>.
CENSUS_DEPTH = 3
DYNAMIC_KEY = re.compile(r"^(toolu_|srvtoolu_|call_)|[/\\\s?:]|^[0-9a-f-]{16,}$|^\d+$")
DATA_MAPS = frozenset({"trackedFileBackups", "answers", "wireToolInputs"})
# A census value is kept only when it looks like an identifier; free text buckets as <other>.
CENSUS_LABEL = re.compile(r"[A-Za-z0-9_.:-]{1,64}")

# Redaction is skipped, never preceded by a cut, for text longer than this: a cut can split a secret
# and leave its head in the kept window, and the vendored patterns slow down on very long text.
TEXT_CAP_FLOOR = 4096
TOO_LONG = "<too-long>"
SUPPRESSED = "<suppressed>"
# `<session>.orphaned-<timestamp>-<suffix>.jsonl` is an earlier transcript Claude Code set aside, not
# a second session. Pointer: https://code.claude.com/docs/en/claude-directory#cleaned-up-automatically
# (as of 2026-10-04; recheck when that table renames the set-aside transcript).
ORPHANED = ".orphaned-"


def emit(status: str, summary: str, data: dict, code: int, schema: str = SCHEMA) -> int:
    print(json.dumps({"schema": schema, "status": status, "summary": summary, "data": data}, indent=2))
    return code


def warn(message: str) -> None:
    print(f"collect.py: warning: {message}", file=sys.stderr)


def default_projects_root() -> Path:
    config_dir = os.environ.get("CLAUDE_CONFIG_DIR")
    return (Path(config_dir) if config_dir else Path.home() / ".claude") / "projects"


def collector_version() -> str:
    try:
        manifest = json.loads((PLUGIN_ROOT / ".claude-plugin" / "plugin.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return "unknown"
    return manifest.get("version", "unknown")


def store_dir(data_dir: Path) -> Path:
    return data_dir / "audit-sessions" / "store" / "v1" / "sessions"


def project_segment(project_dir: str) -> str:
    return "p-" + hashlib.sha256(project_dir.encode("utf-8")).hexdigest()[:12]


def _obj(value: object) -> dict:
    return value if isinstance(value, dict) else {}


def _number(value: object) -> float:
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else 0


def _epoch(value: object) -> float | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return (parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)).timestamp()


def _iso(epoch: float | None) -> str | None:
    if epoch is None:
        return None
    return datetime.fromtimestamp(epoch, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _percentile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(round(fraction * (len(ordered) - 1))))]


def _relpath(path: str, cwd: str | None) -> str:
    if cwd:
        try:
            return Path(path).relative_to(cwd).as_posix()
        except ValueError:
            pass
    return path


def _norm_key(key: str, parent: str) -> str:
    return "<*>" if parent in DATA_MAPS or len(key) > 40 or DYNAMIC_KEY.search(key) else key


def _key_paths(obj: object, prefix: str, depth: int, out: set[str]) -> None:
    """Key paths to CENSUS_DEPTH; list items merge under `[]`, tagged with their `type` value."""
    if depth >= CENSUS_DEPTH:
        return
    if isinstance(obj, dict):
        parent = prefix.rsplit(".", 1)[-1]
        for key, value in obj.items():
            path = f"{prefix}.{_norm_key(str(key), parent)}" if prefix else _norm_key(str(key), parent)
            out.add(path)
            if parent not in DATA_MAPS:
                _key_paths(value, path, depth + 1, out)
    elif isinstance(obj, list):
        for item in obj[:50]:
            if isinstance(item, dict):
                kind = item.get("type")
                base = f"{prefix}[]" + (f"<{kind}>" if isinstance(kind, str) else "")
                for key, value in item.items():
                    path = f"{base}.{_norm_key(str(key), '')}"
                    out.add(path)
                    _key_paths(value, path, depth + 1, out)


def _label(value: object) -> str:
    text = str(value)
    return text if CENSUS_LABEL.fullmatch(text) else "<other>"


def census_keys(record: dict) -> tuple[str, list[str]]:
    """The (version|model) bucket of one record and the `<section>:<key>` names it counts."""
    kind = record.get("type") if isinstance(record.get("type"), str) else "<none>"
    message = _obj(record.get("message"))
    version = record.get("version") if isinstance(record.get("version"), str) else "unknown"
    model = "*"
    if kind == "assistant":
        model = message.get("model") if isinstance(message.get("model"), str) else "unknown"
    paths: set[str] = set()
    _key_paths(record, "", 0, paths)
    keys = [f"record_type:{kind}", *(f"key_path:{kind}:{p}" for p in paths)]
    if kind == "system":
        keys.append(f"system_subtype:{_label(record.get('subtype'))}")
    elif kind == "attachment":
        attachment = record.get("attachment")
        keys.append(f"attachment_type:{_label(attachment.get('type') if isinstance(attachment, dict) else attachment)}")
    elif kind == "assistant":
        for key, value in _obj(message.get("usage")).items():
            keys.append(f"usage_key:{key}")
            keys.extend(f"usage_key:{key}.{inner}" for inner in _obj(value))
        if "error" in record:
            keys.append(f"assistant_error:{_label(record.get('error'))}")
        if "effort" in record:
            keys.append(f"effort_value:{_label(record.get('effort'))}")
    return f"{version}|{model}", keys


class SessionScan:
    """Accumulates one session's records, main transcript first, then each subagent."""

    def __init__(self, excerpt_words: int) -> None:
        self.excerpt_words = excerpt_words
        self.ledgers = {"main": transcript_reader.UsageLedger(), "sub": transcript_reader.UsageLedger()}
        self.messages: dict[str, set] = {"main": set(), "sub": set()}
        self.models = {"main": Counter(), "sub": Counter()}
        self.effort = {"main": Counter(), "sub": Counter()}
        self.interrupts = {"main": 0, "sub": 0}
        self.cache_miss: Counter = Counter()
        self.missed_input_tokens = 0
        self.rate_limit: Counter = Counter()
        self.usage_limit_notices = 0
        self.errors: Counter = Counter()
        self.tool_ids: set[str] = set()
        self.tools: Counter = Counter()
        self.denials: Counter = Counter()
        self.user_rejected = 0
        self.edits: Counter = Counter()
        self.skills: Counter = Counter()
        self.slash: Counter = Counter()
        self.stop_hook_ms: list[float] = []
        self.stop_hook_blocks = 0
        self.stop_hook_errors = 0
        self.compactions: list[dict] = []
        self.started_with_clear = False
        self.active_ms: float = 0
        self.turn_durations = 0
        self.thinking_ms: float = 0
        self.timestamps: list[float] = []
        self.human_timestamps: list[float] = []
        self.versions: set[str] = set()
        self.entrypoints: set[str] = set()
        self.branches: set[str] = set()
        self.prs: set[tuple[str, int]] = set()
        self.permission_modes: Counter = Counter()
        self.permission_changes = 0
        self.last_permission_mode: object = None
        self.custom_title: str | None = None
        self.agent_name: str | None = None
        self.cwd: str | None = None
        self.human_turns = 0
        self.flagged: list[tuple[int, dict, str, int, list[str]]] = []
        self.last_kind: str | None = None
        self.unknown_types: Counter = Counter()
        self.unknown_subtypes: Counter = Counter()
        self.census: dict[str, Counter] = {}
        self.bucket = ""
        self.usage_seen: dict[tuple[str, str], tuple] = {}
        self.usage_split: set[tuple[str, str]] = set()

    def add(self, record: dict, side: str) -> None:
        self.bucket, keys = census_keys(record)
        self.census.setdefault(self.bucket, Counter()).update(keys)
        kind = transcript_reader.record_kind(record)
        if kind == "unknown":
            raw = record.get("type")
            self.unknown_types[raw if isinstance(raw, str) else "<none>"] += 1
            return
        ts = None
        if side == "main":
            ts = _epoch(record.get("timestamp"))
            if ts is not None and kind in ("user", "assistant", "system"):
                self.timestamps.append(ts)
            if self.cwd is None and isinstance(record.get("cwd"), str):
                self.cwd = record["cwd"]
            for field, values in (("version", self.versions), ("gitBranch", self.branches)):
                if isinstance(record.get(field), str) and record[field]:
                    values.add(record[field])
            if isinstance(record.get("entrypoint"), str) and record["entrypoint"]:
                self.entrypoints.add(_label(record["entrypoint"]))
        handler = getattr(self, "_" + kind.replace("-", "_"), None)
        if handler is not None:
            handler(record, side, ts)

    def _assistant(self, record: dict, side: str, _ts: float | None) -> None:
        message = _obj(record.get("message"))
        self.ledgers[side].add(record)
        self._usage_invariant(message, side)
        key = message.get("id") or record.get("uuid")
        if key not in self.messages[side]:
            self.messages[side].add(key)
            self.models[side][str(message.get("model"))] += 1
            if "effort" in record:
                self.effort[side][str(record["effort"])] += 1
            reason = _obj(message.get("diagnostics")).get("cache_miss_reason")
            if isinstance(reason, dict):
                self.cache_miss[str(reason.get("type"))] += 1
                self.missed_input_tokens += int(_number(reason.get("cache_missed_input_tokens")))
        if record.get("error"):
            self.errors[str(record["error"])] += 1
            limit = _obj(record.get("quotaLimits")).get("rateLimitType")
            if isinstance(limit, str):
                self.rate_limit[limit] += 1
        self.thinking_ms += _number(record.get("thinkingDurationMs"))
        content = message.get("content")
        for block in content if isinstance(content, list) else ():
            if isinstance(block, dict) and block.get("type") == "tool_use":
                self._tool_use(block)
        if side == "main":
            self.last_kind = "assistant"

    def _usage_invariant(self, message: dict, side: str) -> None:
        """Count a message whose streamed records disagree on input or cache usage, once.

        Dedup keeps the last record's usage, which is sound only while streaming rewrites
        nothing but output tokens; the drift guard's invariant canary reads this count.
        """
        usage = message.get("usage")
        if not isinstance(usage, dict) or not isinstance(message.get("id"), str):
            return
        group = (side, message["id"])
        signature = tuple(usage.get(k) for k in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
        if self.usage_seen.setdefault(group, signature) != signature and group not in self.usage_split:
            self.usage_split.add(group)
            self.census[self.bucket]["invariant:usage_split"] += 1

    def _tool_use(self, block: dict) -> None:
        # Streaming can repeat a block in a later record; the id counts it once.
        tool_id = block.get("id")
        if isinstance(tool_id, str):
            if tool_id in self.tool_ids:
                return
            self.tool_ids.add(tool_id)
        name = str(block.get("name", "?"))
        self.tools[name] += 1
        tool_input = _obj(block.get("input"))
        path = tool_input.get("file_path") or tool_input.get("notebook_path")
        if name in EDIT_TOOLS and isinstance(path, str):
            self.edits[path] += 1
        if name == "Skill":
            self.skills[str(tool_input.get("skill"))] += 1

    def _user(self, record: dict, side: str, ts: float | None) -> None:
        result = record.get("toolUseResult")
        if isinstance(result, str) and result.startswith("User rejected tool use"):
            self.user_rejected += 1
        if isinstance(record.get("toolDenialKind"), str):
            self.denials[record["toolDenialKind"]] += 1
        text = transcript_reader.user_text(record)
        if text is None:
            return
        if transcript_reader.INTERRUPT_RE.match(text):
            self.interrupts[side] += 1
        if side != "main":
            return
        command = COMMAND_RE.search(text)
        if command and text.startswith(("<command-", "<local-command")):
            self.slash[command.group(1)] += 1
            if command.group(1) == "clear" and self.human_turns == 0 and not self.messages["main"]:
                self.started_with_clear = True
        elif (typed := transcript_reader.typed_text(record)) is not None:
            self._typed_turn(record, typed, ts)

    def _typed_turn(self, record: dict, text: str, ts: float | None) -> None:
        index = self.human_turns
        self.human_turns += 1
        if ts is not None:
            self.human_timestamps.append(ts)
        words = len(text.split())
        if self.last_kind == "assistant" and words <= self.excerpt_words:
            flags = ["short-after-assistant"]
            if CORRECTION_RE.search(text) and not CORRECTION_NEG.search(text):
                flags.append("lexicon-correction")
            if FRUSTRATION_RE.search(text):
                flags.append("frustration")
            self.flagged.append((index, record, text, words, flags))
        self.last_kind = "human"

    def _system(self, record: dict, side: str, _ts: float | None) -> None:
        if side != "main":
            return
        subtype = record.get("subtype")
        if subtype not in SYSTEM_SUBTYPES:
            self.unknown_subtypes[str(subtype)] += 1
        elif subtype == "turn_duration":
            self.active_ms += _number(record.get("durationMs"))
            self.turn_durations += 1
        elif subtype == "stop_hook_summary":
            infos = record.get("hookInfos")
            hooks = [h for h in infos if isinstance(h, dict)] if isinstance(infos, list) else []
            self.stop_hook_ms.append(sum(_number(h.get("durationMs")) for h in hooks))
            self.stop_hook_blocks += bool(record.get("preventedContinuation"))
            self.stop_hook_errors += bool(record.get("hookErrors"))
        elif subtype == "compact_boundary":
            meta = _obj(record.get("compactMetadata"))
            self.compactions.append(
                {"trigger": meta.get("trigger"), "pre_tokens": meta.get("preTokens"), "post_tokens": meta.get("postTokens")}
            )
        elif subtype == "informational":
            content = record.get("content")
            self.usage_limit_notices += isinstance(content, str) and content.startswith("Usage limit reached")

    def _permission_mode(self, record: dict, side: str, _ts: float | None) -> None:
        if side != "main":
            return
        mode = record.get("permissionMode")
        if self.last_permission_mode is not None and mode != self.last_permission_mode:
            self.permission_changes += 1
        self.last_permission_mode = mode
        self.permission_modes[str(mode)] += 1

    def _pr_link(self, record: dict, side: str, _ts: float | None) -> None:
        repo, number = record.get("prRepository"), record.get("prNumber")
        if side == "main" and isinstance(repo, str) and isinstance(number, int):
            self.prs.add((repo, number))

    def _worktree_state(self, record: dict, side: str, _ts: float | None) -> None:
        branch = _obj(record.get("worktreeSession")).get("worktreeBranch")
        if side == "main" and isinstance(branch, str) and branch:
            self.branches.add(branch)

    def _custom_title(self, record: dict, side: str, _ts: float | None) -> None:
        if side == "main" and isinstance(record.get("customTitle"), str):
            self.custom_title = record["customTitle"]

    def _agent_name(self, record: dict, side: str, _ts: float | None) -> None:
        if side == "main" and isinstance(record.get("agentName"), str):
            self.agent_name = record["agentName"]

    def time_block(self) -> dict:
        stamps = sorted(self.timestamps)
        gaps = [later - earlier for earlier, later in zip(stamps, stamps[1:])]
        # The gap before a typed turn: time since the previous activity record.
        human_gaps = []
        for human in self.human_timestamps:
            index = bisect.bisect_left(stamps, human - 0.5)
            if index:
                human_gaps.append(human - stamps[index - 1])
        return {
            "start": _iso(stamps[0]) if stamps else None,
            "end": _iso(stamps[-1]) if stamps else None,
            "wall_clock_s": round(stamps[-1] - stamps[0]) if stamps else 0,
            "active_s": round(self.active_ms / 1000),
            "turn_durations": self.turn_durations,
            "idle_gaps_gt5m": sum(g > 300 for g in gaps),
            "idle_gaps_gt1h": sum(g > 3600 for g in gaps),
            "human_gaps_gt5m": sum(g > 300 for g in human_gaps),
            "human_gaps_gt1h": sum(g > 3600 for g in human_gaps),
            "thinking_ms": round(self.thinking_ms),
        }


def fingerprint(main: Path, subagents: list[Path]) -> dict:
    stat = main.stat()
    with main.open("rb") as handle:
        head = hashlib.sha256(handle.read(HEAD_BYTES)).hexdigest()
    sub_stats = [path.stat() for path in subagents]
    return {
        "main_size": stat.st_size,
        "main_mtime_ns": stat.st_mtime_ns,
        "head_sha256": head,
        "sub_count": len(sub_stats),
        "sub_size": sum(s.st_size for s in sub_stats),
        "sub_mtime_ns": max((s.st_mtime_ns for s in sub_stats), default=0),
    }


def _wsl_relay(path: str) -> bool:
    folded = path.replace("/", "\\").lower()
    return folded.endswith(("\\system32\\bash.exe", "\\sysnative\\bash.exe")) or "\\windowsapps\\" in folded


def resolve_bash(env: dict, platform: str, exists=os.path.isfile) -> str | None:
    """The bash state-key.sh runs under, chosen exactly as hooks/exec-bash.mjs `resolveBash` does."""
    windows = platform == "win32"
    paths = ntpath if windows else posixpath

    def accept(candidate: str | None) -> bool:
        return bool(
            candidate
            and exists(candidate)
            and paths.basename(candidate).lower() in {"bash.exe", "sh.exe", "bash", "sh"}
            and not (windows and _wsl_relay(candidate))
        )

    entries = (env.get("PATH") or env.get("Path") or "").split(";" if windows else ":")
    if windows:
        entries = [e[1:-1] if len(e) > 1 and e[0] == e[-1] == '"' else e for e in entries]
    on_path = [paths.join(e, "bash.exe" if windows else "bash") for e in entries if paths.isabs(e)]
    if not windows:
        candidates = [*on_path, "/bin/bash", "/usr/bin/bash"]
    else:
        if accept(env.get("CLAUDE_CODE_GIT_BASH_PATH")):
            return env["CLAUDE_CODE_GIT_BASH_PATH"]
        local = env.get("LOCALAPPDATA")
        roots = [r for r in (env.get("ProgramFiles"), env.get("ProgramFiles(x86)"), local and paths.join(local, "Programs")) if r]
        git = [paths.join(r, "Git", sub, "bash.exe") for r in roots for sub in ("bin", paths.join("usr", "bin"))]
        candidates = [*git, *on_path]
    return next((c for c in candidates if accept(c)), None)


class RepoIdentity:
    """`state-key.sh --root <cwd>` per distinct cwd, split into (identity, worktree); one warning per cause."""

    def __init__(self) -> None:
        self.bash = resolve_bash(dict(os.environ), sys.platform)
        self.cache: dict[str, tuple[str | None, str | None]] = {}
        self.warned: set[str] = set()

    def _warn_once(self, cause: str, message: str) -> None:
        if cause not in self.warned:
            self.warned.add(cause)
            warn(f"{message}; affected records keep repo_identity null")

    def lookup(self, cwd: str | None) -> tuple[str | None, str | None]:
        if not cwd:
            return None, None
        if cwd not in self.cache:
            self.cache[cwd] = self._derive(cwd)
        return self.cache[cwd]

    def _derive(self, cwd: str) -> tuple[str | None, str | None]:
        if not Path(cwd).is_dir():
            self._warn_once("cwd", "a session's working directory no longer exists")
            return None, None
        if self.bash is None:
            self._warn_once("bash", "no usable bash found for lib/state-key.sh")
            return None, None
        try:
            done = subprocess.run(
                [self.bash, str(STATE_KEY), "--root", cwd], capture_output=True, text=True, timeout=30
            )
        except (OSError, subprocess.SubprocessError) as exc:
            self._warn_once("bash", f"lib/state-key.sh could not run under {self.bash}: {exc}")
            return None, None
        key = done.stdout.strip()
        if done.returncode != 0 or "/" not in key:
            self._warn_once("bash", f"lib/state-key.sh failed under {self.bash} (exit {done.returncode})")
            return None, None
        identity, worktree = key.rsplit("/", 1)
        return identity, worktree


class Scrubber:
    """Redacts every transcript-derived string a record stores, and counts those too long to redact."""

    def __init__(self, redactor: redact.Redactor, excerpt_chars: int) -> None:
        self.redactor = redactor
        self.cap = max(TEXT_CAP_FLOOR, 16 * excerpt_chars)
        self.too_long = 0

    def _fits(self, text: str) -> bool:
        if len(text) <= self.cap:
            return True
        self.too_long += 1
        return False

    def text(self, text: str | None) -> str | None:
        return self.redactor.redact(text) if text is not None and self._fits(text) else None

    def key(self, text: str) -> str:
        return self.redactor.redact(text) if self._fits(text) else TOO_LONG

    def keys(self, counts: Counter) -> dict:
        # Redaction can fold two keys into one, so their counts add up.
        out: Counter = Counter()
        for text, n in counts.items():
            out[self.key(text)] += n
        return dict(out)

    def paths(self, edits: Counter, cwd: str | None) -> dict:
        # Paths are transcript text: none is stored while redaction fails closed, only the count.
        if self.redactor.fail_closed:
            return {SUPPRESSED: sum(edits.values())} if edits else {}
        relative: Counter = Counter()
        for path, n in edits.items():
            relative[_relpath(path, cwd)] += n
        return self.keys(relative)

    def excerpt(self, text: str | None, limit: int | None = None) -> str | None:
        """Redacted, then cut to `limit` (None keeps it whole); None while failing closed or too long."""
        if text is None or self.redactor.fail_closed or not self._fits(text):
            return None
        return self.redactor.excerpt(text, len(text) if limit is None else limit)


def build_record(
    main: Path,
    subagents: list,
    fp: dict,
    *,
    version: str,
    redactor: redact.Redactor,
    identity: RepoIdentity,
    excerpt_chars: int,
    excerpt_words: int,
) -> dict:
    scan = SessionScan(excerpt_words)
    stats: dict[str, int] = {"files": 0}
    for path, side in [(main, "main"), *((s.path, "sub") for s in subagents)]:
        stats["files"] += 1
        for record in transcript_reader.iter_records(path, stats):
            scan.add(record, side)
    repo_identity, worktree = identity.lookup(scan.cwd)
    metas = [s.meta or {} for s in subagents]
    edit_counts = scan.edits.values()
    stop_ms = scan.stop_hook_ms
    suppressed = redactor.fail_closed
    scrub = Scrubber(redactor, excerpt_chars)
    # Repo identity above used the raw cwd; every string below is stored, so each goes through scrub.
    # The dict is built in order, so the closing redaction block sees every scrub call's count.
    return {
        "schema": RECORD_SCHEMA,
        "collector_version": version,
        "excerpt_limits": {"chars": excerpt_chars, "words": excerpt_words},
        "ingested_at": _iso(time.time()),
        "session_id": main.stem,
        "fingerprint": fp,
        "cwd": scrub.text(scan.cwd),
        "repo_identity": repo_identity,
        "worktree": worktree,
        "cc_versions": sorted(scan.versions, key=census.version_key),
        "entrypoints": sorted(scan.entrypoints) or [census.UNKNOWN_ENTRYPOINT],
        "time": scan.time_block(),
        "models": {side: dict(counts) for side, counts in scan.models.items()},
        "effort": {side: dict(counts) for side, counts in scan.effort.items()},
        "tokens": {side: ledger.totals() for side, ledger in scan.ledgers.items()},
        "cache_miss": {"reasons": dict(scan.cache_miss), "missed_input_tokens": scan.missed_input_tokens},
        "rate_limit": {"types": dict(scan.rate_limit), "usage_limit_notices": scan.usage_limit_notices},
        "errors": scrub.keys(scan.errors),
        "tools": {
            "calls": sum(scan.tools.values()),
            "by_name": dict(scan.tools),
            "denials": dict(scan.denials),
            "user_rejected": scan.user_rejected,
            "interrupts": scan.interrupts["main"],
            "interrupts_sub": scan.interrupts["sub"],
        },
        "edits": {
            "files": len(scan.edits),
            "files_ge3": sum(n >= 3 for n in edit_counts),
            "max_one_file": max(edit_counts, default=0),
            "by_relpath": scrub.paths(scan.edits, scan.cwd),
        },
        "subagents": {
            "count": len(subagents),
            "by_type": dict(Counter(str(m.get("agentType")) for m in metas)),
            "by_model": dict(Counter(str(m.get("model")) for m in metas)),
            "by_depth": dict(Counter(str(m.get("spawnDepth")) for m in metas)),
        },
        "stop_hooks": {
            "runs": len(stop_ms),
            "ms_total": round(sum(stop_ms)),
            "ms_p50": _percentile(stop_ms, 0.5),
            "ms_p90": _percentile(stop_ms, 0.9),
            "blocks": scan.stop_hook_blocks,
            "errors": scan.stop_hook_errors,
        },
        "context": {
            "compactions": scan.compactions,
            "compact_commands": scan.slash["compact"],
            "clear_commands": scan.slash["clear"],
            "started_with_clear": scan.started_with_clear,
        },
        "link_keys": {
            # Titles and agent names are typed text, so --excerpt-chars 0 stores neither.
            "custom_title": scrub.excerpt(scan.custom_title) if excerpt_chars else None,
            "agent_name": scrub.excerpt(scan.agent_name) if excerpt_chars else None,
            "first_ts": scan.time_block()["start"],
        },
        "branches": sorted({scrub.key(branch) for branch in scan.branches}),
        "prs": [{"repo": repo, "number": number} for repo, number in sorted({(scrub.key(r), n) for r, n in scan.prs})],
        "permission": {"modes": dict(scan.permission_modes), "changes": scan.permission_changes},
        "commands": {"slash": scrub.keys(scan.slash), "skills_model_invoked": scrub.keys(scan.skills)},
        "human": {
            "turns": scan.human_turns,
            "flagged": [
                {
                    "idx": index,
                    "ts": record.get("timestamp") if isinstance(record.get("timestamp"), str) else None,
                    "uuid": record.get("uuid") if isinstance(record.get("uuid"), str) else None,
                    "words": words,
                    "flags": flags,
                    "excerpt": scrub.excerpt(text, excerpt_chars) if excerpt_chars else None,
                }
                for index, record, text, words, flags in scan.flagged
            ],
        },
        "census": {bucket: dict(counts) for bucket, counts in scan.census.items()},
        "unknown": {"record_types": dict(scan.unknown_types), "system_subtypes": dict(scan.unknown_subtypes)},
        "parse": {
            "files": stats["files"],
            "lines": stats["records"] + stats["bad_lines"] + stats["incomplete"],
            "records": stats["records"],
            "bad_lines": stats["bad_lines"],
            "incomplete": stats["incomplete"],
            "unknown": stats["unknown"],
        },
        "redaction": {
            "rules_version": redactor.version,
            "rules_loaded": redactor.rule_count,
            "rules_skipped": len(redactor.skipped),
            "excerpts_suppressed": suppressed,
            "skipped_too_long": scrub.too_long,
        },
    }


def stored_policy(record: dict) -> tuple:
    """The settings besides the transcript that shaped a record's stored text; None where a field is missing."""
    redaction = _obj(record.get("redaction"))
    return record.get("collector_version"), record.get("excerpt_limits"), redaction.get("excerpts_suppressed")


def load_store(store: Path) -> dict[Path, tuple[dict | None, tuple, float | None]]:
    """(fingerprint, collection policy, session end) of each readable stored record; others are re-ingested."""
    index: dict[Path, tuple[dict | None, tuple, float | None]] = {}
    for path in store.glob("p-*/*.json"):
        try:
            record = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if isinstance(record, dict) and record.get("schema") == RECORD_SCHEMA:
            end = _epoch(_obj(record.get("time")).get("end"))
            index[path] = (record.get("fingerprint"), stored_policy(record), end)
    return index


def cmd_collect(args: argparse.Namespace) -> int:
    started = time.monotonic()
    root = Path(args.projects_root) if args.projects_root else default_projects_root()
    try:
        with os.scandir(root):
            pass
    except OSError:
        return emit("error", f"projects root not readable: {root}", {"projects_root": str(root)}, 2)
    store = store_dir(Path(args.data_dir))
    try:
        store.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        return emit("error", f"data dir not usable: {exc}", {"data_dir": args.data_dir}, 2)
    since = None
    if args.since:
        try:
            since = datetime.strptime(args.since, "%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp()
        except ValueError:
            return emit("error", f"--since is not YYYY-MM-DD: {args.since}", {}, 2)
    cutoff = time.time() - args.retention_days * 86400 if args.retention_days else None
    wanted = set(args.session or ())
    version = collector_version()
    redactor = redact.load_redactor()
    identity = RepoIdentity()
    index = load_store(store)
    # A record stored under other settings is re-ingested, so a lowered excerpt limit reaches old records.
    policy = (version, {"chars": args.excerpt_chars, "words": args.excerpt_words}, redactor.fail_closed)
    scanned = ingested = skipped = expired = orphaned = too_long = 0
    failed: list[dict] = []
    unknown_types: Counter = Counter()
    for main in sorted(root.glob("*/*.jsonl")):
        if ORPHANED in main.stem:
            orphaned += 1
            continue
        if wanted and main.stem not in wanted:
            continue
        try:
            mtime = main.stat().st_mtime
            if since is not None and mtime < since:
                continue
            scanned += 1
            # A file last written before the window cannot hold a session that ended inside it.
            if cutoff is not None and mtime < cutoff:
                expired += 1
                continue
            target = store / project_segment(main.parent.name) / f"{main.stem}.json"
            subagents = list(transcript_reader.iter_subagents(main))
            fp = fingerprint(main, [s.path for s in subagents])
            if not args.force and target in index and index[target][:2] == (fp, policy):
                skipped += 1
                continue
            record = build_record(
                main,
                subagents,
                fp,
                version=version,
                redactor=redactor,
                identity=identity,
                excerpt_chars=args.excerpt_chars,
                excerpt_words=args.excerpt_words,
            )
            end = _epoch(record["time"]["end"])
            if cutoff is not None and end is not None and end < cutoff:
                expired += 1
                continue
            # A concurrent collector holding the target wrote the same session: a skip, not a failure.
            if not census.write_atomic(target, record):
                skipped += 1
                continue
        except OSError as exc:
            failed.append({"session_id": main.stem, "reason": str(exc)})
            continue
        index[target] = (fp, policy, end)
        ingested += 1
        too_long += record["redaction"]["skipped_too_long"]
        unknown_types.update(record["unknown"]["record_types"])
    pruned = 0
    if cutoff is not None:
        for path, (*_, end) in index.items():
            if end is not None and end < cutoff:
                path.unlink(missing_ok=True)
                pruned += 1
    data = {
        "projects_root": str(root),
        "scanned": scanned,
        "ingested": ingested,
        "skipped_unchanged": skipped,
        "skipped_expired": expired,
        "skipped_orphaned": orphaned,
        "failed": failed,
        "pruned": pruned,
        "store_records": sum(1 for _ in store.glob("p-*/*.json")),
        "redaction": {
            "rules_loaded": redactor.rule_count,
            "rules_skipped": len(redactor.skipped),
            "excerpts_suppressed": redactor.fail_closed,
            "skipped_too_long": too_long,
        },
        "unknown_record_types": dict(unknown_types),
        "elapsed_s": round(time.monotonic() - started, 3),
    }
    summary = f"ingested {ingested} of {scanned} sessions"
    if redactor.fail_closed:
        warn(f"redaction rules skipped ({', '.join(sorted(redactor.skipped)) or 'none loaded'}); no excerpts stored")
        return emit("warning", summary + "; excerpts suppressed (redaction degraded)", data, 1)
    if failed:
        return emit("warning", summary + f"; {len(failed)} failed", data, 1)
    return emit("pass", summary, data, 0)


def cmd_census(args: argparse.Namespace) -> int:
    try:
        records, skipped = census.load_records(Path(args.data_dir))
    except OSError as exc:
        return emit("error", str(exc), {"data_dir": args.data_dir}, 2, CENSUS_SCHEMA)
    rows = census.aggregate(records, version=args.version, model=args.model)
    data = {"sessions": len(records), "skipped_records": skipped, "census": rows}
    return emit("pass", f"{len(rows)} (version, model) buckets over {len(records)} sessions", data, 0, CENSUS_SCHEMA)


def cmd_drift(args: argparse.Namespace) -> int:
    try:
        records, skipped = census.load_records(Path(args.data_dir))
        canaries = census.load_canaries(Path(args.canaries))
    except (OSError, ValueError) as exc:
        return emit("error", str(exc), {"data_dir": args.data_dir, "canaries": args.canaries}, 2, DRIFT_SCHEMA)
    data = census.drift(
        records,
        canaries.get("canaries", []),
        min_count=args.min_count,
        versions=args.versions,
        session_floor=args.session_floor,
    )
    data["skipped_records"] = skipped
    found = ", ".join(f"{n} {cls}" for cls, n in data["counts"].items() if n)
    if found:
        return emit("warning", f"drift found: {found}", data, 1, DRIFT_SCHEMA)
    return emit("pass", f"no drift over {len(records)} sessions", data, 0, DRIFT_SCHEMA)


def _positive(value: str) -> int:
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError("must be 1 or more")
    return number


def _non_negative(value: str) -> int:
    number = int(value)
    if number < 0:
        raise argparse.ArgumentTypeError("must be 0 or more")
    return number


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Ingest Claude Code transcripts into the audit-sessions store.")
    sub = parser.add_subparsers(dest="command", required=True)
    collect = sub.add_parser("collect", help="ingest transcripts into the store")
    collect.add_argument("--data-dir", required=True)
    collect.add_argument("--projects-root")
    collect.add_argument("--since", help="only transcripts modified on or after this UTC date (YYYY-MM-DD)")
    collect.add_argument("--session", nargs="+", action="extend", help="only these session ids")
    collect.add_argument("--force", action="store_true", help="re-ingest sessions whose fingerprint is unchanged")
    collect.add_argument("--retention-days", type=_non_negative, default=0, help="0 keeps every record")
    collect.add_argument("--excerpt-chars", type=_non_negative, default=240, help="0 stores no excerpt text")
    collect.add_argument("--excerpt-words", type=_non_negative, default=60)
    collect.set_defaults(func=cmd_collect)
    aggregate = sub.add_parser("census", help="sum stored census rows per (version, model)")
    aggregate.add_argument("--data-dir", required=True)
    aggregate.add_argument("--version", help="only this Claude Code version")
    aggregate.add_argument("--model", help="only this model (`*` for non-assistant records)")
    aggregate.set_defaults(func=cmd_census)
    drift = sub.add_parser("drift", help="classify census changes between Claude Code versions")
    drift.add_argument("--data-dir", required=True)
    drift.add_argument("--min-count", type=_positive, default=census.DEFAULT_MIN_COUNT)
    drift.add_argument("--versions", type=_positive, default=census.DEFAULT_VERSIONS, help="vanish window, in versions")
    drift.add_argument("--session-floor", type=_positive, default=census.DEFAULT_SESSION_FLOOR)
    drift.add_argument("--canaries", default=str(census.BUNDLED_CANARIES))
    drift.set_defaults(func=cmd_drift)
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:
        if exc.code == 0:
            raise
        words = sys.argv[1:] if argv is None else argv
        schema = {"census": CENSUS_SCHEMA, "drift": DRIFT_SCHEMA}.get(words[0] if words else "", SCHEMA)
        return emit("error", "bad arguments", {}, 2, schema)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
