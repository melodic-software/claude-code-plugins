# L5-noise: `ticket-pr-residue`

**7 candidates in. 0 findings out. 7 rejected.**

All 7 read in full. The shape's Tier 2 default exists so a reviewer rules on an inline
parenthetical rather than the scanner. This is that ruling.

## Discriminator

The shape targets **backward** provenance: a tracker reference offered as the reason the prose
says what it says, of the form `See PR #45 for the rationale`. Its sanctioned carve-out is
**forward** work: a task-list item or a `TODO(#123)` marker, where the reference is the actionable
part of the line.

Six of the seven candidates are forward pointers written in prose rather than in a checkbox or a
`TODO(...)` marker. Each names work that has not shipped, and each changes what a reader should do
if it does ship. That is the carve-out's substance arriving in a form the carve-out's syntax does
not cover.

## Rejections

| Path and line | Quoted cue | Grounds |
|---|---|---|
| `plugins/claude-config/skills/audit/reference/audit-checklist.md:151` | will exceed a default Bash tool timeout (tracked in #2216) | forward pointer, and the sentence continues into the workaround |
| `plugins/disk-hygiene/README.md:81` | observed on at least one Claude Code build (producer-reported; see issue #1105) | forward pointer, and the next sentence routes a troubleshooting reader to that issue |
| `plugins/source-control/skills/babysit-prs/SKILL.md:199` | the machine-enforced fix for that displacement bypass is tracked in #571 | forward pointer explaining why the adjacent rule is agent discipline rather than machine-enforced |
| `plugins/source-control/skills/babysit-prs/reference/runbook-cycle.md:61` | with the machine-enforced fix tracked in #571 | same, second site |
| `plugins/work-items/skills/triage/SKILL.md:122` | Formalizing this as the autonomous-mode contract ... is tracked in #459 | forward pointer to unshipped formalization |
| `prompts/loops/loop-lane-prompts.md:1283` | its enforcement wiring into the lane's merge partition is tracked in #1695 | forward pointer to unshipped wiring |
| `plugins/docs-hygiene/skills/audit-noise/evals/fixtures/noisy-rule-snippet.md:24` | See PR #45 for the ordering rationale. | detector eval fixture, corpus-excluded |

The one candidate matching the shape's canonical backward form is the eval fixture, which exists
precisely to exhibit it.

Two representative instances in full, so the distinction is checkable:

```text
plugins/disk-hygiene/README.md:80-83
scope a skill hook to the component's lifetime, but session-long firing of the belt has been
observed on at least one Claude Code build (producer-reported; see issue #1105). If unrelated
commands are denied after a clean run ends, start a new session and see that issue.
```

```text
plugins/work-items/skills/triage/SKILL.md:122
The autonomous branch is the mode the AI disclaimer already anticipates: a session that mutates
without a human turn. The two are one mode, not a contradiction. Formalizing this as the
autonomous-mode contract, codifying that standing-lane rules constitute direction, is tracked
in #459.
```

Neither is provenance for the surrounding claim. Both name work whose landing changes the
instruction.

## Detector observation

The carve-out is written syntactically (task-list checkbox, `TODO(#123)` family) but its
justification is semantic: the reference is the actionable part of the line. In prose, a bare
`tracked in #N` is the same statement without the checkbox. Extending the carve-out to that family
(`tracked in #N`, `is tracked in #N`, `see issue #N` followed by an actionable clause) would have
suppressed 6 of these 7 with no loss.

## Cross-lane observations

- **L3-ssot.** The `#571` displacement-bypass sentence is duplicated between
  `plugins/source-control/skills/babysit-prs/SKILL.md:199` and
  `plugins/source-control/skills/babysit-prs/reference/runbook-cycle.md:61`.
- **L1-derivability, L6-compress.** Nothing.
