# discipline

A Claude Code plugin bundling discipline correctors for one cohesive
capability: pulling a working session back onto a standing discipline that
has lost salience. Each skill re-anchors ONE discipline, applies it to the
current conversation, and corrects what drifted — auditing both the work in
flight and the pre-existing state and choices it trusts. (Some correctors
audit the conversation's own output; others audit state and decisions that
predate the session — a config already on disk, a tool already chosen —
because existing state is not evidence of its own correctness. Scope
recorded as a deliberate widening from the original "work in flight" framing,
a `/discipline:reason-dont-recite` finding on that boundary.)

Firing a corrector is a re-anchor, not an accusation. Reaching for one as a
gentle reminder — before the work, or just to set posture — is a
first-class use, and the audit may honestly return clean.

| Skill | Discipline it re-anchors |
|---|---|
| `/discipline:do-your-research` | Research and no-assumptions before assertion |
| `/discipline:do-your-research-deep` | The verification-fan-out tier of do-your-research — a typed full inventory of the session's claims, verified at a configurable depth |
| `/discipline:follow-our-standards` | Alignment to the consuming org's engineering conventions |
| `/discipline:point-dont-copy` | Pointer over copy — cite the living source, don't duplicate it |
| `/discipline:reason-dont-recite` | Interrogate inherited content — precedent describes, it doesn't justify |
| `/discipline:tighten-your-output` | Terseness — fewer words or lines with no loss of meaning or correctness |
| `/discipline:recheck-against-upstream` | Existing state is not self-justifying — audit config, code, and infra against current official upstream docs |
| `/discipline:recheck-against-upstream-deep` | The fan-out tier of recheck-against-upstream — subagents compare a whole subsystem against upstream, doc-by-doc |
| `/discipline:pick-for-the-problem` | Selection fitted to the problem — not reached for out of habit, availability, incumbency, or preconception |
| `/discipline:mind-your-maxims` | Cooperative communication — Grice's maxims plus the AI-augmented transparency maxim |
| `/discipline:script-the-deterministic-work` | Script deterministic sub-work — run it, then reason over the output |
| `/discipline:use-your-skills` | Actually use the skills in context — scan the listing, invoke the fitting skill, name skills when delegating |
| `/discipline:reuse-or-replace` | Anti-fragmentation — reuse the established way or openly replace it, never silently stand up a second parallel way |
| `/discipline:scrutinize-dont-coast` | Adversarial self-scrutiny — stop coasting on your own recent output; re-examine it through a fresh-context pass and remediate with the user |

The shared method — re-anchor, audit the work in flight, correct forward,
report — lives once at plugin scope in
[`context/re-anchor-audit-correct.md`](context/re-anchor-audit-correct.md);
each skill carries only its own delta.

Beyond the correctors, the plugin ships one **composed runbook** — a declared
second species that is *not* a corrector and re-anchors no discipline of its
own:

| Runbook | What it composes |
|---|---|
| `/discipline:sweep-all` | Runs the whole bundle as one pass — fans out an audit-only subagent per in-scope corrector, then applies the corrections on the main thread in a fixed order; at session start it reports a cheap posture digest instead |

## What each skill does

### do-your-research

Re-anchors research and verification discipline: assert nothing without a
source, verify every concrete specific against the live environment or an
authoritative source, frame the problem before the solution, never act on
ambiguity, and treat training-data recall as unverified. Audits recent
turns for unbacked claims and skipped verification, then corrects forward.

```shell
/discipline:do-your-research        # re-anchor + audit + correct
```

### do-your-research-deep

The verification-fan-out tier of `do-your-research` — same research
discipline, heavier execution. Enumerates a **typed full inventory** of the
session's claims — assumptions, asserted facts, concrete specifics, and
load-bearing premises, as a checklist so coverage is provable — and verifies
each against a primary source, throttled in bounded waves so a claim-heavy
session does not trip a burst overload. Reports one ledger row per inventory
item (no silent drops), each carrying verdict, source, source tier, consensus
count, and recency. Verification depth is **configurable** (this is the
expensive tier by design): `tiered` by default (fan subagents out only over
load-bearing items, resolve the rest inline) or `full` (subagent-verify every
item), set via the `research_deep_verification` `userConfig` option and
overridable by an invocation argument. Reserved for when the accumulated
claims justify the subagent cost; for a single inline re-anchor + audit, use
`do-your-research`. It is a sibling skill rather than a `deep` argument because
the subagent fan-out is a heavier execution tier (mirrors the
`/discovery:research-deep` precedent).

```shell
/discipline:do-your-research-deep         # typed inventory, verified at the configured depth
/discipline:do-your-research-deep full    # override the default: subagent-verify every item
```

### follow-our-standards

Re-anchors alignment to the consuming organization's engineering standards.
Resolves the standards source the consuming project declares (a shared
standards repo, a conventions tree) with progressive, relevance-routed
loading, re-asserts the core principles — DRY / single source of truth, low
coupling and high cohesion, change-together-lives-together, SOLID, clean
code — audits the work against them with doc citations, and respects a
declared managed / locally-owned seam.

```shell
/discipline:follow-our-standards    # resolve + re-anchor + audit + correct
```

### point-dont-copy

Re-anchors pointer-over-copy discipline: cite or link the living source
rather than restating the facts it owns (a paraphrase drifts the same as a
verbatim copy), point at public contracts rather than internal names, and
phrase duties open-ended rather than as closed capability lists.
Duplication starts at two copies. Audits the work for copied content,
internal-name coupling, and closed enumerations, then corrects by pointing.

```shell
/discipline:point-dont-copy         # re-anchor + audit + correct
```

### reason-dont-recite

Re-anchors incumbency discipline: inherited content — a repo's docs,
conventions, structure, processes — is evidence of what is, never a
self-justifying argument for what should be. A choice whose only support is
precedent ("that's how it's done here") or "I don't know why" earns a
first-principles re-derivation, not compliance. The distinct axis from
do-your-research: that skill acquires external evidence you lack; this one
questions internal evidence you inherited. A standards disagreement it
surfaces routes upstream via follow-our-standards.

```shell
/discipline:reason-dont-recite      # re-anchor + audit + correct
```

### tighten-your-output

Re-anchors terseness discipline: say markdown in fewer words with no
semantic loss, write code in fewer lines when readability holds. The code
side re-anchors the consuming org's simpler-code convention (named failure
modes; constraints — clarity, tests, error handling, conventions,
observability — never traded for line count); prose terseness usually has no
dedicated standards doc, so the skill flags that gap rather than inventing a
rubric. Audits the work for avoidable verbosity and tightens only where the
reduction is free; routes batch work to a compress capability (prose) and a
simplify capability (code).

```shell
/discipline:tighten-your-output     # re-anchor + audit + correct
```

### recheck-against-upstream

Re-anchors the discipline that existing state — config, code, docs, infra —
is evidence of what is, never proof it still matches the upstream it depends
on. Fetches the CURRENT official upstream docs for the surface in play,
diffs the repo's state against them, and classifies each divergence: a
**gap** (docs say X, we do Y, no recorded rationale — including deprecation
and version drift), a **deliberate divergence** (rationale recorded in
repo docs / an ADR — re-checked only for whether it still holds, since
upstream may have obsoleted it), or an **undocumented divergence** (looks
intentional, no rationale, needs the human's call — routed to the repo's
ADR/docs convention). Reports what was compared versus skipped; unverified
conformance is not "clean". A distinct axis from `reason-dont-recite`
(internal precedent) and `follow-our-standards` (the org's own standards):
this measures against the external vendor's docs.

```shell
/discipline:recheck-against-upstream        # re-anchor + audit + correct
```

### recheck-against-upstream-deep

The fan-out tier of `recheck-against-upstream` — same discipline, heavier
execution. Enumerates every upstream-dependent surface in a subsystem,
framework, or repo and dispatches fresh-context subagents doc-by-doc,
throttled in bounded waves, to compare each against its current upstream
docs, then reports an inline divergence ledger. Offers to route gap and
undocumented findings to a work-items capability when one is installed
(degrading to a prose offer); deliberate, still-valid divergences stay
report-only. Checkpoints the partial ledger to a durable topic-memory slice
mid-run when one exists, for crash safety — the only persistence it performs.
It is a sibling skill rather than a `deep` argument because the subagent
fan-out is a heavier execution tier, fixed in frontmatter (mirrors the
`/discovery:research-deep` precedent).

```shell
/discipline:recheck-against-upstream-deep   # fan out subagents doc-by-doc over a subsystem
```

### pick-for-the-problem

Re-anchors selection discipline for a tool, library, framework, language, or
approach: the choice fits the problem, not the reflex. Names the four
selection sins — **habit** ("I always use X"), **availability** ("X is at
hand"), **incumbency** ("the repo already uses X"), and **preconception**
("I came in believing X") — and replaces them with the discipline: define
the actual problem first, survey the field, and walk the preference ladder
native (covering the requirements and plausible future ones) > official /
authoritative > vetted third-party. Every dependency is a coupling point
priced at adoption time (abandonment, pricing pivot, license change,
security posture, exit cost); building what already exists is a finding.
When the evaluation is load-bearing it routes to a research capability
(`/discovery:research`, `-deep` for a big surface) rather than a verdict from
memory, degrading to an explicit cited research pass. Fires at choice-time
and over choices already embedded in the work.

```shell
/discipline:pick-for-the-problem    # re-anchor + audit + correct
```

### mind-your-maxims

Re-anchors cooperative-communication discipline. Points at the primary
sources for the maxims rather than restating them — Grice's Cooperative
Principle and the AI-augmented transparency maxim
([arXiv:2403.15115](https://arxiv.org/abs/2403.15115)) — and audits recent
responses AND agent-authored artifacts (docs, PR bodies, prompts) on four
axes it owns: **Quantity** both directions (omitted asked-for detail is a
finding, as is padding), **Relation** (answer the question actually asked —
no adjacent answers, tangents, or buried ledes), **Manner** (unambiguous
references, ordered structure, clarity), and **Transparency** (disclose
uncertainty and knowledge/capability boundaries). Truthfulness delegates to
`do-your-research`; pure verbosity to `tighten-your-output`. Benevolence is a
deliberate out-of-scope exclusion (platform / safety-layer territory). Valid
as posture-setting anytime and as an audit once output exists.

```shell
/discipline:mind-your-maxims        # re-anchor + audit + correct
```

### script-the-deterministic-work

Re-anchors the discipline of offloading deterministic sub-work to a script:
when a sub-task's answer follows mechanically from its input (counting,
diffing, sorting, transforming, matching, sweeping, arithmetic), write and
run a script, read its real output, and reason only afterward over that
output. The tier boundary re-anchors the consuming org's enforceability-tiers
convention — deterministic work gets scripted, detect-then-judge gets only
its detect half scripted while the verdict stays judgement, and
reasoning-only is never scripted. The in-task "script it now" application has
no standards doc yet, so the skill flags that gap. The discipline runs in
both directions: analysis reasons over a script's output, and generation
emits a deterministic scaffold (a PR body, an issue, a report, config
boilerplate) from a script or a native template so model output is reserved
for the judgment slots. Distinct from a standing-automation capability:
recurring checks belong in a hook, this corrector owns the one-off,
session-time script.

```shell
/discipline:script-the-deterministic-work   # re-anchor + audit + correct
```

### use-your-skills

Re-anchors skill-use discipline: the skill listing (every skill's name and
description) is in context so the fitting skill gets invoked, not reinvented.
Scans the listing against the conversation and the task, invokes the skill that
already owns a procedure rather than improvising it, and — because a fresh
non-fork subagent does not inherit the parent's listing — names the relevant
skills in a delegation prompt, recommending a custom subagent's `skills:`
preload for a discipline it should always carry. Audits recent work for a skill
that should have fired and did not, and corrects by invoking it now. Description
quality routes to `/skill-quality:check` and listing-budget overflow to
`/claude-config:audit`; this skill audits use, not surfaceability. A per-prompt
`UserPromptSubmit` routing hook is deliberately deferred.

```shell
/discipline:use-your-skills         # re-anchor + audit + correct
```

### reuse-or-replace

Re-anchors anti-fragmentation discipline: when an established way of doing
something already exists, new work reuses it or openly replaces it (migrate the
uses, record the decision) — it never silently stands up a second, parallel way
alongside. The sin is the silent second way, not divergence: replacing the
established way is first-class when evidence backs an improvement or its
rationale is missing, incumbency-only, or stale, and blind trust in the status
quo is explicitly bad. Divergence is allowed but owes a recorded rationale
proportional to blast radius — an ADR/docs entry for durable changes, a
PR/commit note for small ones; no recorded reason is the finding. Scope is the
unlintable approach level (idioms, structure, naming shapes, error handling,
doc formats, process); mechanical style belongs to linters. Distinct from
`reason-dont-recite` (evaluation-side — is the inherited convention justified?)
and carved out from `pick-for-the-problem` (which owns tool and dependency
selection, where matching the incumbent is a selection sin, not a consistency
win).

```shell
/discipline:reuse-or-replace        # re-anchor + audit + correct
```

### scrutinize-dont-coast

Re-anchors a *meta* discipline rather than a single content axis: don't coast
on your own recent output — confidence that work is sound is not evidence that
it is. The load-bearing adversarial re-examination runs in a fresh-context
(non-fork) subagent blind to the reasoning that produced the output. It makes
two deliberate, documented deltas to the shared loop — it **stops the
trajectory first** and **remediates with the user** rather than autonomously.
Negative routing: pre-implementation plan stress-tests go to
`/planning:devils-advocate`, review checkpoints to `/review:quality-gate`, and
single-axis flaws to the sibling that owns them.

```shell
/discipline:scrutinize-dont-coast   # re-anchor + audit + correct
```

### sweep-all (composed runbook)

The plugin's one **second species** — a router that composes the correctors,
carrying no discipline of its own. Two modes: at conversation start it derives
a cheap posture digest from the skill listing and each corrector's tier
metadata (no bodies load, no audit); mid-session it runs the full pass —
fanning out a conversation-inheriting fork subagent per in-scope corrector for
an audit-only walk, then applying the corrections once on the main thread in a
fixed order (`use-your-skills` first, `tighten-your-output` last). The full
pass preflights that its subagents really do inherit the conversation and
degrades to the posture digest when they do not — auditing blind would write
fabricated corrections to the working tree. Membership
is resolved by reading each corrector's colocated `metadata.discipline-batch`
tier (`core` / `situational` / `never`) and `discipline-batch-rank` — the
runbook names no members — layered with an optional `batch_exclude` /
`batch_promote` / `batch_demote` user overlay. It files no outward artifact and
preserves every member's human gate.

```shell
/discipline:sweep-all   # batch re-anchor, or a session-start posture digest
```

## Consumer conventions

The correctors adapt to the consuming repo rather than imposing a source
of truth:

- **Declared discipline wins.** Each skill re-anchors the discipline the
  consuming project states in its own `CLAUDE.md` / `.claude/rules/` when
  it declares one, and audits against that text.
- **Graceful degradation.** When the consumer declares no such rules, each
  skill re-anchors a concise portable baseline it states in its own body —
  fully useful in a project with rich standing rules and still useful in
  one with none.
- **Citations trace to what resolved.** A finding cites the source
  actually read this session, never an assumed path.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install discipline@melodic-software
```

## Configuration

No persistent state — each skill reads the conversation and the consuming
project's own instruction layer. `follow-our-standards` may fetch a remote
standards source when the consumer declares one and no local checkout exists.

The correctors themselves are zero-config. Two skills expose optional
`userConfig` scalars. The `sweep-all` runbook adds three that
overlay batch membership without editing any corrector — each a comma-separated
list of corrector names, empty by default (tiers run exactly as declared) — and
`do-your-research-deep` adds one that sets its verification depth:

| Option | Effect |
|---|---|
| `batch_exclude` | Drop these correctors from the batch |
| `batch_promote` | Run these situational correctors every session instead of gating them on relevance |
| `batch_demote` | Run these core correctors only when relevant instead of every session |
| `research_deep_verification` | `do-your-research-deep` verification depth: `tiered` (default — subagents only over load-bearing items) or `full` (subagent-verify every item); an invocation argument overrides it |

Set them through Claude Code's native plugin-config flow
(`/plugin configure discipline`); they are personal scalars, not repository
configuration. `/discipline:setup check` reports the effective configuration
read-only (it never writes config — reconfiguration stays the native flow).
Batch membership and order otherwise live in each corrector's own colocated
tier metadata (`metadata.discipline-batch` + `discipline-batch-rank`), so changing
a shipped tier is a PR to that corrector.
