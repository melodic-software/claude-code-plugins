---
bump: minor
---

### Added

- `/work-items:morning-brief` gains a Landed section

  It lists the PRs merged since this machine's `landed_at` (the last day
  on a first read), with a count, and under "Read these" a sample of 3
  of them: the oldest, the newest and evenly between. `--landed-sample`
  or the `morning_brief.landed_sample` key sets the size. `landed_at` is
  a stamp under the plugin data dir beside the stranded-findings
  bookmark, and it moves only after the section read in full. The
  section reuses the stranded-findings read of merged PRs when that read
  reaches back far enough.
