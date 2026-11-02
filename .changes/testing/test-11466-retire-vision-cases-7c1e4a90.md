---
bump: none
---

Evals only: the nine `vision-*` eval cases are retired, with `evals/ui-defects/render-crops.mjs` and the screenshots in `evals/fixtures/ui-defects/crops/` that only they used ([#11466](https://github.com/melodic-software/claude-code-plugins/issues/11466)). Each prompt said no app server or browser exists, so `/testing:run-e2e`, which needs a running app, never loaded: both arms were the bare model, the delta was 0.00, and the cases measured no plugin effect. `probes/run-e2e.json` gains rendered-page positives for a running app, a `testing:write` negative, and a screenshots-only negative modeled on the retired cases. The `run-e2e` description is unchanged; no shipped behavior changes.
