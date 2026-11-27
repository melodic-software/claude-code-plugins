# GENERATED from lib/session_record.py by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# -*- coding: utf-8 -*-
"""One session's `session-record/v2` record, built from its main transcript and its subagents.

Public interface:

- `fingerprint(main, subagents)` is the size, mtime and head hash a stored record keeps, so a
  collector can skip a session whose files have not changed.
- `build_record(main, subagents, fp, *, version, digest, redactor, identity, excerpt_chars,
  excerpt_words, meter=NO_METER)` reads the transcripts through `transcript_reader` and returns the
  record, calling `meter.check()` before each file and `meter.tick()` after each record. Every
  stored string from a transcript goes through `Scrubber`, which redacts with `redactor` and counts
  text too long to redact.
- `RepoIdentity(on_warn=...).lookup(cwd)` is `(repo_identity, worktree)` from `lib/state-key.sh --root <cwd>`,
  run once per distinct cwd under the bash `resolve_bash` picks; `(None, None)` with one warning per
  cause when the cwd is gone or no bash runs it.
  A Windows-form cwd (`C:\\work\\repo`) read on a POSIX host is looked up at its path under the
  WSL automount root (`wsl_automount_root()`, from /etc/wsl.conf).
- `record_policy(digest, excerpt_chars, excerpt_words, fail_closed)` is what a stored record was
  built under; `stored_policy(record)` reads it back, and `is_unchanged(stored, fp, policy)` is the
  one skip rule: a stored `(fingerprint, policy)` pair equal to the session's current one.
- `provenance(source, hello, declared_platform)` is the `provenance` block a stored record
  carries: the configured source name and the reading host's own `hello` report, except that a
  source read through another platform's mount (`mounted_platform`) is stamped with its declared
  platform and a null `cc_version`; `stamp(record, provenance, status)`
  sets it and the record's `status`, one of `STATUSES`.
- `history_prompts(config_dir, sessions, *, scrub, excerpt_chars, since=None, meter=NO_METER)`
  yields each `HISTORY_SCHEMA` prompt of `history.jsonl` whose session is not in `sessions` and
  whose time is not before `since`, its pasted text restored from `paste-cache/` before `scrub`
  redacts it and cuts it to `excerpt_chars` (0 keeps no text). Its `project` is scrubbed too;
  `project_slug` is the raw project's Claude Code slug, the name its store directory already holds.
- `project_segment(project_dir)` is a project's store directory name.
- `SessionScan` accumulates the records; `census_keys(record)` is one record's census bucket and keys.

Callers put this directory on `sys.path` and `import session_record`; `claude_projects`,
`friction_scan`, `redact`, `transcript_reader` and `transcript_values` sit beside it. Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import bisect
import configparser
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
from collections.abc import Callable, Iterator
from datetime import datetime, timezone
from pathlib import Path
from typing import Protocol

import claude_projects
import friction_scan
import redact
import transcript_reader
from transcript_values import UNKNOWN_ENTRYPOINT, epoch, version_key

RECORD_SCHEMA = "session-record/v2"
HISTORY_SCHEMA = "history-prompt/v1"
STATUSES = ("present", "transcript-gone", "presumed-gone-unverified", "carried-over")
PROVENANCE_FIELDS = ("host", "platform", "config_dir", "cc_version")
STATE_KEY = Path(__file__).resolve().parents[1] / "lib" / "state-key.sh"
# `<session>.orphaned-<timestamp>-<suffix>.jsonl` is a transcript Claude Code set aside, not a second
# session: https://code.claude.com/docs/en/claude-directory#cleaned-up-automatically
ORPHANED = ".orphaned-"
HEAD_BYTES = 4096
WINDOWS_CWD = re.compile(r"^([A-Za-z]):[\\/](.*)$", re.S)
PASTE_REF = "[Pasted text #{id}"
IDLE_CUTOFF_S = 300

COMMAND_RE = re.compile(r"<command-name>/?([^<\s]+)</command-name>")
# Older transcripts carry the legacy MultiEdit tool: https://code.claude.com/docs/en/permissions#read-and-edit
EDIT_TOOLS = frozenset({"Edit", "Write", "MultiEdit", "NotebookEdit"})
AGENT_TOOLS = frozenset({"Agent", "Task"})
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

CENSUS_DEPTH = 3
DYNAMIC_KEY = re.compile(r"^(toolu_|srvtoolu_|call_)|[/\\\s?:]|^[0-9a-f-]{16,}$|^\d+$")
DATA_MAPS = frozenset({"trackedFileBackups", "answers", "wireToolInputs"})
CENSUS_LABEL = re.compile(r"[A-Za-z0-9_.:-]{1,64}")

TEXT_CAP_FLOOR = 4096
TOO_LONG = "<too-long>"
SUPPRESSED = "<suppressed>"


def _obj(value: object) -> dict:
    return value if isinstance(value, dict) else {}


def _number(value: object) -> float:
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) else 0


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
    elif kind == "user" and "toolDenialKind" in record:
        keys.append(f"denial_kind:{_label(record.get('toolDenialKind'))}")
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
        self.stop_hook_wait_ms: list[float] = []
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
        self.branches_sub: set[str] = set()
        self.prs_sub: set[tuple[str, int]] = set()
        self.permission_modes: Counter = Counter()
        self.permission_changes = 0
        self.last_permission_mode: object = None
        self.custom_title: str | None = None
        self.ai_title: str | None = None
        self.agent_name: str | None = None
        self.cwd: str | None = None
        self.human_turns = 0
        self.flagged: list[tuple[int, dict, str, int, list[str]]] = []
        self.last_kind: str | None = None
        self.unknown_types: Counter = Counter()
        self.unknown_subtypes: Counter = Counter()
        self.census: dict[str, Counter] = {}
        self.bucket = ""
        self.usage_peak: dict[tuple[str, str], tuple] = {}
        self.usage_last: dict[tuple[str, str], tuple[str, tuple]] = {}
        self.agent_calls: dict[str, str] = {}
        self.agent_call_bucket: str | None = None
        self.friction = friction_scan.FrictionScan()

    def add(self, record: dict, side: str) -> None:
        self.bucket, keys = census_keys(record)
        self.census.setdefault(self.bucket, Counter()).update(keys)
        kind = transcript_reader.record_kind(record)
        if kind == "unknown":
            raw = record.get("type")
            self.unknown_types[raw if isinstance(raw, str) else "<none>"] += 1
            return
        if kind in transcript_reader.IGNORED_RECORD_TYPES:
            return
        ts = None
        if side == "main":
            ts = epoch(record.get("timestamp"))
            if ts is not None and kind in ("user", "assistant", "system"):
                self.timestamps.append(ts)
            if self.cwd is None and isinstance(record.get("cwd"), str):
                self.cwd = record["cwd"]
            for field, values in (("version", self.versions), ("gitBranch", self.branches)):
                if isinstance(record.get(field), str) and record[field]:
                    values.add(record[field])
            if isinstance(record.get("entrypoint"), str) and record["entrypoint"]:
                self.entrypoints.add(_label(record["entrypoint"]))
        elif isinstance(record.get("gitBranch"), str) and record["gitBranch"]:
            self.branches_sub.add(record["gitBranch"])
        self.friction.add(record)
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
        """Track each streamed message's peak and last input and cache usage for `usage_regressions`."""
        usage = message.get("usage")
        if not isinstance(usage, dict) or not isinstance(message.get("id"), str):
            return
        group = (side, message["id"])
        values = tuple(_number(usage.get(k)) for k in ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"))
        self.usage_peak[group] = tuple(map(max, self.usage_peak.get(group, values), values))
        self.usage_last[group] = (self.bucket, values)

    def usage_regressions(self) -> None:
        """Count each message whose last record is below an earlier one on input or cache usage.

        Dedup keeps the last record's usage. Streaming may raise input and cache counts on later
        records, since the API's message_delta usage is cumulative, so the last record is right
        only while no earlier one exceeds it; the drift guard's invariant canary reads this count.
        """
        for group, (bucket, values) in self.usage_last.items():
            if any(value < peak for value, peak in zip(values, self.usage_peak[group])):
                self.census[bucket]["invariant:usage_regress"] += 1

    def subagent_gap(self, subagent_files: int) -> None:
        """Count the session once when an Agent or Task call returned without error but no subagent file exists.

        A rejected, denied or failed call writes no file, so only a call whose tool_result is not
        an error counts. `subagents.count` counts files; the drift guard's invariant canary reads
        this count.
        """
        if self.agent_call_bucket is not None and not subagent_files:
            self.census[self.agent_call_bucket]["invariant:subagent_files_missing"] += 1

    def _tool_use(self, block: dict) -> None:
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
        if name in AGENT_TOOLS and isinstance(tool_id, str):
            self.agent_calls[tool_id] = self.bucket

    def _user(self, record: dict, side: str, ts: float | None) -> None:
        content = _obj(record.get("message")).get("content")
        for block in content if isinstance(content, list) else ():
            if isinstance(block, dict) and block.get("type") == "tool_result" and not block.get("is_error"):
                bucket = self.agent_calls.pop(str(block.get("tool_use_id")), None)
                self.agent_call_bucket = bucket or self.agent_call_bucket
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
        correction = bool(CORRECTION_RE.search(text)) and not CORRECTION_NEG.search(text)
        self.friction.typed_turn(text, ts, correction and words <= self.excerpt_words)
        if self.last_kind == "assistant" and words <= self.excerpt_words:
            flags = ["short-after-assistant"]
            if correction:
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
            durations = [_number(h.get("durationMs")) for h in hooks]
            total, wait = sum(durations), max(durations, default=0)
            self.stop_hook_ms.append(total)
            self.stop_hook_wait_ms.append(wait)
            if wait > total:
                self.census[self.bucket]["invariant:stop_wait_over_sum"] += 1
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
        if isinstance(repo, str) and isinstance(number, int):
            (self.prs if side == "main" else self.prs_sub).add((repo, number))

    def _worktree_state(self, record: dict, side: str, _ts: float | None) -> None:
        branch = _obj(record.get("worktreeSession")).get("worktreeBranch")
        if side == "main" and isinstance(branch, str) and branch:
            self.branches.add(branch)

    def _custom_title(self, record: dict, side: str, _ts: float | None) -> None:
        if side == "main" and isinstance(record.get("customTitle"), str):
            self.custom_title = record["customTitle"]

    def _ai_title(self, record: dict, side: str, _ts: float | None) -> None:
        if side == "main" and isinstance(record.get("aiTitle"), str) and record["aiTitle"]:
            self.ai_title = record["aiTitle"]

    def _agent_name(self, record: dict, side: str, _ts: float | None) -> None:
        if side == "main" and isinstance(record.get("agentName"), str):
            self.agent_name = record["agentName"]

    def time_block(self) -> dict:
        block = self._time_block()
        if block["active_gap_s"] > block["wall_clock_s"] + 1 and self.bucket in self.census:
            self.census[self.bucket]["invariant:active_over_wall"] += 1
        return block

    def _time_block(self) -> dict:
        stamps = sorted(self.timestamps)
        gaps = [later - earlier for earlier, later in zip(stamps, stamps[1:])]
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
            "active_gap_s": round(sum(min(g, IDLE_CUTOFF_S) for g in gaps)),
            "turn_durations": self.turn_durations,
            "idle_gaps_gt5m": sum(g > IDLE_CUTOFF_S for g in gaps),
            "idle_gaps_gt1h": sum(g > 3600 for g in gaps),
            "human_gaps_gt5m": sum(g > IDLE_CUTOFF_S for g in human_gaps),
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


def wsl_automount_root(conf: str = "/etc/wsl.conf") -> str:
    """The Windows drives' mount root inside WSL: `[automount] root` in /etc/wsl.conf, else /mnt/."""
    parser = configparser.ConfigParser()
    try:
        parser.read(conf, encoding="utf-8")
        root = parser.get("automount", "root", fallback="/mnt/")
    except (configparser.Error, UnicodeDecodeError):
        root = "/mnt/"
    return root.strip().strip("\"'") or "/mnt/"


class RepoIdentity:
    """`state-key.sh --root <cwd>` per distinct cwd, split into (identity, worktree); one warning per cause.

    With `script`, the state-key.sh text is run through `bash -s` instead of the file beside this
    module, so a host that holds only the shipped text writes nothing to derive the key. `on_warn`
    receives each warning.
    """

    def __init__(
        self, *, on_warn: Callable[[str], None], script: str | None = None, automount_root: str | None = None
    ) -> None:
        self.bash = resolve_bash(dict(os.environ), sys.platform)
        self.script = script
        self.on_warn = on_warn
        self.automount_root = automount_root
        self.cache: dict[str, tuple[str | None, str | None]] = {}
        self.warned: set[str] = set()

    def _warn_once(self, cause: str, message: str) -> None:
        if cause not in self.warned:
            self.warned.add(cause)
            self.on_warn(f"{message}; affected records keep repo_identity null")

    def lookup(self, cwd: str | None) -> tuple[str | None, str | None]:
        if not cwd:
            return None, None
        if cwd not in self.cache:
            self.cache[cwd] = self._derive(cwd)
        return self.cache[cwd]

    def local_path(self, cwd: str) -> str:
        """`cwd` as this host reaches it: a Windows-form cwd on a POSIX host maps under the automount root."""
        match = WINDOWS_CWD.match(cwd) if os.name == "posix" else None
        if match is None:
            return cwd
        if self.automount_root is None:
            self.automount_root = wsl_automount_root()
        drive, rest = match.groups()
        return posixpath.join(self.automount_root, drive.lower(), *[part for part in re.split(r"[\\/]", rest) if part])

    def _derive(self, cwd: str) -> tuple[str | None, str | None]:
        cwd = self.local_path(cwd)
        if not Path(cwd).is_dir():
            self._warn_once("cwd", "a session's working directory no longer exists")
            return None, None
        if self.bash is None:
            self._warn_once("bash", "no usable bash found for lib/state-key.sh")
            return None, None
        try:
            argv = [self.bash, str(STATE_KEY)] if self.script is None else [self.bash, "-s", "--"]
            done = subprocess.run(
                [*argv, "--root", cwd], input=self.script, capture_output=True, text=True, timeout=30
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
        out: Counter = Counter()
        for text, n in counts.items():
            out[self.key(text)] += n
        return dict(out)

    def paths(self, edits: Counter, cwd: str | None) -> dict:
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


def record_policy(digest: str, excerpt_chars: int, excerpt_words: int, fail_closed: bool) -> dict:
    return {"digest": digest, "excerpt_limits": {"chars": excerpt_chars, "words": excerpt_words}, "fail_closed": fail_closed}


def stored_policy(record: dict) -> dict:
    return {
        "digest": record.get("collector_digest"),
        "excerpt_limits": record.get("excerpt_limits"),
        "fail_closed": _obj(record.get("redaction")).get("excerpts_suppressed"),
    }


def is_unchanged(stored: tuple[object, object] | None, fp: dict, policy: dict) -> bool:
    """True when the stored `(fingerprint, policy)` pair matches the session's current one."""
    return stored is not None and tuple(stored) == (fp, policy)


class Meter(Protocol):
    """A reader's limits: `check()` before each file, `tick()` after each record; either may raise to stop the build."""

    def check(self) -> None: ...

    def tick(self) -> None: ...


class _NoMeter:
    def check(self) -> None:
        pass

    def tick(self) -> None:
        pass


NO_METER: Meter = _NoMeter()


def project_segment(project_dir: str) -> str:
    return "p-" + hashlib.sha256(project_dir.encode("utf-8")).hexdigest()[:12]


def provenance(source: str, hello: dict, declared_platform: str | None = None) -> dict:
    """The source name and the reader's own report, except for a source read through another platform's mount.

    When the reader found the configuration directory under its automount root
    (`hello["mounted_platform"]`) and that is the source's declared platform, the declared platform
    is stamped and `cc_version` is null: the reader cannot ask the other platform's Claude Code, and
    each record keeps the versions its own transcript lines carry.
    """
    stamped = {"source": source, **{key: hello.get(key) for key in PROVENANCE_FIELDS}}
    mounted = hello.get("mounted_platform")
    if declared_platform is not None and declared_platform != hello.get("platform") and mounted == declared_platform:
        stamped.update(platform=declared_platform, cc_version=None)
    return stamped


def mounted_platform(config_dir: Path, reader_platform: str, automount_root: str | None = None) -> str | None:
    """`windows` when a WSL reader finds `config_dir` under its Windows drives' automount root, else None."""
    if reader_platform != "wsl":
        return None
    try:
        relative = Path(config_dir).resolve().relative_to(Path(automount_root or wsl_automount_root()).resolve())
    except (OSError, ValueError):
        return None
    return "windows" if relative.parts else None


def stamp(record: dict, provenance: dict, status: str) -> dict:
    if status not in STATUSES:
        raise ValueError(f"status {status!r} is not one of {', '.join(STATUSES)}")
    return {**record, "schema": record.get("schema", RECORD_SCHEMA), "provenance": provenance, "status": status}


def _restore_pastes(text: str, pastes: object, paste_dir: Path) -> tuple[str, int, int]:
    """`text` with each text paste's placeholder replaced by its content; (text, restored, missing)."""
    restored = missing = 0
    for paste in pastes.values() if isinstance(pastes, dict) else ():
        if not isinstance(paste, dict) or paste.get("type", "text") != "text":
            continue
        body = paste.get("content")
        digest = paste.get("contentHash")
        if not isinstance(body, str) and isinstance(digest, str) and re.fullmatch(r"[0-9A-Za-z_-]{1,128}", digest):
            try:
                body = (paste_dir / f"{digest}.txt").read_text(encoding="utf-8", errors="replace")
            except OSError:
                body = None
        reference = re.compile(re.escape(PASTE_REF.format(id=paste.get("id"))) + r"[^\]]*\]")
        if not isinstance(body, str) or not reference.search(text):
            missing += 1
            continue
        text = reference.sub(lambda _match, body=body: body, text, count=1)
        restored += 1
    return text, restored, missing


def history_prompts(
    config_dir: Path,
    sessions: set[str],
    *,
    scrub: Scrubber,
    excerpt_chars: int,
    since: float | None = None,
    meter: Meter = NO_METER,
) -> Iterator[dict]:
    try:
        handle = (config_dir / "history.jsonl").open(encoding="utf-8", errors="replace")
    except OSError:
        return
    with handle:
        for line in handle:
            meter.tick()
            entry = transcript_reader.decode_line(line)
            session_id = entry.get("sessionId") if entry else None
            stamp_ms = entry.get("timestamp") if entry else None
            if not isinstance(session_id, str) or session_id in sessions or not isinstance(stamp_ms, (int, float)):
                continue
            ts = stamp_ms / 1000
            if since is not None and ts < since:
                continue
            display = entry.get("display") if isinstance(entry.get("display"), str) else ""
            text, restored, missing = _restore_pastes(display, entry.get("pastedContents"), config_dir / "paste-cache")
            key = hashlib.sha256(json.dumps([session_id, stamp_ms, display]).encode("utf-8")).hexdigest()[:16]
            project = entry.get("project")
            yield {
                "schema": HISTORY_SCHEMA,
                "key": key,
                "session_id": session_id,
                "project": scrub.text(project) if isinstance(project, str) else None,
                "project_slug": claude_projects.encode_project_slug(project) if isinstance(project, str) else None,
                "time": {"start": _iso(ts), "end": _iso(ts)},
                "excerpt": scrub.excerpt(text.strip(), excerpt_chars) if excerpt_chars else None,
                "pastes": {"restored": restored, "missing": missing},
            }


def build_record(
    main: Path,
    subagents: list,
    fp: dict,
    *,
    version: str,
    digest: str,
    redactor: redact.Redactor,
    identity: RepoIdentity,
    excerpt_chars: int,
    excerpt_words: int,
    meter: Meter = NO_METER,
) -> dict:
    scan = SessionScan(excerpt_words)
    stats: dict[str, int] = {"files": 0}
    for path, side, meta in [(main, "main", None), *((s.path, "sub", s.meta) for s in subagents)]:
        meter.check()
        stats["files"] += 1
        agent = (meta or {}).get("agentType")
        scan.friction.start_file(side, agent if isinstance(agent, str) else None)
        for record in transcript_reader.iter_records(path, stats):
            meter.tick()
            scan.add(record, side)
    repo_identity, worktree = identity.lookup(scan.cwd)
    metas = [s.meta or {} for s in subagents]
    edit_counts = scan.edits.values()
    stop_ms = scan.stop_hook_ms
    wait_ms = scan.stop_hook_wait_ms
    scrub = Scrubber(redactor, excerpt_chars)
    time_block = scan.time_block()
    scan.usage_regressions()
    scan.subagent_gap(len(subagents))
    return {
        "schema": RECORD_SCHEMA,
        "collector_version": version,
        "collector_digest": digest,
        "excerpt_limits": {"chars": excerpt_chars, "words": excerpt_words},
        "ingested_at": _iso(time.time()),
        "session_id": main.stem,
        "fingerprint": fp,
        "cwd": scrub.text(scan.cwd),
        "repo_identity": repo_identity,
        "worktree": worktree,
        "cc_versions": sorted(scan.versions, key=version_key),
        "entrypoints": sorted(scan.entrypoints) or [UNKNOWN_ENTRYPOINT],
        "time": time_block,
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
            "wait_ms_total": round(sum(wait_ms)),
            "wait_ms_p50": _percentile(wait_ms, 0.5),
            "wait_ms_p90": _percentile(wait_ms, 0.9),
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
            "custom_title": scrub.excerpt(scan.custom_title) if excerpt_chars else None,
            "ai_title": scrub.excerpt(scan.ai_title) if excerpt_chars else None,
            "agent_name": scrub.excerpt(scan.agent_name) if excerpt_chars else None,
            "first_ts": time_block["start"],
        },
        "branches": sorted({scrub.key(branch) for branch in scan.branches}),
        "prs": [{"repo": repo, "number": number} for repo, number in sorted({(scrub.key(r), n) for r, n in scan.prs})],
        "branches_sub": sorted({scrub.key(branch) for branch in scan.branches_sub}),
        "prs_sub": [{"repo": repo, "number": number} for repo, number in sorted({(scrub.key(r), n) for r, n in scan.prs_sub})],
        "permission": {"modes": dict(scan.permission_modes), "changes": scan.permission_changes},
        "friction": scan.friction.block(scrub, excerpt_chars),
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
            "excerpts_suppressed": redactor.fail_closed,
            "skipped_too_long": scrub.too_long,
        },
    }
