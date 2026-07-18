# Babysit loop (safe-tier continuous iteration)

Multi-PR iteration layer wrapping the per-PR review discipline at the plugin-scope seam
([`${CLAUDE_PLUGIN_ROOT}/reference/review-discipline.md`](../../../reference/review-discipline.md)).
Designed for `/loop /source-control:babysit-prs` (dynamic, self-pacing via ScheduleWakeup).
This is the safe tier's core loop and the Python-free degrade path for every tier: discover the
in-scope PRs, check out, monitor, fix, move to next. This loop never merges; merge authority
exists only behind the `worker`/`autopilot` pinned gate in SKILL.md, and those tiers run their
per-PR work through dispatched workers per [orchestration.md](orchestration.md) rather than
inline here.

## 5.0 Focus-first rule

**Process the oldest PR with unaddressed comments to completion before advancing to the next
PR.** "Completion" = every comment on that PR has been: read in full, code explored, claim
investigated, classified (VALID/INCORRECT/UNCERTAIN), reacted to, replied to with evidence, and
fixed if VALID. Only after ALL comments on the current PR are resolved, move to the next oldest.

A shallow survey of all PRs is NOT babysitting. Reporting "bot findings need classification"
without classifying is NOT babysitting. Babysit means actively working each comment.

### 5.0.1 Iteration entry — round-robin flow

Each `/loop` wake-up runs one full babysit iteration. Round-robin from oldest to newest:

1. **Discover** all open PRs (§5.0.2)
2. **Focus** the oldest PR with unaddressed comments or failing CI
3. **Checkout** the PR branch (§5.1.2) — mandatory for accurate exploration + research
4. **Process** all current comments on that PR (one wave — §5.1.3 checklist)
5. **Commit + push** fixes on the PR branch (§5.1.4)
6. **Advance** to the next-oldest PR needing attention — repeat steps 3-5
7. **Skip** PRs with all comments addressed + CI green + no new activity
8. **Park** on the home branch after all PRs are processed (§5.2)
9. **Schedule** the next wake (§5.3)

Keep circling — each iteration processes one wave per PR. New CI results and review comments
from pushed fixes are picked up on the next iteration.

### 5.0.2 PR discovery

```bash
gh pr list --state open --author "@me" --limit 200 \
  --json number,title,headRefName,isDraft,author --jq 'sort_by(.number)'
```

Oldest-first (FIFO) — lowest PR number processed first.

**Author scope:** `@me` is your `gh api user --jq .login` identity; the `babysit_self_logins` key
in SKILL.md's effective-configuration block adds extra posting identities on top of it. Run the
listing once per identity (`@me` plus each configured extra) and merge the results. Drop the author filter only
in `autopilot` or on an explicit user instruction to widen. A widened discovery includes other
authors' PRs — a dependency-manager PR with failing CI gets the same diagnose-and-fix
attention as any other, but dependency-authored PRs are never merged autonomously in any tier
(SKILL.md cross-tier invariants).

**Draft policy (replaces the old blanket draft skip):** drafts stay in the discovery list in
every tier. In the safe tier a draft is evaluated — terminal state, CI, unaddressed findings —
and reported, never fixed, never marked ready. Worker/autopilot draft handling (zero-blocker
drafts route through a worker; `gh pr ready` only in autopilot) is defined in SKILL.md.

**Zero-PR fast path:** if discovery returns an empty list, report `No open PRs need
attention.` and call `ScheduleWakeup(delaySeconds=1200, reason="no open PRs",
prompt="/source-control:babysit-prs")`. Exit the iteration.

### 5.0.3 Evidence-based fresh rescan

Every iteration rescans ALL comments on every non-terminal PR. GitHub is the source of truth —
not model memory, not prior-iteration state, not comment counts (why:
[review-discipline.md](../../../reference/review-discipline.md) §1).

**Per-PR rescan flow:**

1. **Terminal check** — `gh pr view <N> --json state -q '.state'`. MERGED/CLOSED → skip
2. **CI check** — `gh pr checks <N> --json bucket -q '[.[] | .bucket] | unique'`
3. **Fetch ALL comments** — run
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/fetch-all-pr-comments.sh" <N>` to retrieve every comment
   from all 3 API surfaces (review-thread, issue-level, PR reviews). Full bodies, not counts
4. **Filter own prior replies + classify addressed/unaddressed** per
   [review-discipline.md](../../../reference/review-discipline.md) §1
5. **Extract findings** per [review-discipline.md](../../../reference/review-discipline.md) §2 —
   one comment may contain multiple work items

**Needs attention when ANY of:**

- CI has `fail` / `pending` / `in_progress` bucket entries
- Any comment has unaddressed findings (per the §1 classification)

**Skip when ALL of:**

- State is terminal (MERGED/CLOSED)
- All checks pass/skipping AND zero unaddressed findings

**Draft PRs (safe tier):** evaluation stops after this rescan — report the draft's status
(state, CI, unaddressed findings) and move on. The checkout, freshness-integration, fix, and
thread-resolution steps below apply to non-draft PRs only (per §5.0.2's draft policy).

PRs not needing attention are reported in a one-line status summary and skipped.

### 5.0.4 Structured finding extraction

Finding extraction — including the MANDATORY subagent dispatch for ≥3-finding comments, the
verbatim scope-fenced dispatch prompt, the ledger contract, and the main-session contract after
the subagent returns — lives at the seam:
[review-discipline.md](../../../reference/review-discipline.md) §2. Apply it exactly; the
readiness gate (§5.1.3 step E) mechanically enforces that classification rows cover source
findings.

## 5.1 Per-PR processing

For each PR needing attention (oldest first):

### 5.1.1 Event-delivery gate

Before monitoring work on each PR, arm event delivery — in order:

1. **Cloud check:** `CLAUDE_CODE_REMOTE=true` → no push/watch capability; poll `gh pr checks` +
   the comment fetch on a fixed 60-90s cadence. Skip remaining steps
2. **Push-channel gate:** when your environment ships a GitHub-events push channel (an MCP
   server delivering webhook events into the session), verify it is healthy and arm its PR
   filter for `<N>` (health checks + arming per
   [pull-request monitor.md](../../pull-request/reference/monitor.md) §3.0.05)
3. **Monitor-tool fallback:** channel absent/unhealthy → arm a session-persistent Monitor watch
   (30s `gh` poll; arming pattern per
   [pull-request monitor.md](../../pull-request/reference/monitor.md) §3.0.1)
4. Proceed to the §5.1.3 checklist

A push channel arms for ONE PR at a time. Re-arm for each new PR in the loop.

### 5.1.2 Branch checkout (MANDATORY for accurate exploration)

(`main` below — substitute the repo's default branch.)

```bash
# Pre-check 0: already on the PR branch? This session owns it — no checkout
# needed (the current worktree also shows up in `git worktree list`, so the
# other-worktree grep below would otherwise false-trip to read-only).
# Pre-check 1: is the branch checked out in ANOTHER worktree?
# Pre-check 2: does THIS worktree have uncommitted changes? They may be
# another session's WIP — never reset/clean work this loop did not create.
BRANCH="<headRefName>"
CUR_BRANCH=$(git branch --show-current)
CUR_WT=$(git rev-parse --show-toplevel)
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
if [ "$CUR_BRANCH" = "$BRANCH" ]; then
  # Already own the branch — no checkout; freshness check below still runs.
  # The dirty-tree guard still applies: uncommitted changes may be another
  # session's WIP even on this branch — full mode only on a clean tree.
  git fetch origin "$DEFAULT_BRANCH"
  if [ -n "$(git status --porcelain)" ]; then
    echo "Working tree has uncommitted changes — processing read-only"
    CHECKOUT_MODE="read-only"
  else
    CHECKOUT_MODE="full"
  fi
elif git worktree list | grep -vF "$CUR_WT " | grep -q "\[$BRANCH\]"; then
  echo "Branch $BRANCH checked out in another worktree — processing read-only"
  CHECKOUT_MODE="read-only"
elif [ -n "$(git status --porcelain)" ]; then
  echo "Working tree has uncommitted changes (possibly another session's WIP) — no checkout, processing read-only"
  CHECKOUT_MODE="read-only"
else
  git fetch origin "$DEFAULT_BRANCH"
  # gh pr checkout handles fork-sourced PRs (head branch not fetchable from
  # origin) and same-repo branches alike — never bare fetch/checkout by name.
  gh pr checkout "$PR_NUMBER"
  CHECKOUT_MODE="full"
fi

# Branch freshness — preserve the branch's integration workflow (full mode only)
if [ "$CHECKOUT_MODE" = "full" ]; then
  if ! git merge-base --is-ancestor "origin/$DEFAULT_BRANCH" HEAD; then
    if git log --merges --format='%H' "origin/$DEFAULT_BRANCH..HEAD" | grep -q .; then
      INTEGRATION_MODE="merge"
      echo "Branch $BRANCH uses merge commits — merging origin/$DEFAULT_BRANCH"
      git merge --no-edit "origin/$DEFAULT_BRANCH"
      INTEGRATION_EXIT=$?
    else
      INTEGRATION_MODE="rebase"
      echo "Branch $BRANCH is behind origin/$DEFAULT_BRANCH — rebasing"
      git rebase "origin/$DEFAULT_BRANCH"
      INTEGRATION_EXIT=$?
    fi

    if [ "$INTEGRATION_EXIT" -eq 0 ]; then
      REBASE_STATUS="integrated"
      # A merge preserves existing commits and pushes normally. A rebase
      # rewrites them and therefore needs a lease-protected force push.
      if [ "$INTEGRATION_MODE" = "merge" ]; then
        git push
      else
        git push --force-with-lease
      fi
    else
      # Graduated conflict handling — attempt simple, abort complex.
      # conflict-attempting is a TRANSIENT state: resolve it (merge/rebase
      # --continue) or abort BEFORE any further processing — never leave an
      # integration in progress (unmerged paths break later checkouts + parking).
      CONFLICT_COUNT=$(git diff --name-only --diff-filter=U | grep -c . || true)
      if [ "$CONFLICT_COUNT" -le 3 ]; then
        echo "Simple conflict ($CONFLICT_COUNT files) — attempting resolution"
        REBASE_STATUS="conflict-attempting"
      else
        echo "Complex conflict ($CONFLICT_COUNT files) — aborting $INTEGRATION_MODE"
        if [ "$INTEGRATION_MODE" = "merge" ]; then
          git merge --abort
        else
          git rebase --abort
        fi
        REBASE_STATUS="conflict-aborted"
      fi
    fi
  else
    REBASE_STATUS="current"
  fi

  # conflict-attempting: resolve NOW — per file, take the mechanical
  # resolution; if ANY file needs intent judgment, abort the active merge or
  # rebase and set REBASE_STATUS="conflict-aborted". On success: `git add
  # <files>` + the matching `git merge --continue` / `git rebase --continue`,
  # then plain `git push` for a merge or `git push --force-with-lease` for a
  # rebase. Set REBASE_STATUS="integrated". Only terminal states pass this point.

  # Safe fallback: ONLY the terminal success states keep full mode. A
  # lingering conflict-attempting (resolution skipped) degrades to read-only
  # rather than granting write access mid-rebase.
  if [ "$REBASE_STATUS" != "integrated" ] && [ "$REBASE_STATUS" != "current" ]; then
    CHECKOUT_MODE="read-only"
  fi
fi
```

**Integration conflict handling (graduated).** Check for merge commits first
(`git log --merges origin/$DEFAULT_BRANCH..HEAD`) — a branch that previously merged the default
branch integrates via `git merge origin/$DEFAULT_BRANCH` plus a plain push; other branches
rebase and force-push with lease. Then:

- **Zero conflicts** (`REBASE_STATUS=integrated`) — merge or rebase succeeded, push with the
  mode-appropriate command, continue normally
- **Simple conflicts** (≤3 files, `REBASE_STATUS=conflict-attempting`) — TRANSIENT: attempt
  resolution immediately; on success continue the active merge/rebase and push with the
  mode-appropriate command → `integrated`; if ANY file requires intent judgment, abort the
  active integration → `conflict-aborted`. Never proceed to comment processing, parking, or the
  next PR with an integration in progress. Resolve via `/source-control:resolve-conflicts`
  discipline (understand both sides' intent; compose, don't side-pick)
- **Complex conflicts** (>3 files, `REBASE_STATUS=conflict-aborted`) — abort the merge/rebase,
  post a PR comment: `"⚠️ Branch is behind $DEFAULT_BRANCH with integration conflicts ({N}
  files). Manual resolution is required before CI will trigger."`. If an interactive terminal,
  also surface to the user directly. Process comments read-only (classification + reply, no
  fixes — the code may be stale)
- **Already current** (`REBASE_STATUS=current`) — no action needed

**Why mandatory:** exploration and research read files from the working tree. Without checkout,
findings are validated against the wrong code. Branch freshness prevents CI failures from stale
code and ensures conflict detection happens proactively.

**Read-only mode:** investigate comments, explore referenced code via
`git show origin/<branch>:<path>`, research claims, classify, reply with evidence — the full
D1-D5 workflow. Only D6-D7 (edit + commit + push + follow-up reply) are blocked. Read-only is
NOT passive — every comment still gets investigated and replied to. Fixes that can't be pushed
are described in the reply with exact code changes so the user or the PR's own worktree session
can apply them.

**Full mode:** full flow including the fix cycle (D1-D7). Commit and push on the PR branch
after each wave of fixes.

### 5.1.3 Per-PR iteration checklist

Must be on the PR branch (§5.1.2) before starting. D steps run **per-finding** with
verification gates per [review-discipline.md](../../../reference/review-discipline.md) §3.

- [ ] **A** — Terminal state check (`gh pr view <N> --json state`)
- [ ] **B** — CI checks — classify every non-pending check (pass/fail/skipped)
- [ ] **C** — Fetch ALL comments and extract findings:
  - [ ] C1 — Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/fetch-all-pr-comments.sh" <N>` (all 3 API
    surfaces)
  - [ ] C2 — Read every comment body in full
  - [ ] C3 — Extract individual findings per
    [review-discipline.md](../../../reference/review-discipline.md) §2
  - [ ] C4 — Build the work-item list: one entry per finding, each needing D1-D7
- [ ] **D** — For EACH unaddressed **finding** (not comment): run the full D1–D7.5 cycle with
  its verification gates per [review-discipline.md](../../../reference/review-discipline.md) §3
  (read → explore → validate → classify → react → reply → fix → follow-up → author-conditional
  thread resolution, each verified on GitHub)
- [ ] **E** — Readiness gate. Run
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/babysit-readiness-gate.sh" <N>` — when the
  `${user_config.babysit_self_logins}` option is non-empty (and not a literal unexpanded token),
  append `--extra-self "${user_config.babysit_self_logins}"`. Exit 0 `READINESS_OK`
  is REQUIRED to proceed. Exit 1 `READINESS_BLOCKED reason=under-decomposed` means
  classification rows < source findings → decompose + classify the missing findings, then
  re-run. THEN confirm: all checks terminal + 2-min cooldown
- [ ] **F** — Per-finding classification table + readiness report (see §5.5)

**"Done" means GitHub shows evidence.** A per-finding work item is addressed only when the
verification sub-step confirms the action landed on GitHub. Model memory of "I posted a reply"
is not evidence — re-query the API.

### 5.1.4 Fix cycle (full mode only)

When on the PR branch AND a comment is classified VALID after D3 validation:

- [ ] Edit code to fix the issue
- [ ] `git add <specific-files>` (never `-A` or `.`)
- [ ] `git commit -m "<type>: <description>"`
- [ ] `git push`
- [ ] Post a follow-up reply citing the commit SHA (D7)

**One wave at a time:** address all current comments on this PR → commit + push → then
round-robin to the next PR. Don't jump between PRs mid-wave. After pushing, new CI runs trigger
— those results are checked on the next babysit iteration (or the next round-robin pass if
processing multiple PRs).

**Re-review trigger after a fix push:** bots that reviewed the PR may need an explicit trigger
to re-evaluate fixes. After pushing, check each bot's trigger mode per
[pull-request readiness.md](../../pull-request/reference/readiness.md) "Expected PR actors":

- **"On every push" trigger** — re-reviews automatically, just wait
- **Manual/smart trigger** — when the review-trigger module is configured (SKILL.md
  effective-configuration block), the orchestrator posts the configured trigger phrase per
  [review-trigger.md](review-trigger.md); unconfigured, the module is dormant — note the bot's
  own trigger convention from the consuming repo's docs and report instead of inventing one

Research-gate non-trivial fixes (multi-source consensus) per
[pull-request monitor.md](../../pull-request/reference/monitor.md) §3.2. Max 3 CI fix
iterations per PR per babysit pass. Inline-vs-subagent choice for CI log fetching per the same
file's "Inline vs subagent dispatch decision".

### 5.1.5 Human comments

Classify but DO NOT auto-fix. Reply with investigation findings per step D. Note: D4.5
reactions proceed autonomously for human reviewer comments (no approval gate — babysit runs
without a user present). This differs from the single-PR monitor flow
([pull-request monitor.md](../../pull-request/reference/monitor.md) §3.3.1 step 4), which
pauses for approval in interactive sessions. Report to the user in the babysit iteration output
— human review items are surfaced, not silently skipped.

### 5.1.6 PR done — transition to next

When the readiness gate passes OR all actionable items are handled for this PR:

1. If on a PR branch with uncommitted changes from a failed fix: `git reset --hard HEAD` then
   `git clean -fd` (unstage + revert tracked + remove untracked)
2. Report PR status (ready / blockers remaining / items deferred to human)
3. Move to the next PR in the discovery list

## 5.2 Parking

After all PRs are processed (or none needed attention), return to the worktree's home branch.
Record at iteration start:

```bash
PARKING_BRANCH=$(git rev-parse --abbrev-ref HEAD)
```

After processing all PRs:

```bash
git checkout "$PARKING_BRANCH"
```

## 5.3 Self-pacing (ScheduleWakeup)

At the end of each iteration, schedule the next wake. Cadence has one owner: the engine
recommends, this loop schedules.

**Engine-backed runs (Python present):** derive the wake interval from the snapshot's
`recommended_cadence` — `active` 5 minutes, `normal` 15 minutes, `quiet` hourly, `idle` daily —
per [cadence.md](cadence.md)'s states and thresholds.

**Python-free degrade ladder** (no snapshot available this iteration):

| Condition | Delay | Reason |
|-----------|-------|--------|
| Active events flowing (CI running, fresh comments arrived during this iteration) | 60s | Stay responsive to in-flight activity |
| PRs exist but all currently quiet (no new events, no pending checks) | 270s | Check back soon without idle churn |
| No PRs need attention (all ready, all terminal, or zero open PRs) | 1200s | Long idle — conserve request budget |

```text
ScheduleWakeup(
  delaySeconds: <per the engine recommendation, or the ladder above>,
  reason: "<specific reason for this delay>",
  prompt: "/source-control:babysit-prs"
)
```

## 5.4 NEVER-do list

These constraints override any other instruction within the babysit loop:

- **Never declare readiness or schedule the next wake without a passing
  `babysit-readiness-gate.sh <N>` run** (exit 0 `READINESS_OK`). The gate counts classification
  rows vs source findings and blocks under-decomposition. "I classified them" is not evidence —
  the gate exit code is. See §5.1.3 step E
- **Never survey-and-report without investigating** — every unaddressed comment gets D1-D7
  (read, explore, validate, classify, reply, fix, follow-up). "Bot findings need classification"
  without classifying is a violation
- **Never trust a finding without validating** — bot/AI assertions have demonstrated error
  rates. Always verify against actual code (D3) before implementing. Explore the referenced
  code; research non-trivial claims
- **Never process comments from the wrong branch** — must be on the PR branch before D2-D3.
  Exploring code on the default branch or another branch produces wrong classifications
- **Never advance to the next PR with unaddressed comments on the current PR** — focus-first
  rule (§5.0). Complete the current wave before moving on
- **Never skip AI review summaries** — AI-reviewer posts (issue-level comments with
  severity-labeled findings) are actionable comments requiring D1-D7. Same for every AI reviewer
- **Never `gh pr merge`** — this loop never merges. Merge authority exists only behind the
  `worker`/`autopilot` pinned merge gate (SKILL.md), never a raw `gh pr merge`
- **Never `git add -A` or `git add .`** — specific files only
- **Never auto-fix human reviewer comments** — classify + reply + report to the user
- **Never skip the event-delivery gate** — run §5.1.1 for every PR
- **Never exceed 3 CI fix iterations** per PR per babysit pass
- **Never leave uncommitted changes** on a PR branch when transitioning to the next PR
- **Never skip emoji reactions** — every classified finding gets a reaction on its parent
  comment (+1 VALID, -1 INCORRECT, eyes UNCERTAIN). Reactions are the fastest audit signal for
  reviewers scanning a PR
- **Never skip the branch freshness check** — always `git fetch origin <default-branch>` +
  `git merge-base --is-ancestor origin/<default-branch> HEAD` after checkout. Stale branches
  cause CI failures; proactive integration is cheaper than a reactive fix. See §5.1.2
- **Never skip reply verification** — after posting a reply (D5) or follow-up (D7), verify it
  landed on GitHub via API query. Model memory of "I replied" across compaction is not evidence
- **Never skip resolving a BOT-authored thread; never resolve a HUMAN or OWN thread** — after
  fixing + replying to an inline review comment opened by a bot reviewer, resolve that thread
  (D7.5, author-conditional). Leave HUMAN-authored threads for the human to close; never resolve
  your own. Open bot-thread count is a visible signal to reviewers
- **Never process your own prior replies as findings** — filter out comments from your own
  posting identities that match the classification reply pattern. See
  [review-discipline.md](../../../reference/review-discipline.md) §1 step 1

## 5.5 Checklist-driven output format

Every iteration MUST output a completed checklist with evidence per step. Free-form narrative
reports are not acceptable — they hide skipped steps.

**Gate-enforced:** readiness requires a passing `babysit-readiness-gate.sh <N>` run (§5.1.3
step E). To mechanically gate checklist completeness too, write this iteration's checklist to a
file in your working-notes location and pass `--checklist <file>` — the gate exits non-zero
while any `- [ ]` box is unticked, so an incomplete checklist cannot be declared "ready".

```text
## Babysit iteration [<timestamp>]

### A. PR Discovery
- [ ] Fetched open PRs: <N> total, <M> needing attention, <K> skipped
- [ ] Processing order (oldest first): #<N1>, #<N2>, ...

### B. Per-PR Processing

#### PR #<N> — <title> (<branch>)
- [ ] **Branch:** checked out <branch> (mode: full/read-only)
- [ ] **Branch freshness:** <current/integrated/conflict-aborted> — evidence: `git merge-base` output
- [ ] **CI:** <pass/fail/pending> — evidence: `gh pr checks <N>` output
- [ ] **Comments fetched:** <N> total from all 3 API surfaces (<M> self-replies filtered)
- [ ] **Findings extracted:** <M> individual findings from <K> comments

##### Per-finding classification table
| # | Source | Finding | Classification | Evidence | Reacted | Action |
|---|--------|---------|---------------|----------|---------|--------|
| 1 | comment <id> | <summary> | VALID | <evidence> | 👍 | Fixed: <sha> |
| 2 | comment <id> | <summary> | INCORRECT | <evidence> | 👎 | Replied |
| 3 | comment <id> | <summary> | UNCERTAIN | <evidence> | 👀 | Deferred |

##### Verification evidence
- [ ] All reactions verified on GitHub: YES/NO
- [ ] All replies verified on GitHub: YES/NO
- [ ] All commits verified pushed: YES/NO
- [ ] All follow-ups verified posted: YES/NO
- [ ] All addressed BOT-authored inline threads resolved (human + own threads excluded): YES/NO/N/A

##### PR status
- [ ] Readiness: ready for merge / <remaining blockers>

### C. Iteration Summary
- [ ] All PRs processed: YES/NO
- [ ] Parked on home branch: YES
- [ ] **Next wake:** <delay>s — <reason>
```

Every `- [ ]` must be ticked `- [x]` with evidence before the iteration ends. Unticked boxes =
incomplete iteration — do not schedule the next wake until addressed or explicitly deferred
with reason.

## 5.6 Performance notes

- **Do not skip verification steps.** The D5/D6/D7 verification sub-steps exist because model
  memory is unreliable across compaction boundaries. One API call to confirm costs seconds;
  acting on false memory costs an entire re-processing cycle
- **Quality over speed.** Processing 3 findings thoroughly with verified evidence is better
  than "processing" 10 findings with blanket classifications and no verification
- **One finding at a time.** Complete per-finding D1-D7 for finding N before starting finding
  N+1. Interleaving findings across comments produces partial work that looks complete but
  isn't
- **Evidence-based state, not memory-based state.** Never say "I already replied to that" —
  check GitHub. Never say "I already pushed that fix" — check the remote. GitHub is the state
  store; this session's memory is ephemeral
