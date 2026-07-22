---
name: sweep-all-disciplines
description: "Compose the re-anchor plugin's discipline correctors into ONE batched pass — not a corrector itself, but a router that fans out an audit-only subagent per in-scope corrector and then applies their corrections on the main thread in a fixed order. At conversation start it instead reports a cheap posture digest (which disciplines are in scope) with no audit. Use when: 'sweep all disciplines', 'ground ourselves', 're-anchor everything', 'run the whole re-anchor bundle', 'posture batch', 'set our posture before we start', 'batch the correctors', or at conversation start to set posture across every standing discipline at once. Membership is each corrector's own tier metadata; for a single discipline, invoke that corrector directly."
user-invocable: true
disable-model-invocation: false
---

# Sweep all disciplines

A **declared second species** in this plugin: NOT a corrector. Every sibling
skill re-anchors ONE discipline; this one carries no discipline of its own —
it is a pure router that COMPOSES the correctors into a single batched
re-anchor pass. It holds zero discipline text: the disciplines live in the
correctors, the shared method lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md),
and membership + order live in each corrector's own tier metadata. This skill
names no members — it globs and reads them, so the bundle cannot drift from a
hand-maintained list.

## Two modes

1. **Session-start digest (cheap, default when nothing has happened yet).**
   Derive the posture from the skill listing and each corrector's tier
   metadata — NO corrector bodies load, NO audit runs. Report which
   correctors are core (run every session), which are situational
   (relevance-gated), and which are never-batched. This is the
   conversation-start case: set posture, audit nothing.
2. **Full batch pass (mid-session, or on explicit request).** Fan out an
   audit-only subagent per in-scope corrector, then apply their corrections
   once, on the main thread, in a fixed order (below).

## Resolving membership (never named inline)

Glob the sibling corrector directories and read each one's
`metadata.re-anchor-batch` (`core` / `situational` / `never`) and
`metadata.re-anchor-batch-rank`. The runbook never hardcodes member names;
the tier is colocated with each corrector, so changing a shipped tier is a PR
to that corrector — drift is structurally impossible.

- **core** — in scope every session.
- **situational** — in scope only when relevant to THIS conversation. Route
  from the corrector's own listing description (its trigger phrases and
  "at conversation start on …" clause), not from a guess. Report which
  situational correctors were included and which were skipped and why — a
  skip is always reported, never silent.
- **never** — excluded from the batch by execution or interaction class (the
  `-deep` fan-out tiers; `scrutinize-dont-coast`, which needs a non-fork
  fresh context and stops to remediate with the user). Report that they
  exist and are invoked directly, not batched.

**userConfig overlay** (see Configuration) applies after tier resolution:
`exclude` drops a member, `promote` lifts a situational corrector to
always-run, `demote` drops a core corrector to relevance-gated. Report the
net effect when an overlay changes the resolved set. Zero-config = tiers
exactly as the correctors declare them.

## The batched pass — a declared delta from the shared loop

Recorded here as a **declared delta** per the shared method doc's
declared-delta rule (this runbook is not a corrector, but it orchestrates the
shared loop across members and diverges from its per-corrector
"correct forward now" step, so the divergence is part of this skill's
contract, not silent drift). The shared loop has each corrector run steps 1–3
itself, in its own context. This runbook **splits** them: the audit
(steps 1–2) runs in per-corrector subagents; the correction (step 3) is
collected and applied ONCE on the main thread, serialized in rank order.
Rationale: a dozen disciplines each correcting forward independently in one
context recreates the salience dilution this plugin exists to fix, and a
merged pass lets order matter. The shared method's Non-negotiables are
unchanged and bind every member.

1. **Fan out, audit-only.** For each in-scope corrector, dispatch a
   conversation-inheriting **fork** subagent — the Agent tool's
   `subagent_type: "fork"`, which inherits the full conversation history the
   audit must read. A fresh/typed subagent receives no history, and a
   skill-level `context: fork` also discards it — neither can audit this
   conversation. Fork-spawning is a rollout-gated capability
   (`CLAUDE_CODE_FORK_SUBAGENT`); where it is off, requesting the `fork` type
   falls back to a fresh general-purpose subagent that cannot see the
   conversation — so if forks are unavailable, report that the inheriting
   audit fan-out cannot run and stop, rather than auditing blind. Instruct
   each fork: load exactly this ONE corrector's
   `SKILL.md`, run shared-loop steps 1–2 only (re-anchor + self-audit), make
   NO writes, and return a findings ledger (concrete located findings, or an
   honest "clean"). Cap concurrency in bounded waves like the `-deep`
   siblings; retry only a failed subset, once.
2. **Collect** every ledger.
3. **Correct once, in rank order.** Walk the in-scope members — the core and
   situational correctors that ran (never-tier carries no rank and was already
   excluded at membership resolution) — by ascending `re-anchor-batch-rank`,
   and correct forward each finding on the main thread now — the shared loop's
   step 3, batched. The order:
   `use-your-skills` first (fix which skills govern the work) → evidence
   correctors (get the facts right) → structural correctors → `mind-your-maxims`
   (communication) → `tighten-your-output` dead last, so it never tightens
   text a later corrector rewrites. Correcting on the main thread does not
   suppress the shared method's fresh-context escalation: where a finding's
   suspected drift source is this context's own judgement, re-derive it in a
   fresh-context (non-fork) subagent blind to that reasoning, per the method
   doc's Non-negotiable — the batch orchestrates the correction here, it does
   not waive that escalation. (The fork *audit* inherits context on purpose:
   step 2 is a same-context self-audit; this carve-out is about step 3.)
4. **Report** one consolidated ledger: per corrector — corrected / clean /
   open; plus which situational members ran versus were skipped, and which
   never-members exist for direct use.

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
through Claude Code's native plugin-config flow — see the plugin README —
never a hand-edited member), substituted here at load:

- Excluded correctors: `${user_config.batch_exclude}`
- Promoted to always-run: `${user_config.batch_promote}`
- Demoted to relevance-gated: `${user_config.batch_demote}`

Each is a comma-separated list of corrector names. An unset option does not
reliably substitute to empty: on a zero-config or headless install, or for a
user who never ran plugin-config, the literal `${user_config.…}` token
survives instead. Treat BOTH an empty value AND a surviving literal
placeholder as unset — no overlay from that key — and never read the literal
token as a corrector name. Apply
after tier resolution: `batch_exclude` drops a member, `batch_promote` lifts a
situational corrector to always-run, `batch_demote` drops a core corrector to
relevance-gated. Report the net effect whenever the overlay changes the set.

## What this skill does NOT do

- **Not a corrector.** It owns no discipline and re-anchors nothing itself.
- **Not `use-your-skills`.** That corrector routes to the ONE skill fitting a
  task; this composes the whole posture bundle.
- **Not a session or SDLC orchestrator.** Staged navigation and session
  lifecycle belong to the `session-flow` plugin; this only sequences the
  re-anchor correctors.
- **Does not batch the `never` tier** — the `-deep` fan-out siblings and
  `scrutinize-dont-coast` are invoked directly.
- **Does not name its members inline** — membership is each corrector's own
  tier metadata.

## Gotchas

- **Fork, not fresh/typed, and not skill-level `context: fork`.** Only the
  Agent-tool `subagent_type: "fork"` inherits the conversation the audit
  reads; the other two start blank.
- **Audit in the forks, correct on the main thread.** Parallel forks that
  wrote would race and re-dilute salience; the value is one ordered
  correction pass.
- **Forks run at the parent model's cost.** An Agent-tool fork ignores a model
  override and inherits the whole conversation, so each in-scope corrector's
  audit runs at the parent model over the full transcript; the wave cap bounds
  burst, not per-fork cost. Keeping the `never` tier out and relevance-gating
  the situational tier are what hold the fan-out small.
- **`tighten-your-output` stays last** — tightening before the other
  corrections would tighten text they then rewrite.
- **A situational skip is reported, not silent** — the user sees what was
  left out and why.
