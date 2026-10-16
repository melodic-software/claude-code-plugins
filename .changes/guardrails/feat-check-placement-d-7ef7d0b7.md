---
bump: minor
---

### Added

- Three git-hook entries in `git-hooks/entries.json`, registered with
  `/guardrails:setup apply install-git-hooks [scope=local|shared]` through the shared installer
  (lefthook, husky or plain hooks; local to this clone or committed under `.githooks/guardrails/`):
  `commit-msg-convention` checks the subject against the team-tracked `subject_pattern`,
  `pre-commit-content` checks secrets and machine-specific paths on the lines a commit adds, and
  `reference-verify` runs cli-flag-verify, skill-reference-verify and stale-path-verify on the
  lines the pushed commits add, as a `pre-push` entry because it costs about 10 s on a 44-file
  change. Each fails the commit or push on a finding and is declined per clone through
  `/guardrails:setup`, which also removes an installed entry's registration. A cli-flag
  finding's failure names that way out, since such a finding is unverified, not proven wrong.
- `block-no-verify` refuses a persistent `git config core.hooksPath <dir>` in any scope unless
  `<dir>` is exactly `.githooks`, and allows the check-placement skip key
  `git -c checks.skipmissing=<tool>`.

### Changed

- cli-flag-verify, skill-reference-verify and stale-path-verify no longer report after every
  Write or Edit; they run at push time in the `reference-verify` git hook. Their
  `cli_flag_verify_enabled`, `skill_reference_verify_enabled`, `stale_path_verify_enabled`,
  `cli_flag_verify_bins` and `cli_flag_verify_skip_bins` options are gone: decline the entry
  to turn it off, and set `CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_BINS` or
  `CLAUDE_PLUGIN_OPTION_CLI_FLAG_VERIFY_SKIP_BINS` in the pushing environment to change the
  scanned binaries.

### Removed

- `block-hook-bypass` and its `block_hook_bypass_enabled` and `block_hook_bypass_scratch_roots`
  options. A file a shell command writes is checked when it is committed, by the
  `pre-commit-content` git hook.
- `check-bash-file-changes` and its `bash_file_change_check_enabled` option; its path rules
  are in the `pre-commit-content` git hook.
- `/guardrails:setup apply install-commit-msg` and `apply install-pre-commit-content`, replaced
  by `apply install-git-hooks`. A hook either one installed is reported as a foreign hook the
  setup agent replaces, and `retirements.yaml` records the four files they wrote under
  `.git/hooks/` (`guardrails-r001` to `guardrails-r004`): `/guardrails:setup check` reports them
  and `apply` offers the gated cleanup.
