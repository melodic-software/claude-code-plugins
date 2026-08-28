# Changelog

All notable changes to the `source-control` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.55.26]

### Changed

- **Rate-limit-guard inline floor restored to byte-identity.** The loop-lane convention requires the
  floor identical across carriers; hashing found three distinct texts, the drift traceable to two
  de-slop shards that also introduced a comma splice. All five carriers now hash identically on an
  em-dash-free, grammatical form. Whole-repo extract-ssot sweep.

- **Telemetry-upsert reference prose normalized across the three lanes.** An em-dash purge had
  reached one copy only, leaving a comma splice and a dropped clause about what the creation-race
  reconcile does to a sibling instance's comment; the two unpurged copies disagreed with each other
  about it. No executable block changed. Whole-repo extract-ssot sweep.

## [0.55.25]

### Changed

- **Shared `hook-utils.sh` comment cleanup.** Comment-only sync from `lib/hook-utils.sh`: history-narration comments rewritten as present-tense rules; no behavior change.

## [0.55.24]

### Changed

- **Behavior-preserving simplification sweep, wave 8 (batch-simplify).** Each change
  adversarially refutation-verified with emitted bytes unchanged and the full 643-test babysit
  suite green. babysit-prs: `human_stop_from_feedback` extracted as the single definition of
  the human-stop record, with `classify_pr` delegating to it (1,800-case differential matrix
  confirmed field-, key-set-, and key-order-identical outputs, closing a real two-copy drift
  risk on the `external_required` presence branch); `babysit_resolve_thread` folds seven
  repeated summary-count comprehensions into one `acted()` counter; `request_review` folds
  eight `record_attempt_problem` call sites over the same five fixed arguments into a
  `record_problem` closure; `babysit_review_trigger` extracts the thrice-spelled gate-context
  predicate into `is_gate()` (400-fixture differential, De Morgan asymmetry preserved); a
  stale line-number anchor in a merge-test docstring replaced with a symbol anchor. scripts:
  `worktree-claim.sh` collapses the main-vs-linked flush branches; the readiness-gate suite
  resolves its Python probe once; `worktree-root-doctor.test.sh` gains `fgit()` wrapping the
  git-config-isolation prefix at ten fixture sites; the reap suite hoists `uname -s`;
  `reap-project-plugin-records.sh` uses `$'\t'` directly. Suite counts identical throughout
  (53/163/37/45); shellcheck and the portability gate clean.

## [0.55.23]

### Fixed

- **`landed-work.sh` emits `-` for a head-less row, honoring its own non-empty TSV contract.** Every
  field in the row `printf` carried a `:--` fallback except the head column, whose `:0:12` slice
  yields empty (not `-`) when `T_HEAD` is empty. notgit and bare-hub rows carry no HEAD by design, so
  those rows emitted an empty field, and a consumer reading the documented 15-column contract through
  `while IFS=$'\t' read` — the form this file's own callers are told to use — had every later column
  shift left: `risk` read the reason string and `reason` read empty. The slice now lands in a
  `head_col` variable and the fallback applies after it. Covered by cases that consume a notgit row
  and a bare-hub row through `while IFS=$'\t' read` with all 15 field names. (#3371)
- **`worktree-claim.test.sh`'s lock-failure case no longer reports a defect that does not exist under
  root.** The case forced the failure with `chmod a-w` on the worktree admin directory, which uid 0
  writes straight through, so the batch claim succeeded and the case failed in root containers with
  no code change behind it. The permission fixture is now probed before it is trusted and skipped
  with its reason named when it did not take, and a new root-proof arm — a stub `git` on PATH that
  fails only `worktree lock` — covers the lock-failure exit-code propagation on every platform and
  every uid, so the skip vacates no discriminating coverage. (#3378)

## [0.55.22]

### Changed

- **`babysit-prs`'s flag documentation has one home.** The Guarded mutations section keeps the
  operative invariants and per-tier mode selection plus one conditioned pointer; exact wrapper
  flag documentation deduped into `skills/babysit-prs/reference/safety.md`, which first gained the
  semantics it was missing (merge-form self-logins composition, the `--admin` capability bound,
  the merge-gate evaluation set, the per-thread action vocabulary). No semantics changed.
- **Long files carry a `## Contents` index.** The 401-line README and 337-line
  reference/review-discipline.md gained Contents sections; the heading-less 394-line
  skills/setup/reference/apply-convention.md gained an orientation block with a grep recipe.
  Progressive-disclosure audit, tier-mismatch and missing-toc treatments.

## [0.55.21]

### Changed

- **`worktree-root-convention` version-floors row hedges the git 2.56 `worktree:`/`worktree/i:` includeIf claim** as unreleased as of 2026-08-26 (latest upstream tag v2.55.0; the 2.55 docs do not list the condition), so a config is not authored against an unshipped floor. From the repo-wide derivability/point-dont-copy audit (PR #3387).

## [0.55.20]

### Changed

- **Long reference files carry a `## Contents` index.** 6 reference files in this plugin gained one.

  The predicate is `audit-progressive-disclosure`'s own: a reference file over 300 lines with no
  table of contents, which both official sources agree on by that length. Scope came from the
  detector's tier classification rather than a line count, so `SKILL.md` files are excluded by
  construction: they are invocation tier, not the on-demand reference tier the rule names. Files
  with fewer than five H2s were held out, because a three-row index on a long file earns nothing and
  the doctrine offers a grep recipe instead. Purely additive, with anchors generated from each
  file's own headings and verified to resolve. Docs-hygiene sweep, L2-progressive-disclosure.

## [0.55.19]

### Changed

- **`babysit-prs`' `## References` becomes a `Reference index. Load on demand` table**, ordered by
  when each spoke is needed, with `reference/runbook-cycle.md` and
  `reference/independent-resolution.md` added: both were reachable only from mid-body prose.
  `reference/stuck-checks.md`'s row states **both** entry conditions, a non-empty `checks.stuck`
  array **or** a conflicting branch with a short check list. The second limb is the one 0.54.13
  added, for the case where checks were never scheduled at all and `checks.stuck` is empty by
  construction; a row gating on the array alone would have silently reverted that fix while looking
  correct. Docs-hygiene sweep, L2-progressive-disclosure.

## [0.55.18]

### Fixed

- **Five unresolvable citations, one heading anchor, and one cross-plugin schema reach.**
  `reference/config-resolution.md` and `reference/review-discipline.md` cited
  `skills/babysit-loop/...` and `skills/babysit-prs/...` in a form whose implied base is the plugin
  root while the real base is `reference/`; all five now use the anchored
  `${CLAUDE_PLUGIN_ROOT}/skills/<skill>/<path>` form. `reference/worktree-root-convention.md` no
  longer pins the `worktree` skill's nesting invariant by heading anchor.
  `skills/babysit-loop/reference/promotion-evidence-resolution.md` no longer path-cites `autonomy`'s
  `guardrails-security-binding.schema.json`; it names `/autonomy:setup` and keeps the plugin-level
  `verification-topology.md` cite that already carries the obligation. Docs-hygiene sweep,
  L4-encapsulation.

### Changed

- **Three `babysit-prs` rules restated in the positive.** Two negation-only rules and one that
  narrated a superseded policy. The engine-absence rule now says what a safe iteration does
  (proceed, reporting merge-readiness as unchecked) rather than only what it must not do; the
  performance note now says to run the D5/D6/D7 verification sub-steps on every pass; and the draft
  policy no longer opens by naming the blanket draft skip it replaced, which no current reader has
  to compare against. Docs-hygiene sweep, L5-noise.

## [0.55.17]

### Changed

- **`worktree` and `setup` are no longer split, and this plugin's skills are now a documented
  poor split target.**

  `worktree`'s `context/nesting-invariant.md` extraction carried the upstream-drift verification
  stamp out of `SKILL.md`. `skills/worktree/nesting-invariant-ssot.test.sh` declares
  `OWNER_REL="skills/worktree/SKILL.md"` and asserts that body is the single owner of the measured
  claim. Its header states the reason: the defect being prevented was the same statement drifting
  across thirteen sites, and "one owner and twelve pointers" is the fix. Moving the claim into a
  spoke recreates the drift the test exists to stop.

  `setup`'s `reference/babysit-config.md` extraction carried the lane-script reachability canary
  out of `SKILL.md`, and `skills/babysit-prs/scripts/tests/test_guards.py` pins the exact canary
  invocation there in three assertions.

  Those are the third and fourth reverts in this plugin for one reason, after `babysit-prs` and
  `babysit-loop` below. The pattern is worth stating rather than rediscovering: `source-control`
  pins a large share of its skill-body prose by test, on purpose, because the pinned statements
  are safety gates, reachability contracts, and single-owner claims that an agent must have loaded
  rather than one link away. A line-count audit cannot see a pin.

  **Before splitting any skill in this plugin, grep the whole plugin, not just that skill's own
  directory, for a test that reads the target `SKILL.md`.** The `worktree` pin lives in a
  `*.test.sh` beside the skill; the `setup` pin lives under a different skill entirely
  (`babysit-prs/scripts/tests/`). Where a pin covers the content, the line count is the weaker
  consideration and the split does not happen.

- **`babysit-loop` gets its promotion-evidence gate back in the body.** The 0.55.11 cycle-shape
  split moved the merge-eligibility partition into `reference/cycle-shape.md`, and
  `skills/babysit-prs/scripts/tests/test_skill_contract.py` had been failing four assertions since:
  it requires the promotion-evidence gate, the `effective-promoted` state, the
  `promotion-evidence-resolution.md` citation, and the `--merge human-only` launch-line rule to be
  present in `skills/babysit-loop/SKILL.md`. Same reason the `babysit-prs` split was reverted at
  0.55.12: the condition decides whether anything merges at all, and a loop that never opens the
  spoke could resolve a cell as promoted on evidence the seam would refuse. The rest of the cycle
  shape stays in the spoke; only the gate moved back. Docs-hygiene sweep,
  L2-progressive-disclosure.

## [0.55.16]

### Changed

- **The generated options block sits under `## Configuration`.** It was under `## Security`, below
  the section that already documents configuration. The generated table itself is unchanged; only
  its placement moved. Docs-hygiene sweep, L8-write-for-humans.

## [0.55.15]

### Changed

- **Four skill bodies split against the progressive-disclosure audit.** `babysit-loop`,
  `pull-request`, `setup` and `worktree` each sat near the 500-line ceiling with on-demand material
  inlined, which a `SKILL.md` pays for across the rest of a session once it triggers. The
  sometimes-only content moved to a spoke and the body kept what every invocation needs:
  - `babysit-loop` to `reference/cycle-shape.md`
  - `pull-request` to `reference/full-lifecycle.md`
  - `setup` to `reference/babysit-config.md`
  - `worktree` to `context/nesting-invariant.md`

  `babysit-prs` was audited as a fifth candidate and deliberately **not** split. Its oversize
  content is the guarded-mutation gate catalog, and `scripts/tests/test_skill_contract.py` asserts
  three times that the merge-readiness paragraph lives in `SKILL.md` itself, citing #601: the body
  must name the merge gate's `ready` field as the sole authority for a merge-ready claim. Moving
  that behind a pointer would let an agent that never opens the spoke call a PR merge-ready on the
  finding-classification gate's signal, which is the exact failure #601 closed. Line count is the
  weaker consideration when the inlined content is the safety contract.

  Each pointer states when to read the spoke rather than only that it exists, so the split does
  not trade an oversize body for a blind pointer. No content was dropped; the spokes gained only
  a title and enough opening context to read on their own when opened directly.

## [0.55.14]

### Changed

- **Repo-wide behavior-preserving simplification sweep (batch-simplify).**
  Every change was adversarially verified by a fresh-context refutation
  pass; one proposed change was refuted and reverted.

  **Gate hooks:** pr-body-linkage-gate.sh's "three residuals" comment now
  counts its four residuals; worktree-add-claim-gate.sh drops three dead
  pre-initializations.

  **Babysit engine:** request_review.py's existing_trigger uses the shared
  babysit_gh.fetch_paginated_api instead of hand-building the same gh argv,
  and its local flatten_pages wrapper is gone (argv proven byte-identical).
  Docstring punctuation normalizes to the dominant "--" idiom in four
  modules; this also normalizes babysit_resolve_thread.py's --help
  description prose (nothing pins that text). Test suites hoist the
  _raw_run harness to module level, replace a 35-line inline duplicate of
  it, and drop nine suppressions proven dead against the pinned linter.

  **Scripts:** two test harnesses reuse the SCRIPT_DIR they already
  computed; reap-project-plugin-records.sh feeds its loops with
  herestrings instead of single-expansion heredocs;
  worktree-claim.sh's find_worktree_index drops a re-canonicalization of
  an argument every caller already canonicalizes (proven idempotent).

  **pull-request:** fetch-annotations.sh collapses the FILTERED
  accumulation to a single pass and drops a stale else comment; its
  test's stale Covers list is corrected. A proposed removal of
  nesting-invariant-ssot.test.sh's explicit FAILED=0/CASE_NUM=0 inits was
  refuted (the shared helpers deliberately preserve environment-inherited
  values) and reverted.

## [0.55.13]

### Changed

- **setup:** remaining instruction-surface punctuation after the prior
  plugin-wide rewrite. The overlay-ignore probe now ends the repository
  `.gitignore` clause with a period before `$GIT_DIR/info/exclude`.

## [0.55.12]

### Fixed

- **Three seams from the cross-plugin audit (#3128).**

  **S1 — vendored `hook-utils.sh` skip latch.** The shared notice latch now keys
  on session and agent (a subagent gets its own first notice), stores a skip
  count in the marker (independent of `HOOK_TELEMETRY_SINK`), and emits a
  one-line re-notice every 8 skips instead of going silent after the first.
  The first `PATH probed:` dump omits other plugins' bin dirs. SessionEnd is
  not wired: the count lives in the marker and the renew notice prints it.

  **S2 — overlay-ignore guard.** `/source-control:setup check` probes the
  `.claude/*.local.*` ignore rule whether or not the personal overlay exists.
  Missing rule is FAIL, not INFO. A match counts only when `-v` names a
  repository `.gitignore` (not `$GIT_DIR/info/exclude` or `core.excludesFile`).
  `apply` writes that line at team-layer bind time, not only at `layer=local`.

## [0.55.11]

### Fixed

- **PR-body linkage gates mask Markdown code the way CI does.** The shared
  validator treated a `## Fix` (or any other required heading) inside a fenced
  sample, a four-space indented block, or an inline span as the real section,
  so a body CI rejects — real Summary/Verification/Related plus only a templated
  Fix — still passed both local pre-checks. `mask_markdown_code` now blanks
  those constructs before the heading and keyword scan, using the same
  CommonMark fence-close rules the pinned `pr-issue-linkage` reusable applies
  ([#3206](https://github.com/melodic-software/claude-code-plugins/issues/3206)).
- **PR-body linkage gates now check all four contract sections.** The shared
  validator (`pr-linkage-validator.sh`) only required a closing keyword and a
  non-empty `## Related` section, so both local pre-checks — the MCP gate and
  the Bash `gh pr create`/`edit` sibling — allowed bodies the pinned
  `pr-issue-linkage` reusable rejects. Observed on #3205: a body with
  `No linked issue` plus Summary, Verification, and Related (no Fix) passed
  both local gates and failed CI with `Missing a "## Fix" section`. The
  validator now looks up `## Summary`, `## Fix`, `## Verification`, and
  `## Related` through one heading-level helper (a nested `###` is still
  content, not a terminator), reports every missing or empty section in one
  pass, and the blocked-message remedy lists all four so following it produces
  a body CI accepts. Both surfaces pick the change up from the shared core
  ([#3206](https://github.com/melodic-software/claude-code-plugins/issues/3206)).
  Inline-code masking collects backtick runs in one pass, then walks
  openers left to right the way CommonMark does: the first unused
  same-length closer wins, and every run between is content. That keeps
  a crafted unmatched-tick line under the 15s PreToolUse timeout, masks
  nested differing-length runs (`` `code` ``), and does not let the
  escaped-tick idiom steal a later pair on the same line.

## [0.55.10]

### Fixed

- **`reap-project-plugin-records.sh --help` no longer truncates its own header.**
  `usage()` extracts a hardcoded line range from the header, and the range had drifted
  behind it: the help stopped mid-sentence and dropped the last two lines of the exit-code
  table, the ones explaining that an unverified pass must never read as a clean one. The
  range now bounds the header exactly, and a test asserts the help reaches the final
  header line so the next header edit cannot silently truncate it again.
- **`cleanup.md` now lists the `--keep-data` reap rule.** The operator-facing rule list
  carries the same unconditional `--keep-data` contract the helper already enforces, which
  takes it from four rules to five.

## [0.55.8]

### Fixed

- **`worktree` cleanup reap no longer deletes other plugins' data directories
  (#3212, #3238).** `reap-project-plugin-records.sh` called
  `claude plugin uninstall <id> -s project` without `--keep-data`. The helper
  reaps stale *records* keyed to a worktree being torn down; it has no business
  deleting a plugin's `${CLAUDE_PLUGIN_DATA}` directory. Uninstalling from the
  last remaining scope does that by default, and the reap runs non-interactively
  over every plugin id holding a project-scope record for that path. The call
  now always passes `--keep-data`. `reap-project-plugin-records.test.sh` asserts
  the captured argv includes the flag. The measurement probe
  (`skills/worktree/fixtures/project-scope-reap-probe.sh`) passes the same flag
  on every uninstall, so a documented recheck can no longer destroy data as a
  last-scope side effect.

## [0.55.7]

### Fixed

- **`pull-request create`: every GraphQL-backed step on the create path now carries a REST
  substitute.** Sandboxed sessions (Claude Code on the web, remote execution) serve only a
  pinned set of GraphQL operations and refuse the rest with `HTTP 403`, which takes out the
  §2.2 default-branch read, the §2.4.0 issue-state check, `gh pr create` itself, and the
  `gh pr view --json` identity read after it. The §2.4.0 linkage check is the most dangerous of
  the four, because it fails with a *misleading diagnosis* rather than an error: its
  `2>/dev/null || true` swallows the 403, leaving `ISSUE_STATE` empty, so a live open issue is
  reported as "missing or not open" and the flow falls through to the orphan-PR prompt. Taking
  that prompt's `No related issue:` option then clears the §2.4.2.1 gate silently, and the PR
  ships with no linkage at all; declining it aborts the create instead. Either way the stated
  cause is wrong. §2.4.0 now gives the REST form and flags that REST reports `state` in lower
  case, so a comparison against `OPEN` never matches.
- **§2.4.3 states the REST PR-open form.** `gh pr create` sends a `RepositoryInfo` GraphQL
  preamble before it touches the pull-request API, so it 403s having created nothing. The
  section now documents `POST /repos/{owner}/{repo}/pulls` with the four differences that make
  the swap non-mechanical: REST requires `base` (which §2.2 must now resolve over REST itself,
  its `gh repo view --json defaultBranchRef` being the same GraphQL surface), `head` needs the
  namespaced `<fork-owner>:<branch>` form on a triangular flow, plus `head_repo` when both
  repositories share an organization, the body goes through `-f` rather than `-F`
  to avoid `--field`'s type conversion and `@`-filename handling, and the response carries
  `.number` and `.html_url` directly instead of requiring the URL to be parsed back apart. The
  paragraph that follows, which sends later phases to `gh pr view --json number,url` for PR
  identity, now says that read is GraphQL-backed too and gives its REST re-read, so the section
  no longer offers a sandboxed session two adjacent and contradictory instructions.
- **§2.2 carries its own substitute.** It is the first step on the normal `create` path to 403,
  so a sandboxed session died there long before reaching §2.4.3's fallback. It now shows
  `gh api "repos/{owner}/{repo}" --jq '.default_branch'` in place of `gh repo view --json`.
- **§2.7 anchors the substitute, and names the triangular trap.** `gh api`'s `{owner}`/`{repo}`
  placeholders expand from the current directory, which under the out-of-tree orchestrated entry
  is not the target repository — so the REST calls are shown in the same `( cd "$WT" && … )` form
  the section already uses for `resolve-remote.sh`, including a `$BASE` resolution of its own,
  since §2.7 skips the §2.2 step that would otherwise have set one. Anchoring to the worktree is
  not sufficient where the worker pushed to a fork: the placeholders then resolve to the fork, so
  the section also gives a `GH_REPO="<base-owner>/<repo>"` form with a namespaced `head`, which
  would otherwise have opened the pull request against the fork's own default branch silently.
- **The REST path's missing hook backstop is recorded.** `pr-body-linkage-gate.sh` matches
  `gh pr create` / `gh pr edit` and names `gh api …/pulls` among the invocations it deliberately
  does not see. Within the skill this costs nothing — §2.4.2's gates run against the body first
  — but §2.4.3 now says so plainly, because a REST PR opened outside the skill has no second
  check before CI.

## [0.55.6]

### Fixed

- **`setup` skill:** the babysit-config guidance now names `claude plugin uninstall`'s
  `--keep-data` flag. The section already warned against uninstalling to reconfigure,
  citing the lost `pluginConfigs` entry, but stopped there, and `--keep-data` appeared nowhere in
  the plugin. An operator who uninstalled for any of the other legitimate reasons (troubleshooting,
  changing scopes, reinstalling a version) had no warning that uninstalling from the **last
  remaining scope** deletes `${CLAUDE_PLUGIN_DATA}` by default. That directory holds
  `${CLAUDE_PLUGIN_DATA}/state/babysit-prs`, meaning the babysit-prs queue state, the worker
  leases, and the feedback ledger, none of which any `userConfig` key relocates. It is also the
  last resolution rung for both worktree roots, so a `/source-control:worktree` tree holding
  uncommitted work can sit there too. The added paragraph names the flag, states what the directory
  holds, and states which rung each root has to fall through to land in it, since "left unset" is
  necessary but not sufficient for `worktree_root`: a repository's `melodic.worktreeroot` git
  config outranks it. The existing advice against uninstalling to reconfigure is unchanged. The
  plugin README carries a parallel warning, but that copy sits inside the generated options block
  every plugin README shares, so changing it is a marketplace-wide edit to
  `scripts/sync-plugin-options-docs.py` rather than a source-control one. Follows the marketplace's
  own `docs/conventions/plugin-data-report-keying/README.md` Rule 4, which asks a component to
  state its uninstall fragility where its only durable copy lives
  ([#3131](https://github.com/melodic-software/claude-code-plugins/issues/3131)).

## [0.55.5]

### Added

- **Non-helper worktrees are now claimable, and unclaimed trees are
  reportable (#2882).** `worktree-create.sh` already locked the trees it
  created; a plain `git worktree add` did not, so concurrent sessions
  reached into each other's trees with no claim to read. `scripts/worktree-claim.sh`
  is the route that closes that hole:
  - `report` lists each linked worktree as `CLAIMED` (lock reason present)
    or `UNCLAIMED` (none). Demonstrated by creating one with plain
    `git worktree add` and reading the report.
  - `claim` / `claim --all-unclaimed` arms `git worktree lock` with a
    **session-distinct** reason (`worktree-claim.sh: ... session <id>
    since ...`). Two concurrent sessions on one host produce different
    reasons. Existing reasons are never rewritten, so helper-created
    trees keep the `worktree-create.sh: ...` string.
  - `check-enter <path>` is the write gate: a foreign live claim is
    printed and the command exits 4; an unclaimed tree is reported
    (exit 3); only a reason naming this session allows.
  - `hooks/worktree-add-claim-gate.sh` is the PostToolUse sibling of
    the containment gate: after a Bash `git worktree add` it claims
    **only the parsed add target** (not every unlocked tree), composing
    `git -C` and wrapper chdirs the same way the containment sibling
    does. `echo git worktree add` is not a git call. Dynamic paths and
    a prior `cd` fail open. A missed claim stays visible on `report`.
    `check-enter` canonicalizes relative / `.` / symlink paths so a
    foreign claim cannot be skipped by spelling. `--all-unclaimed`
    preserves a lock failure's exit status.
  The lock still only prevents `worktree remove` / `move` / `prune`
  (git-worktree(1)); its value here is as a claim other agents can
  read.

## [0.55.4]

### Changed

- **Instruction-surface de-slop (#2891, shard 4).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. The generated options block is ignore-fenced because
  `scripts/sync-plugin-options-docs.py` still emits em dashes from its shared template.
  Protocol strings in fences and inline code (commit message placeholders, the smart-default
  glance map, `no — report`) stay as written.

## [0.55.3]

### Changed

- **setup:** normalized restated setup-contract prose (preamble, probe-ladder
  opening, never-writes boundary, and/or headless-reconfigure recipe as present) to the
  canonical fleet wording, keeping the operable text inline with a provenance-only citation
  (whole-repo extract-ssot batch, #2698).

## [0.55.2]

### Fixed

- **`worktree` skill:** the orphaned-directory normalization in `cleanup` Step 4b now shows the
  rule as executable code instead of half of it as a comment. The snippet was
  `path="${path%/}"` plus a comment saying to run it "again for a Windows-style trailing
  backslash" — but Step 4b is prose an agent executes literally, so the backslash half never ran,
  and one `%/` pass also strips only a single separator. A trailing `\` (the common
  Explorer/`dir`-pasted form on the platform the original measurement came from) or a doubled
  separator therefore still defeated the `test -L` symlink disqualifier this normalization
  exists to protect. The snippet is now a platform-gated loop: on Windows shells
  (MINGW/MSYS/CYGWIN, where `\` is a separator) it strips both separator styles until none
  remain; off Windows it strips forward slashes only, because there a trailing `\` is a legal
  filename byte — the same gated rule `worktree-create.sh` applies to its root normalization —
  and stripping it would re-point the qualifying tests, the reap, and the `rm -rf` at a
  different sibling path. `audit`'s "check it the way `cleanup` does" pointer carries the same
  snippet instead of prose only, and `reap-project-plugin-records.test.sh` pins the expression
  per platform — doubled slashes always strip, a trailing backslash strips on Windows shells
  and survives on POSIX — as a pure string case that runs even where the symlink fixture must
  skip ([#3163](https://github.com/melodic-software/claude-code-plugins/issues/3163); the
  unshipped remainder of the final security-review finding on
  [#3116](https://github.com/melodic-software/claude-code-plugins/pull/3116), with the POSIX
  filename-byte gate from Codex review on
  [#3165](https://github.com/melodic-software/claude-code-plugins/pull/3165)).

## [0.55.1]

### Fixed

- **`setup` skill:** the headless reconfiguration route no longer prescribes `claude plugin
  uninstall` + reinstall. That instruction rested on an unversioned claim that `claude plugin
  install --config` is ignored once a plugin is installed, and following it dropped the plugin's
  whole stored `pluginConfigs` entry, resetting every declared option to its manifest default.
  On Claude Code 2.1.240 a plain `claude plugin install … --config` against an already-installed
  plugin prints `already installed` and still writes the value, so that is now the documented
  route — stamped with the CLI version it was verified against
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). `apply` also
  now separates the write from its effect: the stored value changes immediately, but the running
  session's hooks keep the `CLAUDE_PLUGIN_OPTION_*` they were handed at session start, so
  verification means rerunning `check` in a FRESH session — a same-session rerun reports the old
  value, which is not a failed write. It never asserts an unobserved change.
- **Docs:** the generated options block's headless route no longer implies `--config` applies
  only at install time, and now carries the CLI version its claim was verified against
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). The block also
  now separates the write from its effect: the value is stored immediately, but hooks are handed
  their `CLAUDE_PLUGIN_OPTION_*` at session start, so a check run in the same session still
  reports the old value and that is not a failed write. Two upstream links that pointed at empty
  backward-compatibility anchors on the settings page were repointed at the headings that hold
  the content.

## [0.55.0]

### Fixed

- **A failed post-reap enumeration no longer reads as a clean reap (#3113 review).**
  `reap-project-plugin-records.sh` verifies its own pass by re-enumerating after
  the uninstall calls. That second `claude plugin list --json` failure was being
  absorbed into an empty survivor list, so the script printed
  `ok: every … is gone` and exited 0 having confirmed nothing — while the
  identical *pre*-reap failure already degraded with `warn:` and exit 3. The
  asymmetry was the defect: both mean "unknown outcome". A post-reap enumeration
  failure now reports `surviving UNKNOWN`, says the pass is UNVERIFIED, names how
  many calls reported success, and exits 3. It is the one outcome a caller acts on
  by deleting the directory, so certainty it does not have was the most dangerous
  thing the script could report.
- **A trailing separator no longer defeats the symlink disqualifier.** `cleanup`'s
  orphaned-directory qualification now normalizes the path before all four tests.
  POSIX resolves a trailing-slash path *through* a symlink, so `test -L "link/"`
  answers about the target: measured on this plugin's host, `test -L link` → true,
  `test -L "link/"` → **false**, and `find link -mindepth 1` → **empty** because
  `find` does not descend a symlinked start point either. One trailing character
  made a live directory look like an empty non-symlink and sail into `rm -rf`.
  `audit`'s mirrored guidance carries the same rule, and
  `reap-project-plugin-records.test.sh` now pins all three measurements.

### Added

- **`worktree cleanup` reaps the project-scope plugin install records a torn-down
  worktree leaves behind (#3113).** Claude Code keys a project-scope install to a
  literal `projectPath` in `~/.claude/plugins/installed_plugins.json` and nothing
  reaps it when that path goes away, so every worktree this plugin created and
  destroyed left one record per installed plugin behind permanently — measured on
  the author's machine: 108 records across 8 marketplaces, all naming a single
  worktree directory that no longer exists, and every project-scope record on that
  machine an orphan. `cleanup` Step 4b now runs
  `scripts/reap-project-plugin-records.sh` from inside the candidate, after the
  stranded-work and carried-file guards clear and before the directory is removed.
  The trigger is the teardown, never path non-resolution: a record for a live
  repository on an unmounted share is indistinguishable from a dead worktree to an
  existence check.
- **`scripts/reap-project-plugin-records.sh`.** Enumerates through
  `claude plugin list --json` and removes through
  `claude plugin uninstall <id> -s project`; it never edits
  `installed_plugins.json`, never runs `-s user` (the CLI's own failure text
  suggests it, and following that would uninstall the plugin fleet-wide), and never
  passes `--prune`. It refuses unless `--worktree-path` names the directory it is
  already standing in, which is the cwd boundary rendered in code rather than in
  prose. `--dry-run` supported; degrades visibly (exit 3) when the CLI or `jq` is
  absent.
- **`worktree audit` Step 2b reports pre-existing orphaned records.** Records left by
  worktrees removed before the reap existed are unreachable by it, so audit makes
  them visible, in four buckets: *live here*, *live elsewhere*, *candidate orphan*,
  and *other project records* (information only, no remedy). The *live elsewhere*
  bucket is load-bearing: the worktree root is shared across repositories
  (`<root>/<owner>-<repo>-<slug>`), so "not in this repository's `git worktree
  list`" is true of every other repository's live worktree under it — a liveness
  test (`git -C <path> rev-parse --is-inside-work-tree`) is required alongside the
  registration test before anything is called an orphan. `cleanup`'s
  orphaned-directory candidate — the only candidate class with no stranded-work
  row to read, since the engine enumerates from `git worktree list` — is held to
  a stricter bar still: *not a symlink*, *not a work tree*, *no `.git` entry*,
  and *empty* — all four. The `.git` test is the load-bearing one and the
  work-tree test does not imply it,
  because a live worktree whose main clone was moved, deleted, or unmounted keeps
  its `.git` file while `rev-parse` fails. Both surfaces also stop scanning a
  configured root that does not resolve. Read-only: removal needs the
  directory recreated first, which the audit emits for the user (plain `mkdir`, so
  it fails rather than no-ops on a live directory; every step `&&`-chained so a
  failed reap leaves the directory in place) and never performs.
- **`skills/worktree/fixtures/project-scope-reap-probe.sh`** plus its
  `fixtures/README.md` record. Six arms establish that `-s project` has no path flag
  and resolves strictly against the resolved absolute cwd, that `plugin list --json`
  enumeration is cwd-independent, and that a record outlives its directory but is
  reachable from an empty directory recreated at the same path. Claude Code
  **2.1.240**, re-run unchanged on **2.1.241**, Windows.

## [0.54.16]

### Changed

- **Fixture-building tests clear inherited git environment (#2872).** Suites
  that build a git fixture now unset `GIT_DIR`, `GIT_WORK_TREE`, and
  `GIT_CONFIG` so an inherited environment cannot write the fixture identity
  into the caller's repository. Test-only; no plugin behavior change.

## [0.54.15]

### Fixed

- **Fixture isolation now clears `GIT_CONFIG` (#2889).** The plugin test
  helper already unset the discovery variables at source time; it now also
  unsets `GIT_CONFIG`. Test-only; no skill behavior change.

## [0.54.14]

### Changed

- **Three cross-skill chains name the Skill tool (#3002).** `babysit-loop`'s per-cycle invocation
  of `/source-control:babysit-prs`, `pull-request`'s commit-step delegation to
  `/source-control:commit` in `reference/create.md`, and its post-merge retrospective step in
  `reference/merge.md`, which said "invoke it" of a `/session-flow:retro`-shaped capability
  without naming the mechanism. The `/source-control:setup` references stay
  prose: `setup` is `disable-model-invocation: true`, so the rubric's invocation-reach invariant
  keeps it human-only. Wording only; tier semantics, gates, and the inline-commit fallback are
  unchanged.

## [0.54.13]

### Added

- **`babysit-prs` `stuck-checks.md` now covers checks that never SCHEDULE, not
  only checks that never settle.** A conflicted PR has no computable merge ref,
  so `pull_request` workflows are never created — absent rather than pending or
  failing, and therefore invisible to `checks.stuck`. Because
  `pull_request_target` lanes run against the base and still pass, the PR
  presents a short all-green list with no failures while most gates are simply
  missing. The section says to read `mergeStateStatus` before reasoning about a
  short check list, and names the misdiagnosis (trigger or App-token problem)
  that this repository has already spent time on once. Documentation only.
- **The load condition for `stuck-checks.md` now admits the conflicting case.**
  `runbook-cycle.md` gated the file on a non-empty `checks.stuck`, which is
  empty by construction in the scenario above, so the new guidance would never
  have been read when it applies. The gate now also fires on
  `branch_freshness.state == "conflicting"`, and `SKILL.md`'s one-line
  description covers both directions rather than the UNSTABLE signal alone.

## [0.54.12]

### Changed

- Sync `hook-utils.sh` from `lib/` (comment-only; no behavior change).
- `babysit_delta.py` drops a duplicated navigational comment and a
  history-narration docstring clause (comment-only; suite green).

## [0.54.11]

### Fixed

- **`babysit-prs` worktree-pruner tests no longer let their fixture identity
  land in the caller's repository
  ([#2840](https://github.com/melodic-software/claude-code-plugins/issues/2840)).**
  `test_prune_babysit_worktrees.py` clears `GIT_DIR`, `GIT_WORK_TREE`,
  `GIT_INDEX_FILE`, `GIT_COMMON_DIR`, `GIT_PREFIX`, `GIT_OBJECT_DIRECTORY` and
  `GIT_CONFIG` from `os.environ` at import. An exported **absolute** `GIT_DIR` overrides
  repository discovery, so `git config`'s default `--local` scope resolves to
  the caller's gitdir and the fixture identity is written there instead. This
  suite is doubly exposed because it also builds a **linked worktree**, whose
  config writes land in the main clone's **shared** `.git/config`. `GIT_CONFIG`
  is cleared as a **second** leak path rather than another spelling of the
  first: it replaces the file the `git config` subcommand reads and writes, so
  an identity write follows it past `-C`, past a cleared `GIT_DIR`, and past the
  working directory. Test-only change; no shipped skill or script behavior is
  affected.

## [0.54.10]

### Changed

- Behavior-preserving simplifications from the repository-wide batch-simplify pass:
  duplicated helpers folded, dead code and redundant constructs removed, no functional
  change. Every group was verified by a fresh-context verifier agent against the
  plugin's own test suite.

## [0.54.9]

### Fixed

- **Stale-base guidance no longer claims coverage it does not have, or recommends a
  forbidden setting (#2691).** The babysit/pull-request stale-base rule cited the
  2026-08-15 incidents (quoted as "#2635 then #2639 ... inside ten minutes") as its
  motivating case. All three of those merges (#2633, #2639, #2641) were stale in
  **content** while up to date in **history** — `git merge-base --is-ancestor f603880d
  refs/pull/2641/head` is true — so `check-stale-base-overlap.sh` exits 0 on them; they
  belong to the post-merge `scripts/check-silent-revert.sh` class.
  `freshness.md` and `merge.md` now state the gate's real scope (stale **base** only) and
  point at the sibling detector for the disjoint class. Both files also dropped the
  "durable fix is `requiredStatusChecks.strict`" recommendation: it is barred by an
  accepted ADR in the org's IaC repo, and the same evidence shows strict would have passed
  all three incidents anyway. No behavior change — wording only.

## [0.54.8]

### Fixed

- **Worktree create refuses a cross-drive unconfigured default on Windows (#2806).**
  `scripts/worktree-create.sh` same-drive guard now fails closed at rung 4 (plugin
  data-dir default) with the same remedy-first exit 3 as rungs 1–3, instead of
  warn-and-proceed. An unconfigured cross-drive machine no longer creates a
  worktree that `git worktree move` will fail on with EXDEV / Improper link; the
  refusal is visible on the `WorktreeCreate` hook path (non-zero stderr), where
  the previous exit-0 warning was dropped to the debug log. Skill create contract
  (`skills/worktree/SKILL.md`, `context/create.md`, evals) documents cross-drive
  as an exit-3 case alongside missing/nested roots.

## [0.54.7]

### Added

- **Stale-base squash-merge hygiene (#2691).** Document the babysit/pull-request rule: never
  squash-merge while the head is behind its base (even when `mergeStateStatus` is CLEAN under
  a non-strict ruleset). Point at `scripts/check-stale-base-overlap.sh` as the overlapping-path
  tripwire. (The coverage and prevention framing shipped with this entry was corrected in
  0.54.9.)

## [0.54.6]

### Changed

- **Nesting-invariant probe run recorded as inconclusive (#2768).**
  `fixtures/nesting-invariant-probe.sh` was executed on Claude Code **2.1.232** with every
  discriminator pinned (creation=`git worktree add`, launch=`cd`+`claude -p --settings`,
  glob=`src/**`, parent rule committed, four placements). All four arms hit the script's
  fixture-failure trap — zero `InstructionsLoaded` events because the CLI was
  unauthenticated — which is **not** a null finding about the leak. README and SKILL.md
  stamp refreshed; arm statuses remain disputed/untested. Probe now prints pinned
  discriminators and surfaces `claude` stderr on a zero-event arm.

## [0.54.5]

### Fixed

- **Nesting-invariant SSOT test enforces the unconditional expiry date arm (#2767).**
  `nesting-invariant-ssot.test.sh` previously only asserted the literal strings
  `as-of **2026-08-07**` and `Unconditional expiry` — so the stamp could pass its
  expiry and the suite stayed green forever. It now parses the as-of date and both
  expiry arms, fails when today is on or after the date arm, asserts the version
  arm is present and `N.N.N`-shaped (not evaluated — CI has no live Claude Code
  version), and proves the red path with an injected post-expiry "today".

## [0.54.4]

### Changed

- **Docs:** `/worktree audit` no longer enumerates a subset of non-`safe` Work values
  (#2766). SKILL.md Step 1 flags any Work value other than `safe` (owned by
  `context/status.md`), so the list cannot drift when the axis gains a value.
  `context/audit.md` health presentation adds `in-progress` and `dirty` — the two
  classes `cleanup` refuses — alongside stranded/unproven. Docs-only.

## [0.54.3]

### Changed

- **Docs:** `/worktree create` and `/worktree cleanup` now document `git worktree repair`
  (#2765). `context/create.md` adds a cross-drive / move-unavailable caveat with the
  unlock → copy → `repair` → re-lock sequence (helper-created worktrees are locked).
  `context/cleanup.md` Step 5 names `repair` alongside `prune` and states the
  distinction. Docs-only; no behavior change.

## [0.54.2]

### Fixed

- **Worktree create enforces the same-drive-on-Windows invariant (#2764).**
  `scripts/worktree-create.sh` now compares the repository and resolved worktree
  path drive letters (path-shape gate: both sides must match `<letter>:/`, so
  POSIX and UNC stay inert). An explicit or configured root on a different drive
  (rungs 1–3: `--root` / `melodic.worktreeroot` / `--fallback-root`) is refused
  with exit 3 and a remedy-first message. The unconfigured plugin-data-dir
  default (rung 4) warns loudly and still creates — refusing would fail every
  harness-driven `WorktreeCreate` on a cross-drive machine. Closes the gap where
  the invariant was stated in `plugin.json` and the containment message but never
  enforced; `git worktree move` cannot cross volumes (`rename()` / EXDEV).

## [0.54.1]

### Changed

- **setup:** Two articles dropped from the local-overlay fixture's prose comment
  (`.claude/source-control.local.md`) by the repo-wide `/docs-hygiene:compress` pass —
  semantic-diff verified (0 semantic loss). No behavior change.

## [0.54.0]

### Added

- **`worktree-add-containment-gate` PreToolUse Bash hook (#2611).** Blocks a raw
  `git worktree add` whose statically-resolved target lands inside a git working tree
  or a `.git` / bare directory, naming the configured external root
  (`melodic.worktreeroot`, then `worktree_root`, then the plugin data dir). Conforming
  targets pass silently; unresolved targets pass. Kill switch:
  `worktree_add_containment_gate_enabled`.
- **`scripts/worktree-root-doctor.sh` (#2612).** Conformance check for the
  `melodic.worktreeroot` convention against the live repository: makes the silent
  `includeIf` failure classes loud (unfired or unrecognized conditions, missing
  include files, parse-order shadowing, scoped-read divergence, identity partials,
  a root inside a repository) and names which rule supplied the root.
  `/worktree audit` runs it as part of its configuration-health step. Convention
  owner doc: `reference/worktree-root-convention.md`.

### Changed

- **Worktree root resolution prefers `melodic.worktreeroot` over the plugin option (#2610/#2612).**
  `scripts/worktree-create.sh` and `hooks/worktree-create-gate.sh` resolve most-specific-first:
  explicit `--root`, then the git config key (includes on), then `--fallback-root` (plugin option),
  then the plugin data directory. Documented in `reference/worktree-root-convention.md`. The
  `/worktree create` skill passes `${user_config.worktree_root}` via `--fallback-root-file` (not
  `--root-file`) so the primary creation flow honors the same precedence.

## [0.53.25]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.53.24]

### Added

- **`babysit-loop`: promotion-evidence gate on the rung partition (#1695).** Before C2/C3 PRs enter
  the merge-eligible set, the partition resolves each promotable cell's effective state through a
  trusted promotion-evidence seam — never from repo-local or agent-writable surfaces, never from
  bound `promotion_state` alone. Unavailable, untrusted, partial, or forgeable evidence fail-closes
  to effective-unpromoted; a contrary demotion event in qualified telemetry excludes the affected
  class on the next cycle without config change. Until the seam qualifies, C2/C3 classes stay off
  the eligible set regardless of tracked rung; operators keep `--merge human-only` on launch lines.
  New reference `skills/babysit-loop/reference/promotion-evidence-resolution.md`; `config-resolution.md`
  notes the gate. Evals 2, 6–8 updated; eval 10. Contract test in `test_skill_contract.py`.

## [0.53.23]

### Added

- **`babysit-loop` drain mode applies the issue-author provenance field test (#1718).** In
  `--drain`, every non-excluded open issue in the cycle-start snapshot is tested with the
  `C5` issue-author trust test from `work-classes.md` — same `authorAssociation` and
  `babysit_loop_trusted_internal_bot_logins` binding as the PR trust test, fail-closed when a
  field is absent. An issue that fails counts as human-gated for the drain-terminal exit even
  without a human-gated role label; the lane never works such intake. `config-resolution.md`
  notes the key is consumed by both the rung partition and this drain test. Eval 9.

## [0.53.22]

### Fixed

- **hook-utils:** distinguish unresolved `physical_path`/`repo_root` answers and honor unquoted `#` in `bash_parse_segments` (#1487).

## [0.53.21]

### Fixed

- **babysit-prs bulk `--include-human` refuses human-deferred threads (#671).**
  Bulk resolution skips threads whose most recent human reply parks the finding
  (`defer`/`deferred`, `VALID (defer)`, `pending ruling`, `held pending`,
  `needs-human`). Truncated comment pages fail closed; pinned `--thread-id` may
  still proceed.

## [0.53.20]

### Documentation

- **babysit-prs:** document dispatched-worker capability tiers — `strong` for routine
  per-PR fix workers, `frontier` for conflict-resolution and independent-resolution
  dispatches (#1664).

## [0.53.19]

### Fixed

- **hook-utils:** scope `read_file_path` to git worktrees when project dir unset (#1091).

## [0.53.18]

### Fixed

- **`worktree-create` copies `.claude/settings.local.json` from the main checkout root, not
  `.git/.claude/` (#2119).** `git rev-parse --git-common-dir` points at metadata, so the carry-in
  step now resolves the sibling working-tree path and copies untracked local settings into new
  worktrees.

## [0.53.17]

### Fixed

- **Branch refresh and review triggers no longer halt on self-authored human stops (#902).**
  `human_stop.external_required` excludes configured self-logins from automation gates while
  `human_stop.required` still blocks merge when the maintainer posts under their own login.

## [0.53.16]

### Changed

- **Synced `hook-utils.sh`:** write `emit_telemetry`'s `data` payload to a temp file instead of passing it via `--argjson`, so payloads above the Windows command-line cap are not dropped (#1595).

## [0.53.15]

### Changed

- **Synced `hook-utils.sh`:** peel sudo clustered short options for chdir resolution (#1811); widen the valueless-short peel set and keep `-h` value-taking.

## [0.53.14]

### Changed

- **Stale-branch recovery defaults to merge-forward, not rebase + force-push (#1436).** `monitor.md`'s
  conflict and stale-branch paths prescribed "force-push with lease", which auto-mode permission
  classifiers commonly deny — the observed cost was a fresh branch + fresh PR per rebase, with every
  review thread re-opened. Merging the default branch *into* the PR branch pushes fast-forward with
  no force-push, and under a squash-only default branch the merge commits collapse on merge, so
  linear-history requirements stay satisfied. Rebase remains the exception for projects that require
  a linear PR branch and where force-push is actually available.

### Added

- **`statusCheckRollup` running-check pitfall documented (#1436).** An unfinished check reports
  `conclusion: ""` (empty string), not `null`, so complement-shaped failure filters
  (`conclusion != null and != "SUCCESS"`) count still-running checks as failures. `monitor.md`'s
  multi-PR scan now carries the correct value-positive jq selectors for "failed" and "still
  running".

## [0.53.11]

### Fixed

- **Finding-extractor reads anchor to the PR worktree cwd (#2454).** Review-discipline
  dispatch text now substitutes `<absolute-worktree-path>` and quotes it in `git -C`
  examples so paths with spaces stay valid.

## [0.53.9]

### Added

- **Guarded resolve-thread wrapper now appends an audit record (#2139).** Every successful
  `source-control-babysit-resolve-thread --resolve` mutation writes one JSONL line (pins, mode,
  disposition, thread metadata) to `resolve-thread-audit.jsonl` under plugin data or
  `~/.claude/source-control/`. Override with `SOURCE_CONTROL_RESOLVE_THREAD_AUDIT_LOG`. Webhook
  capture and permission-layer bypass closure remain open on #2139.

## [0.53.8]

### Changed

- **The co-author trailer key is now spelled `Co-authored-by` (#1604).** GitHub's documentation uses
  that spelling exclusively, and GitHub itself writes it when appending co-author trailers to a
  squash-merge message, so the skill's branch commits and the forge-written merges now agree.
  Attribution was verified to succeed for the previous `Co-Authored-By` spelling too (GraphQL
  `Commit.authors` resolves the co-author either way), so this is a consistency change: existing
  history is never rewritten, and the `trailer_policy` template remains the escape hatch for
  consumers who want a different spelling.

## [0.53.7]

### Fixed

- **Abbreviation gate now asserts every catalogued Python entry point exposes `--help`.**
  Without that premise, a parser built with `add_help=False` would pass the universal
  abbreviation probe vacuously.

## [0.53.6]

### Fixed

- **`fetch_pull_request_commits` fails closed when GitHub's 250-commit API cap truncates the walk
  (#2387).** Compares the walked count to the PR's `commits` field and raises when the endpoint
  cannot return the full list, preserving the over-report-only invariant for signature enforcement.

## [0.53.5]

### Fixed

- **`worktree-create.sh` signals lock failure with exit 5 and `lock_failed=1` on stderr (#2389).** The
  worktree path is still printed so orchestrators can detect an unarmed liveness guard without
  treating a silent success as a locked worktree.

## [0.53.4]

### Changed

- **Synced `hook-utils.sh`:** refuse sub-minimum `stdin_read_timeout` values (#1883).

## [0.53.3]

### Changed

- **Synced `hook-utils.sh`:** `hook::jq_fields` returns 2 when jq is present but cannot parse the payload (#2157).

## [0.53.2]

### Fixed

- **Canonical `gh pr create` now passes `--head` explicitly (#1900).** The §2.4.3 worktree path already
  did; the on-branch canonical path did not. Once dotfiles#375's amended auto-mode grant lands, `gh pr
  create` is covered only when the head branch is named — so the canonical lane must match the
  sibling spelling. Detached HEAD is refused rather than emitting `--head ""`.
- **`babysit_resolve_thread` severity guard reads structured P0/P1 markers only (#1939).** The
  `--autonomous` and `--independent-resolver` paths refused any thread whose body contained a
  word-bounded `P1` token, so a P2 thread discussing P1 properties in prose became
  `skipped-severity-marked`. The scan now keys on shields badges, bracketed `[P0]`/`[P1]`, and
  explicit `P1:`/`P0:` declaration prefixes — not incidental prose mentions. Vetted
  `--resolve --thread-id` still applies no severity screen — documented as intentional.

## [0.53.1]

### Fixed

- **The paused-merge case pins both halves of the in-progress reason, and the landed+in-progress
  fixture's comment corrects the cherry-pick rationale (#2257).** 0.51.16 rewrote the in-progress
  reason to "…(staged result recomputable from base, sequencer position) dies with the directory",
  but the suite asserted only "recomputable" — the clause carried over from the old wording — so
  the #2257 half (the transient state is LOST with the directory, close to the opposite claim)
  could regress silently; a second assertion now pins it. The fixture comment also claimed a
  cherry-pick "would reuse the same object", which is wrong on two counts: cherry-pick mints a new
  commit, and with this fixture's ordering (`unrelated on main` lands before the twin) a
  cherry-pick would not have parent == HEAD at the branch tip and would carry `unrelated.txt` in the
  tree — different parent, tree, and SHA even within the same second. The twin-with-different-subject
  sequence below is deliberate; do not replace it with a cherry-pick.

## [0.53.0]

### Changed

- **The nesting-invariant claim has one owner and twelve pointers, instead of 13 undated copies**
  (`skills/worktree/SKILL.md`, `skills/worktree/context/create.md`, `scripts/worktree-create.sh`,
  `hooks/worktree-create-gate.sh`, `.claude-plugin/plugin.json`, `README.md`; #2213). The mechanism
  claim justifying a machine-wide placement rule enforced by a fail-closed hook was restated as an
  **undated absolute at 13 sites** against exactly two dated statements — and the one site asserting
  freshness ("It is the live constraint, not a historical one") was itself undated, so a pointer
  landed the reader precisely there. `SKILL.md` now carries the claim under an explicit
  `### The nesting invariant, verified` heading and everything else points at it. Not thirteen
  updated copies: one owner, and a test (`skills/worktree/nesting-invariant-ssot.test.sh`) that
  fails when a second site states the mechanism, so the next person to explain it in place has to
  point instead.
  - **Deviation from the filed fix direction, stated so it is not read as an oversight.** The issue
    asks pointers to restate the as-of at each pointer site. They do not: twelve restated dates are
    twelve drift sites, which is the defect being removed. Pointers instead say the claim is dated
    and measured, and name the section that carries the stamp.
  - **The two exit-3 heredocs keep a short restatement** alongside their pointer. They are read at
    the moment creation fails, when the reader cannot go follow a link; a pointer-only refusal there
    would be a regression. Both restatements are deliberately non-causal ("can pick up") rather than
    the absolute the rest of the sweep removed.
- **The nesting invariant now carries an unconditional expiry, because both of its event triggers
  were structurally unable to fire** (`skills/worktree/SKILL.md`; #2213). The triggers were "a
  release note naming worktree rule-file loading" and "upstream #16600 changing state". #16600 has
  not changed state since well before the 2026-08-07 as-of date, and an opaque release stanza
  ("Bug fixes and reliability improvements", 2.1.226) cannot fire an event-keyed trigger at all — so
  the most consequential claim in this plugin was guarded by two triggers that could not go off. The
  stamp now adds **2.1.244 or 2026-11-07, whichever comes first**, composed with
  `docs/conventions/upstream-drift/` rather than inventing a parallel mechanism.
- **The `SKILL.md` ownership claim is no longer a false absolute, and it gained a back-channel**
  (`skills/worktree/SKILL.md`; #2213). "This skill is the canonical owner … — no external prose doc"
  was untrue: a consumer doc outside this repository defers mechanism to this skill *and* is more
  current than it. Ownership is now scoped to this plugin fleet, and states how a consumer who
  measures something contradicting the owner gets that correction back into the owner. Canonical
  ownership with no inbound channel makes the owner the last to know.

### Fixed

- **The nesting-invariant measurement is downgraded to the modality it actually has, and its fixture
  is now recorded** (`skills/worktree/SKILL.md`, `skills/worktree/fixtures/`; #2212). The 2.1.224
  leak measurement was **disputed, not refuted** — a 2.1.227 counter-reproduction did not observe
  it — and *neither run recorded its fixture*, so the two results could not be compared and the
  claim was not adjudicable. It read as settled anyway. The section now names the dispute, carries
  an arm-by-arm status table so a fix to one arm cannot silently weaken another (the
  **nested-in-an-unrelated-repo** arm is untested by anyone and **not** refuted — the dispute does
  not reach it), and ships `fixtures/nesting-invariant-probe.sh`, which pins every discriminator
  neither original run disclosed: creation mechanism, launch mode, the exact `paths:` glob and its
  anchoring root, whether the parent's rule file was committed, and the three placements as separate
  arms. **The probe is written and has NOT been run** — that is stated at the top of the script and
  in `fixtures/README.md`, and nothing is claimed on its authority. It converts a recheck *trigger*
  into a recheck *procedure*.
- **The reproduction guidance no longer contradicts the hooks docs** (`skills/worktree/SKILL.md`;
  #2212). It claimed the single-string command shape "silently never fires". That is not what
  <https://code.claude.com/docs/en/hooks> says (raw markdown, fetched 2026-08-11): both command
  forms are documented with no event-specific carve-out, and the documented rule is narrower — "Set
  `args` whenever the hook references a path placeholder, since each element is passed as one
  argument with no quoting." This plugin's own `hooks/hooks.json` registers all three of its hooks
  in the single-string form and they fire. The guidance now states the documented rule, and the
  genuinely unknown part is named as unknown: whether the single-string form fires for an
  `InstructionsLoaded` hook supplied via `claude -p --settings <file>` is **unprobed by anyone**.
- **The 2.1.224 version basis no longer reads as a release fact** (`skills/worktree/SKILL.md`;
  #2212). "which 2.1.224 already handles correctly" sat several sentences from the only "Basis:"
  clause and had already been misread as a version fact by two independent readers. The basis is now
  inlined at the claim: it is a **null result from the same trace**, not a release note, and the
  changelog scan behind it is packet-sourced and has not been re-run. Supersedes the in-place
  correction shipped in 0.52.1 (#2332), which fixed the same two rows (`D-F1`, `D-F6`) inside the
  old single-paragraph shape; both of its corrections are preserved here, restated inside the
  restructured owner section, and `D-F2` — the missing fixture that #2332 left open — is what
  this release adds.

## [0.52.1]

### Fixed

- **Worktree nesting-invariant prose corrected against measured 2.1.224 behavior**
  (`skills/worktree/SKILL.md`; #2268). The control-arms paragraph misstated the hook
  `args`-array reproduction shape, overstated #16600 as covering path-scoped rules when
  memory traversal did not leak in the same fixture, and dated the hooks doc fetch
  incorrectly. Each claim now matches the InstructionsLoaded trace basis recorded in
  the skill.

## [0.52.0]

### Changed

- **`worktree_create_gate_enabled=false` now refuses out loud instead of exiting 0 silently**
  (`hooks/worktree-create-gate.sh`, `.claude-plugin/plugin.json`, `README.md`; #2211). The option's
  documented meaning — "let Claude Code use its own default", implemented as exit 0 with an empty
  stdout — was **false**, and the suite asserted it. Measured on Claude Code **2.1.228**: a
  `WorktreeCreate` hook that exits 0 without printing a path fails the creation with
  `hook succeeded but returned no worktree path`, and nothing is created. So the old exit-0 path
  produced the *same* outcome as a refusal while suppressing every explanation, because an exit-0
  hook's stderr is dropped — the probe's stderr marker was absent from the harness output on exit 0
  and present, in full, on exit 3. The option only became reachable at 0.51.7 (#2193 declared it in
  `userConfig`), so this is the first release in which anyone could hit it. Disabled now exits
  non-zero with a message naming the real stand-downs: `worktree.bgIsolation: "none"`, or disabling
  the plugin. The docs agree at the current revision and are quoted in the fixture: "Hook failure or
  missing path fails creation."
- **The `WorktreeCreate` contract is now a recorded, runnable fixture** (`skills/worktree/fixtures/`;
  #2211). `worktree-create-hook-probe.sh` runs the four arms — control, exit-0-no-path,
  exit-3-with-stderr, path-without-directory — and `README.md` carries the outcome, the verbatim
  harness strings, corroborating doc quotes, an as-of stamp (2026-08-11, 2.1.228) and a recheck
  trigger, per the upstream-drift convention. A recheck is one command instead of a re-derivation
  from memory.

### Fixed

- **The worktree-create gate's failure output reported a constant exit status, discarded the
  helper's exit taxonomy, and named no remedy** (`hooks/worktree-create-gate.sh`,
  `scripts/worktree-create.sh`; #2209). `status=$?` sat inside the body of `if ! path="$(…)"`, where
  `$?` is the status of the *negated compound* — 0 exactly when the command failed — so every
  failure reported `exited 0`. That constant is what produced, and cost a verification pass to
  unwind, the theory that a hook had exited 0 while failing. The assignment now stands alone, and
  the helper's documented `0/2/3/4` taxonomy is translated into distinct messages, so "not a
  repository", "no `worktree_root` configured" and "illegal branch name" are no longer one
  indistinguishable line. Every refusal leads with a **remedy** and follows with the diagnosis.
  **Corrected mechanism:** the issue was filed on the premise that the transcript surfaces only the
  *first* stderr line; measured on 2.1.228, a failing hook's stderr is surfaced **in full** inside
  the harness's own error text. Remedy-first still holds — it is the line a reader acts on — but it
  is a readability argument, not a truncation one. The helper's non-repository refusal gained the
  same treatment.
- **An empty or unbufferable stdin payload was reported as the wrong cause**
  (`hooks/worktree-create-gate.sh`; #2209). `hook::buffer_stdin`'s status was ignored, so a payload
  that never arrived surfaced as "the WorktreeCreate payload carried no `.name`" — sending readers
  after a field in a document the hook had never received. The two are now separate messages. The
  jq-absent fail-open path through the `sed` fallback is untouched.
- **Both worktree suites were unrunnable on any machine with `commit.gpgsign=true`**
  (`hooks/worktree-create-gate.test.sh`, `scripts/worktree-create.test.sh`). Their repo fixtures set
  a throwaway identity but not `commit.gpgsign false`, so every fixture commit failed for want of a
  secret key for that identity — and the suites then reported their *creation* cases as failures
  while their refusal cases still passed, a shape that reads as a real regression rather than an
  unrunnable fixture. Repo-local on a just-`mktemp`'d repo, the same line the sibling suites
  (`scripts/landed-work.test.sh`, `skills/commit/scripts/exec-bit-check.test.sh`) already carry.
  `worktree-create.test.sh` goes from 94/154 to 154/154 on such a machine.

## [0.51.17]

### Fixed

- **`babysit_merge` enforces `requireSignatures` instead of only reporting it (#2265).**
  `branch_rules` computed the flag and nothing consumed it: on a base whose ruleset requires signed
  commits, a head held only by an unsigned or misattributed commit reported the generic
  `mergeStateStatus` line naming four other causes — none of them the real one — and the operator
  went re-reading checks, approvals, and threads that were already fine. New
  `fetch_pull_request_commits` (`babysit_gh.py`) reads `.commit.verification` per PR commit,
  paginated `per_page=100`; a missing verification block reports reason `unreadable` rather than
  being skipped. `evaluate()` walks the commits only when the rule is present (an ungoverned base
  pays no extra request), in the read-only pass — a signature hold discovered only under `--merge`
  would defeat the wrapper's report-readiness purpose — and emits one blocker per verification
  reason naming every offending commit. `unsigned`, `no_user`, and `unknown_key` carry distinct
  remedies: `no_user` states that the signature IS valid and the author/committer email is
  unlinked (#2162's recurring product, needing `--reset-author` or a linked email, not a key). A
  fetch failure holds with its own "could not be read" blocker (fail closed, never a fabricated
  reason). The generic `mergeStateStatus` enumeration now names signatures, and
  `requiredSignatures` `{required, checked, unverified}` joins the JSON report. New tests pin
  every reason message, the distinct-blockers property, the no-rule-no-request invariant, the
  fail-closed fetch failure, and the fetcher's projection; all fail against the pre-#2265 modules.

## [0.51.16]

### Fixed

- **A lane's worktree is locked at creation, and an in-flight operation outranks `landed` in
  `landed-work.sh` (#2257).** `git worktree remove` deletes a worktree whose `status --porcelain`
  is empty even while an interactive rebase paused at a `break` is mid-flight — cleanliness cannot
  carry liveness. `worktree-create.sh` now arms `git worktree lock` the moment the worktree exists,
  with a reason naming the helper, host, and start time; the cleanup skill already honored a
  `locked` flag, but nothing in this repo ever set one, so that input was structurally always
  absent. `landed-work.sh` adds `BISECT_LOG` to the in-progress probe (a bisect leaves porcelain
  completely clean) and ranks `in-progress` above `landed`: consumers read `landed` as
  safe-to-remove, and removal mid-operation destroys sequencer state and conflict resolutions even
  when every commit is durable — the stranded family still outranks it, data loss being the
  stronger stop. `cleanup.md` gains the locked and in-progress candidate rows (a locked worktree is
  disarmed with `git worktree unlock` after explicit owner confirmation, never bypassed with
  `--force --force`) and `create.md` documents the lock and its interaction with
  `git worktree move`. New tests pin the lock (armed at creation, reason names the helper, plain
  removal refuses and the tree survives) and the ranking (bisect probed; in-progress outranks
  landed); all fail against the pre-#2257 scripts.

## [0.51.15]

### Fixed

- **D6's reachability gate resolves the push remote instead of hardcoding `origin`**
  (`reference/review-discipline.md`, `skills/pull-request/SKILL.md`; #2310). 0.51.12 replaced the
  tip read with `git fetch origin <branch> && git merge-base --is-ancestor <fix-sha>
  origin/<branch>` — a hardcoded remote that release itself introduced, while the same skill pushes
  through `push-branch.sh` / `resolve-remote.sh --push` (pushRemote, pushDefault, non-`origin`
  tracking, triangular forks). On such a checkout a successful push is followed by a fetch of the
  wrong remote — a false D6 failure that blocks D7 and thread resolution — and an `origin` base
  repo carrying a same-named branch can verify the wrong ref entirely (Codex P1 on #2262). Both
  gates now resolve the remote through the existing `resolve-remote.sh --push` and compare against
  `FETCH_HEAD`, exactly what the resolved remote just served. Verified live in both directions: a
  non-tip fix commit on its branch exits 0 where the old tip read reported it missing, a commit
  from a sibling branch exits 1 where the repo-presence lookup returns 200, and a deleted remote
  branch fails the fetch loudly rather than passing.
- **The 0.51.12 entry's two overstated claims are corrected in place.** "Matching the reachability
  *primitive* `verify_fix_commit` uses" now claims the matching *guarantee*: that helper proves the
  same ancestor property via the clone-free, fork-aware compare API
  (`repos/{owner}/{repo}/compare/{sha}...{head_oid}`), not `git merge-base`. And `babysit_gh.py`'s
  `per_page=100` sits at `fetch_paginated_api`'s call sites, not adjacent to the `--paginate` flag
  the line-based #2246 sweep matched.

## [0.51.14]

### Fixed

- **Rule 3 no longer lists bare `select(f)` as element-wise-safe.** Bare `select(f)` applied to a
  paginated page (an array) errors in jq rather than filtering elements; only `.[] | select(f)` is
  safe. Qualified alongside the existing `map(f)` carve-out fix from 0.51.13.

## [0.51.13]

### Fixed

- **Rule 3 no longer lists bare `map(f)` as element-wise-safe (#2245).** `map(f)` is `[.[] | f]` — it
  builds an array per page, so `--paginate` emits one array document per page unless a trailing
  `| .[]` re-flattens. The carve-out now names `.[] | select(f)` and `.[] | f` as safe and calls out
  `map(f) | .[]` as the safe `map` form.

## [0.51.12]

### Fixed

- **D6's verify-commit-pushed gate checks branch reachability, not repo-wide presence or the branch
  tip** (`reference/review-discipline.md`, `skills/pull-request/SKILL.md`; #2244). The published
  form — `commits?sha=<branch>&per_page=1` with `--jq '.[0].sha'` — asked "is my fix commit on the
  remote?" but read only the branch tip, so any later push made it report the fix missing while it
  was present: a false negative on a control gate, and a positional index on a list. A
  repository-scoped `commits/<fix-sha>` lookup fixed the tip-read false negative but still answered
  "does this object exist anywhere in the repo?" — satisfied by a force-pushed-off commit or an
  identical commit on another branch. The gate now fetches the PR branch and runs
  `git merge-base --is-ancestor <fix-sha> origin/<branch>` (exit 0 when the fix commit is on the
  remote PR branch; 0.51.15 replaces the hardcoded `origin` with the resolved push remote),
  matching the reachability *guarantee* of `babysit-prs`'s `verify_fix_commit` — the same
  is-ancestor-of-the-live-head property — not its mechanism, which is the clone-free, fork-aware
  compare API (`repos/{owner}/{repo}/compare/{sha}...{head_oid}`) against the PR's own head
  repository.
- **Every remaining `--paginate` list read carries `per_page=100`**, conforming to rule 1 as
  `readiness.md` publishes it (#2246): `skills/pull-request/reference/merge.md` (three
  comment-source re-checks), `skills/pull-request/SKILL.md` (C1–C3),
  `skills/pull-request/reference/monitor.md` (poll-loop comment fetch),
  `scripts/fetch-all-pr-comments.sh` (the shared surface pager), and
  `skills/babysit-loop/reference/telemetry-upsert.md` (sentinel LOOKUP). Not truncation defects —
  `--paginate` alone fetches every page — but the default 30-per-page form costs 3.3x the
  requests and diverges from the rule the same skill states as absolute.
  `skills/babysit-prs/scripts/babysit_gh.py` and `scripts/request_review.py` were reported in the
  #2246 sweep but were already conformant: each passes `per_page=100` inside the endpoint URL —
  adjacent to the `--paginate` flag in `request_review.py`, and at `fetch_paginated_api`'s four
  call sites in `babysit_gh.py` — so the line-based sweep matched the flag without seeing the
  parameter.

## [0.51.11]

### Changed

- **Shared `hook-utils.sh`: the jq gate now has a fail-CLOSED sibling, and the posture reasoning
  lives at the helper (#2146).** `hook::require_jq` is unchanged and still fails OPEN — one visible
  skip notice per session, then exit 0 — which is the correct posture for every hook in this plugin,
  so **nothing in this plugin's behaviour changes**. What is new is `hook::require_jq_blocking`, a
  second named function that denies the tool call instead, for the narrow class of guards whose job
  is blocking an irreversible operation (today only two, both in `guardrails`). A sibling function
  rather than a parameter, because a flag's omitted value would default to fail-open and a guard
  whose flag someone forgot would then fail open *silently* — the exact defect #2146 reports,
  reintroduced at the API. The two postures are now argued together in one block above both
  functions, which is what #2146 asked for: previously each call site asserted a posture in a
  comment and nothing where the decision is made explained it. Synced from `lib/hook-utils.sh`.

## [0.51.10]

### Documentation

- **`exec-bit-check.sh`'s rename arm is `diff.renames`-dependent on the DEFAULT config, and that
  trade is now recorded where the gate is (#2141).** `git mv` of a `100644` shebang file reads as
  `D`+`A` under `diff.renames=false` and IS reported through the `A` branch; the same index and the
  same HEAD read as `R100` under the default `diff.renames=true` and are NOT. Only the config
  differs. **No behaviour change** — the `R*` arm keeps its `100755`-source gate. #2141 weighed
  dropping the gate for renames and making the `A` branch skip a rename-as-add, and kept the gate:
  the false positive it prevents is real and pinned by `repo19` in `exec-bit-check.test.sh` — a
  deliberately non-executable sourced library or template must not be flipped to `100755` because
  someone moved it. Dropping the gate would buy config-agreement by shipping that false positive to
  every consumer; making the `A` branch match would buy it by reporting *less*, risking silence on
  genuinely new files. What changes is the prose: content-determinism is stated as a property of the
  `A` and `C` classes only — never of the whole tool — at the script header, at the candidate-set
  gate, in `--help`, in `reference/exec-bit.md`, and next to `repo19`. New case group **19b** pins
  both halves of the disagreement on one fixture repo, with HEAD and the index asserted identical
  across the two runs, so the decision is executable rather than only written down.

## [0.51.9]

### Fixed

- **`babysit_merge` no longer drops required status contexts when more than one ruleset governs the
  base branch.** `branch_rules` assigned `requiredContexts` inside its loop over
  `repos/{repo}/rules/branches/{branch}`, but that endpoint returns one rule of a given type PER
  RULESET, so each `required_status_checks` rule overwrote the previous one and only the last
  survived. On a branch governed by two rulesets this reported one of four required contexts,
  under-reporting `effectiveRules` and the "required checks not satisfied" blocker. The single-rule
  assumption was correct under classic branch protection, which has exactly one such rule, and does
  not hold under rulesets. Contexts are now unioned across all rules, deduped (two rulesets may
  legitimately require the same context) and sorted (stable regardless of the order rulesets are
  returned in). An entry carrying no `context` is dropped rather than surfacing as a literal `None`
  required context. Not a merge-safety hole: the gate refuses independently on `mergeStateStatus`,
  which GitHub computes from all required checks. Its one safety-adjacent effect ran in the
  over-holding direction — `baseUnprotected` is true when the context list is empty, which under
  the bug meant "the LAST status-checks rule is empty" and now means "ALL of them are", a subset —
  so the bug produced a false hold on a superset of cases and never retired one. Latent on this
  repository, where neither ruleset carries an empty context list.
- **`pull_request` rules are folded across rulesets too.** Same assign-in-loop shape, same
  function. `requiredApprovingReviews` now takes the max and `requireThreadResolution` the OR — the
  fail-closed direction whatever GitHub's own composition rule is, since max/OR can only
  over-report and hold a PR for a human, where last-wins can under-report and release one. This
  one could lose a blocker outright: a trailing rule with `required_approving_review_count: 0`
  erased an earlier ruleset's requirement and dropped the "needs N approving review(s)" hold. Not
  observed — one such rule governs the branch today. The count fold is a behaviour change; the
  boolean is report-only, never consumed as a blocker. The count also distinguishes an ABSENT
  `required_approving_review_count` (the rule requires no reviews — zero) from one present but
  unreadable (`null`, `""`, `0.0`, `[]`, `{}` — a requirement is stated and its size is unknown, so
  it counts as one). Collapsing a falsy non-int to zero would be the single fail-open step in a
  fold whose guarantee is that it may only ever over-report.

## [0.51.8]

### Fixed

- **`skills/pull-request/reference/readiness.md` no longer documents a `check-runs` query that
  silently truncates.** Gate 1's codex-verification command called
  `repos/{owner}/{repo}/commits/<sha>/check-runs` with no pagination. The endpoint returns 30 per
  page by default and reports nothing when it truncates, so on any PR carrying more than 30 check
  runs the command answers "is check X present?" with a silent *no* for every check that landed on
  a page the caller never fetched — indistinguishable from a check that never attached. Observed on
  this repo: three separate heads returned `total_count=33, returned=30`, dropping
  `do-not-merge / do-not-merge` — a required status context — every time, and a reader concluded
  the context never attaches. It attached and was green on all three. The command now uses
  `--paginate` with `per_page=100`, matching the form
  `skills/pull-request/scripts/fetch-annotations.sh` already used. Pagination alone only moves the
  cliff to 100, so the gate also documents a completeness assertion — `total_count` against the
  flattened count across every page — and names the trap that makes the naive assertion wrong:
  `--jq` runs per page, so `.check_runs | length` reports one page at a time and must be slurped
  before comparing. The rule is hoisted out of Gate 1 into a `Reading GitHub list APIs` section,
  because it governs every gate in the file rather than one command.
- **The per-page `--jq` trap is stated as its own rule, and Gate 5 no longer breaks it.** With
  `--paginate`, `gh` applies `--jq` to each page *separately*, so any expression that folds a whole
  list — `length`, `sort_by`, `add`, `max`, `group_by` — silently answers per page. Element-wise
  filters are safe because their results concatenate; folds are not. Gate 5's codex-comment count
  was itself an instance: `--jq '[…] | length'` over four pages printed `10 10 10 3` instead of
  `33`. It now slurps the page stream with `jq -s` and flattens with `.[][]`, and the rule sits
  beside the other two rather than being buried in the completeness-assertion prose.
- **Every documented PR comment and review read is paginated, and the positional-index reads are
  gone.** The same 30-per-page default governs `issues/<pr>/comments`, `pulls/<pr>/comments`, and
  `pulls/<pr>/reviews`, all of which return **oldest-first** — so an unpaginated read drops the
  newest items, which on a PR being monitored are the only ones that matter. Corrected in
  `readiness.md` (comment-only actor discovery, bot-actor discovery, the codex-comment count at
  HEAD, and Gate 4's three reads) and `skills/pull-request/reference/monitor.md` (all three
  review-surface polls; the reviews poll filters `submitted_at` client-side, which made pagination
  load-bearing there rather than merely tidy).
- **`reference/review-discipline.md` and `skills/pull-request/SKILL.md` no longer verify a reply
  with `.[-1]`.** This shape is worse than truncation: it does not omit, it answers. On an
  unpaginated oldest-first list `.[-1]` is the **30th-oldest** comment, so D7's "did my follow-up
  post?" check passes or fails on someone else's comment. Measured on this repo: issue #657 (33
  comments) returned a comment timestamped 11.5 hours before the actual latest; #502 (31) returned
  the second-newest. Both call sites now paginate and select on the fix SHA, so the query states
  what it is asserting and cannot be satisfied by the wrong record. The inline-reply verifications
  filtered by `in_reply_to_id` are paginated for the same reason.
- **D7's follow-up verification is constrained on the posting identity, not just the SHA.** Selecting
  on SHA-in-body alone proves the SHA was *mentioned*, not that you posted it — a reviewer quoting
  the fix commit, or a bot restating it, satisfies the selector while your own failed write goes
  unnoticed. That is the same failure shape as the `.[-1]` bug it replaced: a plausible positive
  instead of a real presence signal, on a control gate an autonomous agent acts on. Both copies of
  the checklist step now pin `.user.login` as well. Rule 2 gains the general form: where a query is
  a control gate, ask what else could satisfy the selector and constrain that too — one property is
  usually not enough.

## [0.51.7]

### Fixed

- **`worktree_create_gate_enabled` could not be turned off.** `hooks/worktree-create-gate.sh`
  reads `CLAUDE_PLUGIN_OPTION_WORKTREE_CREATE_GATE_ENABLED` and names the option in its own skip
  message, but the option was never declared in `.claude-plugin/plugin.json`. Claude Code exports
  `CLAUDE_PLUGIN_OPTION_<KEY>` only for **declared** options, so the variable was never set, the
  hook's `:-true` fallback always won, and the gate ran unconditionally. Setting the option
  produced no effect and no error — the failure was silent in both directions. The declaration is
  now present with `default: true`, so behaviour is unchanged for anyone who does not set it, and
  the documented routes for setting it now work.

## [0.51.6]

### Changed

- **`skills/worktree`: the pre-compute constraint is grounded in the documented isolation checks
  instead of one observed refusal (#2176).** The SKILL had recorded, from #1619, that "a
  worktree-isolated agent refuses a git-bearing compound command" — true, but stated as an incident,
  which invites a future author to test whether it still holds and fold the calls back. Claude Code
  v2.1.224 documented the enforcement, so the constraint now cites it: an isolated session is screened
  by three checks — main-checkout file edits, a command whose working directory resolves there, and a
  git redirect into it "whether through `git -C`, `--git-dir`, a `GIT_DIR` or `GIT_WORK_TREE`
  variable, or a `cd` into the main checkout before running git" — and both command-level checks fail
  closed, since "Claude Code also blocks a command it can't verify stays inside the worktree"
  (`code.claude.com/docs/en/worktrees#how-claude-code-enforces-isolation`, fetched 2026-08-10). That
  reframes the refusal: an unverifiable compound command is blocked on the same footing as one that
  would really have reached the main checkout, so no amount of narrowing the commands makes the
  pre-compute block safe again. Two adjacent facts are recorded with it — the enforcement "covers
  every subagent Claude spawns from the isolated session", interactive or background, so delegation
  does not escape it; and "For PowerShell commands, Claude Code applies only the working-directory
  check", noted as narrower coverage rather than as a sanctioned route around the git-redirect check.

## [0.51.5]

### Fixed

- **Shared `hook-utils.sh`: `hook::jq_fields` now REPORTS a NUL byte in a payload value
  (#2122).** 0.51.2 stopped a NUL from failing the helper's cardinality check, by stripping every
  NUL out of each value. That keeps the helper working, but stripping also silently rewrites the
  value — `--no-verify<NUL>x` arrives as `--no-verifyx` — so a caller that owns a block/allow
  verdict cannot tell a clean payload from one that carried a NUL, and matches against a token the
  payload never held contiguously. The fact is now reported in a new `HOOK_JQ_FIELDS_NUL` global,
  set on EVERY call including every failure path, so such a caller can fail closed on its own terms.
  It is computed from the values as the payload carried them, BEFORE the strip; strip first and the
  flag would read "0" on every payload. Values themselves are unchanged — still stripped, so a
  scanning caller still sees everything after the NUL. This plugin's own hooks do not consult the
  new global, so their behaviour is unchanged. Synced from `lib/hook-utils.sh`.

## [0.51.4]

### Fixed

- **`exec-bit-check.sh` no longer skips a copy destination whose source was never executable
  (#2118).** `R*` and `C*` shared one `src_mode == "100755"` gate, so a copy off a `100644` shebang
  source went unreported — while the *identical staged content* under `diff.renames=false` reports
  as `A` and IS reported. That config-dependence is the exact failure the candidate set was widened
  in #1590/#2098 to remove. The two statuses are not symmetric and no longer share a predicate: a
  rename destination is the same tracked file at a new path, so a `100644` source means nothing
  dropped a bit and the rename arm keeps its gate; a copy destination is a path that did NOT
  previously exist, so it is newly added, squarely inside this check's scope, and the copy arm now
  gates on nothing and defers to the `100644`-plus-shebang filter exactly as `A` does. Consequence
  worth naming: copying a deliberately non-executable shebang library is now reported under
  `diff.renames=copies`. That is not a new trade — creating one, or copying one under any other
  `diff.renames` setting, is already reported through the `A` branch; the change makes the opt-in
  copy-detection configuration agree with the default rather than adding a class of finding.

## [0.51.3]

### Fixed

- **Shared `hook-utils.sh`: `env -S` / `--split-string` no longer hides a whole command from the
  git guards (#2124).** `-S` exists so a shebang line can pass OPTIONS to env
  (`#!/usr/bin/env -S -i prog`), so the words it splits out are env's own arguments. The resolver
  spliced them back into the scan but resumed at the COMMAND dispatcher, which read a leading
  option in the split string as the command NAME and gave up — `env -S '-C <dir> git push --force'`
  resolved to no git at all, so every guard built on `hook::git_resolve_index` skipped the command
  unexamined. Parsing now resumes inside env's own option loop. That also keeps env's single chdir
  slot last-wins across the splice, so `env -C a -S '-C b git …'` reports `b`, matching GNU env.
  Synced from `lib/hook-utils.sh`.

## [0.51.2]

### Fixed

- **Shared `hook-utils.sh`: a NUL byte inside a payload value no longer makes `hook::jq_fields`
  come back empty (#2120).** The helper delimits its batched fields with NUL, and a JSON string may
  legitimately encode one — a `Write`/`Edit`/`NotebookEdit` content field can. jq emitted the raw
  byte, the read split that value in two, the cardinality check saw one value too many, and the
  helper returned non-zero — which every caller treats as "skip", so the hook exited without doing
  its work. Each value is now NUL-stripped INSIDE the jq filter, so the delimiter provably cannot
  occur in a value. Stripping is not a lesser alternative to an encoding scheme, it is the only
  representable behavior: a bash variable cannot hold a NUL byte, and the per-field command
  substitution this helper replaced dropped the byte and kept the rest of the value — so content
  AFTER a NUL is returned and scanned exactly as it was before the batching. Synced from
  `lib/hook-utils.sh`.

## [0.51.1]

### Fixed

- **The PR-body linkage gate and validator deadlocked on a maximum-length PR body.** Both walked the
  body with `while … done <<<"$body"`. Bash delivers a here-string by filling a pipe ITSELF, before
  the reader is exec'd, and appends a newline, so a body of 65536-65663 bytes puts the write 1-128
  bytes past the 65536-byte pipe capacity and blocks forever. GitHub caps a PR body at exactly
  65536 characters, which lands INSIDE that window — so the worst case is not exotic, it is the
  documented maximum. `pr-body-linkage-gate` is a blocking PreToolUse gate, so a hang means the
  harness cancels it at its timeout and the linkage contract goes unenforced. Both now read through
  `< <(printf '%s\n' "$body")`, which is byte-identical to the here-string it replaces and so
  cannot drop a final line. Same class as #1587 (`hook-utils.sh`) and the guardrails scan gates fixed
  alongside this.

## [0.51.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.50.0]

### Changed

- **The self-login exemption from the merge gate's unprotected-base hold is scoped to the
  repository's default branch.** `babysit_merge.py` held a PR on an unprotected base — zero required
  reviews AND zero required status contexts — only when its author was not a configured self login.
  That exemption exists for the solo-owner repository whose default branch carries no rules, where
  holding every PR would make the gate useless; it silently extended to *any* unprotected base, so a
  self-authored pull request onto another branch merged under `worker`/`autopilot` with no required
  check having governed it. The default branch's rules are the only ones such a merge would ever
  face, and they never ran.

  The hold now also fires for a self author whose base is not the repository's default branch, with
  `--allow-unprotected` as the same deliberate override. A stacked pull request's upper layer is
  exactly this shape (self-authored, base = the layer below), but so is any feature-onto-feature
  merge — the gap did not depend on stacks and is not fixed by detecting them.

  The default branch is read only once an unprotected base has cleared every other blocker, so
  neither a protected-base run nor an already-held PR issues a request it did not issue before — a
  fleet loop never pays that call per cycle for a PR it already knows is ineligible. A
  repository-metadata read failure leaves the prior exemption standing rather than inventing a hold
  from missing evidence.

## [0.49.3]

### Fixed

- **`exec-bit-check.sh` keys its candidate set on a new index *entry*, not on the letter `A`
  (#1590).** Rename and copy detection rewrite the very entries the check exists to catch: the same
  staged file reports as `A <path>` with detection off and as `R<score> <old> <new>` or
  `C<score> <src> <dst>` with it on. Rename detection is on by default (`diff.renames`), so the
  script discarded those destinations and a newly added shebang file staged `100644` could be
  committed non-executable purely as a function of the consumer's diff configuration. A pair
  destination is now a candidate whenever its **source was `100755`** — the mode pairing that means
  the bit was *dropped*, as `core.filemode=false` platforms produce on `mv`/`cp` plus `git add`. A
  deliberately non-executable shebang file (a sourced library, a template) keeps `100644` on both
  sides of a move and is left alone. The scan reads `git diff --cached --raw` rather than
  `--name-status` for exactly this reason: only the raw record carries the source mode.

- **`prune_babysit_worktrees.py` restores the gitfile on every path that leaves the directory
  standing (#1331).** Restoration was keyed on `rmdir` raising, but two other survival paths bypass
  it: the directory rescan after the unlink can itself raise, and a file appearing between the
  unlink and the rmdir skips the removal without raising at all. Either way the directory outlived
  the only record of its owning repository, turning a retryable failure into a permanent
  `unresolved`. Restoration is now keyed on whether the removal actually happened, and its own
  `Path.exists()` probe runs inside the guard — that call re-raises an `OSError` outside the
  ignored not-found family, so a permission denial on the directory being rescued would otherwise
  escape the `finally` and leave the pointer deleted.

- **The conflict orchestrator revalidates the base *before* the final head check (#1355).**
  `safety.md` requires the head check immediately before every push, but the base re-fetch — a
  network round trip — sat between that check and the push, re-opening exactly the window the
  check closes: a writer resetting the PR branch to an ancestor inside it would make the push a
  valid fast-forward that silently restores the removed commits. The contract now runs base → head
  → push in that order, with nothing between the head check and the push.

- **The orchestrator's head checks carry an explicit remote target (#1355).** The orchestrator's
  cwd is whatever the fleet run started from, never reliably the target repository, so a bare
  `gh pr view <N>` either failed or read a same-numbered PR from the wrong repository. Both checks
  now spell `GH_REPO=<owner>/<repo>`, as the worker contract already required for remote-only `gh`
  calls.

- **The `VALID (defer)` grounding rule states its no-tracker branch (#1633).** Grounding a deferral
  mandates filing a work-item tracker item before the D5 reply, and the rule named no branch for the
  consumer that has no tracker to file into — even though the same skill documents a tracker as an
  optional adjacent capability whose absence must never block a phase. Reaching that branch never
  actually stalled `full` mode (the degrade clause and a `VALID (fix now)` reclassification both
  already escaped it); what was missing was the instruction saying so. It is now stated: with no
  reachable tracker `VALID (defer)` is simply not an available disposition — fix the finding now, or
  reply saying why the fix does not belong in this change, leave the thread unresolved, and report
  it for the user to place. Carried on all three surfaces that state the filing mandate: the
  canonical `review-discipline.md` §3 clause and its `pull-request` `SKILL.md` and `monitor.md`
  restatements.

## [0.49.2]

### Fixed

- **`pr-linkage-mcp-gate` yields to a consumer repo's own tracked equivalent.** A repo that wires
  its own `pr-linkage-mcp-gate` in `.claude/settings.json` (the marketplace repo does, so the
  policy survives sessions with no plugin install, and that copy is deliberately kill-switch-free)
  previously got BOTH gates firing exit-2 on every MCP PR create/update. The plugin copy now
  defers (telemetry outcome `deferred`, exit 0) when the consumer's settings wire a PreToolUse
  command naming `pr-linkage-mcp-gate`. The plugin side yields because the settings file states
  the wiring authoritatively, while the repo-local script has no sound "plugin active" signal
  (plugin source present never implies plugin enabled — #2021 line 4 investigation). Named,
  accepted cost: a no-op script of the same name suppresses the gate — this is a policy gate,
  not a security guard, and the required CI check remains the authority.

## [0.49.1]

### Added

- **`babysit-loop`: the rate-limit floor's reactive-only mode now reads the detection records.**
  The fail-open bullet named reactive-only but gave the lane no `stop-events.jsonl` behavior; the
  skill now carries the reader contract's read cadence (read on mode entry and before each new work
  claim, recency baseline = lane start advanced by each resume attempt). Mirrors rate-limit-guard
  0.4.4's reader-contract addition.

## [0.49.0]

### Added

- **babysit-prs: an orchestrator-side independent resolution dispatch, so a disproved current bot
  thread has a route to a terminal state (#1641).** `--independent-resolver` (0.42.0) supplied the
  mechanism; nothing supplied the route. A worker that correctly disproves a bot finding —
  classifies it `INCORRECT`, posts counter-evidence — ships no fix by definition, so the thread
  stays current and satisfies neither `classify`'s `isOutdated` requirement under `--autonomous` nor
  the Worker Contract's tighter pre-push-outdated rule. A grounded `VALID (defer)` and a prose fix
  that rewrote elsewhere in the file land in the same place. The only dispatch that could retire
  such a thread was `babysit-loop`'s pre-escalation resolver, reachable only on the explicit
  `autopilot` + `--merge c3-this-run` widening, so on every ordinary worker-tier run the D7.5
  routing rule terminated in a fail-closed report and the PR sat unmergeable on a finding that was
  fully and correctly addressed.

  The worker now **reports** such a thread as addressed-but-unresolvable (thread id, disposition,
  where the evidence lives) instead of leaving it silently, and — **in a thread-resolving tier
  (`worker`, `autopilot`) only** — the orchestrator routes it, under the PR's worker lease, before
  Cleanup releases it, to a fresh subagent that authored neither the fix nor the counter-evidence.
  The safe tier dispatches nothing: it never resolves threads, and a resolver it dispatched would
  resolve one at one remove. **`classify`'s `isOutdated` requirement under `--autonomous` is
  untouched**; the property it was a proxy for (the context that authored the evidence is not the
  context that acts on it) is what the dispatch preserves. The orchestrator does not resolve the
  thread itself: it holds the merge decision, so adjudicating its own unblock would be the same
  self-certification one hop up.

- **babysit-prs: `reference/independent-resolution.md`, the single owner of that dispatch
  contract.** The D7.5 per-finding verification ledger, the independence requirements, the
  wrapper command shapes, the lease sequencing, and the fail-closed bounds previously lived only
  inside `babysit-loop/reference/pre-escalation-dispatch.md`, which is one of the two callers.
  Writing a second copy into `orchestration.md` would have forked the contract, so it moved to the
  skill that owns the wrapper; `pre-escalation-dispatch.md` now keeps only its widening-specific
  bounds (frontier tier, the four blocker classes it never touches, the post-dispatch re-partition)
  and points here. `guard_contract.py` gains an `independent-resolution.dispatch-commands` doc row,
  so the file's copyable wrapper commands are parser-validated like every other documented command.
  The pointer is scoped to *discipline*, not to the resolve form: the new file's severity bound is a
  bound of `--independent-resolver`, terminal on the babysit-prs route because the mode is its only
  form there, and `pre-escalation-dispatch.md` says explicitly that inheriting it would delete the
  security/P1 exception it exists to carry rather than guard it.

### Fixed

- **The "reachable only on the explicit `autopilot` + `--merge c3-this-run` widening" claim was
  true when written and is no longer (#1641).** `review-discipline.md`'s D7.5 authorization rule
  and `babysit-prs/reference/loop.md`'s Never-Do entry both asserted it; both now name the two
  invocations that reach a dispatch and keep the identical fail-closed fallback — leave the thread
  unresolved, do not merge, report the PR with the addressed-but-unresolvable thread named — for
  every bound the dispatch cannot cross: a security/P1 thread (`skipped-severity-marked`), a
  multi-finding thread, a human thread, evidence the world rejects, or no subagent tools to
  dispatch to. `safety.md`'s Security/P1 "only one dispatch path" bullet is unchanged in substance
  and now says so explicitly: the orchestrator-side dispatch is not a second route to that
  exception, because the wrapper's severity bright line refuses those threads on it.

- **The clause registry no longer reads the dispatch's own NAME as a restatement of the
  authorization rule (#1659, #1641).** `scripts/contract-clause-registry.json` listed
  `independent resolution dispatch` among `D7.5-merge-authorization`'s `restates` signals, written
  when the phrase was only descriptive prose in the canonical span. This change gives that
  mechanism its own file, so the phrase became a proper noun — and the untagged sweep then reported
  the file's own title and two pointer sentences that link to it, i.e. a false positive on exactly
  the pointer-not-copy outcome the gate steers toward. The alternate is dropped; the three that
  state the rule (`never clears the gate`, `adjudicating context`, `authorizes a resolution`) stay.
  Verified non-lossy against the default branch: with every `D7.5-merge-authorization` marker
  stripped from the four tagged surfaces, the narrowed pattern still reports all of them
  (`loop.md`, `pull-request/SKILL.md`, `pull-request/reference/monitor.md`, and the canonical
  span's own requirement) — the dropped alternate detected nothing the others did not. `detect` is
  untouched, because being in scope only means the file is read.

## [0.48.2]

### Changed

- **`babysit-loop`: listing description tightened (1,468 → 1,197 chars)** — trimmed the explanatory
  prose from the frontmatter `description` toward the shared skill-listing budget
  (claude-code-plugins#2022, option 2). Every single-quoted trigger phrase is preserved verbatim
  (skill-quality check 3); the merge-authority invariants (fail-closed human-only default,
  tracked-seam-only raises, the c3-this-run anti-spoofing clause, the independent frontier-tier
  resolver) stay stated in the entry and fully stated in the skill body.

## [0.48.1]

### Changed

- **`pull-request`: the CI-log grep rule leads with the instruction instead of a `CRITICAL:` prefix.**
  `reference/monitor.md` opened with "CRITICAL: Do NOT use `grep -i ...`", which states the
  prohibition before the thing to do. It now says to grep for `##[error]` annotations first and gives
  the reason — a broad keyword grep matches cleanup steps, variable names, and incidental output. The
  worked "Bad credentials" example and the fall-back-if-empty rule are unchanged.

- **`pull-request`: section 1.3's heading is "Verify every finding".** The shout-caps `EVERY` and the
  `(CRITICAL)` parenthetical restated emphasis the numbered verification procedure below already
  carries. No step, classification, or drop rule changed.

## [0.48.0]

### Changed

- **The merge lane's cycle report must now be grounded in tool results from that cycle**, with
  unverified work said to be unverified rather than left undistinguished. The step already bounded
  what the report contains and how often it is written; it said nothing about whether its claims were
  true.
  - This is the one surface where a fabricated line survives: nobody watched the cycle, no receiver
    re-derives the report the way a dispatching orchestrator re-derives a worker's return, and the
    comment is the operator's only record of what happened. Anthropic's Fable 5 prompting guide names
    exactly this case — "Before reporting progress, audit each claim against a tool result from this
    session" — and reports that the instruction nearly eliminated fabricated status reports in its
    testing, including on tasks built to provoke them.
  - The wording matches the sibling drain lane's word for word because their step 6 is the same step;
    that is a coincidence of scope, not a shared source, and neither is registered as one.

## [0.47.2]

### Fixed

- **`babysit-prs` `engine.test.sh` resolves ruff from the declared pin instead of PATH (#1856).**
  A workstation `ruff` at a different version from the one CI installs made the harness report
  findings on an unmodified tree that CI does not, or miss findings CI raises — the two disagree in
  both directions once a release changes the default rule set, as 0.16.0 did. The lint pass now
  goes through `scripts/run-ruff.sh`, which uses a PATH `ruff` only when it already matches the pin
  in `.github/requirements-ci.txt` and otherwise runs `uvx ruff==<pin>`. The pin is read at run
  time, so this follows the repository's version wherever it goes rather than freezing a value
  here.

- **`engine.test.sh` finds that wrapper on a relative invocation, so the lint pass actually runs.**
  The suite re-derived the repository root from `BASH_SOURCE` *after* `cd`-ing into its own
  directory. `BASH_SOURCE` holds the path as invoked, so a relative invocation resolved against the
  new working directory and landed outside the repository: the wrapper was never found, the harness
  printed `SKIP: scripts/run-ruff.sh not found (lint pass omitted)`, and the suite exited 0 having
  linted nothing. `scripts/run-plugin-tests.sh` runs it from the repository root, so that was the
  path CI took every time. The script directory is now captured once, before the `cd`.

## [0.47.1]

### Changed

- **Shared `hook-utils.sh`: a hook invocation spawns three fewer external processes (#1978).**
  Every hook that buffers its stdin paid an `awk` (one float division, to slice the read timeout), a
  `printf | tr -d '\r'` pipeline (a fork and an exec to delete one byte class from a string bash
  rewrites in place), and a `jq -e .` validity probe over a buffer the read loop had already parsed
  with jq. On Windows Git Bash, where process creation is `fork()` emulation, each spawn costs
  ~140 ms. Behavior is unchanged: the slice keeps the three-decimal form `read -t` is given, the
  buffer is CR-stripped as before, and the completeness verdict is reused only when jq itself
  produced it — so a host without jq still fails open exactly as it did. Also adds
  `hook::jq_fields`, which extracts several fields from one payload in a single jq process for
  hooks that read two or three of them. Synced from `lib/hook-utils.sh`.

## [0.47.0]

### Added

- **`worktree` gains a stranded-work axis, and a detection engine to compute it.** The skill could
  report that a worktree was old, quiet, and clean; it could not report whether removing it would
  destroy a commit — different questions with the same surface symptoms. `scripts/landed-work.sh`
  is the new read-only classifier: one TSV row per registered worktree carrying `unpushed`,
  `landed`, the method and base SHA the verdict was reached with, the in-progress sequencer
  operation, four independent working-tree counts, peer worktrees, a risk class, and a reason.

  Only affirmative proof yields `landed=yes`. Every failed command, empty result set, unresolvable
  base, and ambiguity yields `?`, which every consumer treats exactly as `no` — a false `no` costs
  a confirmation prompt, a false `yes` destroys work.

  The unpushed set is `HEAD --not --remotes`: `--branches` reports every other branch in the
  repository and says nothing about a detached worktree's own commits, and `@{upstream}..HEAD`
  returns nothing at all for a locally created branch. Landedness is decided by RANGE patch-id
  first, because a squash-merge collapses N commits into one patch that no per-commit primitive —
  `git cherry` included — can ever match, while the branch's range id equals the squash commit's
  and stays matched as the base advances.

  Patch ids are computed `--verbatim`. The default and `--stable` hash the patch AFTER stripping
  whitespace, so `a b` and `ab` produce one id — measured on git 2.54, both `7ad14294…` — and a
  branch whose unique change differed from the base's only in whitespace classified as landed.
  `--verbatim` separates them, still matches a multi-commit squash, and still matches after the
  base advances; what it gives up is the tolerance that let an EOL-renormalized branch match, which
  now reports `no`. That is a confirmation prompt in exchange for a silent deletion, and the trade
  is deliberate.

  No affirmative verdict is drawn from an incomplete patch-id set: a commit that produces no patch
  — an empty commit among them — is invisible to patch-id, so the id count must equal the non-merge
  commit count before "every commit's content is on the base" is a statement about the branch
  rather than about the commits that happened to hash.

  The path-scoped two-dot fallback answers one question, whether the touched paths differ from the
  base at all, and its verdict is stamped with the base SHA it was computed against. It carries no
  direction test: `git diff base..HEAD` reports deletions both for a branch that is merely BEHIND
  the base and for a branch whose own unique work IS a deletion, and the numstat rows are
  identical, so "additions are zero" classified a delete-only branch as landed. The
  behind-the-base shapes it was written for are caught by the range patch-id instead.

  A registered path is confirmed to be a work-tree ROOT with `rev-parse --show-prefix`, since
  `--is-inside-work-tree` returns true for a leftover directory inside a repository and reports
  that repository's clean state as the directory's own. Enumeration reads
  `git worktree list --porcelain -z` into a file and checks its exit status before parsing — a
  process substitution's failure is invisible to the loop, and the row-count assertion can only
  catch a truncated pass, never a truncated enumeration — and `-z` because a worktree path may
  contain a newline. An ambiguous base ref and a criss-cross history with several merge bases both
  yield `?` rather than a silently chosen one. `comm`'s exit status, the numstat reducer's result,
  and `git status`'s exit status are each checked, because a failure in any of them produces the
  same output shape as the favourable answer.

- **The two-dot fallback hands its paths back to git instead of matching two diffs' text.** Two diff
  invocations only agree on how a path is spelled when they agree on every escaping rule, and they
  did not: `--name-only` quoted non-ASCII bytes while `--numstat` was pinned to
  `core.quotepath=false`, so an i18n'd filename joined against nothing — and an empty join is the
  same shape as "identical to the base", an unproven `landed=yes` on a commit that existed nowhere
  else. Pinning quotepath on both sides closed that byte class and left another, since git escapes
  `"`, `\`, and control characters regardless of the setting and only `-z` suppresses it. Rather
  than chase escaping rules one class at a time, the touched paths are now passed back to git as
  `:(literal)` pathspecs and git does its own matching, which removes the entire mismatch class.
  `:(literal)` because a path is not a pattern — a file named `star[1].txt`, or one beginning with
  `:`, would otherwise be read as pathspec magic. The pathspecs are chunked so a branch touching
  thousands of files cannot exceed the platform's command-line limit.

- **The base-side patch-id set gets the same completeness check as the branch side.** An
  under-complete base set can only make a match less likely, so this was never the difference
  between `yes` and `no` — it is here so the two sides cannot silently diverge under a later
  refactor, and so a base range that failed to render is named rather than quietly narrowing the id
  set every branch is compared against.

- **`worktree-create-gate`: a `WorktreeCreate` hook that places every worktree at the configured
  root.** `/worktree create` already routed through `worktree-create.sh`, but three creation paths
  bypass the skill entirely — `claude --worktree`, a subagent with `isolation: "worktree"`, and a
  background session. Those landed in the in-repo `.claude/worktrees/` default, which is the
  placement the whole nesting invariant exists to prevent. The hook is a thin stdin adapter over
  the same helper, so there is one placement implementation rather than two.

  Its contract was measured rather than inferred, which settled the two questions that had blocked
  it. A **user-scope** hook does fire — verified with a settings.json under a `CLAUDE_CONFIG_DIR`,
  headless, before login was even resolved — and `${CLAUDE_PROJECT_DIR}` resolves to the project
  root the session started in, never the worktree being created. And stdout's **last non-empty
  line** is taken as the path: a hook printing a banner line before the path still succeeds and the
  session lands in the printed directory, refuting the claim that any output but the path fails the
  session. The hook still prints the path alone; the tolerance is margin, not interface.

  Fail-closed: a hook failure fails the creation, because falling through would place the worktree
  at exactly the nested path this prevents. The unconfigured case is not a failure — it resolves to
  the plugin data directory, also outside every repository. The root is read from
  `CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT` rather than substituted as `${user_config.worktree_root}`,
  which Claude Code rejects in shell-running fields. Opt out with `worktree_create_gate_enabled`.

### Changed

- **`worktree status` classifies Work before Status.** `merged` widens to "PR merged **or** every
  unpushed commit landed on the base"; `stale` narrows to require Work to be safe, so a worktree
  holding unpushed unlanded commits is `stranded` rather than merely old. `stranded`,
  `superseded`, `notgit`, and `unknown` join the table, and the summary names the at-risk commit
  total. A stranded row whose commits survive in a peer worktree is presented as such — a
  materially different decision from losing them.

- **`worktree cleanup` guards both places work actually dies.** Removal is recoverable: it leaves
  the branch ref intact. The `git branch -D` the procedure emits one step later is not, and a
  detached-HEAD worktree has no branch ref to begin with — so the precondition is stated at the
  pre-removal site AND carried through to the emitted branch deletion, which now emits nothing
  destructive for stranded, unproven, or superseded work. `superseded` is a narrowed *reading* of a
  `landed=no` row and never a safe one: the merged-PR evidence matches on the branch NAME, so a name
  reused after that merge carries new commits that are still the only copy. It gates exactly as
  stranded. The two pre-removal guards have a stated order
  (stranded first, because it can abort the removal outright), the override is
  `--acknowledge-stranded` per worktree rather than a bare `--force` answering a different
  question, and every path offers `git -C <path> push -u origin HEAD` first as the resolution that
  needs no judgement about whether the work matters. The escalation guard's unpushed probe moves
  from `--branches` to `HEAD`.

### Fixed

- **The nesting invariant's evidence and upstream citations were stale.** The as-of stamp moves
  from 2.1.220 / 2026-07-31 to 2.1.224 / 2026-08-07, and three control arms are added that narrow
  what the invariant rests on: the leak is not specific to `.claude/worktrees/` (a plain non-dot
  subdirectory leaks identically, so nesting itself is the cause); a worktree inside an
  **unrelated** repository is worse rather than better, inheriting `CLAUDE.md` and unconditional
  rules at `session_start` too; and the mechanism is that session-start ancestor traversal is
  suppressed for ancestors of the worktree's own repository but not a different one, while
  `path_glob_match` discovery is suppressed in neither.

  The recheck trigger cited two issues that are both CLOSED — #29599 (`duplicate`, COMPLETED) and
  #23565 (NOT_PLANNED), verified live against the GitHub API. It now cites #16600, which is OPEN,
  and states the gap that citation leaves: #16600 concerns memory files, which 2.1.224 already
  handles correctly, so the surface still leaking — path-scoped rules — has no open upstream issue
  at all. `context/create.md` carried the same two dead citations and now points at the skill's
  paragraph rather than restating them, so the state lives in one place.

## [0.46.2]

### Fixed

- **`babysit-prs` `reference/safety.md`: the permission-mode enumeration behind the wrapper-path
  invocation now matches the official page (#1941).** The list named "Manual and accept-edits" as
  the prompting modes and then covered plan mode and auto mode, so it mixed the CLI display label
  with config values and accounted for four of the six modes. `dontAsk` was the load-bearing
  omission: it auto-denies every call that would otherwise prompt, so an uncovered wrapper
  invocation is refused with no classifier and no prompt — the exact silent-failure hazard the
  section exists to warn about — and `bypassPermissions` was missing too. The enumeration now names
  all six config values (`default`, `acceptEdits`, `plan`, `auto`, `dontAsk`, `bypassPermissions`),
  states once that `default` is the value behind the **Manual** display label with `manual` as a
  v2.1.200 CLI alias, adds plan mode's third branch (bypass-permissions sessions do not enforce its
  blocks), and splits the outcomes into prompt / no-prompt / auto-deny with the `permissions.ask`
  exception stated per mode.

## [0.46.0]

### Added

- **`babysit_loop_trusted_internal_bot_logins` — a reviewed internal-bot trust signal for the
  babysit-loop C5 trust test (#1525, fixing #1520).** The rung partition's trust test classified
  every non-`OWNER`/`MEMBER` author as C5 untrusted-provenance, but GitHub App bot identities are
  never org member accounts, so repository-owned automation — which the autonomy guardrails' work
  classes explicitly place in C2 — was categorically ineligible at every merge rung. The new
  loop-lane key names the exact bot logins a repository attests as its own internal automation: a
  flat bullet list on the tracked `.claude/source-control.md` surface, honored from the TARGET
  repository's team-tracked layer only — always read from its default branch, never any working
  tree, so a checkout sitting on a bot-authored branch cannot self-grant — making every trust
  grant a recorded, reviewable config change; unset, unreadable, or malformed fails closed to
  the empty set, leaving the trust test exactly `OWNER`/`MEMBER`. The match arm requires a
  structural bot (the `[bot]` login suffix or provider `Bot` type), the fork test stays
  independent (a listed bot authoring from a cross-repository head is still C5), the
  dependency-manager hold-merge invariant wins on intersection with
  `babysit_extra_dependency_manager_logins` and the built-in set, and a trust match never
  establishes a work class — it only removes the categorical C5 bar. `babysit_watched_owners`
  remains never a trusted-author list. Documented in `config-resolution.md` ("the C5 trust test's
  one reviewed widening"); loop-lane convention bumped to 8.0.0 in lockstep; eval added for the
  bot-author cases. Design decision, rejected alternatives, and cross-vendor review recorded on
  #1525.

## [0.45.1]

### Fixed

- **`babysit-loop`: the pre-escalation resolution dispatch now honors the resolved thread-resolution
  dimension (#1786).** The dispatch fired on the widening pair alone, while the *"Dimension
  overrides bind by tier flooring"* rule was scoped only to *"Before invoking"* the babysit-prs
  tier — and `reference/pre-escalation-dispatch.md` contained no occurrence of `dimension` at all.
  So `autopilot --merge c3-this-run --thread-resolution safe` still dispatched a fresh subagent to
  mutate bot threads the operator's own argument had just denied, against
  `reference/config-resolution.md`'s *"invocation arguments win"* rule for every dimension but
  merge. Resolving review threads **is** an exercise of dimension 3, so the flooring rule now
  explicitly binds every capability the cycle exercises for a PR rather than only the tier keyword
  it passes on: a floored thread-resolution dimension withholds the dispatch outright and the PR
  escalates, reported as override-constrained — never a dispatch made and then narratively told not
  to resolve. New eval 6.
- **`babysit-loop`: the pre-escalation dispatch names its resolver mode, and it is the one that can
  actually clear the blocker (#1786).** Neither `SKILL.md` nor `reference/pre-escalation-dispatch.md`
  stated which `babysit_resolve_thread.py` mode the dispatch runs; as written, *"the full per-PR
  worker lifecycle"* implied `--autonomous`, which hard-refuses any thread not already `isOutdated`
  before its own push — precisely the current, non-outdated bot thread D7.5 routes to this dispatch,
  so it could never clear the blocker class it exists for. The mode is now stated as
  `--independent-resolver` (landed in 0.42.0, #1782), with the D7.5 ledger mapped onto its validated
  evidence flags (`fixed`/`--fix-commit`, `deferred`/`--tracker-item`,
  `incorrect`/`--counter-evidence`, `UNCERTAIN` → escalate), and the worker-lifecycle sentence scoped
  to how a **code change** is made rather than to mode selection. Two shapes the mode refuses are
  named where the dispatch will meet them, because the ledger's per-finding phrasing does not imply
  either: a thread carrying more than one source finding (`skipped-multi-finding-thread` — one
  disposition cannot clear a thread whose other findings would drop out of the readiness
  denominator) and a severity-flagged thread. Both escalate rather than resolve. New eval 7.
- **`babysit-prs`: the security/P1 bright line is no longer documented as having an exception
  (#1786).** `reference/safety.md` titled a section *"Security/P1 escalation: the one named
  exception"* and presented the pre-escalation resolver as that exception, citing the loop-lane
  convention's §1 — but that convention exception widens the **merge rung** for a single run and
  never touches the severity line, and the same file's `--independent-resolver` rules (with the
  wrapper itself) refuse a severity-flagged thread in every unattended mode. The documented
  exception was therefore unreachable, and it now contradicted `babysit-loop`'s newly explicit
  refusal. The section is retitled and reframed: the bright line has no exception, the paired
  argument unlocks the *dispatch path* rather than the severity widening, and the four scoping
  bullets stay with the dispatch they actually describe. Both inbound citations are corrected with
  it: `SKILL.md`'s one-line restatement, and `babysit-loop/reference/pre-escalation-dispatch.md`,
  which cited the old heading and repeated the refuted claim that the exception is *"scoped to
  security/P1 escalation"*.
- **`babysit-loop`: the subagent discipline preamble no longer hand-copies the discipline plugin's
  membership (#1786).** `SKILL.md`'s Subagents section enumerated `(sweep-all, use-your-skills,
  do-your-research)` inline, which the loop-lane convention's own no-enumeration rule forbids and
  which drifts from the plugin that owns the list. It now points at the sweep skill, which resolves
  its own membership.

## [0.45.0]

### Changed

- **An unset `worktree_root` now defaults to `<plugin-data-dir>/worktrees` instead of refusing every
  `/worktree create`.** The key ships unset, so the refusal fired on a fresh install and the command
  was unusable until the user configured a root by hand — a hard failure standing in for a missing
  default. The containment guard is untouched — a root that resolves inside a repository is still
  rejected, and that check, not the unset check, is what enforces the nesting invariant.

  **The data directory is supplied, not read from the environment.** In a general Bash-tool
  subprocess — which is what every caller of the helper runs in — `CLAUDE_PLUGIN_DATA` is not scoped
  to the invoking plugin; this repository's own probe recorded it naming an unrelated installed
  plugin's data directory. The skill instead substitutes `${CLAUDE_PLUGIN_DATA}` into its own
  SKILL.md body, where it does render per-plugin, and hands the resolved path to the new
  `--data-root-file` flag through the same byte-verbatim file channel `--root-file` already uses.
  A configured root always wins; the data dir is only the fallback. If substitution ever regresses,
  the file carries the literal token, which the helper detects and refuses — never a wrong
  directory.

  A repository-derived default (`<parent>/worktrees`) was considered and rejected: under a
  discovery layout such as ghq's `<root>/github.com/<owner>/<repo>` it lands INSIDE the tree the
  discovery tool walks, and `ghq list` then reports each worktree as a repository of its own — a
  leading dot does not hide it.

### Fixed

- **The refusal rationale cited a defect that no longer reproduces.** Four surfaces — the helper,
  its `--help` text, the `worktree_root` config description, and both skill surfaces — attributed
  the nesting ban to Claude Code's CLAUDE.md/rules double-load bug, fixed upstream in v2.1.69. The
  ban is still correct, for a narrower reason measured on 2.1.220: from a worktree nested inside a
  checkout, a read matching a path-scoped rule's glob also loads the PARENT checkout's copy of that
  rule. Every surface now states the live constraint, so the next reader auditing the guard against
  a fixed bug does not conclude the guard is obsolete.
- **`worktree_root` was missing from the README's configuration table** while every sibling key was
  listed.

## [0.44.1]

### Fixed

- **`babysit-loop`'s inlined telemetry upsert now gates its body and verifies what landed (#943).**
  The lane's telemetry comment was observed carrying a literal `@C:/…/telemetry_combined.txt` as its
  entire body across three sessions: `gh` expands a leading `@` only for `--body-file` / `-F
  field=@file`, so an `@path` passed as a body VALUE is transmitted as text. `claude-ops`'s
  `telemetry-upsert.sh` refuses such a body and re-reads what it wrote, but an installed plugin cannot
  invoke a sibling plugin's script, so this lane inlines its own upsert and inherited neither
  protection. The block now carries three checks, which catch different failures. A **pre-write gate**
  rejects a `$BODY_FILE` that is empty, opens with a literal `@`, is not sentinel-prefixed, or holds
  under 16 bytes of payload — no POST, no PATCH. The **write's own exit status** is then checked, because a
  failed PATCH leaves the previous cycle's body in place and a read-back running regardless would
  accept it. A **post-write read-back** then re-reads what the write stored and reports the cycle
  UNREPORTED unless that body still opens with the sentinel and clears the same floor; this is the
  check that would have caught the actual #943 shape, where the composed file is perfectly fine and
  the defect is the invocation (`-f body=@FILE` instead of `-F body=@FILE`) — a file-only check is
  structurally blind to it. The create path is covered by the same cycle's
  PATCH, and a degraded POST leaves no sentinel-prefixed comment to re-read, so that branch now
  reports UNREPORTED too instead of falling through silently. The 16-byte floor is measured on everything below the
  sentinel LINE, so it matches the wrapper's `MIN_BODY_BYTES` byte-for-byte on LF and CRLF alike;
  prefix comparison is byte-wise, so a CRLF body is not false-rejected. Every branch that ends without
  a verified body reports UNREPORTED and skips the duplicate-supersede pass, so a cycle whose own
  write is unproven never tombstones a racing session's comment. The `$BODY_FILE` sentinel-first-line contract is now stated in
  prose rather than left implicit in a comment. Two wrapper limits are inherited rather than fixed: a
  PATCH that succeeds while storing the previous body still verifies, and the read-back proves *some*
  well-formed telemetry is present, not *this* cycle's. Not replicated at all: the 64 KiB cap, the
  body-file containment checks, retries, and the wrapper's distinct non-zero exits — every inline
  branch exits 0 and reports through stderr.

## [0.44.0]

### Fixed

- **`babysit-loop`'s telemetry marker named the lane type, not the writer (#1295).** Every
  concurrent instance of the lane built the same fixed sentinel, so two merge lanes on one
  repository resolved one comment and overwrote each other's durable state last-writer-wins — the
  same defect `work-items`' lanes carried, and identical in shape, so fixing it in one lane would
  have left it latent in this one. The marker now carries the loop-lane convention's lane-instance
  suffix (`source-control:babysit-loop@<instance>`) and each instance owns exactly one comment no
  sibling can match. The creation-race reconcile is unchanged and now converges duplicates within an
  instance's own sentinel set. The `Lane telemetry: <lane>` issue title is untouched, so the
  lane-infrastructure exclusion every consumer matches on does not move.

### Added

- **`lane_instance` config key, and an instance-collision check in the durable state block.** The id
  defaults to the sanitized lowercased hostname and is validated `^[a-z0-9][a-z0-9-]{0,31}$` inside
  the lane's own executable block, since it is operator-supplied text interpolated into a shell
  string and a `jq` program. The block (now `source-control/babysit-loop-state@2`) carries
  `lane_instance`, a per-session `writer_nonce`, a per-cycle `heartbeat_at`, and `paused_until`: a
  differing nonce over a stale block is the ordinary restart adoption; over a *fresh* block it means
  another live lane holds this id, and the lane writes nothing, escalates, and stops cleanly.
  `paused_until` is not the rate-limit latch — the latch says do not claim work, `paused_until` says
  do not read this lane's silence as death. Two shapes the freshness test alone misreads are carved
  out: a fresh block carrying a non-null `restart_request` is a stopped predecessor's clean handoff
  (recording the ask is its last write), so the replacement adopts immediately — clearing the
  request — instead of waiting out the staleness window; and an unclaimed marker is claimed with a
  cycle-0 block plus a re-read through the creation-race reconcile *before any work*, so two
  same-id sessions starting together stop before either overwrites the other's first durable
  state.

## [0.43.0]

### Added

- **babysit-prs: the (c) non-convergence tripwire is now decided from durable state instead of
  session memory (#1660).** `safety.md` shipped a rule that a **second consecutive advisory round
  whose findings are all (c)** — self-inflicted, against text this lane's own prior fix introduced
  — means incremental patching is injecting defects as fast as it removes them, and the lane must
  change METHOD. That test needs to know what the PREVIOUS round contained, and nothing durable
  recorded it: `manage_feedback_ledger.py record-advisory-round` stored `{"recorded_at": ...}` per
  head and no more. The rule was therefore satisfiable only inside one uninterrupted session,
  while the babysit loop crosses a context boundary on every cycle — a rule that reads as binding
  and, for the case it was written for, silently never fires.

  `record-advisory-round` now takes **`--finding-class` once per finding in the round** (`a`
  genuine duplicate, `b` new and distinct, `c` self-inflicted) and persists the per-finding
  provenance counts alongside the timestamp. The flag is **required**, refused at exit 2 — an
  optional flag would have reproduced the same defect one layer down, because an unclassified
  CURRENT round leaves the tripwire just as unevaluable as an unclassified predecessor, and a
  silently unrecorded classification is exactly what #1660 is about. The refusal is a
  `guard-contract.md` row (`ledger.advisory-round-requires-finding-class`), so it is asserted by
  the guard suite rather than asserted in prose.

  The verdict is computed once, in `babysit_delta`, and read in two places that answer different
  questions. `record-advisory-round` returns the recorded round's `composition` and the resulting
  `non_convergence_tripwire` immediately — that is the read that arms the round being dispatched,
  and why the classification is recorded before the fix rather than after it. The snapshot carries
  `advisory_fix_rounds.non_convergence_tripwire` (`armed` plus the `basis` it was decided on) over
  the rounds recorded so far, adding a material finding when armed, so a worker picking the PR up
  cold sees where it already stood. **Neither read reconstructs the previous round's composition
  from GitHub threads** — the expensive, resolution-fragile duty `safety.md` used to impose.

  **Rounds recorded before this release read as UNKNOWN, and the tripwire fails closed on them**:
  a current all-(c) round following an UNKNOWN round arms and says so, rather than silently
  resetting the count. That preserves the disposition the previous prose already chose for an
  unmarked predecessor. Two scoping facts are now stated where the rule lives, because the ledger
  can only answer what it records: the test is over consecutive **advisory** rounds (blocking-defect
  rounds are never capped and never recorded, so one in between neither counts nor resets), and
  UNKNOWN is not a synonym for "no (c) findings".

## [0.42.3]

### Added

- **Every surface that restates a review-disposition clause now declares itself (#1659).** The
  D4.6 grounding and provenance rules, D7.5 thread eligibility, and the authorization rule for a
  resolution that ships no fix are canonical in `reference/review-discipline.md` and restated
  across five other surfaces. Each restatement now carries a `contract-restatement` marker naming
  the clause it copies, and `scripts/check-contract-clause-coverage.py` holds it to the canonical's
  qualifiers within its own span. Untagged text that restates a clause is reported too, so a new
  copy has to be argued for rather than appearing silently.

### Fixed

- **`pull-request/reference/monitor.md` restated D4.6 grounding without the id-citation
  requirement.** It instructed filing the deferral in the work-item tracker with evidence and the
  PR link, but not citing that item's id in the D5 reply — so a deferral could be filed and still
  leave the thread with no route back to it, which is the dropped finding D4.6 exists to prevent.
  Found by the new gate, not by review.

## [0.42.2]

### Fixed

- **Shared `hook-utils.sh`: the OS temp tree is no longer treated as project content (#1769).**
  `hook::read_file_path` scoped a file to the project by prefix-matching `CLAUDE_PROJECT_DIR`, so a
  session whose project directory is the user's home admitted everything under the OS temp root —
  including Claude Code's own per-session scratchpad, which lives there. Hooks that lint, rewrite, or
  autocorrect then ran on throwaway files that are not project content and carry no project config to
  opt out with; the reported case was `typos-format` autocorrecting a shell variable in a scratch
  script and silently breaking it. The guard now rejects a file inside the OS temp tree when the
  project root is outside it. The exemption is deliberate and load-bearing: when the project root
  itself lives under temp — a `mktemp -d` fixture checkout, which is how this repository's own hook
  suites run — its files are still accepted. Temp roots come from `TMPDIR` / `TMP` / `TEMP` plus the
  POSIX defaults, canonicalized through the same pipeline the membership comparison already uses.
  Synced from `lib/hook-utils.sh`.

## [0.42.1]

### Fixed

- **Shared `hook-utils.sh`: a wrapper's working-directory change is no longer lost when a caller
  parses only git's own global options (#1503).** `hook::git_resolve_index` walks wrapper programs
  (`env`, `sudo`, …) to reach the real `git` token, and a caller that scopes its git-global parsing
  to the slice starting at that token cannot see a relocation the wrapper already performed — GNU env
  documents `-C, --chdir=DIR` as "change working directory to DIR". The resolver now reports those
  directories in a new `HOOK_GIT_RESOLVED_WRAPPER_DIRS` result global, in execution order, so a
  caller composes them ahead of git's own globals instead of dropping them. Five spellings are read
  (`-C DIR`, `-CDIR`, `--chdir DIR`, `--chdir=DIR`, and a clustered `-vC DIR`), a repeat within one
  `env` is last-wins as env itself resolves it, and sudo's `-D`/`--chdir` is read in its unclustered
  spellings. A chdir spelled inside `-S`/`--split-string` is NOT read; that path already fails open
  for any command on `main` and is tracked in #1814. This plugin does not consume the new global; the sync keeps its copy
  byte-identical with the source. Synced from `lib/hook-utils.sh`.

## [0.42.0]

### Added

- **babysit-prs: `--independent-resolver`, an evidence-gated third mode for
  `babysit_resolve_thread.py` (#1632).** `--autonomous` admits only threads GitHub marks
  `isOutdated`, which is the right guard for the merging worker but means "the referenced code
  moved". On a prose or documentation PR a finding is normally addressed by rewriting elsewhere in
  the file, so the anchor never moves, the finding is genuinely addressed, and the guard refuses —
  measured across two real babysit runs, 7 of 20 resolved threads were still not `isOutdated`, and
  that undercounts, because a worker's own push flips the flag without touching a comment. The
  consequence was that an autonomous prose lane had no sanctioned route to zero unresolved
  threads. The new mode is **parallel to `--autonomous`, never a relaxation of it**: it replaces
  `isOutdated` with caller INDEPENDENCE (a fresh context that is neither the merging worker nor the
  author of the fix — the actor resolving is not the actor whose permission slip it is) plus
  machine-validated DISPOSITION EVIDENCE. Independence is a property of the dispatch that no script
  can verify, which is exactly why the evidence half is checked here.

  `--disposition` names one of three claims and carries exactly its own evidence flag, validated
  against the world rather than trusted: `fixed` + `--fix-commit <sha>`, which must be reachable
  from the PR's current head commit (resolved through the head repository, so a fork PR compares
  correctly — existence elsewhere is not evidence this PR carries the fix); `deferred` +
  `--tracker-item <id>`, which must exist and still be open (a closed follow-up is not a deferral,
  it is the finding disappearing); and `incorrect` + `--counter-evidence <text>`, which must
  already appear in a REPLY on the thread, posted by someone other than the thread's OPENER so the
  finding's own author cannot supply the words that rebut it. Excluding the opening comment alone
  was not enough: the mandated classification reply restates the finding's own text, so a finding
  bot that also replies on its own thread would satisfy a `--counter-evidence` claim quoting it. A
  different bot's reply, and the caller's own reply under a `--self-logins` identity, both stay
  admissible — those are the independent parties the disposition is about.

  **A multi-finding thread is refused outright** (`skipped-multi-finding-thread`). One
  `--disposition` is a claim about ONE finding while `resolveReviewThread` clears the whole thread,
  dropping every comment it carries out of the readiness denominator
  (`babysit_classify.thread_is_open`) — so evidence for finding A would suppress an unaddressed
  finding B and let the merge gate pass over it. That is the D7.5 whole-thread eligibility rule
  (`reference/review-discipline.md`) enforced mechanically instead of left to the caller. The count
  comes from the shared severity vocabulary (`babysit_classify.severity_occurrences`, made public
  so the resolver and the readiness counters cannot drift apart) applied to the thread's own
  comments, with a self classification reply's table rows stripped so the worker's own echo of a
  finding is not counted twice; it fails closed, so a truncated comment page's unknown count
  refuses too. The guard is scoped to this mode alone: `--autonomous` rests on `isOutdated`, which
  GitHub computes for the whole thread rather than per finding, so it carries no per-finding claim
  to under-cover. The receipt gains a `findingCount` per thread and a `skippedMultiFinding` summary
  counter.

  **Every `gh` failure now names which answer it got.** Only a confirmed HTTP 404 (parsed from the
  `(HTTP nnn)` status `gh` reports on stderr, verified against gh 2.95.0) earns an
  evidence-specific refusal; a 403, 429, 5xx, timeout, or unreachable API reports
  `refused-evidence-unverifiable`. Previously any nonzero exit from the `compare` lookup reported
  `refused-fix-commit-not-on-head` and any nonzero exit from the tracker-item lookup reported
  `refused-tracker-item-not-found`, sending a caller off to replace evidence that may be perfectly
  valid when the real fix was to retry an outage.

  **Every URL path segment is format-validated before interpolation**, matching
  `babysit_gh.fetch_blocked_base_compare`'s rule for the identical call shape. In
  `verify_fix_commit`: `head_owner` and `head_name` against `GITHUB_OWNER_RE` /
  `GITHUB_REPOSITORY_RE` (and `..` rejected), `head_oid` and `sha` against the commit-SHA pattern.
  Two of those arrive in an API response body, so "the API said so" was their only provenance — a
  crafted or compromised response carrying path syntax could otherwise redirect the request to an
  unintended endpoint. In `verify_tracker_item`, the same rule applies to the resolved `owner/repo`:
  `TRACKER_ITEM_RE` admits an owner/repo *shape*, not a valid one (its character class allows a
  leading dot and a bare `..`), so `validowner/..#1` built a path that was never a GitHub endpoint
  and the resulting 404 reported `refused-tracker-item-not-found` — naming a missing item for a
  lookup that never addressed one. Fail-closed either way in both functions (an unexpected response
  always refused), so this narrows the reachable surface and sharpens the refusal reason rather than
  fixing an exploitable resolve.

  Fail-closed throughout. Missing, unparsable, mismatched, or surplus evidence is a usage error at
  exit `2` before any lookup; evidence the world rejects refuses the resolve with its own
  `action` — `refused-fix-commit-not-on-head`, `refused-tracker-item-not-found`,
  `refused-tracker-item-not-open`, `refused-counter-evidence-not-found`, and
  `refused-evidence-unverifiable` kept distinct so an API outage is never reported as a false
  claim. Evidence is validated in list mode too, so a dry run proves the evidence instead of
  predicting the resolve. A stale `--thread-id` pin is likewise reported in list mode now, not only
  under `--resolve`, so a dry run predicts what the resolve would do — this also corrects
  `--autonomous`'s pre-existing list-mode output, which previously reported `would-resolve` for a
  thread the very next `--resolve` refused. Every other guard is retained deliberately: bot-only authorship, both
  TOCTOU pins, and the security/P1 bright line, because an independent resolver is still an
  unattended path. `--autonomous`, `--include-human`, and `--allow-unpinned-thread` are each
  refused alongside it, and bulk is refused in every mode here (list included) since evidence is a
  claim about one finding. The JSON receipt shape is unchanged apart from additive `mode`,
  `disposition`, and `refusedEvidence` fields; the `bin/` wrapper needed no change, and its
  contract row already pins that it filters nothing.

  `verify_disposition` names every disposition explicitly and its fallthrough refuses, so a
  disposition added to `DISPOSITION_EVIDENCE` without a validator can no longer reach whichever
  branch happened to be last and be reported as validated by a check that never read its evidence.

  The existing modes are otherwise untouched, with regressions asserting it: `--autonomous` still
  refuses a non-outdated thread, still refuses bulk, and is not narrowed by the multi-finding
  guard. Five refusal rows and six classifier predicates were added to the guard contract
  (`reference/guard-contract.md` regenerated from them).

## [0.41.0]

### Added

- **`pr-linkage-mcp-gate` hook — the MCP-surface sibling of `pr-body-linkage-gate`.** Cloud/remote
  sessions have no `gh` CLI and open PRs through the GitHub MCP server
  (`mcp__github__create_pull_request` / `mcp__github__update_pull_request`), a surface the Bash
  hook never sees — so a body failing the consuming repo's required `pr-issue-linkage` check was
  only discovered a full CI round trip after the PR was open. The new PreToolUse hook mirrors the
  same validator semantics on the MCP payload (comment stripping, closing keyword or
  `No linked issue`, present-and-non-empty `## Related` with deeper headings as content) and the
  same scope guards (enforced only in a repo carrying
  `.github/workflows/pr-issue-linkage.yml`/`.yaml`; a call targeting a different repo than origin
  is out of scope, and a target that cannot be established — no origin remote, or a payload
  missing owner/repo — allows rather than imposing this checkout's policy on an unproven
  repository; an `update` with no `body` field allows). The MCP surface hands the hook the
  body as a plain JSON field, so the Bash sibling's extraction caveats don't apply; the one
  fail-closed addition is a `create` with no `body` field at all, which GitHub would open with an
  empty body the CI gate rejects. Kill switch: `pr_linkage_mcp_gate_enabled` (default true).
- **`pr-linkage-validator.sh` — the validator core extracted to one sourced lib.** The comment
  stripping, keyword/`## Related` judging, and the verdict wording now exist once, sourced by both
  hooks (and by the marketplace repo's checked-in MCP gate), so a drift fix against the upstream
  ci-workflows validator lands on every surface atomically instead of being hand-mirrored across
  copies. Behavior unchanged; each surface keeps its own extraction, scope guards, and block
  message.

## [0.40.2]

### Fixed

- **`babysit-loop`'s `usage_sample` prose contradicted the loop-lane invariant it cites.** The
  convention permits reading the previous sample back to derive `five_hour_delta_pct` — the
  subtraction *and* the rollover comparison — but 0.39.0 described the field as "deliberately inert:
  no lane behavior reads it back", which no lane computing a rollover-suppressed delta could satisfy.
  The convention's wording is corrected upstream (loop-lane 6.0.1); the entry recording 0.39.0 is
  left as shipped and superseded by this one. **The measure-only guarantee is unchanged** — the value
  still reaches no decision, at any threshold.
- **`at` was ambiguous between two timestamps.** It is when the lane read the tee, not the snapshot's
  own `captured_at`, which the staleness rule permits to lag it.
- **The delta's `null` condition read too narrowly.** "Either sample is missing" excluded a present
  sample carrying a `null` `five_hour_pct`; it is now `null` whenever either side's `five_hour_pct`
  is unavailable.

## [0.40.1]

### Fixed

- **`pr-body-linkage-gate` false-blocked any `gh pr create` preceded by a `cd` on the same command
  line.** The gate file and a relative `--body-file` both resolve against the payload's `cwd`, but
  the segment tokenizer discards the `cd` segment, so `cd <worktree> && gh pr create …` — a routine
  shape in a multi-worktree setup — was judged against the wrong directory entirely. Two live
  defects, not one: a compliant body was rejected because a same-named file in the session's
  directory was read instead, and enforcement leaked into repositories carrying no
  `pr-issue-linkage.yml` at all, contradicting the scope guard's own promise. A `cd`, `pushd`, or
  `popd` segment now puts every later segment out of scope, exactly as `--repo` already did. A
  directory change *after* the `gh` call still gates normally.
- **The hook exceeded its own 15-second timeout on a body of roughly 800 lines or more, silently
  ceasing to gate the largest PRs.** Trimming each body line ran through a command substitution, so
  every line cost a fork: a 1000-line body took 18.3 s measured. Both per-line trims — and the one
  in the heredoc reader — are now parameter expansion. The same body takes 1.3 s, and 5000 lines
  stays at 1.3 s. A regression test fails if a 1000-line body approaches the timeout.
- **The verdict depended on the ambient locale.** `[[:space:]]` stood in for JavaScript's `\s`, but
  its membership is locale-defined while `\s` is a fixed set, so under `LC_ALL=C` a body carrying a
  non-breaking space between `Closes:` and `#5` — routine in text pasted from an issue title — was
  rejected where the CI check accepts it. Both halves are pinned now: every non-ASCII character in
  the `\s` set is rewritten to a plain space by UTF-8 byte sequence, and matching runs under
  `LC_ALL=C`, where `[[:space:]]` is exactly the six ASCII whitespace characters. The two together
  reproduce `\s` on any host, and the tests assert both locales agree.
- **pflag's grouped shorthand carried bodies straight past the gate.** `gh pr create -db BODY`,
  `-dbBODY`, `-dF file`, and `-dFfile` are all valid gh and all were allowed, because only a bare
  `-b`/`-F` was recognized. Short clusters are now walked properly: boolean shorthands pass through,
  and the first value-taking shorthand ends the cluster, taking the rest of the word or the next
  word. An unknown letter stops the walk rather than guessing which letter would have consumed the
  following word.
- **`gh` was matched only as the exact literal.** `gh.exe`, `/usr/bin/gh`, `./gh`, and `sudo gh` all
  bypassed the gate, inconsistent with the basename comparison the wrapper loop ten lines above
  already used. The binary is matched by basename now, `.exe` suffix and backslash paths included,
  and `sudo` joins `env`/`command` as a recognized wrapper. Wrapper options are classified rather
  than blindly skipped, which three separate defects fell out of: a **separated** option value is
  consumed with its flag (`sudo -u root gh …`, `sudo -r staff_r gh …`, `env -u VAR gh …` all left
  the value sitting where the command name was expected, so the wrapped `gh` was never found); a
  directory- or root-changing option (`env -C DIR`, `sudo -D DIR`, `sudo -R DIR`) is the `cd` case
  wearing a flag and takes the same out-of-scope verdict, where before it **false-blocked** against
  the payload's directory; and `env -S 'gh pr create …'`, which carries an entire command line in
  one operand, is re-parsed the way an `sh -c` operand already was instead of being stepped over.
  A short wrapper word is read as a **cluster** rather than a single flag, so `sudo -Eu root gh …`
  and `env -iu VAR gh …` no longer leave their value where the command name belongs; an `env -S`
  operand is spliced with the wrapper's remaining words before re-parsing, since env appends those
  to whatever it split. And rather than keep extending an option table forever, a wrapper option the
  hook does not **positively** recognize now puts the call out of scope: whether it consumes the
  following word is unknowable, and guessing "boolean" silently moves the command name. One
  documented fail-open rule replaces an open-ended list of options to chase.
- **A stalled hook payload blocked the command.** The gate inherited the sibling security guards'
  fail-closed posture on an unreadable stdin, which for a scoped policy gate means refusing an
  arbitrary Bash command because the hook could not read its own input. It allows now; the header
  records the divergence and why.
- The `## Related` absent-versus-empty distinction moved from a `\001`-prefixed sentinel string,
  which a section whose content happened to equal it would have collided with, onto the return-code
  channel. The applicability pre-filter now requires `gh` at a word boundary, so
  `npm run lighthouse-prod` no longer pays for a full parse.

### Changed

- The gate's test suite no longer claims to prove the hook mirrors the ci-workflows validator —
  nothing in it executes that validator, so all 92 cases are hand-transcribed expectations, and the
  header now says so. A real oracle would mean vendoring upstream JavaScript into this repo, which
  is a separate decision; the divergences fixed above were found by running one out-of-tree.

## [0.40.0]

### Added

- **A `VALID (defer)` must now be durable to count as a disposition — D4.6 (#1614).** The review
  discipline already shipped the `VALID (defer)` classification, and `safety.md` already refused
  to resolve a thread "over a live, unaddressed finding", but nothing connected the two: a lane
  could defer a finding with a plausible sentence in a review thread and resolve against it,
  leaving no artifact anyone could find. D4.6 requires the tracker item to be filed **before**
  the D5 reply, carrying the finding's own evidence, with its id cited in the reply and re-queried
  to confirm it resolves. A deferral whose only record is thread prose is a dropped finding and
  the thread stays open. This narrows what a lane may resolve; it does not widen it, and the
  `--autonomous` `isOutdated` guard in `babysit_resolve_thread.py` is untouched.
- **Never defer a finding this change introduced, judged by base-branch behavior.** The
  discriminator is whether the defect reproduced before the change, never which file it surfaced
  in — so a contract this change altered that breaks an *unchanged* caller is still introduced
  here, and the untouched caller file is evidence about provenance rather than a licence to defer.
  `VALID (defer)` is available only for a defect that already reproduced on the base. Provenance
  decides, never severity: a self-introduced regression wearing a low-severity badge is still a
  regression the change is shipping, so it is `VALID (fix now)` — fix it or revert the cause.
- **A third class in the non-convergence taxonomy — (c) self-inflicted findings (#1614).** The
  existing (a)-duplicate / (b)-new-distinct split had no slot for a finding that is new and
  distinct *and* against text the lane's own prior fix introduced. Provenance decides the class.
  A (c) finding is fixed like any in-scope defect and is never deferrable, but it is counted: a
  second consecutive round of nothing but (c) means incremental patching is injecting defects
  about as fast as it removes them. The response is a change of METHOD — rewrite the contested
  section whole in one commit, or report for a human decision — never a licence to ship a known
  defect. This is a signal, not a counter; the `babysit_advisory_fix_round_cap` backstop is
  unchanged and a low round cap was rejected.

### Changed

- **D7.5 is now author- *and* classification-conditional (#1614).** Resolution eligibility
  previously turned on thread authorship alone, which is the operational hole behind
  `safety.md`'s "Resolve any thread over a live, unaddressed finding". Because resolution is a
  thread-level act while dispositions are per-finding, eligibility is a property of the **whole
  thread**: every finding extracted from it must carry one of three recorded dispositions, and one
  dispositioned finding never retires a multi-finding thread. That granularity is load-bearing
  rather than pedantic — a resolved thread drops every comment it carries out of the readiness
  denominator (`babysit_classify.py::thread_is_open`), so resolving early would make a still-open
  finding vanish from the classification gate and let the PR merge over it. A single `UNCERTAIN`
  holds its whole thread open. The eligible dispositions are: `VALID (fix now)` with the
  fix pushed and cited, `VALID (defer)` grounded per D4.6 with the item id cited, or `INCORRECT`
  with counter-evidence posted. `UNCERTAIN` escalates and is never resolved. Every existing
  author condition still applies on top. All four surfaces that restate the step — `pull-request`'s
  SKILL.md checklist and gotcha, `pull-request/reference/monitor.md`, and
  `babysit-prs/reference/loop.md` — are updated with it. They previously gated resolution on a
  pushed fix, so a correctly grounded deferral or an `INCORRECT` with counter-evidence satisfied
  canonical D7.5 and still left the thread open, holding readiness.
- **Non-outdated threads in an autonomous tier route to the independent resolver, not the worker.**
  `--autonomous` resolves only an `isOutdated` thread, because that is the one deterministic
  "addressed" signal available — otherwise the actor is "signing its own permission slip" on the
  merge gate's zero-unresolved-threads predicate. Prose fixes routinely satisfy a finding by
  rewriting elsewhere, leaving the thread current, so an addressed finding is often non-outdated
  (6 of 15 threads on #1594, 1 of 5 on #1615). Rather than widen the guard, such a thread goes to
  the independent resolution dispatch, which verifies the D7.5 disposition and resolves through the
  wrapper; worker-side self-resolution stays outdated-only exactly as the script enforces. Reaching
  past the wrapper to raw `resolveReviewThread` is called out as the wrong branch explicitly.
- **Eligibility here never overrides a tier's own guards.** A disposition that makes a thread
  eligible under D7.5 does not by itself authorize a resolve the invoking tier refuses. The worker
  tier is the live case: its contract permits resolving only a thread already `isOutdated` in its
  dispatch snapshot, so a disposition leaving the thread current — a grounded deferral, or an
  `INCORRECT` carrying no fix — is reported to the orchestrator as addressed-but-unresolvable
  rather than resolved. That is a description of today's behavior, not a fix; the underlying
  capability gap is #1641, and closing it must not weaken the `--autonomous` `isOutdated` guard.
- **The independent-authorization requirement states a property, not one mechanism.** Naming only
  the pre-escalation dispatch would have made the requirement unreachable — that path exists only
  on the explicit `autopilot` + `--merge c3-this-run` widening, so every other merge-capable path
  would have been required to obtain an authorization it cannot obtain, deadlocking a grounded
  deferral instead of terminating it. The rule is now "the adjudicating context must not be the
  merging context", with the dispatch named where an invocation has one and an explicit fail-closed
  fallback everywhere else: do not resolve, do not merge, report the deferral and let the user
  decide.
- **A defer-resolution on a PR the same session intends to merge is not that session's call.**
  In a merge-capable tier it routes through the fresh independent resolution dispatch
  `babysit-loop` already defines for a contradictory or unresolved bot thread, so a deferral that
  unblocks a merge is adjudicated by a context that is not trying to merge.
- **The auto-merge prohibition now states its reason (#1614).** "Enable auto-merge." sat in the
  Never Do Automatically list with no rationale, so each lane rediscovered it. Under a base whose
  ruleset requires thread resolution plus a reviewer that re-reviews every pushed head, a round
  landing after `--auto` is armed leaves the PR permanently unmergeable while the lane has
  already reported success. The prohibition is unchanged; only the reason is now written down.
- **Verify Before Escalating Non-Convergence states its own reach (#1614).** It binds every
  escalation of that shape regardless of which skill's escalation path carries it, so a lane
  escalating through a loop's own escalation contract no longer reads as outside it. `babysit-loop`'s
  Escalation section carries the matching pointer, because a lane raising a cap-policy question
  through that contract had no reason to open `safety.md` first — which is how #1614 itself came
  to be filed against the rule that forbids it.
- **The (a)/(b)/(c) round taxonomy is a per-round duty, not an escalation-time one.** It was
  written under a heading scoped to escalation and stamped markers "whenever the classification
  runs", while the ordinary advisory-round path (`orchestration.md`) recorded the round and started
  fixing without running it — so ordinary rounds produced no markers and the
  second-consecutive-all-(c) tripwire had nothing to read exactly when it mattered. Classification
  and stamping now run on every advisory round, before its fix is dispatched, and the
  advisory-round step names that duty at the point the round begins.
- **The pre-escalation resolution dispatch must produce a D7.5 verification ledger before it
  resolves anything.** `review-discipline.md` routes a current bot thread to that dispatch *because*
  it verifies the disposition, but the dispatch contract only required briefing the blocker and the
  independence/frontier-tier constraints — and the guarded wrapper checks authorship and comment
  state, never whether a finding was addressed. The dispatched agent could therefore resolve a
  current thread on an unaddressed finding and clear the merge gate's zero-unresolved-threads
  predicate, which is the worker-side self-satisfaction the outdated-only guard prevents, moved one
  hop. The contract now requires a per-finding ledger — pushed SHA verified on the live head, a
  D4.6-grounded deferral with a re-queried tracker id, or counter-evidence read at the live head —
  covering **every** finding in the thread, since one addressed finding never makes a thread
  eligible while a sibling is open. Anything unverifiable means no resolution, no merge, and an
  escalation naming it.

## [0.39.0]

### Added

- **`babysit-loop` samples per-cycle usage into its durable state block
  (melodic-software/claude-code-plugins#1651).** A lane's spend was a blind spot: the cycle budget
  counts cycles, the rate-limit guard's pause is a ceiling, and nothing recorded how much of the
  shared subscription windows a cycle actually consumed. The durable-state block now carries a
  `usage_sample` — the two window percentages the guard step **already reads** every cycle, plus the
  rise since the previous sample — so measuring adds a write, not an observation. The field is
  deliberately inert: no lane behavior reads it back, and no pacing, backoff, merge rung, or pause
  derives from it. Its caveats are recorded beside it because they bound what the data can support —
  the reading is a snapshot no fresher than the guard's staleness rule allows, from a machine-local,
  last-writer-wins tee that refreshes only while an interactive session renders a status line (so an
  unattended background lane samples null every cycle, and an empty sample means unobserved, not
  zero); the figures are account-scope (concurrent lanes move the same windows, so a rise is this
  lane's own consumption only when it is the sole active session) and a percentage of a subscription
  window rather than a token count. No token count is claimed because none is readable at a cycle
  boundary: the status-line context-window token counts are current-context occupancy rather than
  session totals as of Claude Code v2.1.132. A machine-readable cumulative cost field
  (`cost.total_cost_usd`) does exist and is session-scoped, so it is the deferred candidate for
  per-lane attribution — but the guard's tee does not forward it, and widening the tee is a
  rate-limit-guard change this entry deliberately does not make
  (<https://code.claude.com/docs/en/statusline>, re-verified 2026-07-28 — `used_percentage` 0–100,
  `resets_at` epoch seconds, `rate_limits` subscriber-only and each window independently absent; no
  drift).

## [0.38.0]

### Added

- **The merge gate can hold a PR while a review of the live head is still in flight (#1629).** A
  review bot that re-reviews on every push posts minutes after the head moves, and GitHub reports
  the PR mergeable for that whole window — the review does not exist yet, so there is no unresolved
  thread to block on. The gate read only that mergeability, so it could merge past findings landing
  seconds later: #1594 merged 4m40s after its final commit and the reviewer's round arrived 26
  seconds afterward with two valid findings, one a regression that PR had introduced (#1613).
  Configuring `babysit_review_bot_logins` together with the new `babysit_review_settle_minutes`
  adds a merge-gate policy blocker while a configured reviewer still owes the live head a review
  and that head is younger than the window. A review of the live head — a submitted review or an
  inline review comment carrying the head's commit id, reusing `review-trigger.md`'s existing
  current-head test — clears the hold without aging the head, so the already-reviewed case issues
  no request of its own. The window bounds the wait so a reviewer that never engages cannot wedge a PR, and a
  head whose age cannot be established holds rather than merging on an unverifiable clock. Both
  keys or neither: either alone is a usage error, never a silently inert flag, a window converting
  to under a second is refused rather than truncated to an inert zero, and the gate defaults no
  duration of its own because how long a reviewer takes is a property of that reviewer.

  Head age is measured on the **most recent CI start for the live head**, taken from the raw
  status-check rollup the gate already fetches — raw rather than classified, because the classifier
  keeps only the newest run per check identity. Newest rather than oldest is the safety property:
  check runs live on the SHA, so a head returning to a previously-checked SHA still carries that
  SHA's original runs, and reading the oldest would call a brand-new head settled. The cost is
  bounded latency — a re-run can extend the wait by one window. The committer date is the fallback
  only, since a commit pushed long after it was written reads as already-settled. Both that weak
  spot, the residual around a head reverting to an already-tested SHA, and the requirement that a
  configured reviewer be `Bot`-typed — this gate does not pass `--extra-bot-logins`, so the
  operator declaration #1642 added to the shared current-head test does not reach it — are
  documented at the hold's `safety.md` section rather than left implicit.

  That same timestamp is also the **review-recency floor**, which is what keeps the clock from
  being bypassed rather than merely pointed the wrong way. GitHub keeps a review against the SHA,
  not against the head position, so after a force-push A -> B -> A the first occurrence's review of
  A still matches by commit id; matching on the SHA alone let it satisfy the current-head
  short-circuit and merge before any clock was read, restoring the exact race the hold exists to
  prevent. `has_current_head_review` gains an optional `not_before` bound — passed only by this
  gate, so the review-trigger completion rule keeps its own semantics — and the settle hold
  supplies the newest CI start on the live head. A review that predates that bound, or that carries
  no parseable timestamp at all, no longer clears the hold. Evidence records now carry the
  submission time (`submittedAt` for reviews, `created_at` for inline review comments) so the
  comparison has something to read. A check start cannot tell a restored head from a re-run on the
  standing head, so a re-run minted after the review now re-arms the hold for up to one window
  instead of short-circuiting past it: the fail-closed direction, paying bounded latency to refuse
  the safety failure. A head with no check starts has no floor, so the earlier review still clears
  the hold — precisely the residual `safety.md` already scoped, and now pinned by a test so it is a
  decision on record rather than an accident.

  Unconfigured, the gate is byte-for-byte its prior self and issues no request it did not issue
  before — asserted against recorded call counts, not just the verdict. The reviewer corpus is now
  fetched once per run and shared with the autopilot merge tier rather than fetched twice.

  `safety.md`'s rendering rule now refuses a settle-window-without-reviewer-logins configuration at
  the orchestrator rather than rendering it away. The CLI's both-or-neither usage error cannot
  catch that case, because the instruction told the orchestrator to omit *both* flags when either
  key was missing — so the lone flag never reached the CLI and the merge proceeded with the hold
  silently dormant under a setting that looked active. `babysit_review_bot_logins` alone stays
  legal: it is the review-trigger module's own configuration and leaves this hold correctly
  dormant.

### Changed

- **`babysit-prs/SKILL.md` has headroom under the skill line cap again.** It sat at 499 of a hard
  500 — the same wall #1620 described for `babysit-loop`, which #1627 relieved for that skill only —
  so any net-positive edit failed `skill-quality-gate`. The autopilot tier's per-PR steps,
  exclusions, draft handling, and widened scopes move verbatim to
  `skills/babysit-prs/reference/autopilot.md`, leaving a pointer; the body goes 499 -> 471. Nothing is
  deleted, and the tier's operative commands stay where they already lived, in `reference/safety.md`.

## [0.37.0]

### Added

- **A `PreToolUse` hook blocks a `gh pr create` / `gh pr edit` whose PR body would fail the
  consuming repository's required `pr-issue-linkage` check.** The check is a merge gate, but nothing
  enforced its contract at authoring time, so a body missing a closing keyword or a `## Related`
  section was only ever caught post-hoc — one CI round trip after the PR was already open, on
  almost every PR an agent filed directly. `/pull-request create` has always run the equivalent
  pre-create gate (`skills/pull-request/reference/create.md` §2.4.2); this hook covers the calls
  that never go through the skill. On a violation it exits blocking and names the missing half plus
  the line to add, so the authoring agent self-corrects in the same turn instead of on the next CI
  cycle.
  - **Enforcement is keyed to the consumer's own policy**, not to a value this plugin ships: the
    gate runs only when the repository root carries `.github/workflows/pr-issue-linkage.yml` (or
    `.yaml`). A repository that does not run the check is never gated, so the hook cannot drift away
    from what its consumer actually enforces. This is deliberately not the `pr_body_required_sections`
    seam — that key is the repo's configurable section scaffold, whose portable default excludes
    `Related` on purpose; the authority here is the workflow file that defines the check.
  - **The validator is mirrored, not approximated.** HTML comments are stripped exactly as the
    reusable `melodic-software/ci-workflows` workflow strips them (terminated spans, then an
    unterminated comment opener swallowing the rest), a deeper `###` heading counts as the
    `## Related` section's content rather than its terminator, and JavaScript's word boundaries are
    transcribed explicitly so `Closes #12abc` and `unclosed #5` stay non-matches. A PR template
    whose instructional prose names the markers inside comments therefore cannot pass vacuously.
  - **Fail-open on extraction, fail-closed on a determinable bad body.** A `--body` literal, a
    readable `--body-file` path, and the sole heredoc feeding `--body-file -` or a
    `--body "$(cat <<'EOF' … EOF)"` substitution are judged. An unexpanded variable, several
    heredocs, an unreadable file, an absent body flag (`--fill`, `--template`, `--editor`, the
    interactive prompt), and any `--repo`-targeted invocation all allow — guessing at a body the
    hook cannot see would block compliant calls.
  - Toggleable via the new `pr_body_linkage_gate_enabled` userConfig option. The PowerShell tool and
    direct `gh api …/pulls` calls are documented as out of scope at the hook's own site.

## [0.36.0]

### Added

- **`babysit-loop` detects consecutive no-progress cycles and escalates instead of cycling
  invisibly (#1648).** Every stall mechanism was per-PR (`needs_worker` delta, `quiet_recheck_due`,
  `checks.stuck`), so a merge lane cycling repeatedly while its queue sat unmoved was invisible to
  itself. The lane now persists a `no_progress_streak` counter beside `cycle` and `backoff_level`
  in its `#502` durable state block: a cycle with open PRs in the cycle-start snapshot that ends
  with no qualifying progress — no PR merged or closed, materially changed (head, reviews,
  comments, checks, draft elevation — foreign activity included; the lane's own repeat attempt at
  the same still-unresolved blocker never re-qualifies), and no new escalation written —
  increments it, an idle cycle (no open PRs) — or one held by the rate-limit guard, meaning
  `rate_limit_latch` set, which starts no new mutating work and outlives the pause end — leaves it
  unchanged, and any qualifying progress resets it. At the threshold (new `babysit_loop_no_progress_threshold` seam key, default 3) the
  lane raises a stall escalation through the existing escalation contract — a
  `Lane stall: babysit-loop` issue with the human-gated role label and the machine-marked
  escalation comment, at most one open at a time (author-matched) — and **keeps looping**: a
  stalled lane is a signal about the queue, not a reason to terminate. Shared counter semantics
  are owned by the loop-lane convention (§4, "No-progress detector", convention 5.0.0); the lane
  body holds them by citation and defines only the merge-lane progress events.

### Changed

- **`babysit-loop`'s detector binding moved to a progressive-disclosure spoke (#1648).** With this
  lane's share of #1650's escalation-record contract also landing in `SKILL.md`, the file crossed
  the 500-line hard cap. The merge-lane binding — qualifying progress, the `rate_limit_latch`
  held-cycle bar, the threshold key, and the stall-escalation shape — now lives in
  `skills/babysit-loop/reference/no-progress-detector.md`, cited from the cycle-shape step that
  updates the counter, matching the `pre-escalation-dispatch.md` spoke already beside it. The same
  pass dropped the closed inventory of every contract the convention owns (it coupled this file to
  the convention's table of contents) in favor of the three rules that bite hardest here, and
  trimmed the pre-escalation paragraph to what its own spoke does not already own. No contract
  changes.

## [0.35.1]

### Fixed

- **`worktree-create.sh --base-ref fresh` degraded to local `HEAD` in a clone with no `origin`
  remote (melodic-software/claude-code-plugins#904).** The helper probed `refs/remotes/origin/HEAD`
  and nothing else, so a repository cloned with `git clone -o upstream` — which has no `origin` at
  all — took the remoteless fallback path even though `upstream/HEAD` was correctly cached. A
  worktree created from a feature branch then carried unpushed local commits into a base that
  `fresh` promises is the remote default branch. The fallback did emit its warning, so the failure
  was visible rather than silent — but the warning named `origin`, the one remote the repository did
  not have, so it read as a misconfiguration rather than as the helper looking in the wrong place.
  - `fresh` now resolves the effective default **remote** before probing any symref, through a
    three-rung chain: the current branch's configured remote (`branch.<name>.remote`), then `origin`
    when it exists, then the sole remote when the repository has exactly one. The resolved remote's
    `HEAD` symref supplies the base. Nothing hardcodes a default branch name — resolution stays
    symbolic, as the portability lint requires.
  - Rung 1 also changes the base in a repository that *does* have `origin`: when the current branch's
    `branch.<name>.remote` names a different existing remote, `fresh` now bases on that remote's
    default branch rather than `origin`'s. That is the prescribed precedence, but it is a behavior
    change beyond the non-`origin`-clone case in the headline.
  - Rung 1 accepts a configured remote only when it names a remote that still exists, so stale
    config cannot shadow a healthy `origin`, and it rejects git's `.` sentinel (which means "tracks a
    local branch", not a remote — `refs/remotes/./HEAD` is nonsense). A detached `HEAD` has no
    branch, so the rung is skipped rather than erroring.
  - That existence probe passes the configured name after an option terminator
    (`git remote get-url -- "$cfg"`). A remote name may legally begin with `-` — `git clone -o -foo
    <url>` creates one and writes it straight into `branch.<name>.remote` — and without the
    terminator `git remote get-url` parses it as switches (`unknown switch 'f'`). Rung 1 then
    rejected a perfectly healthy remote and resolution fell through to `origin`, producing exactly
    the silently wrong base this release exists to prevent.
  - The `HEAD` probe deliberately does **not** cascade back down the rungs. `fresh` means the
    *effective* remote's default branch; quietly substituting a different remote's default branch is
    a worse failure than the fallback, because the caller cannot see it happen.
  - The local-`HEAD` fallback and its loud warning remain for the genuinely unresolvable cases, and
    the warning now names the cause: the resolved remote whose `HEAD` is uncached (with the
    `git remote set-head <remote> --auto` fix), or the absence of any default remote — no remotes at
    all, or several with neither a branch-configured remote nor an `origin`.
  - Every git read in the resolver is `tr -d '\r'`-trimmed: under `git.exe` on an MSYS or Cygwin
    shell the output carries CRLF, and an untrimmed `upstream\r` would make each downstream lookup
    miss while still reading correctly in an error message.
  - This closes a gap the helper shared with Claude Code's own native `fresh`, which
    [keeps `origin/HEAD` current](https://code.claude.com/docs/en/worktrees#choose-the-base-branch)
    and falls back to local `HEAD` when `origin/HEAD` is absent. The plugin helper is now
    deliberately more general than the native behavior it otherwise mirrors.
  - Regression tests cover a sole non-`origin` remote, branch-config precedence over a coexisting
    `origin` (asserted against three distinct commits so it cannot pass vacuously), a stale
    branch-configured remote, the `.` sentinel, a detached `HEAD`, several remotes with no resolvable
    default, the remoteless case, and an option-shaped branch-configured remote coexisting with
    `origin`. The test fixture gained `--remote-name` plus helpers for seeding a second remote at a
    distinguishable tip; both fixture helpers now add remotes with `--` so an option-shaped name is
    constructible at all.

## [0.35.0]

### Added

- **`babysit-loop` escalation record write — deterministic surface for out-of-band notification
  (#1650).** Escalating now also creates
  `.claude/lane-escalations/<UTC-stamp>-<item>-babysit-loop.json` with the Write tool in the same
  step that files the tracker escalation, immediately before posting the marker comment — one new
  file per NEWLY filed escalation (suppressed by the marker read the step already performs),
  `loop-lane/escalation-record@1`
  shape, summary restating only the already-public marker-comment text. The Write tool call (never
  a shell redirect, whose `Bash` event the seam's `Write` matcher never sees) is what a consuming
  repo's `PostToolUse`
  `type:"http"` hook keys on to reach an off-machine human deterministically; the documented seam
  and settings shape are owned by the loop-lane convention (§2, v4.0.0). Record-before-marker is
  load-bearing: a stop between the two non-atomic writes then costs one duplicate notification the
  next cycle re-files, where the reverse order strands a standing marker that suppresses the record
  on every later cycle and loses the notification permanently. Without a configured hook the file
  is inert exhaust; the tracker item stays the escalation of record. Because the record path is
  relative to the lane session's own checkout, a lane scoped to a repository other than its
  checkout notifies the launching project's endpoint and never the target's — so launching from
  the target's checkout is stated at the site as a requirement whenever that repository's endpoint
  is the one that must hear, not a preference.

### Changed

- **`babysit-loop` gains a lane-start preflight that ignores the escalation record directory itself
  (#1650).** The record write is unconditional, so an unignored `.claude/lane-escalations/` would
  strand an untracked file per escalation in the tree this lane runs its gates against — and
  nothing delivers a tracked ignore rule into a consuming repo, so an existing consumer that
  upgrades would hit exactly that. New cycle-shape step 0 runs once per lane: if
  `git check-ignore -q` reports the path unignored, append it to the clone's untracked
  `$(git rev-parse --git-common-dir)/info/exclude`; skipped outside a git checkout, which the
  neutral-directory launch mode allows. No consumer change, no tracked file touched, and a no-op
  wherever the repo's own `.gitignore` already carries the rule.

## [0.34.1]

### Fixed

- **A worker's own reply to a bot review thread could strand it outside every resolution scope
  forever (#1729).** `babysit_resolve_thread.py`'s `project_thread` inspects EVERY fetched
  comment for `botOnly`, not just the opener, so a bot-started thread carrying a later human reply
  is correctly excluded from the default bot-only scope. But the worker's own documented reply to a
  bot thread -- a classification reply, a `Fixed in <sha>` follow-up (`reference/orchestration.md`)
  -- is a real API comment too, posted under the worker's own login, not the bot's. Before this
  fix that reply was indistinguishable from a genuine third-party human joining the thread:
  `botOnly` flipped `false` the moment it posted, which locked the thread out of the default
  bot-only scope, and `--include-human` stays unset by design in worker/safe modes (it must never
  touch a genuine human thread) so nothing lifted it back in -- a bot thread the worker correctly
  replied to became permanently unresolvable by the normal flow, even though replying was exactly
  the right action.
  - `babysit_resolve_thread.py` gains a `--self-logins` flag (`@me` plus `babysit_self_logins`
    extras, mirroring `babysit_merge.py`'s existing flag of the same name and the
    `babysit_self_logins` userConfig key, which was never threaded through this script).
    `project_thread`'s `botOnly` now treats a self-login-authored comment as a third admissible
    authorship alongside bot and third-party human, admissible as a REPLY only: it does not
    disqualify a bot-opened thread (unlike a genuine human reply), but neither can it open one.
    `botOnly` requires the thread's OPENING comment to be bot-authored, which is what
    `reference/review-discipline.md` D7.5 actually scopes resolution to ("resolve ONLY threads
    whose OPENING comment is authored by a BOT reviewer... NEVER resolve your OWN threads") and
    the same opening-author test `humanThreadsActed` has applied since #512. Neutralizing self
    authorship against a weaker "some participant is a bot" test would have opened the converse
    hole -- a SELF-OPENED thread would become `botOnly` the moment a bot replied to it, making the
    caller's own thread resolvable with no `--include-human` and, once outdated, under
    `--autonomous`. `botOnly` fails closed when the opening comment cannot be attributed at all
    (no fetched comments, or an opener whose author the API withheld), as it already did on a
    truncated comment page. `--self-logins` is resolved after the owner-scope refusal, mirroring
    `babysit_merge.py`'s ordering, so an out-of-scope owner still refuses with no `gh` invocation
    for `@me` resolution.
  - Fixing `botOnly` alone was not sufficient: the mandated classification-reply table
    (`reference/review-discipline.md`) restates the source finding's own severity marker (e.g. a
    `CRITICAL`/`P1` column, or "VALID -- not a security concern") as part of the worker's own
    reply, so a raw severity scan over that self-reply would re-trip `--autonomous`'s
    `skipped-severity-marked` guard the moment `botOnly` stopped blocking it -- the stranding just
    moved to a different verdict. `project_thread`'s severity scan now strips a self-authored
    comment's classification-table rows (not its whole body) before scanning, mirroring
    `babysit_classify.count_findings`'s identical rule for the finding-count gate; the underlying
    `_strip_classification_rows` helper is promoted to public (`strip_classification_rows`) and
    shared between the two modules rather than reimplemented. Non-table self content -- a
    maintainer using a self-login to raise a genuine new finding -- still flags.
  - `SKILL.md`'s thread-resolution bullet and flag-delivery table, `reference/safety.md`'s
    documented resolve-thread command forms (both the read-only listing form and both
    pinned-command-degradation forms), and `reference/orchestration.md`'s Worker Contract and
    Worker Prompt Template now carry `--self-logins @me,<self-logins>` alongside
    `--extra-bot-logins`, so every copyable resolve-thread command actually threads the caller's
    own identity through. `plugin.json`'s `babysit_self_logins` description now names the
    resolve-thread bot-only test among the surfaces the self set covers.

## [0.34.0]

### Changed

- **`babysit-loop`'s rung partition reads the work class from the `work-class:` label only, never
  from a `Work-class: C<n>` body trailer (#1657).** The partition accepted "the triage stamp in the
  item body **or** labels", so a class recorded in an item body decided merge eligibility. The class
  widens merge authority, and an item body is editable by its own author — who need hold no
  permission on the base repository — which made the item self-certifying and contradicted the
  autonomy plugin's admission policy: "No repo-local (agent-writable) surface may supply any
  admission input — rules, caps, or the work class used for admission." Applying a label takes
  triage or write permission, the same permission surface the C5 trust test already keys on.
  - A trailer stays legitimate as the operator's own record of a class and as a proposal, and is
    reported as such, but it never partitions. An item classified only in its body is
    **unclassified** for the partition — not eligible at any rung, exactly as an item with no
    record at all.
  - **Consumer impact.** A repository that recorded classes only as body trailers had a
    merge-eligible population under the old reading and has an empty one under this reading:
    everything there is human-merge, the shipped baseline, until the `work-class:` labels follow
    the trailers. Nothing merges that would not have merged before.
  - The C4/C5 floor is unchanged — it always tested the pull request rather than the linked item's
    stamp, so a fork PR was never eligible through a self-stamped issue.

## [0.33.3]

### Fixed

- **A configured review reviewer that GitHub types as `User` counted as no reviewer at all
  (melodic-software/claude-code-plugins#1642).** `is_review_bot_item` in
  `babysit_review_trigger.py` admitted an item only when GitHub's authoritative actor type said
  `Bot`, so an automation account posting as an ordinary user — no `[bot]` login suffix,
  `__typename` of `User` — had its real, current-head review read as no review. That is the exact
  account class `babysit_extra_bot_logins` exists for and that `actor_kind` and
  `babysit_resolve_thread.py` (#637) already honor, so the same operator-declared account was
  classified two different ways by two consumers of one plugin.
  - `ReviewTriggerConfig` gains `extra_bot_logins`, and the predicate now reads: the login must be
    in `reviewer_logins` AND the author must be a bot. Both halves are required, so declaring an
    account a bot never promotes it to reviewer. The field ships empty, so the predicate is
    structural-only exactly as before for anyone who has not configured it, and no
    default-configuration blocker state moves.
  - Bot-ness is delegated whole to `is_bot` rather than restated, so this module can no longer
    drift from the classification every other consumer uses. The REST `type` key is normalized
    into the `__typename` slot first — `is_bot` reads `__typename` alone, and the reaction and
    review-comment paths carry only `type`, so that normalization is load-bearing and pinned.
  - The widening is applied at the shared predicate rather than per consumer, so all three reach
    the same verdict: review evidence (`fetch_review_evidence`), current-head completion
    (`has_current_head_review`), and reaction engagement (`fetch_review_reactions`). It is not
    uniformly permissive — recognizing a declared reviewer's eyes reaction *adds* the
    `engaged_reaction_reviewing` blocker that strictness was suppressing.
  - `--extra-bot-logins` now threads into the review-trigger config from `pr_queue_snapshot.py`
    (which already parsed it for `FeedbackConfig`) and from `request_review.py`, which gains the
    flag; `SKILL.md`'s delivery mapping and `reference/review-trigger.md`'s pinned invocation and
    completion rule follow.

## [0.33.2]

### Fixed

- **Every git-bearing skill in this plugin was uninvocable from a worktree-isolated agent
  (melodic-software/claude-code-plugins#1619).** The harness composes an entire
  `## Pre-computed context` block into ONE shell invocation, and the worktree-isolation Bash guard
  refuses a git-bearing compound command it cannot statically verify — so `commit`, `pull-request`,
  `worktree`, `resolve-conflicts`, and `babysit-prs` all failed at load with `this command is too
  complex to verify that it stays inside the worktree`. `worktree` is the sharpest case: the skill
  for managing worktrees could not be invoked from inside one.
  - The git lines are removed from each skill's pre-compute block and re-acquired in the skill body
    as **individual** Bash calls, one command per call. Non-git pre-compute lines are untouched —
    `commit` keeps its exec-bit and user-global config probes, `babysit-prs` keeps both `gh` lines.
  - `commit`'s two repo-scoped config-layer probes were themselves compound one-liners that
    re-derived the repository root inline. They are rebuilt on git's repo-root-relative magic
    pathspec `:/` rather than on a substituted root — `git ls-files --error-unmatch --` and
    `git ls-files --cached --others --`, each given `":/.claude/source-control.md"` (or the
    `.local.md` overlay). Nothing is substituted, so a repository root containing a space, `$(…)`,
    a backtick, or a double quote can neither break the command nor inject into it; double-quoting
    a substituted root does *not* neutralize a command substitution, which is why quoting was the
    wrong fix. Verified from a subdirectory: `:/` resolves against the working-tree root regardless
    of the session's cwd, and the same existence probe replaces the personal overlay's old
    `test -f "<root>/…"`.
  - `commit`'s team layer keeps all three of its states — `present (tracked)`,
    `present but UNTRACKED`, `absent` — which a single `--error-unmatch` call cannot express, since
    it exits nonzero for both of the last two. The `git ls-files --cached --others` existence probe
    separates them (`--exclude-standard` deliberately omitted so a gitignored file is still seen),
    and the generic unknown-value rule is narrowed so it no longer swallows the distinction: a
    nonzero `--error-unmatch` exit is a *result*, and only a probe that could not run at all (git
    unavailable, not a repository) is an unknown value.
  - `babysit-prs` is held at exactly 499 lines — the change is net-zero on line count, so it does
    not consume the one line it has left under the 500-line hard cap (see #1626).
  - The pre-compute lines carried `2>/dev/null || echo "unknown"` fallbacks **and** output caps
    (`git status --short | head -20`, `git diff --cached --stat | tail -1`,
    `git worktree list | head -30`, `git status | head -4`). The fallbacks are restated as a reading
    rule — a failed command means "unknown, carry on". The caps are **kept as pipes** on the body
    commands in `commit`, `worktree`, and `resolve-conflicts`. An earlier revision of this change
    restated them as read-time prose ("read at most the first 20 entries"); that bounded nothing,
    because the Bash tool returns a command's complete output into context before there is anything
    to decide about. A real bound beats a fictional one.
  - What was verified, precisely: from an `Agent` with `isolation: "worktree"`, the **unfixed**
    skills were observed to be refused, plain git commands were observed to succeed as individual
    Bash calls, and a multi-line non-git pre-compute block was observed to load. The restored pipes
    (`git status --short | head -20`, `git diff --cached --stat | tail -1`) were observed to pass as
    ordinary body Bash calls in a **non-isolated** session; whether a pipe also clears the isolation
    guard as a body call is not verified here. The **edited** skills have not been invoked from an
    isolated agent — skills load from the version-keyed plugin cache, so `0.33.2` does not exist
    there until this ships. Confirm then; CI cannot prove it.
  - `shell: bash` is deliberately left in place on every affected skill, including the three that
    now have no `!` lines at all. The key is inert without pre-compute lines, and removing it is a
    frontmatter-contract change with no behavioral benefit.

### Changed

- **Two reference spokes described the moved commands as pre-computed and are corrected.**
  `commit/reference/exec-bit.md` no longer calls the config-layer probes pre-computed, and
  `pull-request/reference/create.md`'s `--pushed` section is regrounded: it still says to ignore the
  session-cwd context for an out-of-tree orchestrator, but its stated reason — that a
  `!`-substituted line cannot be `git -C`-redirected — stopped being true once those became ordinary
  Bash calls. The instruction to re-resolve explicitly from the target worktree is unchanged.

## [0.33.1]

### Fixed

- **`babysit-loop` no longer downgrades the whole rate-limit guard because one window is absurd
  (#1612).** The lane body inlined the reader contract's mode table — "tee file absent, stale, missing
  `rate_limits`, or absurd values → mode unknown → reactive-only" — which collapses the guard wholesale
  as soon as any single value is absurd. Against the floor's "pause when **either** window reports
  `used_percentage >= 90`", a lane holding one garbage window and one valid window at 95% kept claiming
  PRs until a reactive rate-limit failure landed, rather than pausing on the window it could still
  trust. The inlined rule now classifies validity per window: tee file absent, stale, or missing
  `rate_limits` is still a whole-guard downgrade; an absurd `used_percentage` or `resets_at` makes only
  that window unknown; the floor keeps applying to every still-plausible window; and reactive-only is
  reached only when no window is plausible. The rule stays byte-identical across all three lane bodies
  (the others are `work-items`' `work-loop` and `attend-queue`). The operable floor's values are
  unchanged.

## [0.33.0]

### Added

- **`/commit` ships a deterministic exec-bit backstop (#1579).** The skill's ordered exec-bit
  procedure was advisory prose with no tier under it, and prose is what a long session stops
  executing: four new shebang scripts once shipped `100644` with only the consuming repo's CI
  catching it. Two tiers now sit under it. A pre-computed probe line at the TOP of the skill —
  inside the documented 5,000-token compaction re-attach window — reports staged newly-added shebang
  files still at `100644`; and `skills/commit/scripts/exec-bit-check.sh` (`--list` / `--probe` /
  `--fix`, with a 47-case `.test.sh`) makes the per-commit step a command with an exit code. Both,
  because the probe is only a snapshot at invocation and cannot see files staged later in the flow.

  Hardened in review before merge, all found by the PR reviewer on #1590:

  - **Every mode anchors at the repository root.** `git diff --cached --name-status` emits
    repo-root-relative paths while a `git ls-files` pathspec resolves against the cwd; run from a
    subdirectory those disagreed, every lookup missed, and the check reported no offenders even when
    they existed — a fail-open backstop. Caller pathspecs are re-anchored via `--show-prefix` before
    the directory change so a scoped `--fix` from a subdirectory still matches. The skill's
    config-layer probes anchor the same way, matching the root-resolution rule
    `reference/config-resolution.md` already states; unanchored, a session started in a
    subdirectory silently dropped the team convention and `trailer_policy`.
  - **A worktree symlink over a staged regular file is refused, not chmod-ed.** `-e` follows a
    symlink, so an unguarded `chmod +x` would have made the link's target executable — a file that
    can sit entirely outside the repository. The `-L` test now runs before `-e`.
  - **The exec bit does not survive a pathspec (`--only`) commit under `core.filemode=false`, and
    that is now documented as a hard constraint** rather than silently losing the fix. `--only`
    records the working-tree mode, and with filemode off git cannot see the `chmod +x`, so a
    correctly-set `100755` index entry is rebuilt as `100644`. Verified both directions on a fixture:
    plain index commit preserves `100755`, pathspec commit loses it. Two candidate workarounds were
    tested and **both failed** on that platform — `-c core.fileMode=true` on the commit, and a
    post-commit `update-index` plus `--amend --only` — so neither is offered. The guidance is
    instead to commit an exec-bit-corrected path with the plain index form (splitting the commit if
    the rest needs a pathspec) and to confirm with `git ls-tree HEAD`, never the index. Both
    behaviors are pinned as characterization tests so a future git change fails loudly.
  - **`--list0`** (NUL-delimited) added for pathnames containing a newline, which would otherwise
    break `--list`'s one-record-per-line contract; `--list` and `--probe` shell-quote such a path so
    the ambiguity is visible rather than silent.

  `--fix` **requires an explicit scope** — `-- <path>...` or a deliberate `--all` — and exits 2
  otherwise, changing nothing. It mutates index entries, and the staged set can hold a concurrent
  session's work (the whole premise of the pathspec-limited commit form), so an unscoped default
  would have inverted this skill's own surgical-staging discipline. `--list` and `--probe` stay
  unscoped because they only read; the asymmetry is deliberate.

  A new cross-platform hazard was found and pinned while implementing this: under
  `core.filemode=false` — **the default on Windows/NTFS** — git ignores worktree permission bits
  entirely and stages every file `100644`, so `chmod +x` alone NEVER reaches the index and
  `git update-index --chmod=+x` is the only thing that can produce a `100755` entry. The script
  always performs both writes, and the test suite pins the case with `core.filemode` set explicitly
  so it tests the same thing on every platform. Demonstrated live: this change's own two new scripts
  staged at `100644` despite `chmod +x`, and the new check caught them pre-commit.

- **A per-commit checklist at the top of the hub (#1583)**, as the cheap re-anchor for a session
  that has drifted — seven numbered steps, stated as commands rather than facts to recall.

- **Pre-computed probes of all three config layers (#1583).** A skipped resolution was previously
  invisible. The tracked-team probe tests **tracked-ness** via `git ls-files --error-unmatch`, not
  file existence, and reports an untracked file at that path as `present but UNTRACKED — not a
  config layer` — preserving the rule 0.25.1 established, rather than reintroducing it as a
  drafting-surface bug.

### Changed

- **The `Co-Authored-By` context clause is now OPTIONAL, and the harness is named in the ladder
  (#1581).** The default template mandated `(<context>)`; a census of this repo found compliance not
  merely low but collapsing — 41.6% of trailers carry the clause over the last 150 commits, 12.1%
  over the last 40. A mandate nobody follows is worse than no mandate, so the default is now the
  context-free form with the clause as an optional addition.

  The ladder also gains the rung it never had. Harness-injected commit guidance is neither a config
  layer nor a project convention, so a session receiving both it and this skill had no stated
  tiebreak. It is now rung 3, with an explicit rule: adopt its **shape**, never its **literal text**.
  Observed first-hand — that injected guidance can carry a **hardcoded model name that does not match
  the running session** (a `Fable 5` trailer injected into an Opus 5 session), and copying it verbatim
  writes a false provenance claim into durable git history, which is precisely the harm the template
  exists to prevent.

  The originating audit's "62 of 74 trailers" figure does **not** reproduce on any window of this
  branch (at the window where the total is 74, the non-compliant count is 49); the figures were
  wrong, the direction right, the trend worse than claimed. Its suggestion to "have setup write an
  explicit `trailer_policy`" is **refuted as already-done** — `trailer_policy` is a documented key
  and `/source-control:setup` already interviews for and writes it.

- **Composition is now two named forms, and "remembered convention" is neither (#1583).** "Compose by
  natural-language reference" was ambiguous between re-invoking `/commit` and following an absorbed
  convention from memory. A composing skill must now name which it is doing: re-invoke, or run the
  per-commit checklist itself as commands. The policy also names *what* decays — not the message
  shape, which is reinforced visibly every commit, but the ordered per-commit checks, which produce
  no signal when skipped.

- **The hub is split into `reference/` spokes with load-when pointers (#1583).** Auto-compaction
  re-attaches only the first 5,000 tokens of each invoked skill
  (<https://code.claude.com/docs/en/skills>, "Skill content lifecycle", fetched 2026-07-26), and the
  hub was spending that window on ~130 lines of pathspec/hide-restore and format-check edge
  machinery while the per-commit checks sat in the tail that gets dropped first. Four spokes now
  carry the depth — `reference/format-check.md`, `reference/exec-bit.md`,
  `reference/pathspec-commits.md`, `reference/staging-preconditions.md` — and the hub leads with the
  checklist, staging rules, and commit mechanic. No rule was dropped; the staging preconditions keep
  their detection command and action inline as a table, with only the per-condition rationale moved.

- **`disable-model-invocation: false` is now declared explicitly, with the deviation recorded
  (#1584).** Same effective behavior as the omitted default, but the choice is visible. A
  `/commit`-shaped skill is the canonical archetype for `disable-model-invocation: true`, and every
  other skill in this plugin declares the field; this one deviates deliberately because its
  composition design requires the model to be able to reach it. The skill body now records the
  deviation, the reason, and the compensating controls.

## [0.32.1]

### Fixed

- **`source-control-babysit-merge`'s `--allow-unpinned-head` guard now strips an `=value` tail
  before the prefix comparison (#1522).** The guard refuses the flag and every long-option prefix
  of it via `"--allow-unpinned-head" == "$arg"*`, but `--allow-unpinned-head=true` is not itself a
  prefix of `--allow-unpinned-head` — the `=true` suffix broke the match, so the wrapper let the
  argument through and argparse rejected it instead (the flag is `store_true`, which never accepts
  an explicit argument). The refusal was still real today, but incidentally so: it depended on the
  interpreter behind the wrapper exactly as this guard exists to not do — the moment the guarded
  flag (or an equivalent guarded flag) accepted a value, the same test would have stopped refusing
  anything, silently. Fixed by stemming each argument on its first `=` before the prefix test.
  `engine.test.sh` gains a `check_wrapper_refusal` helper that asserts the wrapper's own refusal
  text on stderr (not just exit code — exit 2 is shared between the wrapper's refusal and
  argparse's own usage/rejection errors, so an exit-code-only assertion would have passed before
  and after this fix for different reasons) and new rows for `--allow-unpinned-head=true`,
  `--allow-unpinned=1`, and `--allow-unpinned-hea=1`, plus no-over-refusal rows for
  `--allow-dependency`, `--allow-unprotected`, and `--allowed-owners=owner`.

## [0.32.0]

### Added

- **`babysit-loop` gains the loop-lane convention's one named, explicit paired-argument merge-rung
  exception (#1309).** Standing merge-rung raises still bind from the team-tracked seam layer only.
  The exception: an invocation whose own argument line types both the literal `autopilot` tier
  keyword and the dedicated raise argument `--merge c3-this-run` — each never inherited from
  `babysit_loop_tier`, never defaulted, never supplied by a config layer, never model-composed on
  the caller's behalf; the raise token exists for this exception alone, so a saved invocation or
  template carrying the merge-inert `autopilot` tier keyword alone acquires no merge authority —
  widens *that single invocation's* merge dimension up to and including C3, in a repository
  that has already adopted the baseline rung. It persists nothing, ratifies nothing, and is not a
  substitute for the recorded `c3-autonomous` seam flip. A merge-eligible PR blocked on a
  `needs-human` label, an open finding, or a contradictory thread gets one fresh frontier-tier
  subagent — sharing no conversation context with whatever produced or previously reviewed the PR —
  dispatched to resolve that blocker through `babysit-prs`'s guarded-mutation path before the
  deterministic gate runs; the gate itself is never bypassed or weakened, and an unresolved or
  uncertain blocker still escalates. `babysit-prs`'s "escalate security/P1 even in autopilot" rule
  carries a matching named exception for that one dispatch path only. Tracks loop-lane convention
  3.0.0.
- **The widening lifts only the raise restriction.** Every merge-dimension argument value other
  than `c3-this-run` still only selects a *lower* rung, so `autopilot --merge human-only` merges
  nothing; the order is tracked rung → the paired raise → the C4/C5 ceiling.
- **The C4/C5 floor reads the pull request, not the linked item's stamp.** `work-classes.md` assigns
  a class from the risk-property bundle, "not the task's surface description". C5 is two executable
  snapshot tests, either marking C5 and each failing closed when its field is unavailable: a
  cross-repository head (`isCrossRepository` / `headRepositoryOwner`), or an `authorAssociation`
  other than `OWNER`/`MEMBER` — catching the outside collaborator whose base-repository branch
  passes the fork test while still being an external contribution. A fork PR closing an internally
  classified C2/C3 issue is still C5; the partition never tests the author
  login against `babysit_watched_owners`, which is a repository-owner allowlist rather than a
  trusted-author list and would call every internally authored PR on an org-owned repo C5. C4
  follows the diff's blast radius: a refactor, migration, or contract change is C4 however its item
  is stamped, and a PR whose shape no longer matches its recorded class fails closed to escalation.
- **Human blocking feedback, operator-parked items, and merge conflicts stay outside the dispatch —
  and outside the merge-capable set.** A human `CHANGES_REQUESTED` review, explicit human blocking
  language, or an unresolved inline
  human thread remains a stop-and-ask condition per `reference/feedback.md`'s "Human Feedback" — the
  exception does not amend it, no dispatch is made, and the rung partition withholds the PR from
  the merge-capable set entirely (routed to `safe`), because a merge-capable tier's own runbook
  widens thread scope to human threads and the base merge gate does not inspect ordinary human
  blocking comments. An item wearing the `needs-human` role label
  without the machine escalation marker is operator-*parked*, belongs to the attended queue, never
  draws a dispatch on the label alone, and its PR is likewise withheld from the merge-capable set —
  the merge gate does not inspect the linked item's labels. Conflicts route to the dedicated
  merge-only conflict
  worker; the dispatch never rebases a PR branch, which would need the force-push forbidden
  cross-tier.
- **Edit-capable resolution runs the per-PR worker lifecycle, and the partition reruns after it.**
  A blocker needing a code change gets the isolated PR worktree, the HEAD assertion at the live PR
  head, and the commit/refspec push `reference/safety.md` requires — the guarded wrappers implement
  merge and thread resolution and create no worktree, which a lane launched from a neutral directory
  has no substitute for. After any resolver mutation the PR is re-snapshotted and step 3's
  provenance, C4-diff, and rung partition rerun before the merge-capable invocation, so a resolution
  that expanded a C2/C3 change into a refactor or contract change leaves the eligible set rather
  than merging under a stale classification.
- **Partition eligibility is pinned to the head SHA it examined — for every push, not only the
  resolver's.** The merge-capable invocation carries the partitioned head as its merge gate's
  `--expected-head`; a normal worker fix-push (babysit-prs Autopilot steps 1–2) moves the head off
  the pin, the pinned gate's head-match refusal blocks the merge deterministically, and the
  invocation reports the new head instead of re-pinning (babysit-prs gains the matching named
  "Lane-pinned merge authorization" exception in `reference/safety.md`). The lane reruns the
  partition on the post-push head and only a still-eligible PR gets a fresh merge-capable
  invocation pinned to it — no head merges that the partition did not class-check.
- **The widening lasts the invocation that typed it, not one cycle.** Every `/loop` wakeup
  re-invokes the same prompt in the same session and carries the same explicit authorization, so the
  rung does not silently drop after the first cycle and no operator input is awaited that a loop
  cannot supply. It ends when a newly launched invocation omits either token of the pair.
- **The dispatch is leased and its tier is resolved, not named.** It acquires, heartbeats, and
  releases the PR's own worker lease around itself — the guarded-mutation wrappers pin comment
  state, they do not confer concurrency ownership — and a lease another worker holds means no
  dispatch. Its capability tier is requested as the convention's §3 frontier row and resolved to a
  live-updating model alias by that section's runtime-resolution rule, rather than a `fable`/`opus`
  family alias written into the lane as the tier's definition; a run that cannot establish which
  alias currently satisfies `frontier` escalates instead of dispatching, because inheriting the
  session's model would forfeit the capability the dispatch stands on.
- **C4/C5 floor stated as unconditional across the merge surface.** No rung, no seam config, and no
  invocation argument — including this exception and including `full-autonomy` — ever grants merge
  authority over a `work-class: structural` (C4) or `work-class: untrusted-provenance` (C5) item.
  This was already the autonomy matrix's promotion contract ("never promotes"); `babysit-loop`,
  `reference/config-resolution.md`, and the convention now say so explicitly rather than leaving it
  to be inferred from a rung name.

## [0.31.8]

### Fixed

- **`prune_babysit_worktrees.py` hardened against orphaned worktree state (#816).** Two related gaps
  observed at queue-start prune: (1) a worktree directory left behind by a lock-blocked
  `git worktree remove` (its administrative record dropped, the directory itself surviving — most
  commonly on Windows) made every subsequent prune run error `fatal: not a git repository` on that
  entry instead of self-healing; (2) the lock-blocked removal itself silently left the residual
  directory with no signal. `git_status` failures now distinguish "this path is no longer a valid git
  repository" (`is_missing_repo_error`) from every other failure: an orphaned entry drops its stale
  worker-lease record (the lease-only case with no matching directory stays `manage_babysit_lease.py
  reap`'s job, unchanged) and removes the residual directory only when it is empty
  (`drop_orphaned_worktree` / `remove_empty_orphan_directory`, root-contained, never touching an
  orphan's contents since git never confirmed it safe to discard), reported via a new
  `drop_orphan` row action rather than flipping the run's exit code. Self-healing is gated on
  `--apply` like every other mutation the script performs — the flagless run stays the documented
  always-safe report, naming the orphan with `dropped: false` and leaving it on disk.
  `remove_worktree` now
  verifies the directory actually left disk after a *successful* `git worktree remove`
  (`attempt_directory_removal`, safe to fully delete since git already confirmed removability) and
  reports a still-locked directory via `residual_directory` plus a stderr warning instead of leaving
  a silent orphan for a future run to stumble over. The stale-lease drop is scoped to leases that are
  actually stale: when `--lease-token` matched the caller's own unexpired hold, the record survives
  the orphan cleanup (`preserve_lease`), because the documented scoped form prunes while that lease
  is still held and releases it in the next step (`reference/orchestration.md` "Cleanup") — unlinking
  it here turned a successful cleanup into a `lease does not exist` release failure and dropped
  ownership early. Orphan detection no longer rests on `fatal: not a git repository` alone: `git -C
  <path>` runs *as if git had started in that directory*
  ([git-scm.com](https://git-scm.com/docs/git#Documentation/git.txt--Cltpathgt)), so when the
  worktree root itself sits inside another checkout, ordinary upward discovery answers `git status`
  from that ancestor and the orphan reads as healthy — an open PR's entry then sticks as `keep_open`
  and a closed one errors in `git worktree remove`, leaving the directory forever.
  `is_orphaned_entry` compares `rev-parse --show-toplevel` against the candidate path, so an
  ancestor's answer is an orphan too. A non-empty orphan — never force-deleted, since git never
  confirmed its contents safe to discard — is now reported `dropped: false` with
  `residual_directory: true` and a stderr warning rather than claiming a cleanup that did not
  happen at a deterministic path where a replacement worktree still cannot be created.
  - **A removed orphan directory no longer implies a reusable path.** When an entry orphans because
    its `.git` pointer was corrupted, the owning repository still holds the
    `$GIT_DIR/worktrees/<name>` record, so a later `git worktree add` at the same deterministic path
    fails with "missing but already registered" — a directory removal alone was never the self-heal
    it reported. Each dropped orphan now carries `registration_pruned`: `pruned` when the entry's own
    `gitdir:` pointer named its repository and the record was cleared there,
    `skipped` while the directory survives, and `unresolved` when the pointer is gone. Recovering
    ownership is the only thing that clears the uncertainty — an ancestor checkout answering for the
    path proves nothing, because a real linked worktree nested under another checkout resolves to
    that ancestor once its pointer is lost while its owning repository still holds a prunable record
    — so "never registered" and "registered, pointer gone" both stay `unresolved` rather than being
    assumed apart. Anything but `pruned` also sets `stale_registration` and warns on stderr naming
    `git worktree prune`. `dropped` keeps its existing directory-scoped meaning.
  - **A lone dangling `.git` gitfile no longer counts as directory contents.** The emptiness check
    that guards orphan removal treated the pointer file as user work, so the one orphan whose owner
    *is* knowable — pointer readable, contents gone — always reported `directory_removed: false` and
    never reached the prune, making the recoverable self-heal unreachable exactly where it works. A
    sole `.git` **file** is now unlinked as the bookkeeping it is; a `.git` **directory** is still
    never touched, since that is a standalone repository rather than a linked worktree's pointer.
    The pointer is **restored** when the subsequent `rmdir` fails — it is the only record of the
    owning repository, so discarding it on a lock would turn a retryable failure into a permanent
    `unresolved` for every later run.
  - **A bare-clone hub's registration is recoverable too.** The owning repository is derived from the
    record's own `worktrees/<name>` structure rather than from a `.git`-named ancestor, so a hub
    whose common directory is `hub.git` — a layout `repo_path` already supports — no longer resolves
    to nothing and goes unpruned.
  - **`pruned` is now verified, not inferred from the exit status.** `git worktree prune`
    deliberately keeps a **locked** record and still exits 0, so a locked orphan reported a completed
    repair while the path kept rejecting `git worktree add`. The verdict now comes from re-reading
    `git worktree list --porcelain` and confirming the entry is gone, comparing resolved paths (git
    prints POSIX separators and long filenames; the caller's path may carry native separators and a
    Windows 8.3 short name for the same directory).
  - **The registration cleanup is targeted, so a scoped run cannot drop an unrelated record.**
    `git worktree prune` takes no path and drops *every* prunable record in the repository, so a
    `--pr <one PR> --apply` cleanup also discarded the administrative record of any other worktree
    whose directory happened to be missing at that moment — an unmounted share, a removable drive, a
    checkout mid-restore — despite it being outside the requested scope. Reproduced on git
    2.55.0.windows.3: register two worktrees, delete both directories, prune on behalf of one, and
    both records vanish. The record is now cleared with `git worktree remove <path>`, which names its
    one target and behaves identically from a standard clone and a bare hub. Deliberate consequence:
    unrelated stale records are no longer swept up as a side effect — clearing those stays
    `git worktree prune`'s job, run by the operator or by `git gc`, not a decision a single-PR
    cleanup makes. The verification-by-`worktree list` rule above is what keeps the swap honest in
    both directions, since `remove` exits nonzero both for a locked record (correctly `failed`) and
    for a record that is already gone (correctly `pruned`). `--force` is never passed, and a
    still-present directory returns `skipped` rather than being handed to a command that — unlike
    `prune` — would delete its contents.
  - **A corrupted pointer is an orphan, not a hard error.** git answers a malformed `.git` with
    `fatal: invalid gitfile format`, not the missing-repository wording, so the detector re-raised
    and every run reported `action: error` for that entry instead of healing it — despite a
    corrupted pointer being one of the states this change exists to clear. The marker set now covers
    it (verified against git's actual C-locale output for a deleted, dangling, and malformed
    pointer) while still re-raising every unrelated git failure.
  - **Orphan detection no longer depends on the operator's locale.** `worktree_toplevel` recognized a
    missing repository by matching git's English `not a git repository` text. Git translates its
    diagnostics, so on a localized machine every orphan surfaced as an unrelated error and never
    reached the self-healing path. That probe now pins `LC_ALL=C` (and clears `LANGUAGE`, which
    outranks it for GNU gettext) through a new `env_overrides` parameter on the shared
    `run_command` seam, so the marker is only ever matched against output whose wording is
    guaranteed.

## [0.31.7]

### Fixed

- **`babysit-prs`'s one-verdict-per-run claim now scopes out the help form (#1434).**
  `reference/safety.md`'s Lane-Script Reachability section said `babysit-readiness-gate.sh` emits
  exactly one `READINESS_*` line on stdout on every run, failure paths included — but
  `skills/setup/SKILL.md`'s reachability canary runs the gate with `--help`, which prints usage and
  exits 0 with no verdict. That form was always the intended non-mutating canary target, and `#787`
  already carried this exemption in the script's own header; `safety.md`'s wording was never updated
  to say so, leaving a reader to treat the canary as a contract violation. Narrowed the claim to
  every run that attempts a check and named the help form as the stated exemption — both `--help`
  and its `-h` alias, which the script's argument parser handles in one branch, so naming only the
  long form would have left the identical short-form invocation reading as a contract violation.
  Documentation only; no script behavior change.

## [0.31.6]

### Fixed

- **`babysit-prs` states the bare-name wrapper situation accurately (`#843`).** `safety.md` asserted
  the bundled wrappers' bare names "are not on the Bash tool's `PATH`", and the two `bin/` wrapper
  headers presented their bare-command allow-rule rationale as operative fact. Both were wrong, in
  opposite directions. Two corrections, each tied to its source:
  - **Bare-name resolution is unreliable, not absent.** A local shell-snapshot survey recorded on
    `#843` found plugin `bin/` directories present on the Bash tool's `PATH` in some sessions and
    missing in others on the same machine, including sessions carrying this plugin's own `bin/`. The
    delivery path is the session snapshot's final `export PATH=` line; when it does not land, every
    enabled plugin's `bin/` goes with it
    ([anthropics/claude-code#68066](https://github.com/anthropics/claude-code/issues/68066), which
    reports the same signature on macOS/zsh and supplies the mechanism — the Windows/Git-Bash
    evidence is the local survey, not that issue). The earlier "never delivered here" reading came
    from sampling only sessions in which it was missing.
  - **A path invocation cannot match a bare-name allow rule.** Claude Code strips only a fixed
    wrapper set before matching Bash rules (`timeout`, `time`, `nice`, `nohup`, `stdbuf`, `command`,
    `builtin`, `noglob`, bare `xargs` — [permissions](https://code.claude.com/docs/en/permissions));
    `bash` is not among them. So `Bash(source-control-babysit-merge:*)` does not cover the
    `bash "…/bin/…"` form this skill uses, and what follows is the permission mode's call rather
    than a misconfiguration: a mode that prompts issues a per-call prompt, while
    [auto mode](https://code.claude.com/docs/en/permission-modes#eliminate-prompts-with-auto-mode)
    issues none — it routes the uncovered call to its classifier, which may approve or deny it
    silently, so an operator must read `/permissions` → **Recently denied** rather than wait for a
    prompt. `safety.md` also records that
    [`autoMode.classifyAllShell`](https://code.claude.com/docs/en/auto-mode-config#route-all-shell-commands-through-the-classifier)
    suspends even narrow shell allow rules while auto mode is active.

  Guidance is unchanged and was already correct: the `${CLAUDE_PLUGIN_ROOT}/bin/` path form is
  canonical because it is the only form that runs in both `PATH` states. Only the justification
  changed, and it mattered — a reader who checked on a session where the bare name *did* resolve
  found the doc contradicting their own shell, and the documented reason to keep the path form
  disappeared exactly when it looked safe to drop.

## [0.31.5]

### Fixed

- **A readiness-gate classification is now a table CELL that OPENS with a disposition, matched
  case-insensitively (#619).** Both the bash safe-tier degrade and the preferred Python classifier
  (`babysit_classify.py`) matched the classification tokens exact-case only, anywhere in a
  `|`-prefixed line. A worker reply that wrote a natural-language disposition like "Valid (defer)"
  instead of the mandated all-caps `VALID` scored as unclassified, so the gate reported
  `READINESS_BLOCKED reason=under-decomposed` even though the finding genuinely was classified.
  Matching is now case-insensitive, and the token must open a table cell, optionally followed by an
  annotation introduced by punctuation. That punctuation requirement is what separates the
  disposition values `reference/review-discipline.md` documents — `VALID — fixing`, `VALID (defer)`,
  `VALID — fix now` — from prose that merely starts with a disposition word. Scanning the whole line
  instead credited `| CI check | result is valid |`, and accepting a bare space before the
  annotation credited `| 2 | c2 | Valid cache entries are rejected | | |`; either miss lets an
  unclassified finding past the under-decomposition gate. The decoration allowed before the token
  and the character required after it exclude word characters rather than only letters, so `valid2`,
  `2valid` and `VALID_TOKEN` no longer satisfy the token, and "invalid"/"INVALID" still does not
  false-match "valid"/"VALID". One predicate drives both the classified count and the self-row
  exclusion that keeps a classification row's own severity word from re-counting as a phantom
  finding, so the two counts cannot drift apart. New convergence fixtures pin the bash degrade and
  the Python classifier to the same counts on a lowercase disposition, both prose false positives, a
  word-like continuation, and the documented annotated forms.

## [0.31.4]

### Fixed

- **Headless reconfigure recipe now preserves install scope (#1406).** The `claude plugin
  uninstall` → `claude plugin install ... --config` recipe in `skills/setup/SKILL.md` defaulted
  both halves to `-s user`. When this plugin is installed at `project` or `local` scope, that
  silently uninstalled a separate user-scope record while the effective project/local install kept
  loading, and the reinstall landed at a scope that does not load. Both commands now carry
  `-s <scope>`, sourced from what `claude plugin list` reports for this plugin — the same fix
  already applied to `session-flow` and `rate-limit-guard` in #1393.
  The recipe also now requires the reinstall to re-supply **every** key whose value should
  stay non-default, not only the key being changed: uninstalling drops the stored
  `pluginConfigs` entry, so an omitted key silently falls back to its manifest default.
  Record the current values before uninstalling.

## [0.31.3]

### Changed

- **`test_pr_queue_snapshot.py`'s Approve-with-nits integration test now pins the routing by
  elimination (#578).** The test asserted only that `blocking` and `material` were empty, which does
  not distinguish "routed to `ignored`" from "routed to a human bucket". It now also asserts
  `human_blocking` and `human` are empty; since `collect_feedback` places every record in exactly one
  bucket and `classify_pr` surfaces four, all four empty rules out every bucket the snapshot projects.
  Elimination alone still could not tell "routed to `ignored`" from "dropped before reaching any
  bucket", so the test now also calls `collect_feedback` directly on the same fixture — under the
  same `FeedbackConfig` `classify_pr` passes down — and asserts the record is in `ignored` carrying
  the `approval_verdict` downgrade marker, which pins the arrival branch rather than only the
  destination. #578 asked for a direct assertion on `feedback["ignored"]`: that holds at the
  `collect_feedback` layer, but not on the snapshot's `feedback` mapping, which deliberately does not
  project `ignored`. Test-only; no behavior change.

## [0.31.2]

### Fixed

- **`babysit-prs` worktree pruning no longer gives a false all-clear for a non-conforming directory
  name (#555).** `prune_babysit_worktrees.py` derives each worktree's PR identity from its directory
  name, and a directory that did not match `<owner>__<repo>__pr-<number>` was dropped before the
  report was built — not kept, not removed, not an error, simply absent. A caller reading the JSON to
  answer "is anything left to clean up?" saw an empty list while merged PRs' worktrees sat on disk,
  and had to find and `git worktree remove` them by hand. Every directory under `<worktree-root>` now
  appears in the report; an unmappable one is an explicit `action: unrecognized` row carrying its path
  and the reason, in every mode including `--pr` — an unrecognized entry has no key to match a target
  against, so leaving it to that filter would hide it from every scoped run (a recognized non-target
  worktree is out of the caller's declared scope and still appears in an unscoped run). Unrecognized
  entries are never removed — identity is a precondition for the PR-state and worker-lease checks
  that authorize removal — and do not fail the run. `reference/worktrees.md` now states the naming
  convention that was previously only implied by the helper's regex, plus what happens to a
  directory that breaks it.

## [0.31.1]

### Fixed

- **`babysit_resolve_thread.py`'s two `is_bot` call sites now thread `extra_bot_logins` through
  (#637).** The bot-only classifier (`project_thread`'s `botOnly` computation) and the
  `humanThreadsActed` reporting counter both called the shared `is_bot` without the caller's
  `extra_bot_logins` config, unlike every other classifier call site (e.g. `actor_kind` in
  `babysit_classify.py`). An operator who registered a non-structural bot account via
  `babysit_extra_bot_logins` (no `[bot]` login suffix, API `__typename` reports `User`) had that
  account's threads miscategorized at both sites — pre-existing relative to #534/#634, which
  migrated these call sites to the shared classifier without introducing the omission. The script
  now accepts `--extra-bot-logins` (same comma-separated shape as the snapshot wrapper) and passes
  it to both sites; `babysit_extra_bot_logins`'s flag-delivery mapping in SKILL.md now lists
  `resolve-thread` alongside `snapshot`. Because configuration reaches these scripts only through
  CLI flags, the mapping alone would have left the flag unused: every exact resolver command form
  the agent copies — the two pinned degradation commands in `reference/safety.md`, the Worker
  Contract clause and the Worker Prompt Template in `reference/orchestration.md`, and the
  thread-resolution bullet in SKILL.md — now carries `--extra-bot-logins <extra-bot-logins>`, and
  `safety.md` states the rule so a future command form does not drop it again. The module docstring
  argparse renders as `--help` no longer claims bot identity comes from API signals alone: it now
  names `--extra-bot-logins` as the one operator-supplied exception, so someone auditing this
  privileged helper reads the capability it actually has. Low severity — dormant unless an operator
  has configured the userConfig key for a non-structurally-detected bot account.

## [0.31.0]

### Changed

- **No babysit parser resolves a flag abbreviation any more, and the property is now the
  directory's rather than two files' (`#1371`).** A permission grant states its condition as the
  literal presence or absence of a flag in the command text — above all "no `--merge` means
  check-only". Argparse's default prefix abbreviation lets `--mer` resolve to `--merge` while the
  command text contains no such flag, so the written command and the resolved behavior diverge,
  which is exactly what such a condition must be able to rule out. `#1354` closed this on
  `babysit_merge.py` and `babysit_resolve_thread.py`; the remaining seven entry points —
  `babysit_findings.py`, `manage_babysit_lease.py`, `manage_feedback_ledger.py`,
  `pr_queue_snapshot.py`, `prune_babysit_worktrees.py`, `refresh_pr_branch.py`, and
  `request_review.py` — still inherited the default. All nine now set `allow_abbrev=False`.

  Hardening them one at a time is what let the gap persist, so the guard contract gains a gate over
  the whole catalogue: every Python entry point is invoked with an unambiguous three-character
  prefix of `--help` and must not exit 0. `--help` is registered on every parser, and it
  short-circuits parsing — so an abbreviation that resolves exits 0 before required-argument
  validation runs, while one that does not is a usage error. That makes the exit code a sufficient
  discriminator without a per-CLI argument shape, and a companion test asserts the discrimination
  against argparse itself rather than assuming it. Three characters because
  `manage_babysit_lease.py` also registers `--heartbeat-interval-seconds`, so a shorter prefix is
  ambiguous there and exits 2 regardless — the probe would have passed on that entry point while
  proving nothing. A tenth entry point arriving with the default now fails CI instead of shipping.

  Abbreviated invocations that previously worked are now usage errors, which is the point.

## [0.30.0]

### Added

- **`babysit-readiness-gate.sh` emits a `READINESS_UNPROVEN` verdict instead of going silent
  (`#787`).** Its header promised a machine-readable verdict on every check run, but the
  invalid-argument (exit 3) and prerequisite-missing / fetch-failed (exit 4) paths wrote to stderr
  only. A caller grepping stdout for a verdict therefore saw *nothing* on those paths — identical to
  what it sees when the gate was never invoked at all, which is how a blocked gate could be reported
  as readiness. Every *check* run now prints exactly one `READINESS_*` line;
  `READINESS_UNPROVEN reason=<bad-args|identity-unresolved|prereq-missing|comments-unreadable|checklist-unreadable|fetch-failed> pr=<n>`
  joins `READINESS_OK` and `READINESS_BLOCKED`. Exit codes are unchanged, so existing callers keyed
  on them are unaffected.
  `--help` is explicitly outside the contract — it prints usage and exits 0 with no verdict — and
  the header no longer un-indents a `READINESS_*` token into its own help output, where a caller's
  `^READINESS_` grep read documentation as a malformed verdict. The header is now printed by
  derivation from the comment block rather than a hardcoded line range that silently truncated as
  the header grew.
- **Readiness is declared by quoting the gate's verdict verbatim (`#787`).** `babysit-prs`'s
  iteration report (`reference/loop.md` §5.5) gains a per-PR **Gate verdict** line carrying the
  gate's stdout as printed, or `not emitted — harness denied: <exact command>` when the harness
  blocked the call. Since the gate always prints a verdict, a readiness claim with nothing to quote
  is unproven on its face. This is the limit of what the gate can enforce and the reason the
  requirement sits on the report: no script can report its own non-invocation.
- **A verdict-less readiness claim is never backfilled from live `gh` state (`#787`).**
  `mergeStateStatus`, the check rollup, and any other live state miss exactly the cross-checks the
  gate runs (dependency author, unprotected base, self-login exemption, head match), so they are not
  a substitute verdict. Codified in `skills/babysit-prs/reference/safety.md` "Lane-Script
  Reachability" and in the loop's NEVER-do list. Pinned-Command Degradation continues to cover the
  denied-*mutation* case; this covers the denied-*check* case, which has no ready-to-execute handoff
  because nothing was proven ready.
- **`babysit-prs` declares auto-mode reachability of its own scripts as a prerequisite (`#787`).**
  A host permission classifier can deny the lane's bundled scripts — including the *read-only*
  merge-readiness check, which mutates nothing — leaving the lane unable to gate-prove readiness.
  That reachability is now a declared prerequisite alongside Python, stated with the difference that
  matters: the paths that *prove readiness* have **no degrade tier**, because the Python-free path
  also proves readiness with a bundled script and a verdict never produced cannot be handed to
  anyone. A denied *mutation* is deliberately outside that narrowing — there the gate has already
  proven the PR ready, so Pinned-Command Degradation still degrades it to an operator handoff. The
  contract lives in `skills/babysit-prs/reference/safety.md` "Lane-Script
  Reachability", which points at the host's auto-mode configuration reference for the permission
  semantics rather than restating them, and names the operator's verification step
  (`claude auto-mode config`). The section states its evidence plainly: `#787`'s own denial was of a
  raw wildcarded-interpreter form that auto mode drops by design and that the `bin/`-path wrapper
  has since superseded, so the prerequisite generalizes from `melodic-software/dotfiles#315` — where
  `autoMode.classifyAllShell` suspended twelve purpose-built lane-script grants — rather than
  reproducing that ticket.
- **The disputed retry semantics of a classifier denial are flagged, not settled (`#455`).** The
  Harness Permission Layer's "never retry a harness permission denial" rule is contested by `#455`,
  which records a classifier denial whose retry succeeded. The new reachability section sits
  directly beneath that rule and restates it, so a note now marks the question open and points at
  `#455` — the restatement is inherited, not fresh confirmation.

### Changed

- **`setup`'s babysit `check` gained an executable lane-script reachability canary (`#787`).** So
  the prerequisite surfaces before a cycle rather than mid-cycle. The probe runs the lane's mandated
  invocation forms against non-mutating targets — **both** path prefixes
  (`bash "${CLAUDE_PLUGIN_ROOT}/bin/source-control-babysit-merge" --help` and
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/babysit-readiness-gate.sh" --help`, each exiting 0 without
  network or GitHub access) — and treats a tool-call denial on either as a **FAILED** prerequisite.
  Probing only the `bin/` wrapper would have certified a path the lane's own readiness verdict never
  travels: an allow rule or classifier decision covering one prefix says nothing about the other.
  A *pass*, though, is only reachability: the classifier decides per call, so a permitted `--help`
  cannot certify the production argument shapes, and the probes stay `--help`-only on purpose
  because the merge wrapper's read-only production shape is a live GitHub call a `check` run must
  not make. The skill states that limit rather than over-claiming, and names what covers the
  residual gap — a mid-cycle denial is already fail-honest through `READINESS_UNPROVEN` and the
  §5.5 verbatim verdict quote above.
  The earlier draft only reported settings surfaces as INFO, and instructed enumerating the scopes
  the classifier reads — for which no executable path exists, since the managed scopes are not
  ordinary readable settings files. That clause is dropped in favour of `claude auto-mode config`,
  which prints the effective merged configuration across the scopes it can see; it stays INFO,
  because settings cannot prove what a per-call classifier decides. Because `--settings` is a
  launch-time global flag rather than a subcommand input, a bare probe spawned from a session
  launched with one under-states the effective rules, so the skill now says to forward it (and to
  report the probe as scope-incomplete when the scope came from an SDK object with no file to
  re-supply). The probe still never writes settings.

### Fixed

- **A malformed comment payload no longer reads as readiness.** `babysit-readiness-gate.sh` fed its
  counters straight from `--comments-json` (or the live fetch) with jq's stderr suppressed and its
  exit status unchecked, so a snapshot that was truncated, hand-edited, or simply not a JSON array
  produced zero findings and a `READINESS_OK findings=0` verdict — a ready claim derived from data
  the gate never read, and the exact fail-open shape this release exists to close. The resolved
  payload is now shape-checked once, the body extractions surface their own failures instead of
  swallowing them, and every such path routes through `READINESS_UNPROVEN reason=comments-unreadable`
  at exit 4. The check covers the ELEMENTS, not just the container: `type == "array"` alone still
  admitted `[null]` and `[{}]`, whose missing fields the counters' own `.body // ""` coalesced to an
  empty string — the same false-ready verdict reached through a well-formed container holding
  elements the gate cannot read. Every element must now be an object carrying `author` and `body` as
  strings, which is exactly how the counters consume them (`author` matched against the self list,
  `body` grepped for severity markers); a non-string in either position is unreadable, not empty. An
  empty array and an empty `body` string stay legitimate and still reach a verdict.
- **A `<pr>` argument can no longer forge a verdict line.** Every `READINESS_*` line interpolates
  the PR reference as `pr=%s`, and the value was stored unvalidated — so a positional argument
  carrying a newline emitted *additional* lines into the machine-readable output. A caller reading
  the first `READINESS_*` line could be handed a forged `READINESS_OK findings=0` ahead of the real
  verdict, which turns the exactly-one-verdict contract into a forgery channel. `<pr>` is now
  required to be digits at parse time, so a value that could break the line shape never reaches a
  verdict at all.
- **A snapshot read that fails partway is unreadable, not empty.** `--comments-json` was read with
  `$(cat …)` and the exit status ignored, so a `cat` that emitted a syntactically valid prefix and
  then hit an I/O error left the shape check validating that prefix. A file whose readable head is
  `[]` passed as an empty array while the real findings sat in the part that never arrived. On the
  Python-free degrade path that is `READINESS_OK findings=0` outright; with the refinement available
  it was masked, because `babysit_findings.py` re-reads the file itself. The read status now routes
  through `READINESS_UNPROVEN reason=comments-unreadable` before the payload is examined at all.
- **A comment from a deleted GitHub account no longer makes the gate permanently unprovable.** The
  element check required `.author` to be a string, but GitHub returns `author: null` for a comment
  whose account was deleted and `fetch-all-pr-comments.sh` passes that through — so one such
  comment anywhere on a PR rejected the whole live snapshot as unreadable. Fail-closed against the
  wrong thing: the payload was fine. `.author` is now string-or-null while `.body` stays strictly a
  string, and a *missing* `author` key is still malformed (`has("author")` is what separates them —
  jq reports both an explicit null and an absent key as type `null`). A null author reads as
  non-self on both counters, so the comment counts as a finding source exactly as an unrecognized
  login would, and can never be credited as a self classification row.
- **The §5.5 report template no longer offers an abbreviated verdict to paste.** It listed
  `READINESS_UNPROVEN <reason>` as a shape to choose while the surrounding contract requires
  quoting the gate's stdout verbatim — but the gate prints `reason=<reason> pr=<n>`, and the
  OK/BLOCKED forms carry count fields the menu dropped. A worker following the template produced a
  reconstruction, which carries none of the provenance the verdict contract rests on. The field now
  requires the captured line exactly as printed.
- **The guard contract's documented-command check now covers the reachability canary, and stops
  rejecting `--help`.** `skills/setup/SKILL.md` and this changelog both spell out the canary
  invocation, so the completeness gate correctly demanded `DOC_COMMAND_SOURCES` rows for them —
  and then rejected the command, because accepted flags are read from the parser's usage block and
  argparse renders the `--help` pair as `-h` there. `--help` is now added back on the evidence of
  the check's own call: that invocation *is* `--help` and it exits 0, which is stronger proof of
  acceptance than the usage text gives any other flag.
- **An unreadable `--checklist` no longer reads as a clean one.** The R6 count ran
  `grep -c … || true`, which collapses grep's two distinct nonzero statuses into one: 1 means "no
  unticked box" — a clean checklist — while 2 means the file could not be read. Both produced an
  empty count that normalized to zero, so a checklist lost to a permission or I/O error emitted
  `READINESS_OK … checklist=clean`. Zero matches and zero readable lines are the same number and
  only one of them is evidence. The read status is now captured: 1 stays clean, anything above it
  is `READINESS_UNPROVEN reason=checklist-unreadable` at exit 4, alongside the payload fail-open
  above.
- **An identity-lookup failure is no longer reported as a bad argument.** With neither `--self` nor
  `--extra-self` supplied and the supported `gh api user` default failing — expired auth, an
  unreachable API, an offline snapshot replay — the arguments were valid but stdout said
  `reason=bad-args`. Since §5.5 quotes that verdict verbatim, it pointed operators and automation at
  flags that were already correct. The path now emits `reason=identity-unresolved`, keeping exit 3
  so callers keyed on the code are unaffected.

## [0.29.1]

### Fixed

- **The guard contract's wrapper-denial table is now bound in both directions.** `WRAPPER_DENIED_FLAGS`
  records the flags a `bin/` wrapper refuses before Python runs, and a check already proved every
  *listed* flag is one a `bash-wrapper` refusal row invokes the wrapper to demonstrate. Nothing
  proved the converse: a new refusal row could demonstrate a second refused flag while the table
  stayed silent about it, leaving that flag spellable in a documented command — the table would be a
  subset of the wrapper's behavior while reading as a statement of it. Every bash-wrapper refusal
  row's named flag must now be covered by the table. A companion assertion pins the premise the
  separate wrapper check rests on: the merge parser *does* register `--allow-unpinned-head`, which is
  exactly why a CLI-only check cannot see the wrapper's refusal — if that stops holding, the two
  checks have collapsed into one and the narrowing is no longer load-bearing. The reverse check also
  requires each bash-wrapper row to name a `--flag` in `error_contains`: that field is a tuple of
  asserted output substrings with no invariant that any of them is a flag, so an empty tuple — or an
  option recorded without its leading dashes — would have passed vacuously, leaving exactly the
  omission the check exists to catch.

## [0.29.0]

### Changed

- **Merge-conflict resolution splits the resolve from the push.** `babysit-prs` dispatched conflict
  resolution to a dedicated subagent that also pushed the result. A dispatched subagent starts with
  a fresh, isolated context window and never sees the parent conversation
  (<https://code.claude.com/docs/en/sub-agents>), so a host runtime that grants mutation authority
  only from the operator's own turn cannot observe that grant from inside one — such a push could
  only ever be refused by that gate or route around it. The conflict worker now does the base fetch,
  the head assertion, the `git merge` (never rebase), the marker resolution, the local merge commit,
  and the affected-file verification, and returns one of `resolved` / `escalate` /
  `verification-impossible` / `no-conflict` without touching GitHub. The orchestrator — which does
  hold the operator's turn — pushes, fail-closed: only on `resolved`, only after matching the
  worktree `HEAD` to the reported merge commit, requiring it to have two parents, re-asserting the
  live PR head against its first parent, and re-running the affected-file verification in the
  worktree itself; by refspec, never force. A conflict worker remains a worker for every other rule
  — leases, concurrency cap, check-in — with resolving and not-pushing its only two differences.
  Every prior invariant is preserved, now with an explicit owner. `reference/orchestration.md`
  gains the Conflict-Worker and Orchestrator contracts plus a Conflict-Worker Prompt Delta (the
  regular worker template forbids only *force*-pushing, so a conflict worker needs an affirmative
  never-push instruction); an escalating conflict worker now preserves its partial resolution on a
  SHA-qualified `conflict-wip/<pr-number>-<short-sha>` branch — created with hook-free plumbing,
  never a hook bypass — and exits the merge only after that preservation, so it never strands an
  unmergeable worktree and repeated escalations never collide; `reference/freshness.md` drops its drifting restatement for a pointer; `SKILL.md`,
  `reference/safety.md`, and `babysit-loop`'s Subagents section state the new boundary. Pinned by
  `test_skill_contract.py`.

## [0.28.0]

### Added

- **`babysit-prs` guard semantics are now an executable contract (`#1265`).** The facts a host
  permission classifier has to know about this lane — which entry points mutate, which flags gate
  which guard, where a refusal is enforced, and how a mutation is actually performed — were
  restated in prose by every consumer and had nothing detecting drift. They are now a table in
  `skills/babysit-prs/scripts/tests/guard_contract.py`, executed row by row against the real entry
  points by `test_guards.py`, and rendered to a citable
  `skills/babysit-prs/reference/guard-contract.md`. Every row carries the prose claim it backs, so
  a changed guard fails CI with a message naming the downstream claim that just became false. Five
  binding kinds: refusals (invoked, exit code and message asserted), predicates (the classifier
  called directly, because `--autonomous`'s `isOutdated` requirement is a condition over fetched
  API data that no argument shape expresses), effects (run offline against a throwaway state dir —
  this is what proves `manage_babysit_lease.py acquire` writes with no `--apply`, contrary to what
  its flag names suggest), mechanisms (`refresh_pr_branch.py` uses GitHub's server-side
  `update-branch` and never pushes), and documented command lines (every `bin/`-path wrapper
  command spelled in `reference/safety.md` and `reference/orchestration.md` is checked against the
  backing CLI's own parser). Catalogue gates fail when a new entry point, wrapper, or
  command-spelling document arrives without a row — including the plugin-level
  `scripts/babysit-readiness-gate.sh`, the one lane entry point outside the skill's scripts
  directory. Each binding asserts the specific claim rather than a proxy for it: a row claiming
  the refusal precedes every network call is replayed against a recording `gh` shim and fails if
  the shim ran at all, an effect row records which way the state directory's file set moved so a
  rewrite cannot pass as a deletion, and documented flags are checked against the parser's usage
  block rather than scraped `--help` prose that names flags the CLI rejects. What CI does not
  bind is stated in the generated doc's "Not covered here" section rather than left to inference:
  the entry-point **Class** column cannot be proven for the four entry points whose mutation is a
  GitHub write, because every row runs without network access.

## [0.26.12]

### Fixed

- **`worktree create`'s `worktree_root` handoff is now shell-safe for unset AND special-character
  values (#965).** `${user_config.worktree_root}` substitution into skill content is RAW text
  substitution, not shell-escaped (confirmed against the official
  [plugins-reference § User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration)
  docs), so neither quote style around an inline `--root '${user_config.worktree_root}'` literal was
  fully safe: double-quoted broke on an unset key (`bad substitution`, #898's original finding), and
  the interim single-quoted fix (#898) broke on a configured value containing a single quote (e.g.
  `~/worktrees/O'Connor`), `$`, or a backtick. `worktree-create.sh` gains an additive
  `--root-file <path>` flag that reads the root from a file instead of a process argument; both
  render sites (`context/create.md`, `SKILL.md`) now write the substituted value to a temp file with
  the `Write` tool — a JSON string parameter no shell ever parses — and pass `--root-file` instead of
  inlining the value in a `--root` shell literal. A quoted heredoc is deliberately NOT used: quoting
  the delimiter suppresses expansion inside the body but cannot prevent delimiter collision, so a
  value carrying a line equal to the delimiter would end the heredoc early and the shell would parse
  the remainder as commands. The existing unset guard is reused unchanged: an unset key still leaves
  the literal `${user_config.worktree_root}` token, which lands in the file verbatim, and the helper
  still refuses with exit 3 and its guidance — no behavior change on that path. The rendered
  invocation captures the helper's status before removing the temp directory and re-exits with it, so
  the cleanup cannot mask a refusal behind a zero status. `--root-file` treats the file's bytes as the
  root verbatim: a newline anywhere in it, trailing included, is a usage error (exit 2) rather than a
  trimmed terminator or a silently-taken first line — trimming would be indistinguishable from a root
  whose own last byte is a newline. A NUL byte is rejected the same way, checked on the file before
  the value reaches a shell variable, because command substitution drops NULs and would otherwise
  collapse `<root>-<NUL>suffix` into a path nobody supplied. The `--root`/`--root-file` mutual
  exclusion now keys off whether each flag appeared rather than whether its value is non-empty, so
  `--root '' --root-file <f>` is the usage error it always should have been rather than silently
  selecting one source. `--root` is otherwise unaffected and stays available for a caller that
  already holds the value as a real process argument (a hook, or direct CLI use). No remaining
  `${user_config.worktree_root}` shell literal in either render site.

## [0.26.11]

### Fixed

- **`fetch-all-pr-comments.sh` now emits `in_reply_to_id` for inline review comments (#587).** The
  script's unified schema never projected the GitHub REST field that marks an inline review comment
  as a threaded reply, so any caller reading the script's own output saw the key absent (surfacing as
  `None`/`null` in downstream tooling) even for comments GraphQL confirmed were properly threaded
  replies. Reproduced against live PR #563 data: the raw `pulls/<pr>/comments` response correctly
  carries `in_reply_to_id` on reply comments — the script's `jq` projection for the inline surface
  simply dropped it. Added `in_reply_to_id: .in_reply_to_id` to the inline mapping (sourced from the
  same raw field GraphQL cross-checks against) and `in_reply_to_id: null` to the general/review
  mappings, which have no reply-parent concept on their surfaces. Additive schema change — existing
  consumers that don't read the new key are unaffected. Regression-tested with a threaded-reply
  fixture.

## [0.26.10]

### Changed

- `babysit-prs`'s Worker Contract and Worker Prompt Template
  (`skills/babysit-prs/reference/orchestration.md`) now hand the worker the worktree's **absolute**
  path and forbid relying on the shell's working directory persisting across separate tool calls:
  every git operation is anchored with `git -C <absolute-worktree-path>` (`status`, `add`, `commit`,
  `diff`, `log`, `push`), every file read/edit/write/glob/search takes an absolute path rather than
  a relative one — worktree-prefixed for target-repository files, its own absolute path for a file
  outside the worktree the worker is told to read, such as a `${CLAUDE_PLUGIN_ROOT}` reference — and
  any command that derives its target from the working
  directory without a `-C` equivalent — bare `gh`, `fetch-all-pr-comments.sh`, the target
  repository's own build/test/lint commands — takes a per-call re-`cd` or its own explicit target
  (`GH_REPO`, `FETCH_COMMENTS_OWNER`/`FETCH_COMMENTS_REPO`). A one-time `cd` at dispatch is not
  enough:
  cwd can drift between a read and the next write, silently committing a branch-owned fix into the
  session's default checkout instead of the assigned worktree. Closes the same correctness gap
  `implementation` 0.7.4 closed in the sibling `implement-dispatch` lane. `GH_REPO` is scoped to the
  `gh` calls it can actually anchor: it selects the remote repository only (`gh help environment`),
  so a locally-mutating call such as `gh pr checkout` ("Check out a pull request in git", `gh pr
  checkout --help`) still takes a same-call `cd` — with `GH_REPO` alone it would fetch and switch
  branches in whatever directory cwd had drifted to.

## [0.26.9]

### Fixed

- **`babysit-prs` review-trigger contract now says `pending`, matching the code, and states what a
  failing gate means (#324).** `reference/review-trigger.md` described the trigger signal as
  `<review-gate-context>` "pending or failing", while every gate_state comparison in the engine
  accepts only `pending` (`babysit_review_trigger.py` candidate predicate, `babysit_delta.py`
  "awaiting requested review"), and `request_signal_pending` is derived solely from a `PENDING`
  StatusContext with no target URL. The doc's own Engagement Gate Semantics section defines only
  `PENDING` (no qualifying reviewer activity after the polling window) and `SUCCESS` (may reflect an
  earlier head) — it gives `FAILING` no engagement meaning — so "or failing" was the erroneous
  restatement, not the code. Narrowed the sentence to `pending` and recorded the failing semantic
  once: a failing gate is not an engagement signal and is never a trigger candidate; it is bucketed
  by `classify_checks` like any other check, so it already reaches the operator through the ordinary
  failing-check blocker. Documentation and test only; no behavior change.

## [0.26.8]

### Fixed

- **`fetch-all-pr-comments.sh` output can choke a downstream Python consumer on Windows
  (emoji/cp1252 mismatch) (#597).** The script's UTF-8 JSON output commonly carries non-ASCII
  bytes — bot badge images, reaction emoji — from bot review comments. Reproduced directly: a
  Python consumer that opens the output (or reads this script's stdout) without an explicit UTF-8
  encoding inherits the interpreter's default ANSI code page on Windows (cp1252) and raises
  `UnicodeDecodeError` on those bytes; this repo's own consumers (`babysit_findings.py`) already
  pin `encoding="utf-8"` explicitly and are unaffected, so the gap is external/downstream
  consumers. `fetch-all-pr-comments.sh --help` now documents the `PYTHONUTF8=1` (PEP 540)
  requirement for Windows consumers that don't pin the encoding themselves.
  `babysit-readiness-gate.sh` — the one `babysit_python` caller that parses this script's
  comment-JSON schema and lacked the `export PYTHONUTF8=1` convention the two `bin/` babysit
  wrappers already apply — now sets it too, closing the inconsistency.

## [0.26.7]

### Fixed

- **`babysit-prs` no longer misclassifies a bot's PR-level review comment as "new human feedback"
  (#683).** `gh pr view --json reviews,latestReviews` (`view_pr`'s `VIEW_FIELDS`) returns each
  review's `author` as `{login}` only — no `__typename`, no `is_bot`, and a GitHub App bot's login
  without its `[bot]` suffix; verified live that this is a `gh` CLI JSON-field limitation, not a
  GraphQL one — a raw `author{login __typename}` query against the same PR correctly reports
  `__typename: "Bot"`. Both classification call sites (`pr_queue_snapshot.py`,
  `babysit_feedback.fetch_current_human_stop`) already replace `pr["reviews"]` with the fully-typed
  REST list (`fetch_pull_request_reviews`), but left `pr["latestReviews"]` untouched. Because
  `collect_feedback`'s `latest_reviews_by_author` merges both collections keyed by raw login, the
  same bot actor produced two entries under different keys — one correctly typed (from `reviews`),
  one not (from `latestReviews`, e.g. `chatgpt-codex-connector` without `[bot]`) — and the untyped
  duplicate fell through to `actor_kind`'s login-suffix heuristic and landed in `feedback["human"]`.
  New `babysit_gh.rest_hydrate_reviews` replaces `reviews` with the REST list and drops the stale
  `latestReviews` in one place, used by both call sites, so `latest_reviews_by_author` derives every
  actor's latest review from the properly-typed REST list alone.

## [0.26.6]

### Fixed

- **`scripts/worktree-create.sh` now refuses a git-illegal `--name` with the documented usage exit 2
  instead of environment exit 4 (`#1016`).** The up-front character class (letters, digits, dots,
  underscores, dashes per `/`-separated segment) is not a subset of git's ref grammar, so names like
  `feat/foo..bar`, `foo.lock`, `.foo`, `HEAD`, and `-lead` passed validation, reached
  `git worktree add`, and failed there as exit 4 — the code the helper reserves for environment
  faults. A caller's correction flow keys on exit 2, so an invalid name was indistinguishable from a
  broken environment. The schema check is now followed by `git check-ref-format --branch`, whose
  output is discarded on both streams: on success `--branch` echoes the name to stdout, which would
  break the helper's "created path is the sole stdout line" output contract. Verified across every
  name the character class admits, `check-ref-format` and `git worktree add -b` agree exactly, so no
  previously-creatable name is newly refused. `skills/worktree/context/create.md` gains the matching
  constraint bullet, and the header comment that claimed the character class was "a strict subset of
  what git refs allow" is corrected.

  The grammar check runs **after** the repository is resolved and is scoped with `-C "$toplevel"`:
  `--branch` takes a branchname-shorthand and so performs repository discovery, which dies outright
  when the process's CWD is a stale checkout (a `.git` file naming a gitdir that no longer exists —
  what this plugin's own worktree cleanup handles). Run unscoped, that turned a valid name into a
  false exit 2 from such a directory, and the documented invocation omits `--repo-dir`, so the CWD is
  the default. Consequence: exits 3 (root unconfigured) and 4 (not a repository) can now precede the
  grammar refusal, matching how the pre-existing `--base-ref` and empty-slug exit-2 checks already
  sit after them. The character-class and length checks still run first, before any git call.

## [0.26.5]

### Fixed

- **`babysit_delta.py` and `babysit_feedback.py` now casefold owner/repo/login identity
  comparisons, matching the already-ratified `.casefold()` convention `pr_queue_snapshot.py`
  uses for the identical concept (#815).** `head_repository_scope`'s base/head owner and
  same-repository checks, and `latest_reviews_by_author`'s per-reviewer login key, used
  `.lower()` instead. Functionally equivalent for GitHub's ASCII-only owner/repo/login
  alphabet, but a straggler against the sibling scripts' shared convention. Converted to
  `.casefold()` in both files; added case-insensitivity regression tests covering a
  differently-cased base repo, head repository, and allowlisted owner, and a differently-cased
  reviewer login collapsing to one latest review.

## [0.26.4]

### Fixed

- **`babysit-prs` now separates the finding-classification gate from the merge gate (`#601`).** Two
  differently-named scripts both produced a verdict the docs called "readiness":
  `babysit-readiness-gate.sh` (classification-row counting — blind to branch rules, thread
  resolution, and required checks) and `babysit_merge.py` via `source-control-babysit-merge` (the
  actual merge-policy check). Nothing said which one owns a `MERGE-READY` claim, and the
  `loop.md` §5.5 checklist paired a single "Readiness: ready for merge" field directly under the
  classification gate — which produced a false human-facing `MERGE-READY` report on a PR that a
  `required_review_thread_resolution` ruleset was mechanically blocking. `safety.md` gains "Two
  Gates, One Merge-Ready Authority" as the single home for the distinction; the checklist now
  reports the two gates as separate fields, and every "readiness" site that meant *classification*
  is renamed. No gate code and no emitted `READINESS_*` token changed; note that the §5.5 template
  is machine-consumed via `--checklist <file>` (R6 blocks on any unticked `- [ ]`), so splitting one
  status box into three does change what a checklist-gated iteration must tick. The new section also
  states what "both gates satisfied" means on the orchestrator's direct zero-blocker path (a
  non-draft PR the snapshot reports with zero blockers and no untriaged material feedback goes
  straight to a merge-gate check with no worker): it takes that check without the worker's per-PR
  classification-gate run, what keeps the path from a false `MERGE-READY` is the engine's
  `untriaged_material_feedback` exclusion from `pr_clean_ready_for_direct_gate`, and
  merge-readiness there still comes only from the merge gate's `ready` field. That `ready` field is
  the plugin's **full merge-policy** verdict, not a readout of GitHub's mergeability alone —
  `babysit_merge.py` adds its own policy blockers (dependency-manager author without
  `--allow-dependency`, non-self author on an unprotected base without `--allow-unprotected`, and
  an enabled autopilot merge tier's criteria), so `ready: false` may name a plugin hold on a PR
  GitHub would merge; the docs no longer describe the gate as answering only whether GitHub will
  merge.

## [0.26.3]

### Changed

- **The plugin is now the canonical, sole source for the worktree conventions (#401).** The
  `babysit-prs` skill's `reference/worktrees.md` states it owns the ephemeral babysit-worktree
  exemption (lease-scoped cleanup, never a global open-PR prune — machine-enforced by
  `prune_babysit_worktrees.py`) and that rooting those worktrees outside a repository's discoverable
  tree keeps them out of enumeration such as `ghq list`; the `worktree` skill states it owns the
  parallel-session external-root convention going forward. Both close the SSOT gap left by the
  retired external `ghq-layout-sibling-pr-worktrees` prose doc (physical deletion of that doc is a
  separate follow-up in the dotfiles repo).

## [0.26.2]

### Fixed

- **`babysit-prs` SKILL.md cadence cross-references now point at the section that owns the wake
  seconds (#653).** #652 added the engine-backed `recommended_cadence` → `delaySeconds` mapping table
  to `reference/loop.md` §5.3, alongside the static Python-free degrade ladder already there;
  `reference/cadence.md` has disclaimed the wake mechanics since #322, owning only the cadence states
  and thresholds. SKILL.md still described the older split: runbook step 9 and the Reporting closing
  line sent the reader to `cadence.md` for the wake interval, and the References entry credited
  `loop.md` with only a "static cadence ladder". The Reporting line was a live wrong-number risk —
  `cadence.md` states `idle` = daily, while §5.3 documents `ScheduleWakeup` clamping `delaySeconds`
  to `[60, 3600]`, so inside `/loop` `idle` and `quiet` both wake hourly. All three now cite the §5.3
  cadence contract, and the step-5 progressive-disclosure trigger for `cadence.md` — which correctly
  still points there, for the cadence states — now fires on interpreting a state rather than on
  recommending one. Docs-only; no behavior change.

## [0.26.1]

### Documentation

- `scripts/test-helpers.sh` now points at `docs/conventions/shell-test-helpers/README.md`, the
  repo's owner doc recording that per-plugin shell assert-helper duplication and per-script exit-code
  taxonomies are deliberate, not drift. No behavior change.

## [0.26.0]

### Added

- **`pull-request` gains a `create --pushed --worktree <path>` PR-only entry (`#572`).** For an
  orchestrated flow where a dispatched worker already committed and pushed inside its own out-of-tree
  worktree, an out-of-tree orchestrator opens the PR without redoing commit / push / rebase: the mode
  re-resolves branch and diff from the target worktree (ignoring the session-cwd pre-computed
  context), asserts the tree is clean and fully pushed, runs body assembly and the pre-create gates,
  and calls `gh pr create --head <branch>` explicitly. Body shape, `Closes #N` injection, and the
  required-section gate are the existing `create` mechanics, unchanged. See
  `skills/pull-request/reference/create.md` §2.7.

### Changed

- **`worktree`'s `create` action now documents that orchestrated (autonomous) provisioning does not
  use it (`#572`).** An orchestrator that must stay resident to keep dispatching — e.g.
  `/work-items:work` — cannot invoke `create`, whose `EnterWorktree` terminal transitions the calling
  session; such runs provision non-interactively via the shared `worktree-create.sh` helper (omitting
  the `EnterWorktree` step) or a plain `git worktree add`, then work the worktree via `git -C` without
  entering it.

## [0.25.1]

### Fixed

- **Well-known rung's git-tracked requirement now stated on both resolution surfaces.** #1185's review
  hardening (an untracked/gitignored file at the well-known path must not drive resolution) landed only
  in the enforcement resolver. `config-resolution.md` (drafting) and the commit-convention seam README
  still described rung 2 as firing "when that file exists" while claiming the surfaces were "identical"
  — false after the fix, and a real divergence risk (drafting would use an untracked file the gate
  skips). Both specs now require rung 2 to be **git-tracked** and tell the drafting reader how to check
  it (`git ls-files --error-unmatch`), so drafting and enforcement resolve the same file. Docs-only;
  the resolver already enforced this.

## [0.25.0]

### Added

- **Well-known default path for the neutral convention SSOT (#163434).** The commit-convention
  resolver now probes a repo-dogfooded default path,
  `docs/conventions/source-control/commit-convention.yml`, when the team file declares no explicit
  `## convention_source` pointer. The common case reads ONE tool-agnostic file with no markdown
  pointer-parse and nothing in agent-rewritable prose to sever. Fixed 3-rung precedence, identical on
  the drafting and enforcement surfaces: explicit `convention_source` pointer (relocation override) >
  well-known default path > markdown-H2 (legacy). Full back-compat — absent both a pointer and the
  well-known file, resolution is unchanged.

### Changed

- **Setup recommends the neutral SSOT as the default when a second enforcement consumer exists (F1).**
  When inference detects a commit-msg hook, a CI title check, or a user-stated second consumer,
  `/source-control:setup apply` now recommends the tool-agnostic neutral file (at the well-known
  path, pointerless) rather than steering to markdown-primary; it falls back to markdown-only only
  when this plugin is demonstrably the sole consumer.
- **`setup check` surfaces neutral-SSOT drift (F3).** Two probes: a broken pointer / neutral file
  (FAIL — was silent fail-closed), and a resolved neutral file shadowing a stale markdown-H2
  duplicate (WARN).
- **Neutral-YAML preamble trimmed to a 1–2 line header (F4).** The self-describing multi-line
  preamble template is reduced to what the file is and who reads it; the human document proper lives
  in CONTRIBUTING/AGENTS.md.

## [0.24.0]

### Added

- **`/babysit-loop` — the loop-lane merge lane, plus repo-scoped lane keys on the layered config
  seam.** New skill wrapping `/source-control:babysit-prs` in a self-paced standing or drain loop
  over one repository (required `<owner/repo>` argument): each cycle invokes babysit-prs at the
  resolved tier and scope, layered with a concurrency-safety activity grace window (default 30
  minutes — a PR whose head moved or that received comments inside it, or a draft carrying WIP
  signals, is report-only that cycle), do-not-merge respect (strip only behind the explicit
  `--strip-do-not-merge` flag), the loop-lane escalation contract, and `#502` lane telemetry with a
  durable machine-readable state block. Autonomy is decomposed into seven dimensions with tiers as
  named presets; the merge dimension resolves human-only until the target repository's team-tracked
  config carries loop-lane keys — that tracked file, landed by a reviewable PR, is the recorded
  lane-enabling act — after which it defaults to the loop-lane convention's baseline rung (human
  merge for everything except gate-proven C2-mechanical PRs — a work-class test irrespective of
  author), and its raises bind from the team-tracked config layer only. Shared cross-lane concerns —
  topology, stop shapes including the drain-terminal state, cycle-budget and expiry semantics,
  capability tiers, the subagent discipline preamble — are held by citation to the marketplace
  repository's `docs/conventions/loop-lane/` convention, and the rate-limit guard's operable floor
  is inlined verbatim per that convention's inline-floor rule. `reference/config-resolution.md`
  widens accordingly: the layered `.claude/source-control.md` surface now documents the
  `babysit_loop_*` key family (stop mode, tier preset, per-dimension overrides, grace-window width,
  cycle budget) alongside the commit-subject/PR-title convention keys, with the merge-rung key
  declared in the consumer-config layering convention's policy-floor class. The existing
  user-settings-scoped `babysit_*` `userConfig` keys are untouched — the reference documents the
  personal-scalar vs repo-policy split.

## [0.23.0]

### Added

- **Neutral tool-agnostic convention SSOT — `convention_source` (#1141, author-directed reopen of
  #913).** The team-tracked `.claude/source-control.md` may now declare `## convention_source`: a
  repo-relative flat-scalar YAML file (`subject_pattern`, `pr_title_pattern`, optional
  `pr_body_required_sections` list or `none`, optional `dialect:` defaulting `posix-ere`) that
  enforcement (commit-msg hooks, CI) and drafting (any agent) consume as ONE source — decoupling
  the convention values from the markdown-H2 grammar that previously left consuming machines
  hand-syncing byte-identical regex copies. Absent pointer → today's behavior, zero action for
  existing consumers; the path is always repo-declared (no hardcoded doc root, no well-known
  search list in V1 — recorded decision); the `Conventional Commits` keyword and the pr-title
  deferral marker work identically on both surfaces; the neutral file is authoritative per key with
  markdown-H2 fallback, plugin-only keys stay `.claude/`-side, and user/local overlay layers are
  unchanged. Enforcement contract unchanged (POSIX ERE only, unresolved = no enforcement,
  team-only policy floor — the pointer too is honored from the team file only); a
  declared-but-broken pointer or non-`posix-ere` dialect fails closed with a diagnostic.
  `lib/resolve-convention-pattern.sh` extended (guardrails vendored copy synced byte-identical,
  guardrails 0.13.0); 14 new resolver test cases (44 total). The incumbent markdown-H2 steelman and
  the format decision walk-through are recorded in `docs/conventions/commit-convention/README.md`;
  `setup apply` gains the offer-and-migrate path (spoke section, eval 18) that retires duplicated
  keys rather than leaving both surfaces authoritative. Monorepo per-directory scoping: out of
  scope V1, recorded.

## [0.22.0]

### Changed

- **`/setup` clears the skill-quality static gate; Gotchas surface added; hub split (#1140).** The
  audit flagged MD041/MD013 lint findings, a missing Gotchas surface, and a 453-line hub. Verified
  against the REPO's actual markdownlint config first (per the item's instruction): this repo
  disables MD013 and MD041 in `.markdownlint-cli2.jsonc`, so those findings do not apply under the
  repo's own gate — no lint edits made for them; markdownlint reports clean. A `## Gotchas` section
  now records real first-contact failure patterns from the live audits (omission-never-resets
  per-key fallthrough, `none` vs absence, resolved-value inference gating, nested-directory
  cwd-relative reads, linked-worktree hooks dir, `--since` committer-date vs `%ad` author-date
  recency skew, same-session stale `userConfig` reads). **Hub-split decision: DONE** (not deferred)
  — the `apply` convention write path (layer selection, non-interactive update semantics, the
  7-step interview, the written-file template, per-layer verification scripts) moved verbatim to a
  progressive-disclosure spoke, `skills/setup/reference/apply-convention.md`, with a normative
  pointer and summary in the hub; the growth from #1139's consensus-window inference had pushed the
  hub to 512 lines, over the gate's 500-line hard cap, so the split fell out naturally rather than
  optionally. Hub now 211 lines; `skill-quality:check` passes with zero errors.

## [0.21.0]

### Changed

- **`/setup` convention inference reads a configurable year-scale consensus window, not
  `git log -50` (#1139).** A fixed 50-commit tail misses convention shifts and informal variant
  families entirely — live-run evidence: a 2,122-subject year-scale analysis found a rising
  ticket-prefix pattern at 78.8% recent vs 71.9% older with Conventional Commits at 0%, invisible
  at n=50. The history signal is now one
  `git log --since="<window>" --no-merges --date=short --format='%cd|%s'` pass (committer dates —
  the same clock `--since` filters by, so a rebased commit can't land in the wrong recency bucket;
  review-caught during #1139), auto-subjects
  (`Revert`/`fixup!`/`squash!`; merges via `--no-merges`) excluded, bucket-classified in-context
  and reported as volume-weighted percentages with a recent-vs-older recency split — the user picks
  from the evidence table; no bucket is silently promoted into config. Every knob is plugin
  `userConfig`, never a constant: `setup_inference_window` (git-approxidate, default `1 year`),
  `setup_inference_recency_days` (default `90`), `setup_inference_min_commits` (default `50`),
  documented in the README config table. Generic caveats are handled and stated in the report when
  they apply: shallow clones report the actual covered span, young repos widen to full history and
  degrade to low-confidence below the threshold, and squash-merge-only repos are flagged as one
  signal (subjects ARE the PR titles), not two corroborating ones. New setup eval 17 covers the
  consensus-window inference.

## [0.20.0]

### Added

- **`pr_body_required_sections` accepts the literal keyword `none` — no required sections (#1138).**
  The key could previously express only a list or absence (absence yields the portable default), so
  a repo whose team convention is no PR-body sections — real consumer evidence: a repo whose merged
  PRs are overwhelmingly empty-bodied by design — had no way to state that in config. `none` now
  resolves to zero required sections, parallel to the sibling keys `trailer_policy` and
  `pr_body_attribution`: `/pull-request create` drafts no section scaffold and the §2.4.2.2
  pre-create gate has nothing to require (the §2.4.2.1 closing-keyword check is independent and
  unchanged; ad hoc `## Related` content from real refs is still never dropped). `none` participates
  in per-key layering as a **resolved value, not an absence** — a layer declaring `none` overrides a
  lower layer's list wholesale, while a key unset in every layer still falls through to the portable
  default (`Summary`, `Test plan`). Documented in `reference/config-resolution.md` and the
  pr-body-convention seam README (which now owns the value's rationale); `/setup check` renders a
  resolved `none` as `none (no required sections)` with the winning layer, distinct from the unset
  row, and the `apply` interview offers `none` for repos whose convention requires no sections. New
  pull-request evals 19 (team-layer `none` resolves to an empty scaffold) and 20 (`none` wins the
  per-key override across the three layers) and setup eval 16 (check-report rendering) cover the
  resolution.

## [0.19.0]

### Added

- **`/source-control:setup` now covers `pr_body_required_sections` (#1032, completing #975's
  adoption path).** `check` reports the key's effective value across all three layers — a
  `pr_body_required_sections` row on the effective-configuration table, resolving to the plugin's
  portable default (`Summary`, `Test plan`) with `won by: plugin default` when no layer sets it,
  rather than a blank row. `apply`'s interview offers setting it and the written-config template
  gains the matching `## pr_body_required_sections` section, at parity with every other per-key
  surface (`subject_pattern`, `pr_title_pattern`, `trailer_policy`, `pr_body_attribution`). The
  interview deliberately recommends only the plugin's own portable default and never proposes a
  `Related`/linked-issue section or any other organization-specific list — asking what the repo's
  actual convention requires, never inventing one, per the plugin's Two-lane convention posture. The
  interview also states, per-key-fallthrough-aware, when resetting to the portable default over a
  lower layer that already sets the key requires writing the explicit default list rather than
  omitting the section — an omission only inherits, it never overrides (review-caught during #1032).

### Fixed

- **`## Related` pre-create gate no longer drops visible text sharing a line with an inline HTML
  comment (#975/#1029 follow-up, review-caught during #1032).** The comment-aware heading scan
  previously treated an entire line as comment text once it saw `<!--`, dropping content like
  `Ran smoke tests <!-- details omitted -->` before the section's non-empty check — a false-fail,
  since GitHub still renders the visible text outside the comment. The scan now strips only the
  comment SPAN (single- or multi-line), preserving visible text before, between, and after spans on
  the same line; a genuinely comment-only line, or a fully-hidden middle line of a multi-line span,
  still contributes nothing. Defensive pass over the fence/comment interaction: a fence's content is
  never comment-parsed (comment-marker-shaped text inside a fence stays literal) and a comment's
  content is never fence-parsed (fence-marker-shaped text inside a comment stays literal), and a
  heading line carrying a trailing inline comment is still correctly read as a real exit boundary.
  New eval 18 covers the regression.

## [0.18.0]

### Added

- **Configurable PR-body required-sections scaffold (`pr_body_required_sections`, #975).** A new key
  on `.claude/source-control.md`, resolved across the same three layers as every other key on that
  surface (per-key, whole-list override) — see
  [`reference/config-resolution.md`](reference/config-resolution.md). `/pull-request create` builds
  one `## <heading>` block per resolved section and a new §2.4.2.2 pre-create gate blocks
  `gh pr create` when any required section is missing or empty, naming the exact section and the
  resolved config source (winning layer's file + the key) in its failure message. The gate scans the
  body BEFORE the config-gated attribution footer is appended, so an empty last required section can
  never be masked by footer text that carries no `##` heading of its own; the heading scan is also
  fence- and HTML-comment-aware, so a `## <heading>`-shaped line inside a fenced code sample (e.g. a
  Summary documenting a PR-body template) or an HTML comment (a commented-out draft section) never
  counts as a real section boundary. Fence detection matches GFM's actual rules (up to 3 leading
  spaces before the opener, and a fence closes only on a matching delimiter character — a `~~~` line
  never closes an open ` ``` ` fence or vice versa), not a bare column-zero triple-delimiter check.
  Comment text is never counted as section content at all (unlike a fence, which renders visibly and
  legitimately counts) — a required section whose entire body is an unfilled `<!-- ... -->`
  placeholder reads as empty, matching both GitHub's own render and a comment-stripping PR-body
  validator (all five review-caught during #975). Absent everywhere → the bundled portable default:
  `Summary` and `Test plan` only (research-grounded across GitHub's
  own guidance, Google's CL-description doc, GitLab's dogfooded default template, and a cross-section
  of OSS PR templates — see
  [`docs/conventions/pr-body-convention/README.md`](../../docs/conventions/pr-body-convention/README.md)).
  A marketplace-level owner doc lands now, ahead of a future CI/enforcement consumer, following the
  commit-convention seam's two-reads prior art.

### Changed

- **The assembled PR body no longer includes `## Related` by default.** Previously hardcoded and
  always emitted (defaulting to the literal `N/A`); a `Related` section presumes an issue-tracking
  convention the plugin cannot assume for every consumer, so it moves to configuration
  (`pr_body_required_sections` including `Related`) — the two-lane convention posture the fleet
  already applies elsewhere. A repo that wants the prior behavior declares `Related` in its own
  `pr_body_required_sections`. The closing-keyword line and its own pre-create gate (§2.4.2.1,
  formerly the whole of §2.4.2) are unaffected — this is a scaffold-content change only, never a
  linkage-signal change. When the multi-issue or orphan-PR flow collects genuine `Refs #Y`
  references, a `## Related` section is still emitted ad hoc to carry them, even when the repo has
  not configured it as required.
- **This repository (`claude-code-plugins`) now dogfoods `pr_body_required_sections`.** Its own
  `.github/workflows/pr-issue-linkage.yml` requires a non-empty `## Related`, which the new portable
  default no longer guarantees — self-regression atomicity: a change that would break this repo's
  own CI ships with its own remedy in the same PR, not a follow-up. `.claude/source-control.md`
  (team layer, root) now sets `pr_body_required_sections` to `Summary, Test plan, Related`, matching
  this repo's actual gate. This is the **first fleet-adoption instance** of the key — every other
  consuming repo adopts it the ordinary way, via `/source-control:setup apply`, not by hand-editing a
  file.

## [0.17.1]

### Changed

- **The team convention file `/source-control:setup apply` writes is now self-describing
  (#1046, audit f6).** The template's header states, for the reader who does NOT run these
  plugins, that the file is read by the source-control plugin (and the guardrails
  commit-convention gate where installed), is inert without them, and is a drafting aid —
  not team-wide enforcement, which is a commit-msg hook or CI check. The header is part of
  the template (a reconfiguration run rewrites it in place, never appends a second copy),
  and prose above the first `##` heading is inert to every consumer by construction: the
  enforcement resolver reads only the first non-empty body line under a `## <key>` H2 — a
  regression test in `lib/resolve-convention-pattern.test.sh` now proves a preambled file
  resolves identically to a bare one. The `apply` report for a team write states the same
  draft-aid vs enforcement distinction instead of implying the file enforces anything by
  itself.

## [0.17.0]

### Added

- **Shared worktree-creation helper `scripts/worktree-create.sh` (#399, Phase A).** One helper now
  owns worktree placement: it computes the external path `<root>/<owner>-<repo>-<slug>`, sanitizes the
  branch slug, resolves the base ref (`worktree.baseRef` fresh/head, default branch resolved
  symbolically — never a hardcoded `origin/main`), runs `git worktree add`, and reimplements Claude
  Code's `.worktreeinclude` copy (the intersection of `.worktreeinclude`-matched and gitignored files),
  which is bypassed when a worktree is created with `git worktree add` directly. The flag CLI is the
  stable seam the future `WorktreeCreate` hook (Phase B) will share.
- **New `worktree_root` userConfig directory key.** The external root `/worktree create` places
  worktrees under, mirroring the `babysit_worktree_root` shape. When unset, `/worktree create` refuses
  with guidance rather than falling back to the in-repo `.claude/worktrees/` default.

### Changed

- **`/worktree create` routes through the shared helper instead of `EnterWorktree(name:)` (#399, #400).**
  It runs `worktree-create.sh`, then enters the created worktree with `EnterWorktree(path:)`. On a
  non-zero helper exit (notably exit 3, `worktree_root` unconfigured) it stops with the helper's
  guidance and never falls back to the in-repo path — closing the CLAUDE.md/rules double-load bug
  (#400, upstream anthropics/claude-code #29599 / #23565) for the interactive path. Entering the
  external path prompts for approval (not suppressible outside `bypassPermissions`); create.md documents
  the expected prompt and the declined-approval recovery. The native `WorktreeCreate` hook (Phase B)
  stays gated on the two empirical upstream gates and is not shipped here.

## [0.16.3]

### Changed

- **Dependency-manager hold-merge login set is now configurable (`#917` W1).** The merge gate held
  only the built-in `dependabot`/`renovate` product bots (`DEPENDENCY_MANAGER_LOGINS`); a
  non-dependabot/renovate dependency bot an operator runs slipped the cross-tier hold. The gate now
  also holds any login in the new `babysit_extra_dependency_manager_logins` userConfig (threaded as
  the `--extra-dependency-manager-logins` merge-wrapper flag, matching the existing arg-threading of
  `--approver-bot-logins`); logins are normalized on both sides (casefold, strip `app/` and `[bot]`).
  Ships empty, so an unconfigured install matches the built-in set alone.
- **Branch-to-issue grammar is now configurable (`#917` W2).** `parse-branch-issue.sh` hardcoded the
  `<type>/<N>-<slug>` (and `routine-issue-<N>`) convention, so a repo that places the GitHub issue
  number differently in its branch names silently failed to derive a `Closes #N` line. The script now
  accepts an ERE `pattern` positional (last capture group = the numeric GitHub issue number, e.g.
  `^[^/]+/([0-9]+)-` for `alice/1234-slug`), wired from the new `branch_issue_pattern` userConfig at
  the `/pull-request create` call site. The placeholder is single-quoted there so an unset value
  reaches the script as an inert literal (double-quoting a dotted `${…}` name is a Bash
  `bad substitution`) and falls back to the built-in convention.

## [0.16.2]

### Fixed

- **Babysit worker-worktree head-safety + merge-only freshness (`#548`).** A babysit worker can be
  assigned a worktree in detached HEAD (its PR branch locked in a sibling/foreign worktree) or on a
  stale local branch tip behind `origin`; the checkout/freshness mechanics then merged and pushed
  from that tip, so a stale-tip integration could silently revert the newest branch commit — a
  near-miss where safety depended on the assigned `HEAD` happening to match, not a guard.
  - `reference/safety.md` Checkout And Push Invariants now require asserting the assigned worktree's
    `HEAD` equals the true PR head (`gh pr view --json headRefOid`) before any merge/edit/push (stop
    on a stale/detached mismatch) and pushing via an explicit refspec (`git push "$PUSH_REMOTE"
    HEAD:<headRefName>`) to a **fail-closed** destination — `origin` for a same-repo head; for a
    write-allowed cross-repo head, the fork destination validated by **host + owner/repo** identity,
    not by remote name: canonicalize the URL `git push` will actually use (`git remote get-url
    --push`, which honors a `pushurl` that can differ from the fetch URL) and require it to equal the
    head repo's own URL (`gh api repos/<nameWithOwner> --jq .html_url`), else read-only — fast-forward
    by construction, never `--force` — so a branch locked by a sibling worktree is not a `git
    checkout` dead-end.
  - The worker mechanics are reconciled to that contract: `reference/loop.md` §5.1.2 acquires the head
    via `gh pr checkout` and asserts `HEAD == the live headRefOid` in every checkout path (already-at-
    head, sibling-locked `--detach` reuse, and heal-via-checkout), degrading to read-only on mismatch;
    `SKILL.md` Step 0.2 + cross-tier invariants and `reference/orchestration.md`'s conflict-worker
    follow the same assertion + upstream refspec push.
  - **Freshness is now merge-only.** The prior `loop.md` path rebased-and-`--force-with-lease`d
    linear-history branches, which both violated the skill's own never-force-push invariant
    (`safety.md` "Never Do Automatically", `orchestration.md`) and was the silent-revert vector.
    Behind-default branches now always integrate via `git merge` + a fast-forward refspec push (the
    final squash merge still flattens interim history). **Behavior change:** linear-history branches
    now carry an interim merge commit during freshness instead of being rebased.

  Enforcement remains agent discipline; whether the head assertion belongs in a deterministic helper
  is tracked in `#885`.

## [0.16.1]

### Fixed

- **`babysit-prs` worker/autopilot contract now invokes the guarded mutation wrappers by their
  bundled `bin/` path, not by bare command name (#484).** The bare wrapper names
  (`source-control-babysit-merge`, `source-control-babysit-resolve-thread`) are not on the Bash
  tool's `PATH`, so every bare invocation the contract prescribed failed `command not found`
  (exit 127), forcing workers to hand-roll raw `gh api graphql resolveReviewThread` calls and lose
  the wrapper's `--allowed-owners` guardrail and JSON `action` receipt. `SKILL.md`,
  `reference/orchestration.md` (including the worker prompt template), and `reference/safety.md`
  now invoke each wrapper as `bash "${CLAUDE_PLUGIN_ROOT}/bin/<wrapper>" …` — the same form the
  read-only sibling scripts under `${CLAUDE_PLUGIN_ROOT}/scripts/` already use. The Guarded
  Mutation Wrappers posture in `safety.md` is refined to match: launching a wrapper by path runs
  the wrapper with every guard intact (the merge wrapper still rejects `--allow-unpinned-head`;
  both still fail closed without `--allowed-owners`), so the only forbidden re-spelling is the raw
  Python behind them — which bypasses those guards — and piping a wrapper into an interpreter. A
  one-line pointer in `reference/review-discipline.md` records that the babysit tiers resolve
  through the wrapper, while its D7.5 keeps the general raw-GraphQL policy for `/pull-request`.
- **Known residuals, not fixed here.** The `bin/`-path form does not match a pre-approved
  bare-name `Bash(source-control-babysit-merge:*)` allow rule, so an operator's narrow allowlist
  entries no longer auto-approve these calls; and the root gap — Claude Code documents a plugin's
  `bin/` as on the Bash tool's `PATH` while enabled, yet it is empirically absent here — is an
  upstream/harness matter. Only closing that gap restores bare-name invocation.

## [0.16.0]

### Added

- **`pr_queue_snapshot.py` gains dedicated `--self` / `--extra-self` self-identity flags (`#511`).**
  The posting identities whose comments self-classification suppresses are now resolved from their
  own flags — mirroring `babysit-readiness-gate.sh`'s `--self`/`--extra-self` flag semantics — instead
  of being overloaded onto the `--author` discovery filter. `--self` is a full override (exactly the given logins, `@me` not added);
  `--extra-self` adds identities on top of the authenticated `@me`. The skill's step-4 invocation and
  the `babysit_self_logins` userConfig mapping now route the configured extras through `--extra-self`.
  The `babysit_self_logins` userConfig `description` is corrected to match: it is a
  suppression/classification/merge-exemption set, **not** a discovery filter — which authors' PRs the
  queue discovers stays `--author`'s job, independent of this set. This resolves the discovery-contract
  fork (`#897`): the pre-`#511` `--author @me,<self-logins>` widening was an incidental side effect of
  the old author-derived self set, not a stated goal, so it is intentionally dropped, not restored.

### Fixed

- **Babysit self-comment suppression no longer rides on `--author` (`#511`).** Deriving `self_logins`
  from the discovery `--author` filter broke in both directions: configured extra self identities were
  dropped whenever autopilot widening drops `--author` (so a bot poster's own comments re-fired
  `new_human_blocking_feedback` every cycle), and a discovery `--author` for a different login was
  wrongly treated as self (suppressing that author's genuine feedback from the worker-dispatch arm).
  Self-identity is now resolved independently of `--author` for both `--queue` and `--pr` scope,
  superseding the `@me`-only union from `#494`; the author-derived self fallback in `build_config` is
  removed so no discovery author can leak into the self set.

## [0.15.9]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.15.8]

### Fixed

- **`babysit-readiness-gate.sh` now emits an actionable diagnostic when the live comment fetch
  fails, instead of an undifferentiated exit 4 (#475).** The gate shells out to
  `fetch-all-pr-comments.sh`, which auto-derives owner/repo from the current directory via
  `gh repo view`; from a cwd that is not a checkout of the target repo (e.g. a targeted-recheck
  pass) that derivation returns empty and the fetch exits non-zero, which the gate previously
  surfaced only as `fetch-all-pr-comments.sh failed for PR <N>` + exit 4 — the same exit code as a
  missing `jq`. The gate's failure message now names the cwd it resolved from and the
  `FETCH_COMMENTS_OWNER` / `FETCH_COMMENTS_REPO` override, `fetch-all-pr-comments.sh`'s own
  "cannot resolve owner/repo" message names the cwd and the override, the gate's `--help` and
  exit-code documentation cover the override, and the `babysit-prs` worker checklist (SKILL.md,
  `reference/loop.md`) documents it as a prerequisite for out-of-checkout passes. No behavior
  change to the readiness verdict or exit codes; only the diagnostics and docs.

## [0.15.7]

### Added

- **`babysit-prs` now detects checks that degrade `mergeStateStatus` to `UNSTABLE` without ever
  completing (#374).** The snapshot engine classifies three stuck-check classes from data it already
  normalizes — no new GitHub fetch — and emits them as a per-PR `checks.stuck[]` field (always
  present, empty when none): `orphaned_status` (a pending `StatusContext` with no backing run to
  cancel), `stuck_queued` (a `CheckRun` still `QUEUED` past an age threshold, e.g. an unmatched
  self-hosted runner label), and `never_settling` (any other non-required pending check past the
  threshold). Detection fires only under `UNSTABLE`, so normal in-flight CI and pending required
  checks are never flagged; the age threshold is configurable via
  `babysit_stuck_check_age_seconds` / `--stuck-check-age-seconds` (default 1800s), and orphaned
  status contexts are detected structurally without an age gate. The signal surfaces as a
  `material_findings` entry, **never a `blockers` string** — a sticky blocker would re-pin the PR
  `active` and re-dispatch a worker every cycle for a check no branch action can clear. New
  `reference/stuck-checks.md` routes remediation (branch CI / `ci-workflows` for config-fixable
  cases; `github-iac` / app config for runner-pool and orphaned-status cases) and points at
  `safety.md`'s Stop-and-Ask / Never-Do-Automatically rules; the shared `babysit_checks` classifier
  means the guarded merge gate sees the same normalization.

## [0.15.6]

### Changed

- **`babysit-prs` autopilot merge tier (#476) gains a bot-review precision enabling precondition,
  still shipped DISABLED.** `reference/safety.md` now documents a second operator enabling
  precondition alongside the review-workflow requiredness one: the tier may be enabled only after
  the fleet's bot-review lane has demonstrated recorded precision over a sustained window — the same
  earned-promotion trigger ADR 0002 sets for flipping an advisory review lane to a blocking gate
  (precision proven over a sustained window, ratified as a reviewed change citing the evidence,
  never a calendar flip and never operator discretion alone). Because the tier lets a fleet-produced
  approval satisfy a required-review ruleset, it promotes that lane from advisory to merge-deciding
  and inherits the same evidence bar. Prose/contract change only — no behavioral shift to the merge
  gate, which remains fail-closed and DISABLED absent `babysit_autopilot_merge_tier`.

## [0.15.5]

### Fixed

- **`/pull-request` create flow no longer silently corrupts a branch's fetch/rebase upstream when
  publishing it for a PR (#442, residual finding from PR #763).** A post-merge review empirically
  reproduced a residual silent clobber: §2.4.1's conditional `-u` gate keyed on the LITERAL
  `branch.<name>.remote` config being set. In the triangular shape where `remote.pushDefault` names a
  fork globally but `branch.<name>.remote` is unset (so fetch/rebase falls back to `origin`), the gate
  read "unset", took the `-u` bootstrap path, and `git push -u <fork>` rewrote `branch.<name>.remote`
  to the fork — so the next fetch/rebase silently targeted the fork instead of `origin`. The gate now
  fires `-u` only when the branch has NO existing upstream (`branch.<name>.remote` AND
  `branch.<name>.merge` both literally unset) AND its fetch and push remotes resolve to the same name
  (`resolve-remote.sh` fetch-mode vs `--push`); otherwise it pushes plain and writes no branch config.
  This closes the reported `pushDefault`-only clobber (fetch resolves `origin`, push resolves the fork →
  they differ → plain push, upstream untouched) and a broader corruption family the fix surfaced:
  `git push -u` rewrites the branch's WHOLE upstream — both `branch.<name>.remote` and
  `branch.<name>.merge` — so a branch with any configured tracking kept its merge ref overwritten under
  a resolved-name-only comparison. Three such shapes: an already-tracked branch; a deliberate local-only
  `.` upstream (`git branch --track . <ref>`); and merge-only tracking (`branch.<name>.merge` set with
  `branch.<name>.remote` unset — valid, since Git defaults the remote to `origin`, so the branch tracks
  `origin/<merge-ref>`). Requiring BOTH upstream keys to be absent before bootstrapping preserves any
  existing tracking via plain push. This also changes #763's behavior for the `.` case (it took the
  `-u` path); publishing a branch for a PR no longer mutates a deliberate local-only or merge-only
  upstream — a strict improvement. An ambiguous fetch resolution (empty) is unequal to any push remote →
  plain push, never an abort. The conditional moved out of the `create.md` prose into a new co-located
  `scripts/push-branch.sh` (§2.4.1 now delegates to it), so the gate sequence is executable and testable
  rather than living only in markdown; the normalized `.`-as-unset / `\r`-strip handling stays solely in
  `resolve-remote.sh` and is not duplicated (the upstream-absent probe reads both keys raw — any
  non-empty value means "has an upstream"). New `push-branch.test.sh` drives the full resolve-fetch →
  resolve-push → conditional-push → re-resolve-fetch sequence against real bare remotes across the
  pushRemote-triangular, `pushDefault`-only triangular, non-triangular (asserting the merge ref is
  preserved), fresh-branch bootstrap, local-only `.`, merge-only tracking, and fetch-ambiguous shapes —
  the integration coverage whose absence let this escape `resolve-remote.test.sh`'s resolver-only cases.

## [0.15.4]

### Fixed

- **`/pull-request` create flow no longer hardcodes the remote name `origin` (#442).** The
  `create.md` reference had baked `git fetch origin` (§2.2 rebase) and `git push -u origin <branch>`
  (§2.4.1), so a consumer whose remote is not named `origin` (a repo cloned with `git clone -o
  <name>`, or a fork-based multi-remote setup) would break — a baked repo assumption the
  convention-resolution ladder forbids. Both sites now delegate to a shared resolver
  (`scripts/resolve-remote.sh`) that applies the same candidate-priority ordering the `toolchain`
  linters already use: the current branch's configured remote (`branch.<name>.remote`, a local-only
  `.` upstream treated as unset), else `origin`, else the sole OTHER configured remote when exactly
  one exists. Two or more non-origin candidates with neither `branch.<name>.remote` nor `origin` set
  is ambiguous and fails loudly with a diagnostic rather than silently resolving to `git remote |
  head -1` and risking a rebase/push against the wrong base. The §2.2 substitution is complete —
  every `origin/$DEFAULT_BRANCH` occurrence (fetch, `merge-base`, `rev-parse`, `rev-list`, `rebase`,
  the progress echo, and the
  merge-vs-rebase / skip-condition prose) now reads `$REMOTE/$DEFAULT_BRANCH`, and the
  `ORIGIN_DEFAULT` variable is renamed `REMOTE_DEFAULT` to stay coherent. On the common path — a
  single-remote repo, or a fresh feature branch with no `branch.<name>.remote` yet — both sites
  still resolve to `origin`, preserving current behavior exactly. The §2.4.1 push step calls the
  resolver in `--push` mode, which prepends Git's documented push precedence
  (`branch.<name>.pushRemote`, else `remote.pushDefault`, else the fetch order above) per
  git-config(1) / git-push(1), so a triangular fork flow — fetch from `upstream`, push to the fork —
  resolves each side correctly instead of publishing the branch to `upstream`; the resolver's push
  cases are covered by `resolve-remote.test.sh`. Relatedly, the §2.4.1 `git push` now sets upstream
  (`-u`) only when the branch has no real `branch.<name>.remote` yet: `git push -u` rewrites that key
  to the push target, so on a triangular fork an unconditional `-u` would silently repoint the FETCH
  remote §2.2 reads to the fork and break the next rebase — the push now preserves an existing fetch
  remote and bootstraps tracking only for a fresh (or local-only `.`) branch, where it still resolves
  to `origin` as before. The same `origin` hardcoding still lives in `merge.md` and the `babysit-prs`
  references, deferred to a follow-up.

## [0.15.3]

### Added

- **`pull-request` create flow gates the PR-body "Generated with Claude Code" attribution line behind
  a config seam (#439).** The `🤖 Generated with [Claude Code](https://claude.com/claude-code)` line
  was hardcoded into the PR-body heredoc `/pull-request create` appends to every skill-created PR, with
  no config key to change or suppress it — asymmetric with the commit trailer, which `/commit` already
  externalizes via `.claude/source-control.md`'s `trailer_policy`. A consumer wanting no Claude
  attribution in PR bodies (or a different line) had to fork or hand-edit the plugin, violating the
  repo's "configurable without editing the plugin" convention. The line now resolves from a new
  `pr_body_attribution` key across the same three `source-control.md` layers (per
  `reference/config-resolution.md`): **absent → the default line (unchanged current behavior, so
  existing consumers are unaffected)**, `none` → the line is omitted, any other value → that literal
  line. A **sibling key rather than a reuse of `trailer_policy`** was chosen deliberately: the two
  govern different surfaces (a commit `Co-Authored-By:` trailer vs a Markdown PR-body line), and
  overloading `trailer_policy` would have silently stripped the PR-body line from every consumer who
  already set `trailer_policy: none` (the plugin's own commit eval fixture is one) — a behavior change
  the opt-in-only requirement forbids. `create.md` §2.4.1 resolves the effective value at the model
  level and splices it in as literal text *outside* the quoted heredoc via the same
  parameter-expansion concat `${CLOSES_LINE}` uses, preserving the section's shell-injection safety
  (a custom `$`-bearing line stays inert). `/source-control:setup`'s interview, config template, and
  `check` render the new key; `pull-request` `SKILL.md` and `config-resolution.md` document it. New
  evals pin both the default-present and `pr_body_attribution: none` opt-out paths.

## [0.15.2]

### Fixed

- **`babysit-prs` worktree pruner no longer hard-depends on `ghq` (#438).** The engine-backed
  pruner (`prune_babysit_worktrees.py`) resolved a linked worktree's main checkout by shelling out
  to `ghq` — the plugin author's personal repo-layout tool — and raised a hard `RuntimeError`
  ("install ghq or set ghq.root") for any consumer without it, an undeclared prerequisite absent
  from the README's "runs on `git`, `gh`, `jq`" contract. `repo_path` now resolves the main
  checkout natively from the worktree's own gitdir/commondir pointer via
  `git rev-parse --git-common-dir` (parent of the shared `.git` for a standard clone, the git
  directory itself for a bare-clone hub), so cleanup works with only `git` present regardless of
  repo layout. `ghq` is removed from the executable allowlist entirely — native resolution is
  strictly more correct than ghq's guess from a configured root plus an assumed
  `<root>/github.com/owner/repo` layout, so no optional ghq path is retained. Adds a hermetic
  regression test that exercises resolution and removal against a real linked worktree with no
  `ghq` on `PATH`.

## [0.15.1]

### Changed

- **`babysit-prs` autopilot merge tier (#476) — completed the gate-off flip precondition (#675),
  still shipped DISABLED.** Three coherence gaps that had to close before the tier can ever be
  flipped on are now resolved, all as prose/contract changes with no behavioral shift to the
  merge gate. (1) **Merge-surface wiring:** every autopilot merge surface is swept so an ENABLED
  config can no longer merge via the flagless base path — autopilot's step 3 in `SKILL.md` and the
  zero-blocker direct-gate path both point at `reference/safety.md`, now the single home for both
  the base and the enabled-tier merge paths, and the Pinned-Command Degradation operator handoff
  reproduces the tier-flagged command when the tier is enabled. (2) **Second-account approve mechanic:** the concrete
  out-of-band approval the gate's distinct-bot criterion requires is specified — `gh pr review
  … --approve` submitted under a distinct `<approver-bot-logins>` identity (`GH_TOKEN` or `gh
  auth switch`, never the PR author or a lane identity), only after a genuine clean review pass,
  on the live head so the `--expected-head` pin holds. (3) **Review-workflow requiredness
  precondition:** enabling the tier now carries a documented operator precondition — the base
  branch's ruleset must make the review workflow a **required** status context *and* that workflow
  must always run to a non-skipped conclusion on every PR to the base (requiredness is necessary
  but not sufficient: a required-but-skipped review still reads `mergeStateStatus == CLEAN` without
  having gated anything). Where the review workflow is not required, or can conditionally skip on
  the tier's PRs, the tier must not be enabled. Chosen over a merge-gate review-context config
  (rejected option b) to keep the gate deterministic with nothing new to wire. The skill-contract
  tests are extended to pin all three contracts against drift.

## [0.15.0]

### Added

- **`babysit-prs` autopilot merge tier (#476), shipped DISABLED behind an explicit operator
  flag.** At day-scale throughput, human approve-and-merge is the pipeline bottleneck. The new
  tier lets the fleet satisfy the branch ruleset instead of bypassing it: a second bot account
  (author ≠ approver) runs a genuine review pass through the review plugin and submits an
  approving review only when clean, after which the pinned merge gate merges **only when every
  criterion holds** — required checks green including the review workflow (`mergeStateStatus`
  CLEAN, ruleset untouched), issue-linked, authored by a configured pipeline lane, no human
  `CHANGES_REQUESTED` / blocking comment / unresolved thread, no configured do-not-merge label,
  no unratified `Decision defaulted` marker on the linked issue (the triage lane's maintainer
  veto window, which a maintainer ratifies by comment before the default rides into a merge),
  and a distinct-bot approval on the live head (head SHA unchanged since review). Any criterion
  failing falls back to today's behavior: the PR is reported on the human merge-ready list. The
  gate flag `--autopilot-merge-tier` is **fail-closed** — it refuses unless `--lane-logins`,
  `--approver-bot-logins`, and `--block-labels` are all supplied — and every criterion predicate
  is reused from the shared `babysit_classify` module rather than re-implemented. The tier exists
  only while `babysit_autopilot_merge_tier` is enabled (new boolean userConfig, default off);
  enabling it and any later gate-off flip is a separate, announced operator step. New userConfig:
  `babysit_autopilot_merge_tier`, `babysit_lane_logins`, `babysit_approver_bot_logins`,
  `babysit_merge_block_labels`. Absent the flag the merge gate is byte-for-byte its prior self, so
  worker/autopilot's existing gate-proven merges are unchanged. `safety.md`'s "Never do
  automatically: merge" contract is updated deliberately to codify the tier and its criteria.

## [0.14.0]

### Added

- **The convention config is now three layers, not one.** `source-control.md` was resolved as a
  single project-level file, so a commit convention could not follow an operator across repos or
  machines and a personal deviation from team policy had nowhere to live — per-machine
  reconfiguration meant editing the team-tracked file. It now resolves
  `~/.claude/source-control.md` (user-global) → `.claude/source-control.md` (team, tracked) →
  `.claude/source-control.local.md` (gitignored personal overlay), the order the tracked-rich-config
  seam mandates. `/commit`, `/pull-request`, and `/setup` all read the layering rules from one new
  bundled reference instead of restating them.
- **`/setup apply` takes a `layer=user|team|local` target**, defaulting to `team`, and infers the
  layer from a request that names one ("my personal convention", "for all my repos"). `/setup check`
  now renders the effective merge as a row per key with the layer that supplied it, rather than
  reporting the team file's values as if they were the whole convention.

### Changed

- **Merge semantics are per-key override, a recorded deviation from the seam's concatenating
  default.** A later layer replaces an earlier layer's value key by key and never drops the base
  layer wholesale; a key absent from a later layer keeps the earlier value. Concatenation is right
  for the first-party `security-guidance` precedent, whose layers are prose blocks that genuinely
  accumulate. Every key here is a scalar or a closed list: two `subject_pattern` regexes cannot
  concatenate into a third valid regex, and a concatenated `trailer_policy` would emit two trailers.

### Fixed

- **`/setup`'s gitignore guard no longer applies one verdict to layers that need opposite ones.** A
  gitignored *team* file remains a hard STOP — teammates would never receive the shared convention.
  A gitignored *personal overlay* is the success condition, and the overlay is never staged; when it
  is not ignored, `/setup` surfaces the `.claude/*.local.*` line for the consumer to add rather than
  editing their `.gitignore`. The user-global file is outside the worktree, so no git command runs
  against it at all — `git check-ignore` and `git status` on a path outside the repository would
  produce a meaningless verdict, or a confidently wrong one when the home directory is itself a
  repository.

## [0.13.4]

### Fixed

- **`babysit-prs` dynamic `/loop` wakeups now map `recommended_cadence` to a concrete
  `ScheduleWakeup.delaySeconds` instead of falling back to the generic `/loop` heuristic.** The
  snapshot engine emits `recommended_cadence` (`reference/cadence.md`: active / normal / quiet /
  idle) and `reference/loop.md` §5.3 told the orchestrator to "derive the wake interval" from it,
  but never gave the string-to-seconds translation — so orchestrators silently fell back to the
  generic `/loop` skill's own "lean 1200–1800s" fallback-heartbeat range, overriding the domain
  skill's tighter adaptive-cadence contract and leaving PRs with pending CI or blocking feedback
  unchecked 4–5x longer than intended. §5.3 now carries a deterministic mapping table
  (`active`→300, `normal`→900, `quiet`→3600, `idle`→3600) and states plainly that this signal
  ALWAYS wins over the generic heuristic whenever a snapshot supplies it — in babysit dynamic mode
  the `ScheduleWakeup` delay is the primary cadence signal, not a fallback heartbeat. The `idle`
  row is documented as a ceiling: `ScheduleWakeup` clamps `delaySeconds` to `[60, 3600]`, so
  cadence.md's daily `idle` intent truncates to the 3600s hourly ceiling — a genuine daily cadence
  needs the durable `/schedule` cron mechanism, not a single-session `/loop` wakeup.

## [0.13.3]

### Fixed

- **`babysit-readiness-gate` now credits classification rows per comment surface, closing a
  fail-open where a stale classification could pass the gate past a live unclassified finding
  (#642).** The gate blocks while source findings outnumber their per-finding classification rows.
  The shared classifier counted a self-authored classification pipe-row in ANY comment, including
  PR-level review-summary comments that are never thread-resolved. Because a review thread's
  findings drop when it resolves (the lifetime-vs-open discount) but a PR-level comment can never
  resolve, a stale classification posted outside a thread kept counting after its finding was
  discounted — inflating the classified count past a fresh, still-unclassified open-thread finding
  and emitting a fail-open `READINESS_OK`. Classification credit is now bucketed by surface
  (review-thread, PR-level, and an isolated bucket for comments bearing no surface signal) and
  capped within each bucket, so a classification can only offset a finding on its own surface. The
  Python-free bash degrade gains the thread-state-free analogue (`classified = min(classified,
  findings)`); the per-surface refinement is Python-only, mirroring the existing lifetime discount,
  and stays convergent with the degrade on unsignalled input.

### Changed

- **BEHAVIOR FLIP — a PR whose inline-thread findings are answered only by detached PR-level
  classification replies now reports `READINESS_BLOCKED` where it previously passed.** With
  per-surface credit, a PR-level classification row no longer offsets an inline-thread finding, so
  the gate blocks until each inline finding is answered on its own thread. This enforces
  `review-discipline.md` §D5's already-ratified reply routing (inline findings MUST reply threaded,
  "NEVER a detached `pr comment`") mechanically rather than by prose. Runs that already follow §D5
  routing are unaffected; only runs relying on the previously-tolerated detached-reply shape change
  verdict, and the fix direction is fail-closed.

## [0.13.2]

### Fixed

- **`pull-request` create flow no longer treats a bare `Refs #N` as a closing-keyword opt-out in its
  §2.4.2 pre-create gate.** The local gate's `OPTOUT_REGEX` accepted `Refs #N`, but the real
  `pr-issue-linkage` reusable CI workflow (`melodic-software/ci-workflows` `pr-issue-linkage.yml`,
  the SHA this repo pins) accepts only a native closing keyword (`Closes`/`Fixes`/`Resolves #N`) or a
  literal `No linked issue` / `No related issue:` phrase for its closing-keyword half — `Refs #N` is
  not in that set. A `Refs #N`-only body therefore cleared the skill's own gate yet still failed the
  CI gate on push. The regex now drops `Refs #N` (`^No related issue:` only), so any body the local
  gate passes the validator also passes (a strict safe subset). `Refs #N` remains a valid
  link-without-close reference in the `## Related` section; the §2.4.0 orphan-PR prompt, the §2.4.1
  asymmetry note, and the §2.4.2 gate messages were reconciled to match. The §2.4.0 multi-issue
  prompt still offers `Refs #Y`, but its accepted `Refs` lines now route into `## Related` rather
  than onto the closing-keyword line, and the `closed-branch-issue-does-not-autoclose` eval's
  expected output was aligned to the two-option orphan prompt (`Closes` or `No related issue:`).
  Narrow same-repo fix (option 1); extending the upstream validator to accept `Refs #N` was out of
  scope.

## [0.13.1]

### Fixed

- **`pull-request` create flow now scaffolds a non-empty `## Related` section in the assembled PR
  body.** The create flow builds the PR body from its own template and passes it via `gh pr create
  --body`, which fully overrides `.github/pull_request_template.md` (cli/cli#10751) — so
  skill-driven PRs never see a repo PR template. The assembled skeleton had `## Summary` /
  `## Test plan` but no `## Related` section, so PRs in a repo whose CI enforces a
  `pr-issue-linkage`-style contract (non-empty `## Related` + a native closing keyword) failed the
  gate on first push and burned a red-CI round-trip. The template now emits a `## Related` section
  defaulting to the literal `N/A` (non-empty by default; replace with `Refs #N` references to
  related-but-not-closed PRs/ADRs/decisions when they exist), pairing with the always-present
  `${CLOSES_LINE}` closing keyword so both halves of the contract are scaffolded up front. This is
  the create-flow half of the same gap the repo PR template covers for the web/editor authoring
  path. The §2.4.1 prose documents both scaffolds and flags that a bare `Refs #N` opt-out does not
  satisfy a validator's closing-keyword half (only a real keyword or a `No linked issue` /
  `No related issue:` phrase does).

## [0.13.0]

### Changed

- **`babysit-prs` authorship / finding / approval classification is now one shared module.** The
  self/bot/human authorship test, the finding severity + lifetime-vs-open counting, and the
  approval-verdict heuristics were hand-rolled independently across the snapshot classifier, the
  merge gate, the resolve-thread reporter, and the readiness gate, and the surfaces disagreed on
  identical input — the six-issue misclassification class this refactor closes. They now consume
  one classifier: `babysit_delta`, `babysit_feedback`, and `babysit_merge` import the self-login
  membership test and authorship/finding/approval primitives directly instead of re-deriving them,
  `babysit_resolve_thread` shares the same `is_bot` test, and `babysit-readiness-gate.sh` shells
  out to the shared finding counter (mirroring the existing merge-gate wrapper) rather than
  re-implementing the severity vocabulary in bash grep. Every surface stays a pure predicate with
  no writes. Each formerly-divergent member issue is now a golden fixture, regression-proof by
  construction.

### Fixed

- **`babysit-readiness-gate.sh` no longer over-counts lifetime findings as unaddressed.** The gate
  counted every severity marker ever posted across a PR's lifetime — including markers in review
  threads GitHub already reports resolved or outdated — so a fully-classified PR with re-review
  history reported `READINESS_BLOCKED reason=under-decomposed` permanently even when every open
  item was addressed. The shared finding counter discounts a marker carried in a resolved or
  outdated thread, counting currently-open findings only. (De-duplicating the same concern restated
  across re-review rounds within still-open threads is deliberately out of scope — there is no
  reliable mechanical "same concern" signal — so restatements still count.) The bash counting is
  retained only as the Python-free safe-tier degrade, which cannot see thread state; a convergence
  test pins the two counts together on thread-state-free input.
- **`source-control-babysit-resolve-thread` no longer reports `humanThreadsActed` for a
  Bot-authored thread.** The counter incremented for any acted thread whose comments were not
  *all* bots (`botOnly` false), so a bot-opened thread carrying a later human reply was reported as
  a human-thread action that never happened, undermining the human-thread safety rail's own
  telemetry. It now counts only threads whose opening author is human, via the shared authorship
  classifier — the same author check the `--include-human` eligibility decision already uses.

## [0.12.0]

### Fixed

- **`babysit-prs` snapshot no longer classifies an Approve-with-nits bot review as blocking bot
  feedback.** A `claude[bot]` PR review posted as an issue-level comment with an explicit
  **Approve** verdict and only 🟡-nit findings (no `CRITICAL`/`IMPORTANT` or other severity
  marker) was surfaced as a blocking, genuinely-fresh finding because the body's prose contained
  the word "blocking" ("blocking criteria", "blocking checks", "No blocking issues"), which the
  text heuristic matched. The classifier now parses the verdict and severity markers: an explicit
  approval carrying no genuine severity marker is downgraded structurally (for any bot, not only a
  configured login) to a non-blocking result, consistent with `babysit-readiness-gate.sh`
  reporting `findings=0` for the same review. Detection of genuinely blocking feedback is
  unweakened — in a comment or a non-`APPROVED`-state review, a `CRITICAL`/`IMPORTANT` finding or
  a Request-changes verdict still classifies as blocking, and `CRITICAL`/`IMPORTANT` are now
  recognized as blocking-severity markers in their own right. (A review submitted in the formal
  `APPROVED`/`DISMISSED` state is routed to `ignored` before the severity check — pre-existing
  behavior this change does not alter; whether such reviews should be severity-scanned first is
  tracked as a follow-up in #621.) A negated severity conclusion — a clean approval stating `No CRITICAL or IMPORTANT
  findings` — is redacted before the severity check, the structured-marker analogue of the
  existing `no P1/P2 issues` redaction, so introducing severity-marker detection does not itself
  re-create a false blocker for that common clean-verdict phrasing. A login named in
  `babysit_approval_downgrade_logins` opts that bot's approval into the more-conservative
  `material` bucket (surfaced but non-blocking) instead of `ignored` in the one case the
  structural downgrade reaches — a review body carrying blocking-looking prose that still parses
  as an approval verdict. It does not affect a review already in the APPROVED state or a plain
  clean approval whose body carries no blocking-looking prose: both are ignored regardless of the
  setting, since neither reaches the downgrade branch.

## [0.11.0]

### Added

- **`babysit-prs` surfaces a silent bot→personal identity fallback as an attribution-drift material
  finding.** The snapshot engine gains an `attribution_drift` reconciliation arm: for each write the
  mutation ledger recorded performing, it verifies the landed timeline author is the configured
  intended write-identity, not merely *some* accepted self-login. A recorded write that landed under
  a different self-login — the canonical case being a bot write-identity that degraded to the
  operator's personal login when a token mint failed — becomes a first-class material finding on that
  PR's cycle-status line instead of drifting silently. It is the complement of `foreign_activity`
  (which reconciles same-login events the ledger *cannot* account for) and is mutually exclusive with
  it per comment; unlike `foreign_activity` it reports without suppressing dispatch, since the PR is
  still ours to babysit. The intended identity is configured via the new `babysit_intended_write_identity`
  userConfig key (threaded as `--intended-write-identity` to the snapshot); absent it, the arm is
  dormant. This is pure plugin-side authorship verification — the token-generation root cause is a
  cross-repo concern (medley `gh-bot.sh`) and no change there is needed for the finding to fire.
  Coverage is bounded to the write class the ledger records with a recoverable author (review-trigger
  comments); drift on reactions, classification replies, and branch pushes awaits ledgering their
  identifiers with authorship. Covered by unit and full-classify regression tests in
  `test_babysit_delta.py`. Closes #450.

## [0.10.0]

### Changed

- **`babysit-prs` requires per-thread pins for autonomous thread resolves — the bulk autonomous
  path is refused.** `babysit_resolve_thread.py` now rejects a `--autonomous --resolve` call that
  carries no `--thread-id`, forcing the unattended-worker path through a per-thread vetted loop
  (each thread pinned with `--expected-comment-count` and `--expected-last-updated`, reusing the
  existing TOCTOU pin guard). `--allow-unpinned-thread` is likewise refused in `--autonomous`
  mode, so there is no unpinned autonomous resolve. A worker's own push marks a review thread
  `isOutdated`, and the previous bulk path cleared such threads in one unpinned sweep with no
  proof the finding was addressed; the per-thread pins now close the bulk and comment-drift gaps.
  They do not close the displacement bypass — a push that flips `isOutdated` while the comment
  pins still match is still resolvable — which is tracked as the root fix in #571. This is a
  behavior change to the
  autonomous-worker contract: `SKILL.md` Autopilot step 2 changes from one bulk call to a
  per-thread loop, aligning it with the pinned form already documented in
  `reference/orchestration.md` and `reference/safety.md`. Covered by a regression test in
  `test_guards.py`.

## [0.9.3]

### Added

- **`babysit-prs` snapshot exit-code taxonomy splits advisory from substantive errors.**
  `pr_queue_snapshot.py` now returns `3` for a valid snapshot whose only failure is the advisory
  head-ref alias cross-check, distinct from `1` (substantive per-PR hydration or discovery
  failure) and `2` (fatal, no state written). The split is documented in the module docstring and
  covered by unit tests for every code; an advisory-only run no longer looks like a per-PR
  failure. No caller keyed on the previous `1`-means-any-error behavior (all consumers parse the
  JSON snapshot). The same advisory/substantive split also governs sweep completeness and cadence:
  an advisory-only sweep persists as complete (its full-sweep counter still advances) and does not
  force the tight `active` cadence, since the degraded cross-check leaves every per-PR
  classification and the persisted state intact.
- **`babysit-prs` formalizes the worker→main cross-PR dependency channel.** `orchestration.md`
  documents a worker signalling a discovered cross-PR coupling back to the main agent (which owns
  cross-PR ordering) over the same messaging mechanism used for main→worker, rather than reaching
  across PRs itself.
- **`babysit-prs` records the self-blocking-CI-check bootstrap gotcha.** A newly required check
  whose own fix PR carries that same check cannot be gate-merged and needs a one-time human
  admin-merge bootstrap; captured in the `SKILL.md` Gotchas list.

### Changed

- **`babysit-prs` adds a no-background-monitor STOP at the merge / gate-completion step.** Once
  the merge gate proves a PR ready, or its merge is deferred to a human, the agent reports and
  stops instead of arming a CI watch; added to `SKILL.md` and `reference/safety.md`, pointing at
  the existing no-background-monitor clause rather than restating it.
- **`babysit-prs` clarifies the bare-wrapper invocation rule.** `reference/safety.md` now states
  that the guarded-wrapper JSON must be parsed in a separate step — never piped into an
  interpreter — because an interpreter-in-pipeline trips the auto-mode safety classifier and
  blocks the call.

## [0.9.2]

### Fixed

- **babysit-prs no longer re-dispatches a worker onto its own prior-round replies.** For a solo
  maintainer whose `gh` login is the configured self-login (`gh api user` login plus any
  `babysit_self_logins` extras), the delta engine counted the worker's own classification replies
  and `Fixed in <sha>` follow-ups as new human-authored feedback, manufacturing a self-inflicted,
  unsuppressible `new_human_blocking_feedback` dispatch that re-fired every cycle with zero real
  work. The `new_human_blocking_feedback` and `new_human_feedback` deltas now exclude items
  authored by the configured self-login(s) — the same self-reply exclusion `review-discipline.md`
  §1 already mandates for the worker, and parity with the bot delta arms (self-filtered
  structurally because the engine never comments as a bot). Scoped to the dispatch deltas only: a
  self-authored item still classifies as human feedback, so a genuine "do not merge" comment the
  maintainer posts under their own login keeps the human stop and triage blocker intact and still
  halts the merge gate.

## [0.9.1]

### Fixed

- **babysit-prs review-trigger head-staleness hardening** (dormant-by-default module; no effect
  until `babysit_review_trigger_phrase` + `babysit_review_bot_logins` + `babysit_review_gate_context`
  are configured).
  - **F7** — `request_review.py`'s pre-POST freshness guard rejected only the literal `BEHIND`
    merge state. A head that is behind its base but reports `BLOCKED` (GitHub masks `BEHIND` behind
    `BLOCKED`) slipped through and spent the one-shot review request on a stale SHA. The guard now
    reuses the compare-confirmed freshness signal (`compute_branch_freshness`, off the
    `_blocked_base_compare` enrichment `view_pr` already computes), so a compare-behind head is
    rejected and the branch-refresh flow runs first.
  - **F8** — the candidate predicate in `babysit_review_trigger.py` blocked candidacy whenever *any*
    reviewer reaction existed. Reactions carry no commit SHA, so a reaction left on an earlier head
    persisted onto later heads and permanently suppressed the new head's observation window. The
    check is now scoped to reactions associated with, or newly observed for, the current head.
  - **F8 follow-on** — the F8 scoping stopped at the candidate predicate: `request_review.py`'s
    posting guard (`validate_current_candidate`, both its pre-POST check and its post-POST
    concurrency check) still gated on the raw, unscoped reaction list. A PR made eligible by the F8
    fix because its only reaction was stale (an earlier head) would still have every request attempt
    rejected at posting time, recorded as `"ambiguous"`, and blocked from retrying. The scoping rule
    is extracted into a shared `resolve_associated_reactions` helper in `babysit_review_trigger.py`
    and applied at both the candidate predicate and every posting-guard reaction check.

## [0.9.0]

### Changed

- **`/source-control:setup` adopts the uniform setup contract** (fleet conformance wave). The skill
  now splits into a read-only `check` action (default) and an `apply` action across both
  configuration surfaces. `check` reports the effective commit-subject / PR-title convention (from
  the tracked `.claude/source-control.md`) and the babysit-prs `userConfig` surface (effective
  config, branch-protection posture, Windows long paths) — treating an unconfigured surface as INFO
  (the Conventional Commits / inference default; the safe babysit tier) and FAILing only a
  configured-but-broken convention (a non-machine-checkable `subject_pattern`, or a
  `.claude/source-control.md` excluded by `.gitignore`). The previous interactive convention
  interview becomes `apply`'s interview path, run when no arguments are supplied; `apply
  subject_pattern=<anchored-regex | 'Conventional Commits'>` now writes the convention
  non-interactively. The repo-root anchoring and the git-ignore / staging verification of the written
  file are preserved unchanged.
- The babysit reconfigure guidance is corrected to the fresh-install-only semantics of `--config`:
  interactive `/plugin configure source-control` any time; headless requires
  `claude plugin uninstall source-control` then reinstalling with `--config KEY=VALUE`. Reconfiguring
  `userConfig` is not visible to the running session, so verification defers to a fresh session
  rather than reporting a false failure.

## [0.8.1]

### Changed

- README now declares the full runtime (prerequisite-visibility wave): `jq`
  and Bash (Git Bash on native Windows) alongside `git`/`gh`, plus the
  `unzip` requirement of the CI-log fetch path with its documented
  stop-with-remediation behavior. Script behavior is unchanged — the gates
  already existed at point of use.

## [0.8.0]

### Added

- **`/source-control:babysit-prs` capability convergence.** The skill gains opt-in `worker` and
  `autopilot` tiers on top of the safe default: `worker` auto-resolves outdated bot threads and
  merges PRs the deterministic gate proves ready; `autopilot` widens author and thread scope
  under the watched owners. Both merge only behind `babysit_merge.py`'s gate — `mergeStateStatus
  == CLEAN` cross-checked, head-SHA pinned, never `--admin`, never force-push.
- **Decomposed Python engine** under `skills/babysit-prs/scripts/` (stdlib-only): `babysit_util`,
  `babysit_gh` (one parameterized discovery function, one reviewThreads paginator), `babysit_state`
  (scope-aware, schema-versioned, corrupt-state quarantine), `babysit_lease` (`--repo` scoping +
  snapshot pairing), `babysit_checks`, `babysit_feedback`, `babysit_review_trigger` (bot-agnostic,
  config-driven, dormant when unconfigured), `babysit_delta` (classification + fan-out + L3
  foreign-activity detection). Thin CLIs: `pr_queue_snapshot`, `babysit_merge`,
  `babysit_resolve_thread`, `manage_babysit_lease`, `manage_feedback_ledger`,
  `prune_babysit_worktrees`, `refresh_pr_branch`, `request_review`. Relocated + reorganized test
  suite runs in the plugin-tests lane (`engine.test.sh`, self-SKIP when Python is absent). Python
  3.11+ is a declared prerequisite for the `worker`/`autopilot` tiers only; the safe default runs
  Python-free.
- **First-in-fleet plugin `bin/` wrappers** — `source-control-babysit-merge` and
  `source-control-babysit-resolve-thread` expose the guarded mutations as bare commands whose
  allow rules survive auto mode; the merge wrapper refuses `--allow-unpinned-head`.
- **15 `babysit_`-prefixed `userConfig` keys** (watched owners, self logins, default tier, merge
  method, the bot-agnostic review-trigger settings, bot-login fallbacks, downgrade-reviewer logins,
  cadence and fan-out bounds, worktree root) plus a babysit check/apply section in
  `/source-control:setup`. `babysit_self_logins` unifies with and extends the additive key
  introduced in 0.7.0: it composes on your `gh api user` login as the self set for discovery scope,
  readiness-gate rows, and the merge-gate self-exemption.

### Changed

- **Breaking:** the safe default narrows discovery from every open PR to your own PRs under the
  current repository's owner (own-authorship boundary; Dependabot/dependency PRs are held from
  merge in every tier). `worker`/`autopilot` widen scope explicitly.
- State root moves from `CODEX_HOME` to `${CLAUDE_PLUGIN_DATA}`; all engine configuration is now
  delivered via CLI flags substituted from the SKILL.md effective-config block.
- Self-identity is additive across every consumer — `--extra-self` (readiness gate), `--author
  @me,<extras>` (discovery), and `--self-logins @me,<extras>` (merge gate) each fold the configured
  `babysit_self_logins` extras onto your gh login.

### Fixed

- Multi-login discovery queries `--author` once per login and unions the results (a comma-joined
  value matched no one, silently dropping owned PRs for multi-login users).
- Review-trigger candidacy no longer stalls forever when no CI gateway context is configured (the
  documented gateway-unused fallback).
- Snapshot state honors a `~`-prefixed `--state-dir`, sharing the resolved path with the other
  engine CLIs instead of writing under a literal `./~/…` directory.
- The merge gate recognizes your own PRs on unprotected bases (self logins are passed through),
  no longer requiring the interactive `--allow-unprotected` override for own-authored PRs.

### Removed

- The `BABYSIT_*` environment-variable seams on the Python engine (owners, timeouts, quiet-recheck
  window) — replaced by CLI flags fed from `userConfig`. The shared readiness gate's `--self`
  (full override) / `--extra-self` (additive) contract is unchanged.

## [0.7.0]

### Changed

- **Personal tuning scalars migrated to native `userConfig`** (the fleet-wide kill-switch/scalar
  doctrine ruling): `worktree_stale_days` (default 14), `babysit_self_logins` (csv, default
  empty), and `fetch_logs_max_bytes` (default 52428800). The skills substitute the values into
  their own content; `babysit-readiness-gate.sh` gained an additive `--extra-self` flag (the
  `--self` full-override flag is unchanged) and `fetch-failed-logs.sh` gained `--max-bytes`.
- **BREAKING:** the `WORKTREE_STALE_DAYS`, `BABYSIT_SELF_LOGINS`, and `FETCH_LOGS_MAX_BYTES`
  environment variables are retired and no longer read; re-express any non-default value as the
  matching `userConfig` option. `FETCH_LOGS_SCRATCH` / `FETCH_LOGS_REPO` are unchanged.
  Zero-config behavior is identical.

## [0.6.0]

### Added

- **New `/source-control:babysit-prs` skill** — the all-PR self-pacing babysit loop, extracted
  from `/source-control:pull-request` into its own skill (distinct discovery intent: fleet loop
  vs single-PR lifecycle). Same behavior as the former `babysit` action: discovers every open
  non-draft PR oldest-first, checks each out, keeps branches fresh, classifies every review
  finding with GitHub-verified evidence, fixes valid findings, reports readiness. Never merges.
  Invoke via `/source-control:babysit-prs` (loop pairing: `/loop /source-control:babysit-prs`).
- **Plugin-scope shared review discipline** at `reference/review-discipline.md` — the canonical
  home of finding extraction (with the mandatory ≥3-finding subagent dispatch), per-finding
  D1–D7 verification gates, and self-reply filtering, cited by both `pull-request` and
  `babysit-prs` instead of duplicating the rules per skill.

### Changed

- **Breaking:** the `babysit` action is removed from `/source-control:pull-request` — use
  `/source-control:babysit-prs`. The pull-request description, action table, phase table, and
  checklists no longer carry babysit content; `reference/monitor.md`'s cross-references into the
  former babysit reference now cite the plugin-scope review discipline.
- Shared scripts hoisted from `skills/pull-request/scripts/` to plugin-root `scripts/`
  (`fetch-all-pr-comments.sh`, `babysit-readiness-gate.sh`, `test-helpers.sh`, with their
  tests) — cited by both skills via `${CLAUDE_PLUGIN_ROOT}/scripts/`.

### Removed

- `discover-prs.sh` (+ test) — retired; the inline `gh pr list` filter in the babysit-prs
  reference is the discovery contract.

## [0.5.2]

### Fixed

- `/pull-request create`'s worktreeinclude sync check no longer reports phantom `CHANGED:` lines
  for `.worktreeinclude` patterns that match no files — an unmatched glob stays a literal string
  in Bash and previously fell through to the changed-file branch; it is now skipped.

## [0.5.1]

### Changed

- References to the renamed `/toolchain:build` skill now invoke `/toolchain:check` (toolchain 0.2.0 breaking rename). Version bumped so existing installs pick up the rewritten prompts.

## [0.5.0]

### Added

- **Exec-bit check in `/source-control:commit`.** Immediately after staging, newly-added files whose
  first line is a shebang (`#!`) are checked against the index and fixed with
  `git update-index --chmod=+x` when staged non-executable. Closes the gap where a new `.sh`/`.py`
  script lands as mode `100644` and is only caught by a CI exec-bit lint lane after the push
  round-trip. Runs after the format-before-push check below (not before), because re-staging a
  formatter's fixes reads the worktree file mode and would otherwise silently undo an
  already-applied `--chmod=+x`.
- **Format-before-push check in `/source-control:commit`.** Before drafting the commit message, the
  skill now checks the consuming repo for an already-configured formatter/linter (`package.json`
  scripts, `biome.json`, a `Makefile` target, `.editorconfig` + `editorconfig-checker`, or an
  equivalent repo-native tool) and runs it against the files staged for that commit, re-staging any
  fixes. Scoped to this commit's paths, not the full index, so it never mutates or blocks on staged
  work outside this commit's scope. Runs only tooling that already exists in the consuming repo;
  skips silently when none is discoverable.

## [0.4.1]

### Fixed

- Require a branch-derived issue to be open before adding `Closes #N`, preserve
  merge-commit branch history when integrating the default branch during PR
  babysitting, and stash a dirty worktree before reusing it for the next task.

## [0.4.0]

### Added

- `/source-control:setup` skill: interviews the repo and writes the tracked
  `.claude/source-control.md` commit-subject / PR-title convention config —
  inferring first from the repo's own `CLAUDE.md`/rules, commit-msg hook, or
  git log history before asking. Offers Conventional Commits (11-type
  vocabulary) as the recommended default, or a custom pattern for orgs that
  don't use Conventional Commits. Re-runnable to reconfigure. Ships evals.

## [0.3.1]

### Changed

- Synced the pull-request verify-gate example to the reorganized taxonomy:
  `/verify-changes` / `/build` are now `/verification:confirm` / `/toolchain:build`.

## [0.3.0]

### Added

- `/resolve-conflicts` skill: intent-first resolution of in-progress merge/rebase/cherry-pick
  conflicts — both sides' history read before any hunk is edited, compose-by-default with
  evidence-gated side-dropping, a post-resolution semantic-conflict sweep (build/tests before
  done), and a hard never-`--abort` discipline. Ships three evals.

## [0.2.0]

### Added

- Readiness security-gate, mixed-actor, and three worktree evals.
