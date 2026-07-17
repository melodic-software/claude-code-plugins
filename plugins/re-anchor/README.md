# re-anchor

A Claude Code plugin bundling discipline correctors for one cohesive
capability: pulling a working session back onto a standing discipline that
has lost salience. Each skill re-anchors ONE discipline, applies it to the
current conversation, audits the work in flight, and corrects what drifted.

Firing a corrector is a re-anchor, not an accusation. Reaching for one as a
gentle reminder — before the work, or just to set posture — is a
first-class use, and the audit may honestly return clean.

| Skill | Discipline it re-anchors |
|---|---|
| `/re-anchor:do-your-research` | Research and no-assumptions before assertion |
| `/re-anchor:do-your-research-deep` | The verification-fan-out tier of do-your-research — subagents verify every load-bearing claim |
| `/re-anchor:follow-our-standards` | Alignment to the consuming org's engineering conventions |
| `/re-anchor:point-dont-copy` | Pointer over copy — cite the living source, don't duplicate it |
| `/re-anchor:reason-dont-recite` | Interrogate inherited content — precedent describes, it doesn't justify |
| `/re-anchor:tighten-your-output` | Terseness — fewer words or lines with no loss of meaning or correctness |
| `/re-anchor:script-the-deterministic-work` | Script deterministic sub-work — run it, then reason over the output |

The shared method — re-anchor, audit the work in flight, correct forward,
report — lives once at plugin scope in
[`context/re-anchor-audit-correct.md`](context/re-anchor-audit-correct.md);
each skill carries only its own delta.

## What each skill does

### do-your-research

Re-anchors research and verification discipline: assert nothing without a
source, verify every concrete specific against the live environment or an
authoritative source, frame the problem before the solution, never act on
ambiguity, and treat training-data recall as unverified. Audits recent
turns for unbacked claims and skipped verification, then corrects forward.

```shell
/re-anchor:do-your-research        # re-anchor + audit + correct
```

### do-your-research-deep

The verification-fan-out tier of `do-your-research` — same research
discipline, heavier execution. Enumerates every load-bearing claim made so
far and dispatches fresh-context subagents to verify each against a primary
source, throttled in bounded waves so a claim-heavy session does not trip a
burst overload, then reports a per-claim verified / corrected / unverifiable
ledger. Reserved for when the accumulated claims justify the subagent cost;
for a single inline re-anchor + audit, use `do-your-research`. It is a
sibling skill rather than a `deep` argument because the subagent fan-out is a
heavier execution tier, fixed in frontmatter (mirrors the
`/discovery:research-deep` precedent).

```shell
/re-anchor:do-your-research-deep   # fan out subagents to verify every load-bearing claim
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
/re-anchor:follow-our-standards    # resolve + re-anchor + audit + correct
```

### point-dont-copy

Re-anchors pointer-over-copy discipline: cite or link the living source
rather than restating the facts it owns (a paraphrase drifts the same as a
verbatim copy), point at public contracts rather than internal names, and
phrase duties open-ended rather than as closed capability lists.
Duplication starts at two copies. Audits the work for copied content,
internal-name coupling, and closed enumerations, then corrects by pointing.

```shell
/re-anchor:point-dont-copy         # re-anchor + audit + correct
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
/re-anchor:reason-dont-recite      # re-anchor + audit + correct
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
/re-anchor:tighten-your-output     # re-anchor + audit + correct
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
/re-anchor:script-the-deterministic-work   # re-anchor + audit + correct
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
/plugin install re-anchor@melodic-software
```

## Configuration

No `userConfig`, no persistent state — each skill reads the conversation and
the consuming project's own instruction layer. `follow-our-standards` may
fetch a remote standards source when the consumer declares one and no local
checkout exists.
