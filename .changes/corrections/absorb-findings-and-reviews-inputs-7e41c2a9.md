---
bump: minor
---

### Added

- `/corrections:codify findings <findings-file>` takes each row of one review findings file through the count, rung and proof steps, strongest rung first, and writes one proposal per row. `reference/finding-classes.md` holds the class lookup and each rung's next step.
- `/corrections:codify reviews` mines recent merged pull requests' review comments through `/source-control:pull-request review-comments`; the PR author's own comments made after the merge count.
- `ratchet_offer` and `review_mining_prs` settings and plugin options, resolved by `codify-settings.mjs`; `corrections.yaml` wins over the option, and an invalid repository value falls to the default.
- The codify report names the chosen rung by its ladder id and reports a recurring checkable mistake with no check as a "no guardrail" finding naming the ladder's "Guardrail criterion" section; a rule that was never loaded is fixed where it lives as well as taking its checking rung.
- An eval suite under `evals/` with deterministic graders for both inputs and the behavior ported from `/review:audit-enforceability` and `/session-flow:retro codify`.
