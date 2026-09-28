# Skill invocation-context rubric

Owner doc for choosing a skill's **invocation context**: whether the skill body runs in the
current conversation (`context` omitted, the fleet default) or in an isolated subagent
(`context: fork`). Consumed by skill authors at design time (`playbooks:skill-authoring`) and
by audits grading existing skills. One home per the convention registry
([`docs/plugin-philosophy.md`](../../plugin-philosophy.md) "Convention registry"); this doc
decides, other surfaces point here.

Sibling: the [invocation-mode rubric](../invocation-mode/README.md) owns `disable-model-invocation`.
The two keys compose. A forked skill with `disable-model-invocation: true` is still unreachable via
the Skill tool; a forked skill with `false` remains Skill-tool reachable, and a blocking fork
(`background: false`) returns in the invoking turn so an orchestrator can wait for the report.

## What a fork does

**Claim:** `context: fork` starts a new subagent of the type in `agent` (default `general-purpose`)
and gives it the skill body as its prompt. The subagent does not see conversation history, so the
body has to stand on its own. Background is the default; `background: false` waits for the result
in the invoking turn. A backgrounded fork uses the narrower background-subagent tool set.
Requires Claude Code v2.1.218 or later for `background: false`; earlier versions always blocked.

**Basis:** [Run skills in a subagent](https://code.claude.com/docs/en/skills#run-skills-in-a-subagent)
and the frontmatter table rows for `context`, `agent`, and `background`
(<https://code.claude.com/docs/en/skills#frontmatter-reference>). As of 2026-09-28.
**Recheck:** that page drops or redefines `context: fork`, `background`, or the isolated-prompt
claim, or a release note names forked-skill execution.

A skill-level fork is not the Agent tool's `fork` subagent type. The Agent-tool fork inherits
conversation history; `context: fork` starts blank. Do not cite one as the other.

## When a fork pays

A fork is worth the isolation when all of these hold:

- The skill is **read-only** (report, inventory, audit). A mutating skill that writes through the
  shell is outside `/rewind` on a backgrounded fork, and even a blocking fork still discards the
  parent conversation the mutation might need.
- The body is **argument-scoped** and has **no human gate** mid-run. A fork cannot ask the user.
- The body does **heavy file reading** that currently stays in the main context. Isolation is the
  payoff; a short body that already finishes cheaply does not earn a subagent.
- The skill does **not measure the current session**. A fork would measure the subagent instead.

Pilot (2026-09-27 operator decision, #3545): `claude-config:audit-permission-state` and
`mcp-tools:audit`, both with `background: false`. Next-tier candidates, still unflipped: 
`claude-ops:inventory`, `claude-ops:audit-install-state`, `skill-quality:check`,
`code-tidying:audit-dead-code`, `docs-hygiene:audit-progressive-disclosure`, `testing:audit`.
`claude-config:audit-permission-grants` is next-tier on paper but `audit-pass` dispatches its
frontmatter scope, so it stays unflipped until that composition is measured.

## Background posture

A user-invoked report that prints in the same turn today becomes asynchronous if the skill
backgrounds. That is a UX change, not a default this rubric will set for a report skill.

- **User-invoked report:** `background: false`. The operator waits; the report arrives in the
  invoking turn.
- **Fire-and-forget research with no operator sitting on the result:** background may stay at the
  platform default (`true`), and only after an explicit product decision.
- **Skill-tool orchestration** (`audit-pass` and similar): a blocking fork keeps one-gate flow and
  result timing. A backgrounded fork returns before the report exists, so the orchestrator cannot
  wait. Do not flip a skill `audit-pass` (or any Skill-tool chain) invokes to a backgrounded fork.

The 2026-09-27 decision uses `background: false` on both pilot skills, including
`audit-permission-state`, which `audit-pass` does dispatch. Blocking is the composition that keeps
that chain's result timing.

## Anti-candidate classes

Recorded as standing rules. Do not flip a skill in these classes later without reopening this doc.

1. **Current-session measurement.** The fork would measure the subagent. Examples:
   `context-budget:audit`, `claude-ops:audit-performance`, `claude-ops:audit-skill-visibility`.
2. **Mid-flow confirmation or interview.** A fork has no user interaction during the run.
   Examples: `docs-hygiene:audit-encapsulation` (confirmation), `claude-memory:audit` `fix`,
   `ai-briefing:generate` (collection gate), every `session-flow:*` skill,
   `planning:interview` / `plan` / `prd`, every `discipline:*` conversation-bound corrector.
3. **Mutating action variants** of an otherwise forkable audit (`fix`, `--implement`, `--track`).
   The argument for forking is that the skill is read-only.

## Invocation-mode composition

`disable-model-invocation: true` hides the skill from the model entirely, Skill-tool included.
Forking such a skill only affects the `/name` path. Do not fork a `true` skill to "save listing
cost"; listing cost is not an invocation-mode exception
([invocation-mode](../invocation-mode/README.md) "Listing cost was considered as a fourth exception
class and rejected").

A `false` forked skill stays in the listing and stays Skill-tool reachable. The isolation is
execution context, not discoverability.

## Cross-references

- plugin-philosophy: Convention registry (this doc's row); Skills surface adoption of
  `context: fork`.
- `playbooks:skill-authoring`: authoring-time pointer ("Invocation context") and
  `reference/authoring-guidance.md`.
- [invocation-mode](../invocation-mode/README.md): `disable-model-invocation`, Skill-tool reach.
- Provenance: #3545 (2026-08-31 fleet skills audit; 2026-09-27 operator decision).
