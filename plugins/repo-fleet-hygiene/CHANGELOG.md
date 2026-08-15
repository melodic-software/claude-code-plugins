# Changelog

All notable changes to `repo-fleet-hygiene` are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.21.0]

### Added

- **Worktree-root conformance against the configured convention (#2606).** The audit reads
  `melodic.worktreeroot` (git config, gated on `rev-parse --git-dir`, attributed with
  `--show-origin`) when present on the first resolvable TARGET, else source-control's
  `worktree_root` (`CLAUDE_PLUGIN_OPTION_*` or user `pluginConfigs`). Linked worktrees that pass
  existence and root-verifiability checks are classified as conforming, outside the root /
  wrong `<owner>-<repo>-<slug>` layout (expected location named; physical-path comparison so
  symlink aliases of the configured root do not false-positive), or tool-owned (Codex/Cursor).
  Missing / unverifiable / non-root registrations keep their own findings and are excluded from
  conformance denominators. The collector uses one fleet-wide root (intentionally different
  per-repository `includeIf` roots are not modeled). When `pluginConfigs` cannot be read because
  `jq` is missing, emit `UNKNOWN` `worktree-root-pluginconfigs-unreadable` instead of a false
  unconfigured report. When no root is configured, placement is reported without asserting a
  convention. Per-repository and fleet rollups always state the classifiable counts — including
  when every classifiable linked worktree already conforms.

## [0.20.0]

### Added

- **`merged-remote-branch` findings for heads still on origin after merge (#2607).** When
  `delete_branch_on_merge` is not enabled (or a remote head survived), the collector reports merged
  remote branches that remain on the configured remote and hands off exact cleanup guidance.
  Enabling GitHub auto-delete remains complementary and is not changed by this release.

### Fixed

- **`merged-remote-branch` requires live remote proof for HIGH (#2607 review).** A last-fetched
  remote-tracking tip match alone does not prove the head still exists after merge-and-auto-delete
  without a pruning fetch. The collector now runs allowlisted `git ls-remote --heads` before HIGH;
  probe failure demotes to MEDIUM (cached observation); empty ls-remote emits no finding.


## [0.19.2]

### Changed

- **The plugin contract now matches its fleet-level job (#2597).** README, manifest, and audit-skill
  framing assign machine-wide discovery, evidence rollup, and action-plan handoff to
  `repo-fleet-hygiene`, while per-repository branch/worktree decisions and cleanup remain with
  `repo-hygiene` and `source-control`.
- **The fleet cleanup-plan boundary is explicit.** The machine-readable rollup from #2608 is on
  `main`; a future consumer groups repository-qualified actions for the sibling owners, requires one
  explicit fleet confirmation, and re-derives mutable OIDs before execution. This release still
  refuses to invent an execute/auto-delete mode until that consumer ships.
- **Remaining unshipped epic capabilities are named as contracts, not advertised as commands.**
  Worktree-root conformance (#2606) remains a child-issue contract. GraphQL merge evidence (#2604)
  and rollup/handoff framing (#2608/#2609) are on `main`; merged remote branches (#2607) track the
  open follow-up PR.

## [0.19.1]

### Changed

- **Bare paths and drive roots are valid discovery roots (#2599).** A positional `<dir>` (including
  Windows drive roots such as `D:`) is equivalent to `--root <dir>` (normalized to `D:/`). Symlinked
  discovery roots are refused. A `--root` that exists but is not readable/executable hard-fails with
  `discovery root is not traversable` instead of recording a `ROOT_LABEL` and reporting a clean empty
  audit. An empty walked root remains a valid zero-repository audit.
- **No-argument audits no longer fall back to the session project directory (#2599).** Without a
  bare path, `--root`/`--repo`, or config-supplied `fleet.root`/`fleet.repo`, the collector hard-fails
  and names how to set scope (`/repo-fleet-hygiene:setup apply` or explicit CLI roots). This is a
  breaking change for bare `/repo-fleet-hygiene:audit` invocations that previously audited
  `$CLAUDE_PROJECT_DIR` as an implicit `--repo`.

## [0.19.0]

### Fixed

- **Restore aliased GraphQL merge evidence, per-repository rollup, and fleet action plans after
  the #2633 squash regression.** The bare-repo merge accidentally replaced the collector with a
  pre-GraphQL script, dropping `MERGED_PR_GRAPHQL_*`, rollup/`--apply-plan`, and related tests
  while the changelog still documented 0.17.0/0.18.0 behavior. Re-integrates those surfaces with
  `#2602` bare-repo classification and `#2598` discovery-skip degradation.

## [0.18.2]

### Added

- **`bare-repo-with-working-tree` finding (#2602).** A path with `core.bare=true` that still has
  populated working-tree content or registered linked worktrees is classified as `MEDIUM` manual
  review instead of rejected as "not a Git working tree". The finding names
  `git config --local core.bare false` as the preferred remedy and states that linked worktrees are
  unaffected. Discovery and `--repo` no longer abort the whole run on this administrative anomaly.
  Ordinary `git init --bare` hubs (administrative entries at the repository root, no `.git`
  subdirectory) are not this finding.

## [0.18.0]

### Added

- **Per-repository rollup is the default audit presentation (#2608).** The report opens with a
  fleet header and a per-repository rollup of counts by finding kind, plus an explicit
  `CLEAN` / `N candidates` / `BLOCKED (evidence gap)` verdict (and a fleet verdict). Per-item
  evidence moves behind `--detail`, where findings are collapsed to one entry per target so a
  path that carries both `locked-worktree` and `worktree-nested-in-repository` is triaged once.
- **Fleet-scale action plan + `--apply-plan` dry-run (#2609).** Every audit writes a
  machine-readable action-plan JSON (path via `--plan-file`, otherwise a temp file named in the
  report) that lists recommended skill invocations once per repository — `/repo-hygiene:clean git`
  for merged local branches, `/source-control:worktree cleanup --dry-run` for worktree candidates —
  ordered so branch cleanups precede worktree cleanups. `--apply-plan PATH` re-renders that plan as
  a single-gate dry-run approval artifact; producing or applying the plan never mutates. Re-derive
  OIDs at real execution time.

### Fixed

- **Plan JSON preserves UTF-8 paths (#2608/#2609 review).** `json_escape` no longer turns each
  non-ASCII UTF-8 byte into a separate `\u00XX` code point (which mojibaked paths such as `répô`);
  ASCII controls stay escaped and UTF-8 sequences pass through intact.
- **Action-plan targets are real array elements (#2609 review).** Paths may legally contain
  newlines, and bash scalars cannot store NUL, so in-band delimiters are unsafe. Targets are kept
  as parallel `ACTION_TARGET_OWNER` / `ACTION_TARGET_VALUE` entries so one path cannot forge several
  plan targets.
- **Unwritable `--plan-file` fails closed (#2609 review).** A failed plan redirection now exits
  nonzero via `fail` before the report claims `Action plan: <path>` or prints an `--apply-plan`
  command for a missing artifact.
- **Rollup candidates track actionable kinds (#2608 review).** `N candidates` / fleet candidate
  counts follow `merged-local-branch` and worktree cleanup plan kinds, not mere HIGH/MEDIUM
  confidence — so manual-review findings such as `locked-worktree` or `merged-pr-tip-drift` no longer
  inflate candidates while `Actions: none`.

## [0.17.0]

### Changed

- **Merged-PR evidence uses aliased GraphQL and retires REST window/privacy findings (#2604).** One
  `gh api graphql` query per repository page (≤100 exact `headRefName` aliases, `first:1`,
  `states:[MERGED]`) replaces per-repo `gh pr list --state merged` and the privacy-gated `--head`
  fallback. Measured rate cost stays 1 per call. Retires `merged-pr-window-truncated` and
  `merge-evidence-privacy-gated`. Fail-closed `github-pr-evidence-unavailable` when GraphQL fails.
  Branch matching stays exact (`feature/auth` never conflates with `feature/auth-v2`).

## [0.14.1]

### Fixed

- **Discovery husks under `--root` no longer abort the fleet (#2598).** A path discovered beneath a
  `--root` that is unreadable or not a Git working tree (despite a `.git` marker) now degrades
  per-entry like a stale config entry: the audit continues, the header reports
  `Discovery skips: N non-repository, M unreadable`, and each `.git` husk becomes an `UNKNOWN`
  `discovery-skip` finding. An explicitly supplied `--repo` that is not a working tree still
  hard-fails. SKILL.md graceful degradation and the confidence-model tier table updated to match.

## [0.14.0]

### Changed

- **Worktree disposability ownership moves to `source-control:worktree` (#2605).** Linked unlocked
  worktrees with reliable admin emit one `MEDIUM` `worktree-status-handoff` per repository naming
  those paths and routing to `/source-control:worktree status` (stranded / unknown / safe). The
  collector no longer emits `reclaimable-worktree` or `worktree-disposability-unverifiable` from
  `git status --porcelain`. When `source-control` is absent, name the listed targets and the missing
  collaborator — do not substitute a weaker verdict. Retires the weaker fleet-local reclaimable axis
  relative to #2601's ignored-files hardening of that same finding.

## [0.13.2]

### Fixed

- **Moved-identity checkouts keep branch and worktree analysis (#2600).** Emitting
  `github-remote-moved` no longer reads as a silent stop: evidence states that classification
  continues against the resolved `full_name`, and the collector regression fixture requires both
  `merged-worktree` and `merged-local-branch` exact-OID findings from that resolved identity.

## [0.13.1]

### Fixed

- **`merged-pr-tip-drift` evidence no longer claims commits "may never have been pushed" (#2603).**
  Absence from the last-fetched remote-tracking ref does not prove the tip was never on GitHub —
  post-merge head deletion plus prune is the common case, and the tip object may still exist on the
  remote. The non-matching push-state clause now states that the tip differs from the merged PR
  `headRefOid` and that commits may still be on the remote.

## [0.13.0]

### Added

- **`reclaimable-worktree` finding (#1776).** Linked, unlocked worktrees with reliable admin and an
  empty `git status --porcelain` at the work-tree root emit `MEDIUM` evidence for a worktree cleanup
  dry-run handoff. Working-tree cleanliness is not proof the checkout is still wanted; stash list is
  deliberately out of scope. A failed status probe emits `UNKNOWN`
  `worktree-disposability-unverifiable`.

## [0.12.1]

### Fixed

- **`merge-evidence-privacy-gated` handoff no longer prescribes impossible remedies (#1796).** The
  aggregate handoff had told operators to push or re-fetch pruned branches to "restore remote
  evidence" — but for the dominant population (merged heads auto-deleted on GitHub, then pruned
  locally) re-fetch cannot restore a ref that no longer exists upstream, and the skill boundary
  forbids suggesting `git fetch` inline. The handoff now distinguishes never-pushed locals (push,
  then rerun) from auto-deleted merged heads (verify merge state with
  `gh pr list --repo github.com/<owner>/<repo> --state merged --head <branch> --json headRefOid`
  per named branch and confirm `headRefOid` equals the local tip; merged PRs stay queryable after head
  deletion). Matching prose updates in `SKILL.md`, `confidence-model.md`, and eval expectations.

## [0.12.0]

### Fixed

- **`setup`'s verify step stays within its own boundary (#1801).** `apply` step 5 now enumerates the
  config-only `check` probes — parse validity, per-entry path resolution, `maxDepth`, and identity
  normalization — and explicitly forbids invoking the collector. A genuine end-to-end proof remains an
  opt-in handoff to `/repo-fleet-hygiene:audit`, stated as a real audit.
- **`setup` can set `maxDepth` through its argument grammar (#1801).** The body now documents
  `--max-depth <1..12>` alongside the frontmatter `argument-hint`, so the skill that owns the config
  file can write `[fleet] maxDepth` without hand-editing.
- **Cross-volume fleet roots no longer read as consumer error (#1801).** When a Windows fleet root sits
  on a different volume from the config file, the gotcha now states that the absolute path is the only
  honest form and names remedies when a path-portability guard still rejects it — colocate on one
  volume, exempt the file or path, or keep a user-global config outside the guard's scan.

## [0.11.0]

### Fixed

- **`/repo-fleet-hygiene:audit`'s grant has been dead since #1798 "fixed" it, for a reason nobody
  filed: a quote mismatch.** That issue corrected the variable half
  (`${CLAUDE_PLUGIN_ROOT}` → `${CLAUDE_SKILL_DIR}`) and explicitly parked quoting as "Unverified, not
  asserted." The shipped rule wrote the path unquoted —
  `Bash(bash ${CLAUDE_SKILL_DIR}/scripts/audit-fleet.sh *)` — while the body ran
  `bash "${CLAUDE_SKILL_DIR}/scripts/audit-fleet.sh" …` with the path quoted. A Bash rule is matched
  against the literal command string, so the character after the wrapper name is a closing quote
  where the rule expects a path: the grant never matched, and the fleet audit has been prompting or
  falling to the classifier ever since.

  The remaining half of #1798's advice — "drop the `bash` prefix only" — would not have fixed it
  either, and that correction is the point. `bash` is not among the wrappers Claude Code strips
  before matching (`timeout`, `time`, `nice`, `nohup`, `stdbuf`, `command`, `builtin`, `noglob`), so
  a rule without `bash` stops matching a body that still says `bash <path>`, and dropping the prefix
  addresses nothing about the quoting. The change is **paired** on both axes: the body invokes the
  script directly and unquoted, and the rule names that exact string,
  `Bash(${CLAUDE_SKILL_DIR}/scripts/audit-fleet.sh:*)`. The arguments the skill passes stay quoted
  individually — it is a prefix rule, so their quoting does not affect the match.

### Added

- **`scripts/allowed-tools-pairing.test.sh`**, which encodes the failure #1798 could not assert:
  besides rejecting an interpreter-led grant and `${CLAUDE_PLUGIN_ROOT}` in `allowed-tools`, it fails
  on a quoted bundled-script path in any skill markdown, because an unquoted rule will not match one.

## [0.10.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.9.0]

### Added

- **Three worktree findings the collector could not previously express.**
  `worktree-not-a-root` (HIGH) fires when a registered path exists but
  `git rev-parse --show-prefix` is non-empty: the path is a subdirectory of a work tree rather than
  its root, so every `git -C` probe of it answers with the CONTAINING repository's state at exit 0
  — indistinguishable from a healthy clean worktree, and the shape that makes a leftover directory
  read as safe to remove. `worktree-root-unverifiable` (UNKNOWN) covers the case where that probe
  itself fails; both stop worktree classification for that registration rather than describing the
  wrong repository. `worktree-nested-in-repository` (MEDIUM) reports a non-main registration whose
  root sits inside the canonical checkout's own working tree instead of at an external root — the
  placement that makes a read matching a path-scoped rule's glob also load the parent checkout's
  copy of that rule.

  `rev-parse --show-prefix` joins the probe allowlist, matching `--show-toplevel`'s shape:
  read-only, operand-free, fixed arity. The containment test resolves the canonical checkout
  through git rather than reusing the discovered path, so both operands come from one source — a
  filesystem-derived path and a git-emitted one differ by drive spelling on Windows, and the
  comparison would silently never match.

### Fixed

- **A bare-clone hub silently skipped the placement check.** `canonical_top` is resolved with
  `git rev-parse --show-toplevel`, which fails on a bare repository by design, so
  `worktree-nested-in-repository` was never evaluated for any registration under a bare hub and
  nothing said so — a placement check that quietly did not run reads identically to one that ran
  and found nothing. A bare hub is now recognized as such (it has no working tree for a worktree to
  be nested inside, so the skip is legitimate) and any OTHER failure to resolve the working-tree
  root emits `worktree-placement-unverifiable` (UNKNOWN), matching what every sibling probe in the
  same function already does. `--is-bare-repository` joins the probe allowlist in the same
  read-only, operand-free, fixed-arity shape as `--show-toplevel` and `--show-prefix`.

- **`worktree-root-unverifiable` had no test coverage.** The mock's `--show-prefix` arm returned
  success for every input, so the collector's probe-failure branch was dead code as far as the
  suite was concerned and a regression in it — a wrong confidence tier, message drift, a dropped
  `continue` that let the wrong-repository probes run anyway — would have gone undetected. A
  fixture now fails that probe, following the same shape the suite already uses for the worktree
  inventory.

- **The SKILL.md handoff row overstated what one of two findings proves.** It asserted that "every
  `git -C` probe describes the containing repository" for `worktree-not-a-root` AND
  `worktree-root-unverifiable`, but that is established only for the former. The latter's probe
  FAILED, so root-ness is unproven rather than disproven — which `confidence-model.md` already
  stated correctly. The two now have separate rows.

## [0.8.1]

### Fixed

- **The merged-PR evidence window now covers busy fleet repositories (#1795).** The
  repository-scoped `gh pr list --state merged` query now covers the most recent 1000 PRs instead
  of 200 while preserving the existing `UNKNOWN merged-pr-window-truncated` disclosure when that
  finite cap binds. The batch and exact-head limits are shared with the probe allowlist so their
  admitted arguments cannot drift from the call sites.

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
  file rather than a directory, so an ordinary fleet sweep pays nothing per repository. The
  substitution is disclosed rather than applied silently — the operator named one path and the
  report is about another — on one `Resolved to main worktree:` header line per repository naming
  every path that resolved into it, so several worktrees of one repository cannot read as several
  repositories against the discovered count. Evidence rule 1 in both skills is corrected to match.

  The porcelain's first record is **not** always a checkout, and three ordinary shapes all present a
  `.git` file so they reach the retarget: a submodule reports the superproject's
  `.git/modules/<name>` administrative directory, `--separate-git-dir` reports the detached git
  directory, and a worktree of a bare repository reports the bare repository. Adopting any of them
  would aim every handoff *inside* another repository's administrative directory — the precise harm
  this retarget exists to prevent. The porcelain's answer is therefore re-resolved as a working tree
  before it is adopted: bare and `--separate-git-dir` fail that probe and are skipped, a submodule
  resolves back to the path already held and self-cancels, and a genuine linked worktree retargets.
  All four shapes are pinned by regression fixtures.
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
  `repositories_audited`). An empty `--root`/`--repo`/`--config` value stops the run rather than
  being counted toward the scope the header reports and then skipped by the discovery loops.
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
