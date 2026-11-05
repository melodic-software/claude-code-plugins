---
bump: patch
---

### Changed

- The grounding, setup and sync `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Three of the nine legacy cases become new cases: `su-check-claimed-present`, `su-check-auth-error` and `sy-refresh-refused`. Five were already covered by `gr-covered-topic`, `gr-export-injection` with `gr-export-injection-names`, `su-check-disabled` and `sy-check-report-only` (two cases), and three of those cases gain a grader: `gr-export-injection` checks the reply still answers the outbox question, `su-check-disabled` that it never claims to have read `/mcp`, and `sy-check-report-only` that it reports the failed fetch rather than an invented drift result. The legacy mechanical-rename case was dropped because it measured nothing: with no Dometrain tool in a run, its no-search expectations pass with or without the plugin, and `gr-off-catalog` already guards the skip path. The legacy already-enabled case now checks that setup does not report connected on the user's word, because no Dometrain tool resolves in an eval run. All three `evals.json` files are deleted.

### Fixed

- `sync`'s `update.sh`, when no baseline exists, now says that seeding it with `--refresh-baseline` is a maintainer step in a working clone. The skill relays this output verbatim and never runs the flag itself.
