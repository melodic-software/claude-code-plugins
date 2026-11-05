---
bump: major
---

### Removed

- `/review:explain-change` no longer reads the old team locations

  The team layer is `docs/conventions/review-digest.yaml` only. The `json config` block in
  `docs/conventions/review-digest.md` and `.claude/review-digest.json` were read for one release
  while the YAML file was absent; they are now ignored, and a change to either no longer fires the
  risk-path trigger on its own. Move their keys into `docs/conventions/review-digest.yaml`. The
  user-global `~/.claude/review-digest.json` and the personal override
  `.claude/review-digest.local.json` are still read.
