---
bump: major
---

### Changed

- **Breaking:** a lane's `stage` is one of `intake`, `admit`, `build`, `refine`, `review`, `fix`, `verify`, `hold`, `merge`, `post-merge`, `upstream` or `maintenance`. `work-resolve-issue` is `build`, `work-unblock` is `admit`, `pr-unblock` is `fix`, and the review lanes are `review`; `work`, `pre-ready` and `unblock` are gone from the schema, so a config that still sets them fails it.
- `lane-rules.json` is the one list of lane ids: each id is its workflow file stem, or a lane another repository's `lane-grants.json` row admits. The review lanes are `pr-review-hosted` and `pr-review-security-hosted`, and `pr-review-main`, `pr-rate-merge-risk`, `pr-run-plugin-evals`, `post-merge-test-mutation` and `maintenance-audit-lane-runs` have rows. `lane-registry.json` names a review caller's footer under `footer`. `lane-ids.test.mjs` fails when the registry, the funding file, the grants or the README's Lanes table name a lane the list lacks.

### Removed

- `post-merge-verify` and `post-merge-sweep-comments`, which had no workflow and no grant, and the README rows for them, `pr-run-checks` and `pr-explain`.
