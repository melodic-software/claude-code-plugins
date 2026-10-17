# Babysit loop (safe-tier continuous iteration)

## Contents

- [5.0 Focus-first rule](#50-focus-first-rule)
- [5.1 Per-PR processing](#51-per-pr-processing)
- [5.2 Parking](#52-parking)
- [5.3 Self-pacing (ScheduleWakeup)](#53-self-pacing-schedulewakeup)
- [5.4 NEVER-do list](#54-never-do-list)
- [5.5 Checklist-driven output format](#55-checklist-driven-output-format)
- [5.6 Performance notes](#56-performance-notes)

Multi-PR iteration layer wrapping the per-PR review discipline defined in the plugin-scope reference
([`../../../reference/review-discipline.md`](../../../reference/review-discipline.md)).
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

### 5.0.1 Round-robin iteration entry

Each `/loop` wake-up runs one full babysit iteration. Round-robin from oldest to newest:

1. **Discover** all open PRs (§5.0.2)
2. **Focus** the oldest PR with unaddressed comments or failing CI
3. **Checkout** the PR branch (§5.1.2), mandatory for accurate exploration + research
4. **Process** all current comments on that PR (one wave, per the §5.1.3 checklist)
5. **Commit + push** fixes on the PR branch (§5.1.4)
6. **Advance** to the next-oldest PR needing attention and repeat steps 3-5
7. **Skip** PRs with all comments addressed + CI green + no new activity
8. **Park** on the home branch after all PRs are processed (§5.2)
9. **Schedule** the next wake (§5.3)

Keep circling. Each iteration processes one wave per PR. New CI results and review comments
from pushed fixes are picked up on the next iteration.

### 5.0.2 PR discovery

List your own open PRs, up to 200, with number, title, head branch, draft flag and author,
sorted by number ([GitHub](../../../reference/providers/github/babysit-prs/loop.md#pr-discovery)).

Oldest-first (FIFO): lowest PR number processed first.

**Author scope:** `@me` is your current login ([GitHub](../../../reference/providers/github/babysit-prs/loop.md#pr-discovery)); the `babysit_self_logins` key
in SKILL.md's effective-configuration block adds extra posting identities on top of it. Run the
listing once per identity (`@me` plus each configured extra) and merge the results. Drop the author filter only
in `autopilot` or on an explicit user instruction to widen. A widened discovery includes other
authors' PRs. A dependency-manager PR with failing CI gets the same diagnose-and-fix
attention as any other, but dependency-authored PRs are never merged autonomously in any tier
(SKILL.md cross-tier invariants).

**Draft policy:** drafts stay in the discovery list in
every tier. In the safe tier a draft is evaluated for terminal state, CI, and unaddressed findings,
then reported, never fixed, never marked ready. Worker/autopilot draft handling (zero-blocker
drafts route through a worker; the `/source-control:pull-request ready --unattended` flip only in autopilot) is
defined in SKILL.md.

**Zero-PR fast path:** if discovery returns an empty list, report `No open PRs need
attention.` and call `ScheduleWakeup(delaySeconds=1200, reason="no open PRs",
prompt="/source-control:babysit-prs")`. Exit the iteration.

### 5.0.3 Evidence-based fresh rescan

Every iteration rescans ALL comments on every non-terminal PR. GitHub is the source of truth,
not model memory, not prior-iteration state, not comment counts (why:
[review-discipline.md](../../../reference/review-discipline.md) §1).

**Per-PR rescan flow:**

1. **Terminal check:** read the PR's state ([GitHub](../../../reference/providers/github/babysit-prs/loop.md#per-pr-rescan-reads)).
   MERGED/CLOSED → skip
2. **CI check:** one-off read: the distinct buckets of the PR's checks
   ([GitHub](../../../reference/providers/github/babysit-prs/loop.md#per-pr-rescan-reads)); any
   loop, or more than one worker, reads the head SHA's REST check-runs instead, per
   [pull-request monitor.md](../../pull-request/reference/monitor.md) "Polling CI from more than
   one worker". A `pending` entry is reported as queued or running (with the queued job's
   `runs-on` labels) per that file's "Waiting on a pending check", never waited on with a
   blocking checks watch
3. **Fetch ALL comments:** run
   `bash "<plugin-root>/scripts/fetch-all-pr-comments.sh" <N>` to retrieve every comment
   from all 3 API surfaces (review-thread, issue-level, PR reviews). Full bodies, not counts. The
   script derives owner/repo from the current directory's repository
   ([GitHub](../../../reference/providers/github/babysit-prs/loop.md#per-pr-rescan-reads)); from a cwd that is not
   a checkout of the target repo (e.g. a targeted-recheck pass), export `FETCH_COMMENTS_OWNER` and
   `FETCH_COMMENTS_REPO` first, else it exits with "cannot resolve owner/repo"
4. **Filter own prior replies + classify addressed/unaddressed** per
   [review-discipline.md](../../../reference/review-discipline.md) §1
5. **Extract findings** per [review-discipline.md](../../../reference/review-discipline.md) §2.
   One comment may contain multiple work items

**Needs attention when ANY of:**

- CI has `fail` / `pending` / `in_progress` bucket entries
- Any comment has unaddressed findings (per the §1 classification)

**Skip when ALL of:**

- State is terminal (MERGED/CLOSED)
- All checks pass/skipping AND zero unaddressed findings

**Draft PRs (safe tier):** evaluation stops after this rescan. Report the draft's status
(state, CI, unaddressed findings) and move on. The checkout, freshness-integration, fix, and
thread-resolution steps below apply to non-draft PRs only (per §5.0.2's draft policy).

PRs not needing attention are reported in a one-line status summary and skipped.

### 5.0.4 Structured finding extraction

Finding extraction lives in the plugin-scope reference,
[review-discipline.md](../../../reference/review-discipline.md) §2, including the
subagent dispatch for ≥3-finding comments, the verbatim scope-fenced dispatch prompt, the ledger
contract, and the main-session contract after the subagent returns. Apply it exactly; the
finding-classification gate (§5.1.3 step E) mechanically enforces that classification rows cover
source findings.

## 5.1 Per-PR processing

For each PR needing attention (oldest first):

### 5.1.1 Event-delivery gate

Before monitoring work on each PR, arm event delivery, in order:

1. **Cloud check:** `CLAUDE_CODE_REMOTE=true` → arm no PR-event route (the decision, pointer and
   recheck trigger are in [pull-request monitor.md](../../pull-request/reference/monitor.md)
   §3.0.0); poll CI (REST
   check-runs when more than one worker polls, per the monitor.md section the per-PR rescan flow's CI check cites) +
   the comment fetch on a fixed 60-90s cadence. Skip remaining steps
2. **Push-channel gate:** when your environment ships a GitHub-events push channel (an MCP
   server delivering webhook events into the session), verify it is healthy and arm its PR
   filter for `<N>` (health checks + arming per
   [pull-request monitor.md](../../pull-request/reference/monitor.md) §3.0.05)
3. **Monitor-tool fallback:** channel absent/unhealthy → arm a Monitor watch, re-armed at each
   deadline (60s REST poll, never a blocking checks watch
   ([GitHub](../../../reference/providers/github/babysit-prs/loop.md#per-pr-rescan-reads)); arming pattern per
   [pull-request monitor.md](../../pull-request/reference/monitor.md) §3.0.1)
4. Proceed to the §5.1.3 checklist

A push channel arms for ONE PR at a time. Re-arm for each new PR in the loop.

### 5.1.2 Branch checkout (MANDATORY for accurate exploration)

(`main` below stands in for the repo's default branch.)

Run the checkout procedure ([GitHub](../../../reference/providers/github/babysit-prs/loop.md#branch-checkout-and-push-destination)). It takes
`$PR_NUMBER`, `<headRefName>` and `<watched-owners>`, and sets `CHECKOUT_MODE` (`full` or
`read-only`), `INTEGRATION_STATUS`, and the `lane_push` function every later push uses. Its
rules:

- **Checkout mode.** Decide it by asserting this worktree's HEAD against the TRUE PR head, read
  live from the forge, authoritative for same-repo and fork PRs alike (never a possibly-stale
  `origin/<branch>` remote-tracking ref, which is itself the silent-revert vector this guards;
  [safety.md](safety.md), Checkout And Push Invariants). Acquire the head with the forge's PR
  checkout, never a bare fetch/checkout by branch name. Mutate only when HEAD == the PR head;
  otherwise read-only. Only the fetch of the default branch (always on origin) is done up front,
  for the freshness merge.
  - Uncommitted changes may be another session's WIP: never reset or clean work this loop did not
    create; process read-only.
  - HEAD already at the true PR head keeps full mode only on `$BRANCH` or detached, not on some
    other local branch that merely points at the same commit (a fix committed there would advance
    that unrelated branch while only the refspec push lands on `$BRANCH`). A coincidental same-tip
    match on another branch falls through to the PR checkout paths, which put us on the actual PR
    head.
  - A branch locked in a sibling worktree dead-ends `git checkout $BRANCH` (`already used by
    worktree at ...`). Check the PR out detached at its head instead, which resolves the head for
    same-repo AND fork PRs; operate in detached HEAD at it and push by refspec.
  - Otherwise the PR checkout heals a behind-origin local branch up to the true head and handles
    fork-sourced PRs; a genuinely divergent local (unpushed commits) leaves HEAD != the PR head and
    correctly falls to read-only.
  - After either checkout, full mode requires HEAD == the PR head; anything else is read-only.
- **Push destination.** `push-branch.sh`'s. In a lane, `lane-push.sh` reads the pull request's
  head repository and branch from the forge and builds `https://github.com/<owner>/<repo>.git`
  itself, so a remote, `pushRemote` or `pushurl` that the PR checkout wrote, or that points at
  the base repository or another host, is never pushed to (the cross-repo regression this
  guards; [safety.md](safety.md)). Attended, it is the resolved push remote, refused unless every
  push URL is the PR's head repository. A cross-repo head is writable only when its owner is within
  `<watched-owners>` ([safety.md](safety.md) Stop And Ask: an external-fork head outside the
  watched owners stays read-only even with maintainer edits enabled).
- **`lane_push`.** EVERY push goes through it, and it is the only push: pull-request's
  `push-branch.sh --dir <this checkout> --pr <N>`, which pushes the checkout's HEAD to the PR's head
  branch. Inside a lane (a `[bot]` login) it hands the push to `lane-push.sh` as the target's
  `merge.agent-identity` and refuses unless the session acts as it; an attended run takes the
  operator's own push path (the loop-lane convention's "Lane write identity"). It runs between two auto-merge
  disarms, one immediately before the push and one right after it (someone may arm the old head
  mid-push), because a push keeps auto-merge armed and the new head could merge on ci-status
  alone before the AI reviews re-run ([safety.md](safety.md), "Merge lane: no auto-merge"). It
  never arms auto-merge; nothing does. A failed read or disarm, or a refusal, stops the push.
  Never run a bare `git push`.
- **Branch freshness, MERGE-ONLY (full mode only).** Rebasing would rewrite history and require a
  force-push, which [safety.md](safety.md) ("Never Do Automatically") and orchestration.md's
  never-force-push invariant forbid; the final squash merge flattens interim history, so a merge
  commit here costs nothing the skill cares about. A branch whose HEAD does not contain
  `origin/$DEFAULT_BRANCH` gets `git merge --no-edit "origin/$DEFAULT_BRANCH"`. A clean merge is
  `integrated`: `lane_push` by refspec (works from a detached HEAD too), fast-forward given the
  head assertion, never force; a rejected non-fast-forward
  push means the head moved: re-fetch and stop. A conflicting merge of ≤3 files is
  `conflict-attempting`; more than 3 aborts the merge as `conflict-aborted`. A branch already
  containing the base is `current`.
- **`conflict-attempting` is TRANSIENT.** Resolve it now (per file, take the mechanical
  resolution; on success `git add <files>` + `git merge --continue`, then `lane_push`,
  fast-forward, never force, and set `integrated`), or, if ANY file needs intent judgment,
  `git merge --abort` and set `conflict-aborted`. Never leave an integration in progress
  (unmerged paths break later checkouts + parking). Only the terminal success states
  (`integrated`, `current`) keep full mode; a lingering `conflict-attempting` (resolution
  skipped) degrades to read-only rather than granting write access mid-merge.

**Integration conflict handling (graduated).** Freshness is merge-only: integrate a behind-default
branch via `git merge origin/$DEFAULT_BRANCH` and push by refspec to the PR's head repository
and branch through `lane_push` (`push-branch.sh` between two auto-merge disarms, for a same-repo
head and a write-allowed cross-repo head alike; fast-forward, never force, since rebasing or force-pushing a PR branch as freshness
maintenance is forbidden, safety.md and orchestration.md). Then:

- **Zero conflicts** (`INTEGRATION_STATUS=integrated`): the merge succeeded; `lane_push` and
  continue normally
- **Simple conflicts** (≤3 files, `INTEGRATION_STATUS=conflict-attempting`), a TRANSIENT state: attempt
  resolution immediately; on success continue the merge and `lane_push`
  → `integrated`; if ANY file requires intent judgment, abort the merge → `conflict-aborted`.
  Never proceed to comment processing, parking, or the next PR with an integration in progress.
  Resolve via `/source-control:resolve-conflicts` discipline (understand both sides' intent;
  compose, don't side-pick). A plugin version-bump collision (`.claude-plugin/plugin.json`,
  `CHANGELOG.md`) is mechanical, not intent judgment: run
  `<plugin-root>/scripts/resolve-version-bump-conflict.sh` first; exit 0 resolved and
  staged every such pair. For a plugin listed in the repository's `fragment-plugins.txt` list (under `scripts/`), take main's
  `plugin.json` and `CHANGELOG.md` and move the PR's entry into a changelog fragment, per
  `/source-control:resolve-conflicts` step 3
- **Complex conflicts** (>3 files, `INTEGRATION_STATUS=conflict-aborted`): abort the merge,
  post a PR comment: `"⚠️ Branch is behind $DEFAULT_BRANCH with integration conflicts ({N}
  files). Manual resolution is required before CI will trigger."`. If an interactive terminal,
  also surface to the user directly. Process comments read-only (classification + reply, no
  fixes, since the code may be stale)
- **Already current** (`INTEGRATION_STATUS=current`): no action needed

**Why mandatory:** exploration and research read files from the working tree. Without checkout,
findings are validated against the wrong code. Branch freshness prevents CI failures from stale
code and ensures conflict detection happens proactively.

**Read-only mode:** investigate comments, explore referenced code via
`git show --end-of-options 'origin/<branch>:<path>'` (the head branch name and the path come
from GitHub: substitute each only when it matches `^[A-Za-z0-9._/-]+$`, does not start with
`-` and contains no `..`, and keep the single quotes; any other value reaches no command,
report it as data), research claims, classify, reply with evidence: the full
D1-D5 workflow. Only D6-D7 (edit + commit + push + follow-up reply) are blocked. Read-only is
NOT passive. Every comment still gets investigated and replied to. Fixes that can't be pushed
are described in the reply with exact code changes so the user or the PR's own worktree session
can apply them.

**Full mode:** full flow including the fix cycle (D1-D7). Commit and push to the PR branch (by
refspec, which works from a detached HEAD too) after each wave of fixes.

### 5.1.3 Per-PR iteration checklist

Must hold a HEAD-asserted checkout before starting: HEAD equal to the true PR head
([GitHub](../../../reference/providers/github/babysit-prs/loop.md#per-pr-rescan-reads)), on the branch or in detached HEAD (§5.1.2). Read-only mode still runs
D1-D5 (investigate/classify/reply); only the D6-D7 fix cycle requires full mode. D steps run
**per-finding** with verification gates per [review-discipline.md](../../../reference/review-discipline.md) §3.

- [ ] **A:** Terminal state check (the PR's state, [GitHub](../../../reference/providers/github/babysit-prs/loop.md#per-pr-rescan-reads))
- [ ] **B:** CI checks. Classify every non-pending check (pass/fail/skipped)
- [ ] **C:** Fetch ALL comments and extract findings:
  - [ ] C1: Run `bash "<plugin-root>/scripts/fetch-all-pr-comments.sh" <N>` (all 3 API
    surfaces)
  - [ ] C2: Read every comment body in full
  - [ ] C3: Extract individual findings per
    [review-discipline.md](../../../reference/review-discipline.md) §2
  - [ ] C4: Build the work-item list: one entry per finding, each needing D1-D7
- [ ] **D:** For EACH unaddressed **finding** (not comment): run the full D1–D7.5 cycle with
  its verification gates per [review-discipline.md](../../../reference/review-discipline.md) §3
  (read → explore → validate → classify → react → reply → fix → follow-up → author-conditional
  thread resolution, each verified on GitHub)
- [ ] **E:** Finding-classification gate (**not** a merge-readiness check, see
  [safety.md](safety.md) "Two Gates, One Merge-Ready Authority"). Run
  `bash "<plugin-root>/scripts/babysit-readiness-gate.sh" <N>`. When the
  `${user_config.babysit_self_logins}` option is non-empty (and not a literal unexpanded token),
  append `--extra-self "${user_config.babysit_self_logins}"`. Exit 0 `READINESS_OK`
  is REQUIRED to proceed. Exit 1 `READINESS_BLOCKED reason=under-decomposed` means
  classification rows < source findings → decompose + classify the missing findings, then
  re-run. Exit 4 means jq is missing, the comment fetch failed, or the comment payload did not parse
  as a JSON array. The stderr names the fix; the common cause is owner/repo unresolved from a cwd
  that is not a checkout of the target repo, fixed by exporting
  `FETCH_COMMENTS_OWNER`/`FETCH_COMMENTS_REPO` (inherited into `fetch-all-pr-comments.sh`). Exit 3
  with `reason=identity-unresolved` is NOT an argument error: the flags were valid and the
  current-login lookup failed, so repair the forge CLI's auth
  ([GitHub](../../../reference/providers/github/babysit-prs/loop.md#per-pr-rescan-reads)) rather than editing the command. Every
  run, exit 3 and 4 included, prints exactly one `READINESS_*`
  line; the failure paths print `READINESS_UNPROVEN`, which is NOT a classification verdict and never
  licenses substituting live `gh` state for it (see
  [safety.md](safety.md) §Lane-Script Reachability). **Capture that line verbatim**, since §5.5
  requires it. THEN confirm: all checks terminal + 2-min cooldown
- [ ] **F:** Per-finding classification table + PR status report, both gates as separate fields (see §5.5)

**"Done" means GitHub shows evidence.** A per-finding work item is addressed only when the
verification sub-step confirms the action landed on GitHub. Model memory of "I posted a reply"
is not evidence. Re-query the API.

### 5.1.4 Fix cycle (full mode only)

When in full mode (HEAD asserted at the true PR head, attached or detached per §5.1.2), every
reviewer check run on the head has completed, AND comments are classified VALID after D3
validation, run one wave over all of them:

- [ ] For each VALID comment: edit code to fix it, `git add <specific-files>` (never `-A` or
      `.`), `git commit -m "<type>: <description>"`. No push yet
- [ ] One `lane_push` for the whole wave: `push-branch.sh --dir` (it pushes `HEAD` by refspec to
      the PR's head branch, from a `--detach` checkout too) between two auto-merge
      disarms; never a bare `git push`
- [ ] For each fixed comment, after that push: verify its commit is on the branch (D6 verify
      step, [review-discipline.md](../../../reference/review-discipline.md) §3), then post a
      follow-up reply citing the commit SHA (D7)

**One wave at a time:** address all current comments on this PR → commit each → one push →
then round-robin to the next PR. While a reviewer check run on the head is still running, leave
the PR's fixes to a later iteration rather than push a partial wave, since a finding that lands
after the push costs a second full CI run. Don't jump between PRs mid-wave. After pushing, new CI runs trigger.
Those results are checked on the next babysit iteration (or the next round-robin pass if
processing multiple PRs).

**Re-review trigger after a fix push:** bots that reviewed the PR may need an explicit trigger
to re-evaluate fixes. After pushing, check each bot's trigger mode per
[pull-request readiness.md](../../pull-request/reference/readiness.md) "Expected PR actors":

- **"On every push" trigger:** re-reviews automatically, just wait
- **Manual/smart trigger:** when the review-trigger module is configured (SKILL.md
  effective-configuration block), the orchestrator posts the configured trigger phrase per
  [review-trigger.md](review-trigger.md); unconfigured, the module is dormant, so note the bot's
  own trigger convention from the consuming repo's docs and report instead of inventing one

Research-gate non-trivial fixes (multi-source consensus) per
[pull-request monitor.md](../../pull-request/reference/monitor.md) §3.2. Max 3 CI fix
iterations per PR per babysit pass. Inline-vs-subagent choice for CI log fetching per the same
file's "Inline vs subagent dispatch decision".

### 5.1.5 Human comments

Classify but DO NOT auto-fix. Reply with investigation findings per step D. Note: D4.5
reactions proceed autonomously for human reviewer comments (no approval gate, since babysit runs
without a user present). This differs from the single-PR monitor flow
([pull-request monitor.md](../../pull-request/reference/monitor.md) §3.3.1 step 4), which
pauses for approval in interactive sessions. Report to the user in the babysit iteration output.
Human review items are surfaced, not silently skipped.

### 5.1.6 Transition after a PR is done

When the finding-classification gate passes OR all actionable items are handled for this PR:

1. If a full-mode PR checkout (attached or detached per §5.1.2) has uncommitted changes from a
   failed fix: `git reset --hard HEAD` then `git clean -fd` (unstage + revert tracked + remove
   untracked)
2. Report PR status: classification gate result, blockers remaining, items deferred to human.
   Report the PR **merge-ready only on a merge-gate run whose `ready` is `true`**; without one,
   say merge-readiness was not checked ([safety.md](safety.md) "Two Gates, One Merge-Ready
   Authority")
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

**Engine-backed runs (Python present):** the snapshot's `recommended_cadence` is the cadence
signal. Map it directly to a concrete `ScheduleWakeup.delaySeconds`. The states behind each value
live in [cadence.md](cadence.md); this table owns the seconds:

| `recommended_cadence` | `ScheduleWakeup.delaySeconds` |
|-----------------------|-------------------------------|
| `active`              | 300                           |
| `normal`              | 900                           |
| `quiet`               | 3600                          |
| `idle`                | 3600 (ceiling, see caveat)    |

**This mapping ALWAYS wins** over the generic `/loop` skill's own delay-picking heuristic whenever
a snapshot supplies `recommended_cadence`. Read the field out of the snapshot/state JSON and
schedule from this table. Do not fall back to the generic skill's "lean 1200–1800s" range. In
babysit dynamic mode the `ScheduleWakeup` delay **is** the primary cadence signal, not a fallback
heartbeat sitting behind some other armed wake event, so the generic skill's heartbeat framing does
not apply here: an `active` cycle schedules at 300s, never 1200–1800s.

**Idle ceiling (a true daily cadence cannot run in single-session `/loop`).** `ScheduleWakeup`
clamps `delaySeconds` to `[60, 3600]`, so cadence.md's `idle` = daily (86400s) truncates to the
3600s ceiling, the same wake interval as `quiet`. This is a documented limitation, not a silent
truncation: within `/loop`, `idle` and `quiet` both wake hourly. A genuine daily babysit cadence
needs the durable `/schedule` cron mechanism (a scheduled routine on a real cron interval), not a
single-session `/loop` wakeup. Reach for `/schedule` when that is what is wanted.

The `[60, 3600]` bound is verified 2026-09-06 against Claude Code 2.1.263 and the
[tools reference](https://code.claude.com/docs/en/tools-reference), where `ScheduleWakeup`
"Reschedules the next iteration of a self-paced `/loop`" and picks when the next one runs "between
one minute and one hour out". Recheck when that page names a different range, or when a release
note names `ScheduleWakeup` or self-paced `/loop` scheduling.

**Python-free degrade ladder** (no snapshot available this iteration):

| Condition | Delay | Reason |
|-----------|-------|--------|
| Active events flowing (CI running, fresh comments arrived during this iteration) | 60s | Stay responsive to in-flight activity |
| PRs exist but all currently quiet (no new events, no pending checks) | 270s | Check back soon without idle churn |
| No PRs need attention (all ready, all terminal, or zero open PRs) | 1200s | Long idle, conserve request budget |

```text
ScheduleWakeup(
  delaySeconds: <per the engine recommendation, or the ladder above>,
  reason: "<specific reason for this delay>",
  prompt: "/source-control:babysit-prs"
)
```

## 5.4 NEVER-do list

These constraints override any other instruction within the babysit loop:

- **Never declare an iteration complete or schedule the next wake without a passing
  `babysit-readiness-gate.sh <N>` run** (exit 0 `READINESS_OK`). The gate counts classification
  rows vs source findings and blocks under-decomposition. "I classified them" is not evidence.
  The gate exit code is. See §5.1.3 step E
- **Never report a readiness verdict the gate did not emit.** The §5.5
  finding-classification-gate line quotes the gate's `READINESS_*` stdout verbatim.
  `READINESS_UNPROVEN` (the gate ran, reached no verdict) and a harness-denied call (the gate never
  ran, so there is no line) are both reported as **readiness unproven**, never as a passing
  verdict, and never backfilled from `mergeStateStatus`, the check rollup, or any other live `gh`
  state. See [safety.md](safety.md) §Lane-Script Reachability
- **Never report a PR MERGE-READY off `READINESS_OK`.** That gate proves finding decomposition,
  nothing about GitHub's merge state. Merge-readiness comes only from a merge-gate run whose
  `ready` is `true` ([safety.md](safety.md) "Two Gates, One Merge-Ready Authority"); with no such
  run, report merge-readiness as unchecked rather than asserting it
- **Never survey-and-report without investigating.** Every unaddressed comment gets D1-D7
  (read, explore, validate, classify, reply, fix, follow-up). "Bot findings need classification"
  without classifying is a violation
- **Never trust a finding without validating.** Bot/AI assertions have demonstrated error
  rates. Always verify against actual code (D3) before implementing. Explore the referenced
  code; research non-trivial claims
- **Never process comments from the wrong branch.** HEAD must be asserted at the true PR head
  (attached or detached, §5.1.2) before D2-D3.
  Exploring code on the default branch or another branch produces wrong classifications
- **Never advance to the next PR with unaddressed comments on the current PR.** Focus-first
  rule (§5.0). Complete the current wave before moving on
- **Never skip AI review summaries.** AI-reviewer posts (issue-level comments with
  severity-labeled findings) are actionable comments requiring D1-D7. Same for every AI reviewer
- **Never merge, and never the async merge API.** This loop never merges or enqueues.
  Merge authority exists only behind the `worker`/`autopilot` pinned merge gate (SKILL.md), never a
  raw merge command or async merge call ([GitHub](../../../reference/providers/github/babysit-prs/loop.md#merging-stays-out-of-this-loop))
- **Never wait on, re-run, or push to clear a check held for approval** (`action_required`). Only
  a maintainer releases it; report it for one ([stuck-checks.md](stuck-checks.md))
- **Never `git add -A` or `git add .`:** specific files only
- **Never auto-fix human reviewer comments.** Classify + reply + report to the user
- **Never skip the event-delivery gate.** Run §5.1.1 for every PR
- **Never exceed 3 CI fix iterations** per PR per babysit pass
- **Never leave uncommitted changes** on a full-mode PR checkout (attached or detached) when
  transitioning to the next PR
- **Never skip emoji reactions.** Every classified finding gets a reaction on its parent
  comment (+1 VALID, -1 INCORRECT, eyes UNCERTAIN). Reactions are the fastest audit signal for
  reviewers scanning a PR
- **Never skip the branch freshness check.** Always `git fetch origin <default-branch>` +
  `git merge-base --is-ancestor origin/<default-branch> HEAD` after checkout. Stale branches
  cause CI failures; proactive integration is cheaper than a reactive fix. See §5.1.2
- **Never skip reply verification.** After posting a reply (D5) or follow-up (D7), verify it
  landed on GitHub via API query. Model memory of "I replied" across compaction is not evidence
- **Never skip resolving a BOT-authored thread; never resolve a HUMAN or OWN thread.** Once
  <!-- contract-restatement-begin: D7.5-thread-eligibility -->
  <!-- contract-restatement-begin: D7.5-merge-authorization -->
  EVERY finding in an inline review comment opened by a bot reviewer carries an eligible
  disposition (a pushed fix, a fix in a linked PR the reply cites, a grounded `VALID (defer)`, or
  `INCORRECT` with counter-evidence;
  a single `UNCERTAIN` holds the thread open), resolve that thread (D7.5, author- and
  classification-conditional). **The worker tier is bounded further by its own contract:** it may
  resolve only a thread already `isOutdated` in its dispatch snapshot (`orchestration.md`, Worker
  Contract), so a disposition that leaves the thread current, a grounded deferral, a fix in a
  linked PR, or an `INCORRECT` carrying no fix, routes to the independent resolution dispatch
  ([independent-resolution.md](independent-resolution.md)), which verifies the disposition and
  resolves through the wrapper; the merging worker never resolves it itself, and neither does the
  orchestrator that dispatches the resolver. The worker reports such a thread as
  addressed-but-unresolvable, and **in a thread-resolving tier** (`worker`, `autopilot`) the
  orchestrator routes it, under the PR's worker lease, to a fresh subagent that authored neither the
  fix nor the counter-evidence. **The safe tier dispatches nothing.** It never resolves threads,
  through a subagent or otherwise. Where no dispatch is reachable, whether the safe tier, no subagent
  tools, or a bound the dispatch cannot cross (a security/P1 thread, a multi-finding thread, a human
  thread, evidence the world rejects), the fail-closed fallback applies unchanged:
  leave the thread unresolved, do not merge, and report the PR with the addressed-but-unresolvable
  thread named. An unreachable authorization is never a license to self-resolve. A `VALID (defer)` must be grounded per D4.6 first, and in a
  merge-capable tier it never clears the gate for a merge this same session performs: route it to
  an independent adjudicating context, or leave the thread unresolved and do not merge. Leave
  HUMAN-authored threads for the human to close; never resolve your own. Open bot-thread count is
  a visible signal to reviewers
  <!-- contract-restatement-end: D7.5-merge-authorization -->
  <!-- contract-restatement-end: D7.5-thread-eligibility -->
- **Never process your own prior replies as findings.** Filter out comments from your own
  posting identities that match the classification reply pattern. See
  [review-discipline.md](../../../reference/review-discipline.md) §1 step 1

## 5.5 Checklist-driven output format

Every iteration MUST output a completed checklist with evidence per step. Free-form narrative
reports are not acceptable. They hide skipped steps.

**Gate-enforced:** completing an iteration requires a passing `babysit-readiness-gate.sh <N>` run
(§5.1.3 step E). To mechanically gate checklist completeness too, write this iteration's checklist
to a file in your working-notes location and pass `--checklist <file>`. The gate exits non-zero
while any `- [ ]` box is unticked, so an incomplete checklist cannot be declared done. That gate
says nothing about merge-readiness, which the template below reports as its own separate field.

**Gate verdict, quoted verbatim.** The per-PR "Gate verdict" line carries the gate's `READINESS_*`
stdout as printed, never paraphrased, never reconstructed from memory. The gate prints exactly one
such line on every run, so the only way to have none is that the gate never ran; in that case the
line reads `not emitted — harness denied: <exact command>` and the readiness line reads *readiness
unproven*. This is what stops a blocked gate from being indistinguishable from a passing one
([safety.md](safety.md) §Lane-Script Reachability).

```text
## Babysit iteration [<timestamp>]

### A. PR Discovery
- [ ] Fetched open PRs: <N> total, <M> needing attention, <K> skipped
- [ ] Processing order (oldest first): #<N1>, #<N2>, ...

### B. Per-PR Processing

#### PR #<N>: <title> (<branch>)
- [ ] **Branch:** checked out <branch> (mode: full/read-only)
- [ ] **Branch freshness:** <current/integrated/conflict-aborted>, evidence: `git merge-base` output
- [ ] **CI:** <pass/fail/pending>, evidence: the PR's checks listing output
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
- [ ] Finding-classification gate: `<paste the gate's READINESS_* line here, whole>`,
  the captured stdout line exactly as printed, every field included
  (`findings=`/`classified=`/`checklist=`, `reason=`/`pr=`); an abbreviated form is a
  reconstruction, and a reconstruction carries no provenance. Or
  `not emitted — harness denied: <exact command>` when the harness blocked the call
- [ ] Merge gate: `ready: true` / `ready: false` with <blockers> / not checked this iteration
- [ ] Remaining blockers / items deferred to human: <list>

### C. Iteration Summary
- [ ] All PRs processed: YES/NO
- [ ] Parked on home branch: YES
- [ ] **Next wake:** <delay>s, <reason>
```

Every `- [ ]` must be ticked `- [x]` with evidence before the iteration ends. Unticked boxes =
incomplete iteration. Do not schedule the next wake until addressed or explicitly deferred
with reason.

## 5.6 Performance notes

- **Run the D5/D6/D7 verification sub-steps on every pass.** They exist because model
  memory is unreliable across compaction boundaries. One API call to confirm costs seconds;
  acting on false memory costs an entire re-processing cycle
- **Quality over speed.** Processing 3 findings thoroughly with verified evidence is better
  than "processing" 10 findings with blanket classifications and no verification
- **One finding at a time.** Complete per-finding D1-D7 for finding N before starting finding
  N+1. Interleaving findings across comments produces partial work that looks complete but
  isn't
- **Evidence-based state, not memory-based state.** Never say "I already replied to that".
  Check GitHub. Never say "I already pushed that fix". Check the remote. GitHub is the state
  store; this session's memory is ephemeral
