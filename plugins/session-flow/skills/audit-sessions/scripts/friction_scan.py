# -*- coding: utf-8 -*-
"""Per-event friction records for one session, built while collect.py scans it.

`FrictionScan` sees every record collect.py reads, main transcript first, then each subagent, and
keeps one event per friction moment:

- `denied`: a tool call refused by the classifier, a hook, a permission rule, or the person
  (`cause`); a stream-json `result` record's `permission_denials` count once per tool call.
- `prompt-approved`: a call the person approved at a permission prompt.
- `agent-ask`: the agent asked the person something (an `AskUserQuestion` call, or a turn whose last
  text asks), with the person's `reply` classed `approve`, `correction`, `rejected` or `other`.
- `handoff`: the agent handed a step to the person (a command to run, text to paste), with `reply`.
- `user-command`: the person ran a `!` shell command.
- `correction` and `approve-reply`: a short typed turn of that class that answered no detected ask.
- `interrupt`: the person interrupted a turn.

The ask, hand-off and approve patterns are English heuristics: high precision, low recall. Events
past `EVENT_CAP` per session are counted in `events_dropped`; `counts` always covers every event.
Secondary performance signals are counts in `perf`. Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import posixpath
import re
from collections import Counter
from datetime import datetime, timezone

import census
import transcript_reader

EVENT_CAP = 200
TOOL_WAIT_S = 300
ASK_TAIL_CHARS = 600

ASK_RE = re.compile(
    r"\b(shall i|should i|do you want me to|want me to|would you like me to|ok(ay)? to (proceed|continue|go ahead)|"
    r"can i (proceed|go ahead)|which (option|one) (do you|would you|should)|(pick|choose) (one|between|an option)|"
    r"let me know (if|which|whether|how)|reply ['\"“`]|say ['\"“`]?go)\b",
    re.I,
)
HANDOFF_RE = re.compile(
    r"\b((you('ll| will)? )?need to (run|paste|apply|approve|merge|click)|please (run|paste|apply|approve|merge|click)|"
    r"run (this|these|it|the (following|command|script)) yourself|your step\b|paste (this|it|the following) into|"
    r"(in|from) your (own )?(terminal|shell)|on your side|you('ll| will)? have to (run|do)|waiting on you|"
    r"needs? your (approval|review|action))"
    r"|`!\s?[\w./~-]",
    re.I,
)
APPROVE_RE = re.compile(
    r"^\W*(y(es|ep|eah)?|sure|ok(ay)?|approved?|lgtm|sounds good|do it|go( ahead| for it)?|proceed|continue|"
    r"keep going)\b|\b(go(ing)?|went) with (the |your |my )?recommend\w*|\b(as )?recommended\b",
    re.I,
)
POLL_RE = re.compile(r"\bsleep\s+\d|\buntil\b.*\bdo\b|\bwhile\b.*\bdo\b|--watch\b|\bwatch\s", re.S)
CI_WAIT_RE = re.compile(r"\bgh\s+(run\s+watch|pr\s+checks\b.*--watch)|\bglab\s+ci\s+status\b.*--live", re.S)
CONFLICT_RE = re.compile(r"^CONFLICT \(|Automatic merge failed", re.M)
PERF_COUNTS = ("tool_waits_gt5m", "polling_calls", "ci_wait_calls", "merge_conflicts")
FILE_TOOLS = frozenset({"Edit", "Write", "MultiEdit", "NotebookEdit", "Read"})
SHELL_TOOLS = frozenset({"Bash", "PowerShell"})
SUBCOMMAND = re.compile(r"[a-z][a-z0-9-]{0,30}")
GIT_ARG_FLAGS = frozenset({"-C", "-c"})


def _epoch(value: object) -> float | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return (parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)).timestamp()


def command_shape(command: str) -> tuple[str, list[str]]:
    """`<program>[ <subcommand>[ <subcommand>]]` of a shell command, and the shape flags that take a
    command off a plain-prefix rule match: cd-prefix, env-prefix, compound, redirect, heredoc,
    substitution, multiline."""
    text = command.strip()
    flags = []
    if "\n" in text:
        flags.append("multiline")
    if "<<" in text:
        flags.append("heredoc")
    if "$(" in text or "`" in text:
        flags.append("substitution")
    head = text.splitlines()[0] if text else ""
    if re.match(r"cd\s+\S+\s*(&&|;)", head):
        flags.append("cd-prefix")
        head = re.sub(r"^cd\s+\S+\s*(&&|;)\s*", "", head)
    if re.match(r"([A-Za-z_]\w*=\S*\s+)+", head):
        flags.append("env-prefix")
        head = re.sub(r"^([A-Za-z_]\w*=\S*\s+)+", "", head)
    if re.search(r"&&|\|\||;|\|", head):
        flags.append("compound")
    if re.search(r"(^|[^<>&0-9-])>{1,2}\s*[^&>\s]", head):
        flags.append("redirect")
    words = head.split()
    if not words:
        return "", flags
    program = posixpath.basename(words[0].replace("\\", "/"))
    parts = [program]
    rest = iter(words[1:])
    for word in rest:
        if program == "git" and word in GIT_ARG_FLAGS:
            next(rest, None)
            continue
        if len(parts) == 3 or not SUBCOMMAND.fullmatch(word):
            break
        parts.append(word)
    return " ".join(parts), flags


def tool_shape(name: str, tool_input: dict, cwd: str | None) -> tuple[str | None, list[str], str | None]:
    """(shape, flags, target text) of one tool call; the target is what an excerpt may show."""
    if name in SHELL_TOOLS and isinstance(tool_input.get("command"), str):
        shape, flags = command_shape(tool_input["command"])
        return shape, flags, tool_input["command"].strip().splitlines()[0] if tool_input["command"].strip() else None
    path = tool_input.get("file_path") or tool_input.get("notebook_path") or tool_input.get("path")
    if name in FILE_TOOLS and isinstance(path, str):
        norm = path.replace("\\", "/")
        flags = ["claude-config"] if "/.claude/" in f"/{norm}" or norm.endswith("CLAUDE.md") else []
        if cwd and not norm.startswith(cwd.replace("\\", "/").rstrip("/") + "/"):
            flags.append("outside-cwd")
        ext = posixpath.splitext(norm)[1] or posixpath.basename(norm)
        return f"{name} {ext}", flags, path
    for key in ("subagent_type", "skill", "url"):
        value = tool_input.get(key)
        if isinstance(value, str) and value:
            if key == "url":
                value = re.sub(r"^\w+://([^/]+).*$", r"\1", value)
            return f"{name} {value}", [], None
    return name, [], None


def event_key(event: dict) -> str:
    """`kind[/cause][/hook][/reason][/reply]`, the aggregation key of one event; the reason is cut to 100 characters."""
    parts = [event.get("kind"), event.get("cause"), event.get("hook"), (event.get("reason") or "")[:100], event.get("reply")]
    return "/".join(str(p) for p in parts if p)


def _matched_line(text: str, match: re.Match) -> str:
    start = text.rfind("\n", 0, match.start()) + 1
    end = text.find("\n", match.end())
    return text[start : end if end != -1 else len(text)].strip()


class FrictionScan:
    def __init__(self, cwd_hint: str | None = None) -> None:
        self.events: list[dict] = []
        self.counts: Counter[tuple[str, str]] = Counter()
        self.dropped = 0
        self.calls: dict[str, tuple[str, dict, float | None, str]] = {}
        self.denied_ids: set[str] = set()
        self.side = "main"
        self.agent: str | None = None
        self.headless = False
        self.cwd = cwd_hint
        self.last_text: str | None = None
        self.perf = Counter(dict.fromkeys(PERF_COUNTS, 0))
        self.max_tool_wait_s = 0.0

    def start_file(self, side: str, agent: str | None) -> None:
        self.side, self.agent = side, agent

    def _event(self, kind: str, ts: float | None, **fields) -> dict:
        event = {
            "ts": datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ") if ts else None,
            "side": self.side,
            "agent": self.agent,
            "kind": kind,
            "no_prompt_host": self.headless,
            **fields,
        }
        self.counts[(self.side, event_key(event))] += 1
        if len(self.events) < EVENT_CAP:
            self.events.append(event)
        else:
            self.dropped += 1
        return event

    def add(self, record: dict) -> None:
        if self.cwd is None and isinstance(record.get("cwd"), str):
            self.cwd = record["cwd"]
        if record.get("entrypoint") in census.AUTOMATED_ENTRYPOINTS:
            self.headless = True
        ts = _epoch(record.get("timestamp"))
        kind = record.get("type")
        if kind == "assistant":
            self._assistant(record, ts)
        elif kind == "user":
            self._user(record, ts)
        elif kind == "result":
            for denial in transcript_reader.permission_denials(record):
                if denial["tool_use_id"] in self.denied_ids:
                    continue
                cause = denial["reason_type"] if denial["reason_type"] in ("classifier", "hook") else "rule"
                shape, flags, target = tool_shape(denial["tool_name"] or "?", denial["tool_input"], self.cwd)
                self._event(
                    "denied", ts, tool=denial["tool_name"], shape=shape, flags=flags, target=target,
                    cause=cause, reason=denial["reason_type"], hook=None, source="result",
                )

    def _assistant(self, record: dict, ts: float | None) -> None:
        content = record.get("message", {}).get("content") if isinstance(record.get("message"), dict) else None
        for block in content if isinstance(content, list) else ():
            if not isinstance(block, dict):
                continue
            if block.get("type") == "text" and isinstance(block.get("text"), str) and block["text"].strip():
                self.last_text = block["text"]
            elif block.get("type") == "tool_use" and isinstance(block.get("id"), str):
                self.last_text = None
                name = str(block.get("name", "?"))
                tool_input = block.get("input") if isinstance(block.get("input"), dict) else {}
                self.calls.setdefault(block["id"], (name, tool_input, ts, self.side))
                command = tool_input.get("command") if name in SHELL_TOOLS else None
                if isinstance(command, str):
                    self.perf["ci_wait_calls"] += bool(CI_WAIT_RE.search(command))
                    self.perf["polling_calls"] += bool(POLL_RE.search(command)) and not CI_WAIT_RE.search(command)
                if name == "Monitor":
                    self.perf["polling_calls"] += 1

    def _user(self, record: dict, ts: float | None) -> None:
        use_id = transcript_reader.tool_result_id(record)
        if use_id is not None:
            self._tool_result(record, use_id, ts)
            return
        text = transcript_reader.user_text(record)
        if text is None:
            return
        if transcript_reader.INTERRUPT_RE.match(text):
            self._event("interrupt", ts)
            return
        if self.side != "main":
            return
        if text.startswith("<bash-input>"):
            command = re.sub(r"</?bash-input>", "", text).strip()
            shape, flags = command_shape(command)
            self._event("user-command", ts, shape=shape, flags=flags, target=command.splitlines()[0] if command else None)

    def typed_turn(self, text: str, ts: float | None, correction: bool) -> None:
        """Called by collect.py for each typed turn of the main transcript, with its correction flag."""
        reply = "correction" if correction else "approve" if len(text.split()) <= 60 and APPROVE_RE.search(text) else "other"
        asked = self.last_text
        self.last_text = None
        tail = asked[-ASK_TAIL_CHARS:] if asked else ""
        handoff = HANDOFF_RE.search(tail)
        ask = ASK_RE.search(tail)
        if handoff:
            self._event("handoff", ts, reply=reply, target=_matched_line(tail, handoff))
        elif ask and ("?" in tail or re.search(r"let me know|reply", tail, re.I)):
            self._event("agent-ask", ts, reply=reply, target=_matched_line(tail, ask))
        elif reply == "correction":
            self._event("correction", ts, target=text)
        elif reply == "approve":
            self._event("approve-reply", ts, target=text)

    def _tool_result(self, record: dict, use_id: str, ts: float | None) -> None:
        name, tool_input, started, _side = self.calls.get(use_id, ("?", {}, None, self.side))
        if started is not None and ts is not None and ts - started > 0:
            wait = ts - started
            self.max_tool_wait_s = max(self.max_tool_wait_s, wait)
            self.perf["tool_waits_gt5m"] += wait > TOOL_WAIT_S
        text = transcript_reader.tool_result_text(record)
        if CONFLICT_RE.search(text[:20000]):
            self.perf["merge_conflicts"] += 1
        permission = transcript_reader.permission_event(record)
        if name == "AskUserQuestion":
            reply = "rejected" if permission and permission["outcome"] == "denied" else (
                "approve" if "(Recommended)" in text else "other"
            )
            self._event("agent-ask", ts, tool=name, reply=reply)
            return
        if permission is None:
            return
        shape, flags, target = tool_shape(name, tool_input, self.cwd)
        if permission["outcome"] == "denied":
            self.denied_ids.add(use_id)
            self._event(
                "denied", ts, tool=name, shape=shape, flags=flags, target=target,
                cause=permission["cause"], reason=permission["reason"], hook=permission["hook"],
                source=permission["source"], reason_type=permission["reason_type"],
            )
        elif (permission["source"] or "").startswith("user"):
            self._event("prompt-approved", ts, tool=name, shape=shape, flags=flags, target=target, source=permission["source"])

    def block(self, scrub, excerpt_chars: int) -> dict:
        """The record's `friction` block; every transcript string goes through `scrub` (collect.Scrubber)."""
        events = []
        for event in self.events:
            stored = {k: v for k, v in event.items() if k != "target"}
            for key in ("reason", "hook", "shape"):
                if isinstance(stored.get(key), str):
                    stored[key] = scrub.key(stored[key])
            target = event.get("target")
            stored["excerpt"] = scrub.excerpt(target, excerpt_chars) if excerpt_chars and target else None
            events.append(stored)
        return {
            "events": events,
            "events_dropped": self.dropped,
            "counts": {
                side: scrub.keys(Counter({key: n for (s, key), n in self.counts.items() if s == side}))
                for side in ("main", "sub")
            },
            "perf": {**{k: int(v) for k, v in self.perf.items()}, "max_tool_wait_s": round(self.max_tool_wait_s)},
        }
