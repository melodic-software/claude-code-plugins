# Operator-gated sync tail

Read-only checks for the tail of the plugin-sync cluster (#4186, following #3733, #3728, #3734,
#3681, #3688). The script is `scripts/sync-tail-check.sh`. It does not write
`~/.claude/settings.json`, does not delete a cache tree, and does not edit standards,
ci-workflows, or github-iac.

## Decision

- **Claim:** Items that need the operator's settings file, a wiped host, or another repository are checked from this plugin and left for the operator to apply. A missing `Bash(gh pr merge *)` rule is printed as a seed. A removed marketplace cache is reported against both documented sweep windows. Adjacent drift is `open`, `clear`, `waiting-on-release`, or `unprobed`. `tree=absent` is unobserved, not proof the orphan sweep ran.
- **Basis:** [plugins-reference](https://code.claude.com/docs/en/plugins-reference) "Plugin cache", fetched 2026-09-28: "When you update or uninstall a plugin, the previous version directory is marked as orphaned and removed automatically 14 days later." [claude-directory](https://code.claude.com/docs/en/claude-directory), fetched 2026-09-28: "Orphaned versions are deleted 7 days after a plugin update or uninstall." The two pages disagree. [settings](https://code.claude.com/docs/en/settings) stores `permissions.allow` in the operator's settings file. This skill already refuses to silently fix drift.
- **As of:** 2026-09-28.
- **Recheck:** either page changes its orphan window, or a ci-workflows release absorbs `actions/checkout` so the managed-files-guard row flips from `waiting-on-release` to `clear`.

## What each row is

| Id | Check | Actionable status |
|---|---|---|
| permissions | `Bash(gh pr merge *)` in `permissions.allow`. A `--auto`-only rule does not count. | `absent` |
| orphan | Cache directories whose marketplace is absent from `known_marketplaces.json`, and the named `--marketplace` when its tree is gone. | `unmarked` or `overdue`. `pending` and `split` are reported and not failures. `absent` is `reason=unobserved`. |
| a | standards `components/claude-settings/targets` includes `account-rotation`. | `open` |
| b | ci-workflows `release.yml` cites a workflow path that is not in that repo. | `open` |
| c | ci-workflows README version sentence versus the latest release tag. | `open` |
| d | standards managed-files-guard acceptance bullet names `dependabot[bot]`. | `open` |
| e | github-iac dependabot ignore includes `melodic-software/ci-workflows/*`. A 404 is `unprobed`. | `open` |
| f | ci-workflows release header keys the version on published releases. | `open` |
| g | upstream claude-community SessionEnd hook. Always `unprobed` here. | none |
| h | standards managed-files-guard still runs `actions/checkout`. | `waiting-on-release` |

`--offline` prints the commands and does not call `gh`. `--fixture <dir>` classifies files the tests plant. A live run calls `gh` and degrades each failed read to `unprobed`.
