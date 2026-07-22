# Changelog

All notable changes to the `review` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.15.0]

### Added

- Deep-scan escalation routing to the official Claude Security plugin (`/claude-security`) from
  quality-gate security mode and the fanout leaf roster — presence-gated, pointer-only
  (contract stays upstream at <https://code.claude.com/docs/en/claude-security>), and explicitly
  not a fan-out leaf.

## [0.14.11]

### Changed

- Fresh-eyes delegation sites now prefer a cross-vendor advisor when one is installed
  (e.g. the OpenAI Codex plugin, invoked per its own docs), with the fresh-context same-vendor
  subagent as the stated fallback — presence-gated per the seam-phrasing convention.

## [0.14.10]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.14.9]

### Added

- **`doc-drift-detector` gates classification behind an existence pre-check**
  (#505). Before judging a page's accuracy, the agent now asks the admission
  question first — could a reader with repository search derive this content
  from the code itself? — and routes an admission failure to a new
  **Deletion-candidate** category (recommend relocate-then-delete, never
  auto-delete) instead of forcing it into Stale/Missing/Aspirational.
  Decisions, domain language, thin navigation, and policy/wiring pages always
  pass admission. The four-factor scoring behind a contested call reuses
  `/docs-hygiene:audit-derivability`'s rubric by reference (optional
  namespaced skill invocation, degrading to the admission question standalone
  when that plugin is unavailable). Ships as a portable-baseline default;
  a consuming repo's own declared documentation-existence convention overrides
  it via `/re-anchor:follow-our-standards`'s resolution ladder. Report-only,
  matching the agent's existing read-only contract.

## [0.14.8]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.14.7]

### Added

- **`quality-gate` code mode documents its boundary with the built-in
  `/code-review`.** The mode triggers on "code review" and reviews the current
  diff — the same target Claude Code's bundled `/code-review` skill covers — yet
  `context/code.md` never acknowledged the built-in existed, leaving a user with
  no basis to choose between them. The context file now carries a **Boundary**
  section: reach for this mode when the review must ground in the project's own
  standards and severity vocabulary (resolved through the standards index), stay
  report-only, and land in the gate's unified findings report; reach for the
  always-available built-in `/code-review` for a fast zero-dependency pass or its
  `ultra` cloud deep-dive when project-standards grounding is not the point,
  noting that its `--fix` / `--comment` flags mutate and sit outside the review
  modes' report-only contract. Documents the boundary rather than dispatching the
  built-in as a leaf surface — code mode's convention-grounded dispatch
  (`pr-review-toolkit` / `code-reviewer`) is not duplicated review logic that a
  thin router would remove, and delegating to the generic built-in would drop the
  standards grounding, the unified report, and the report-only guarantee.

## [0.14.6]

### Fixed

- **`quality-gate` slash invocation no longer dies silently in headless
  sessions.** The skill's *Pre-computed context* block injects dynamic context
  via the `` !`<command>` `` syntax, which is preprocessing that runs during
  prompt expansion — before the model turn — so the permission gate sits *above*
  the shell. In a non-interactive session (`claude -p "/review:quality-gate …"`)
  the `gh pr list` preflight was permission-denied during that preprocessing,
  and the whole invocation aborted with empty output and exit 0 — total silent
  failure with no model output. The in-command `|| echo "unknown"` guard is
  structurally incapable of catching this: the denial happens a layer above the
  shell, so the shell string (and its `||` fallback) never runs. Prose
  invocation degraded gracefully only because it has no dynamic-context
  preprocessing — the model issues `gh` as an ordinary Bash *tool* call whose
  denial returns a handleable result. Fix: declare `allowed-tools` frontmatter
  authorizing every segment of the three compound pre-computed lines
  (`git branch --show-current`, `git status`, `head`, `echo`, `gh pr list`), the
  documented canonical mechanism for dynamic-context bash, matching the
  `pressure-test` and `wayfind` in-repo precedents. The existing `|| echo`
  fallbacks are retained — they cover a different failure mode (`gh` missing /
  unauthenticated / no PRs) that `allowed-tools` does not touch. The three
  fixed pre-computed lines are granted as EXACT full-command rules (no
  prefix wildcards), so neither mutating subcommands nor output-redirection
  writes (`echo payload > file`, `head src > dst`) fall inside the grant;
  the only wildcard kept is `Bash(gh pr list:*)` for the documented uncapped
  fallback query.

## [0.14.5]

### Fixed

- **Reviewer agents captured the wrong diff base in single-branch clones whose
  branch is based off a non-default branch.** The diff-base resolution ladder in
  all four change-set agents (`code-reviewer`, `security-reviewer`,
  `architecture-guardian`, `ecosystem-specialist`) fetched the PR's real base
  (`git fetch origin "$PR_BASE"`) into `FETCH_HEAD`, but rung 1 then referenced
  `origin/$PR_BASE` — a ref that a `--single-branch` clone never creates — so the
  rung failed and a later fallback rung fetched the default branch, overwriting
  `FETCH_HEAD` before the real base was ever used. `merge-base` then ran against
  the default branch, folding the base branch's own pre-existing commits into the
  review as if they were the PR's (empirically: 3 commits reviewed where only 1
  belonged to the PR). The base rev is now captured
  (`BASE="$(git rev-parse FETCH_HEAD)"`) immediately after the base fetch and used
  directly for `merge-base`, before any fallback fetch can clobber `FETCH_HEAD`;
  the prior no-PR / fetch-failed behavior is preserved via
  `${BASE:-origin/${PR_BASE:-HEAD}}`. Facet B of #625; #661.

## [0.14.4]

### Changed

- **`fanout` `fix` action no longer mutates the working tree unconfirmed in a
  headless session.** The fix action's Step-3 confirmation gate previously
  self-downgraded — "interactive sessions; non-interactive sessions proceed
  without the gate" — so a headless `/review:fanout fix` applied correctness- and
  cleanup-class fixes with no confirmation at all, in exactly the unattended
  context where a human check matters most. The silent waiver is replaced with an
  explicit opt-in flag mirroring the `ai-briefing:generate` `--yes` / `-y`
  precedent ("Skip the pre-execution confirmation gate. Required for headless
  runs."). Interactive `fix` is unchanged (emit plan, confirm, apply). Headless
  `fix` WITHOUT `--yes` now emits the classification plan and STOPs, mutating
  nothing — the plan is the report, so an operator reviews what would have been
  applied and re-runs with the flag. Headless `fix` WITH `--yes` applies, then
  writes a durable applied-plan record (`type: fix-pass-record`) into the branch
  findings directory for after-the-fact review; the non-`review-findings` type
  makes the fix-pass locator skip it so it is never re-consumed as findings.
  Start-strict posture: loosening later is additive, tightening later would break
  automations built against a permissive default. Implements the operator-accepted
  direction on #435.

## [0.14.3]

### Fixed

- **Review diff base no longer bakes `main` as the terminal default-branch
  fallback** (silent-empty-diff fix). Every base-resolution surface resolved the
  default branch as `origin/HEAD`, then fell straight to the literal `origin/main`.
  `origin/HEAD` is frequently unset in CI, shallow, single-branch, and fresh
  clones, so a repository whose default branch is `master`/`develop` fell past a
  non-existent `origin/main` all the way to the `echo HEAD` / `echo "unavailable"`
  terminal — producing an EMPTY diff on a clean committed branch, i.e. a silent
  no-op review with no error. This violated the convention-resolution ladder's
  "No baked repo assumptions, ever". A dynamic resolution rung now sits BEFORE the
  literal `origin/main`: `git ls-remote --symref origin HEAD` queries the remote's
  own default branch over the same transport the clone used — host-agnostic,
  needing neither a locally-set `origin/HEAD` symref nor `gh`. The resolved branch
  is then fetched and the diff is taken against `FETCH_HEAD`, because `ls-remote`
  reports only the branch name and does not populate a local `refs/remotes/origin/*`
  ref — so `origin/<default>` is unresolvable in a full-depth `--single-branch`
  clone (and in a full clone whose `origin/HEAD` is unset), where
  `merge-base "origin/<default>"` would otherwise still fall through to the
  empty-diff terminal. This mirrors the existing `PR_BASE` fetch. The rung stays
  lazy — the network `ls-remote`/fetch fire only when the local `origin/HEAD` rung
  fails, so the well-connected common case pays no round-trip. Falls to
  `origin/main` only as the terminal last resort. Applied identically across the
  four reviewer agents (`code-reviewer`, `security-reviewer`, `architecture-guardian`,
  `ecosystem-specialist`), the `fanout` pre-computed diff-size snippet, and the
  `fanout`/`quality-gate` shared-input and subagent-prompt prose. The remote name
  stays `origin` (de-hardcoding the remote is the cross-plugin shared default-branch
  helper tracked separately by #442, out of scope here). Same bug shape as the
  toolchain gap resolved in #411, using that fix's `git ls-remote --symref`
  resolution mechanism.

  Known limitation: a `--depth=1` shallow clone (the default `actions/checkout`
  shape) still degrades to the empty-diff terminal — after fetching the resolved
  branch at the same shallow depth, `merge-base FETCH_HEAD HEAD` finds no common
  ancestor. Resolving that requires deepening/unshallowing (or a convention-aligned
  report-and-stop) — a real design fork, tracked and deferred to #625 rather than
  bolted onto every reviewer-agent invocation here.

## [0.14.2]

### Fixed

- **`fanout` fix-pass docs describe `/simplify` as an optional in-session skill,
  not "bundled"** (doc-accuracy fix). No `simplify` skill ships under
  `plugins/review/`; the plugin bundles the `fanout`, `quality-gate`, and `setup`
  skills, while `/simplify` is an external/built-in skill resolved from the
  session. `context/fix-pass-mode.md` and the `fanout` eval expectation now call
  the cleanup-class route the "optional in-session `/simplify`" skill. Behavior is
  unchanged — the existing fallback ("when available in the session; otherwise
  apply the cleanup findings directly, one file at a time") already degrades
  gracefully; only the inaccurate "bundled" descriptor is dropped.

## [0.14.1]

### Fixed

- **`quality-gate` pr mode gates the PR-comment-posting orchestrator behind
  explicit opt-in** (un-sanctioned side-effect fix). The `code-review`
  orchestrator's PR mode posts findings as a PR comment, which violates the
  review modes' report-only contract; `context/pr.md` previously presented it
  as the ungated "Primary path." It now carries the same **PR-mutation gate**
  the sibling `fanout` skill already applies to the identical call: when the
  branch has an open PR, the posting mode is dispatched only on explicit user
  opt-in ("post the review comment"), otherwise it is skipped (the skip is
  named in the review report) and review falls to the read-only manual path.

## [0.14.0]

### Changed

- **Setup adopts the uniform check/apply contract** (fleet conformance wave,
  dim 8 — caught by the new contract gate rather than the wave list). `check`
  runs the standards-contract binding's state-reading procedure read-only
  (index presence, row-path validation, version delta) and reports; `apply`
  carries the existing bootstrap/reconfigure/migration flow with its
  explicit-confirmation gates intact, re-verifying after every write. The
  by-reference discipline is unchanged — the procedure still lives in the
  contract binding, not restated here.

## [0.13.0]

### Changed

- **Runtime prerequisites declared and classified** (prerequisite-visibility
  wave). README gains a Requirements section (git; authenticated `gh`; Bash
  via Git Bash on native Windows). `ci-log-auditor` now checks `gh`
  presence/auth up front and stops with a remediation message instead of
  auditing from partial evidence when the CLI is missing.

## [0.12.0]

### Added

- **Named design-smell baseline in `code-reviewer`** (Fowler, *Refactoring* 2nd ed., ch. 3): twelve
  smells — Mysterious Name, Duplicated Code, Feature Envy, Data Clumps, Primitive Obsession,
  Repeated Switches, Shotgun Surgery, Divergent Change, Speculative Generality, Message Chains,
  Middle Man, Refused Bequest — matched against the diff as advisory heuristics. Findings default
  to SUGGESTION at medium/low confidence, carry an explicit confidence label the fanout
  normalization pipeline passes straight through; escalation happens only through a documented
  project rule (the rule carries the severity), and a project standard that endorses a flagged
  pattern suppresses the smell. The prior duplicated-structural-boilerplate bullet is folded into
  Duplicated Code. `fanout` and `quality-gate` inherit the baseline by dispatching the agent; the
  external `pr-review-toolkit` orchestrator path and the self-mode general fallback do not reach it
  (documented limitations). No config surface added — smell suppression rides the existing
  `REVIEW.md` / project-rules seam. No live upstream; regeneration trigger is a Fowler edition
  revision to ch. 3 or a change to `code-reviewer`'s design-smell taxonomy.

## [0.11.0]

### Changed

- Adopt topic-docs contract 2.0.0 (visibility semantics): `reference/topic-docs.md` states review
  reports are lane-local (invisible to sibling worktrees and clones) and cross-lane findings
  graduate through the work-item tracker as tickets that point, never as pasted report bodies.

## [0.10.0]

### Added

- **Standards-index criteria resolution in `/review:quality-gate`**: criteria mode resolves
  review criteria through the consumer's standards index via the new
  `reference/standards-contract.md` binding (synced from the marketplace's standards
  convention) — repo review docs like `REVIEW.md` become inference sources inside the binding's
  resolution ladder, with the severity baseline and agent checklists as the final fallback.
  Step 1's "What conventions apply?" routes through the same index, so every review mode
  (self/code/architecture/security/pr/slice/restatement) inherits index-grounded conventions and
  reviews against the same rows plan formulation loaded.
- **New `/review:setup` skill**: idempotent standards-index bootstrap implementing the binding's
  normative Setup-and-migration section — conforming-index short-circuit, row-path validation,
  directional version-delta migration, and a setup-owned `<standards_dir>/.gitignore` for
  personal overlays.
- **Tripwire test** `tests/standards-binding.test.sh` guards the binding references, the
  ladder-pointer discipline, and the Step 1 index routing against future prose edits.

## [0.9.0]

### Added

- **Cross-repo `REVIEW.md` citation dereferencing** in `code-reviewer`, `security-reviewer`, and
  `architecture-guardian`. Each now recognizes a code-span citation in a consuming project's
  `REVIEW.md` shaped like `<relative-path>.md#<heading>`, splits it into the file path and heading
  anchor, and Reads only the `.md` file — which may live outside the current repository, mounted via
  `--add-dir` — before locating the referenced heading for the full criterion behind a thin
  `REVIEW.md` line before finalizing an overlapping finding. An unresolved citation (mount absent,
  wrong path) is noted in the agent's report rather than dropped silently or treated as a hard
  failure. Whether a `--add-dir`-mounted path is visible to a plugin subagent's `Read` tool the same
  way it is to the main session is not yet empirically verified against a live cross-repo mount.

## [0.8.0]

### Changed

- Renamed the plugin `review-toolkit` → `review` and its skill `code-review-fanout` → `fanout`;
  the six reviewer agents move to the `review:` namespace. Invocations are now `/review:fanout`
  and `/review:quality-gate`. Existing installs migrate automatically through the marketplace
  renames map.

## [0.7.0]

### Added

- **Judgement-call labeling in reviewer output formats.** `code-reviewer` and
  `architecture-guardian` now label design-smell and convention findings as judgement calls —
  advisory, reviewer-tier — never as hard violations; hard-violation framing is reserved for
  findings backed by a documented project rule, a failing check, or a demonstrable defect
  (`architecture-guardian` admits a finding into its Violations bucket only with that backing).
- **Pre-flight fail-fast gate in `code-review-fanout`.** Both review modes now resolve the review
  diff base and confirm a non-empty diff BEFORE any surface is spawned: an unresolvable base ref
  or an empty change set reports and stops — reviewers are never fanned out against an empty or
  wrong diff. The default mode's inline dispatch-gate summary folds into the shared gate; the full
  clean-tree and untracked-only logic stays in the default-mode context, and run-everything mode
  defers to the same gate.
- **Per-dimension breakdown in the fanout report.** The persisted findings file keeps the merged
  ranked queue and adds a required `## By dimension` section regrouping the same findings under
  one heading per review dimension — a merged rank can mask one dimension failing badly while the
  others pass. Stage 4 of the normalization pipeline carries the matching two-axis presentation
  rule; the fix action's parse contract (`## Findings` + `## Unparsed`) is unchanged.

## [0.6.0]

### Added

- **Restored fanout regression evals.** `code-review-fanout`'s `evals/evals.json` gains 14 cases
  (ids 7–20) covering behavior that was still documented but had lost eval coverage: dedup and
  severity-derivation (Stage 3/4 cross-surface merge, content-derived severity for
  no-native-severity surfaces), the fix-pass safety fence (correctness findings are never routed
  to `/simplify`, branch-scoped findings lookup, mixed-class routing), and run-everything's
  null-reconciliation and priority-ordering (named null leaves, the tier-1 barrier ahead of
  tier-2). Also restored: per-tier surface routing and promotion, the large-tier ownerless-slice
  exclusions, the findings-file shape contract, the clean-tree short-circuit, and graceful
  orchestrator-absent degradation.

## [0.5.0]

### Added

- **Model-assignment cost routing for the findings-normalization pipeline.** Each stage heading in
  `code-review-fanout`'s findings-normalization context now carries its model annotation, and a
  closing `## Model assignment` section summarizes the routing: Stage 0 Sonnet (parse fidelity),
  Stages 1–2 deterministic/Haiku (enum lookup), Stage 3 Sonnet (semantic merge), Stage 4
  deterministic.

## [0.4.0]

### Changed

- **Consume the topic-docs convention** (`docs/conventions/topic-docs/README.md`), bound for this
  plugin in the new `reference/topic-docs.md`. The default findings location moves from
  `.claude/review/<branch-slug>/` to `.work/reviews/<branch-slug>/` — the memory tier's
  concern-scoped reviews home (branch axis, never committed, self-ignoring root). Resolution
  follows the contract's ladder: the concern file's `memory_dir` first, then a consumer-declared
  review-artifacts location (an inference source — the skills offer to persist it into the concern
  file), then the default. The session's first memory-tier write runs the verify-or-create
  self-ignore guard on the resolved memory root; no skill edits the consumer's root `.gitignore`.
- **`.claude/review/` retired outright.** The prior findings location gets no compatibility
  layer, no dual-read window, no migration tooling; move residual content manually.
- **`quality-gate` self-mode plan source:** the approved plan/brief is now sourced from the
  conversation, else the topic's contract slice `docs/topics/<slug>/PLAN.md` (memory-tier fallback
  under `contract_tier: local`), replacing the untyped "project's working notes" phrase.

### Added

- **`reference/topic-docs.md`** — the plugin's compact binding to the topic-docs contract: what it
  writes (memory tier only, branch axis), resolution order, branch-slug and timestamp spec, and
  runtime guards.

## [0.3.0]

### Added

- **Skill evals for the two orchestration skills.** Rich-form `evals/evals.json` authored for
  `quality-gate` (6 cases) and `code-review-fanout` (6 cases), each covering trigger/routing, the
  happy path, a refusal/guardrail, and an anti-pattern the skill must not do. Additive test
  definitions only — no behavioral change to any skill or agent.

## [0.2.0]

### Changed

- **`ecosystem-specialist` consumes the ecosystem-commands contract.** The agent now resolves each
  ecosystem's build/test/lint command truth from the consumer repo's `.claude/ecosystems/<ecosystem>.yaml`
  files (authoritative when present) — the marketplace-wide ecosystem-commands contract
  (`docs/conventions/ecosystem-commands/README.md`) — falling back to the project's documented
  conventions, then the agent's own bundled generic defaults as an explicit last resort. Ecosystem
  detection may use the contract's `globs` when config exists. Report format, MISSING-tool handling,
  and detection behavior are unchanged; only the command-truth sourcing moved from the agent's inline
  defaults to the declared contract.

## [0.1.0]

- Initial release: six read-only reviewer agents (`code-reviewer`, `security-reviewer`,
  `architecture-guardian`, `doc-drift-detector`, `ecosystem-specialist`, `ci-log-auditor`) plus two
  orchestration skills (`quality-gate`, `code-review-fanout`).
