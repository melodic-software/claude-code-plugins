---
bump: minor
---

### Changed

- fix-ci runs on ci-workflows' run-claude-cli v0.54.0, on the automations role's API key first.
  pr-unblock.yml calls the read runner twice, each call with one Claude secret: `fix-ci` passes
  only `AUTOMATIONS_CLAUDE_API_KEY`, and `fix-ci-subscription` passes only
  `AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN` and runs only when the first call's key leg hit a credit
  stop or its key is empty. A call that hands off uploads nothing, records no lane outcome and
  posts no check; the fallback call's lane record names why it ran. Both calls queue in the
  per-PR write group
  ([pr-run-activity.md, Two calls on one credential each](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#two-calls-on-one-credential-each)).
- The read runner stages a PR-mode skill's plugin, CI context, scratch directory and prompt
  under `.lane/` in the checkout, which `--restricted` can read, and leaves `.lane/` out of the
  patch. A head that already holds `.lane` fails red.
- fix-ci's patch goes through
  [`apply-patch.mjs`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/scripts/apply-patch/apply-patch.mjs)
  as the `apply-patch` activity, named in fix-ci's `applied-by`. The `ci-context` row of
  [`patch-rules.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/actions/resolve-config/patch-rules.json)
  caps a patch at 300 files and gains the optional `instruction-path` refusal, so fix-ci still
  pushes no agent instruction path. apply-patch refuses a row with no `requires` list.

### Removed

- The read runner's `output-mode` input: patch mode follows the activity's `applied-by.patch`,
  and issue mode refuses an activity that names no patch.
- `apply-ci-fix` and `.github/scripts/pr-unblock/apply-ci-fix.mjs`.
