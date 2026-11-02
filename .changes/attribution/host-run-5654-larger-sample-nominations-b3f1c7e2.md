---
bump: patch
---

### Added

- `skills/audit/evals/nominations/2026-11-02-larger-sample.json` lists 18 real repository passages
  nominated for the larger-sample re-measure, from 15 distinct source pages, with the
  `fingerprint.mjs` figures and the blind three-judge panel outcome for each (copy rubric v5,
  restated-fact v1). It holds pointers only, never the passages or sources. Outcomes: 2 unanimous
  findings (one near-verbatim, one verbatim, both from one source page), 14 unanimously cleared, and
  2 splits, settled by agent decisions under the owner's standing direction (k16 near-verbatim;
  k17 restated-fact, after five of six judges across both panels returned it).
- Golden cases `c39` to `c56`, one synthetic rewrite per nominated passage, registered as eval 16.
  No real passage or source text is carried. Each case keeps its passage's fingerprint profile
  against its own source (fires for the twelve that fired, below both limbs for the six that did
  not), and stays below both limbs against the real passage and its real source.
- Whole-set re-score: `score-golden.sh` over all 56 cases, merging the stored #11252 verdicts for
  `c01` to `c38` with three new blind judges per new case (`coverage_declared` true, nothing
  declined). The previous column is the stored verdicts alone, scored against the current
  expectations.

  | Class | n before | n now | Precision before | Precision now | Recall now | Gate now |
  |---|---|---|---|---|---|---|
  | near-verbatim | 13 | 15 | 1.00 | 1.00 (14 tp, 0 fp) | 0.93 | binding |
  | verbatim | 4 | 5 | 1.00 | 1.00 (4 tp, 0 fp) | 0.80 | report-only |
  | paraphrase | 1 | 1 | 1.00 | 1.00 | 1.00 | report-only |
  | restated-fact | 8 | 9 | 1.00 | 1.00 (9 tp, 0 fp) | 1.00 | report-only |
  | hard negatives | 12 | 26 | n/a | 26 tn, 0 fp | n/a | binding |

  Overall: 28 tp, 0 fp, 2 fn, 26 tn; precision 1.00, recall 0.93. The new miss is `c39` (a
  two-to-one panel, the dissent grading C4 on the whole file). No class is declared fix-eligible.
