---
bump: minor
---

### Changed

- The unattended merge gate merges a MED score whose every reason is a class or size reason (`class-contradicted`, `blast-radius-missing`, `lines-over`, `files-over`, `no-patch:*`), as it does LOW (#9270). Unbound or missing review evidence, an open claude-review finding, an unread file listing, the rung and every HIGH reason still hold, and such a MED gets no reasons comment or risk escalation.
- The security lane holds the merge only on a CRITICAL finding. The gate reads each inline comment's `severity:` line and the summary's `critical-findings:` line; a finding whose severity it cannot read counts as CRITICAL.
- The HIGH path floor holds only what has an effect outside the repository or its review: `**/settings*.json`, `.gitmodules`, `CODEOWNERS`, package manifests and lockfiles, the workflows that publish a release or hold `id-token: write`, and `check-trusted-trigger`. Agent instructions, hooks, `bin`, `lib`, scripts, monitors, `.mcp.json` and `.lsp.json`, the review and merge-gate plugins, `docs/conventions` and the rest leave it, as do the capability, test-only, eval-data, eval-scaffold, script-mode and base-side declaration checks. `merge.diff-check.floor-paths` and `floor-script-scopes` are gone.
- `manifest-review-required` holds only a `plugin.json` change to `hooks`, `mcpServers`, `lspServers`, `monitors` or `experimental.monitors`, and a marketplace plugin added, removed, renamed or re-sourced, or the marketplace renamed.
- A `work-class: structural` label scores as `C3` (scoped), in the local merge gate and the promotion evidence.
- `NEVER_FLOOR_EXEMPT` is the HIGH path floor, and `INSTRUCTION_PATH_RE` (twin of `thread-scope.mjs` `INSTRUCTION_PATH`) names only submodule, code-owner, agent permission and package manifest files; the review-thread tool `feedback-thread.sh` reads the same set.
