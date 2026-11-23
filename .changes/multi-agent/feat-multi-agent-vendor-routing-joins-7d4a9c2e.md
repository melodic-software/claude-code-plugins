---
bump: minor
---

### Added

- Harness gating in `vendor-decide` (`--needs-tools <list>`, `--context <tokens>`) and `scripts/lib/gating.mjs`: skips harnesses lacking a needed tool, models whose `context_window` is below `--context` (keeping Claude when its window is unknown), and vendors with `breaker.open: true` (naming `reset_at`), each with one note.
- Usage tiebreak in `vendor-decide` (`--usage <file>`): `most-usage-left` compares per-vendor `UsageReading.remaining` and falls back to `vendor-order` with one note when any tied vendor's reading is missing or `unavailable`.
- Eval cases `evals/ro-vendor-image-recommend/` (image recommendation with `auto_delegation: false`) and `evals/ro-vendor-unavailable-line/` (one-line notice for an unavailable `in_use` vendor).
- Benchmark registry recheck agents `agents/registry-fetcher.md` (Bash-only, gated by a second `PreToolUse` `Bash` entry in `hooks/hooks.json` to the exact host list of `reference/benchmarks.json` with `onFailure: "block"`) and `agents/registry-judge.md` (`tools: []`, closed JSON verdict, never quotes page text).
- `workflows/registry-audit.js` and `skills/audit-defaults/scripts/list-registry.mjs` (plus tests `hooks/registry-fetcher-gate.test.mjs`, `tests/registry-audit.test.mjs`, and `skills/audit-defaults/scripts/list-registry.test.mjs` with `.test.sh` wrappers) for read-only benchmark registry rechecks across shipped and team rows.

### Changed

- `/multi-agent:route vendors` now grants `external-agents usage:*` and `external-agents run` (`codex`, `antigravity`), passes harness facts (`tools`, `image`, `breaker`, `context_window`) into `--models`, queries plan usage only when `vendors.tiebreak` names `most-usage-left` (`external-agents usage` per in-use vendor plus `mcp__rate-limits__status` when enabled), handles `image` auto-delegation with task-only prompts naming the vendor's built-in image tool, reviews generated images with `Read` before `vendor-state record`, and recommends nothing (`basis: user-choice`) when every image-capable vendor has failed its trial.
- `reference/vendors.md` and `reference/config.md` document harness gating, breaker skipping, usage tiebreak fallback, image auto-delegation, and Claude's live model-overview context-window pointer.
- `/multi-agent:audit-defaults` gains read-only `registry` mode (always runnable manually regardless of `vendors.*` switches) with an explicit opt-in apply step that writes the proposed `reference/benchmarks.json` diff in a worktree and opens a PR through `/source-control:pull-request create` in `melodic-software/claude-code-plugins` only; `allowed-tools-pairing.test.sh` and `README.md` are updated for `Workflow(multi-agent:registry-audit)` and the `registry-fetcher` gate.
