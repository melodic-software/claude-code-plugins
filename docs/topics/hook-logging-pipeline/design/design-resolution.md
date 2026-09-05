# Design resolution: hook-logging-pipeline

outcome: early-exit
tier: B (light design)
date: 2026-09-05

## Why early-exit

The five-round `/planning:interview` (21 questions, Brief in `../PLAN.md`) already resolved every
design thread `/planning:design` would open: the record contract (Q14 spine, Q11 correlation keys),
storage topology (Q7, Q12, Q16), retention (Q18, Q19), toggles (Q10), module placement (Q3, Q4),
and the reader boundary (Q20). No new type crosses a module boundary: the producer, sink, retention
hook and reader all live in `plugins/claude-ops`, and the one shared contract (the telemetry
envelope) is additive-only and unchanged by this lane. A full design pass would restate the Brief.

## Type sketch

Per-session record, one JSON object per line in `.observability/claude/sessions/<session_id>.jsonl`:

```text
Spine (every line):
  ts               string   ISO-8601 UTC, second resolution
  session_id       string   from the hook payload; a line is never written without it
  hook_event_name  string   from the hook payload
  status           string   ok | blocked | error | skipped   (open set; readers tolerate unknown)
  duration_ms      integer  producer-measured elapsed
  prompt_id        string?  present when the payload carries it
  tool_use_id      string?  present on tool events
  agent_id         string?  present inside a subagent
  traceparent      string?  present when TRACEPARENT is in the environment
  source           string   "event-log" (the per-event producer) | "envelope" (a routed telemetry envelope)

Payload (only on events carrying a decision or a change):
  tool_name, file_path            PostToolUse / PostToolUseFailure / PreToolUse
  reason                          SessionEnd, PermissionDenied
  model                           PreModelSwitch / PostModelSwitch
  hook                            envelope-sourced lines: the producing hook id
  exit_code, subject, changed     envelope-sourced lines, mapped as the legacy sink maps them
```

Event registry entry (`plugins/claude-ops/hooks/hook-events.registry.json`, generated):

```text
  name      string   event name as the reference spells it
  when      string   the "When it fires" cell, verbatim
  category  string   session | prompt | tool | permission | agent | task | turn | config | worktree | compaction | model | mcp
  claim     string   "hook event <name> is documented in the Hooks reference lifecycle table"
  basis     string   https://code.claude.com/docs/en/hooks#hook-events (raw markdown, curl -sS -L of hooks.md)
  as_of     string   YYYY-MM-DD of the fetch
  recheck   string   "the lifecycle table in hooks.md adds, removes or renames an event; re-run scripts/gen-hook-event-registry.sh"
```

Both shapes are consumed only by bash and jq inside this plugin; neither is exported to another
plugin, which is what keeps this at Tier B.
