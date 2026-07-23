# Changelog

All notable changes to `repo-fleet-hygiene` are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.6.0]

### Added

- **Drift findings name the push state (#1120).** `merged-pr-tip-drift` evidence now states whether
  the local tip exists on the same-named remote-tracking ref — the fact that flips the cleanup risk
  profile (pushed drift is recoverable from the remote after deletion; unpushed drift is data
  loss). Computed from the remote-ref OIDs the enumeration already collected and previously
  discarded; purely local, no network. When the remote-tracking inventory is unavailable the
  evidence says "push state unknown" instead of guessing.
- **Report header names the authenticated gh account (#1120).** `GitHub evidence: available
  (account: <login>)` — a dozen `HTTP 404` UNKNOWNNs read very differently under the wrong login
  than under the right one. Probed via a narrowly allowlisted `gh api user` GET with a fixed
  template (mirroring the `repos/{slug}` allowlist shape); any probe failure keeps the plain
  header line. This is the cheap subset of the tracked per-domain-gh-auth request.
- **Clean repositories say so (#1120).** A finding-less repository section now ends with an
  explicit `Findings: none` line and the same `---` terminator finding blocks use — clean output
  is distinguishable from truncated output.

## [0.5.0]

### Fixed

- **One repository with zero remote-tracking refs no longer aborts the whole fleet report (#1119).**
  The merged-PR exact-fallback gate expanded `REMOTE_BRANCH_NAMES` unguarded — the script's only
  value-expansion of a possibly-empty array without the `:-` idiom its siblings use. Under `set -u`
  on bash ≤ 4.3 (macOS system bash is 3.2.57; bash 4.4 removed the behavior) that expansion is a
  fatal unbound-variable error, and `analyze_repo` runs in the main shell — a never-fetched clone,
  a fully-pruned repo, or the partial-failure reset killed the entire run mid-report. Guarded with
  the sibling idiom plus an empty-string skip; repo-b in the test suite is documented as the
  empty-remote-inventory regression fixture.

### Added

- **Privacy-gated merged-branch misses are now visible (#1119).** The exact `--head` fallback stays
  fail-closed (a branch name never observed on the remote is never transmitted to GitHub), but the
  skip is no longer silent: branches with no batch evidence that the gate blocks from exact lookup
  are reported once per repository as an `UNKNOWN merge-evidence-privacy-gated` aggregate finding —
  the merged-then-auto-deleted-then-pruned branch now surfaces as a reportable evidence gap instead
  of vanishing. A repo-wide failed remote-ref scan keeps the aggregate quiet (the existing
  `remote-branch-inventory-unavailable` finding already covers every branch; new `rref-fail`
  fixture proves no double-report). The misleading fallback comment ("prevents a false negative" —
  untrue after head auto-delete + prune) is corrected, and the deferred widenings
  (`branch.<name>.merge`/`.remote` proof of prior push; batch-window pagination) are recorded there.

## [0.4.1]

### Added

- **Per-root discovery counts in the audit report header (#1101).** The header printed only the total
  `Repositories discovered: N`; a discovery root that walked to zero repositories left no trace, so a
  directory the user expected to be a repo had to be diffed against memory. Each `--root`/config `root`
  now prints `Root <path>: <k> repositories`, keeping a zero-contribution root visible without any
  per-directory noise. Covered by `audit-fleet.test.sh`.
- **`## Gotchas` surfaces on both skills (#1101).** The `audit` and `setup` skills now document the
  real first-contact gotchas: a project-scoped config is consumed only from its own project (fleet
  configs belong at the user-global path), and absolute paths in tracked config can trip a consumer's
  write-time path-portability guard where the relative form passes and resolves identically.

### Changed

- **`setup apply` prefers relative-to-config-dir paths (#1101).** `apply` now writes any
  root/repository/canonical target relative to the config file's directory when expressible that way —
  the two forms audit identically, and the relative form avoids consumer write-time path guards that
  reject absolute paths in tracked config.
- **`audit` skill trigger phrases are single-quoted (#1101).** The `Use when:` triggers are now
  single-quoted so the skill-quality checker's trigger-drop regression protection tracks them; every
  existing trigger keyword is preserved.

## [0.4.0]

### Added

- **`fleet.ackUnavailable` — acknowledge known-inaccessible GitHub identities (#1100).** In real
  fleets, many `github-identity-unavailable` UNKNOWNNs are foreseeable 404s (upstream repos made
  private/deleted; repos owned by a different GitHub account than the authenticated `gh` login) and
  re-reported at full prominence every run. The repeatable `ackUnavailable = github.com/owner/repo`
  config key demotes a 404/403 identity failure for that identity to a new `ACKNOWLEDGED`
  confidence — still reported with its real HTTP reason and the ack source, never suppressed, and
  counted separately in the summary (`acknowledged=N`). Acks never touch non-404/403 failures
  (network errors keep UNKNOWN prominence even for acked identities) or successful-response
  evidence (a rename still reports HIGH). The read-probe allowlist is extended narrowly
  (`--null --get-all fleet.ackUnavailable`); malformed ack values fail loud. Documented in the
  setup grammar and `check` (INFO listing); covered by ack-hit, unacked-404, and
  non-404-on-acked-identity test cases.

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
