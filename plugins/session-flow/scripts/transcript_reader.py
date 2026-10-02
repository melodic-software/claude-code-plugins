# -*- coding: utf-8 -*-
"""The one reader of Claude Code transcript JSONL for the session-flow scripts.

Public interface:

- `iter_records(path, stats)` streams the JSON object on each line of a transcript file. Malformed
  lines are counted in `stats["bad_lines"]`, never raised.
- `UsageLedger` holds one usage per assistant message: streaming writes one message as several
  records, so usage is keyed by `message.id` (fallback: record `uuid`) and the last record wins.
  Summing per record double-counts tokens.
- `is_typed_turn(record)` is true only for a user record the human typed, as opposed to tool
  results, meta records, slash-command output and injected notices, which outnumber typed turns.

Callers put this directory on `sys.path` and `import transcript_reader`. Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import json
import re
from collections.abc import Iterator
from pathlib import Path

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
INTERRUPT_RE = re.compile(r"^\[Request interrupted by user( for tool use)?\]")
TYPED_PROMPT_SOURCES = {"typed", "queued"}


def iter_records(path: Path, stats: dict[str, int] | None = None) -> Iterator[dict]:
    with Path(path).open(encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                record = None
            if not isinstance(record, dict):
                if stats is not None:
                    stats["bad_lines"] = stats.get("bad_lines", 0) + 1
                continue
            if stats is not None:
                stats["records"] = stats.get("records", 0) + 1
            yield record


def _usage_tokens(usage: dict) -> dict[str, int]:
    creation = usage.get("cache_creation") or {}
    return {
        "input": usage.get("input_tokens") or 0,
        "output": usage.get("output_tokens") or 0,
        "cache_read": usage.get("cache_read_input_tokens") or 0,
        "cache_creation": usage.get("cache_creation_input_tokens") or 0,
        "cache_creation_1h": creation.get("ephemeral_1h_input_tokens") or 0,
        "cache_creation_5m": creation.get("ephemeral_5m_input_tokens") or 0,
    }


class UsageLedger:
    def __init__(self) -> None:
        self._by_message: dict[str, dict[str, int]] = {}

    def add(self, record: dict) -> None:
        message = record.get("message") or {}
        usage = message.get("usage")
        key = message.get("id") or record.get("uuid")
        if not isinstance(usage, dict) or not key:
            return
        self._by_message[key] = _usage_tokens(usage)

    def totals(self) -> dict[str, int]:
        totals = {field: sum(u[field] for u in self._by_message.values()) for field in TOKEN_FIELDS}
        totals["unique_messages"] = len(self._by_message)
        return totals


def _user_text(record: dict) -> str | None:
    content = (record.get("message") or {}).get("content")
    if isinstance(content, list):
        blocks = [b for b in content if isinstance(b, dict)]
        if any(b.get("type") == "tool_result" for b in blocks):
            return None
        content = "\n".join(b.get("text", "") for b in blocks if b.get("type") == "text")
    return content.strip() if isinstance(content, str) else None


def is_typed_turn(record: dict) -> bool:
    if record.get("type") != "user":
        return False
    if record.get("isMeta") or record.get("isCompactSummary") or record.get("isVisibleInTranscriptOnly"):
        return False
    kind = (record.get("origin") or {}).get("kind")
    if kind and kind != "human":
        return False
    source = record.get("promptSource")
    if source and source not in TYPED_PROMPT_SOURCES:
        return False
    text = _user_text(record)
    if not text or INTERRUPT_RE.match(text):
        return False
    return not text.startswith(INJECTED_PREFIXES)
