# -*- coding: utf-8 -*-
"""The one reader of Claude Code transcript JSONL for the session-flow scripts.

Public interface:

- `iter_records(path, stats=None)` streams the JSON object on each line of a transcript file, read
  as UTF-8 with undecodable bytes replaced, CRLF or LF. It never raises on content. It adds to the
  integer counters in `stats`: `records` (objects yielded), `bad_lines` (lines that are not a JSON
  object), `incomplete` (an unterminated final line that does not parse: a session still being
  written, not a bad line) and `unknown` (records whose `record_kind` is `unknown`).
- `record_kind(record)` is the record's `type` when it is one of `RECORD_TYPES`, else `unknown`.
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

Callers put this directory on `sys.path` and `import transcript_reader`. Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import json
import re
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

# Text that arrives as a user record but was not typed by the human.
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
# What Claude Code writes into a denied tool call's result text.
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
RECORD_TYPES = frozenset(
    {
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


def iter_records(path: Path, stats: dict[str, int] | None = None) -> Iterator[dict]:
    counts = stats if stats is not None else {}
    for key in ("records", "bad_lines", "incomplete", "unknown"):
        counts.setdefault(key, 0)
    with Path(path).open(encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                record = None
            if not isinstance(record, dict):
                # Only the last line can lack its newline: a session still being written.
                counts["bad_lines" if line.endswith("\n") else "incomplete"] += 1
                continue
            counts["records"] += 1
            if record_kind(record) == "unknown":
                counts["unknown"] += 1
            yield record


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


def _obj(value: object) -> dict:
    return value if isinstance(value, dict) else {}


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
    kind = record.get("toolDenialKind") if isinstance(record.get("toolDenialKind"), str) else None
    if not decision and kind is None:
        return None
    reason_type = decision.get("reasonType") if isinstance(decision.get("reasonType"), str) else None
    event = {
        "tool_use_id": tool_result_id(record),
        "outcome": "denied" if kind is not None or decision.get("decision") == "reject" else "allowed",
        "source": decision.get("source") if isinstance(decision.get("source"), str) else None,
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
    out = []
    for denial in record["permission_denials"]:
        if not isinstance(denial, dict):
            continue
        reason_type = denial.get("decision_reason_type")
        out.append(
            {
                "tool_name": denial.get("tool_name") if isinstance(denial.get("tool_name"), str) else None,
                "tool_use_id": denial.get("tool_use_id") if isinstance(denial.get("tool_use_id"), str) else None,
                "tool_input": _obj(denial.get("tool_input")),
                "reason_type": reason_type if isinstance(reason_type, str) else None,
            }
        )
    return out
