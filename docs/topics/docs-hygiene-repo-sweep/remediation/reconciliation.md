# Wave 2 reconciliation

How eight lanes' findings become one ordered edit plan without two agents writing the same file.

## What wave 1 actually produced

| Lane | Candidates examined | Findings | Applied |
|---|---:|---:|---|
| `L1-derivability` | 1302 files | 3 | yes, wave 3 step 1 |
| `L2-progressive-disclosure` | 1302 files | 200 | splits in flight |
| `L3-ssot` | ~352 instances | 26 clusters, 13 remediated | pending |
| `L4-encapsulation` | 407 non-self citations | 89 | pending, partly dissolved by E1 |
| `L5-noise` | 5858 candidates | 10 | pending |
| `L6-compress` | 1302 files | 35 files, 312 bytes | 34 fixed at the generator |
| `L7-write-for-agents` | 21 predicates | 13 | pending |
| `L8-write-for-humans` | 308 human-audience files | pending | pending |

The striking number is the rejection rate, and it is the sweep's main empirical result. `L5` rejected
5847 of 5858 candidates. Its largest shape, `enum-list`, contributed 4568 candidates and zero
findings: a census showed the shape's canonical form has no instances here, so the defect is absent
rather than unmatched. `L6` found 312 bytes of defensible compression across 17 MB. `L1` found 3
actionable files in 1302.

Three lanes independently reached the same explanation and cited the same in-repo measurement,
`docs/specs/d1-model-already-knows-measurement.md`, whose verdict on a comparable cue-based
judgment class is "never rule on it". This corpus is written by the very skills auditing it, and was
swept repo-wide two commits before this one. A sweep that produced hundreds of edits here would be
producing damage, not hygiene.

## Contention

157 corpus files carry findings from more than one lane. Counting citations overstates it: the
most-cited files are the repo's own meta-documents, and most of those citations are lanes invoking
them as authority rather than targeting them.

| Files | Lanes citing |
|---:|---|
| 1 | 7 |
| 3 | 6 |
| 2 | 5 |
| 10 | 4 |
| 41 | 3 |
| 100 | 2 |

The heaviest genuine lane pairs are `L2`+`L3` (38 files), `L2`+`L8` (30), `L2`+`L4` (23) and
`L2`+`L5` (23). `L2` dominates because a split changes the file every other lane wants to edit.

## The ordering, and why each step precedes the next

This is a dependency chain, not a preference. Each step changes state the next step reads.

1. **`L1` deletions and pointer conversions.** Removing a file moots every other lane's findings
   against it. `L5` had a finding voided this way mid-run, which is the mechanism working.
2. **`L2` splits.** Creates the spoke files that steps 3 and 4 cite. A citation rewritten before the
   split targets a path about to move.
3. **`L3` deduplication**, over the post-split structure, because a split can move one of the
   duplicated spans.
4. **`L4` citation rewrites**, over the final paths. Line numbers from wave 1 are stale by this
   point and must be re-resolved rather than trusted.
5. **One merged in-file prose pass** carrying `L5`, `L6`'s remainder, `L7` and `L8` together.

Step 5 is merged deliberately. Those four lanes all edit prose inside files that survive steps 1 to
4, and running them separately would mean four passes over the same file with three chances to
collide. Merged, exactly one editor owns any given file and applies that file's findings from all
four lanes in one edit. Their combined volume, well under a hundred findings, is small enough that
this costs nothing.

## Hazards that cross every lane

- **Generated blocks.** Roughly 70 lines in each of 34 plugin READMEs sit between
  `<!-- BEGIN GENERATED: plugin options ... -->` and its `END` marker, emitted by
  `scripts/sync-plugin-options-docs.py` and checked in CI by `plugin-options-docs-gate`. **Reject any
  edit whose line falls inside such a block.** Hand-edits there fail CI and revert on the next sync.
  `L6` found this the hard way; its own 34 findings were all inside these blocks and were fixed at
  the generator instead.
- **Stale line numbers.** Every finding's `path:line` was recorded before steps 1 to 4 moved
  content. Re-resolve by matching the quoted text, not by seeking the line number.
- **Fixtures are not prose.** `L7` found 62 rows under `evals/fixtures/` and `scripts/fixtures/`
  that are test data, several deliberately defective, including a file whose textbook violation is
  the point of the fixture. Editing one breaks the test that asserts it. These need excluding from
  every in-file lane, not just `L7`.
- **Mandated duplication.** `L3` found that plugin contracts are carried inline at every adopting
  site on purpose, because plugins ship without the marketplace repo
  (`docs/conventions/untrusted-content/README.md:34`). Repetition here is portability, not a defect.
- **Quoted material.** Several corpus files quote external authors verbatim. Compressing or
  de-noising a quotation misattributes it. `L6` resolved 12 `UNCERTAIN` rows to `SKIP` on this
  ground alone.

## Rulings applied

Both live in `escalations.md` with their full reasoning.

- **E1**: the plugin, not the skill, is this repo's unit of distribution. Intra-plugin sibling-skill
  citation in the anchored form is legal here; cross-plugin citation into skill privates is not;
  bare relative cross-skill paths stay defects; heading anchors stay private. Dissolves part of
  `L4`'s 89 and requires a clarifying edit to both documents in wave 3.
- **E4**: `write-for-agents` disclaims skill *authorship*, not prose inside an authored skill body.
  Releases `L7`'s 8 disputed findings. Applied.

## What does not get applied

Recorded so the next sweep does not re-derive them.

- `L3` proposes **no new SSOT artifact**. Every remediated cluster resolves in place by citing an
  existing owner. Three clusters passed the Rule of Three and were still resolved in place.
- `L6`'s article drops, passive-to-active conversions and nominalization rewrites are all declined,
  on a measured 9-of-9 revert record at 0.02 to 0.4 percent yield.
- `L5`'s `negation` population beyond the 7 individually read instances is not issued. Its sample put
  precision at 11.7 percent, so issuing the unread remainder would mean roughly 910 spurious edits to
  instruction surfaces.
- `L1` deletes none of `docs/topics/**`. Nine of eleven slices carry open phases, and pruning them is
  already owned elsewhere with a graduation step this sweep would skip.
