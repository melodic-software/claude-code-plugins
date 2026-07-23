# Changelog

All notable changes to `repo-fleet-hygiene` are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.0]

### Fixed

- **Fleet config is no longer silently ignored outside the project that wrote it (#1099).**
  The audit consumed config only from `${CLAUDE_PROJECT_DIR}/.claude/repo-fleet-hygiene.conf`,
  so a machine-scoped fleet config authored in one directory vanished the moment the audit ran
  from any real project — silently narrowing to that single project with no mention of the
  existing file. The collector now owns a resolution ladder: explicit `--config`, else the
  project-scoped file, else the user-global `~/.claude/repo-fleet-hygiene.conf` (a file placed
  there is recorded user intent, not a guessed machine root; `$HOME` with `%USERPROFILE%`
  fallback). The report header names the consumed config and its source — or states that none
  was consumed — so silent non-consumption cannot recur. An invalid auto-probed config fails
  loud rather than falling back to a narrower scope. Setup's `check`/`apply` output states the
  scoping rule and the user-global placement option. Ladder covered by four new test cases.

## [0.2.0]

### Changed

- **`setup` split onto the uniform check/apply contract.** `check` inspects the optional
  `.claude/repo-fleet-hygiene.conf` read-only (presence — absent is INFO, since the audit defaults to
  the current project — parse validity, entry-path resolution, `maxDepth` range, and canonical-key
  normalization) and reports a PASS/FAIL/INFO table; `apply` creates or updates the file
  non-interactively from its argument grammar, then re-runs `check` to verify. Config-writing behavior
  and the argument grammar are unchanged; the read-only inspection path and the argument-hint gain the
  `check | apply` prefix.

## [0.1.0]

### Added

- Read-only fleet discovery across explicit repositories and bounded repository-tree roots.
- Git-native canonical checkout resolution with explicit/configured overrides.
- Per-repository GitHub merged-PR evidence with local-tip drift detection.
- Worktree porcelain parsing, missing/prunable registration reporting, and actual-versus-expected
  common-directory mismatch detection.
- GitHub transfer/rename detection by comparing the configured remote identity with the REST result's
  canonical `full_name`; hard 404/403/network failures remain unknown.
- Fail-closed canonical-identity and worktree-inventory gates that prevent unrelated local evidence or
  a failed attachment query from producing a cleanup candidate.
- Control-safe report rendering: newline/ANSI-bearing paths are encoded as one field and cannot forge
  finding, confidence, or handoff lines.
- Fail-closed Git/gh command allowlists, Git lazy-fetch/optional-lock suppression, and explicit GET-only
  GitHub API access with non-interactive/update-free environment controls.
- NUL-delimited branch inventory with producer-status capture; partial or failed ref enumeration is
  discarded as `UNKNOWN` and does not increment the successful-repository count.
- Bounded GitHub calls with a 30-second TERM deadline, five-second KILL escalation, compatible
  coreutils detection, and a portable Bash watchdog fallback.
- Confidence-tiered reports, exact non-destructive handoffs, setup/config documentation, contract
  tests, model evals, and a plugin-acceptance security review.
