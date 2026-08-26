---
description: "Compose this plugin's discipline correctors into ONE batched pass. Requires conversation-inheriting fork subagents (`subagent_type: fork`); when fork mode is unavailable the skill emits `SWEEP-ALL: DEGRADED (fork-unavailable)` and runs the posture digest only (no audits, no corrections, no inline sequential fallback). At conversation start it instead reports a cheap posture digest (which disciplines are in scope) with no audit. Use when: 'sweep all disciplines', 'ground ourselves', 're-anchor everything', 'run the whole re-anchor bundle', 'posture batch', 'set our posture before we start', 'batch the correctors', or at conversation start to set posture across every standing discipline at once. Membership is each corrector's own tier metadata; for a single discipline, invoke that corrector directly."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Batch every discipline corrector into one audited re-anchor pass
---

# Sweep all disciplines

A **declared second species** in this plugin: NOT a corrector. Every sibling
skill re-anchors ONE discipline; this one carries no discipline of its own. It is a pure router that COMPOSES the correctors into a single batched
re-anchor pass. It holds zero discipline text: the disciplines live in the
correctors, the shared method lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md),
and membership + order live in each corrector's own tier metadata. This skill
names no members. It globs and reads them, so the bundle cannot drift from a
hand-maintained list.

## Two modes

1. **Session-start digest (cheap, default when nothing has happened yet).**
   Derive the posture from the skill listing and each corrector's tier
   metadata. NO corrector bodies load, NO audit runs. Report which
   correctors are core (run every session), which are situational
   (relevance-gated), and which are never-batched. This is the
   conversation-start case: set posture, audit nothing.
2. **Full batch pass (mid-session, or on explicit request).** Preflight that
   the fan-out can inherit this conversation (mandatory. See Preflight), then
   fan out an audit-only subagent per in-scope corrector and apply their
   corrections once, on the main thread, in a fixed order (below). A failed
   preflight degrades to mode 1 with the exact degrade token as the report's
   first line (see Preflight).

## Resolving membership (never named inline)

Glob the sibling corrector directories and read each one's
`metadata.discipline-batch` (`core` / `situational` / `never`) and
`metadata.discipline-batch-rank`. The runbook never hardcodes member names;
the tier is colocated with each corrector, so changing a shipped tier is a PR
to that corrector. Drift is structurally impossible.

- **core**. In scope every session.
- **situational**. In scope only when relevant to THIS conversation. Route
  from the corrector's own listing description (its trigger phrases and
  "at conversation start on …" clause), not from a guess. Report which
  situational correctors were included and which were skipped and why. A
  skip is always reported, never silent.
- **never**. Excluded from the batch by execution or interaction class
  (heavier fan-out tiers; correctors that need a non-fork fresh context or
  stop to remediate with the user). Membership is whichever correctors
  declare `discipline-batch: never`. This runbook does not enumerate them.
  Report that they exist (from the glob) and are invoked directly, not
  batched.

**userConfig overlay** (see Configuration) applies after tier resolution:
`exclude` drops a member, `promote` lifts a **situational** corrector to
always-run, `demote` drops a core corrector to relevance-gated. `promote`
is situational-only: a name whose resolved tier is `never` or `core`, or
that matches no installed corrector, draws a **visible warning** and is
not promoted (core stays core; never stays out of the batch; unknown is
ignored). Report the net effect, including every such warning, when an
overlay changes the resolved set. Zero-config = tiers exactly as the
correctors declare them.

## Preflight: prove the fan-out can inherit (before step 1)

The batched pass is only meaningful if its subagents actually inherit this conversation, and its
step 4 writes their remedies to the working tree. Establish inheritance before dispatching, never
by assuming it. Read [reference/inheritance-preflight.md](reference/inheritance-preflight.md) now,
before the first dispatch of a full-batch pass: it owns the three stages, the canary, the
fail-closed verify, the degrade path when inheritance cannot be proved, and what is gated on the
result. Session-start digest mode never runs the preflight and never reads that file.

## The batched pass, a declared delta from the shared loop

Read [reference/batched-pass.md](reference/batched-pass.md) once the preflight has proved
inheritance, and before beginning step 1: it owns the five steps, the declared delta from the
shared loop's correct-forward-now step, the per-member ledger contract, the root-cause dedup, the
rank-ordered single correction pass, and the consolidated report. Do not begin step 1 from the
preflight's output alone. Session-start digest mode never reaches it.

## Member human-gates survive batching

The batch never converts a member's human gate into an autonomous action.
The shared method's outward-artifact carve-out (no PR, issue, or published
comment without explicit opt-in) holds, as do `follow-our-standards`'
upstream-divergence routing (draft and route, do not file),
`pick-for-the-problem`'s incumbent-replacement decisions, and
`recheck-against-upstream`'s undocumented-divergence calls. The batch
surfaces these for the user; it does not resolve them unasked.

## Configuration

The overlay reads three personal-scalar `userConfig` options (configured
through Claude Code's native plugin-config flow, see the plugin README, never a hand-edited member), substituted here at load:

- Excluded correctors: `${user_config.batch_exclude}`
- Promoted to always-run: `${user_config.batch_promote}`
- Demoted to relevance-gated: `${user_config.batch_demote}`

Each is a comma-separated list of corrector names. An unset option does not
reliably substitute to empty: on a zero-config or headless install, or for a
user who never ran plugin-config, the literal `${user_config.…}` token
survives instead. Treat BOTH an empty value AND a surviving literal
placeholder as unset, no overlay from that key, and never read the literal
token as a corrector name. Apply
after tier resolution: `batch_exclude` drops a member, `batch_promote` lifts a
situational corrector to always-run, `batch_demote` drops a core corrector to
relevance-gated. **`batch_promote` accepts situational names only.** For each
promote entry, resolve the name against the globbed correctors' tier metadata:

- **situational**. Promote to always-run (the only successful case).
- **never**. Visible warning; do not promote; leave excluded from the batch.
- **core**. Visible warning; do not promote; leave as always-run core (a
  no-op that must not look like a successful promote).
- **unknown** (matches no installed corrector). Visible warning; ignore.

Report the net effect whenever the overlay changes the set, and surface every
never/core/unknown promote warning in that report, never silently drop them.

## What this skill does NOT do

- **Not a corrector.** It owns no discipline and re-anchors nothing itself.
- **Not `use-your-skills`.** That corrector routes to the ONE skill fitting a
  task; this composes the whole posture bundle.
- **Not a session or SDLC orchestrator.** Staged navigation and session
  lifecycle belong to the `session-flow` plugin; this only sequences the
  re-anchor correctors.
- **Does not batch the `never` tier**. Correctors that declare
  `discipline-batch: never` are invoked directly; this runbook does not list
  them by name.
- **Does not define membership by inline names**. Membership is each
  corrector's own tier metadata (glob + read). Inline names elsewhere in this
  file illustrate rank-order intent or overlay examples, never the member set.
- **Does not silently accept a non-situational `batch_promote`**. Never,
  core, and unknown promote entries warn and are not promoted.

## Gotchas

- **Fork, not fresh/typed, and not skill-level `context: fork`.** Only the
  Agent-tool `subagent_type: "fork"` inherits the conversation the audit
  reads; the other two start blank.
- **Audit in the forks, correct on the main thread.** Parallel forks that
  wrote would race and re-dilute salience; the value is one ordered
  correction pass.
- **The forks' no-writes rule is trusted, not enforced. Say so.** A named
  subagent's tool access can be narrowed with `tools` / `disallowedTools`; a
  fork's cannot. Forks "skip both filters and receive the main conversation's
  exact tool pool", and a fork's system prompt and tools are "Same as main
  session" (<https://code.claude.com/docs/en/sub-agents>). So every audit fork
  holds Write, Edit, and Bash and is only *asked* not to use them. Never
  present the audit fan-out's read-only posture as harness-enforced. If you
  want assurance that the fan-out honored it, capture the working tree's state
  before the FIRST dispatch (the canary included) and compare afterwards, and
  treat any difference as a fork that wrote. Untrusted output, stop rather
  than correct on top of it. That is detection after the fact, not prevention,
  and a robust comparison is more than a `git status` diff. Specifying one is
  tracked in `#1631` rather than half-specified here.
- **`isolation: "worktree"` was considered for the audit forks and rejected.**
  The Agent tool accepts it on a fork, and it would move a fork's file edits
  off the user's checkout, but a git worktree is created from a commit, so the
  fork would not see the uncommitted work in flight, which is usually the very
  thing the audit exists to inspect. It also would not bound a write addressed
  by an absolute path, and inherited history is full of absolute paths. It
  trades a real loss of audit fidelity for partial containment. Record this if
  it is proposed again.
- **The preflight is the guard, not an optimization.** Skipping it does not
  make the sweep cheaper. It makes every ledger unfalsifiable, and the
  batched pass's step 4 writes those ledgers' remedies to the working tree.
- **Forks run at the parent model's cost.** An Agent-tool fork ignores a model
  override and inherits the whole conversation, so each in-scope corrector's
  audit runs at the parent model over the full transcript; the wave cap bounds
  burst, not per-fork cost. Keeping the `never` tier out and relevance-gating
  the situational tier are what hold the fan-out small. Order of magnitude from
  a real full-batch run on a mid-length session: each fork consumed
  ~170K tokens (inherited transcript), so an 8-in-scope pass ran ~1.4M tokens
  for the audit phase alone, plus one more fork for the proof-only canary.
  Budget the sweep as a
  deliberate spend, not a reflex. On a long transcript the per-fork cost only
  grows.
- **`tighten-your-output` stays last**. Tightening before the other
  corrections would tighten text they then rewrite.
- **A situational skip is reported, not silent**, the user sees what was
  left out and why.
