# RESEARCH — Autonomous-agent escalation & observability (stop-and-surface criteria, report-back channels)

## Task

WP7-Q5 grounding (2026-07-17, two fresh-context subagents, primary sources fetched this run):
how do Anthropic surfaces and credible peers decide an autonomous coding agent must stop and
surface an issue to a human, through what channels does it report back, and on what
observability substrate. Complements RESEARCH-headless-agents.md (seams 5/7/8) and the T6
telemetry contract.

## Summary

Vendors converge on a **stop-criteria taxonomy with two families** — deterministic caps/errors
(native everywhere) and judgment-based escalation (policy layer, most explicit in Yegge's
gastown) — and on **transient-recoverable never escalates** (retry with backoff). Two divergent
escalation SHAPES exist: **mid-run interrupt** (pause + out-of-band notify + ack + stale
re-escalation: gastown, the SDK `canUseTool` pattern, Managed Agents `session.status_idled`
webhook) and **terminal handoff** (run to a terminal state, surface on tracker/PR: Copilot,
OpenAI Symphony). The coding-agent-native systems converge on **VCS host / issue tracker as the
default report-back surface**, with chat/email/SMS as urgency-scaled add-ons. Anthropic ships
the HOOK POINTS (Notification/PermissionRequest hooks, managed-agent webhooks, result
subtypes, native OTel with TRACEPARENT inheritance) but **no managed escalation integration**
— routing is the adopter's to own. **No standard telemetry signal for "agent escalated to a
human" exists**: OTel GenAI agent span conventions are Status: Development and define no
escalation/approval/handoff span.

## Key evidence (fetched 2026-07-17; per-claim detail in session subagent reports)

### Anthropic surface (all code.claude.com / platform.claude.com / anthropic.com primaries)

- Plain headless `-p` has **no built-in human callback**: `dontAsk` denies un-pre-approved
  tools (model told via rejection), `acceptEdits` aborts the run on unapproved tool attempt.
  Stop-and-ask requires the Agent SDK (`canUseTool` pauses the loop, may stay pending
  indefinitely; `defer` lets the process exit and resume later from the persisted session).
- Native terminal result subtypes = deterministic stop criteria: `success`,
  `error_max_turns`, `error_max_budget_usd` (`maxBudgetUsd` — "a good default for production
  agents"), `error_during_execution`, `error_max_structured_output_retries`;
  `stop_reason:"refusal"` for model declines. Caveat: hooks may not fire at the `max_turns`
  limit — caller must inspect the result subtype.
- Escalation hook points (self-wired, not managed): `Notification` hook (permission_prompt /
  idle_prompt → "Send agent status updates to Slack or PagerDuty", Slack-webhook example
  shipped), `PermissionRequest` hook, `PreToolUse` deny (applies even in bypassPermissions),
  `Stop`/`StopFailure`.
- Managed Agents (beta): signed webhooks — `session.status_idled` ("Agent awaiting input, for
  example a tool permission approval or a new user message") = the stop-and-surface signal;
  `session.status_terminated` (terminal error); `session.status_rescheduled` (transient,
  auto-retry); `deployment.paused` only on UNRECOVERABLE scheduled-run failure. Docs' own
  example: on idled → GET session → notify user. Ordering not guaranteed.
- Human takeover is not a first-class API: takeover = resume the persisted `session_id`
  (`resume`/`fork_session`, `--teleport` on web). Documented recovery: resume with a higher
  limit after `error_max_turns`/`error_max_budget_usd`.
- Cloud auto-fix PR branches on judgment: clear fix → push + explain; "ambiguous or
  architecturally significant" → asks the human first. Merge-conflict blindspot (no VCS-host
  webhook when base advances).
- Native OTel in headless: `-p`/SDK sessions inherit `TRACEPARENT`/`TRACESTATE` (spans join
  the caller's distributed trace — confirms the T6 propagation claim empirically at the docs
  level); metrics (cost, tokens, edit-decisions), events (`api_error`, `api_refusal`,
  `tool_decision`, `permission_mode_changed` incl. `auto_gate_denied`,
  `api_retries_exhausted`), beta trace span `claude_code.tool.blocked_on_user` (measures
  human-block wait directly).
- Engineering guidance verbatim: "Agents can then pause for human feedback at checkpoints or
  when encountering blockers"; "include stopping conditions (such as a maximum number of
  iterations)".

### Peers (gastown, Copilot, Symphony, OTel semconv primaries)

- gastown escalation criteria (explicit SHOULD-escalate list): system errors, security
  issues, unresolvable merge conflicts, ambiguous requirements (multiple valid
  interpretations), design decisions needing human judgment, stuck loops, gate timeouts.
  Explicit non-escalation: normal workflow, recoverable/transient (auto-retry), info queries.
  Severity fan-out (P0 → tracker item + agent-mail + email + SMS; P1 drops SMS; P2
  tracker+mail only), ack semantics (`ack` prevents re-escalation), stale-unacked
  auto-re-escalation (default 4h, severity bump, capped at 2).
- Copilot cloud agent = pure terminal handoff: never asks mid-run; 59-min cap; firewall
  blocks and failures surface as PR-body warnings / PR comments; retry = unassign+reassign.
- OpenAI Symphony: orchestrator handles only operational stops (ineligibility, transient
  backoff); human handoff is a **workflow-defined terminal state** ("Human Review") reached
  by the agent, with proof-of-work (CI status, review feedback, walkthrough) surfaced on the
  tracker/PR; the AGENT writes tracker state/comments, not the orchestrator. REQUIRED
  operator observability: structured logs minimum.
- OTel GenAI agent span conventions: moved to dedicated semconv repo, **Status: Development**
  (experimental); spans for create_agent/invoke_agent/invoke_workflow/plan/execute_tool; **no
  escalation/approval/human-handoff span or attribute exists** (verified negative).

## Gaps / flags (carried, not laundered)

- claude-code-action failure-reporting specifics (comment vs check-run vs job failure)
  UNVERIFIED — README thin; fetch its docs/usage.md if load-bearing at architect.
- HumanLayer approval-SDK: deprecated/pivoted (repo README says code deprecated; company now
  ships an agent IDE) — approval-API-as-a-service pattern has no maintained credible vendor;
  do not cite as living precedent.
- ACP human-input requests + cross-vendor AGENTS.md signaling guidance: not fetched, UNVERIFIED.
- Managed-agent stream vs webhook event-name drift (`status_idle` vs `status_idled`) — bind
  exact names at build time from live docs.

## Synthesis for the runner design pack

1. **Stop-criteria taxonomy (contract):** two families. (a) Deterministic, runner-owned:
   turn/budget/wall-clock caps, execution/API error after retries, structured-output
   exhaustion, refusal, verification-gate failure, isolation violation, cancellation. (b)
   Judgment, agent-signaled: ambiguity, design decision needing human judgment, security/
   data-integrity event, unresolvable blocker, no-progress. Transient-recoverable = retry
   with backoff, never escalation (cross-vendor consensus).
2. **Shape:** terminal handoff is the vendor-converged launch shape for headless drains;
   mid-run interrupt mechanisms exist first-party (SDK `canUseTool`+`defer`, managed
   `session.status_idled`) and are adoptable later without contract change.
3. **Channels:** tracker/VCS = source-of-truth surface (converged); chat/email/push =
   severity-scaled notification add-ons; ack + stale-re-escalation semantics are the
   mature pattern to absorb (own vocabulary).
4. **Observability:** T6 contract holds and is strengthened (native TRACEPARENT inheritance,
   blocked-on-user span, api_error/refusal events). Escalation events have NO standard
   semconv signal → they ride the T6 custom namespace with the work-item join key; flag as
   candidate upstream contribution when the GenAI semconv matures.
