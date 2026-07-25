# Changelog

All notable changes to the `source-control` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.26.8]

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
    `bash "…/bin/…"` form this skill uses, and a per-call prompt on these invocations is expected
    rather than a misconfiguration.

  Guidance is unchanged and was already correct: the `${CLAUDE_PLUGIN_ROOT}/bin/` path form is
  canonical because it is the only form that runs in both `PATH` states. Only the justification
  changed, and it mattered — a reader who checked on a session where the bare name *did* resolve
  found the doc contradicting their own shell, and the documented reason to keep the path form
  disappeared exactly when it looked safe to drop.

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
