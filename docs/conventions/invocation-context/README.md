# Skill invocation-context rubric

Owner doc for choosing a skill's **execution context**: whether the body runs in the current
conversation (the fleet default: omit `context`) or as an isolated subagent (`context: fork`).
Consumed by skill authors at design time (`playbooks:skill-authoring`). One home per the convention
registry ([`docs/plugin-philosophy.md`](../../plugin-philosophy.md) "Convention registry"); this
doc decides, other surfaces point here.

This is a different axis from [invocation-mode](../invocation-mode/README.md), which owns whether
the model may invoke the skill at all. A skill can be model-invoked and still run inline, or
model-invoked and forked. Fork does not change listing eligibility.

Provenance: 2026-08-31 fleet skills audit
([#3545](https://github.com/melodic-software/claude-code-plugins/issues/3545)); operator decision
2026-09-27 to run a two-skill blocking-fork pilot and to record the anti-candidate classes here.

## Official semantics

`context: fork` makes the skill body the prompt of a new subagent. The subagent does not see the
parent conversation, so the body plus `$ARGUMENTS` plus the working tree have to stand on their
own. `agent` selects the subagent type (default `general-purpose`). The fork is backgrounded by
default from Claude Code v2.1.218; `background: false` waits for the result in the invoking turn.
A backgrounded fork uses the narrower background-subagent tool set. There is no user interaction
mid-run.

> **Verification.** Claim: `context: fork` starts an isolated subagent with no conversation
> history; `background` defaults to `true` from v2.1.218 and `false` blocks the invoking turn;
> `agent` selects the type and defaults to `general-purpose`; a backgrounded fork uses the
> narrower background-subagent tool set. Basis:
> <https://code.claude.com/docs/en/skills#run-skills-in-a-subagent> and the frontmatter-reference
> rows for `context`, `agent`, and `background`. As of 2026-09-28 (Claude Code 2.1.282). Recheck
> when that section drops any of those statements, when the default for `background` changes, or
> when a release note names `context: fork`.

`context: fork` is not the Agent tool's "fork the current conversation" subagent, which *does*
inherit history. When the task depends on what was just discussed, keep the skill inline or fork
the conversation explicitly; do not set `context: fork`.

## The default, and why

**Inline (omit `context`) is the default.** Every `context: fork` must earn it below. Zero skills
in this fleet used the key before the 2026-09-27 pilot, so there is no in-repo runtime history to
treat as precedent: the pilot is the evidence-gathering step, not a rollout.

Fork pays when the body is a long, argument-scoped, read-only procedure whose file reading would
otherwise stay in the main conversation. It costs the parent history, mid-run user interaction,
and — unless `background: false` is set — the invoking turn's result timing.

## When fork pays

All of these, together:

1. **Read-only.** The skill reports; it does not mutate the target. Mutating action variants
   (`fix`, `--implement`, `--track`) stay inline even when the report path would fork.
2. **Argument-scoped.** `$ARGUMENTS` plus the working tree are enough. The body does not need
   earlier turns.
3. **No human gate.** No mid-flow confirmation, interview, or AskUserQuestion.
4. **Heavy isolated reading.** The body (or the files it loads) would otherwise occupy the parent
   context for a long read-only pass.

A skill that fails any one of those stays inline.

## Background posture

Official default for a fork is `background: true`: the user keeps working and the report arrives
later. That is a UX change for a user-invoked report skill, and it breaks Skill-tool orchestration
that expects the result in the same turn.

**This fleet's default for a forked skill is `background: false`.** Write the key explicitly.
A backgrounded fork is allowed only after a skill-specific confirmation that an async report is
the intended UX.

**A skill another skill invokes via the Skill tool must block.** `claude-config:audit-pass` chains
lanes through the Skill tool and keeps one human gate for the whole pass. A backgrounded target
would return before the lane's report exists, so result timing and that one-gate flow would
diverge. Blocking (`background: false`) keeps the caller's wait. The harness also waits without
that key when `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` or when an earlier invocation of the same
skill is still running; those are harness fallbacks, not a reason to omit the key.

## Pilot (2026-09-27)

Two skills, both `context: fork` and `background: false`, both `agent` omitted (general-purpose):

| Skill | Why it pays | Orchestration |
|---|---|---|
| `claude-config:audit-permission-state` | Read-only, argument-scoped, no human gate, long deterministic reader over every settings scope | `audit-pass` *does* Skill-tool-invoke it as a lane. Blocking fork is the composition posture: the pass waits for the lane report. `--oracle` is never dispatched from the pass. |
| `mcp-tools:audit` | Read-only, optional path argument, no human gate, heavy per-tool file reading | Not an `audit-pass` lane. User-invoked and Skill-tool-invoked callers both wait for the scorecard. |

Evaluate the pilot on (a) whether the returned report is complete without parent history, (b)
whether `audit-pass`'s permission-state lane still lands in the same turn with the one-gate
intact, and (c) whether a user who types `/claude-config:audit-permission-state` still sees the
report before the turn ends. Do not flip further skills until those three hold.

Next-tier candidates, only after that evaluation: `claude-config:audit-permission-grants`,
`claude-ops:inventory`, `claude-ops:audit-install-state`, `skill-quality:check`,
`code-tidying:audit-dead-code`, `docs-hygiene:audit-progressive-disclosure`, `testing:audit`.
Each still has to clear the four tests above and, if `audit-pass` or another orchestrator
Skill-tool-invokes it, take `background: false`.

## Anti-candidate classes

Do not set `context: fork` on these, even if the skill is otherwise long and read-only. Each is a
correctness argument, not a preference. Recorded so a later sweep cannot flip them by analogy
with the pilot.

1. **Current-session measuring.** The fork is a different session, so the reading would be of the
   wrong thing. Examples: `context-budget:audit`, `claude-ops:audit-performance`,
   `claude-ops:audit-skill-visibility`.
2. **Mid-flow confirmation or interview.** A fork has no user interaction during the run.
   Examples: `docs-hygiene:audit-encapsulation` (confirmation), `claude-memory:audit` on its `fix`
   path, `ai-briefing:generate` (collection gate), every `session-flow:*` skill,
   `planning:interview`, `planning:plan`, `planning:prd`, and the `discipline:*` conversation-bound
   correctors.
3. **Mutating action variants** of an otherwise-forkable audit (`fix`, `--implement`, `--track`).
   The argument for forking is that the skill is read-only.

A skill that matches an anti-candidate class and also matches "when fork pays" stays inline. The
anti-candidate wins.

## Authoring checklist

- Omit `context` unless every "when fork pays" test holds and no anti-candidate class applies.
- When `context: fork` is set, write `background: false` unless a recorded skill-specific
  confirmation chooses async.
- Do not set `agent: Explore` or `agent: Plan` on a skill whose steps need tools those agents
  strip; the default `general-purpose` is the pilot's choice.
- State in the body that the run has no parent history, so `$ARGUMENTS` and the working tree are
  the whole input.
- Re-read this doc before flipping a next-tier candidate. The pilot is two skills, not a pattern
  to copy.

## Cross-references

- plugin-philosophy: Convention registry (this doc's row); Skills row of the adoption table
  (`context: fork` is case-by-case through the adoption gate — the pilot is that gate's first
  in-fleet use).
- [invocation-mode](../invocation-mode/README.md): whether the model may invoke the skill; orthogonal.
- `playbooks:skill-authoring`: authoring-time pointer here.
- `claude-config:audit-pass` lane catalog: the permission-state lane is a blocking fork.
