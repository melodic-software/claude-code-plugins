---
bump: minor
---

### Added

- A skill leaf's `applied-by` names what it hands on, keyed by artifact (`patch`,
  `feedback-replies`, `dependency-verdict`, `work-outcome`), and the script activity that applies
  each. Only a skill with effect `read` and gating `advisory` sets it. The config reader rejects
  (`invalid-applied-by`) a target that is not a script activity, a `patch` target without
  `prepare: apply-patch`, and a lane that holds the producer without the target in a slot that
  needs it. `resolve-config` emits the map in the resolved activity and takes an
  `applied-by-supported` input, which `pr-run-activity-read.yml` passes as `patch`. A `read` skill
  whose `applied-by` sets `patch` gets the edit tools of a write skill, commits nothing, and is not
  asked to fix instruction surfaces or CODEOWNERS paths. No activity in this repository sets it
  yet ([README](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#activities)).
- `.github/actions/resolve-config/patch-rules.json`, with its schema, registers what an apply-patch
  script is to admit from each producer's patch: one row per prepare mode, plus `default` and `issue`.
  Every row refuses `.github/**`, `.claude/**`, the root `.mcp.json`, `.gitmodules`,
  `**/settings*.json`, symbolic links, gitlinks, a new executable bit and a rename into any of
  those; a row without that set, or a two-parent commit whose `allow` is not exactly `[merge-result]`, is rejected.
  `resolve-config` checks the registry before every lane resolve and fails closed without it; the
  lanes token broker does not read it
  ([README](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#patch-rules)).

### Changed

- `web-access`, `self-checks` and `verify-scripts` no longer require an effect other than `read`;
  `web-access` still requires `reads-untrusted: true`. `version` stays 2.

### Removed

- The `funding` map. No workflow read it: each lane's workflow names its funding role as a literal
  ([README](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#funding)).
