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
| `/re-anchor:follow-our-standards` | Alignment to the consuming org's engineering conventions |
| `/re-anchor:point-dont-copy` | Pointer over copy — cite the living source, don't duplicate it |
| `/re-anchor:reason-dont-recite` | Interrogate inherited content — precedent describes, it doesn't justify |

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
/re-anchor:do-your-research deep   # fan out subagents to verify every load-bearing claim
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

No `userConfig`. No persistent state, no network calls — each skill reads
the conversation and the consuming project's own instruction layer, and
resolves any external standards source the consumer declares.
