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
  patch. A head that already holds `.lane` fails red. A staged plugin with no `.mcp.json` gets
  an empty server list, and the patch leaves out the CLI's empty scrub stubs; a stub name the
  head does not track that holds anything else fails the collector, so nothing is collected.
- fix-ci's patch goes through
  [`apply-patch.mjs`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/scripts/apply-patch/apply-patch.mjs)
  as the `apply-patch` activity, named in fix-ci's `applied-by`. The `ci-context` row of
  [`patch-rules.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/actions/resolve-config/patch-rules.json)
  caps a patch at 300 files and gains the optional `instruction-path` refusal, so fix-ci still
  pushes no agent instruction path. apply-patch refuses a row with no `requires` list.
- `collect-patch.sh` runs git against a fresh scratch repository that borrows only the checkout's
  objects, so no filter, hook, fsmonitor or include the activity planted in `.git` runs. The PR-mode
  leak scan applies the patch onto the gated head, as apply-patch does, and scans every file it
  makes; it scans copies of the reply and patch that the uploads then read, and the run's
  `patch-sha256` is the scanned copy's.
- The read runner's PR-mode model job uploads nothing and writes no step summary. It hands the
  reply, the run fields and the patch to a new scan job as job outputs sealed with
  `seal-lane-output` to the committed `.github/lane-keys/scan-carrier.pub`, each with its byte
  count, with the patch capped at 256 KiB. The scan job runs with `contents: read`, no `id-token`,
  and in the `pr-pipeline-scan-carrier` environment, whose `SCAN_CARRIER_PRIVATE_KEY` its
  `open-lane-output` step alone reads; each caller passes it by name as `scan-carrier-private-key`,
  and `scripts/check-scan-carrier-secret-shadow.sh` fails when a repository or organization
  secret shares the name. It fails closed on a withheld, oversize, mismatched or
  unopenable output, scans against a fresh checkout of the gated head, and is the only job that
  uploads the reply, patch and verdict
  ([pr-run-activity.md, The scan job](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#the-scan-job)).
- The read runner's dirty-tree check runs through `collect-patch.sh` and prints no path, and a
  PR-mode run removes the workspace's `.git` and `.base/.git` after the collector, so no git
  config the model planted runs after its legs.

### Removed

- The read runner's `output-mode` input: patch mode follows the activity's `applied-by.patch`,
  and issue mode refuses an activity that names no patch.
- `apply-ci-fix` and `.github/scripts/pr-unblock/apply-ci-fix.mjs`.
