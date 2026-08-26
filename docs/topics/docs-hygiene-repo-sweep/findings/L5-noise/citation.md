# L5-noise: `citation`

**7 candidates in. 0 findings out. 7 rejected. Plus a recall check, no additions.**

All 7 read in full.

## Rejections

| Path and line | Grounds |
|---|---|
| `plugins/docs-hygiene/skills/audit-noise/SKILL.md:53` | shape self-definition, the row that names the cues |
| `plugins/code-tidying/skills/audit-comment-residue/SKILL.md:36` | sibling skill's shape-definition row, same self-match |
| `plugins/discipline/skills/point-dont-copy/SKILL.md:66` | the phrase used generically, not a dated citation |
| `plugins/docs-hygiene/skills/rename-references/context/audit-modes.md:119` | worked example with placeholder filenames |
| `docs/topics/fresh-eyes-checkpoint-audit/PLAN.md:57` | plan amendment record, the ADR-amendment exemption in substance |
| `plugins/docs-hygiene/skills/audit-noise/evals/fixtures/noisy-rule-snippet.md:12` | detector eval fixture, corpus-excluded |
| `plugins/docs-hygiene/skills/audit-noise/evals/fixtures/recall-paraphrases.md:13` | detector eval fixture, corpus-excluded |

### `plugins/discipline/skills/point-dont-copy/SKILL.md:66`

```text
Owning a fact is not copying it. A config genuinely adapted for this repo, a
constraint this project itself pins, a one-shot dated research deliverable,
and an error string empirically observed in this environment are content
THIS project authors and owns.
```

The cue `empirically observed` appears inside a definition of a category of owned content. There
is no date, no incident, and no provenance attribution. Matching the words, not the shape.

### `plugins/docs-hygiene/skills/rename-references/context/audit-modes.md:119`

```text
- **Orphan (broken):** path-form match where path does not exist on disk after rename. Verify via
  Glob/Read. E.g. `[text](context/old.md)` matched but `context/old.md` was renamed to
  `context/new.md` — link now broken
```

`old.md` and `new.md` are placeholders in a worked example of the audit algorithm. The skill's own
dismissal grounds cover a worked example matching its own pattern.

### `docs/topics/fresh-eyes-checkpoint-audit/PLAN.md:57`

```text
3. Ten retrofits merged: session-flow:retro, code-tidying:tidy (Phase G), codebase-health:audit
   (Phase 6), claude-config:audit-automation-gaps *(renamed from automation-gaps by #371, same-day
   merge — corrected 2026-07-19)* (step 6), discovery:research (outcome gate subjective
```

This is a correction record attached to a plan goal condition. Four lines above it, the same
document carries an explicit amendment with ratification language:

```text
*(Amended 2026-07-19 during /architect: the original "FAILs a skill that declares a
judgment step without conformant delegation" contradicted the fuzzy-tier=WARN decision locked
this session; plan-reviewer finding #1. Approval of this plan ratifies the amendment.)*
```

Corrections to a plan's goal conditions are recorded inline in this repo so that approval covers
them. That is the ADR amendment block exemption arriving on a plan artifact rather than an ADR.
Stripping the parenthetical would remove the record that the criterion was corrected rather than
authored as-is.

## Recall check

A corpus-wide grep over all 1218 scanned files for the shape's semantic forms beyond the
detector's literals:

```text
empirically observed
we pivoted (from|to)
was renamed (to|from)
formerly (known as|called)
used to be called
```

returns the same two non-fixture, non-self-definition hits already adjudicated above. No recall
gap in this shape.

## Cross-lane observations

- **L1-derivability, L3-ssot, L6-compress.** Nothing.
