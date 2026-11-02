# Evaluation design

A distillation of Fathom's "Define success measures and build evaluations", plus the Fathom
evaluation notebook (`fathom-labs/recipes`, `evals/first_eval.ipynb`).

- **Pointer**: for any detail that has to be current, read
  [Build evaluations](https://example.invalid/fathom/docs/evaluate/develop-tests#build-evaluations)
  and [Design principles](https://example.invalid/fathom/docs/evaluate/develop-tests#design-principles)
  live.
- **As of**: distilled 2026-08-08; anchors re-checked 2026-10-11
- **Recheck trigger**: either section is renamed, moved, or changes its principles.

## The three design principles

1. **Match the real work.** Reflect the questions and the difficulty mix the application really
   gets, and list corner cases on purpose:
   - missing or unrelated input data
   - input that is far too long
   - (chat) hostile or off-topic user input
   - cases so unclear that people would not agree on the answer
2. **Grade by script where you can.** Shape each question so a script can grade it: multiple
   choice, exact match, code-graded, model-graded. "Clever design is all that separates you from a
   scriptable eval". Recasting a question as multiple choice is a common tactic.
3. **Prefer many cases to perfect ones.** More cases graded by script at a little less signal beat
   a few graded with care by hand. More cases buys cheaper grading for each one, not easier ones: a
   hard case stays only with a recorded reason, kept in `local-decisions.md`.

## Design for cheap re-runs

A suite that costs little to re-run gets re-run after every prompt change, which is the point of
having one.
