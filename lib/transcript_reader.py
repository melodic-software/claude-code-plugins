# -*- coding: utf-8 -*-
"""The one reader of Claude Code transcript JSONL for the session-flow scripts.

Public interface:

- `iter_records(path, stats=None)` streams the JSON object on each line of a transcript file, read
  as UTF-8 with undecodable bytes replaced, CRLF or LF. It never raises on content. It adds to the
  integer counters in `stats`: `records` (objects yielded), `bad_lines` (lines that are not a JSON
  object), `incomplete` (an unterminated final line that does not parse: a session still being
  written, not a bad line) and `unknown` (records whose `record_kind` is `unknown`).
  A gzipped file, or one whose text starts with `[`, is a lane leg instead: one JSON array of
  `claude -p --output-format stream-json` messages (the sealed transcript a lane uploads). Each
  object in it is yielded through `stream_record`; an item that is not an object, a top-level value
  that is not an array, or a file that does not decompress or parse counts one `bad_lines` each.
- `stream_record(message)` is a stream-json message with the transcript's names for the fields the
  readers use, added beside the originals: `sessionId` from `session_id`, `toolUseResult` from
  `tool_use_result`, `version` from the init message's `claude_code_version`, `compactMetadata`
  (`trigger`, `preTokens`) from `compact_metadata` (`trigger`, `pre_tokens`), and for a user or
  assistant message `isSidechain`, true when `parent_tool_use_id` is set: a subagent's messages
  arrive inline in the array rather than in a file of their own. A field the message lacks (an
  older CLI writes no `timestamp`) stays absent.
- `decode_line(line, stats=None)` is the record on one transcript line already read as text, else
  None for a blank line or one that is not a JSON object, updating the same `stats` counters as
  `iter_records`, which is built on it. A tailer that reads appended bytes calls it per line; an
  unparsed line without its trailing newline counts as `incomplete`, not `bad_lines`.
- `record_kind(record)` is the record's `type` when it is one of `RECORD_TYPES`, else `unknown`.
  `IGNORED_RECORD_TYPES`, a subset, is known only so drift checks stop reporting it: a caller
  skips such a record before counting anything from it. `STREAM_RECORD_TYPES`, another subset,
  holds the stream-json message types only a lane leg carries; none feeds a metric.
- `UsageLedger` holds one usage per assistant message: streaming writes one message as several
  records, so usage is keyed by `message.id` (fallback: record `uuid`) and the last record wins.
  Summing per record double-counts tokens. `add(record)`, then `totals()` gives `TOKEN_FIELDS`
  plus `unique_messages`. Non-integer counts read as 0.
- `user_text(record)` is a user record's text, stripped, with text blocks joined by newlines; None
  for a tool result or a content shape that carries no text. Injected text is returned as is.
- `typed_text(record)` is the text of a user record the human typed, else None: not a tool
  result, not meta, compact-summary or transcript-only, `origin.kind` absent or `human`,
  `promptSource` absent or in `TYPED_PROMPT_SOURCES` unless `origin.kind` is `human`, not an
  interrupt, and not starting with an `INJECTED_PREFIXES` entry. For an `origin.kind: human` record,
  one leading `<system-reminder>` block is dropped first: Claude Desktop writes the person's prompts
  that way, with `promptSource: sdk`. Injected records outnumber typed turns.
- `is_typed_turn(record)` is `typed_text(record) is not None`.
- `tool_result_id(record)` is the `tool_use_id` of a user record's first tool result, else None;
  `tool_result_text(record)` is that result's text (`toolUseResult` when it is a string, else the
  result block's text), `""` when there is none.
- `permission_event(record)` is the permission outcome a user record carries for one tool call, else
  None: `tool_use_id`, `outcome` (`denied` or `allowed`), the decision's `source` and `reason_type`,
  `denial_kind` (`toolDenialKind`) and, for a denial, `cause` (`classifier`, `hook`, `rule` or
  `user-rejected`), `reason` (the classifier's bracketed category, `unexplained` when it gave none, or
  the first line of a hook's message) and `hook` (the plugin a hook message names, else the leading
  label of the message, else `unattributed`). A hook message's leading `[<command line>]` is dropped.
- `permission_denials(record)` is the `permission_denials` list of a stream-json `result` record
  (headless output, not a session transcript): one dict per denial with `tool_name`, `tool_use_id`,
  `tool_input` (an object, `{}` when absent) and `reason_type` (`decision_reason_type`, or None);
  `[]` for any other record.
- `iter_subagents(main_path)` yields a `Subagent(path, meta)` for each
  `<session>/subagents/agent-*.jsonl` beside `<session>.jsonl`, in name order; `meta` is the
  parsed `agent-*.meta.json` object, or None when it is missing, unreadable or not an object.
  Stream each `path` through `iter_records`.
- `iter_workflow_agents(main_path)` yields a `WorkflowAgent(workflow, path)` for each agent the
  Workflow tool started, `<session>/subagents/workflows/wf_*/agent-*.jsonl`, in path order;
  `workflow` is the `wf_*` directory name. Each workflow directory also holds a `journal.jsonl`,
  whose records carry no timestamps. `iter_subagents` never yields these agents.
- `first_cwd(path)` is the `cwd` of the first record that carries a non-empty string one, else None.
  It stops reading at that record, so a long transcript costs one or two lines.

Callers put this directory on `sys.path` and `import transcript_reader`. Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import gzip
import json
import re
import zlib
from collections.abc import Iterator
from pathlib import Path
from typing import NamedTuple

TOKEN_FIELDS = (
    "input",
    "output",
    "cache_read",
    "cache_creation",
    "cache_creation_1h",
    "cache_creation_5m",
)

INJECTED_PREFIXES = (
    "<local-command-caveat>",
    "<local-command-stdout>",
    "<local-command-stderr>",
    "<command-name>",
    "<command-message>",
    "<bash-input>",
    "<bash-stdout>",
    "<bash-stderr>",
    "<task-notification>",
    "<system-reminder>",
    "Another Claude session sent",
    "[Cross-session idle notice]",
    "[Usage limit",
    "[Earlier usage-limit",
    "Your claude.ai usage limit",
    "(Re-invocation of",
    "Base directory for this skill",
    "Caveat:",
    "<user-prompt-submit-hook>",
)
CLASSIFIER_DENIAL = "denied by the Claude Code auto mode classifier"
CLASSIFIER_REASON_RE = re.compile(r"Reason: \[([^\]\n]{1,80})\]")
UNEXPLAINED_RE = re.compile(r"gave no explanation", re.I)
HOOK_ERROR_RE = re.compile(r"\b[A-Za-z]+:[\w.-]+ hook error: ")
HOOK_PLUGIN_RE = re.compile(r"This hook comes from the ([\w.-]+?)(?:@[\w.-]+)? plugin")
HOOK_COMMAND_RE = re.compile(r"^\[[^\]\n]*\]:?\s*")
HOOK_LABEL_RE = re.compile(r"^([a-z0-9][\w.-]{1,40}): ")
INTERRUPT_RE = re.compile(r"^\[Request interrupted by user( for tool use)?\]")
LEADING_REMINDER_RE = re.compile(r"<system-reminder>.*?</system-reminder>\s*", re.S)
TYPED_PROMPT_SOURCES = {"typed", "queued"}
IGNORED_RECORD_TYPES = frozenset(
    {
        "atis-latch",  # a latched session flag
        "mode",  # session mode, apart from permission-mode
        "bridge-session",  # remote bridge id and sequence number
        "relocated",  # the cwd a session moved to
        "file-history-delta",  # one file backup for checkpoint rewind
        "cost-state",  # running cost and duration totals
        "fork-context-ref",  # pointer to a forked session's context
        "frame-link",  # artifact links and their count
        "artifact-comment-monitor",  # watched-artifact comment state
        "artifact-autoreact-ledger",  # artifact auto-react state
    }
)
STREAM_RECORD_TYPES = frozenset(
    {
        "rate_limit_event",
        "stream_event",
        "tool_progress",
        "tool_use_summary",
        "auth_status",
        "prompt_suggestion",
        "conversation_reset",
    }
)
RECORD_TYPES = IGNORED_RECORD_TYPES | STREAM_RECORD_TYPES | frozenset(
    {
        "ai-title",  # used: `aiTitle`, the generated session title, a predecessor link key
        "user",
        "assistant",
        "system",
        "attachment",
        "progress",
        "queue-operation",
        "last-prompt",
        "custom-title",
        "agent-name",
        "pr-link",
        "worktree-state",
        "permission-mode",
        "file-history-snapshot",
        "result",
    }
)


def record_kind(record: dict) -> str:
    kind = record.get("type")
    return kind if isinstance(kind, str) and kind in RECORD_TYPES else "unknown"


def _init_stats(stats: dict[str, int] | None) -> dict[str, int]:
    counts = stats if stats is not None else {}
    for key in ("records", "bad_lines", "incomplete", "unknown"):
        counts.setdefault(key, 0)
    return counts


def decode_line(line: str, stats: dict[str, int] | None = None) -> dict | None:
    counts = _init_stats(stats)
    if not line.strip():
        return None
    try:
        record = json.loads(line)
    except json.JSONDecodeError:
        record = None
    if not isinstance(record, dict):
        counts["bad_lines" if line.endswith("\n") else "incomplete"] += 1
        return None
    counts["records"] += 1
    if record_kind(record) == "unknown":
        counts["unknown"] += 1
    return record


GZIP_MAGIC = b"\x1f\x8b"


def _first_text_char(path: Path) -> str:
    with Path(path).open(encoding="utf-8", errors="replace") as handle:
        return handle.read(64).lstrip()[:1]


def _stream_array(path: Path, gzipped: bool, counts: dict[str, int]) -> Iterator[dict]:
    try:
        raw = gzip.decompress(path.read_bytes()) if gzipped else path.read_bytes()
        messages = json.loads(raw.decode("utf-8", errors="replace"))
    except (OSError, EOFError, ValueError, zlib.error):
        messages = None
    if not isinstance(messages, list):
        counts["bad_lines"] += 1
        return
    for message in messages:
        if not isinstance(message, dict):
            counts["bad_lines"] += 1
            continue
        counts["records"] += 1
        if record_kind(message) == "unknown":
            counts["unknown"] += 1
        yield stream_record(message)


def stream_record(message: dict) -> dict:
    record = dict(message)
    aliases = {"session_id": "sessionId", "tool_use_result": "toolUseResult"}
    for stream_name, transcript_name in aliases.items():
        if stream_name in message and transcript_name not in message:
            record[transcript_name] = message[stream_name]
    if message.get("type") == "system" and message.get("subtype") == "init" and "claude_code_version" in message:
        record.setdefault("version", message["claude_code_version"])
    compact = message.get("compact_metadata")
    if isinstance(compact, dict) and "compactMetadata" not in message:
        record["compactMetadata"] = {"trigger": compact.get("trigger"), "preTokens": compact.get("pre_tokens")}
    if message.get("type") in {"user", "assistant"} and "isSidechain" not in message:
        record["isSidechain"] = message.get("parent_tool_use_id") is not None
    return record


def iter_records(path: Path, stats: dict[str, int] | None = None) -> Iterator[dict]:
    counts = _init_stats(stats)
    path = Path(path)
    with path.open("rb") as handle:
        gzipped = handle.read(2) == GZIP_MAGIC
    if gzipped or _first_text_char(path) == "[":
        yield from _stream_array(path, gzipped, counts)
        return
    with path.open(encoding="utf-8", errors="replace") as handle:
        for line in handle:
            record = decode_line(line, counts)
            if record is not None:
                yield record


def first_cwd(path: Path) -> str | None:
    records = iter_records(path)
    try:
        for record in records:
            cwd = record.get("cwd")
            if isinstance(cwd, str) and cwd:
                return cwd
        return None
    finally:
        records.close()


class Subagent(NamedTuple):
    path: Path
    meta: dict | None


def iter_subagents(main_path: Path) -> Iterator[Subagent]:
    for path in sorted((Path(main_path).with_suffix("") / "subagents").glob("agent-*.jsonl")):
        try:
            meta = json.loads(path.with_suffix(".meta.json").read_text(encoding="utf-8", errors="replace"))
        except (OSError, ValueError):
            meta = None
        yield Subagent(path, meta if isinstance(meta, dict) else None)


class WorkflowAgent(NamedTuple):
    workflow: str
    path: Path


def iter_workflow_agents(main_path: Path) -> Iterator[WorkflowAgent]:
    workflows = Path(main_path).with_suffix("") / "subagents" / "workflows"
    for path in sorted(workflows.glob("wf_*/agent-*.jsonl")):
        yield WorkflowAgent(path.parent.name, path)


def _obj(value: object) -> dict:
    return value if isinstance(value, dict) else {}


def _str(value: object) -> str | None:
    return value if isinstance(value, str) else None


def _count(value: object) -> int:
    return value if isinstance(value, int) and not isinstance(value, bool) else 0


def _usage_tokens(usage: dict) -> dict[str, int]:
    creation = _obj(usage.get("cache_creation"))
    return {
        "input": _count(usage.get("input_tokens")),
        "output": _count(usage.get("output_tokens")),
        "cache_read": _count(usage.get("cache_read_input_tokens")),
        "cache_creation": _count(usage.get("cache_creation_input_tokens")),
        "cache_creation_1h": _count(creation.get("ephemeral_1h_input_tokens")),
        "cache_creation_5m": _count(creation.get("ephemeral_5m_input_tokens")),
    }


class UsageLedger:
    def __init__(self) -> None:
        self._by_message: dict[str, dict[str, int]] = {}

    def add(self, record: dict) -> None:
        message = _obj(record.get("message"))
        usage = message.get("usage")
        key = next((k for k in (message.get("id"), record.get("uuid")) if isinstance(k, str) and k), None)
        if not isinstance(usage, dict) or key is None:
            return
        self._by_message[key] = _usage_tokens(usage)

    def totals(self) -> dict[str, int]:
        totals = {field: sum(u[field] for u in self._by_message.values()) for field in TOKEN_FIELDS}
        totals["unique_messages"] = len(self._by_message)
        return totals


def user_text(record: dict) -> str | None:
    content = _obj(record.get("message")).get("content")
    if isinstance(content, list):
        blocks = [b for b in content if isinstance(b, dict)]
        if any(b.get("type") == "tool_result" for b in blocks):
            return None
        texts = (b.get("text") for b in blocks if b.get("type") == "text")
        content = "\n".join(t for t in texts if isinstance(t, str))
    return content.strip() if isinstance(content, str) else None


def typed_text(record: dict) -> str | None:
    if record.get("type") != "user":
        return None
    if record.get("isMeta") or record.get("isCompactSummary") or record.get("isVisibleInTranscriptOnly"):
        return None
    kind = _obj(record.get("origin")).get("kind")
    if kind and kind != "human":
        return None
    source = record.get("promptSource")
    if kind != "human" and source and not (isinstance(source, str) and source in TYPED_PROMPT_SOURCES):
        return None
    text = user_text(record)
    if text and kind == "human" and (reminder := LEADING_REMINDER_RE.match(text)):
        text = text[reminder.end() :]
    if not text or INTERRUPT_RE.match(text) or text.startswith(INJECTED_PREFIXES):
        return None
    return text


def is_typed_turn(record: dict) -> bool:
    return typed_text(record) is not None


def tool_result_text(record: dict) -> str:
    result = record.get("toolUseResult")
    if isinstance(result, str):
        return result
    content = _obj(record.get("message")).get("content")
    for block in content if isinstance(content, list) else ():
        if isinstance(block, dict) and block.get("type") == "tool_result":
            inner = block.get("content")
            if isinstance(inner, list):
                inner = "\n".join(b.get("text", "") for b in inner if isinstance(b, dict) and isinstance(b.get("text"), str))
            return inner if isinstance(inner, str) else ""
    return ""


def tool_result_id(record: dict) -> str | None:
    content = _obj(record.get("message")).get("content")
    for block in content if isinstance(content, list) else ():
        if isinstance(block, dict) and block.get("type") == "tool_result" and isinstance(block.get("tool_use_id"), str):
            return block["tool_use_id"]
    return None


def _hook_cause(text: str) -> tuple[str, str]:
    plugin = HOOK_PLUGIN_RE.search(text)
    match = HOOK_ERROR_RE.search(text)
    message = HOOK_COMMAND_RE.sub("", text[match.end() :] if match else text, count=1)
    label = HOOK_LABEL_RE.match(message)
    hook = plugin.group(1) if plugin else label.group(1) if label else "unattributed"
    first = next((line.strip() for line in message.splitlines() if line.strip()), "")
    return hook, first[:160]


def permission_event(record: dict) -> dict | None:
    if record.get("type") != "user":
        return None
    decision = _obj(record.get("permissionDecision"))
    kind = _str(record.get("toolDenialKind"))
    if not decision and kind is None:
        return None
    reason_type = _str(decision.get("reasonType"))
    event = {
        "tool_use_id": tool_result_id(record),
        "outcome": "denied" if kind is not None or decision.get("decision") == "reject" else "allowed",
        "source": _str(decision.get("source")),
        "reason_type": reason_type,
        "denial_kind": kind,
    }
    if event["outcome"] == "allowed":
        return event
    text = tool_result_text(record)
    cause, reason, hook = "rule", reason_type, None
    if kind == "user-rejected" or text.startswith("User rejected"):
        cause, reason = "user-rejected", None
    elif reason_type == "classifier" or kind == "automode-blocked" or (reason_type is None and CLASSIFIER_DENIAL in text):
        category = CLASSIFIER_REASON_RE.search(text)
        cause = "classifier"
        reason = category.group(1) if category else "unexplained" if UNEXPLAINED_RE.search(text) else None
    elif reason_type == "hook" or (reason_type is None and HOOK_ERROR_RE.search(text)):
        cause = "hook"
        hook, reason = _hook_cause(text)
    event.update(cause=cause, reason=reason, hook=hook)
    return event


def permission_denials(record: dict) -> list[dict]:
    if record.get("type") != "result" or not isinstance(record.get("permission_denials"), list):
        return []
    return [
        {
            "tool_name": _str(denial.get("tool_name")),
            "tool_use_id": _str(denial.get("tool_use_id")),
            "tool_input": _obj(denial.get("tool_input")),
            "reason_type": _str(denial.get("decision_reason_type")),
        }
        for denial in record["permission_denials"]
        if isinstance(denial, dict)
    ]
