# L5-noise: `preamble`

**4 candidates in, plus 8 recovered by a recall check. 12 examined. 0 findings out.**

This is the one shape where the detector has a measurable recall gap, so the examined set is three
times the candidate set.

## Recall gap

The detector matches `Why this file exists`, `Motivation`, and `Rationale` as headings. A
corpus-wide grep for the heading family found **8 instances of `## Why this exists`** that the
detector did not emit, twice the candidate count. All eight were adjudicated alongside the four
candidates.

## Diataxis classification

The shape's treatment is a Diataxis call: KEEP on an Explanation-quadrant file (rule bodies, ADRs,
convention rationale), STRIP on a Reference-quadrant file (data tables, registries, cheat-sheets),
replacing with a one-sentence orientation.

Every one of the twelve sits on an Explanation-quadrant surface. None is a data table, registry,
or cheat-sheet.

| Path and line | Heading | Quadrant | Decision |
|---|---|---|---|
| `docs/conventions/topic-docs/README.md:14` | `## Why this exists` | convention rationale | KEEP |
| `plugins/computer-use/README.md:12` | `## Why this exists` | plugin README, human audience | KEEP |
| `plugins/mutation-testing/README.md:13` | `## Why this exists` | plugin README, human audience | KEEP |
| `plugins/overengineering/README.md:23` | `## Why this exists` | plugin README, human audience | KEEP |
| `plugins/claude-memory/skills/audit/context/update.md:6` | `## Why this exists` | explains why a refresh workflow exists | KEEP |
| `plugins/repo-hygiene/skills/clean/context/clean-batch.md:9` | `## Why this exists` | justifies a capability's existence against the hand-rolled alternative | KEEP |
| `plugins/repo-hygiene/skills/clean/context/git-tree-reset-batch.md:8` | `## Why this exists` | names the two defects the capability closes | KEEP |
| `plugins/work-items/tools/work-item-tracker/adapters/linear/schema-check/README.md:5` | `## Why this exists` | records a descoped acceptance criterion and its substitute evidence | KEEP |
| `plugins/knowledge/skills/video-digest/templates/companion-source-brief.md:5` | `## Rationale` | template data slot, not a preamble | KEEP |
| `plugins/docs-hygiene/skills/audit-noise/evals/fixtures/noisy-rule-snippet.md:3` | `## Why this file exists` | detector eval fixture | corpus-excluded |
| `plugins/docs-hygiene/skills/audit-noise/evals/fixtures/recall-paraphrases.md:5` | `### Why this file exists` | detector eval fixture | corpus-excluded |
| `plugins/docs-hygiene/skills/audit-noise/evals/fixtures/recall-paraphrases.md:9` | `## Motivation` | detector eval fixture | corpus-excluded |

### Two calls worth showing

`plugins/repo-hygiene/skills/clean/context/git-tree-reset-batch.md:8` is load-bearing rather than
motivational. Verbatim:

```text
## Why this exists

A hand-rolled `ghq list` reset loop `reset --hard`s repos it was meant to skip: a
skip entry written with one path separator silently fails to match the same path
carrying the other, and unstaged work in the repo it hits is unrecoverable.
`tree-batch` is the supported capability that closes both defects — skip-matching
is separator-agnostic so an entry matches whichever separator the path carries,
and the dirty guard is on by default so a repo with uncommitted work is skipped
rather than reset.
```

That section is the argument for not hand-rolling the loop, and it names the two guarantees the
tool provides. A one-sentence orientation would delete a safety argument.

`plugins/knowledge/skills/video-digest/templates/companion-source-brief.md:5` is not a preamble at
all. It is a template field:

```text
## Rationale

{{RATIONALE}}
```

The heading names a slot filled at queue time with why these companion sources were chosen. The
shape targets an opening section explaining the file's own motivation; this explains the
instance's content.

## Detector defect worth reporting

The preamble heading matcher should cover `Why this exists` alongside `Why this file exists`. It
misses the more common of the two forms in this corpus by 8 to 1.

## Cross-lane observations

- **L2-progressive-disclosure.** All eight recovered instances are section headings on files L2
  may split. If a split moves one, the heading travels with its section.
- **L1-derivability, L3-ssot, L6-compress.** Nothing.
