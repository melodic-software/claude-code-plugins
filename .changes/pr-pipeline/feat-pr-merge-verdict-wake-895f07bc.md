---
bump: minor
---

### Changed

- A pass or pass-notes verdict now wakes pr-merge for that one pull request: `pr-verify.yml`'s new `wake-pr-merge` job, holding only `actions: write`, dispatches a PR-scoped `pr-merge.yml` run (`-f pr=<n>`). That run reads and arms only that pull request, takes the lane's room from the last sweep's post-merge report, and skips the merge job, `post-merge-dispatch` and every other sweep job. `who.mjs` admits it as `github-actions[bot]`'s first attempt on main; no sweep reads its artifacts or counts it as a superseder. It logs one `pr-merge-wake` notice with its outcome and `api-calls` totals. pr-merge's schedule slows from every 15 minutes to every 30, as the backstop. `red-main.confirm-wait-minutes` rises from 40 to 55 to cover the slower re-run, with its cap at 60 and the report job's timeout at 75.
