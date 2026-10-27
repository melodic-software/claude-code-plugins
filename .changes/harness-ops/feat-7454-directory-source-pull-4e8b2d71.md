---
bump: minor
---

### Added

- **`/harness-ops:plugins sync` offers to fast-forward a `directory` marketplace's checkout.**
  When the checkout is clean, on a branch with an upstream, and only behind it, the report's
  digest marks it `offered` and the skill asks once per marketplace. On a yes it reruns with
  `--pull-source`: `sync-run.sh` checks the checkout again, runs `git pull --ff-only` before
  the marketplace refresh, and the run goes on against the newer catalog, its `source:` row
  naming the commits it moved from and to. The script refuses a dirty, detached, upstream-less,
  ahead, diverged or current checkout with the reason and touches nothing, and a refused or
  failed pull does not stop the run. The new `directory_source_pull` option takes `ask`
  (default) or `never`; an autonomous or ambiguous session never asks or pulls, and the script
  treats a set `CLAUDE_CODE_REMOTE` as `never` (#7454).
- **The `autoUpdate: off` suggestion can be silenced.** Marketplaces named in the new
  `quiet_auto_update_marketplaces` option render `autoUpdate: off` without the suggestion to
  enable it; unset keeps it.
