---
bump: patch
---

### Changed

- **Whole-set score against copy rubric version 5 and restated-fact version 1, 38 cases, 114 blind
  judges: 22 tp / 3 fp / 1 fn / 12 tn, precision 0.88, recall 0.96
  ([#5654](https://github.com/melodic-software/claude-code-plugins/issues/5654)).** This is the
  re-score 0.10.4 requires before any precision figure is cited. It replaces the 0.8.2 whole-set
  score, which was taken against copy rubric version 4.

  **Method.** The method is 0.7.1's, as reused by 0.8.2, with these differences:
  - Model `claude-opus-5-5`, effort `medium`, Claude Code 2.1.314.
  - Each judge was one `claude -p` process with no tools, no skills or slash commands, no MCP
    servers and no setting sources. Each ran from its own empty home and working directory outside
    any repository. The init event listed no tools, skills or MCP servers, and three built-in
    plugins. No hook event fired.
  - Each judge's input was 12,169 to 13,109 tokens, the size of its own prompt.
  - Each prompt held the framing block, the "Judgment" prompt shape for its rubric, one lens
    sentence, the whole of `reference/rubric.md` as committed, and the case block. The local
    passage was the whole `case.md`, and LOCAL FILE carried the same text with line numbers.
  - Each case went to judges under a neutral label (`case-a` to `case-al`) in a seeded random
    order. The source's preamble paragraph, its canonical-location line and its HTML comments were
    dropped. Its declared URL was kept as its identity.
  - The case blocks were checked for the words golden, fixture, negative, adversarial, rotation,
    synthetic and invented before dispatch, and none was present.
  - The dispatching run opened one `expected.json` (`c01`) while orienting, before dispatch. It
    opened no other until all 114 outputs were saved.

  **Rubric routing** followed `nomination.md`'s order and was fixed before dispatch:
  - Copy: the 22 cases where `fingerprint.mjs` fired, plus `c05` to `c07` and `c10`, whose sources
    are invented pages that no external owner can change.
  - Restated-fact: `c11` to `c20` and `c22` to `c24`, which restate a real upstream page and did
    not fire.

  The combine rule is 0.7.1's. As in 0.8.2, the restated-fact refutation pass was not run.

  | Class | n | tp | fp | fn | tn | Precision | Recall | Previous (0.8.2, rubric v4) |
  |---|---|---|---|---|---|---|---|---|
  | verbatim | 3 | 3 | 0 | 0 | 0 | 1.00 | 1.00 | 1.00 / 1.00 |
  | near-verbatim | 13 | 12 | 0 | 1 | 0 | 1.00 | 0.92 | 0.92 / 0.92 |
  | paraphrase | 1 | 1 | 0 | 0 | 0 | 1.00 | 1.00 | 1.00 / 1.00 |
  | restated-fact | 6 | 6 | 0 | 0 | 0 | 1.00 | 1.00 | 1.00 / 1.00 |
  | hard negatives | 15 | 0 | 3 | 0 | 12 | n/a | n/a | 2 fp, 13 tn |

  `score-golden.sh` reports near-verbatim and hard negatives at a binding gate (n 13 and 15). It
  reports near-verbatim above the 0.95 precision bar and the 0.8 recall floor. **This entry
  declares no class fix-eligible.** A precision of 1.00 rests on 12 true positives, nine of them
  adjudicated from real repository text and four sharing one source. Changing fix eligibility is
  outside #5654 and goes to the owner.

  **Where the panel disagreed with a recorded expectation.** No expectation was changed.
  - `c26`, recorded near-verbatim, split 2 to 1. Two judges returned `verbatim` on lines 7-10. One
    cleared it at C4: lines 11 and 13 add a local rule and a local application. It is the
    near-verbatim row's one false negative. In 0.8.2 it was unanimous `verbatim`.
  - `c36`, recorded as a negative, returned a unanimous `near-verbatim` finding on line 12, as in
    0.8.2.
  - `c22` and `c23`, recorded as negatives, each returned a unanimous `restated-fact` finding on
    line 3. Every judge graded R4 PASS: the nearby citations name a document or a section but carry
    no URL, as-of date or recheck trigger. 0.8.2 recorded `c23` as a `near-verbatim` finding and
    `c22` as a true negative. Its routing of these cases is not recorded.
  - `c24` and `c34`, which split in 0.8.2, were unanimously cleared.

  **What this score does not support.** The ten blocked candidate panels and the contradicting
  verbatim candidate from 0.8.2 were not re-run: their inputs are real repository passages that
  are not tracked as cases. Verbatim still has 3 cases against `min_n_per_class` 10, so it stays
  report-only.
