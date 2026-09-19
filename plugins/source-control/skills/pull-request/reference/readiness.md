# PR Merge Readiness Checklist

Single source of truth for merge readiness. Both monitor.md (Phase 3.4) and merge.md (Phase 4.1) reference this file. **Every item must be satisfied before suggesting merge. No exceptions, regardless of PR type or `full` mode.**

## Expected PR actors

Monitor must discover and track every actor that participates in PRs. Actors fall into three categories based on how they report:

### Actor categories

| Category | How they report | How to discover | Timing |
|----------|----------------|-----------------|--------|
| **Check-run actors** | `gh pr checks` status/conclusion fields | Poll `gh pr checks <pr_number>` until all reach terminal state | Deterministic: GitHub triggers them on push |
| **Check-run + comment actors** | Both a check run AND a PR comment | Poll checks AND comments | Check run arrives first, comment follows |
| **Comment-only actors** | PR comments only, no check run | Poll `gh api --paginate "repos/{owner}/{repo}/issues/<pr_number>/comments?per_page=100"` | Non-deterministic: arrives at an unpredictable time |

### Discovery (not hardcoded)

**Don't assume a fixed list of actors.** On each monitoring cycle, discover what's present:

1. **Check runs**: `gh pr checks <pr_number> --json name,state,bucket` shows ALL check runs and commit statuses. Every entry here must reach terminal state and be classified
2. **Comments**: `gh api --paginate "repos/{owner}/{repo}/issues/<pr_number>/comments?per_page=100"` lists them. Every comment from a `[bot]` account is a PR actor needing evaluation. Unpaginated, a bot that commented early on a busy PR is simply absent from the actor list
3. **Security scans**: any check run containing "security", "guardian", "CodeQL", "Snyk", "Dependabot", or similar in the name is a security actor. These get mandatory triage (see Gate 3)

**Required vs soft heuristic:**

- Check runs showing `FAILURE` → **required**: must be investigated and classified before merge
- Check runs showing `SUCCESS` or `SKIPPED` → **pass**: no action needed
- Security-related check runs (any state) → **required**: must evaluate findings even on SUCCESS (confirm no suppressions are hiding issues)
- Comment-only bot comments → **soft**: evaluate if posted, but don't block forever waiting. Apply cooldown period (Gate 5) to give them time to arrive
- CI gateway check (whatever it's named) → **required**: must pass

### Common actors (reference shapes)

Reference shapes only. The discovery logic above is authoritative, not this table. The consuming repo's own workflow set defines the real actor list.

| Actor | Reports as | Notes |
|-------|-----------|-------|
| CI workflows | Check runs (names vary by ecosystem) | Repos often aggregate into a single required gateway check |
| AI reviewers | Check run, PR review, or both, varying by reviewer | Where a reviewer's round lands, which push its comments belong to, and how long it takes are per-reviewer facts. Look the discovered login up in [reviewer-shapes.md](reviewer-shapes.md); a reviewer with no record there gets the Gate 5 cooldown and no reviewer-specific wait |
| Security scanners (GitGuardian, Snyk, CodeQL, …) | Check run + comment | Mandatory triage per Gate 3 when present |

### When actors change

When a security scanner or reviewer is added, replaced, or removed:

1. Discovery logic handles it automatically: new check runs appear in `gh pr checks`, new bot comments appear in the comments API
2. If a new actor is comment-only and critical, consider converting it to a required status check via a GitHub Action

## Reading GitHub list APIs

Every gate below reads a GitHub list endpoint, and every one of those endpoints returns **30 items per page** by default and reports nothing when it truncates. A truncated read is not a visibly short answer. It is a confidently wrong one. Three rules, all absolute:

**1. Paginate every list read.** `--paginate` with `per_page=100`. Without it, "is X present?" answers a silent *no* for anything on a page you never fetched, indistinguishable from X not existing. A PR head with more than 30 check runs makes the unpaginated form drop required contexts silently, so a reader concludes a context never attaches when it attached and was green.

**2. Never pair a positional index with a list.** `.[-1]` on a truncated list is the 30th-oldest item, not the newest. The read returns a real item, plausibly shaped, and simply wrong. Select by the property you actually care about (an id, a SHA, an author, a timestamp) so the query states its own intent and cannot be silently satisfied by the wrong record. **Where the query is a control gate you will act on, such as "did my write land?", one property is usually not enough.** Ask what else could satisfy this selector, and constrain that too: a SHA in a comment body proves the SHA was mentioned, not that *you* posted it, so a reviewer quoting it passes the gate while your failed write goes unnoticed. Pin the identity as well.

**3. Never reduce across pages inside `--jq`.** With `--paginate`, `gh` applies `--jq` to **each page separately**, so `length`, `sort_by`, `add`, `max`, `group_by`, anything that folds a whole list, silently answers per page. A count over four pages prints four numbers, none of them the total; a `sort_by` emits four separately-sorted arrays. Element-wise filters (`.[] | select(f)`, `.[] | f`) are safe, because their results simply concatenate. Bare `map(f)` is not, because it builds an array per page. Use `map(f) | .[]` or `.[] | f` instead. When the operation folds, drop `--jq` and slurp the page stream with `jq -s`, indexing pages with `.[][]`.

Pagination alone only moves the cliff from 30 to 100, so where an endpoint reports a total, assert against it, slurping per rule 3:

```bash
gh api --paginate "repos/{owner}/{repo}/commits/<sha>/check-runs?per_page=100" \
  | jq -s -r '"total_count=\(.[0].total_count) returned=\([.[].check_runs[]] | length)"'
```

The two numbers must be equal. When they are not, every conclusion drawn from that response is unsound. Re-fetch before reasoning. The comments and reviews endpoints report no total, so rule 1 plus a property-based selector is the whole discipline there.

## The readiness checklist

Run this checklist **twice**: once when monitor declares convergence (3.4), and again immediately before merge execution (4.1). Second run catches late-arriving comments or status changes between monitor completion and merge.

### Gate 1: All check runs in terminal state

```bash
gh pr checks <pr_number> --json name,state,bucket
```

- [ ] Every check run is in a terminal state (`SUCCESS`, `FAILURE`, `SKIPPED`), none `PENDING` or `IN_PROGRESS`
- [ ] No unexpected checks missing (compare against expected actors table)

**Gotcha: one name may show duplicate entries (`SUCCESS` check-run + stuck `PENDING` commit-status).** `gh pr checks` aggregates BOTH workflow check-runs AND external commit-statuses, so a workflow and an external app posting under the same name produce two rows: the workflow's check-run resolves cleanly, while the app's redundant commit status may never finalize and sits at `PENDING` indefinitely. When you see two rows for one name, one `pass|SUCCESS` with a `link` and one `pending|PENDING` with no link, treat the check-run as authoritative. Verify with the duplicated name in place of `<name>`:

```bash
gh api --paginate "repos/{owner}/{repo}/commits/<sha>/check-runs?per_page=100" \
  --jq '.check_runs[] | select(.name | test("<name>"; "i")) | "\(.status) \(.conclusion)"'
```

If `completed success`, the stuck commit-status is the redundant external bot. Classify it as non-blocking, document, and proceed. `mergeStateStatus=UNSTABLE` will reflect the stuck status but does NOT block merge when the repo's required checks are green.

The pagination is not optional and the completeness assertion is not hygiene. See [Reading GitHub list APIs](#reading-github-list-apis).

### Gate 2: All failures evaluated

For every check run with `bucket == "fail"`:

```bash
gh pr checks <pr_number> --json name,state,bucket --jq '.[] | select(.bucket == "fail")'
```

- [ ] Each failure has been **investigated**: logs read via the monitor §3.1 tiered fetch chain (bundled `fetch-annotations.sh` → `fetch-failed-logs.sh` full untruncated ZIP; `gh run view <run-id> --log-failed` only as a last-resort eyeball, since it truncates at the CLI display layer)
- [ ] Each failure is **classified**: real failure (fix required) OR informational (document why safe to proceed)
- [ ] Informational failures explicitly documented in monitoring report with exact error message
- [ ] **No unclassified failures**: every `FAILURE` state must have an explicit disposition

### Gate 3: Security scans evaluated

Identify all security-related actors (check runs with "security", "guardian", "CodeQL", "Snyk", "Dependabot", etc. in the name, plus any `[bot]` comments about secrets/vulnerabilities).

- [ ] Every security actor's check run status checked
- [ ] If a security actor posted a comment: **read full comment**, identify each finding
- [ ] Each finding classified: **true positive** (BLOCK: fix or remove the secret/vulnerability), **false positive** (document why, e.g., "code examples in course-digest, not actual secrets"), or **not applicable**
- [ ] True positives resolved before merge, no exceptions
- [ ] False positives documented in monitoring report (rationale for dismissal)
- [ ] Findings dismissed in scanning tool's UI/dashboard as appropriate (e.g., "Skip: false positive" for GitGuardian, "Dismiss alert" for CodeQL/Dependabot)

### Gate 4: All comments processed

```bash
# PR reviews (review body — a reviewer that posts no issue comment lands here)
gh api --paginate "repos/{owner}/{repo}/pulls/<pr_number>/reviews?per_page=100" \
  | jq -r '.[] | "\(.user.login): \(.state) — \(.body[:100])"'

# Inline review comments (diff-level)
gh api --paginate "repos/{owner}/{repo}/pulls/<pr_number>/comments?per_page=100" \
  | jq -r '.[] | "\(.user.login): \(.body[:100])"'

# General PR comments (conversation tab)
gh api --paginate "repos/{owner}/{repo}/issues/<pr_number>/comments?per_page=100" \
  | jq -r '.[] | "\(.user.login): \(.body[:100])"'
```

- [ ] Every substantive comment from every reviewer (bot or human) has been:
  - Read and understood
  - Classified per monitor.md 3.3 (VALID fix now / VALID defer / INCORRECT / UNCERTAIN)
  - Reacted to (thumbs up/down for bots, user approval for humans)
  - Replied to with evidence
- [ ] No unprocessed comments exist
- [ ] Every discovered comment-only actor waited for on the terms Gate 5 sets for it

### Gate 5: Cooldown period

- [ ] **Minimum 2 minutes** have elapsed since last check-run completion or comment arrival
- [ ] Prevents race condition where an actor hasn't posted yet but will shortly
- [ ] If a new comment or check result arrives during cooldown, **restart cooldown**
- [ ] **Per-reviewer wait:** take the reviewer logins discovery produced, the `[bot]` authors across the three comment surfaces and the reviewers on the reviews endpoint, and look each one up in [reviewer-shapes.md](reviewer-shapes.md). A login with a recorded shape is waited for on that record's terms, which distinguish a round that finished with findings, a round that finished with none, and a round that never started. A login with no record, or whose signal that file records as not observed, gets the cooldown above and nothing further: never hold the gate open for a signal no record says arrives, and never treat a check-run `pass` as "no comments coming" unless that reviewer's record says its check run is posted after its comments
- [ ] **A reviewer that posted nothing has not passed the gate, and the wait for it is bounded.** Silence is a round that never started as often as it is a round with no findings, and the two are told apart by the reviewer's own record, not by the clock. End the wait for a reviewer on the first of three events: its record's no-findings signal appears; findings appear from it on **any** of the three surfaces, not inline comments alone, since a reviewer that posts its findings only in a review body would otherwise read as still working forever; or the wait passes the bound below. Then, and only then, the gate moves on
- [ ] **The bound is the reviewer's recorded round latency plus the cooldown above, and at least five minutes.** Past it, stop holding the gate: name that reviewer in the readiness verdict as not yet responded, say which of its artifacts are missing, and let the human weigh the missing review against merging. A reviewer with no recorded latency gets the same five-minute floor. Reaching the bound is a reported outcome, never a silent pass and never a reason to keep re-firing the trigger phrase in a loop
- [ ] **Scope the wait to the current push.** Comments from an earlier round are not evidence that this round finished, and each surface carries a different field for "which commit was this written against". Inline review comments (`pulls/<pr>/comments`) carry both `original_commit_id` and `commit_id`; select on `original_commit_id`. The reviews endpoint (`pulls/<pr>/reviews`) carries `commit_id` alone, frozen at the reviewed commit. Issue-level comments (`issues/<pr>/comments`) carry no commit field at all, so scope those by `created_at` against the push time. For the inline surface, against the current HEAD SHA, one reviewer per run with its discovered login in the `--arg login` value:

  ```bash
  HEAD_SHA=$(git rev-parse HEAD)
  gh api --paginate "repos/{owner}/{repo}/pulls/<pr>/comments?per_page=100" \
    | jq -s --arg sha "$HEAD_SHA" --arg login "<discovered reviewer login>" \
      '[.[][] | select(.user.login == $login and .original_commit_id == $sha)] | length'
  ```

  `commit_id` is the wrong field for this question: it re-anchors to the newest head while a comment's hunk still applies, so it counts surviving prior-round comments as current and short-circuits the wait. Unpaginated, the count also undercounts: the comments you are waiting on are the newest, and on a PR with prior review rounds the newest are exactly what page 1 omits. The count is slurped rather than passed to `--jq` for the reason rule 3 gives: a reduction like `length` inside `--jq` runs per page and prints one number per page, never the total.

<!-- contract-restatement-begin: B2-lane-productivity -->
- [ ] **A review lane that produced nothing for this round is SUBSTITUTED before the gate clears, not merely reported.** Take the roster for this item from `gh pr checks`, NOT from the bot authors the reviewer roster above is built from: a lane that posted nothing is missing from every author-derived roster by construction, so that roster would apply this item to an empty set, which is exactly the lane this item exists for. Its own check row cannot settle it either: these lanes report on their session rather than on their output, so a session that ends without error is green whether or not it reviewed anything, and cost is no signal since the session is billed either way. Judge the lane by the artifacts the scoping rule above attributes to this head, bounding a rerun of the same head by timestamp against the run's start, since a rerun's artifacts carry the same SHA; zero attributed artifacts means nothing was reviewed, however green the row. Run a local review over the same diff (`/review:fanout` for breadth, or the bundled `/code-review` against an explicit target for a correctness lane, whichever resolves in this session), then name every absent lane and its substitute on the verdict's `Review lanes:` line. A lane whose posted body admits it fell back to a manual pass counts as absent on the same terms. This is what the bound above hands off to: reaching the bound ends the wait, it does not supply the review.
<!-- contract-restatement-end: B2-lane-productivity -->

### Gate 6: No pending work

- [ ] No fix pushes are in flight (a push restarts the entire monitoring loop)
- [ ] No VALID (fix now) comments remain unaddressed
- [ ] No UNCERTAIN classifications remain unresolved (escalate to user)

## Readiness verdict

Only when ALL gates pass, present:

```markdown
## PR Ready for Merge

**PR:** #N: title
**Check runs:** X passed, Y skipped, Z failed-informational
**Security:** GitGuardian [evaluated, N findings: X false positive, Y not applicable]
**Comments:** X from N reviewers: Y fixed, Z deferred, W incorrect
**Cooldown:** 2+ min since last activity
**Reviewers:** [each discovered reviewer: responded, no-findings signal, or not yet responded at the bound with its missing artifacts named]
**Review lanes:** [each lane on the checks roster: productive, or ABSENT with what was run locally in its place]
**Failures classified:**
- `review`: FAILURE, usage limit (informational, safe to proceed)
- [any other failures with classification]

**All readiness gates passed. Recommend merge.**
```

If ANY gate fails, present which gates failed and what action is needed. **Never suggest merge with open gates.**

## `full` mode behavior

In `full` mode, readiness gates are NOT relaxed. Only difference: transition from monitor → merge is automatic **when all gates pass**. If any gate fails, `full` mode pauses and reports. It does not skip gates.

## Recap

The four failures the gates above exist to prevent:

1. **Merging with FAILURE check runs.** Never suggest merge while any check shows FAILURE without explicit classification (Gate 2)
2. **Ignoring security scan results.** A security actor's check run and comment are both evaluated before merge (Gate 3)
3. **Not waiting for comment-only actors.** A review bot can post minutes after PR creation; the cooldown gives it time (Gate 5)
4. **Treating "no comments" as "ready".** An empty comment list may mean reviewers have not posted yet (Gate 5)
