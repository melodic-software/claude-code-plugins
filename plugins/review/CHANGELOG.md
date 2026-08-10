# Changelog

All notable changes to the `review` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.18.1]

### Fixed

- **`agents/ci-log-auditor.md`'s annotation-gap cross-reference no longer truncates.** Finding 6
  fetched `repos/<owner>/<repo>/commits/<sha>/check-runs` unpaginated. The endpoint caps at 30 per
  page by default and signals nothing when it truncates, so the auditor compared the `##[error]`
  count against an under-counted check-run list — manufacturing a mismatch, or hiding a real one,
  with no visible symptom. Both that fetch and the per-check-run `/annotations` fetch now use
  `--paginate` with `per_page=100`, and the agent is told to assert `total_count` against the
  flattened per-page count before drawing any conclusion, including the reason the naive assertion
  is wrong (`--jq` runs per page, so the count must be slurped across pages first).

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.17.2]

### Fixed

- **`skills/fanout`: the `code-review` plugin's comment is identified as the one this invocation
  created, not as the latest comment.** `context/findings-normalization.md` told the pipeline to
  retrieve that surface's raw text with `.comments[-1].body`, which is whatever landed most
  recently — the prose named the plugin's `### Code review` heading but the expression applied no
  filter at all. Any bot or reviewer commenting between the dispatch and the fetch was therefore
  normalized as `code-review` findings and written into the persisted report. Retrieval is now an
  ID-set difference: `SKILL.md` records the PR's comment IDs before dispatching, and the fetch
  selects the comment whose ID is new. Identity rather than a timestamp window, because a cutoff
  narrows *when* a comment arrived but never establishes *who* wrote it — a third party quoting the
  heading mid-dispatch would still have won. Identity is paired with a shape test, because being
  new does not make a comment the plugin's: a reviewer quoting the review posts a genuinely new
  heading-bearing comment, and when the dispatch posted nothing that quotation was the sole new
  match and was normalized as this surface's findings. The body must now BEGIN with the
  `### Code review` heading and carry the `🤖 Generated with [Claude Code]` trailer — the shape the
  plugin's own command file mandates — which a quotation fails, where a substring test did not. The
  trailer is matched by prefix rather than by its full link so an upstream URL change cannot
  silently un-match it. Author remains deliberately unfiltered: the plugin posts under whatever
  `gh` credential invoked it, so no fixed login exists and a hardcoded one would break for the next
  consumer. A `length == 1` guard refuses to guess: zero new matches (the dispatch produced none)
  and two or more (a genuinely ambiguous window) both yield empty output, documented as a
  `## Surfaces` skip — never a fallback to the latest comment.
- **`skills/fanout`: the pre-dispatch snapshot is taken in the step that dispatches.** `SKILL.md`
  Step 1 dispatches the surfaces and Step 2 only then opens
  `context/findings-normalization.md`, so a "capture this before dispatching" instruction living in
  the normalization context could never run in time. The snapshot now sits in `SKILL.md`'s
  `code-review` bullet, and it is carried into the retrieval as a spliced literal rather than a
  shell variable, which does not survive the tool-call boundary between the two steps.

## [0.17.1]

### Changed

- **`ci-log-auditor`: the 500-word output budget now says what to do when findings exceed it.** A hard
  word cap on a finding-bearing report with no overflow rule leaves dropping findings as the only way
  to comply — the opposite of the never-drop normalization `fanout` applies to the same findings. The
  agent now keeps every finding row and compresses evidence and recommendations instead.

- **`quality-gate` criteria mode: the five-step "Applying criteria to changes" list is one sentence.**
  The steps enumerated a procedure the model already performs, and step 2's change-nature taxonomy
  (new feature, refactor, bug fix, config) routed nothing — no other file in the plugin reads it, and
  step 1 matched on the change's surfaces rather than its nature. The replacement keeps all three
  load-bearing elements: grounding in the actual changes, selectivity, and the resolved severity
  vocabulary. The skip-list paragraph and the "How to use" routing list are untouched.

## [0.17.0]

### Added

- **`fanout`: dispatch contract — finder leaves are told coverage is their job.** The skill runs a
  5-stage normalization pipeline (dedup, agreement/rank) downstream of its leaves, and the Sonnet 5
  and Opus 4.8 prompting guides both state that current models follow a stated severity bar
  faithfully at the finding stage — same investigation depth, fewer reported findings — and that a
  harness with a separate filter stage should say so explicitly at the finder stage. Both review
  modes now append a verbatim coverage clause to every dispatched finding-producing leaf prompt:
  report everything including uncertain/low-severity findings, attach confidence and estimated
  severity, filtering happens downstream. Recall is restored without moving precision work — the
  pipeline remains the filter. run-everything's Workflow path carries the same clause in its
  script: both prompt constructors (`AGENT_PROMPT`, `slicePrompt`) append it, and the slice prompt
  asks for the high/medium/low confidence level, so the Workflow-accelerated sweep gets the same
  recall and confidence axis as live dispatch.
- **`quality-gate`: per-slice template reports coverage-first with a Confidence column.** The slice
  reviewer template now states that severity and confidence label findings rather than deciding
  whether they are reported, and its findings table carries a Confidence column — constrained to
  the severity baseline's high / medium / low vocabulary — feeding the fanout pipeline's confidence
  stage instead of leaving slice findings unscored (an unlabeled finding ranks above
  honestly-labeled low-confidence ones). The seams consume it end-to-end: the fanout normalization
  parse contract records the slice surface's native confidence and Stage 2 passes the label
  through, and quality-gate's own Step 3 report table gains the Confidence column. The agent
  leaves carry the same field: architecture-guardian and doc-drift-detector gain per-finding
  high/medium/low confidence in their output formats, code-reviewer extends its confidence line
  from design-smell findings to every finding (smells stay capped at medium), and
  security-reviewer's no-findings line no longer reads as a low-confidence reporting filter —
  matching the dispatch clause's ask and the parse contract's expectations.

### Changed

- **Agents: instruction scope made explicit where literal executors under-covered.** Current
  models do not silently generalize an instruction from one item to another (Sonnet 5 / Opus 4.8
  prompting guides, "More literal instruction following"), so four spots that demonstrated one
  instance while meaning a class now state the class:
  - `code-reviewer`, `security-reviewer`, `architecture-guardian`: the `REVIEW.md` code-span
    citation step now enumerates and resolves **every** citation of the `<path>.md#<heading>`
    shape (deduplicating repeated paths) instead of describing the procedure for "a citation" —
    a literal read resolved the first and silently truncated the criteria set.
  - `security-reviewer`: ecosystems with no dedicated section (Go, Rust, Ruby, Java, …) now have a
    stated floor — the OWASP table plus the cross-ecosystem list, with the unlisted status named
    in the report — instead of an accidental gap behind "apply the sections matching the
    ecosystems actually touched".
  - `ecosystem-specialist`: a detected ecosystem with no generic default (e.g. PowerShell) is no
    longer conflated with "has no such phase" — commands resolve from the repo, and a phase that
    resolves nowhere reports UNVERIFIED rather than skipping silently.
  - `security-reviewer`, `architecture-guardian`: the change-set step now says to Read the
    untracked files `git ls-files --others` lists (previously stated only in `code-reviewer`), so
    two dispatched reviewers no longer run a command whose output nothing told them to use.

## [0.16.1]

### Changed

- **`skills/fanout`: the reason the orchestrator plugins run on the main thread is now a
  configuration bound, not an impossibility.** `SKILL.md` said "a subagent cannot dependably do
  that" and `context/run-everything-mode.md` said a Workflow `agent()` "cannot dependably spawn
  them". The live
  [sub-agents documentation](https://code.claude.com/docs/en/sub-agents#let-subagents-spawn-their-own-subagents)
  states that by default a subagent CAN spawn subagents of its own, within a nesting-depth limit, so
  both sentences asserted a limitation that does not exist. The rationale is now the narrower true
  one: that depth budget is settings-configurable through `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`
  (`1` turns nesting off) and so sits outside the skill's control, and at the limit Claude Code
  withholds the `Agent` tool — in a fork, keeps it but errors — whereas that limit never disables
  the main thread's own `Agent` tool.

  **The claim is deliberately scoped to the depth limit.** The session and concurrent subagent
  limits bind the main thread too, so no surface can claim an unconditional spawn guarantee.
  `run-everything-mode.md` now states only the placement it enforces — orchestrators on the main
  thread, never inside the Workflow — and points at `SKILL.md` for the rationale, because the
  sub-agents page holds workflow-spawned agents to their own limits rather than this one.

  **No behavior changes.** Both surfaces still run the orchestrators on the main thread and still
  keep them out of the Workflow; only the justification prose changed.

## [0.16.0]

### Changed

- **`context/severity.md`: each severity tier is now stated as a decidable test, not a qualitative
  label.** The tiers read "Must fix" / "Should fix" / "Consider" plus a list of examples, which lets
  a reviewer place a finding that resembles a listed example but leaves a novel finding undecidable.
  The Sonnet 5 prompting guide, "Code review harnesses", names this shape directly — "be concrete
  about where the bar is rather than using qualitative terms like `important`", the qualitative term
  being one of this file's own tier names. Each tier now carries a test the reviewer can argue a
  finding against: CRITICAL, whether you can name a concrete input, caller, or subsequent
  otherwise-correct change the defect makes produce a wrong, unsafe, or absent result; IMPORTANT,
  whether the finding names a
  stated rule violated, behavior added that no test covers, or a degradation or maintenance cost
  with a named trigger; SUGGESTION, neither, so a preference among alternatives that all work. The
  example lists are retained as illustrations of the tests.

  **No finding changes tier.** The tests were written to restate the existing bars, and the example
  lists are unchanged — this states the criterion, it does not re-tier.

  **CRITICAL's subsequent-change limb is qualified `otherwise-correct`, which is what holds that
  guarantee.** Unqualified, "a subsequent change that the defect makes produce a wrong result" is
  satisfied by **code duplication** read literally — the subsequent change is an edit to one copy,
  after which the copies diverge. Because the tests are applied in order and resemblance to a listed
  example is explicitly not a rebuttal, that CRITICAL match would win and silently promote
  duplication out of IMPORTANT, where the previous text pinned it. The qualifier draws the line the
  example lists already assumed: a **cascading architecture violation** breaks a future change whose
  author did everything right, so it stays CRITICAL, while **duplication** bites only through a
  future edit that is itself incomplete, so it stays IMPORTANT.

- **The P1–P5 security fold now states its precedence over the tier tests.** `security-reviewer`
  emits CVSS-anchored P-levels folded as P1/P2 → CRITICAL, P3 → IMPORTANT, P4/P5 → SUGGESTION.
  CRITICAL's new test names an unsafe result, which a P3 finding also satisfies read literally, so
  the fold is now marked as deciding the tier for a P-scored finding. Without that precedence the
  criterion-stating change would have silently promoted every P3 to CRITICAL.

## [0.15.5]

### Fixed

- **`quality-gate`'s code-mode boundary no longer calls `/code-review` "built-in"**
  (doc-accuracy fix). `context/code.md` headed its boundary "the built-in `/code-review`
  skill" and opened "Claude Code ships a built-in `/code-review` bundled skill" — a
  compound of two categories the official docs keep apart. The commands reference
  states "Most are built-in commands whose behavior is coded into the CLI" and marks
  `/code-review` **[Skill]**, "a bundled skill"; the skills page lists `/code-review`
  among the bundled skills and says bundled skills are "prompt-based … Most built-in
  commands instead execute fixed logic directly", with `/doctor` cited as having been
  "a built-in command rather than a bundled skill" before v2.1.205 — the two labels are
  mutually exclusive. `/code-review` **is** a bundled skill; only the "built-in"
  modifier was wrong, so the fix drops it rather than re-labelling the surface. The
  heading and opening sentence now read "bundled skill" and link
  <https://code.claude.com/docs/en/skills#bundled-skills>. The plugin's other
  `/code-review` references (`README.md`, `fanout/SKILL.md`,
  `fanout/context/findings-normalization.md`, `quality-gate/context/pr.md`) already
  carry the correct "bundled" modifier and are untouched. Behavior is unchanged — the
  boundary's routing advice, the report-only contract, and the `--fix` / `--comment`
  opt-in gate all stand.

  Three released entries below carry the same smear — `0.15.1` ("a bundled built-in
  command"), `0.14.7` (the entry that added this boundary section: "always-available
  built-in `/code-review`"), and `0.14.2` ("`/simplify` is an external/built-in
  skill"). They are left as written: a released entry records what that version
  shipped, and this file's own `0.15.3` entry sets the precedent of correcting a past
  rationale in a new entry rather than editing the old one.

## [0.15.4]

### Fixed

- `fanout`'s pre-computed committed-diff-size probe no longer fails to load the skill from a
  worktree-isolated agent. The harness composes a skill's `## Pre-computed context` lines into one
  shell invocation, and the worktree-isolation Bash guard refuses any genuine `$` expansion — the
  line's `D="$(git ls-remote …)"` assignment and command substitution were therefore enough to make
  the whole block, and with it the skill, refuse to load. The fallback chain moves verbatim into a
  bundled `skills/fanout/scripts/diff-vs-base.sh` invoked through `${CLAUDE_PLUGIN_ROOT}`, which the
  harness substitutes into a literal path before any shell sees it; `$` inside the script file is
  unrestricted. Behavior is unchanged, including the `git fetch origin <default-branch>` side effect
  and the distinction between an empty resolved range (prints nothing) and no resolvable base
  (prints `unavailable`). The line's awk `$2` was probed and is not a trigger, so it stays. Covered
  by `diff-vs-base.test.sh` across all four branches of the chain (#1687).

## [0.15.3]

### Fixed

- Restored the `code-review` marketplace plugin as a real, distinct review surface across the
  plugin. The `0.15.1` and `0.15.2` entries below both state a false premise as their rationale —
  that no installable `code-review` plugin exists and that `fanout` "described the same nonexistent
  plugin". `anthropics/claude-plugins-official`'s `marketplace.json` lists `code-review`
  (`./plugins/code-review`, category `productivity`) alongside `pr-review-toolkit`, and
  `plugins/code-review/commands/code-review.md` defines `/code-review:code-review`. Those entries
  are left as written — history is corrected forward, not rewritten. Three surfaces overlap a PR
  review and are now enumerated as three everywhere: the installable `code-review` marketplace
  plugin, the bundled `/code-review` command, and the managed Code Review GitHub App service.
  `pr.md`'s Boundary covers all three and its mutation gate again covers the plugin, which takes a
  PR as its only target and ends every run by commenting the surviving findings back onto it — the
  gate is unconditional because the plugin has no session-returning mode; `fanout`'s orchestrator
  roster is back to three plugins, carrying that gate plus an applicability gate — the same PR-only
  targeting makes the plugin undispatchable on a local branch with no open PR, which
  `run-everything` step 3 would otherwise invoke as an empty surface; and
  `findings-normalization.md` carries the `code-review` parse contract again — with the retrieval
  step it needs, since the plugin posts its findings instead of returning them and the row would
  otherwise have no Stage-0 input — which restores the only referent for the Stage-1 "surfaces
  emitting no severity → DERIVE" rule; the README's
  optional-orchestrator roster names it again. The `pr-comment-gate-opt-in` eval covers the plugin
  alongside the other two mutating surfaces. Re-verified against the live marketplace manifest,
  upstream `plugins/code-review/commands/code-review.md`, and
  <https://code.claude.com/docs/en/code-review> (#1402).
- The behavioral corrections `0.15.1` and `0.15.2` got right are unchanged: bare
  `/code-review <target>` stays ungated (report-only; only `--fix` and `--comment` mutate), the
  managed Code Review GitHub App service stays described as the built-in/managed service it is, and
  `codex` stays in the README's optional-orchestrator roster.

## [0.15.2]

### Fixed

- Carried the `code-review` framing reconciliation of `0.15.1` into the `fanout` skill, which
  described the same nonexistent plugin independently: `SKILL.md`'s "Orchestrator plugins" section
  and `context/findings-normalization.md` both listed `code-review` as one of three optional
  `claude-plugins-official` orchestrator plugins invoked as `/code-review:code-review`. `SKILL.md`
  now carries its own "Boundary" section for the two real surfaces, and
  `findings-normalization.md`'s per-surface parse-contracts table no longer lists `code-review` as
  a normalized fan-out leaf. Two `fanout` evals (`pr-comment-gate-opt-in`, renamed
  `unscored-surface-severity-derived-not-invented`) carried the same stale framing and were updated
  for internal consistency. The two surface descriptions are not restated — `SKILL.md` points at
  `pr.md`'s Boundary for those and carries only the fan-out-specific reasoning.
- `fanout`'s exclusion of the bundled command no longer rests on classing a **bare**
  `/code-review` invocation as PR-mutating. Per <https://code.claude.com/docs/en/code-review>
  ("Review a diff locally"), bare `/code-review` is report-only — findings arrive in the
  conversation, and only `--fix` and `--comment` mutate — matching the gate scoping `pr.md` already
  applies. The Boundary section now states the real reason it is not a normalized leaf (it is
  itself a multi-agent review of the same diff, with no documented output schema to write a parse
  contract against) and points the reader at running it directly (review-caught).
- The README's optional-orchestrator roster also names `codex` (OpenAI Codex marketplace), the
  other orchestrator `fanout` dispatches, and points at both skills' Boundary sections
  (review-caught).

## [0.15.1]

### Fixed

- Reconciled stale `code-review` framing in `quality-gate`'s `pr.md` and the plugin README: it
  described `code-review` as an optional `claude-plugins-official` marketplace plugin invoked as
  `/code-review:code-review`. Per current official docs, `/code-review` is a bundled built-in
  command (invoked bare) and the "parallel agents / posts PR comments" behavior actually
  describes the separate managed Code Review GitHub App service — neither is an installable
  marketplace plugin. `pr.md` now documents both surfaces distinctly under a Boundary section,
  mirroring the pattern `code.md` already uses for its own built-in boundary (#266/#735). The
  section's mutation gate covers only the surfaces that actually write — `--comment` (posts to the
  PR), `--fix` (mutates the working tree), and the managed service — leaving bare
  `/code-review <target>` ungated as a read-only option.

## [0.15.0]

### Added

- Deep-scan escalation routing to the official Claude Security plugin (`/claude-security`) from
  quality-gate security mode and the fanout leaf roster — presence-gated, pointer-only
  (contract stays upstream at <https://code.claude.com/docs/en/claude-security>), and explicitly
  not a fan-out leaf. The fanout pre-flight gate checks ask shape before diff resolution, so a
  whole-repo security-audit ask escalates regardless of diff state.

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
