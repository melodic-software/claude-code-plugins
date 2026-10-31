---
bump: patch
---

### Changed

- Golden cases `c22` and `c23` are now recorded as `restated-fact` findings on line 3, and `c36` as a `near-verbatim` finding on line 12, under the owner's rule that a unanimous blind label is accepted ([#5654](https://github.com/melodic-software/claude-code-plugins/issues/5654#issuecomment-6417188551)). Each was a recorded negative that a unanimous 0.14.4 panel flagged: restated-fact v1 for `c22` and `c23`, copy v5 for `c36`. Evals 13 and 15 expect these findings. `c23`'s 0.8.2 `near-verbatim` result is a class only the copy rubric emits, which indicates 0.8.2 judged it under copy, while the documented routing sends `c22` and `c23` to restated-fact. The new labels change the 0.14.5 tally as follows. No judge was re-run.

  | Class | n | tp | fp | fn | tn | Precision | Recall | Previous (0.14.5) |
  |---|---|---|---|---|---|---|---|---|
  | verbatim | 4 | 3 | 0 | 1 | 0 | 1.00 | 0.75 | 1.00 / 0.75 |
  | near-verbatim | 13 | 13 | 0 | 0 | 0 | 1.00 | 1.00 | n 12, 1.00 / 1.00 |
  | paraphrase | 1 | 1 | 0 | 0 | 0 | 1.00 | 1.00 | 1.00 / 1.00 |
  | restated-fact | 8 | 8 | 0 | 0 | 0 | 1.00 | 1.00 | n 6, 1.00 / 1.00 |
  | hard negatives | 12 | 0 | 0 | 0 | 12 | n/a | n/a | n 15, 3 fp, 12 tn |

  Overall 25 tp / 0 fp / 1 fn / 12 tn, precision 1.00, recall 0.96. The table is derived by hand from the 0.14.5 tally; `score-golden.sh` has not been re-run over the stored judge outputs. Verbatim, paraphrase and restated-fact stay report-only below `min_n_per_class` 10. No class is declared fix-eligible: the owner ruled to re-measure on a larger sample first ([#5654](https://github.com/melodic-software/claude-code-plugins/issues/5654#issuecomment-6523541851)).
