# Iterating

1. Read the delta column first, never the absolute score. The read is done when each case is
  either a number or an explicit "not comparable".
2. The usual first finding: a delta near zero with the case's `tool_used: Skill` grader failing means the model is not
  choosing the skill on natural phrasing. Fix the skill's `description`, not the case, and re-run
  that one case until the grader passes. A passing fired grader shows the trigger works; it is not
  evidence that the skill improved, and any claim of a gain still needs a VALID run and its noise
  report.
3. That grader passing and a negative delta: suspect the judge before the plugin, since a small
  judge marks a correct answer wrong on formatting. Re-run with a larger `--judge-model` and
  tighten the rubric until it survives a rubric silent on form.
4. Iterate on one case with `--case <name> --runs 1 --ablation none` (it reports `SCORE` and
  `PASS%`, no delta). One run is noisy, so confirm any change at 3 runs per case, the only repeat
  count this repository sets ([local-decisions.md, Repeat count](../../methodology/reference/local-decisions.md#repeat-count)),
  and read the confirm's noise report before trusting it.
5. Give each case one grader on the result and one on how the model got there (`tool_used` or
  `tool_order`). That pairing separates "the answer was right" from "the plugin is why".
