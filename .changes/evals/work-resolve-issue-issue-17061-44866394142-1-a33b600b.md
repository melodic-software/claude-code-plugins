---
bump: minor
---

### Changed

- **Eval runs on Linux and WSL2 clean up their own temp directory.** `/evals:plugin-eval` now
  requires `$HOME/.ev` as the eval temp root and gives each run its own `TMPDIR`,
  `$HOME/.ev/<short-run-id>`, made with `mktemp -d`. The 24-character bound applies to that
  per-run path. A new closing step removes the run's directory when the run ends, whether or not a
  read happened, unless the user asks to keep it. Before, each session picked its own directory
  under `$HOME` and nothing removed it, so hundreds of them, holding sealed sandboxes, built up.
  ([#17061](https://github.com/melodic-software/claude-code-plugins/issues/17061))

### Added

- **Preflight lists stale run roots.** A new `stale_run_roots` field lists run roots under
  `$HOME/.ev` older than 3 days, with a count of the `claude-eval-*` sandboxes inside them. Like
  the rest of preflight it only reports and removes nothing. `reference/sandboxes.md` now holds
  the run-root removal loop: it acts only on a real directory directly under `$HOME/.ev` that holds
  `claude-eval-*` sandboxes, and it opens `sealed/` the same way as the loop that removes a read's
  sandboxes.
