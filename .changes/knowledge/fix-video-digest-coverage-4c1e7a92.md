---
bump: patch
---

### Fixed

- `/knowledge:video-digest` sets the default maximum gap between sampled frames by video length:
  5 s up to 90 s, 6 s up to 5 minutes, 60 s beyond. Short demo-heavy videos no longer miss screens
  shown between scene cuts; `--max-frame-gap-sec` still overrides it.
- Watch checklist row 1.5 states the `highVolume` rule the pipeline applies, including the
  candidate-count condition, and its generated tick checks that condition too.
- `init-watch-checklist.js --force` and a `run-watch.js` re-run rewrite the generated evidence
  lines from the new run and keep agent-written ticks and evidence; a criteria-change notice goes
  to stderr.
