---
bump: patch
---

### Changed

- `collect_lane_runs` uses each kept run's fresh `GET actions/runs/{id}` response as its latest attempt instead of also reading `actions/runs/{id}/attempts/{run_attempt}`, one fewer call per kept review-lane run on every merge gate. Earlier attempts are still read. The fresh run read stays: it gives the attempt count and is how a deleted run is noticed. A recorded live pair shows the two responses differ only in `jobs_url` and `logs_url`, which nothing reads.
