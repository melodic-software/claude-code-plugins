---
bump: patch
---

### Changed

- The `quality-gate` PR mode gates the `code-review` marketplace plugin only in its `--comment`
  form. It lists the plugin's default run, which reports to the terminal and posts nothing, as an
  optional read-only pass beside the bundled `/code-review`, and names the early stops that can
  leave that run with no findings.
- The `fanout` skill no longer says the `code-review` plugin always posts to the PR: it passes
  `--comment` on an opted-in dispatch. Its description of the plugin's filtering now matches the
  command's validation subagents; the old text described a 0–100 confidence scorer.
