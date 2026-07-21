---
name: babysit-prs
description: "Babysit your own open GitHub pull requests as a tiered fleet loop. The safe default discovers YOUR PRs under the current repo's owner, checks readiness, fixes clear branch-owned issues, and reports — it never resolves threads or merges. Explicit 'worker' tier adds auto-resolving outdated bot threads and gate-proven merges; explicit 'autopilot' adds all authors under the watched owners. Use when: 'babysit PRs', 'babysit my PRs', 'watch my open PRs', 'keep my PRs moving', 'advance all open PRs', 'babysit worker', 'run the PR queue on autopilot', or pairing with /loop for continuous coverage — not for the single-PR lifecycle: prep, create, monitor one PR, or merge (use /pull-request)."
user-invocable: true
disable-model-invocation: false
argument-hint: "[worker|autopilot|help] [owner/repo | #n | owner/repo#n] · default: configured default_tier (safe) over your own PRs; worker=fix+resolve-outdated+merge-ready; autopilot=max autonomy all authors; 'help' lists flows"
shell: bash
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Working tree status: !`git status --porcelain 2>/dev/null || echo "clean"`
Current login: !`gh api user --jq .login 2>/dev/null || echo "unknown"`
Own open PRs here: !`gh pr list --state open --author "@me" --limit 200 --json number --jq 'length' 2>/dev/null || echo "unknown"`

## Purpose

Keep pull requests moving without taking unsafe GitHub actions. Guarantees are enforced in
deterministic gate scripts; judgment stays with the agent. The safe default discovers your own
open PRs — author is one of your self logins — under the current repo's owner (or the configured
watched owners), works each to readiness, and reports. **The safe tier never resolves threads
and never merges**; merging exists only behind the explicit `worker`/`autopilot` opt-in and a
deterministic merge gate. Designed for `/loop /source-control:babysit-prs` continuous coverage.

The per-PR review discipline (finding extraction, per-finding D1–D7 verification gates,
self-reply filtering) is the plugin-scope seam shared with `/source-control:pull-request`:
[`${CLAUDE_PLUGIN_ROOT}/reference/review-discipline.md`](../../reference/review-discipline.md).
Read it before processing findings; dispatched workers cite it directly.

## Modes and arguments

An invocation is `[mode] [scope]`. Mode and scope are orthogonal — combine them freely
(`worker owner/repo`, `worker #87`, etc.).

| Mode | What it does |
| --- | --- |
| *(none)* — the configured `default_tier` (`safe` unless the consumer changed it) | Safe tier: discover in-scope PRs (your own, under the current repo's owner by default), check readiness, fix clear branch-owned issues and push, report blockers and the next cadence. Never resolves threads or merges. |
| `worker` | Everything safe does, and additionally auto-resolves *pre-push-outdated* bot threads and merges PRs the merge gate proves 100% ready. Requires Python. For dedicated 24/7 loops over your own PRs. |
| `autopilot` | Maximum autonomy for a solo owner: every open PR under the watched owners regardless of author; fix everything it can; resolve every thread it has addressed (bot, AI-review, and human); merge everything the gate proves ready. Requires Python. A deliberate power-user opt-in, never a default. |
| `help` (or `?`) | Print the common flows and the effective configuration below; take no other action. |

**Tier selection is explicit.** The tier keyword in the invocation wins. An explicitly typed
`/source-control:babysit-prs` invocation with no keyword — including inside `/loop` — runs the
configured `default_tier`, `safe` unless the consumer changed it. An auto-routed match (this
skill loaded from conversational vocabulary such as "babysit my PRs" rather than a typed
invocation) always runs the safe tier: `default_tier` never acts on auto-routed invocations, so
a merge-capable tier engages only when the user names it — the `worker`/`autopilot` keyword, or
a typed invocation under a deliberately changed `default_tier`. Configuration can never convert
a casual invocation into standing merge authority.

Any tier also honors an explicit user instruction to merge or resolve specific PRs now; that is
a direct order, not autonomous behavior, and it runs the same guarded gates below.

Common flows (this is what `help` prints, along with the effective configuration):

```text
/source-control:babysit-prs                     one pass at the configured default tier
/source-control:babysit-prs #87                 one PR in the current repo
/source-control:babysit-prs owner/repo          one repository
/source-control:babysit-prs owner/repo#87       one specific PR
/source-control:babysit-prs worker              full-auto (your PRs): fix + resolve-outdated + merge-ready
/source-control:babysit-prs autopilot           max autonomy: ALL authors, fix+resolve+merge, escalate stuck PRs
/source-control:babysit-prs help                list these flows and stop
Looped worker:    /loop 15m /source-control:babysit-prs worker
Looped autopilot: /loop 15m /source-control:babysit-prs autopilot
Explicit order (any tier): "merge owner/repo#87 now" | "resolve bot threads on #87"
```

## Scope resolution

Scope resolves deterministically, most specific first. Read the current git context with
`gh`/`git` (all read-only) before falling back:

1. **Explicit full ref** in the invocation (`owner/repo#N` or `owner/repo`) — use it exactly.
2. **Bare PR number** (`#87`, `pr 87`) inside a git repo — resolve the current repo with
   `gh repo view --json nameWithOwner -q .nameWithOwner` and target that `owner/repo#87`.
3. **Bare invocation inside a repo whose current branch has an open PR you authored** — target
   just that one PR (detect with `gh pr view --json number,url,author,headRefName`; use it only
   when the PR exists and its author is a self login).
4. **Bare invocation inside a repo under a watched owner** — that repository's own open PRs.
   When `watched_owners` is unset, the current repo's owner is the inferred watch scope.
5. **Otherwise** (a neutral working directory, or an unattended loop) — your own open PRs
   across every watched owner, via the snapshot's author filter.
6. **Conversation context** that clearly scopes specific PRs or repositories overrides the
   working-directory inference at any level.

Own-authorship is the default safety boundary, not a preference: never act on another person's
PR under the safe default. Widen beyond your own authorship ONLY on an explicit user
instruction or in `autopilot` — a deliberate opt-in that drops the author filter. The owner
allowlist (`watched_owners`, inferred as the current repo's owner when unset) is a separate,
always-on trust boundary: even autopilot never acts on a repository outside the watched owners.

## Autonomy tiers (per action class)

Autonomy is decomposed per action, not per run. Irreversibility governs the gate.

| Action class | Safe (default) | Worker | Autopilot |
| --- | --- | --- | --- |
| Discover, snapshot, report | yes | yes | yes, **all authors** |
| Fix clear branch-owned CI or bot-review issues, commit, push | yes | yes | yes, and harder (research a fix before giving up) |
| Dispatch a dedicated conflict-resolution worker (`git merge`, never rebase) | no — report (simple mechanical conflicts met while freshening a branch are still handled inline per [reference/loop.md](reference/loop.md)) | mechanical/textual conflicts only, escalate genuine ambiguity | mechanical/textual conflicts only, escalate genuine ambiguity |
| Resolve review threads | no — report | **pre-push-outdated bot threads only** | any thread **it has addressed** — bot, AI-review, or human |
| Merge a PR | no — report readiness | only when the gate proves 100% ready | only when the gate proves 100% ready |
| Mark a completed draft ready (`gh pr ready`) | no — report | no — report | yes, via its worker's completeness assessment |
| Refresh a stale (behind-base) branch, post a review trigger | orchestrator-only | orchestrator-only | orchestrator-only |
| `CHANGES_REQUESTED`, security/P1, posture, design, dependency acceptance | escalate | escalate | attempt with research; escalate only when it cannot confidently and safely resolve |

**Reading the merge-conflict blocker string.** The snapshot classifier is mode-agnostic by
design — it has no tier input — so it emits the same blocker string, `"merge conflict;
dedicated conflict-resolution agent required"`, for every conflicting PR regardless of tier.
That string names a capability that exists in this skill, not an instruction to invoke it. In
the safe tier the table's `no — report` still governs: report the blocker exactly as stated
and do not spawn the conflict worker. Only `worker` and `autopilot` read that same string as
license to act.

**Cross-tier invariants** — hold in every tier including autopilot: never an unprotected
force-push (a rebase integration pushes only `--force-with-lease` per
[reference/loop.md](reference/loop.md)); never `--admin`; never delete a branch or worktree
that is dirty or unmerged; never change GitHub settings, secrets, branch protection, or
billing; never act on a repository outside the watched owners; never resolve a thread whose
finding is not actually addressed. A merge always requires the deterministic gate — autopilot
works harder to reach that state but never forces past it. A blocked action escalates; it is
never routed around. Advisory-only fix attempts are bounded per PR (the fix-round cap in
[reference/orchestration.md](reference/orchestration.md)); blocking defects are never capped.
**Dependency hold-merge:** a dependency-manager-authored PR (Dependabot/Renovate-class) is
never merged autonomously in ANY tier — the merge gate refuses it absent `--allow-dependency`,
which is passed only on an explicit user instruction to merge that specific PR.

**Draft policy (per tier).** Drafts enter evaluation scope in every tier — there is no blanket
draft skip. Safe: evaluate and report draft status, never `gh pr ready`. Worker and autopilot:
zero-blocker drafts always route through a worker (see Fan out). `gh pr ready` happens only in
autopilot, only for a draft its worker assesses complete.

## Autopilot

`autopilot` is a deliberate, set-aside power-user tier for a **solo owner** who wants the queue
driven to zero — not the default, and not for a repo with other human reviewers whose feedback
must not be steamrolled. Its purpose is to never get stuck saying "nothing I can do": it
processes every PR, fixes what it can, and escalates only the specific PRs that genuinely need
a human. Per PR, in its own fresh worker, autopilot:

1. Fixes every issue it can — failing CI, mergeability, actionable review findings —
   researching a fix from authoritative sources before conceding, and pushing to the PR branch.

2. Addresses each open review thread, then resolves it through the guarded resolve-thread wrapper
   (`--resolve --include-human` — bot, AI-review, and human threads alike); the exact command is
   the single home in [reference/safety.md](reference/safety.md). The order is
   load-bearing: **address the finding first, then resolve.** A thread is resolved only because
   its concern is fixed or confirmed stale — never to clear the merge gate over a live concern.
   After running, parse the JSON output and confirm each addressed thread's entry shows
   `"action": "resolved"` before treating it as cleared — never the exit code alone.

3. After the worker's final push, takes a fresh post-push snapshot (or uses the exact pushed
   commit after vetting it), then merges on that post-push head through the pinned
   `source-control-babysit-merge` gate once it proves the PR ready. The exact command — and the
   `--autopilot-merge-tier` flags the enabled tier layers on so an enabled config never merges
   via the base path — is the single home in [reference/safety.md](reference/safety.md). Never
   reuse the pre-worker snapshot pin after a push. The gate is never bypassed; if a PR cannot be
   made ready, autopilot reports that one PR and moves on.

"Every PR" means every PR: the orchestrator's own priority judgment is never grounds to leave
a queue member untouched. The only permitted exclusions are the deterministic ones — lease
contention, the owner allowlist, `mutation_policy.branch_write_allowed`, and the `needs_worker`
delta gate skipping a PR that has not materially changed since it was last handled. A PR the
coordinator judges lower-priority still gets its cycle; it is sequenced, never silently dropped
from the fan-out.

**Draft PRs** are in scope, not exempt. Its worker assesses whether the draft's work is
actually complete: if so, mark it ready for review (`gh pr ready`) and continue through the
normal fix/resolve/merge steps in the same cycle; if it is genuinely still in progress, leave
it draft and report why — that is a real escalation with a reason, not a silent skip.

Autopilot keeps every cross-tier invariant above — including dependency hold-merge. It widens
*author* scope (all authors under the watched owners) and *thread* scope (`--include-human`);
it does **not** widen the owner allowlist, and it does not gain force-push, `--admin`, or
settings powers — those still escalate. Run it looped:
`/loop 15m /source-control:babysit-prs autopilot`.

## Autopilot merge tier (#476)

A config-gated escalation of autopilot's merge authority, **shipped DISABLED** and active only while the operator sets `babysit_autopilot_merge_tier` (enabling it, and the later gate-off flip, are separate announced steps; without it every merge decision is exactly today's). When enabled, per candidate PR autopilot runs a **genuine review pass** under a **second bot account** (author ≠ approver) that submits an approving review **only when clean**, then runs the pinned merge gate with the `--autopilot-merge-tier` flags layered onto `--merge --expected-head <post-push-head-sha>`. The concrete enabled-path merge command, the second-account approve mechanic, and the review-workflow requiredness precondition for enabling the tier are the single home in [reference/safety.md](reference/safety.md).
That gate merges **only when every criterion holds** — the criteria and the safety-contract rationale are codified in [reference/safety.md](reference/safety.md). It is **fail-closed** (the umbrella flag refuses unless all three parameter sets are supplied; predicates reused from the shared `babysit_classify` module), and any criterion failing falls back to the human merge-ready list — the tier never routes around the gate.

## Guarded mutations: deterministic gates, agent judgment

The two mutation gates are invoked ONLY through their wrapper scripts, by the bundled `bin/`-path
form — never the bare command name nor the raw Python behind them. The exact form is the single
home in [reference/safety.md](reference/safety.md). Both fail closed without `--allowed-owners`.

- **Merge readiness** — `source-control-babysit-merge owner/repo#N --allowed-owners
  <watched-owners> --self-logins @me,<self-logins>` (read-only; add `--merge --expected-head
  <vetted-head-sha>` to merge, and `--method <merge-method>` when configured). `--self-logins`
  exempts your own PRs from the unprotected-base hold: `@me` resolves to your gh login, plus any
  `babysit_self_logins` extras (drop the trailing `,<self-logins>` when that value is empty). It gates on GitHub's own
  `mergeStateStatus == CLEAN` plus explicit cross-checks (branch rules, review decision,
  unresolved threads, check rollup keyed by check type and name, head match) and reports the
  exact `blockers`. If the expected-head pin is missing or no longer matches the live head, the
  gate refuses the merge; re-snapshot and reassess the new head instead of using
  `--allow-unpinned-head` — the wrapper rejects that flag outright, so no unattended unpinned
  merge exists. The pin is carried to GitHub's server-side match-head-commit guard. It refuses
  a dependency-manager-authored PR absent `--allow-dependency`, refuses merge on an unprotected
  repo (zero required reviews and zero required contexts) for a non-self author absent
  `--allow-unprotected`, never uses `--admin`, and cannot resolve threads, reply, or
  force-push. React to `blockers`; do not bypass the gate. A `ready:false` immediately
  following a `ready:true` on the same expected head is often GitHub's own mergeability
  recompute lag — re-run the read-only check once before treating it as a real block.

- **Once ready, stop.** When the gate proves a PR ready (safe mode) or its merge is deferred to
  a human (Pinned-Command Degradation, [reference/safety.md](reference/safety.md)), report that
  outcome and end the PR's cycle. The no-background-monitor clause (Worker Contract,
  [reference/orchestration.md](reference/orchestration.md)) governs this gate-completion step
  exactly as it governs a worker's turn — proving readiness is never a license to arm a watch.

- **Thread resolution** — `source-control-babysit-resolve-thread owner/repo#N
  --allowed-owners <watched-owners>` (lists by default; add `--resolve`). By default it touches
  only bot-authored threads (structural `__typename == "Bot"` or the `[bot]` login suffix — no
  hardcoded identity list) and never a human thread. In worker tier pass `--autonomous`, which
  resolves only threads GitHub marks `isOutdated`, each pinned via `--expected-comment-count` and
  `--expected-last-updated`. Those pins enforce comment-state only — they block a thread whose
  comment count or latest comment-edit timestamp drifted after vetting. The worker must
  additionally confine resolves to threads already outdated in the PRE-push snapshot
  ([reference/orchestration.md](reference/orchestration.md)); that pre-push-outdated rule is agent
  discipline, not machine-enforced, so a thread a worker's own push merely displaced (`isOutdated`
  flipped while both comment pins still match) is still resolvable — the machine-enforced fix for
  that displacement bypass is tracked in #571.
  In autopilot pass `--resolve --include-human` for threads the agent has addressed; the
  script still cannot merge, reply, or dismiss reviews. Never treat exit code 0 alone as proof
  a specific thread was resolved — always parse the per-thread JSON `action` field
  (`resolved` vs `skipped-*` / `refused-stale-pin` / `resolve-failed`) and the
  `resolvedCount`/`eligibleCount` summary before reporting or re-checking the merge gate.
  `--resolve --thread-id` without matching `--expected-comment-count` and
  `--expected-last-updated` (or an explicit `--allow-unpinned-thread` override) is refused
  before anything is fetched or resolved.

- **The agent** decides severity (is this security/P1?), whether a finding is genuinely
  addressed, what a label means, and every fix-vs-escalate call — never a script. Escalate a
  security/P1 thread instead of resolving it, even in autopilot.

## Fan out: one fresh worker per PR that needs one, per cycle

Engine-backed runs (Python present) process the queue as one bounded cycle: snapshot the queue,
handle orchestrator-only transitions (stale-branch refresh, review triggers) and global cleanup
while holding the queue lease, then spawn one fresh, unbiased sub-agent per actionable PR up to
the concurrency cap. "Actionable" is every open in-scope PR the snapshot returns, narrowed only
by the deterministic exclusions — lease contention, the owner allowlist,
`mutation_policy.branch_write_allowed`, and the snapshot's `needs_worker` delta gate — never by
the orchestrator's own priority judgment. Full mechanics, the worker contract, and the prompt
template (untrusted PR fields fenced as data) are in
[reference/orchestration.md](reference/orchestration.md).

A PR that is merely unchanged since the last cycle — even one still reporting blockers it was
already escalated for — does not get a fresh worker. A non-draft PR with zero blockers **and no
untriaged material feedback** also gets no worker, only a direct mode-appropriate
`source-control-babysit-merge` gate check; that is coverage, not a skip — a PR still carrying
untriaged material findings defers to the snapshot's `needs_worker` signal instead. In default
(safe) mode, run the gate without `--merge` and report readiness without merging. Pass
`--merge --expected-head <snapshotted-head-sha>` only in `worker` or `autopilot` mode, or under
an explicit user order to merge that PR — but an enabled autopilot merge tier adds the tier flags
([reference/safety.md](reference/safety.md)), never the flagless base command. Use the exact head
SHA from the snapshot; a missing or stale pin must refuse the merge and send the PR back through
snapshot and assessment, never an unattended unpinned override.

**Zero-blocker drafts are the exception:** always route them through a worker, never directly
to the merge gate. In autopilot, that worker assesses whether the draft is complete: a
completed draft is marked ready with `gh pr ready` and continues through the normal guarded
path; a genuinely in-progress draft stays draft and is reported and escalated with the reason.
GitHub's
[draft-stage contract](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/changing-the-stage-of-a-pull-request)
confirms a draft cannot merge until it is marked ready. Completeness of the diff is not the
only hold reason: an explicit unchecked human-only item named in the PR's own body holds the
draft too, even when the content is finished and green — see the worker contract in
[reference/orchestration.md](reference/orchestration.md).

Each per-PR worker owns its local lifecycle end to end: acquire that PR's worker lease and its
own isolated worktree (find or create, never a shared checkout), check out and freshen the PR
branch, make only clear branch-owned fixes, re-check the head SHA, push, clean up on merge
(worktree + local branch), and release the lease. Worktree policy:
[reference/worktrees.md](reference/worktrees.md).

## Effective configuration (substituted at load)

The values below substitute from this plugin's stored configuration when this skill loads.
A surviving literal `${user_config.…}` placeholder means that key is unset — apply its
documented unset behavior. Reference files use `<angle-bracket>` slots; fill every slot from
this block. Values reach scripts ONLY as explicit CLI flags (option environment variables never
reach skill-invoked scripts). Configuration selects targets and thresholds; it never widens tier authority.

| Key | Value | Flag delivery | Unset behavior |
| --- | --- | --- | --- |
| `babysit_watched_owners` | `${user_config.babysit_watched_owners}` | `--owners` (snapshot), `--allowed-owners` (both wrappers, fail-closed) | infer the current repo's owner |
| `babysit_self_logins` | `${user_config.babysit_self_logins}` | `--extra-self` (readiness gate and snapshot); `--self-logins` (merge gate) | none — always added to your `gh api user --jq .login` login |
| `babysit_intended_write_identity` | `${user_config.babysit_intended_write_identity}` | `--intended-write-identity` (snapshot) | attribution-drift check dormant |
| `babysit_default_tier` | `${user_config.babysit_default_tier}` | prose only — tier of explicit bare invocations | `safe` |
| `babysit_merge_method` | `${user_config.babysit_merge_method}` | `--method` (merge wrapper) | repo convention, then squash |
| `babysit_autopilot_merge_tier` | `${user_config.babysit_autopilot_merge_tier}` | prose only — gates whether the tier's `--autopilot-merge-tier` merge flags are wired at all | `false` (tier disabled; PRs go to the human merge-ready list) |
| `babysit_lane_logins` | `${user_config.babysit_lane_logins}` | `--lane-logins` (merge wrapper, autopilot merge tier) | tier refuses fail-closed when enabled |
| `babysit_approver_bot_logins` | `${user_config.babysit_approver_bot_logins}` | `--approver-bot-logins` (merge wrapper, autopilot merge tier) | tier refuses fail-closed when enabled |
| `babysit_merge_block_labels` | `${user_config.babysit_merge_block_labels}` | `--block-labels` (merge wrapper, autopilot merge tier) | tier refuses fail-closed when enabled |
| `babysit_review_trigger_phrase` | `${user_config.babysit_review_trigger_phrase}` | `--trigger-phrase` (snapshot, request_review) | review-trigger module dormant |
| `babysit_review_bot_logins` | `${user_config.babysit_review_bot_logins}` | `--review-bot-logins` (snapshot, request_review) | review-trigger module dormant |
| `babysit_review_gate_context` | `${user_config.babysit_review_gate_context}` | `--review-gate-context` (snapshot) | gate treated as absent |
| `babysit_ci_gateway_context` | `${user_config.babysit_ci_gateway_context}` | `--ci-gateway-context` (snapshot) | gateway check unused |
| `babysit_extra_bot_logins` | `${user_config.babysit_extra_bot_logins}` | `--extra-bot-logins` (snapshot) | structural bot detection only |
| `babysit_approval_downgrade_logins` | `${user_config.babysit_approval_downgrade_logins}` | `--approval-downgrade-logins` (snapshot) | an approval carrying blocking-looking prose is downgraded to ignored structurally (every bot); a named login instead surfaces its own as material. Real APPROVED-state reviews and plain clean approvals are ignored regardless. |
| `babysit_skip_downgrade_logins` | `${user_config.babysit_skip_downgrade_logins}` | `--skip-downgrade-logins` (snapshot) | downgrade heuristic dormant |
| `babysit_max_quiet_recheck_seconds` | `${user_config.babysit_max_quiet_recheck_seconds}` | `--max-quiet-recheck-seconds` (snapshot) | `14400` |
| `babysit_stuck_check_age_seconds` | `${user_config.babysit_stuck_check_age_seconds}` | `--stuck-check-age-seconds` (snapshot) | `1800` |
| `babysit_advisory_fix_round_cap` | `${user_config.babysit_advisory_fix_round_cap}` | `--fix-round-cap` (snapshot, ledger) | `100` |
| `babysit_worker_concurrency_cap` | `${user_config.babysit_worker_concurrency_cap}` | prose only — fan-out bound | `10` |
| `babysit_worktree_root` | `${user_config.babysit_worktree_root}` | `--root` (prune; worktree creation) | `${CLAUDE_PLUGIN_DATA}/worktrees` |
| state dir (not configurable) | `${CLAUDE_PLUGIN_DATA}/state/babysit-prs` | `--state-dir` (every state-touching script) | — |

Configure via the `/plugin` dialog, or headless at install time with
`claude plugin install --config KEY=VALUE`; `/source-control:setup` documents both plus the
environment probes.

## Engine and degrade

The snapshot engine and gates are Python (stdlib-only) under
`${CLAUDE_PLUGIN_ROOT}/skills/babysit-prs/scripts/`; every script ships `--help`. Python is a
declared prerequisite for `worker` and `autopilot` (and for engine-backed safe runs): when it
is absent, `worker`/`autopilot` STOP at entry with a concise remediation message naming the
prerequisite, and the safe tier degrades gracefully to the Python-free loop in
[reference/loop.md](reference/loop.md) — discovery via `gh pr list`, readiness via the
plugin-scope gate script, cadence via the static ladder. Never block a safe iteration on the
engine's absence.

## Per-PR checklist (safe core — each PR, every iteration)

Execute for EACH PR discovered, oldest first. Detailed mechanics:
[reference/loop.md](reference/loop.md).

- [ ] **Step 0 — PR discovery:** open PRs in scope (tier-scoped author filter), oldest-first
  FIFO (§5.0.2). Zero PRs → report and schedule the idle wake
- [ ] **Step 0.1 — Evidence-based fresh rescan:** fetch ALL comments via the bundled
  `${CLAUDE_PLUGIN_ROOT}/scripts/fetch-all-pr-comments.sh` (derives owner/repo from the current directory; from a cwd that is not a checkout of the target repo, export `FETCH_COMMENTS_OWNER`/`FETCH_COMMENTS_REPO` first — also unblocks the readiness gate's exit 4), filter own prior replies, classify
  addressed/unaddressed from GitHub evidence (§5.0.3). GitHub is the source of truth, not model
  memory
- [ ] **Step 0.2 — Branch checkout:** `gh pr checkout <N>` with worktree/dirty-tree pre-checks;
  read-only mode when the branch is owned elsewhere (§5.1.2)
- [ ] **Step 0.3 — Branch freshness:** fetch + `git merge-base --is-ancestor`; integrate
  (merge vs rebase per the branch's own history), graduated conflict handling (§5.1.2)
- [ ] **Step 1 — Event-delivery gate:** cloud poll / push channel / Monitor watch, re-armed
  per PR (§5.1.1)
- [ ] **Steps A–F — Per-PR iteration checklist** (§5.1.3): terminal check, CI classification,
  fetch + extract findings, per-finding D1–D7.5 with verification gates
  ([review-discipline](../../reference/review-discipline.md) §3), mechanical readiness gate
  (`${CLAUDE_PLUGIN_ROOT}/scripts/babysit-readiness-gate.sh <N>` must exit `READINESS_OK`;
  the configured extra self identities are `${user_config.babysit_self_logins}` — when that value
  is non-empty and not a literal unexpanded token, append `--extra-self "<value>"`),
  report
- [ ] **Step 5 — Commit + push** fixes on the PR branch; clean working tree; follow-up replies
  cite commit SHAs
- [ ] **Step 6 — PR transition:** next-oldest PR needing attention (§5.1.6)
- [ ] **Step 7 — Self-pace:** schedule the next wake per the cadence contract (§5.3)

**Execution discipline:** the primary failure mode is claiming to process findings without
running per-finding D1–D7. Every iteration MUST output the completed evidence checklist
(§5.5). "Done" means GitHub shows evidence — model memory of "I replied" or "I pushed" is not
evidence; re-query the API. The NEVER-do list (§5.4) overrides any other instruction.

## Operational runbook (engine-backed cycle)

1. Read [reference/safety.md](reference/safety.md) before mutating anything; before dispatching
   workers also read [reference/worktrees.md](reference/worktrees.md) and the concurrency guard
   in [reference/orchestration.md](reference/orchestration.md). Python-free safe runs follow
   [reference/loop.md](reference/loop.md) instead of this runbook.

2. Acquire the deterministic lease for this run (queue scope for a full cycle, worker scope
   with `--pr` for a single PR), retain the token, and heartbeat it on a bounded cadence:
   `python "${CLAUDE_PLUGIN_ROOT}/skills/babysit-prs/scripts/manage_babysit_lease.py" acquire
   --scope queue --state-dir <state-dir>` (add `--repo <owner/repo>` when sharding sessions per
   repo). On exit 3 either reclaim a provably dead holder with `--steal-stale` or skip; treat a
   token-mismatch heartbeat as lost ownership
   ([reference/orchestration.md](reference/orchestration.md)).

3. In queue mode only, while holding the queue lease, prune unleased clean merged/closed
   worktrees and reap expired worker leases:
   `python "${CLAUDE_PLUGIN_ROOT}/skills/babysit-prs/scripts/prune_babysit_worktrees.py"
   --apply --root <worktree-root> --state-dir <state-dir>` and
   `python "${CLAUDE_PLUGIN_ROOT}/skills/babysit-prs/scripts/manage_babysit_lease.py" reap
   --apply --state-dir <state-dir>`.

4. Run the snapshot with the tier's scope:
   `python "${CLAUDE_PLUGIN_ROOT}/skills/babysit-prs/scripts/pr_queue_snapshot.py" --queue
   --author @me --owners <watched-owners> --state-dir <state-dir> --write-state`
   (the `@me` scopes discovery to your own gh login; when `babysit_self_logins` is non-empty and not a
   literal unexpanded token, append `--extra-self <self-logins>` — those extra posting identities join
   the self-suppression set independently of `--author`, surviving autopilot widening; when
   `babysit_intended_write_identity` is set and not a literal unexpanded token, append
   `--intended-write-identity <intended-write-identity>` so a wrong-self-login write surfaces as
   attribution drift; append review-trigger flags only when configured; `--pr owner/repo#N` (single PR)
   or `--repo <owner/repo-csv>` (sharded); drop `--author` only to widen — self-suppression no longer rides on it).
   Capture the prior cycle's `generated_at` per
   [reference/cadence.md](reference/cadence.md) before writing new state.

5. Decide per PR from the snapshot's `classification`, `needs_worker`, `recommended_cadence`,
   and `material_findings`: delegate a worker (only when `needs_worker` is true), act locally,
   report, back off, or escalate. Load [reference/freshness.md](reference/freshness.md) only
   when a branch is behind, [reference/stuck-checks.md](reference/stuck-checks.md) only when a PR's `checks.stuck` is non-empty (escalate the routing, never auto-fix),
   [reference/feedback.md](reference/feedback.md) and
   [reference/review-trigger.md](reference/review-trigger.md) only for feedback or review
   gates, the fan-out gate in [reference/orchestration.md](reference/orchestration.md) only
   before assigning workers, and [reference/cadence.md](reference/cadence.md) only before
   recommending cadence.

6. Process stale-branch refreshes and review-trigger posts as orchestrator-only actions before
   assigning workers; each is terminal for that PR's cycle until a later snapshot observes its
   new head ([reference/freshness.md](reference/freshness.md),
   [reference/review-trigger.md](reference/review-trigger.md)).

7. In worker mode, after a worker's fix is pushed and its checks are green, take a fresh
   post-push snapshot (or use the exact pushed commit after the worker has vetted that commit),
   then run the merge gate with `--merge --expected-head <post-push-head-sha>` only when it
   reports ready. Never reuse the pre-worker snapshot pin after the head moves. Resolve
   pre-push-outdated bot threads that block the gate — once the agent has confirmed they are not
   security/P1 — as a per-thread vetted loop: one `--autonomous --resolve --thread-id <id>
   --expected-comment-count <n> --expected-last-updated <ts>` call per thread, pins taken from the
   same snapshot that vetted it. `--autonomous --resolve` refuses a bulk (no `--thread-id`) call,
   so the comment-state pins are always enforced (a reply or edit after vetting blocks the
   resolve). Those pins do NOT catch displacement — a push that flips `isOutdated` while the
   comment count and last-updated still match is still resolved — so keeping such a thread
   unresolved rests on the pre-push-outdated agent-discipline rule, with the machine-enforced fix
   tracked in #571. In autopilot, after addressing
   the findings, additionally resolve AI-review and human threads with `--resolve --include-human`,
   then run the same pinned merge gate — the gate is never bypassed. After any `--resolve` run,
   parse its JSON output (per-thread `action`, and `resolvedCount`) before re-running the merge gate.

8. After each PR is integrated, prune only that PR's clean worktree with `--pr`,
   `--lease-token`, and `--prune-open-clean`, delete its local feature branch on merge, then
   release its worker lease. Never globally prune open-PR worktrees. Release the queue lease in
   finally-style cleanup.

9. Schedule the next wake from the snapshot's `recommended_cadence`
   ([reference/cadence.md](reference/cadence.md)); the static ladder in
   [reference/loop.md](reference/loop.md) §5.3 is the Python-free degrade.

## Reporting

Report only material findings, one line per materially changed or blocked PR:

```text
repo#number (@author) | checks | action | open items
```

Material findings: fixes committed or pushed; new failing or pending required checks; new
blocking bot feedback; new ordinary human comments (one notification per stable comment ID,
never an automatic reply); PRs merged; a PR the host runtime's permission layer left "ready,
awaiting human execution" with its exact pinned command
([reference/safety.md](reference/safety.md)); escalations that need a user decision; and
suspicious state changes such as missing permissions, changed branch protection, merge
conflicts, or a head SHA that moved during work. When nothing materially changed, stay silent.
Recommend the exact next interval per [reference/cadence.md](reference/cadence.md).

## Gotchas

Failure patterns observed in real babysit sessions:

- **Survey-without-classifying is the #1 failure.** An audited run classified 16 of ~32 findings
  while reporting completion — prose "MANDATORY" alone under-decomposes. That is why readiness is
  gated by `babysit-readiness-gate.sh` exit code, not by the model's claim
- **Multi-finding comments glossed as one work item.** A single comment carrying N severity
  markers is N work items; ≥3 findings REQUIRE the extractor-subagent dispatch
  ([review-discipline](../../reference/review-discipline.md) §2)
- **Model memory across compaction is not state.** "I already replied/pushed" without an API
  re-query has produced false completion claims — GitHub is the state store
- **Exploring the wrong branch produces wrong classifications.** Findings validated off the PR
  branch have been confidently wrong — checkout is mandatory before D2
- **Own prior replies re-processed as findings.** Classification-table replies from your own
  posting identities must be filtered during rescan or the loop chases its own tail
  ([review-discipline](../../reference/review-discipline.md) §1)
- **Exit codes are not per-thread outcomes.** Both wrappers demand JSON `action`-field parsing;
  a zero exit covers skipped and refused threads too
- **Self-blocking CI check.** A newly required check whose own fix PR carries that same check
  cannot be gate-merged — the check is failing or absent on the very PR that would make it pass,
  so the merge gate correctly refuses. Breaking the cycle is a one-time human admin-merge
  bootstrap of that fix PR; no tier automates it. Surface it as a blocker needing that bootstrap,
  never as a reason to route around the gate

## References

- [reference/loop.md](reference/loop.md) — the safe-tier iteration loop (also the Python-free
  degrade path): discovery, checkout, freshness, checklist, static cadence ladder.
- [reference/orchestration.md](reference/orchestration.md) — fan-out gate (`needs_worker` arms), concurrency cap, leases, worker contract + prompt template, conflict resolution, cleanup.
- [reference/cadence.md](reference/cadence.md) — active/normal/quiet/idle cadence states,
  real-elapsed-time detection, bounded full-sweep interval, persisted counters.
- [reference/freshness.md](reference/freshness.md) — guarded refresh for behind-base branches,
  BLOCKED compare fallback, async-update terminality.
- [reference/stuck-checks.md](reference/stuck-checks.md) — the `checks.stuck` signal (checks holding `mergeStateStatus` at UNSTABLE without completing) and its escalation routing; report, never auto-fix.
- [reference/review-trigger.md](reference/review-trigger.md) — generalized AI-review trigger +
  gate semantics; dormant when unconfigured.
- [reference/worktrees.md](reference/worktrees.md) — ephemeral worktree policy and prune commands.
- [reference/safety.md](reference/safety.md) — role boundaries, verify-before-escalate, the
  harness permission layer (pinned-command degradation), stop-ask and never-do lists.
- [reference/feedback.md](reference/feedback.md) — feedback classification, dispositions,
  advisory cap, bot-PR taxonomy, human-feedback policy.
- [`${CLAUDE_PLUGIN_ROOT}/reference/review-discipline.md`](../../reference/review-discipline.md)
  — the plugin-scope per-PR review discipline shared with `/source-control:pull-request`.
