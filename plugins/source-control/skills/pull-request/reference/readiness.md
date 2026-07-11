# PR Merge Readiness Checklist

Single source of truth for merge readiness. Both monitor.md (Phase 3.4) and merge.md (Phase 4.1) reference this file. **Every item must be satisfied before suggesting merge — no exceptions, regardless of PR type or `full` mode.**

## Expected PR actors

Monitor must discover and track every actor that participates in PRs. Actors fall into three categories based on how they report:

### Actor categories

| Category | How they report | How to discover | Timing |
|----------|----------------|-----------------|--------|
| **Check-run actors** | `gh pr checks` — status/conclusion fields | Poll `gh pr checks <pr_number>` until all reach terminal state | Deterministic — GitHub triggers them on push |
| **Check-run + comment actors** | Both a check run AND a PR comment | Poll checks AND comments | Check run arrives first, comment follows |
| **Comment-only actors** | PR comments only — no check run | Poll `gh api repos/{owner}/{repo}/issues/<pr_number>/comments` | Non-deterministic — arrives at unpredictable time |

### Discovery (not hardcoded)

**Don't assume a fixed list of actors.** On each monitoring cycle, discover what's present:

1. **Check runs**: `gh pr checks <pr_number> --json name,state,bucket` — shows ALL check runs and commit statuses. Every entry here must reach terminal state and be classified
2. **Comments**: `gh api repos/{owner}/{repo}/issues/<pr_number>/comments` — every comment from a `[bot]` account is a PR actor needing evaluation
3. **Security scans**: any check run containing "security", "guardian", "CodeQL", "Snyk", "Dependabot", or similar in the name is a security actor — these get mandatory triage (see Gate 3)

**Required vs soft heuristic:**

- Check runs showing `FAILURE` → **required** — must be investigated and classified before merge
- Check runs showing `SUCCESS` or `SKIPPED` → **pass** — no action needed
- Security-related check runs (any state) → **required** — must evaluate findings even on SUCCESS (confirm no suppressions are hiding issues)
- Comment-only bot comments → **soft** — evaluate if posted, but don't block forever waiting. Apply cooldown period (Gate 5) to give them time to arrive
- CI gateway check (whatever it's named) → **required** — must pass

### Common actors (reference shapes)

Reference shapes — the discovery logic above is authoritative, not this table. The consuming repo's own workflow set defines the real actor list.

| Actor | Reports as | Notes |
|-------|-----------|-------|
| CI workflows | Check runs (names vary by ecosystem) | Repos often aggregate into a single required gateway check |
| Claude review | Check run + may post comments | May fail on usage limits — classify from logs |
| Codex | Commit status (`codex-review`) + PR review | Posts via the Reviews API (not issue comments). Trigger configurable: "On every push" recommended for re-review after fixes. **Emoji signals:** 👀 (eyes) = reviewing, will post comments — MUST wait for comments before declaring ready; 👍 (thumbs-up) = approves, no findings, no comments coming. **Comment timing:** the `codex-review` check can pass BEFORE inline comments are posted — check-run `pass` does NOT mean "no comments." When the 👀 emoji is present, poll for codex bot comments until they arrive or a 3-min timeout elapses. **May not auto-fire** — if no reaction after ~3 min, post `@codex review` as a PR comment to trigger manually. Codex reacts to the trigger comment (not the PR body) |
| Security scanners (GitGuardian, Snyk, CodeQL, …) | Check run + comment | Mandatory triage per Gate 3 when present |

### When actors change

When a security scanner or reviewer is added, replaced, or removed:

1. Discovery logic handles it automatically — new check runs appear in `gh pr checks`, new bot comments appear in the comments API
2. If a new actor is comment-only and critical, consider converting it to a required status check via a GitHub Action

## The readiness checklist

Run this checklist **twice**: once when monitor declares convergence (3.4), and again immediately before merge execution (4.1). Second run catches late-arriving comments or status changes between monitor completion and merge.

### Gate 1: All check runs in terminal state

```bash
gh pr checks <pr_number> --json name,state,bucket
```

- [ ] Every check run is in a terminal state (`SUCCESS`, `FAILURE`, `SKIPPED`) — none `PENDING` or `IN_PROGRESS`
- [ ] No unexpected checks missing (compare against expected actors table)

**Gotcha — `codex-review` may show duplicate entries (`SUCCESS` check-run + stuck `PENDING` commit-status).** `gh pr checks` aggregates BOTH workflow check-runs AND external commit-statuses. `codex-review.yml` workflow posts a real check-run that resolves cleanly; the external Codex bot ALSO posts a redundant commit status that may never finalize (sits at `PENDING` indefinitely). When you see two `codex-review` rows — one `pass|SUCCESS` with a `link`, one `pending|PENDING` with no link — treat check-run as authoritative. Verify via:

```bash
gh api repos/{owner}/{repo}/commits/<sha>/check-runs --jq '.check_runs[] | select(.name | test("codex"; "i")) | "\(.status) \(.conclusion)"'
```

If `completed success`, the stuck commit-status is the redundant external bot — classify as non-blocking, document, and proceed. `mergeStateStatus=UNSTABLE` will reflect the stuck status but does NOT block merge when the repo's required checks are green.

### Gate 2: All failures evaluated

For every check run with `bucket == "fail"`:

```bash
gh pr checks <pr_number> --json name,state,bucket --jq '.[] | select(.bucket == "fail")'
```

- [ ] Each failure has been **investigated** (logs read via `gh run view <run-id> --log-failed`)
- [ ] Each failure is **classified**: real failure (fix required) OR informational (document why safe to proceed)
- [ ] Informational failures explicitly documented in monitoring report with exact error message
- [ ] **No unclassified failures** — every `FAILURE` state must have an explicit disposition

### Gate 3: Security scans evaluated

Identify all security-related actors (check runs with "security", "guardian", "CodeQL", "Snyk", "Dependabot", etc. in the name, plus any `[bot]` comments about secrets/vulnerabilities).

- [ ] Every security actor's check run status checked
- [ ] If a security actor posted a comment: **read full comment**, identify each finding
- [ ] Each finding classified: **true positive** (BLOCK — fix or remove the secret/vulnerability), **false positive** (document why — e.g., "code examples in course-digest, not actual secrets"), or **not applicable**
- [ ] True positives resolved before merge — no exceptions
- [ ] False positives documented in monitoring report (rationale for dismissal)
- [ ] Findings dismissed in scanning tool's UI/dashboard as appropriate (e.g., "Skip: false positive" for GitGuardian, "Dismiss alert" for CodeQL/Dependabot)

### Gate 4: All comments processed

```bash
# PR reviews (review body — bots like Codex post here)
gh api --paginate repos/{owner}/{repo}/pulls/<pr_number>/reviews \
  | jq -r '.[] | "\(.user.login): \(.state) — \(.body[:100])"'

# Inline review comments (diff-level)
gh api --paginate repos/{owner}/{repo}/pulls/<pr_number>/comments \
  | jq -r '.[] | "\(.user.login): \(.body[:100])"'

# General PR comments (conversation tab)
gh api --paginate repos/{owner}/{repo}/issues/<pr_number>/comments \
  | jq -r '.[] | "\(.user.login): \(.body[:100])"'
```

- [ ] Every substantive comment from every reviewer (bot or human) has been:
  - Read and understood
  - Classified per monitor.md 3.3 (VALID fix now / VALID defer / INCORRECT / UNCERTAIN)
  - Reacted to (thumbs up/down for bots, user approval for humans)
  - Replied to with evidence
- [ ] No unprocessed comments exist
- [ ] Comment-only actors (Codex) waited for per timeout in expected actors table

### Gate 5: Cooldown period

- [ ] **Minimum 2 minutes** have elapsed since last check-run completion or comment arrival
- [ ] Prevents race condition where an actor hasn't posted yet but will shortly
- [ ] If a new comment or check result arrives during cooldown, **restart cooldown**
- [ ] **Codex comment wait:** if `codex-review` check passed AND codex reacted with 👀 (eyes), wait for codex inline comments to arrive — up to 3-min timeout after check completion. 👍 (thumbs-up) without 👀 = no comments expected, skip wait. **Scope to current push:** filter by `commit_id` matching current HEAD SHA (codex comments carry the reviewed commit's SHA). On PRs with prior codex comments from earlier pushes, unscoped poll short-circuits on stale comments:

  ```bash
  HEAD_SHA=$(git rev-parse HEAD)
  gh api repos/{owner}/{repo}/pulls/<pr>/comments \
    --jq "[.[] | select(.user.login == \"chatgpt-codex-connector[bot]\" and .commit_id == \"$HEAD_SHA\")] | length"
  ```

### Gate 6: No pending work

- [ ] No fix pushes are in flight (a push restarts the entire monitoring loop)
- [ ] No VALID (fix now) comments remain unaddressed
- [ ] No UNCERTAIN classifications remain unresolved (escalate to user)

## Readiness verdict

Only when ALL gates pass, present:

```markdown
## PR Ready for Merge

**PR:** #N — title
**Check runs:** X passed, Y skipped, Z failed-informational
**Security:** GitGuardian [evaluated — N findings: X false positive, Y not applicable]
**Comments:** X from N reviewers — Y fixed, Z deferred, W incorrect
**Cooldown:** 2+ min since last activity
**Failures classified:**
- `review`: FAILURE — usage limit (informational, safe to proceed)
- [any other failures with classification]

**All readiness gates passed. Recommend merge.**
```

If ANY gate fails, present which gates failed and what action is needed. **Never suggest merge with open gates.**

## `full` mode behavior

In `full` mode, readiness gates are NOT relaxed. Only difference: transition from monitor → merge is automatic **when all gates pass**. If any gate fails, `full` mode pauses and reports — it does not skip gates.

## Anti-patterns (from an observed incident)

These specific failures must never recur:

1. **Merging with FAILURE check runs** — an observed PR had two FAILURE check runs visible in `gh pr checks` and was merged anyway. Monitor must NEVER suggest merge when any check shows FAILURE without explicit classification
2. **Ignoring security scan results** — a security scanner posted both a check run and a comment. Neither was evaluated before merge
3. **Not waiting for comment-only actors** — a review bot posted 8 minutes after PR creation. Monitor declared readiness before bot had a chance to post
4. **Treating "no comments" as "ready"** — "No comments" may mean reviewers haven't posted yet, not that there are no issues. Cooldown period prevents this race condition
