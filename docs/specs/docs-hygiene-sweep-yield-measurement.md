# docs-hygiene-sweep-yield-measurement

Measurement record for the repo-wide `docs-hygiene` sweep: all eight `docs-hygiene` audit skills
run over the whole tracked markdown corpus in one pass, with the yield of each lane measured against
the candidate population it started from.

This document exists because the sweep's headline result is a set of numbers rather than a set of
edits. Six of the eight lanes measured that this corpus is already clean on their axis, and the
denominators are the point: a future sweep that does not know them will spend the same effort to
reach the same near-zero. It also corroborates
[`d1-model-already-knows-measurement.md`](d1-model-already-knows-measurement.md) on a different
axis, and that record's verdict is the mechanism behind most of the rejections here.

## Contents

- [Verdict](#verdict)
- [Corpus](#corpus)
- [Results by lane](#results-by-lane)
- [The three zero results worth keeping](#the-three-zero-results-worth-keeping)
- [Why the yield is this small](#why-the-yield-is-this-small)
- [Detector defects the sweep exposed](#detector-defects-the-sweep-exposed)
- [Recall limits, per lane](#recall-limits-per-lane)
- [Consequences](#consequences)

## Verdict

**This corpus is clean on the noise, compression, and derivability axes, and the cost of proving
that again is higher than the value of anything a re-run would find.** Do not re-run those three
lanes repo-wide without a stated reason that is not "it has been a while".

The two lanes that did produce actionable volume, progressive disclosure and encapsulation, are
structural rather than prose-level, and their remainder is inventoried in
[`docs-hygiene-sweep-unapplied-remediations.md`](docs-hygiene-sweep-unapplied-remediations.md)
rather than re-derivable from a scan.

## Corpus

1302 tracked `.md` files, 17,422,358 bytes. Every tracked markdown file except
`plugins/*/skills/*/vendor/**` (22 files, upstream reference material excluded by
`.claude/rules/vendor-docs-are-not-style.md`) and the sweep's own working artifacts.

| Axis | Split |
|---|---|
| Load tier | `T1` 3, `T2` 250, `T3` 1049 |
| Audience | `AGENT` 997, `HUMAN` 305 |

`T1` is `AGENTS.md` (0 bytes), `CLAUDE.md` (11 bytes, a single `@AGENTS.md` import), and
`.claude/rules/vendor-docs-are-not-style.md`. The always-loaded budget is 466 bytes in total, so no
lane found anything to remove from it.

Denominators for the byte figures below are the summed file sizes of the files in question, and
numerators are the byte lengths of the removed spans. Nothing here is estimated from a sample where
a census was available.

## Results by lane

| Lane | Skill | Candidate population | Findings | Yield |
|---|---|---:|---:|---|
| L1 | `audit-derivability` | 1302 files | 3 | 0.23% of files |
| L2 | `audit-progressive-disclosure` | 1302 files | 200 | 33 splits, 167 structure |
| L3 | `extract-ssot` | ~352 duplicated instances in 26 clusters | 13 clusters | 0 new SSOT artifacts |
| L4 | `audit-encapsulation` | 407 non-self private-surface citations | 89, then 34 | 8.4% of candidates |
| L5 | `audit-noise` | 5858 mechanical candidates | 10 | 0.17% of candidates |
| L6 | `compress` | 1302 files | 35 files | 312 bytes, 0.0018% of corpus |
| L7 | `write-for-agents` | 997 `AGENT` files, 21 predicates | 13 | 1.3% of files |
| L8 | `write-for-humans` | 305 `HUMAN` files, 12 predicates | 60 | 55 of them in plugin READMEs |

### L5 noise: 5858 candidates in, 10 findings out

The single largest number in the sweep, and its largest rejection rate: **5847 of 5858 candidates
rejected, 99.81%.**

| Shape | Candidates | Findings |
|---|---:|---:|
| `enum-list` | 4568 | 0 |
| `negation` | 1229 | 6 |
| `ghost-ref` | 36 | 3 |
| `ticket-pr-residue` | 7 | 0 |
| `citation` | 7 | 0 |
| `preamble` | 4, plus 8 recovered by a recall grep | 0 |
| `scope-meta` | 3 | 0 |
| `plan-reference` | 2 | 1 |
| `conversational-antecedent` | 2 | 0 |

**`enum-list` is the result to carry forward: 4568 candidates, zero genuine instances, and the
shape is absent rather than unmatched.** Both of its canonical forms were censused over the full
population. The prose form (`following N <consumers>`) has 3 instances, one of them the shape's own
self-definition and two eval fixtures. The list form (`- /slug — role` bullet roster) has **zero**.
The 4565 remaining candidates are two detector defects firing on ordinary markdown typography: 1625
are the repo's standard `- **Term** — definition` glossary bullet, of which only 17 name a command
at all, and 2940 are table rows containing any `/token`, of which 2039 match a path or URL rather
than a slash command. A semantic recall grep for the shape's meaning
(`the following skills`, `consumed by`, `consumers of this rule`, `call sites:`) returns one
unrelated hit.

### L6 compress: 312 bytes across 17 MB

**Total defensible compression yield across the entire corpus: 312 bytes, 0.0018%.**

| Tier | Files in corpus | Files proposed | Yield |
|---|---:|---:|---|
| `T1` | 3 | 0 | 0% |
| `T2` | 250 | 0 | 0% |
| `T3` | 1049 | 35 | 0.062% of the 35 proposed files |

The 312 bytes are two findings. 306 bytes is one verbose form (`in order to` for `to`) repeated in
34 plugin READMEs, and every one of the 34 sits inside a CI-checked generated block emitted by
`scripts/sync-plugin-options-docs.py`, so it was fixed at the generator rather than in the markdown.
The remaining 6 bytes is one stacked-hedge intensifier in a single file.

Nothing was proposed in `T1` or `T2` at all. Every `T2` file is a `SKILL.md`, which the skill's own
body bounds empirically at 2 to 3% yield with a 3-of-3 revert record, and this corpus was de-slopped
repo-wide two commits before the sweep. The lane declined the tier rather than reporting a number it
could not stand behind.

The mechanical scan and the adjudication share **no** COMPRESS members: all 10 mechanically
nominated files were overturned and all 35 proposed files were promoted from a mechanical SKIP. All
12 mechanical `UNCERTAIN` rows resolved to SKIP on facts the scan cannot see, most often a flavor
token sitting inside protected quoted text.

### L1 derivability: 3 actionable files in 1302

| Verdict | Count |
|---|---:|
| `keep-owns-facts` | 1149 |
| out of scope, functional artifact | 141 |
| `keep-as-derivation-cache` | 10 |
| `delete` | 2 |
| `convert-to-pointer` | 1 |

The 141 functional artifacts are 11% of the corpus and receive no verdict at all: eval and script
fixtures, templates a skill instructs an agent to copy, config fixtures, and machine-written sync
state. They are inputs a component consumes, not prose a reader learns from, and every in-file lane
should exclude them.

A mechanical scan for the index-restatement shape (a document more than 45% of whose non-blank lines
name a repo file) returns 6 hits across all 1302 files, and every one of the 6 is a deliberate
manifest or ledger. The 10 cache verdicts all have a named regeneration path plus a CI check, which
is the drift-control condition the rubric gates that verdict on.

### L4 encapsulation: the negative result

11,641 resolving path citations across the corpus. 7,903 are self-citations, which is legal
progressive disclosure. 407 non-self citations reach a private surface. 89 adjudicated illegal; 55
of those dissolved under
[ADR 0018](../adr/0018-treat-the-plugin-as-the-encapsulation-boundary-for-skill-citation.md), 34
remain.

**Not one cited path is missing from disk.** All 89 targets exist, both heading anchors and the one
schema file included. The silent-breakage failure the public-surface contract exists to prevent has
not occurred anywhere in this corpus. What is broken is narrower: 10 citations do not resolve from
the base their own form implies, and 8 of those 10 are intra-plugin.

## The three zero results worth keeping

Three separate measurements ran a cue-based predicate over a large population and adjudicated every
sampled hit to zero. They are recorded because each cost real effort and each will be re-run by
anyone who does not know it happened.

**L8's `A1`, `A2` and `C1` fired 102 times between them across the 305-file human slice and
adjudicated to zero.** `A1` is "command with its condition first", `A2` is "no banned intensifier in
a procedure", `C1` is "the real name and the real number". `C1`'s zero is a CI gate doing its job:
`scripts/check-skill-count-claims.sh` already enforces it everywhere except changelogs, which it
deliberately skips.

**L7's `P16`, prompt the positive, produced 1178 cue hits across 490 files and 0 findings from a
30-row `T2` sample read in file context.** The breakdown of the 30: 12 segmentation artifacts, 12
hard boundaries where the positive form loses the constraint, 6 prohibitions paired with their
positive in the adjacent sentence, 0 genuine unpaired prohibitions. The lead-word distribution over
all 1178 (`no` 451, `never` 429, `do not` 220, `don't` 59, `avoid` 19) is dominated by `no`, which is
mostly not a prohibition at all. This axis is owned by L5's `negation` shape, which has a shipped
detector and the carve-out the sample proved essential.

**L7's `P9`, completion criteria, produced 162 files with an ordered procedure carrying no explicit
done-cue, 12 read end to end, and 0 findings.** In every one, the criterion is carried by the step's
stated output shape rather than by a literal "the step is complete when Y appears" clause. Filing
162 findings on that basis would be a style edit dressed as a defect.

One positive zero is worth the same treatment. **L7's `P21` checked five harness load-semantics fact
families across 456 cue hits in 132 files and found zero contradictions.** The fleet has a de facto
agreement chain on the fact most often got wrong elsewhere: `claude-memory`, `claude-config`,
`docs-hygiene` and `instruction-placement` all independently state that `@path` imports do not defer
loading, and `plugins/instruction-placement/context/verified-mechanics.md:33` refines it for the
nested case without contradicting it.

## Why the yield is this small

Four reasons, each evidenced rather than asserted, and each one a reason a future sweep will hit the
same wall.

**1. This repository's markdown is the product, not a description of code.** Derivability asks
whether a fresh agent could reconstruct a document's conclusions from primary sources. In a plugin
marketplace the skill bodies, `reference/` and `context/` files *are* the primary source. There is no
upstream code they restate.

**2. The corpus was already swept, and the sweeps are recorded.** A repo-wide `extract-ssot` batch
ran 2026-08-15 (clusters C01 to C25, recorded in
`plugins/docs-hygiene/skills/extract-ssot/context/lessons.md` and in 41 plugin changelogs), a
repo-wide derivability pass ran the same day (recorded in
`plugins/docs-hygiene/context/derivability-route-followups.md:9`: 1089 `keep-owns-facts`, 38 noise
routes, 136 SSOT routes), and an `/ai-slop:audit fix` pass ran two commits before this sweep. Most of
what a duplication or noise scan finds here is those passes' deliberate output.

**3. The house style makes the cues fire on the material that must not be touched.** This is the
mechanism [`d1-model-already-knows-measurement.md`](d1-model-already-knows-measurement.md) measured
and it generalises exactly. That record found a 94.1% false-positive rate over an 895-file
agent-facing corpus overlapping this one almost entirely, and its verdict was **"never rule on it"**,
on the reasoning that the predicate is not an imprecise approximation of the right test but a proxy
for a property that cannot be read off the text at all. Three lanes here reproduced the result
independently: L5's `negation` E3 sample (11.7% precision), L7's `P16` (0 of 30), and L8's `A1`,
`A2`, `C1` (0 of 102). The fleet writes its most load-bearing rules as bare negative imperatives
precisely because they are universal, so a negation cue correlates with the passages whose "fix" is
most damaging.

**4. Deliberate duplication is doctrine here, not debt.** Plugins ship to consumers who do not have
the marketplace repository, so a contract is carried inline at every adopting site and the citation
is provenance-only (`docs/conventions/untrusted-content/README.md:34`). Against a plugin runtime
surface, `trim-to-citation` is structurally unavailable because the target is unreachable at runtime.
L3 refused 13 clusters and roughly 197 instances on this and adjacent grounds, and proposed **zero**
new SSOT artifacts: three clusters passed the Rule of Three and were still resolved in place.

## Detector defects the sweep exposed

Four were fixed during the sweep and are recorded in `plugins/docs-hygiene/CHANGELOG.md` versions
0.21.12 through 0.21.15. The rest were measured and not fixed, and each one inflates a denominator
above.

| Detector | Defect | Candidates it produced |
|---|---|---:|
| `audit-noise` `enum-list` | F4's inner test is `/[a-z]`, matching any path or URL rather than requiring a slash command | 2039 |
| `audit-noise` `enum-list` | F3 has no consumer test at all, matching every `- **Term** — text` glossary bullet | 1625 |
| `audit-noise` `negation` | Soft-wrap accumulation strips a wrapped table row's leading pipe before the opener test, defeating the skill's own stated table-row exemption | 30 |
| `audit-noise` `negation` | Blockquotes are not exempt the way fenced code is | 28 |
| `audit-noise` `negation` | The paired-positive search window is one sentence; the house style pairs across two | ~739 projected |
| `audit-noise` `negation` | The guardrail keyword list omits this fleet's registers: honesty, no-fabrication, quote integrity, read-only, terms of service | ~172 projected |
| `audit-noise` `preamble` | Matches `Why this file exists` but not `Why this exists`, the more common form here by 8 to 1 | 8 missed |
| `audit-noise` `ticket-pr-residue` | The forward-work carve-out is written syntactically (checkbox, `TODO(#N)`) but justified semantically, so prose `tracked in #N` is not covered | 6 |
| `compress` | Neither the six signals nor the target-validation gates know about generated regions; a gate excluding any span between `BEGIN GENERATED` and `END GENERATED` markers would have caught all 34 files mechanically before any reading | 34 |
| `audit-encapsulation` | Emits only the matched path fragment truncated at the first subdirectory slash, so a raw run cannot tell two files in one subdirectory apart; its self-citation filter never constructs the plugin-root-relative form; it does not resolve paths inside URLs | n/a |

One more, measured and worth its own line because it changed a headline number.
`audit-progressive-disclosure`'s `detect.sh` reported **132 orphan spokes**; the real number is
**4**. The bug is fixed (0.21.14), and the lesson the independent verification re-learned is the
reusable part: **anyone reporting a count without naming the files is reporting their resolver's
limits.**

## Recall limits, per lane

Every lane ran serially in one context. **No subagent-spawn tool was available**, which four lanes
confirmed independently before it was written down. Every substitute for fan-out was a corpus-wide
mechanical detector plus sampled adjudication, which trades recall for precision. The numbers above
are precision-side results and should not be read as completeness.

| Lane | What the number does not cover |
|---|---|
| L1 | Both `delete` verdicts needed a fresh-context spot-test the lane could not run. One passed when the orchestrator ran it later; one **failed and was overturned**, having named four behavioral rules recoverable from nowhere else. Without that gate the sweep would have deleted them. |
| L2 | The `missing-toc` band from 100 to 300 lines (303 files) is contested between the two official sources and carries no treatment; it is counted as one awareness entry per group, not 303 findings. |
| L3 | Line-anchored matching only. Two files stating the same sentence with different line breaks share no normalized line, which is a real unquantified hole in a corpus that wraps at roughly 100 columns. Roughly 200 of 364 candidate blocks were triaged by first line, not verified. |
| L4 | Prose references with no path are invisible to both passes. Anchors are under-counted: only `#fragment` forms were caught, not sections pinned by quoting their title. 81 candidates in `.sh`, `.yml` and `.json` were out of the markdown corpus and got no remediation spec. |
| L5 | `negation` E3 recall is 7 of an estimated 120 (95% Wilson interval about 60 to 228); the 1031-row remainder was sampled at n=60, not read. Six of the nine shapes were read in full with no sampling. |
| L6 | Article drops, passive-to-active conversions and nominalization rewrites were excluded deliberately, on a measured 9-of-9 revert record at 0.02 to 0.4% yield. The verbose-form sweep is a fixed 15-form list, not a model pass. |
| L7 | Recall is cue-bounded on every predicate and was never measured; precision was verified by reading. `T3` was adjudicated by sample for `P7` and `P9`. Four predicates are not text-auditable and were not attempted. |
| L8 | 24 files read in full, 61 read at the sections a mechanical hit pointed at, 220 mechanically scanned only. `M1`, `Am4` and `N1` recall are all low and stated as such: `Am4` filed 2 findings against roughly 900 candidate instances of `only`, read rather than scanned. |

## Consequences

- **The noise, compression and derivability lanes are done for this corpus.** Re-running them
  repo-wide costs the same effort for the same near-zero. If one is re-run, run it against a
  changed subset with a stated reason, not against 1302 files.
- **`enum-list` should not be re-adjudicated at all** until its F3 and F4 predicates are fixed. As
  written it produces 4193 candidates that are, measurably, ordinary markdown typography.
- **Cue-based predicates over this corpus are a known failure class**, not a promising lead. The
  `d1` verdict is the reason, it now has three independent corroborations at a different tier and a
  different audience, and the correct response to a new cue idea is to measure its precision on a
  read sample before emitting anything.
- **Fixture and template files must be excluded from every in-file lane**, not just from the one
  that noticed. 62 rows under `evals/fixtures/` and `scripts/fixtures/` are test data, several of
  them deliberately defective specimens that anchor a passing eval, and applying doctrine to one
  breaks the test it exists for. The manifest generator is where that exclusion belongs.
- **Reject any edit whose line falls inside a `BEGIN GENERATED` / `END GENERATED` pair.** Roughly 70
  lines in each of 34 plugin READMEs are generated by `scripts/sync-plugin-options-docs.py` and
  checked in CI; a hand edit there fails CI and reverts on the next sync. Route it to the generator.
- **The structural remainder is not re-derivable from a scan** and is inventoried separately in
  [`docs-hygiene-sweep-unapplied-remediations.md`](docs-hygiene-sweep-unapplied-remediations.md).
