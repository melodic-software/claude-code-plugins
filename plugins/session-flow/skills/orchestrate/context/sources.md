# Sources behind the orchestration brief

## Contents

- [Imperative 1: DELEGATE / FAN OUT](#imperative-1-delegate--fan-out)
- [Imperative 2: SPEC EVERY SPAWN](#imperative-2-spec-every-spawn)
- [Imperative 3: FRESH-CONTEXT VERIFY](#imperative-3-fresh-context-verify)
- [Imperative 4: RUN WORKERS WELL](#imperative-4-run-workers-well)
- [Imperative 5: NESTED SUBAGENTS](#imperative-5-nested-subagents)
- [Priming addendum: surface reachability](#priming-addendum-surface-reachability)
- [Priming addendum: model and effort routing](#priming-addendum-model-and-effort-routing)
- [Imperative 6: SURFACE DRIFT](#imperative-6-surface-drift)
- [Imperative 7: CALIBRATE TO CONDITIONS](#imperative-7-calibrate-to-conditions)

Each record states the decision the brief makes, in our words, and points at the upstream section
to read live. This file stores no upstream text. When a decision needs the specific, fetch it from
the pointer. A blog post is never the pointer; it appears only as a correlate beside one.

## Imperative 1: DELEGATE / FAN OUT

- Start with one agent, and add agents only when evidence supports it.
- Decompose by the context each piece needs, not by the kind of work. Sequential phases of one
  feature stay in one agent.
- Coding parallelizes less than research: never split one feature across agents.
- This plugin's operating cost figure for multi-agent work is 3–10× a single agent's tokens, and
  roughly 15× for a research-shaped fan-out.
- Delegate only for context protection, parallelism, or a tool-restricted specialist; outside
  those, coordination costs more than it returns.

- **Pointer**: for when to delegate rather than stay in the main conversation, see
  <https://code.claude.com/docs/en/sub-agents#choose-between-subagents-and-main-conversation>;
  for multi-agent token cost, see <https://code.claude.com/docs/en/costs#agent-team-token-costs>
  and <https://code.claude.com/docs/en/agent-teams#when-to-use-agent-teams>. No docs page states a
  cost multiplier as of the as-of date.
  (correlate with <https://claude.com/blog/building-multi-agent-systems-when-and-how-to-use-them>;
  correlate with <https://www.anthropic.com/engineering/multi-agent-research-system>)
- **As of**: 2026-06-14
- **Recheck trigger**: one of those sections moves, or a docs page starts stating a multi-agent
  token multiplier.

## Imperative 2: SPEC EVERY SPAWN

Every spawn states what to produce and why (the larger task, who reads the output, what it
enables), when it is done, the shape of the return, which tools and sources it may use, and what
it must not touch. Size the number of workers and their tool budgets to how hard the task is.

- **Pointer**: for giving the reason behind a request, see
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5#give-the-reason-not-only-the-request>;
  for briefing a parallel worker, see
  <https://code.claude.com/docs/en/agent-teams#give-teammates-enough-context>.
  (correlate with <https://www.anthropic.com/engineering/multi-agent-research-system>)
- **As of**: 2026-06-14
- **Recheck trigger**: either section moves or stops covering what a delegated request should
  carry.

## Imperative 3: FRESH-CONTEXT VERIFY

A finished batch goes to a separate verifier in a fresh context, never a self-review in the
context that produced it. The verifier gets concrete pass/fail criteria, is scoped to correctness
and the stated requirements, and judges the final state, not the process.

- **Pointer**: for a fresh-context review step, see
  <https://code.claude.com/docs/en/best-practices#add-an-adversarial-review-step>; for giving the
  model a check it can run, see
  <https://code.claude.com/docs/en/best-practices#give-claude-a-way-to-verify-its-work>; for
  verifier subagents in long runs, see
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5#recommended-scaffolding-changes>.
  (correlate with <https://claude.com/blog/multi-agent-coordination-patterns>;
  correlate with <https://www.anthropic.com/engineering/multi-agent-research-system>)
- **As of**: 2026-06-14
- **Recheck trigger**: one of those sections moves or stops recommending a fresh-context
  verifier.

## Imperative 4: RUN WORKERS WELL

Dispatch without blocking and keep working while workers run. Reuse a long-lived worker across
related subtasks. Watch running workers and intervene when one drifts or lacks context. The brief
states these model-agnostically on purpose: they are correct standing imperatives for an
under-delegating model too.

- **Pointer**: for asynchronous dispatch, long-lived subagents and intervention, see
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5#parallel-subagents>.
- **As of**: 2026-06-14
- **Recheck trigger**: that section moves or stops covering any of the three behaviors.

### A worker's own background work is not a wait

The "poll in the foreground or return" clause. A worker never counts on its own background
command, watch, or sentinel file to resume it: it polls an external result in the foreground with
a bounded loop, or returns what it has and lets the parent re-dispatch. The brief does not claim a
background worker is never notified when its own command ends. We found no documented way for a
worker to wait on an external result without a command of its own that ends when the result
arrives.

The sentinel-file clause is judgment from observed stalls: in one handoff chain, workers waited on
background tasks, watches, or sentinel files that never resumed them, 14+ times across two
sessions, until their timeouts.

- **Pointer**: for when a subagent's background command stops, see
  <https://code.claude.com/docs/en/tools-reference#when-a-background-command-stops>; for watch
  deadlines, see <https://code.claude.com/docs/en/tools-reference#monitor-tool>; for the
  notification a background subagent gets, see
  <https://code.claude.com/docs/en/sub-agents#run-subagents-in-foreground-or-background>.
- **As of**: 2026-10-01
- **Recheck trigger**: either page changes its subagent background-command lifetime or
  notification behavior, or the Monitor deadline figures.

#### Record: a hung background shell keeps a returned worker listed as active

A hung background shell has been observed to keep a worker that already reported listed as
active. Retiring a finished worker therefore includes checking for its still-running background
tasks.

- **Pointer**: one local observation on 2026-09-19: an `awk` scan over a file of about 9 MB hung,
  the dispatching worker returned, and the agent panel still showed it active for hours. For a
  background subagent leaving a command running past its turn, see
  <https://code.claude.com/docs/en/sub-agents#run-subagents-in-foreground-or-background>. As of
  the as-of date no docs page covers how such a command affects the agent panel's active state or
  how a hung one is retired.
- **As of**: 2026-09-29
- **Recheck trigger**: a Claude Code release note or docs change describes background shell
  lifecycle or the agent panel's active state.

### SendMessage worker continuation

The mechanism the priming addendum names for reusing and steering workers, in Claude Code
specifically.

- Resume a worker with `SendMessage` addressed by its agent ID, never with a new `Agent` call,
  which starts a second, independent worker. Continuation does not need agent teams enabled.
- A completed worker, or one Claude stopped with `TaskStop`, is resumable by message. A worker the
  user stopped is not: read a refused send as that case. So never retire a worker with `TaskStop`
  when the goal is to keep it from resuming.
- Prefer the agent ID over the name, because a newer agent can take a name.
- Empirical probe (Tier 0): in this repository's own cloud session on 2026-08-24, two completed
  background subagents (a researcher and a verifier) were each resumed by agent ID via
  `SendMessage`, retained their full context, and returned follow-up work without a fresh `Agent`
  dispatch.
- A permission deny rule naming `SendMessage` also forfeits worker continuation, since resume runs
  through that tool. A session that wants no cross-session messaging but keeps continuation uses
  the narrower inbound control (`crossSessionInbound`) instead of the deny rule.

- **Pointer**: for resuming subagents, see
  <https://code.claude.com/docs/en/sub-agents#resume-subagents>; for turning off cross-session
  messaging, see
  <https://code.claude.com/docs/en/cross-session-messaging#turn-off-cross-session-messaging>.
- **As of**: 2026-08-24
- **Recheck trigger**: a Claude Code changelog entry touching `SendMessage`, subagent resume, or
  cross-session messaging.

## Imperative 5: NESTED SUBAGENTS

Nesting is a shipped feature, not experimental, and the brief never authors a tree that needs a
specific or deep nesting level. The reason is volatility: the nesting default changed three times
between v2.1.172 and v2.1.219, and the surfaces agreeing again does not weaken that argument.
Reliability also degrades with depth.

- Listing `Agent` in a subagent's tools is necessary but not sufficient for a nested spawn, and the
  gate is definition-specific: confirm nesting with the behavioral probe in `gotchas.md`, using the
  definition you plan to put in the intermediate tier.
- A permission gate can deny a spawn before depth is consulted. Read a failed spawn's error text
  before counting it as evidence about depth: a depth rejection names depth, a permission refusal
  names permission.
- When a cached, vendored, or offline copy of the sub-agents page and the changelog disagree,
  treat the changelog as authoritative for the default and the page as authoritative for the
  env-var mechanism and cap semantics, and confirm with the behavioral probe. The page carries no
  dated revision history and has lagged the changelog by a release before, so a copy can still
  describe an older nesting default.

- **Pointer**: for nesting and the depth limit, see
  <https://code.claude.com/docs/en/sub-agents#let-subagents-spawn-their-own-subagents>; for which
  definitions may spawn, see
  <https://code.claude.com/docs/en/sub-agents#restrict-which-subagents-can-be-spawned>; for the
  version history, see <https://code.claude.com/docs/en/changelog> entries 2.1.172, 2.1.178,
  2.1.217, 2.1.219 and 2.1.232 (the raw `changelog.md` is byte-exact where the rendered page
  summarizes).
- **As of**: 2026-08-10
- **Recheck trigger**: a changelog entry touching subagent nesting, depth, or concurrency.

Agent-tool subagents carry two caps, depth and concurrency, each with its own variable
(`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`, `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`). We treat workflow
agents and agent-team teammates as outside those caps. Read the concurrency cap's exemptions and
how resumes count against it from the pointer before sizing a wide fan-out.

- **Pointer**: <https://code.claude.com/docs/en/sub-agents#concurrent-subagent-limit>.
- **As of**: 2026-08-15
- **Recheck trigger**: a changelog entry touching subagent concurrency, or that section moves.

**Below-limit fork parenting a non-fork child: unconfirmed.** The depth-limit rules imply a
below-limit fork keeps `Agent`, but the docs do not state the child-type outcome and no
authenticated probe has recorded it. Keep treating the path as unconfirmed.

- **Pointer**: <https://code.claude.com/docs/en/sub-agents#how-forks-differ-from-other-subagents>.
- **As of**: 2026-08-10
- **Recheck trigger**: an authenticated probe session, or a sub-agents page edit that states the
  child-type rule explicitly.

## Priming addendum: surface reachability

Backs the addendum's parenthetical on dynamic workflows. We rely on two facts together: the
`Workflow` tool is withheld from every non-fork subagent, and a fork keeps the main session's
tools. Either alone proves nothing. Agent-team teammates do not get `Workflow` back.

- **Pointer**: for the tool filters on subagents, see
  <https://code.claude.com/docs/en/sub-agents#available-tools>; for a fork's tools, see
  <https://code.claude.com/docs/en/sub-agents#how-forks-differ-from-other-subagents>.
- **As of**: 2026-10-01
- **Recheck trigger**: either section changes which tools a subagent, fork, or teammate keeps.

## Priming addendum: model and effort routing

Backs the addendum's routing sentence. When the multi-agent plugin is enabled, its skills own the
workflow-or-subagents choice and the per-role model and effort; imperative 7 stays independent of
any plugin. Without them, the session reads the upstream model-selection order directly.

- **Pointer**: <https://code.claude.com/docs/en/sub-agents#choose-a-model>; with the plugin,
  `/multi-agent:assess` and `/multi-agent:route`.
- **As of**: 2026-10-02
- **Recheck trigger**: that section changes how a subagent's model is chosen, or the multi-agent
  skills are renamed.

## Imperative 6: SURFACE DRIFT

Authoring convention, NOT canonical Anthropic orchestration guidance (it appears in none of the
multi-agent sources). Kept in the brief because drift-flagging is useful for any worker: a one-line
flag preserves the signal without derailing the task.

## Imperative 7: CALIBRATE TO CONDITIONS

Part-sourced, part authoring convention. The boundary is called out per factor.

- **Size effort to complexity (S/M/L).** A small ask stays single-agent; only a large, genuinely
  independent surface earns a wide or nested tree. Pointer: as for imperatives 1 and 2.
- **Single-agent is the floor; multi-agent is spent, not defaulted.** The cost figure and the
  delegation conditions under imperative 1 are the reason a small ask stays single-agent.
  Pointer: as for imperative 1.
- **Model capability shifts the sizing.** Our interpretation: a model strong enough to dispatch
  and steer workers reaches further single-agent, and a weaker one needs more decomposition and
  tighter specs. Pointer:
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5#capability-improvements>.
  As of: 2026-06-14. Recheck trigger: that section moves or stops covering delegation.
- **Advisor / verifier availability, context pressure, and concurrent-session / rate-limit
  headroom** are operational authoring convention, NOT canonical Anthropic orchestration guidance.
  They scale the same underlying trade-offs (a fresh-context verifier is worth leaning on when one
  is on hand; a filling window is itself the context-protection trigger imperative 1 names; thin
  rate-limit headroom is a hard ceiling on parallel workers).
- **Unobservable headroom → thin-by-default.** The rate-limit-guard reader contract classifies a
  missing, stale, or `rate_limits`-less snapshot as **unknown → reactive-only**. The guard's mod
  writes that snapshot in interactive and headless sessions and serves the same reading through
  the `mcp__rate-limit-guard__status` pull tool. Headroom is unobservable whenever no live reading
  is obtainable: mods off, the guard not installed, the tool's registration refused by policy, or
  a tool answer with no windows (`verdict: "unknown"`, as under API-key or enterprise auth).
  Imperative 7's thin-by-default concurrent cap, sibling-429 backoff, and
  "never invent window percentages" clauses are the orchestration consumption of that
  classification, not a second contract. Pointer:
  `plugins/rate-limit-guard/reference/reader-contract.md` ("Capability detection (fail-open)",
  "Cloud / remote sessions").
- **Per-worker model tier is an explicit spawn decision.** Every spawn names a model tier,
  because a spawn that names none, for an agent whose definition names none, can fall through to
  the parent session's model: the mechanism behind premium-model fan-outs (imperatives 2 and 7's
  tiering clauses). Pointer: <https://code.claude.com/docs/en/sub-agents#choose-a-model> and
  <https://code.claude.com/docs/en/sub-agents#run-every-subagent-on-one-model>. As of:
  2026-09-27. Recheck trigger: the page changes the resolution order or what an omitted `model`
  field resolves to, or a release note names subagent model resolution.
- **Tier is model AND effort.** A cheaper tier is a cheaper model, a lower effort, or both, and an
  agent definition can set its own effort. This backs imperative 7's "match the reasoning depth
  (effort) to the subtask too" clause. Pointer:
  <https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields> (the `effort` field).
  As of: 2026-10-01. Recheck trigger: that field is renamed, removed, or stops overriding the
  session's effort.
- **Volume-driven default: a fleet inherits the session model unless explicitly routed.** A
  workflow stage that does not need the strongest model names a smaller one; an unrouted fleet runs
  on the session's model, the same resolution as the subagent path at fan-out scale. Pointer:
  <https://code.claude.com/docs/en/workflows#cost>. As of: 2026-09-27. Recheck trigger: the page
  changes how a workflow agent's model is picked.
- **The platform's large-workflow warning is our anchor for "wide fan-out."** The brief speaks of
  a wide fan-out abstractly; the size guideline in force, the warning threshold, the concurrency
  bound with its override, and the total agent cap are read live from the pointer, never copied
  here. Empirical, unpinned datum: a 4-CPU cloud container bound a run at 2 concurrent agents
  (observed 2026-08-15). Pointer: <https://code.claude.com/docs/en/workflows#cost>,
  <https://code.claude.com/docs/en/workflows#set-a-size-guideline> and
  <https://code.claude.com/docs/en/workflows#behavior-and-limits>. As of: 2026-10-01. Recheck
  trigger: that page changes a size-guideline agent count or default, the warning threshold, or
  the concurrency bound or its override.
