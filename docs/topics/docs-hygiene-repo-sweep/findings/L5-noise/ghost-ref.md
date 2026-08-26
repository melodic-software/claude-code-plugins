# L5-noise: `ghost-ref`

**36 candidates in. 3 findings out. 33 rejected.**

Every one of the 36 was read in its own file context and its cited path tested for existence on
disk. No sampling.

## Discriminator

The shape's premise is stated in its own definition: the citing document outlives the slice, so
slice retirement breaks the reference. Two tests follow from that, applied to every candidate:

1. **Does the cited path exist?** A path that resolves today is a working reference.
2. **Does the citer outlive the cited slice?** A slice document citing its own slice, or a sibling
   slice it is pruned alongside, does not satisfy the premise. Nothing survives to dangle.

A candidate is a finding only when the path does not resolve **and** the citer is durable.

## Path-existence check

| Cited slice | On disk |
|---|---|
| `docs/topics/pocock-course-lanes/` | **missing** |
| `docs/topics/boris-video-absorption/` | missing, self-annotated as pruned in #1459 |
| `docs/topics/github-plugin-candidates/` | missing, self-annotated as pruned in #1459 |
| `.work/**` (all forms) | **never present**, gitignored at `.gitignore:29` |
| `.claude/notes/` | not cited by any candidate |
| the seven live slices listed below | present |

Live slices confirmed present: `docs/topics/ladder-climb-roadmap/`, `docs/topics/autonomy-ignition/`,
`docs/topics/fresh-eyes-checkpoint-audit/`, `docs/topics/plugin-audit-port/`,
`docs/topics/interview-batch-rounds/`, `docs/topics/context-engineering-claude-5/`,
`docs/topics/ai-adoption-ladder/`.

## Findings

All Tier 2, the shape's default. Treatment is the shape's 3-way classify: promote, replace with a
durable pointer, or strip.

### 1. `docs/specs/invocation-mode-doctrine-brief.md:5`

Verbatim, lines 5 to 7:

```text
`docs/topics/pocock-course-lanes/PLAN.md` on branch `claude/plan-mode-discussion-55kszx`, steering
rows now in `docs/upstream/aihero-course.md` — the interim steering record dissolved into it at
the lane 6 harvest).
```

Durable spec, pruned slice, and a branch name that is itself not durable. The sentence already
carries the durable replacement one clause later, the pointer to
`docs/upstream/aihero-course.md`, so the ghost path is redundant with its own fix.

**Remediation.** Strip the slice path and the branch name. Keep the issue link and the durable
pointer. Replacement text:

```text
chain contract: the steering rows in `docs/upstream/aihero-course.md`, which the interim
steering record dissolved into at the lane 6 harvest).
```

### 2. `docs/specs/invocation-mode-doctrine-brief.md:8`

Verbatim, lines 7 to 8:

```text
Interview ledger:
`.work/invocation-mode-doctrine/interview-checklist.md` (8/8 answered, register gate clean).
```

`.work/` is gitignored, so this path has never existed for any reader of this repo other than the
original author's checkout. The parenthetical carries the whole load-bearing content.

**Remediation.** Strip the path, keep the assertion. Replacement text:

```text
Interview ledger: 8/8 answered, register gate clean (memory tier, not committed).
```

### 3. `docs/specs/write-for-agents-brief.md:6`

Verbatim, lines 5 to 8:

```text
answered, register gate clean, **user confirmed the shared understanding 2026-08-17**). Working
ledger: the topic's memory slice (`.work/authoring-steering-skill/`, disposable). The verified
auto-read enumeration feeding the scope statement lives in that slice's `RESEARCH.md` artifact
set; its durable adaptation lands in the skill's reference file at implementation.
```

Worse than finding 2: this one sends the reader to a specific artifact inside an unrecoverable
path for the evidence behind the scope statement.

**Remediation.** Strip the ledger pointer and the sentence that routes to the slice's artifact
set. Replacement text for the last two sentences:

```text
The verified auto-read enumeration behind the scope statement lands in the skill's reference
file at implementation.
```

If that enumeration is load-bearing evidence rather than working notes, promote it into the brief
instead of stripping the pointer.

## Rejections, with grounds

| Grounds | n | Candidates |
|---|---:|---|
| Repo-declared doctrine: provenance, not a promise | 5 | `docs/upstream/aihero-course.md:73,137,179,227,368` |
| Intra-slice or sibling-slice citation | 12 | listed below |
| Cited path exists, with a PR number already attached | 4 | `docs/adr/0005-bound-instruction-surface-work-by-question-not-population.md:326`, `docs/upstream/mattpocock-skills.md:128`, `docs/upstream/mattpocock-skills-v12-map.md:94`, `plugins/docs-hygiene/context/derivability-route-followups.md:37` |
| Self-annotated with the pruning PR, the prescribed treatment | 2 | `docs/topics/loop-engineering-codification/PLAN.md:33,267` |
| Convention roster or worked example | 4 | `docs/conventions/topic-docs/README.md:43`, `docs/conventions/topic-docs/examples/worked-slice.md:44,50,61` |
| Shape self-definition | 2 | `plugins/docs-hygiene/skills/audit-noise/SKILL.md:54,148` |
| Eval fixture | 1 | `plugins/docs-hygiene/skills/audit-noise/evals/fixtures/noisy-rule-snippet.md:15` |
| Memory-tier write destination the citer owns | 2 | `plugins/coupling/skills/reduce/SKILL.md:75`, `plugins/coupling/skills/reduce/reference/ledger.md:5` |
| Delete instruction naming its own target | 1 | `docs/topics/ladder-climb-roadmap/PLAN.md:324` |

### Repo-declared doctrine, 5 candidates

`docs/upstream/aihero-course.md` accounts for 5 of the 36 and every one of them cites the missing
`pocock-course-lanes` slice. The file settles them itself at lines 63 to 70, as a stated
maintainer decision. Verbatim:

```text
**Re-fetch basis for course-lesson claims (deliberate, maintainer-decided):** the lesson pastes
are NOT durably committed — course pages are account-gated, and the maintainer authorized
committing the verbatim texts only on the contract branch's topic slice, pruned before any
merge to this public default branch. A future re-fetch therefore compares against the live
course (account required) or, as the durable proxy, the companion skills repo pinned per the
SSOT — the same regime the sibling
[aihero-shipping-course.md](aihero-shipping-course.md) records. Where a row's basis names a
lesson file under `docs/topics/pocock-course-lanes/lessons/`, that citation is provenance (what
the lane graded, with its as-of date), not a promise the file exists on this branch.
```

Every one of the 5 carries an as-of date or an issue number alongside the path. The skill's own
Org override clause defers to a repo-declared convention over the portable baseline, and this is
one, written on the page the candidates sit on. This is the same class of trap L3-ssot hit with
`docs/conventions/untrusted-content/README.md:34`: repetition and pointer forms that look like
noise are sometimes mandated, and the mandate is written down.

### Intra-slice or sibling-slice citation, 12 candidates

`docs/topics/autonomy-ignition/PLAN.md:3`,
`docs/topics/autonomy-ignition/design/design-resolution.md:11`,
`docs/topics/ladder-climb-roadmap/PLAN.md:87`,
`docs/topics/ladder-climb-roadmap/PLAN.md:94`,
`docs/topics/ladder-climb-roadmap/PLAN.md:302`,
`docs/topics/ladder-climb-roadmap/design/design-resolution.md:10`,
`docs/topics/ladder-climb-roadmap/interview-checklist.md:128`,
`docs/topics/fresh-eyes-checkpoint-audit/PLAN.md:12`,
`docs/topics/fresh-eyes-checkpoint-audit/PLAN.md:123`,
`docs/topics/fresh-eyes-checkpoint-audit/PLAN.md:215`,
`docs/topics/plugin-audit-port/PLAN.md:11`,
`docs/topics/plugin-audit-port/design/design-resolution.md:13`.

Each is a slice document citing its own slice, its own memory tier, or a sibling slice it is
pruned alongside. The shape's premise, a durable citer outliving a retired slice, does not hold:
when the slice goes, the citer goes with it. Every one of these also names its carrying PR
(#794, #796) or labels the target uncommitted inline.

### Memory-tier write destination, 2 candidates

`plugins/coupling/skills/reduce/SKILL.md:75` and its reference file declare
`.work/coupling/coupling-ledger.md` as where the skill writes its ledger, with the surrounding
text reading "Create or ...". An output-path specification is not a reference to an existing
document; nothing dangles, because the skill creates the path when it runs.

## Detector observation

`.work/**` and pruned `docs/topics/**` are exactly what this shape is for, and it found them.
Precision on the low-volume shapes is where this detector earns its keep: 3 of 36 is a far better
yield than either high-volume shape produced from 5797. The rejections are dominated not by bad
matching but by two things the scanner cannot see, a repo-declared doctrine and the direction of
the citer-to-cited lifetime relationship.

## Cross-lane observations

- **L4-encapsulation.** No overlap found. None of the 36 is a private-path citation of the kind
  `docs/PLUGIN-PHILOSOPHY.md:337-342` prescribes, so the doctrine conflict L4 hit does not recur
  in this shape.
- **L1-derivability.** `docs/specs/write-for-agents-brief.md` and
  `docs/specs/invocation-mode-doctrine-brief.md` are both briefs whose working evidence is
  unrecoverable. Whether they still earn their existence is L1's question, and if L1 deletes
  either, findings 1 through 3 moot.
- **L3-ssot.** Nothing.
