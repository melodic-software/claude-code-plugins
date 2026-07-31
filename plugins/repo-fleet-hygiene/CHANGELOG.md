# Changelog

All notable changes to `repo-fleet-hygiene` are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.8.0]

### Fixed

- **Canonical resolution can no longer select a linked worktree (#1797).** Discovery reaches a
  linked worktree and its own main worktree through the same glob, and both map to one
  `--git-common-dir` dedup key, so the winner was decided by glob order. A sibling whose directory
  name sorts before the canonical one under `LC_ALL=C` therefore became "Canonical" — and every
  emitted handoff carries that path, so per-repository cleanup would be aimed at a checkout that is
  not the repository of record, while the real canonical checkout was deduplicated away and never
  reported. `add_target` now resolves each candidate to its main worktree, read as the first record
  of `git worktree list --porcelain` (which lists the main worktree first wherever it runs), before
  the dedup tie-break. `rev-parse --show-toplevel` cannot make this distinction: inside a linked
  worktree it returns the linked root. The extra probe is gated on the candidate's `.git` being a
  file rather than a directory, so an ordinary fleet sweep pays nothing per repository. Evidence
  rule 1 in both skills is corrected to match.
- **The `allowed-tools` grant used a variable that is not substituted there (#1798).** The rule named
  `${CLAUDE_PLUGIN_ROOT}`, which the skills documentation does not list among the variables
  substituted in skill content or `allowed-tools` Bash rules — only `${CLAUDE_SKILL_DIR}` and
  `${CLAUDE_PROJECT_DIR}` are. The rule stayed a literal string, never matched the real invocation,
  and the skill's one permission grant was inert in a workflow built for unattended sweeps. Both the
  grant and the documented invocation now use `${CLAUDE_SKILL_DIR}`.
- **The project-scoped config rung is reachable again (#1798).** The collector read
  `CLAUDE_PROJECT_DIR` from its own environment, where it is not provided — that variable is
  documented for hooks, MCP stdio servers, and skill content, not for Bash tool invocations. The
  project rung of the config ladder therefore resolved against nothing, and the zero-argument
  fallback silently became `$PWD`, an agent session's incidental working directory. The skill body
  now passes `--project-dir "${CLAUDE_PROJECT_DIR}"`, where the documented substitution applies; the
  environment variable is still honored for callers that genuinely have it, and a value left as an
  unexpanded `${...}` placeholder counts as absent. When no project directory resolves, the run
  stops with the scope remedies instead of auditing whatever directory the shell was sitting in.
- **Report text no longer asserts things the run contradicts (#1800).** The header printed a fixed
  `Config: none (… current-project scope)` literal that could contradict the very next lines — it
  claimed project scope on a run whose scope came from `--root`, and described a mode that was not
  reachable at all. A computed `Scope:` line now names each rung that actually contributed and its
  entry count, which also discloses that config-supplied scope is additive to CLI-supplied scope.
  `Mutation count: 0` was a hardcoded literal that would have read identically in a build that
  mutated; it is replaced by a statement of the enforcing mechanism (the read-only git/gh command
  allowlists), because a real counter would undercount — most probes run inside command
  substitution, so increments are lost with the subshell. On Windows, MSYS-style `/c/...` paths are
  converted to `C:/...` for presentation only, since the report is actionable text whose paths get
  pasted into tools that reject the MSYS form. The two differently-scoped `repositories` counts are
  now labelled distinctly (`Repositories discovered (audit targets after deduplication)` and
  `repositories_audited`).
- **`setup`'s verify step no longer violates `setup`'s own boundary (#1801).** `apply` step 5
  prescribed running the collector, which is the full fleet walk the skill states it never performs —
  minutes of per-repository network queries in a step described as validating that a config parses.
  Verification is now config-only (parse validity plus per-entry path resolution); an end-to-end run
  is an explicit handoff to `/repo-fleet-hygiene:audit`.
- **`setup` can set `maxDepth` (#1801).** The grammar `setup` documents and owns includes `maxDepth`,
  and the collector implements `--max-depth`, but `setup`'s argument grammar had no way to write it,
  so a consumer needing a non-default depth had to hand-edit the file `setup` manages. `--max-depth`
  is now part of `setup`'s grammar, and `--max-depth` was missing from the audit skill's
  `argument-hint` as well.

### Changed

- **A truncated merged-PR window is disclosed (#1803).** The batched merged-PR query returns at most
  200 rows; a repository with more merged history silently lost the remainder, and a branch merged
  before the window then produced no merged finding — indistinguishable in the report from a branch
  that was never merged. A full window now emits `merged-pr-window-truncated` (`UNKNOWN`) saying
  that absent merged findings in that repository are unproven. It cannot distinguish "exactly 200"
  from "far more" and deliberately errs toward warning.
- **The confidence model documents every finding kind and what the tiers rest on (#1799).** The tier
  table covered 12 of 24 emitted kinds, so a consumer meeting an untabulated kind had no documented
  disposition. It now covers all 25, and a test asserts set equality in both directions between the
  table and the collector's emitted kinds, so this drift is a test failure rather than a later
  discovery. `ACKNOWLEDGED` is documented as a prominence demotion of an `UNKNOWN`, not a fifth
  confidence value. Evidence rule 3 now describes the mechanism that actually runs — one batched
  query per repository plus a privacy-gated per-branch fallback — rather than a per-branch
  authoritative query. Two undisclosed dependencies are stated: the `LOW` ancestry tier is near-inert
  under squash merges, and `missing-worktree` versus `prunable-worktree` turns on the user-tunable
  `gc.worktreePruneExpire` window rather than on evidence strength. The two reference files that had
  no pointer from the hub are now linked.

### Added

- **Behavioural coverage for the failures a real fleet produced (#1803).** The suite exercised the
  documented happy path while a single 11-repository run surfaced defects none of it could reach.
  New executable assertions cover canonical selection against an earlier-sorting linked worktree
  (constructed red first), the computed scope-provenance line, merged-PR window truncation,
  unauthenticated-`gh` degradation, and tier-table/collector drift. New model-graded evals cover
  privacy-gated branches as unverified rather than unmerged, squash-merge semantics, worktree
  disposability as deliberately out of scope, and — for `setup` — config-only verification,
  cross-volume paths, and `maxDepth`.

## [0.7.1]

### Fixed

- **A no-scope audit from a non-Git project directory now names the remedy (#1771).** With no
  `--root`, `--repo`, or `--config` and no config on the ladder, the audit uses the session's
  project directory as an exact repository target. When that directory is not a Git working tree —
  the shape of the very first invocation on a machine whose fleet lives elsewhere — the run stopped
  at `Error: not a Git working tree: <path>` and said nothing else, so recovering meant reading the
  collector source to learn that the implicit default was a `--repo` rather than a discovery root.
  The implicit target now carries its own rejection origin: it still fails closed, and the failure
  now lists `--root`, `--repo`, and `--config` with a pointer to `/repo-fleet-hygiene:setup apply`.
  An explicitly supplied bad path stays terse — the operator just passed a scope, so repeating how
  to pass one is noise. When a config WAS consumed but carries no `fleet.root`/`fleet.repo` entries
  (only `maxDepth`, acknowledgments, or overrides), the rejection no longer claims `--config` was
  omitted: it names the consumed config and directs scope into it. The skill body described the
  same default in discovery-root terms and now states that it is an exact target.

## [0.7.0]

### Changed

- **Stale config entries degrade per-entry, not per-run (#1121).** A config-sourced
  `fleet.repo`/`fleet.root` path that is missing or no longer a Git working tree becomes an
  `UNKNOWN stale-config-entry` finding (naming the path, the reason, and the config source) and the
  rest of the fleet is still audited — deleting five repositories right after an audit no longer
  aborts every subsequent run until the config is edited. CLI-supplied `--repo`/`--root` paths still
  hard-fail (a typo should stop the run), as does invalid config syntax. SKILL.md graceful
  degradation updated to match.

### Added

- **Duplicate checkouts surfaced (#1121).** Multiple audited checkouts resolving to the same
  normalized GitHub identity are still audited independently (correct — same-identity clones have
  independent local state), but the coincidence now yields one LOW informational
  `duplicate-checkout` finding per identity listing the checkout paths. Guaranteed LOW-only.
- **README names the deletion-triage owner (#1121).** "Can I delete this repository safely?" is
  disposability analysis owned by `/repo-hygiene:clean` (scan/stash/git tiers); the README's new
  "What this does not answer" section points there. The deletion-triage inventory itself was
  declined by design for this read-only report — recorded in the source handoff item's resolution.

## [0.6.0]

### Added

- **Drift findings name the push state (#1120).** `merged-pr-tip-drift` evidence now states whether
  the local tip matches the last-fetched remote-tracking ref — the fact that changes the cleanup
  risk profile. The wording is deliberately cached-observation, not current-reachability: a
  tracking ref only records what the remote advertised at the last fetch (the branch may have been
  deleted or force-pushed since), so a match reads "pushed as of the last fetch; verify current
  remote state before relying on recoverability". Computed from the remote-ref OIDs the
  enumeration already collected and previously discarded; purely local, no network. When the
  remote-tracking inventory is unavailable the evidence says "push state unknown" instead of
  guessing.
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
