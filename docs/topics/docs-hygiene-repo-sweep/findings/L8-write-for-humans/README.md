# L8-write-for-humans, corpus roll-up

Lane: `/docs-hygiene:write-for-humans`. Wave 1, read-only. Scope: the 305 rows in
`inventory/manifest.tsv` carrying `audience=HUMAN`.

## Contents

- [Standard resolved](#standard-resolved)
- [Predicates](#predicates)
- [Findings by predicate](#findings-by-predicate)
- [The two class judgments](#the-two-class-judgments)
- [Reclassifications](#reclassifications)
- [What the numbers look like and why they are small](#what-the-numbers-look-like-and-why-they-are-small)
- [Recall limits](#recall-limits)
- [Cross-lane observations](#cross-lane-observations)
- [Files in this findings set](#files-in-this-findings-set)

## Standard resolved

**`plugins/ai-slop/skills/audit/reference/rewrite-guide.md`**, declared authoritative by
`.claude/rules/vendor-docs-are-not-style.md` and restated in `PLAN.md`. The skill's bundled default
set (Diátaxis, Google developer style, ASD-STE100, Global English) applies only where that guide is
silent, which is on two axes: document mode and sentence-level ambiguity.

Eleven points where the repo guide overrode a named default are recorded in
`standard-resolution.md`. The four that most changed this lane's output:

| Override | Effect |
|---|---|
| Latin abbreviations not adopted | 104 sites of consistent house `e.g.` / `i.e.` usage left alone |
| Semicolons not adopted | Pervasive deliberate house usage left alone |
| Voice and rhythm register-gated | Zero rhythm findings anywhere; the rule is off in reference sections |
| Generated blocks out of scope | `docs/CATALOG.md`, `docs/SKILL-CHEAT-SHEET.md`, and every `### Options reference` table exempt |

Two of the skill's three survives-the-guide rules turned out to be enforced by this repository rather
than by prose review: `scripts/check-skill-count-claims.sh` for real numbers, and the resolved
guide's own filler and plain-word sections for dead words, which route to `ai-slop:audit`.

## Predicates

Twelve, in `predicates.md`, each traced to its passage. Five produced findings.

| Predicate | What it tests | Findings |
|---|---|---:|
| `Am1` | A parenthetical is a full grammatical unit | 18 |
| `M3` | One place per recurring block | 15 |
| `L1` | One thought per sentence, no backtracking | 14, of which 12 carry an exact rewrite |
| `M1` | One document, one mode | 4 |
| `M2` | Release history belongs in the changelog | 4 |
| `Am3` | No slash coordination in prose | 2 |
| `Am2` | No `(s)` plurals in prose | 1 |
| `Am4` | `only` next to the word it changes | 1 |
| `N1` | One name per thing | 1 |
| `A1` | Command with its condition first | 1, no edit recommended |
| `A2` | No banned intensifier in a procedure | 0 |
| `C1` | The real name and the real number | 0 |

Sixty findings in total, one of which (`C-vcs-repo.md` C1) is filed under both `M1` and `M2` and is
counted once in each row above. Several findings carry a secondary predicate named in their group
file; only the primary is counted here.

Beyond the 14 adjudicated `L1` findings, all 442 raw `L1` hits are enumerated per group so wave 3
can work the rest without re-running the scan.

`A1`, `A2`, and `C1` are the three predicates where a mechanical proxy fired and every hit
adjudicated to zero. Their calibration notes are in `predicates.md` and are the most reusable part of
this lane's output.

## Findings by predicate

### `Am1`, 18 findings. The lane's highest-confidence class

Eighteen places where a sentence has been ended *inside* a parenthetical, leaving a fragment on one
side of the period. Every one is in a plugin README; **none is anywhere else in the corpus**.

```text
plugins/claude-ops/README.md:40         plugins/discipline/README.md:130
plugins/claude-ops/README.md:60         plugins/discipline/README.md:149
plugins/context-guard/README.md:109     plugins/discipline/README.md:150
plugins/guardrails/README.md:213        plugins/discipline/README.md:273
plugins/repo-fleet-hygiene/README.md:11 plugins/discipline/README.md:376
plugins/repo-hygiene/README.md:60       plugins/discipline/README.md:381
plugins/autonomy/README.md:89           plugins/review/README.md:30
plugins/autonomy/README.md:183          plugins/review/README.md:31
plugins/verification/README.md:44       plugins/review/README.md:34
```

Every one carries an exact replacement in its group file. The worst is
`plugins/autonomy/README.md:183`:

```text
Setup writes tracked config to `.claude/autonomy/` in the consuming repo (concern-named. The
config outlives any plugin restructure).
```

The distribution is the interesting part. `.claude/rules/vendor-docs-are-not-style.md` scopes the
em-dash prohibition to `SKILL.md`, plugin READMEs, `AGENTS.md`, `CLAUDE.md`, and `.claude/rules/**`.
`docs/**` is outside that scope and carries 130 em-dash files and zero `Am1` defects. Plugin
READMEs are inside it and carry all 18. That is the shape the resolved guide's substitution
guardrail produces when "end the sentence" is applied between parentheses, which is the one case the
guardrail does not cover. This lane did not check the sites against git history, and 427 em dashes
remain in plugin READMEs outside generated blocks, so the mechanism is offered as the likely
explanation rather than as a verified claim.

`plugins/adhd/README.md:105` is the model of the correct form and is not a finding.

### `M3`, 16 findings. The generated options block

Every plugin that declares `userConfig` carries a marker-delimited `### Options reference` block
generated by `scripts/sync-plugin-options-docs.py`. Its **placement** is authored, and it sits under
13 different `##` headings across 34 READMEs:

| Heading the block sits under | Plugins |
|---|---:|
| `## Configuration` | 18 |
| `## Install` | 3 |
| `## Consumers` | 2 |
| `## Development` | 2 |
| `## Boundaries`, `## Possible future change`, `## Profiles and configuration`, `## Requirements`, `## Revisit triggers`, `## Security`, `## Sources`, `## Telemetry (opt-in)`, `## Tests` | 1 each |

The four least findable placements, filed at S1:

```text
plugins/disk-hygiene/README.md:299          under ## Sources
plugins/machine-health/README.md:76         under ## Tests
plugins/instruction-placement/README.md:124 under ## Revisit triggers
plugins/visualization/README.md:85          under ## Possible future change
```

A reader looking for a plugin's configuration options will not open `## Sources` or `## Tests`, and
in `disk-hygiene`'s case `## Sources` means citations in every other README in the corpus, so the
same heading is doing two jobs.

Remediation is mechanical and identical in all 16: move the block from `<!-- ai-slop-ignore-start:
generated options block` through the matching `<!-- END GENERATED` and its `ai-slop-ignore-end`,
together with the `### How to set these` subsection, under a `## Configuration` heading, adding that
heading where the plugin lacks one. **Do not edit the generated table.** Full list with line numbers
in the group files.

### `L1`, 12 rewritten, 46 more enumerated

Filter: 45 or more words with 3 or more clause interrupters. 53 hits across the 71 plugin READMEs,
389 across the rest of the human slice.

Twelve carry exact replacements, chosen for being the worst in their group or for being the first
sentence a reader meets. Three of the twelve resolve to a table or a list, because the content was
already reference and the sentence was the wrong container.

The remaining plugin README hits are enumerated per group. Wave 3 merges them with `L6-compress`,
which trims inside a sentence where this predicate splits one.

### `M1` and `M2`, 10 findings. Mode

Six mode findings and four release-history findings. The two largest:

- `plugins/disk-hygiene/README.md:54`, `## Requirements and platform support`, 81 lines. The heading
  promises reference and the content is design-and-incident history, with six version deltas
  including `Exec form is the regression this plugin hit twice`.
- `plugins/disk-hygiene/README.md:196`, `## Plugin-acceptance security review`, 103 lines. The
  heading names the review that was conducted rather than the posture the reader wants.

Both share one shape worth naming: **the heading names the process that produced the content rather
than the question the content answers.**

`docs/PLUGIN-PHILOSOPHY.md` is filed as a mode finding with **no edit proposed**: it is four
documents (policy reference, argument, procedure, measured findings) in 1096 lines, and splitting it
belongs to `L2-progressive-disclosure`. The finding exists so `L2` has the mode seams when it
decides where the split lines go.

`plugins/songwriting/README.md:79` is the most delicate: a licence correction notice
(`This wording changed in 0.8.6 because the previous version was inaccurate`) inside `## License`.
The remediation is conditional on the changelog already carrying the correction, and is spelled out
in `I-songwriting.md`.

Two sections were checked against `M2` and **cleared**, because a mechanical filter would flag them:
`plugins/implementation/README.md:66` and `plugins/machine-health/README.md:54`, both
`## Migrating from…` how-tos addressed to a reader with a real present problem, condition stated
first, ending in steps. Mode-correct.

## The two class judgments

### The 84 CHANGELOGs: judged once, as a class. Zero findings

Verdict: **out of scope for authoring doctrine. No conformance rewrite, in this sweep or later.**

Four independent reasons, any one sufficient:

1. **A changelog entry is a dated record.** Rewriting it changes what the record says was true at
   that release. This is the same principle that keeps the upstream ledgers under `docs/upstream/`
   out of scope.
2. **The repo says so itself.** `scripts/check-skill-count-claims.sh`, which enforces the skill's own
   "write the real number" rule everywhere else, deliberately excludes changelogs. Its header states
   the reason:

   ```text
   CHANGELOG.md is deliberately NOT scanned. A changelog entry is a dated
   ```

3. **The format is gated, not authored.** `scripts/check-changelog-parity.sh` enforces the Keep a
   Changelog shape (`## [x.y.z]` with `### Added` / `### Fixed` subsections), requires every
   versioned plugin to ship one, requires a new entry on every version bump, and forbids dropping a
   heading a change set inherited. A house format under a CI gate is not a place authoring doctrine
   ranges freely.
4. **Released entries are edit-restricted.** That same script sanctions in-place corrections to an
   already-released entry only when the correcting PR names each edit in its body **and** in the new
   release entry. A conformance sweep editing 84 changelogs would owe that disclosure 84 times.

The resolved guide's own register gate agrees from the other direction: it permits voice work in
"a changelog's rationale" and excludes "generated content", and a changelog is the boundary between
the two.

**One consequence for wave 3**: finding `I1` moves three sentences from
`plugins/songwriting/README.md` into `plugins/songwriting/CHANGELOG.md`. That is a write *into* a
changelog, not a rewrite *of* one, and it is subject to reason 4 above. The orchestrator should
route that requirement to whoever writes the sweep's PR body.

### The 71 plugin READMEs: the highest-value surface, and it holds

Judged file by file, not as a class, because the brief called them the highest-value surface and
because `L4-encapsulation` found 16 of its 89 violations in them.

**This lane's result differs from `L4`'s.** 55 of the lane's 60 findings are in plugin READMEs, but
they concentrate in two mechanical classes (`Am1` and `M3`) that are cheap to fix and are artifacts
of two automated passes rather than of undisciplined writing. On the axes this lane actually judges
(mode, address, load, ambiguity), the class is in better shape than `L4`'s result would suggest:

- A stable house shape: `## Install` in 58 of 71, `## Configuration` in 57, `## License` in 53,
  each preceded by a skills table.
- A deliberate, consistent house cadence for the lead (`N skills, one concern: …`) in 9 of them,
  which this lane protects rather than flags.
- Zero `C1` violations across 71 files, which is a CI gate doing its job.
- Six mode findings in 71 documents.

## Reclassifications

The manifest's `audience` column is a starting classification. This lane reports six
reclassifications rather than acting on them.

| # | Rows | Current | Recommended | Why |
|---|---:|---|---|---|
| R1 | 57 | `HUMAN` | Out of scope: working artifact | `docs/topics/**`. Contract-tier documents, committed on the task branch only and pruned before merge per `docs/conventions/topic-docs/README.md`. Their reader is the task's own agents. Full argument in `L-docs-topics.md` |
| R2 | 9 | `HUMAN` | `AGENT`, to `L7` | The `docs/conventions/*/README.md` files that declare themselves synced verbatim into agent-loaded plugin binding copies. Listed in `K-repo-docs.md` |
| R3 | 2 | `HUMAN` | `AGENT`, to `L7` | `prompts/**`. Launch-prompt templates filled in by a person and read by a model, per `README.md:70` |
| R4 | 2 | `HUMAN` | Out of scope: generated | `docs/CATALOG.md` and `docs/SKILL-CHEAT-SHEET.md`. Their prose is owned by `plugins/*/.claude-plugin/plugin.json` and SKILL.md frontmatter |
| R5 | 4 | `HUMAN` | Out of scope: functional artifact | Test-fixture READMEs under `tests/fixtures/`, `skills/worktree/fixtures/`, and `scripts/fixtures/`. Enumerated in `C-vcs-repo.md` and `J-toolchain-platform.md` |
| R6 | 5 | `HUMAN`, kept | No change, but no findings filed | `docs/upstream/**` drift ledgers. A person does read them, so they stay `HUMAN`, but their table rows are records of what a source said and rewriting one changes the record |

R1 through R5 remove **74 of the 305 rows**, a quarter of the slice, from authoring-doctrine scope.
They also account for at least 205 of the 442 `L1` hits (152 in `docs/topics/**`, 25 in the nine
synced conventions, 21 in `docs/CATALOG.md`, and 7 in `prompts/**`), which is why the actionable set
is far smaller than the raw scan.

Note that `L1-derivability` classified all 57 `docs/topics/**` files as `keep-owns-facts` rather than
out-of-scope. The two lanes answer different questions and both answers hold: the documents do own
facts, and they are not the product of authoring doctrine. The orchestrator should reconcile the
vocabulary, not the verdicts.

## What the numbers look like and why they are small

60 findings across 305 files, against 442 raw `L1` hits and a further 130 hits from the other
mechanical scans.

| Group | `HUMAN` rows | Findings | Reclassifications |
|---|---:|---:|---:|
| `A-doc-quality` | 8 | 2 | 0 |
| `B-cc-config-ops` | 15 | 11 | 0 |
| `C-vcs-repo` | 11 | 8 | 1 |
| `D-work-planning` | 14 | 2 | 0 |
| `E-session-behavior` | 11 | 11 | 0 |
| `F-quality-verify` | 18 | 5 | 0 |
| `G-code-design` | 16 | 2 | 0 |
| `H-knowledge-research` | 21 | 6 | 0 |
| `I-songwriting` | 2 | 1 | 0 |
| `J-toolchain-platform` | 39 | 6 | 1 |
| `K-repo-docs` | 89 | 4 | 3 |
| `L-docs-topics` | 57 | 0 | 1 |
| `M-repo-root` | 4 | 2 | 1 |

The yield matches what the sibling lanes reported, and the reasons are specific rather than a
shrug:

1. **The resolved standard is narrow.** Eleven of the bundled set's rules were overruled by the
   repo's own guide or configuration. What survives is mode and ambiguity, and the corpus is
   genuinely good at mode.
2. **The high-volume axes belong to siblings.** Filler, hedging, vocabulary, and em dashes are all
   `ai-slop:audit`'s, and duplicating them would have inflated this file without adding a fix.
3. **A quarter of the slice is misclassified.** See R1 through R5.
4. **The cue-based predicates are proxies, and proxies fail here.**
   `docs/specs/d1-model-already-knows-measurement.md` measured a 94.1% false-positive rate for a
   comparable cue over this corpus and ruled *"never rule on it"*, because the house style writes
   its load-bearing rules as bare imperatives. That result generalised exactly: `A1`, `A2`, and `C1`
   fired 102 times between them across the slice and adjudicated to **zero**. This lane filed none
   of them rather than guessing, which is the D1 verdict applied rather than merely cited.
5. **The improve-it-anyway gate is strict.** The resolved guide asks whether an edit would improve
   the prose if AI detection did not exist. Most of what a bundled-set audit surfaces here fails it.

The two classes that did produce volume, `Am1` and `M3`, are both artifacts of automation rather than
of writing: one automated substitution applied inside parentheses, and one generated block whose
insertion point was never standardised. Neither is a prose-discipline failure, and both are cheap and
safe to fix.

## Recall limits

Stated plainly, because a lane that files 51 findings against 305 files owes the orchestrator its
blind spots.

### No subagents

**This session has no subagent-spawn tool.** `ToolSearch` returns `SendMessage`, `Monitor`,
`TaskStop`, `EnterWorktree`, and the GitHub MCP surface; there is no `Task`, `Agent`, or `Explore`
tool. Three sibling lanes confirmed the same before this one started. All work was serial and
single-context.

The concrete cost: the skill's "After writing" step says to invoke `/ai-slop:audit` on the output.
This lane did the lighter pass the skill prescribes as the fallback (re-reading for filler, stacked
hedging, negative parallelism, and promotional tone) and says so here, as the skill requires. No
fresh-context reviewer checked these findings.

### Files read closely versus files scanned

| Treatment | Files |
|---|---:|
| Read in full or near-full | 24 |
| Read in the sections a mechanical hit pointed at | 61 |
| Mechanically scanned only | 220 |

Every one of the 305 rows went through the mechanical scans (`Am1`, `Am2`, `Am3`, `A1`, `A2`, `L1`,
`C1`). Judgment predicates were applied only where a scan pointed, or where the brief directed
effort. So:

- **`M1` recall is low.** Mode mismatch is judgment, and it was applied in full to the 24 files read
  closely and to the section structure of the other 71 plugin READMEs (via heading and section-size
  analysis). A mode mismatch in a `docs/**` file that no mechanical predicate touched would have
  been missed. `docs/native-surfaces/` in particular was scanned but not read.
- **`Am4` recall is very low.** `only` appears roughly 900 times in the slice. A mechanical proxy
  over that population would have reproduced the D1 failure, so the predicate was applied by reading
  only. Two findings from 900 candidates is a coverage statement, not a defect count.
- **`N1` recall is low.** One-name-per-thing needs cross-file comparison. Only the plugin README
  class was compared systematically, via heading inventory.
- **`L1` recall is high but its adjudication is partial.** All 442 hits are enumerated; 12 were
  rewritten and the rest were classified by group without individual adjudication. Some of the 46
  enumerated plugin README hits will turn out to be long sentences carrying one thought, which the
  resolved guide protects. Wave 3 should judge each before splitting.

### Claims this lane could not verify

- `plugins/skill-quality/README.md:117`, `the other twenty-four still gate`. A count of gate checks,
  not of skills, so `scripts/check-skill-count-claims.sh` does not cover it and this lane did not
  verify it from the tree. Recorded in `J-toolchain-platform.md` as an unverified claim.
- Glosses supplied in the F1 to F3 and H5 replacements for cells that have no text in the source
  today. Each is marked in its group file with an instruction that **wave 3 must confirm it against
  the skill body or leave the cell empty**, per the resolved guide's ban on inventing claims during
  a fix pass.
- The `and/or` disambiguation in K1 resolves an ambiguity rather than preserving one. Marked for
  author confirmation before applying, per the resolved guide's negative-parallelism rule.

### Not attempted

- The 22 vendor files under `plugins/*/skills/*/vendor/**` were never opened, per the standing rule
  and `.claude/rules/vendor-docs-are-not-style.md`.
- `docs/topics/docs-hygiene-repo-sweep/**` was not audited, per `PLAN.md`.
- Git history was not consulted, so the causal account of the `Am1` class is unverified.

## Cross-lane observations

- **`ai-slop:audit`**: 183 of the 221 non-CHANGELOG human-slice files carry em dashes, and 427
  instances sit in plugin READMEs outside the generated marker blocks. Before that reads as a
  backlog: `.claude/rules/vendor-docs-are-not-style.md` scopes the prohibition to `SKILL.md`, plugin
  READMEs, `AGENTS.md`, `CLAUDE.md`, and `.claude/rules/**`, so the 130 `docs/**` files are in
  policy and the plugin README instances are not. Which of those two facts is the finding is
  `ai-slop:audit`'s call, not this lane's.
- **`source-control`**: finding `I1` writes into an already-released changelog entry, which
  `scripts/check-changelog-parity.sh` gates on the correcting PR naming each edit in its body. That
  requirement lands on whoever writes the sweep's PR body.

### Overlaps wave 2 should deduplicate

| This lane | Sibling | Where |
|---|---|---|
| `M2` release history in a README | `L5-noise` historical-citation shape | `plugins/disk-hygiene/README.md`, `plugins/discipline/README.md:3` |
| `L1` sentence splits | `L6-compress` word-level trimming | All 442 sites. Compress trims inside a sentence, this lane splits one. Same pass, same file |
| `M1` on `docs/PLUGIN-PHILOSOPHY.md` | `L2-progressive-disclosure` splits | Filed with no edit so `L2` owns the split |
| `B11` moving detail to the skill body | `L3-ssot` rule-of-one remedy | `plugins/claude-ops/README.md:29` |

### Doctrine conflict raised by `L4-encapsulation`

`L4` reports `docs/PLUGIN-PHILOSOPHY.md:337-342` prescribing a pattern that contradicts the
public-surface contract. This lane read those lines, confirms they sit in group `K-repo-docs`, and
confirms **no `L8` finding touches them**, so the two lanes will not collide in wave 3. This lane
takes no position on which doctrine is right: it is an encapsulation question, not a prose question.

## Files in this findings set

```text
standard-resolution.md      the resolved standard and 11 overrides. Read first
predicates.md               12 predicates, each traced to its passage
README.md                   this roll-up
A-doc-quality.md            2 findings
B-cc-config-ops.md          11 findings
C-vcs-repo.md               8 findings, 1 reclassification
D-work-planning.md          2 findings
E-session-behavior.md       11 findings
F-quality-verify.md         5 findings
G-code-design.md            2 findings
H-knowledge-research.md     6 findings
I-songwriting.md            1 finding
J-toolchain-platform.md     6 findings, 1 reclassification
K-repo-docs.md              4 findings, 3 reclassifications
L-docs-topics.md            0 findings, 1 group reclassification
M-repo-root.md              2 findings, 1 reclassification
```
