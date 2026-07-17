---
name: pull-request
description: "Orchestrate the full PR lifecycle: prep (review + verify), create, monitor CI + review comments, merge, and fetch CI logs. Use when: 'create pr', 'ship it', 'pr prep', 'fix CI', 'address comments', 'monitor PR', 'merge this', 'check pr status' — not for the all-PR babysit loop (use /babysit-prs), branch/worktree lifecycle (use /worktree), or committing without a PR (use /commit)."
user-invocable: true
disable-model-invocation: false
argument-hint: "<action> [args] (e.g., /pull-request prep, /pull-request create, /pull-request monitor, /pull-request merge, /pull-request full, /pull-request status)"
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Recent commits: !`git log --oneline -5 2>/dev/null || echo "no commits"`
Working tree status: !`git status --porcelain 2>/dev/null || echo "clean"`
Changed files (staged+unstaged): !`git diff --name-only HEAD 2>/dev/null || echo "none"`

## Purpose

Orchestrate the PR lifecycle from quality review through merge and cleanup, with smart state detection and resume capability.

**The two non-negotiable gates:**

1. **Finding verification** (prep phase) — agent review findings have a demonstrated error rate. Every finding is verified against current docs and actual code before being presented to the user.
2. **Research-gated CI fixes** (monitor phase) — no code fix without researched multi-source consensus on the root cause. Unresearched "obvious" CI fixes are how wrong fixes ship.

## Adapting to your environment (graceful degrade)

This skill is self-contained: it runs on `git`, `gh`, and its bundled scripts (skill-private ones under `${CLAUDE_PLUGIN_ROOT}/skills/pull-request/scripts/`, plugin-shared ones under `${CLAUDE_PLUGIN_ROOT}/scripts/`). Where a phase names an adjacent capability — a code-review skill or agents, a simplifier, a build/test/lint verifier, an external research skill, an exploration skill, a work-item tracker, a CI-log-audit agent, a GitHub-events push channel — treat it as **optional**: if your environment provides it (a skill, plugin, agent, or MCP server), invoke it; otherwise proceed with the inline guidance, which stands on its own. Never block a phase because an adjacent tool is absent.

Consumer conventions come from the consuming project's own `CLAUDE.md`, `AGENTS.md`, and rules — notably: PR body template, branch naming, merge style (this skill defaults to squash), review-reply identity (some projects post bot-identity replies via a wrapper; default is plain `gh`), and any extra pre-PR gates. Read them before creating or merging.

**PR title format** resolves via the same ladder `/commit` uses for the commit subject (see its SKILL.md), checked in order: `.claude/source-control.md`'s `pr_title_pattern` (when present, written by `/source-control:setup`) → the consuming project's own `CLAUDE.md`/`AGENTS.md`/rules → Conventional Commits (11-type vocabulary — `build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test`; confirmed via the spec, the Angular convention, commitlint's `@commitlint/config-conventional`, and `amannn/action-semantic-pull-request`'s default `types` — `security` is not a member of any of these) as the default. See [reference/create.md](reference/create.md) §2.4.1 for where the title is derived. When no config exists and nothing is inferable, point the user at `/source-control:setup`.

## Emit checklist

For PR lifecycle runs spanning 3+ phases, copy `${CLAUDE_PLUGIN_ROOT}/skills/pull-request/templates/checklist.md` into your project's working-notes location (or track it inline) and tick each `- [ ]` as the phase produces its output. Stateful surface; survives `/clear`.

## Arguments

`$ARGUMENTS` — action selector:

| Action | Entry point | Use case |
|--------|-------------|----------|
| *(empty)* | Smart default | Detect current state, resume from right phase |
| `prep` | Phase 1 | Review + verify findings + simplify + verify build |
| `prep quick` | Phase 1 (fast) | Code errors only, skip simplify |
| `prep review-only` | Phase 1 (partial) | Just review + verify findings |
| `prep simplify-only` | Phase 1 (partial) | Just simplify + re-verify |
| `create` | Phase 2 | Branch-name check + commit + push + `gh pr create`. Reports the PR URL and stops |
| `monitor` | Phase 3 | Watch CI, fix failures, evaluate comments. **Three-tier event delivery: (1) push channel** when your environment ships a GitHub-events channel (an MCP server delivering webhook events into the session) — ~0 idle requests; **(2) Monitor tool** fallback (30s `gh` poll); **(3) plain `gh` polling** in cloud/headless sessions. Check the push channel FIRST per [monitor.md](reference/monitor.md) §3.0.05 before falling back |
| `comments` | Phase 3.5 | Evaluate/respond to PR comments only |
| `merge` | Phase 4 | Squash merge + worktree cleanup + verify |
| `status` | Report only | Unified status across all phases |
| `full` | Phase 1-4 | Run prep → create → monitor → merge end-to-end |
| `fetch-logs <pr\|run> [--raw\|--job <job-id>]` | CI log retrieval | Pull failed-CI evidence: default = `::error`/`::warning` annotations only (cheapest); `--raw` = full ZIP dump for archive review; `--job <id>` = per-job plain text |

For the all-PR continuous loop (discover every open PR, work each to readiness, self-pace), use
the sibling skill `/source-control:babysit-prs` — it wraps this skill's per-PR review discipline
in fleet orchestration and never merges.

## Action defaults

- **Merge mode:** `merge` squash-merges (one squashed commit per PR onto the default branch) — see [reference/merge.md](reference/merge.md) §4.2. Follow the consuming project's convention when it differs.
- **Monitor cadence:** `monitor` polls `gh pr checks` and comment fetches every 30 seconds — see [reference/monitor.md](reference/monitor.md) §3.1.
- **Required reviewers:** `create` requests no reviewers (runs `gh pr create` without `--reviewer`) — see [reference/create.md](reference/create.md) §2.4.3.

## PR identity resolution

PR identity (number, URL) resolves **live via `gh` CLI** at every phase that needs it — `gh` is the authoritative source. No caching, no state files.

**Standard pattern** (used in every phase):

```bash
PR_NUMBER=$(gh pr view --json number -q '.number')
```

When `gh pr view` (no positional arg) is ambiguous — multiple open PRs, stale checkout, returning days later — pass the branch explicitly:

```bash
PR_NUMBER=$(gh pr view "$(git branch --show-current)" --json number -q '.number')
```

After resolving once at phase entry, **pass `<pr_number>` explicitly to all subsequent `gh` calls** within that phase (`gh pr checks <pr_number>`, `gh pr merge <pr_number>`, etc.). Never rely on bare-branch resolution mid-phase.

**Why explicit PR numbers?** `gh pr view` (no args) resolves by HEAD branch — fragile when: the worktree was cleaned up (branch context lost), multiple open PRs exist (wrong match), returning days later (stale checkout), or another session's PR merged first. Resolving once at phase entry and threading the number through bounds this risk to one point per phase.

---

## Phase 0: Parse action and detect state

Parse `$ARGUMENTS` to extract the action (first token) and any sub-arguments.

**Smart default** (empty args): read live state via `gh` to determine the right phase:

```text
1. Check git branch — on the default branch? → "Create a worktree or branch first"
2. Resolve PR for current branch:
   gh pr view --json state,number 2>/dev/null
   a. exit non-zero → no PR yet → START AT PHASE 1 (prep); skip steps 3-6
      entirely (they all need a PR number that does not exist yet)
   b. state = MERGED → skip to Phase 4.3 (cleanup only — pull default branch, delete branch, prune)
   c. state = CLOSED → report "PR was closed without merging" and stop
   d. state = OPEN → capture pr_number, continue to step 3
3. Check CI status (gh pr checks <pr_number>) — still running? → start at monitor
5. Check for unaddressed comments → start at monitor (comments sub-phase)
6. CI green + comments addressed → suggest merge
```

Present detected state and proceed to the appropriate phase. In interactive mode, announce which phase is starting. In autonomous mode (`full`), proceed without pausing — phase transitions are not decision points.

**Status action**: query `gh pr view --json number,url,state` for PR number/URL, then report current state across all phases.

---

## Phases

Execute in order. Each phase is self-contained — read the relevant file for detailed steps:

| Phase | File | Entry actions |
|-------|------|--------------|
| 1. Prep | [reference/prep.md](reference/prep.md) | `prep`, `prep quick`, `prep review-only`, `prep simplify-only` |
| 2. Create | [reference/create.md](reference/create.md) | `create` |
| 3. Monitor | [reference/monitor.md](reference/monitor.md) | `monitor`, `comments` |
| 4. Merge | [reference/merge.md](reference/merge.md) | `merge` |

---

## Monitor entry checklist (MANDATORY — execute in order before ANY monitoring work)

When entering Phase 3 (`monitor`, `comments`, or `full` reaching monitor), complete EVERY step below. Do NOT skip to CI polling or comment evaluation.

- [ ] **Step 0 — Checkout the PR source branch (DEFAULT):** monitoring a PR means working ON its head branch — exploration, research, and any fix must run against the PR's actual code, not whatever branch you happen to be on. Check it out with `gh pr checkout <N>` (fork-safe — a fork's head branch is not fetchable from `origin` by name, and a bare `git checkout <headRefName>` can select a stale same-named local branch). This is the default, not an exception.
  - **Pre-check `git worktree list`:** if the branch is already checked out in another worktree, work there (or process read-only — no fix — if you can't). If you're already on the PR branch, no-op.
  - **Dirty tree with unrelated WIP** (staged/unstaged/untracked from other work): do NOT switch — surface the WIP to the user and proceed read-only. Never `git stash` another session's WIP.
  - **Interactive session** (human present): changing branches re-points the working tree, so confirm the target branch with the user FIRST — UNLESS the invoking message already named the checkout (invoking `/pull-request monitor <N>` against a specific PR is intent, but the target-branch confirmation gate still governs the mechanical switch).
  - **Autonomous session** (e.g. `CLAUDE_CODE_REMOTE=true`): check out without prompting.
  - **`/source-control:babysit-prs`** runs its own per-PR checkout — this Step 0 is the single-PR `monitor` equivalent; don't double-checkout when the sibling loop skill applies this checklist.
- [ ] **Step 1 — Cloud check:** if `CLAUDE_CODE_REMOTE=true`, use §3.0.0 `gh` polling. Skip remaining steps
- [ ] **Step 2 — Push-channel gate (§3.0.05):** if your environment ships a GitHub-events push channel (an MCP server that delivers webhook events into the session), verify it is healthy per its own docs and this skill's §3.0.05 guidance (broker alive, subscriber fresh). No channel available → skip to Step 3's fallback
- [ ] **Step 3 — Arm event delivery:** channel healthy → arm its PR filter for `<N>`; channel absent/unhealthy → arm the §3.0.1 Monitor tool watch
- [ ] **Step 4 — Proceed to §3.1 monitoring loop**

**Why this exists:** event-delivery setup gets skipped in practice — the model reads the action table and jumps straight to `gh` polling. The checklist in this always-loaded surface prevents the skip.

## Per-iteration monitoring checklist (MANDATORY — on every CI/comment event)

When a channel event, Monitor notification, or poll iteration fires, complete ALL applicable steps before declaring readiness or reporting status.

- [ ] **A — Terminal state:** `gh pr view <N> --json state -q .state` — MERGED/CLOSED → self-terminate
- [ ] **B — CI checks:** `gh pr checks <N>` — classify EVERY non-pending check (pass/fail/skipped). Read logs for ANY failure per §3.1 fetch chain
- [ ] **C — Fetch ALL comments from ALL sources:** read every update on the PR regardless of author or format. Three API surfaces + reviews:
  - [ ] C1 — Review-thread comments: `gh api repos/<owner>/<repo>/pulls/<N>/comments --paginate`
  - [ ] C2 — Issue-level comments: `gh api repos/<owner>/<repo>/issues/<N>/comments --paginate` (includes AI-review summaries, user replies, bot task-completion posts)
  - [ ] C3 — PR reviews: `gh api repos/<owner>/<repo>/pulls/<N>/reviews --paginate` (review bodies contain findings — APPROVED/CHANGES_REQUESTED/COMMENTED reviews all may carry actionable content)
  - [ ] C4 — Read every comment body in full. Summaries and review posts from ANY AI agent (claude[bot], codex, cursor, copilot) contain findings that require classification — these are NOT informational. **Extract individual findings** per [`${CLAUDE_PLUGIN_ROOT}/reference/review-discipline.md`](../../reference/review-discipline.md) §2 — one comment with N findings = N work items, each needing individual D1-D7. **For ≥3 findings, MANDATORY subagent dispatch** per the same §2 — preserves main session context, structurally enforces per-finding ledger shape
- [ ] **D — For EACH unaddressed **finding** (not comment — one comment may contain multiple findings):**
  - [ ] D1 — Read full finding context (parent comment body + surrounding findings). For multi-finding comments dispatched to a subagent ([review-discipline](../../reference/review-discipline.md) §2), this work is in the subagent; the main session receives the ledger
  - [ ] D2 — Explore referenced code (must be on the PR branch for accurate results)
  - [ ] D3 — **Validate the claim** before trusting: verify the assertion against actual code, run the command, check the file. Research non-trivial claims against official docs. Never implement a fix based solely on a bot's assertion — confirm it is correct first
  - [ ] D4 — Classify: VALID (fix now) / VALID (defer) / INCORRECT / UNCERTAIN. Classification MUST cite evidence from D2-D3
  - [ ] D4.5 — React to the parent comment: `+1` VALID, `-1` INCORRECT, `eyes` UNCERTAIN (via `gh api .../reactions`). One reaction per comment. Mixed findings: `+1` if any VALID. Verify the reaction posted via a GET on the same endpoint — non-zero confirms. **Exemption:** PR review BODIES (C3 surface) have no reactions endpoint in the REST API — skip the reaction for review-body findings; the D5 reply is the audit signal there
  - [ ] D5 — Reply with a per-finding classification table + evidence (before fixing). **Route by comment type — REQUIRED, not interchangeable:** inline review comments MUST reply THREADED via `gh api repos/<owner>/<repo>/pulls/<N>/comments/<id>/replies`; issue-level / review-level → `gh pr comment <N>`. Answering an inline finding with a detached `pr comment` is a routing error, not a style choice. Use the project's bot-identity wrapper for these writes when it has one; plain `gh` otherwise
    - [ ] **Verify reply exists — on the surface it was posted to:** inline threaded replies land on the review-comment surface — `gh api repos/<owner>/<repo>/pulls/<N>/comments --jq '.[] | select(.in_reply_to_id == <original-id>)'`; issue-level replies — `gh api repos/<owner>/<repo>/issues/<N>/comments --jq '.[].body'`. Querying only issues/comments false-fails a correctly posted inline reply
  - [ ] D6 — Fix if VALID (fix now) — edit, `git add <files>`, commit, push
    - [ ] **Verify commit pushed:** `gh api "repos/<owner>/<repo>/commits?sha=<branch>&per_page=1" --jq '.[0].sha'` — confirm the fix commit SHA appears on the remote
  - [ ] D7 — Post a follow-up reply citing the fix commit SHA
    - [ ] **Verify follow-up reply posted — same surface routing as D5:** inline thread → `pulls/<N>/comments` filtered by `in_reply_to_id`; issue-level → `gh api repos/<owner>/<repo>/issues/<N>/comments --jq '.[-1].body'` — confirm the follow-up with SHA appears on GitHub
  - [ ] D7.5 — Resolve review thread — **author-conditional, inline only**. Resolve threads opened by a BOT reviewer that you addressed. NEVER resolve HUMAN-authored threads (the human resolves their own). NEVER resolve your OWN (your posting identity — bot or personal). Detect bot via the API surface in use — REST `user.type==Bot`; GraphQL `author.__typename==Bot` (resolution runs via GraphQL). Verify `isResolved == true` via GraphQL
- [ ] **E — Readiness gate:** ALL checks terminal + ALL comments addressed + 2-min cooldown since last activity per [readiness.md](reference/readiness.md)
- [ ] **F — Report:** present the full readiness table OR list remaining blockers

**Receiving an event is NOT processing it.** Each event must drive at LEAST steps A-C. New comment events must drive D1-D7 for that comment. Declaring "ready to merge" without completing E is a checklist violation.

---

## Full lifecycle (`/pull-request full`)

Run Phase 1 → Phase 2 → Phase 3 → Phase 4 as a continuous flow. Phase transitions are automatic — don't pause between phases except at **decision gates** where the outcome could vary, plus one interactive-only checkpoint at the create→monitor boundary.

**Create→monitor checkpoint (`full` only):**

After Phase 2 reports the PR URL, detect session mode:

- **Interactive** (no autonomous-session marker like `CLAUDE_CODE_REMOTE=true`): ask the user whether to proceed to Phase 3 (monitor) in this session. Acceptable responses: proceed (continue to Phase 3) / stop (end after create) / handoff (end; another session/routine will pick up monitoring). Default on no-response is stop.
- **Autonomous** (`CLAUDE_CODE_REMOTE=true` or equivalent): no prompt; continue to Phase 3 without pausing. There is no user to ask.

Standalone `create` (not invoked inside `full`) always stops after Phase 2 — see [reference/create.md](reference/create.md) §2.6.

**Decision gates (pause for user):**

| Gate | Why it needs input |
|------|-------------------|
| Prep findings have VALID fixes | User decides which to fix vs defer |
| Commit message content | User may want different wording |
| Create→monitor (interactive only, `full` mode) | User may want to hand off monitoring to another session/routine |
| CI failure fix proposal | Fix approach has multiple options |
| Merge confirmation | Irreversible action |

**NOT gates (proceed automatically):**

| Transition | Just do it |
|-----------|-----------|
| Prep complete → create | Obvious next step |
| All [readiness gates](reference/readiness.md) pass → suggest merge | Report with full readiness verdict |
| Comment classified INCORRECT → react + reply | Evidence already gathered |
| Fix pushed → re-monitor | New push = new cycle |

**NEVER auto-proceed on these (even in `full` mode):**

| Condition | Why it's NOT a gate pass |
|-----------|------------------------|
| CI green + no comments yet | Reviewers may not have posted — cooldown required |
| CI green + failing security scan | Security findings MUST be evaluated before merge |
| CI green + unclassified failures | Every FAILURE needs explicit classification |

In a non-interactive context (cloud session, CI action), minimize gates to merge-only.

---

## Fetch CI logs (`/pull-request fetch-logs <pr|run> [--raw|--job <job-id>]`)

Public action for retrieving failed-CI evidence. Tiered fetch chain — cheapest signal first; escalate only when the lower tier is insufficient. The skill body chooses which internal helper to invoke based on flags; consumers describe WHAT they want and the skill picks HOW.

**Behaviors:**

| Invocation | What it returns | When to use |
|------------|-----------------|-------------|
| `fetch-logs <pr-number>` (default) | `::error::` + `::warning::` annotations across all failed jobs | First-pass — usually enough to identify the cause |
| `fetch-logs <pr-number> --failed` | Annotations from failed jobs only | When the run has many jobs and noise is a concern |
| `fetch-logs <run-id> --raw` | Full GitHub Actions log ZIP, dumped in scope | When annotations are sparse / missing — debug-grade detail |
| `fetch-logs <run-id> --job <job-id>` | Plain-text log of one job | Targeted dive after seeing which job failed |

`<pr-number>` and `<run-id>` are interchangeable inputs — the skill resolves the latest run for a PR when given a PR number.

**Composition with `monitor`:** `monitor` invokes this action internally on CI failure. Direct `fetch-logs` invocation is for ad-hoc post-mortem (e.g., reviewing a closed PR's CI failure, auditing a green run for warnings).

**Implementation note:** the skill body delegates to the bundled `fetch-annotations.sh` and `fetch-failed-logs.sh` scripts. Those are private — consumers MUST NOT cite script paths directly. Use this action.

---

## Important notes

- **Side effects** — this skill commits, pushes, creates PRs, and merges. User approval gates at each dangerous step (commit message, CI fix, merge) provide safety — the skill itself enforces human checkpoints
- **Finding verification is non-negotiable** — agent recommendations have demonstrated error rates. Skipping verification presents potentially wrong advice
- **Research-driven fixes** are the entire point of the monitor phase. The cost of a short research burst is near-zero; the cost of an unresearched fix is high
- **Max 3 CI fix iterations** — prevents infinite fix-push-fail loops
- **Findings triage**:
  - **Bot comments classified CORRECT** (Codex, claude-review, etc. — after evidence-based verification against actual code): **auto-fix + test + push + react 👍 + reply in the same turn**. No user-approval pause. The safety gate is the CORRECT/INCORRECT classification, not a separate confirmation. Applies when the fix is small and scoped (<~50 LOC, single concern); pause for cross-cutting refactors even when CORRECT
  - **Bot comments classified INCORRECT**: autonomous 👎 reaction + reply with research-backed counter-evidence. Never silently ignore
  - **Human reviewer comments**: always pause for user approval before reacting or fixing, regardless of classification
- **Docs-only changes skip the review/simplify work** — no code review needed for markdown/config-only PRs; the verify gate reduces to lint. Any extra project-specific prep-evidence requirements come from the consuming project's own hooks

---

## Gotchas

Failure patterns encountered in real sessions. Add to this section when new gotchas are discovered.

- **Agent review findings are wrong by default.** Validation of one review batch found 0/5 specific fixes were correct. Every finding MUST be verified against current docs and actual code before presenting. Never skip the 1.3 verification step
- **Never guess at CI failure causes.** Use monitor.md §3.2's prioritized fetch chain: annotations → full ZIP via REST API → `gh run view --log-failed` as last resort. `gh run view --log-failed` truncates at the CLI display layer (~4MB cap, cli/cli #11059 #10551 #7771); the script-based paths return complete data. Do NOT use broad keyword grep (`error|fail|...`) — false matches from cleanup steps, variable names, and incidental output
- **OIDC-based workflows fail when the PR modifies the workflow file.** The workflow file must match the default branch for OIDC token exchange to succeed. GitHub limitation — classify as informational when it applies
- **`gh pr view` without a PR number is fragile.** Branch-based resolution fails when: the worktree is cleaned up, multiple PRs exist for the branch, or returning days later. Resolve `<pr_number>` once at phase entry (per "PR identity resolution" above) and pass it explicitly to every subsequent `gh` call. No state file — `gh` is authoritative
- **Squash merge needs `git branch -D`, not `-d`.** After squash merge, the local branch commit doesn't appear in the default branch's history (different SHA). `-d` says "not fully merged." `-D` is safe because you already confirmed the merge
- **`git add -A` and `git add .` are banned.** Risk of committing secrets, build artifacts, or unrelated changes. Always `git add <specific-files>`
- **Bot comments need reactions AND replies.** React (👍/👎/👀) on every substantive comment AND reply with a per-finding classification table with evidence. Don't skip any reviewer — each gets individual attention. Verify BOTH the reaction and the reply landed on GitHub via API query. After fixing, resolve the thread IF bot-authored — never human-authored, never your own (D7.5, author-conditional)
- **Monitor is async, not serial.** Process comments as they arrive while CI is still running. Don't wait for all checks to complete before reading comments — bots post at different times
- **Check mergeable BEFORE polling CI.** `gh pr view <pr_number> --json mergeable` — if `CONFLICTING`, GitHub won't trigger workflows. Integrate the default branch first, then poll
- **Never merge with unclassified FAILURE check runs.** Every FAILURE must be investigated, classified (real failure vs informational), and documented before merge is even suggested. See [readiness.md](reference/readiness.md) for the full 6-gate checklist
- **"No comments" does NOT mean "ready."** Comment-only actors post at unpredictable times. A 2-minute cooldown after the last check-run completion or comment arrival prevents the race condition. See readiness.md Gate 5
- **Security scans are always blocking.** Any check run or bot comment reporting security findings (secrets, vulnerabilities) triggers mandatory triage — even if the finding is a false positive, it must be explicitly classified and documented before merge
- **Discover actors, don't hardcode them.** Security tools and AI reviewers change over time. Monitor discovers actors from `gh pr checks` and PR comments, classifies them by category (CI, security, review), and evaluates accordingly
- **Uncommitted changes are silently lost on branch deletion.** `git reflog` cannot recover uncommitted edits — only commits. Before staging (Phase 2.3.1) and before post-merge cleanup (Phase 4.3), check `git status --porcelain` for unrelated uncommitted changes. Stash them (`git stash push -m "desc" -- <files>`) — stashes survive branch deletion. Never silently ignore uncommitted changes
- **Cloud sessions use `gh` polling, not event subscription.** Autonomous cloud sessions (`CLAUDE_CODE_REMOTE=true`) poll `gh pr checks` + `gh api` on a fixed 60-90s cadence (§3.0.0 of monitor.md)
- **Monitor MUST check the push channel FIRST, then fall back.** Three-tier hierarchy on local CLI sessions: (1) **push channel** (when your environment ships a GitHub-events MCP channel — ~0 idle requests), (2) **Monitor tool** (session-persistent `Monitor(persistent: true, ...)` watch; 30s `gh` poll fires on real CI/comment events; cancel via `TaskStop`), (3) fixed-interval cron polling (deprecated — wasteful). Do NOT skip straight to the Monitor tool without checking for a channel — polling wastes ~1 request per 30s interval vs ~0 idle with push delivery
