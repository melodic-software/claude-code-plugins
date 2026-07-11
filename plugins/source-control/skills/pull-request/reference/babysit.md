# Phase 3+: Babysit (all-PR continuous loop)

Multi-PR orchestration layer wrapping the existing single-PR monitor infrastructure. Designed for `/loop /pull-request babysit` (dynamic, self-pacing via ScheduleWakeup). Processes every open PR in the repo — discovers, checks out, monitors, fixes, moves to next. Never merges.

## 5.0 Focus-first rule

**Process the oldest PR with unaddressed comments to completion before advancing to the next PR.** "Completion" = every comment on that PR has been: read in full, code explored, claim investigated, classified (VALID/INCORRECT/UNCERTAIN), reacted to, replied to with evidence, and fixed if VALID. Only after ALL comments on the current PR are resolved, move to the next oldest.

A shallow survey of all PRs is NOT babysitting. Reporting "bot findings need classification" without classifying is NOT babysitting. Babysit means actively working each comment.

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

Keep circling — each iteration processes one wave per PR. New CI results and review comments from pushed fixes are picked up on the next iteration.

### 5.0.2 PR discovery

```bash
gh pr list --state open --limit 200 --json number,title,headRefName,isDraft,author \
  --jq '[.[] | select(.isDraft == false)] | sort_by(.number)'
```

Oldest-first (FIFO) — lowest PR number processed first.

Deterministic equivalent: `bash "${CLAUDE_PLUGIN_ROOT}/skills/pull-request/scripts/discover-prs.sh"` runs this exact filter (open, skip draft, oldest-first; `--prs-json <file>` for offline/testing).

**Filters:**

- Skip `isDraft` PRs (signal "not ready for review")
- Every open PR is in scope regardless of author or label — Dependabot included. A Dependabot PR with failing CI needs the same diagnose-and-fix attention as any other; auto-merge (where configured) only fires once CI is green, so babysit owns the red ones

**Zero-PR fast path:** if discovery returns an empty list, report `No open non-draft PRs need attention.` and call `ScheduleWakeup(delaySeconds=1200, reason="no open PRs", prompt="/pull-request babysit")`. Exit the iteration.

### 5.0.3 Evidence-based fresh rescan

Every iteration rescans ALL comments on every non-terminal PR. GitHub is the source of truth — not model memory, not prior-iteration state, not comment counts.

**Why full rescan:** compaction loses prior-iteration classification state. Comment-count heuristics miss edits, deletions, and multi-finding comments. An evidence-based fresh rescan from GitHub every iteration defeats both failure modes.

**Per-PR rescan flow:**

1. **Terminal check** — `gh pr view <N> --json state -q '.state'`. MERGED/CLOSED → skip
2. **CI check** — `gh pr checks <N> --json bucket -q '[.[] | .bucket] | unique'`
3. **Fetch ALL comments** — run `bash "${CLAUDE_PLUGIN_ROOT}/skills/pull-request/scripts/fetch-all-pr-comments.sh" <N>` to retrieve every comment from all 3 API surfaces (review-thread, issue-level, PR reviews). Full bodies, not counts
4. **Filter out own prior replies** — comments authored by your own posting identities (`gh api user --jq .login`, plus any project bot identity — the same set the readiness gate's `--self` / `BABYSIT_SELF_LOGINS` covers) that ARE classification replies (contain the `| # | Finding | Classification |` table pattern) are NOT findings — skip them. Own follow-up replies citing commit SHAs are also not findings. Only process comments from OTHER authors as potential finding sources
5. **Classify each remaining comment** as "addressed" or "unaddressed" by checking GitHub for evidence:
   - **Addressed (skip)** — the comment has a substantive reply (from ANY author) containing BOTH: (a) a classification token (VALID, INCORRECT, or UNCERTAIN), AND (b) evidence (code reference, test output, or reasoning)
   - **Unaddressed (process)** — no reply meeting both criteria. "Noted" or "will fix" without classification + evidence does NOT count
6. **Extract findings** per §5.0.4 — one comment may contain multiple work items

**Needs attention when ANY of:**

- CI has `fail` / `pending` / `in_progress` bucket entries
- Any comment has unaddressed findings (per the classification above)

**Skip when ALL of:**

- State is terminal (MERGED/CLOSED)
- All checks pass/skipping AND zero unaddressed findings

PRs not needing attention are reported in a one-line status summary and skipped.

### 5.0.4 Structured finding extraction

AI review summaries (claude[bot], codex, cursor, etc.) and detailed human reviews often pack multiple findings into a single comment — markdown tables, numbered lists of severity items, or multi-paragraph analyses. Each finding is a separate work item requiring individual D1-D7.

**Extraction rules:**

- One comment with N findings = N entries in the work item list
- Each finding gets its own D1-D7 cycle (read, explore, validate, classify, reply, fix, follow-up)
- Findings are tracked individually — addressing 3 of 5 findings in a comment means 2 remain unaddressed
- Reply with a per-finding classification table (not one blanket reply for the whole comment)

**Finding identification signals:**

- Numbered items with severity labels (CRITICAL, IMPORTANT, SUGGESTION, P1/P2/P3)
- Markdown table rows with file/line/description columns
- Bullet lists where each bullet describes a distinct code concern
- Multiple `###` sub-headings each addressing different files or concerns

**Per-finding classification table format** (reply on the comment):

```text
| # | Finding | Classification | Evidence | Reacted |
|---|---------|---------------|----------|---------|
| 1 | <summary> | VALID — fixing | <evidence> | 👍 |
| 2 | <summary> | INCORRECT | <evidence why wrong> | 👎 |
| 3 | <summary> | VALID (defer) | <reason for deferral> | 👍 |
```

The reaction is per-comment (GitHub allows one reaction type per user per comment). Post the reaction BEFORE the reply — reviewers scanning a PR see 👍/👎 at a glance without expanding threads.

**MANDATORY subagent dispatch for multi-finding comments (≥3 findings):**

When a single PR comment packs 3+ findings, dispatch a finding-extractor subagent rather than attempting inline extraction. The subagent:

1. Preserves main session context — large comment bodies + per-finding investigation evidence stay in the subagent's context window; only the structured ledger returns
2. Structurally enforces the per-finding work-item shape — the subagent returns a fixed-schema ledger; missing entries trigger main-session escalation
3. Is scope-fenced — ALLOWED: read PR-branch files + `gh api` against the specific PR; FORBIDDEN: edits, commits, pushes, reactions, replies on GitHub (those stay in the main session)

**Subagent dispatch prompt (compose verbatim, substitute `<PR>` and `<COMMENT_ID>` / `<REVIEW_ID>`):**

```text
Extract individual findings from the multi-finding bot/human review at:
  https://github.com/<owner>/<repo>/pull/<PR>#issuecomment-<COMMENT_ID>
  (or pull/<PR>#pullrequestreview-<REVIEW_ID>)

ALLOWED scope (read-only on PR branch <BRANCH>):
- `gh api repos/<owner>/<repo>/issues/<PR>/comments` and per-id endpoints
- `gh api repos/<owner>/<repo>/pulls/<PR>/{comments,reviews}` and per-id endpoints
- `Read` / `Grep` / `Glob` against the repo working tree
- `Bash` for git inspection (`git show`, `git log`, `git diff`) — NEVER state-mutating

FORBIDDEN:
- Any Edit / Write of repo files
- Any `git add` / `git commit` / `git push`
- Any reaction / reply / comment POST to GitHub
- Any Skill invocation other than read-only exploration

Return a SINGLE markdown ledger with this exact shape (one row per finding):

| # | Severity | File:Line | Finding (≤120 chars) | Validation status | Evidence | Suggested classification |
|---|---|---|---|---|---|---|
| 1 | CRITICAL | path/to/file.cs:42 | <one-line summary> | VERIFIED — code matches claim | <quote 1-3 lines of code OR test output OR doc text> | VALID — fix now |
| 2 | IMPORTANT | path/to/file.cs:73 | <one-line summary> | INCORRECT — code already does X | <counter-evidence> | INCORRECT |
| 3 | SUGGESTION | path/to/file.md:12 | <one-line summary> | UNCERTAIN — behavior depends on Y | <what's missing> | UNCERTAIN |

CRITICAL constraints on the ledger:
- Severity column MUST match the parent comment's severity labels verbatim (CRITICAL / IMPORTANT / SUGGESTION / P1 / P2 / P3)
- Validation status MUST come from your own code reading, not a paraphrase of the bot claim
- Evidence MUST cite line numbers + verbatim snippets (≤3 lines) OR direct command output
- Suggested classification MUST be one of: VALID — fix now | VALID (defer) | INCORRECT | UNCERTAIN
- One row per finding. If the parent comment has 6 findings, the ledger has 6 rows. No collapsing.

If the parent comment is genuinely single-finding, return a 1-row ledger anyway.

Report ONLY the ledger + a one-line summary count ("Extracted N findings: X CRITICAL, Y IMPORTANT, Z SUGGESTION"). No prose framing.
```

**Main-session contract after the subagent returns:**

1. Receive the ledger. Verify the row count matches the source comment's finding count (independent count via grep on the parent comment body for severity markers)
2. For each ledger row, the main session runs D4.5 (react) + D5 (reply with the per-finding sub-row from the ledger) + D6 (fix if VALID — fix now) + D7 (follow-up SHA) with verification gates between each step
3. The subagent ledger is the D1-D4 work product. The main session NEVER skips D4.5-D7 by trusting the ledger alone — the ledger feeds the work, it doesn't replace it

**Single-finding comments** (1-2 findings): inline extraction in the main session is fine; subagent overhead is not warranted.

**Why a subagent for ≥3 findings:** empirically, multi-finding comments treated as single work items in the main session produce near-zero per-finding D1-D7 cycles — dozens of findings glossed in one pass. Subagent dispatch structurally forces the per-finding shape because the ledger contract demands it.

**Mechanical enforcement (gate, not prose):** advisory "MANDATORY" wording alone still under-decomposed in practice. So enforcement is a gate: `babysit-readiness-gate.sh <pr>` (run at §5.1.3 step E) counts source findings (severity markers in reviewer comments) vs classification rows (VALID/INCORRECT/UNCERTAIN in your replies) and exits non-zero when rows < findings. The subagent-dispatch rule above tells you HOW to decompose; the gate enforces THAT you did — readiness cannot be declared while it reports `READINESS_BLOCKED`.

## 5.1 Per-PR processing

For each PR needing attention (oldest first):

### 5.1.1 Event-delivery gate

Run the **Monitor entry checklist** from SKILL.md — the identical 4-step sequence:

1. Cloud check (skip if `CLAUDE_CODE_REMOTE=true`)
2. Push-channel gate (§3.0.05) — when your environment ships one
3. Arm event delivery for this PR (channel PR filter, or Monitor watch)
4. Proceed to monitoring

A push channel arms for ONE PR at a time. Re-arm for each new PR in the loop.

### 5.1.2 Branch checkout (MANDATORY for accurate exploration)

(`main` below — substitute the repo's default branch.)

```bash
# Pre-check: is branch checked out in another worktree?
BRANCH="<headRefName>"
if git worktree list | grep -q "\[$BRANCH\]"; then
  echo "Branch $BRANCH checked out in another worktree — processing read-only"
  CHECKOUT_MODE="read-only"
else
  git fetch origin "$BRANCH"
  git fetch origin main
  # Ensure clean working tree + index before checkout
  if [ -n "$(git status --porcelain)" ]; then
    git reset --hard HEAD
    git clean -fd
  fi
  git checkout "$BRANCH"

  # Branch freshness — rebase if behind main
  if ! git merge-base --is-ancestor origin/main HEAD; then
    echo "Branch $BRANCH is behind origin/main — rebasing"
    if git rebase origin/main; then
      REBASE_STATUS="rebased"
      git push --force-with-lease origin "$BRANCH"
    else
      # Graduated conflict handling — attempt simple, abort complex
      CONFLICT_COUNT=$(git diff --name-only --diff-filter=U | grep -c . || true)
      if [ "$CONFLICT_COUNT" -le 3 ]; then
        echo "Simple conflict ($CONFLICT_COUNT files) — attempting resolution"
        REBASE_STATUS="conflict-attempting"
      else
        echo "Complex conflict ($CONFLICT_COUNT files) — aborting rebase"
        git rebase --abort
        REBASE_STATUS="conflict-aborted"
      fi
    fi
  else
    REBASE_STATUS="current"
  fi

  if [ "$REBASE_STATUS" = "conflict-attempting" ] || [ "$REBASE_STATUS" = "conflict-aborted" ]; then
    CHECKOUT_MODE="read-only"
  else
    CHECKOUT_MODE="full"
  fi
fi
```

**Rebase conflict handling (graduated).** Check for merge commits first (`git log --merges origin/main..HEAD`) — a branch that previously merged main integrates via `git merge origin/main`, not rebase. Then:

- **Zero conflicts** (`REBASE_STATUS=rebased`) — rebase succeeded, force-push with lease, continue normally
- **Simple conflicts** (≤3 files, `REBASE_STATUS=conflict-attempting`) — attempt resolution; if ANY file requires intent judgment, abort to conflict-aborted
- **Complex conflicts** (>3 files, `REBASE_STATUS=conflict-aborted`) — abort the rebase, post a PR comment: `"⚠️ Branch is behind main with merge conflicts ({N} files). Manual rebase required before CI will trigger."`. If an interactive terminal, also surface to the user directly. Process comments read-only (classification + reply, no fixes — the code may be stale)
- **Already current** (`REBASE_STATUS=current`) — no action needed

**Why mandatory:** exploration and research read files from the working tree. Without checkout, findings are validated against the wrong code. Branch freshness prevents CI failures from stale code and ensures conflict detection happens proactively.

**Read-only mode:** investigate comments, explore referenced code via `git show origin/<branch>:<path>`, research claims, classify, reply with evidence — the full D1-D5 workflow. Only D6-D7 (edit + commit + push + follow-up reply) are blocked. Read-only is NOT passive — every comment still gets investigated and replied to. Fixes that can't be pushed are described in the reply with exact code changes so the user or the PR's own worktree session can apply them.

**Full mode:** full flow including the fix cycle (D1-D7). Commit and push on the PR branch after each wave of fixes.

### 5.1.3 Per-finding D1-D7 with verification gates

D steps operate **per-finding**, not per-comment. One comment with 5 findings = 5 individual D1-D7 cycles. Must be on the PR branch (§5.1.2) before starting.

- [ ] **A** — Terminal state check (`gh pr view <N> --json state`)
- [ ] **B** — CI checks — classify every non-pending check (pass/fail/skipped)
- [ ] **C** — Fetch ALL comments and extract findings:
  - [ ] C1 — Run the bundled `fetch-all-pr-comments.sh <N>` (all 3 API surfaces)
  - [ ] C2 — Read every comment body in full
  - [ ] C3 — Extract individual findings per §5.0.4
  - [ ] C4 — Build the work-item list: one entry per finding, each needing D1-D7
- [ ] **D** — For EACH unaddressed **finding** (not comment):
  - [ ] D1 — Read full finding context (parent comment body + surrounding findings)
  - [ ] D2 — Explore referenced code on the PR branch
  - [ ] D3 — **Validate the claim** — verify against actual code before trusting. Research non-trivial claims
  - [ ] D4 — Classify with evidence: VALID (fix now) / VALID (defer) / INCORRECT / UNCERTAIN
  - [ ] D4.5 — React to the parent comment via `gh api .../reactions`. One reaction per comment (not per finding). **Tiebreaker for mixed-finding comments:** `+1` if ANY finding is VALID (signals action taken), `-1` only when ALL are INCORRECT, `eyes` when all UNCERTAIN or a mix of UNCERTAIN + INCORRECT with zero VALID
    - [ ] **verify reaction exists:** GET the same reactions endpoint filtered by your posting identities — non-zero confirms. Use `pulls/comments/<id>/reactions` for inline review comments
  - [ ] D5 — Reply with the per-finding classification table + evidence (before fixing). Table format per §5.0.4 — includes the Reacted column. **Route the reply by comment type — REQUIRED, not interchangeable:** inline review comments (diff-anchored, `pulls/comments`) MUST reply THREADED via `gh api repos/{owner}/{repo}/pulls/<N>/comments/<comment-id>/replies -f body='...'` so the reply lands under the source thread — NEVER a detached `pr comment`. Issue-level / review-level comments (no thread) → `gh pr comment <N> --body '...'`. Use the project's bot-identity wrapper for these writes when it has one. Answering an inline finding with a detached issue comment orphans the reply from the thread the reviewer tracks — a routing error, not a style choice
    - [ ] **verify reply exists:** `gh api repos/{owner}/{repo}/issues/<N>/comments --jq '.[].body'` — confirm the reply text on GitHub. For inline replies: `gh api repos/{owner}/{repo}/pulls/<N>/comments --jq '.[] | select(.in_reply_to_id == <original-id>)'`
  - [ ] D6 — Fix if VALID → edit, `git add <files>`, commit, push
    - [ ] **verify commit pushed:** `gh api "repos/{owner}/{repo}/commits?sha=<branch>&per_page=1" --jq '.[0].sha'` — confirm the fix commit SHA on the remote
  - [ ] D7 — Post a follow-up reply citing the fix commit SHA
    - [ ] **verify follow-up reply posted:** `gh api repos/{owner}/{repo}/issues/<N>/comments --jq '.[-1].body'` — confirm the follow-up with SHA on GitHub
  - [ ] D7.5 — Resolve review thread — **author-conditional** (canonical policy: SKILL.md D7.5), inline review comments only. Resolve ONLY threads whose OPENING comment is authored by a BOT reviewer that you addressed. NEVER resolve HUMAN-authored threads — the human resolves their own after verifying the fix. NEVER resolve your OWN threads (any of your posting identities — same self set as §5.0.3 step 4). Skip issue-level comments (no thread). **Thread author = login of the THREAD-OPENING comment** (replying into it does not change the author). **Bot detection is API-surface-specific:** resolution runs via GraphQL (the threadId fetch), where bot authors have `author.__typename == "Bot"` and `login` omits the `[bot]` suffix; REST surfaces show the suffix. When fetching the threadId, also select `author{__typename login}` to apply the conditional in one query
    - [ ] **verify thread resolved:** query the thread node via `gh api graphql` — `isResolved` must be `true`
- [ ] **E** — Readiness gate. Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/pull-request/scripts/babysit-readiness-gate.sh" <N>` — exit 0 `READINESS_OK` is REQUIRED to proceed. Exit 1 `READINESS_BLOCKED reason=under-decomposed` means classification rows < source findings → decompose + classify the missing findings, then re-run. THEN confirm: all checks terminal + 2-min cooldown
- [ ] **F** — Per-finding classification table + readiness report (see §5.5)

**"Done" means GitHub shows evidence.** A per-finding work item is addressed only when the verification sub-step confirms the action landed on GitHub. Model memory of "I posted a reply" is not evidence — re-query the API.

### 5.1.4 Fix cycle (full mode only)

When on the PR branch AND a comment is classified VALID after D3 validation:

- [ ] Edit code to fix the issue
- [ ] `git add <specific-files>` (never `-A` or `.`)
- [ ] `git commit -m "<type>: <description>"`
- [ ] `git push`
- [ ] Post a follow-up reply citing the commit SHA (D7)

**One wave at a time:** address all current comments on this PR → commit + push → then round-robin to the next PR. Don't jump between PRs mid-wave. After pushing, new CI runs trigger — those results are checked on the next babysit iteration (or the next round-robin pass if processing multiple PRs).

**Re-review trigger after a fix push:** bots that reviewed the PR may need an explicit trigger to re-evaluate fixes. After pushing, check each bot's trigger mode per readiness.md "Expected PR actors":

- **"On every push" trigger** — re-reviews automatically, just wait
- **Manual/smart trigger** (e.g., Codex) — post `@codex review` (or the bot's equivalent) as a PR comment to request a re-review

Per monitor §3.2: research-gate non-trivial fixes (multi-source consensus). Max 3 CI fix iterations per PR per babysit pass. Inline-vs-subagent choice for CI log fetching per monitor.md "Inline vs subagent dispatch decision".

### 5.1.5 Human comments

Classify but DO NOT auto-fix. Reply with investigation findings per step D. Note: D4.5 reactions proceed autonomously for human reviewer comments (no approval gate — babysit runs without a user present). This differs from monitor.md step 4, which pauses for approval in interactive sessions. Report to the user in the babysit iteration output — human review items are surfaced, not silently skipped.

### 5.1.6 PR done — transition to next

When the readiness gate passes OR all actionable items are handled for this PR:

1. If on a PR branch with uncommitted changes from a failed fix: `git reset --hard HEAD` then `git clean -fd` (unstage + revert tracked + remove untracked)
2. Report PR status (ready / blockers remaining / items deferred to human)
3. Move to the next PR in the discovery list

## 5.2 Parking

After all PRs are processed (or none needed attention), return to the worktree's home branch. Record at iteration start:

```bash
PARKING_BRANCH=$(git rev-parse --abbrev-ref HEAD)
```

After processing all PRs:

```bash
git checkout "$PARKING_BRANCH"
```

## 5.3 Self-pacing (ScheduleWakeup)

At the end of each iteration, schedule the next wake based on observed state:

| Condition | Delay | Reason |
|-----------|-------|--------|
| Active events flowing (CI running, fresh comments arrived during this iteration) | 60s | Stay responsive to in-flight activity |
| PRs exist but all currently quiet (no new events, no pending checks) | 270s | Check back soon without idle churn |
| No PRs need attention (all ready, all terminal, or zero open PRs) | 1200s | Long idle — conserve request budget |

```text
ScheduleWakeup(
  delaySeconds: <per table above>,
  reason: "<specific reason for this delay>",
  prompt: "/pull-request babysit"
)
```

## 5.4 NEVER-do list

These constraints override any other instruction within babysit mode:

- **Never declare readiness or schedule the next wake without a passing `babysit-readiness-gate.sh <N>` run** (exit 0 `READINESS_OK`). The gate counts classification rows vs source findings and blocks under-decomposition. "I classified them" is not evidence — the gate exit code is. See §5.1.3 step E
- **Never survey-and-report without investigating** — every unaddressed comment gets D1-D7 (read, explore, validate, classify, reply, fix, follow-up). "Bot findings need classification" without classifying is a violation
- **Never trust a finding without validating** — bot/AI assertions have demonstrated error rates. Always verify against actual code (D3) before implementing. Explore the referenced code; research non-trivial claims
- **Never process comments from the wrong branch** — must be on the PR branch before D2-D3. Exploring code on the default branch or another branch produces wrong classifications
- **Never advance to the next PR with unaddressed comments on the current PR** — focus-first rule (§5.0). Complete the current wave before moving on
- **Never skip AI review summaries** — AI-reviewer posts (issue-level comments with severity-labeled findings) are actionable comments requiring D1-D7. Same for every AI reviewer
- **Never `gh pr merge`** — babysit declares readiness; the user merges
- **Never `git add -A` or `git add .`** — specific files only
- **Never auto-fix human reviewer comments** — classify + reply + report to the user
- **Never skip the event-delivery gate** — run the Monitor entry checklist for every PR
- **Never exceed 3 CI fix iterations** per PR per babysit pass
- **Never leave uncommitted changes** on a PR branch when transitioning to the next PR
- **Never skip emoji reactions** — every classified finding gets a reaction on its parent comment (+1 VALID, -1 INCORRECT, eyes UNCERTAIN). Reactions are the fastest audit signal for reviewers scanning a PR
- **Never skip the branch freshness check** — always `git fetch origin <default-branch>` + `git merge-base --is-ancestor origin/<default-branch> HEAD` after checkout. Stale branches cause CI failures; proactive integration is cheaper than a reactive fix. See §5.1.2
- **Never skip reply verification** — after posting a reply (D5) or follow-up (D7), verify it landed on GitHub via API query. Model memory of "I replied" across compaction is not evidence
- **Never skip resolving a BOT-authored thread; never resolve a HUMAN or OWN thread** — after fixing + replying to an inline review comment opened by a bot reviewer, resolve that thread (D7.5, author-conditional). Leave HUMAN-authored threads for the human to close; never resolve your own. Open bot-thread count is a visible signal to reviewers
- **Never process your own prior replies as findings** — filter out comments from your own posting identities that match the classification reply pattern. See §5.0.3 step 4

## 5.5 Checklist-driven output format

Every iteration MUST output a completed checklist with evidence per step. Free-form narrative reports are not acceptable — they hide skipped steps.

**Gate-enforced:** readiness requires a passing `babysit-readiness-gate.sh <N>` run (§5.1.3 step E). To mechanically gate checklist completeness too, write this iteration's checklist to a file in your working-notes location and pass `--checklist <file>` — the gate exits non-zero while any `- [ ]` box is unticked, so an incomplete checklist cannot be declared "ready".

```text
## Babysit iteration [<timestamp>]

### A. PR Discovery
- [ ] Fetched open PRs: <N> total, <M> needing attention, <K> skipped
- [ ] Processing order (oldest first): #<N1>, #<N2>, ...

### B. Per-PR Processing

#### PR #<N> — <title> (<branch>)
- [ ] **Branch:** checked out <branch> (mode: full/read-only)
- [ ] **Branch freshness:** <current/rebased/conflict-attempting/conflict-aborted> — evidence: `git merge-base` output
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

Every `- [ ]` must be ticked `- [x]` with evidence before the iteration ends. Unticked boxes = incomplete iteration — do not schedule the next wake until addressed or explicitly deferred with reason.

## 5.6 Performance notes

- **Do not skip verification steps.** The D5/D6/D7 verification sub-steps exist because model memory is unreliable across compaction boundaries. One API call to confirm costs seconds; acting on false memory costs an entire re-processing cycle
- **Quality over speed.** Processing 3 findings thoroughly with verified evidence is better than "processing" 10 findings with blanket classifications and no verification
- **One finding at a time.** Complete per-finding D1-D7 for finding N before starting finding N+1. Interleaving findings across comments produces partial work that looks complete but isn't
- **Evidence-based state, not memory-based state.** Never say "I already replied to that" — check GitHub. Never say "I already pushed that fix" — check the remote. GitHub is the state store; this session's memory is ephemeral
