# L5-noise: lane roll-up

Lane lead for `/docs-hygiene:audit-noise` over the 1302-file sweep corpus, 1218 files after the
detector's `CHANGELOG.md` basename skip.

**5858 mechanical candidates in. 11 findings adjudicated, 10 still applicable. 5847 rejected.**

One `negation` finding was mooted mid-sweep when another lane deleted the file it sits in. It is
retained in [negation.md](negation.md), marked void, because the sampled precision rate that
drives this lane's central decision was measured with it in.

## Findings by shape and tier

Applicable findings only; the void row is excluded from the totals.

| Shape | Candidates | Findings | T1 | T2 | Rejected | File |
|---|---:|---:|---:|---:|---:|---|
| `enum-list` | 4568 | 0 | 0 | 0 | 4568 | [enum-list.md](enum-list.md) |
| `negation` | 1229 | 6 (+1 void) | 0 | 6 | 1222 | [negation.md](negation.md) |
| `ghost-ref` | 36 | 3 | 0 | 3 | 33 | [ghost-ref.md](ghost-ref.md) |
| `ticket-pr-residue` | 7 | 0 | 0 | 0 | 7 | [ticket-pr-residue.md](ticket-pr-residue.md) |
| `citation` | 7 | 0 | 0 | 0 | 7 | [citation.md](citation.md) |
| `preamble` | 4 (+8 recovered) | 0 | 0 | 0 | 12 | [preamble.md](preamble.md) |
| `scope-meta` | 3 | 0 | 0 | 0 | 3 | [scope-meta.md](scope-meta.md) |
| `plan-reference` | 2 | 1 | 1 | 0 | 1 | [plan-reference.md](plan-reference.md) |
| `conversational-antecedent` | 2 | 0 | 0 | 0 | 2 | [conversational-antecedent.md](conversational-antecedent.md) |
| **Total** | **5858** | **10** | **1** | **9** | **5855** | |

Rejected exceeds candidates-minus-findings by 8 because the `preamble` recall check added 8
instances the detector never emitted, and all 8 were rejected too.

## Rejection grounds, aggregated

| Grounds | Count |
|---|---:|
| Structural cue firing on ordinary markdown typography, no defect present | 4565 |
| Positive alternative already present in the adjacent sentence or clause | 43 sampled, ~739 projected |
| Hard guardrail the scanner's keyword carve-out does not name | 10 sampled, ~172 projected |
| Quoted third-party teaching material (Pattison, Khorikov, Pocock) | 114 mechanical, more in sample |
| Blockquote, somebody else's words | 28 |
| Detector's own shape-definition rows and eval fixtures | ~20 |
| Table-row attribution contradicting the skill's own pipe-opener rule | 30 |
| Rubric exclusion clause, an inclusion list is a different document | 26 |
| Repo-declared doctrine overriding the portable baseline | 5 |
| Intra-slice or sibling-slice citation, citer does not outlive the slice | 12 |
| Cited path exists, or already carries the prescribed durable pointer | 6 |
| Forward pointer to outstanding tracked work, the `TODO(#N)` carve-out in prose | 6 |
| Diataxis Explanation quadrant, KEEP is the prescribed treatment | 9 |

The projected rows are marked as projections. See "Recall limits".

## Form taxonomy for the two high-volume shapes

### `enum-list`, 4568 candidates, assigned mechanically over all of them

| Form | Population | Decision |
|---|---:|---|
| F1 `following N <consumers>`, the shape's canonical prose form | 3 | Reject: 1 self-definition, 2 eval fixtures |
| F2 `- /slug — role` bullet roster, the shape's canonical list form | 0 | Population empty |
| F3 `- **Term** — definition` bullet | 1625 | Reject: repo's standard glossary bullet, 17 of 1625 name a command at all |
| F4 table row containing any `/token` | 2940 | Reject: 2039 match a path or URL only; the 754 remainder are a generated catalog, mandated plugin-README rosters, routing tables, and incidental mentions |

Neither canonical form of the shape occurs in real corpus prose. A recall grep for the semantic
form (`the following skills`, `consumed by`, `consumers of this rule`, `call sites:`) returns one
unrelated hit, so the defect is absent rather than unmatched.

### `negation`, 1229 candidates, forms A to D mechanical over all of them, form E sampled

| Form | Population | Decision |
|---|---:|---|
| A: attributed to a table row | 30 | Reject, detector defect |
| B: blockquote | 28 | Reject, quoted material |
| C: quoted teaching corpus under `pat-pattison/research/` | 114 | Reject, attributed third-party voice |
| D: rubric exclusion clause (`Must NOT flag: ...`) | 26 | Reject, no positive form exists |
| E: remainder | 1031 | Sampled at n=60, split below |

Form E, from a 60-row random sample read in file context:

| Sub-form | n | share | Decision |
|---|---:|---:|---|
| E1: positive present in the adjacent sentence or clause | 43 | 71.7% | Reject |
| E2: hard guardrail the keyword gate missed | 10 | 16.7% | Reject |
| E3: genuine unpaired prohibition, clean positive rewrite | 7 | 11.7% | Finding |

**The lane does not apply the E3 form decision to its population.** That is the single most
consequential call here and it is argued in full in [negation.md](negation.md). Short version:
`docs/specs/d1-model-already-knows-measurement.md` measured, over 895 files of this same corpus,
that 54.8% of a comparably cued population sits in hard-boundary register because the house style
writes its most load-bearing rules as bare negative imperatives, and that a cue-based verdict on
that population reached a 94.1% false-positive rate. At 11.7% sampled precision, issuing 1031
unread rows as findings would produce roughly 910 spurious edits against instruction surfaces. So
for this shape, form membership is not sufficient evidence and only an individually read instance
is emitted.

## Recall limits

Stated plainly, because a silent cap reads as full coverage.

1. **`negation` E3 recall is 7 of an estimated 120** (95% Wilson interval about 60 to 228). The
   1031-row remainder was sampled at n=60, not read. Roughly 113 genuine unpaired prohibitions
   exist in this corpus that this lane did not enumerate. A later pass wanting them should read
   the remainder rather than trust this file's count.
2. **`enum-list` F3 and F4 form decisions rest on 20-row reads each**, backed by mechanical
   censuses over the full populations (17 of 1625 for F3, 2039 of 2940 for F4). The censuses are
   complete; the reads are not.
3. **Only `preamble` got a recall sweep that found anything.** Recall greps were run for
   `citation`, `scope-meta`, `plan-reference`, `conversational-antecedent`, and the semantic form
   of `enum-list`. No recall sweep was run for `negation`, `ghost-ref`, or `ticket-pr-residue`
   paraphrases: the first two are already the detector's high-yield shapes and the third has a
   population of 7.
4. **No subagents were used.** No `Agent` or `Task` tool exists in this lane's context, and
   `create_session` spawns a container without this checkout. Every count above comes from serial
   work plus corpus-wide mechanical detectors run in place of fan-out.
5. **`ghost-ref`, `ticket-pr-residue`, `citation`, `scope-meta`, `plan-reference`, and
   `conversational-antecedent` were each read in full**, all 61 candidates individually, with path
   existence tested on disk for every `ghost-ref`. No sampling in those six.

## Detector defects found

Reported because the mechanical layer is reused by later sweeps.

| Shape | Defect | Cost |
|---|---|---|
| `enum-list` | F4's inner test is `/[a-z]`, which matches any path or URL and does not require a slash command | 2039 candidates |
| `enum-list` | F3 has no consumer test at all, matching `- **Term** — text` | 1625 candidates |
| `negation` | Soft-wrap accumulation strips a wrapped table row's leading pipe before the opener test, defeating the skill's own stated table-row exemption | 30 candidates |
| `negation` | Blockquotes are not exempt the way fenced code is | 28 candidates |
| `negation` | The paired-positive search window is one sentence; the house style pairs across two | ~739 projected |
| `negation` | The guardrail keyword list omits this fleet's registers: honesty, no-fabrication, quote integrity, read-only, terms of service | ~172 projected |
| `preamble` | Matches `Why this file exists` but not `Why this exists`, the more common form here by 8 to 1 | 8 missed |
| `ticket-pr-residue` | The forward-work carve-out is written syntactically (checkbox, `TODO(#N)`) but its justification is semantic, so prose `tracked in #N` is not covered | 6 candidates |

## Wave 3 application notes

All 10 applicable findings are in-file edits with no cross-file dependency. Three sit in
`docs/specs/`, which L1-derivability may delete; if it does, `ghost-ref` findings 1 through 3
moot. The remaining seven sit in plugin bodies and `docs/` root files.

Line numbers were re-verified against the working tree after the roll-up was written, and 10 of
the 11 still resolve to their quoted text. Concurrent lanes are editing source files during
wave 1, so re-verify each `path:line` before applying rather than trusting the number: that is
how the void finding was caught.

## Cross-lane observations

- **L6-compress.** `negation` form E1's two-sentence prohibition-then-positive pattern is a
  compression target as much as a noise one. This lane's interest ends once the positive is
  present somewhere adjacent; whether the two sentences merge is L6's call.
- **L3-ssot.** Two duplications surfaced: the `CLAUDE_PLUGIN_OPTION_*` paragraph across at least
  three plugin READMEs, and the `#571` displacement-bypass sentence across two `babysit-prs`
  files.
- **L1-derivability.** `docs/specs/write-for-agents-brief.md` and
  `docs/specs/invocation-mode-doctrine-brief.md` are briefs whose working evidence is
  unrecoverable from this repo. Whether they still earn their existence is L1's question.
- **Corpus classification, all lanes.** `plugins/songwriting/context/pat-pattison/research/**` is
  quoted third-party teaching material that sits outside the sweep's
  `plugins/*/skills/*/vendor/**` exclusion. It supplied 114 of this shape's candidates and it
  should not be style-edited by any lane. `plugins/tdd/skills/principles/reference/anti-patterns-khorikov.md`
  and `docs/topics/ai-adoption-ladder/design/RESEARCH-sandcastle-pocock.md` are single-file
  instances of the same problem.

## Provenance

Mechanical baseline: [../../inventory/noise-detector-baseline.md](../../inventory/noise-detector-baseline.md),
a full-corpus `detect.sh` run at docs-hygiene 0.21.13. This lane re-parsed that run's raw output
into a per-finding table and replayed the detector's own shape predicates from
`plugins/docs-hygiene/skills/audit-noise/scripts/lib/noise-shapes.sh` to assign forms. It did not
re-run the scan.
