# Phase 3: Monitor (CI + comments + fixes)

Phase 3 is an **async event loop**, not a sequential pipeline. After every push (initial PR creation, CI fix, comment fix), monitor CI status AND process comments concurrently as they arrive. Don't wait for all CI checks to complete before reading comments — bots post at different times.

## 3.0 Expected PR actors and merge readiness

**Before polling, know who you're waiting for.** The [readiness checklist](readiness.md) defines the authoritative registry of all expected PR actors — CI workflows, security scanners, AI reviewers, and comment-only bots. Read that file before starting the monitoring loop.

**Key principle: "no comments" ≠ "ready to merge."** An empty comment list may mean reviewers haven't posted yet, not that there are no issues. The readiness checklist includes a **cooldown period** (minimum 2 minutes after the last check-run completion or comment arrival) to prevent the race condition where monitor declares readiness before all actors post.

**Bounded autonomy — NEVER auto-merge.** Monitor is a co-pilot, not an autopilot. It evaluates, classifies, and recommends — it does not merge. The merge decision is always a human gate (Phase 4), even in `full` mode. The only difference in `full` mode: readiness gates are checked automatically — never relaxed. The user must explicitly approve every merge via `/pull-request merge` or manual `gh pr merge`. No auto-merge, no `--auto` flag, no autonomous merge under any condition.

## 3.0.0 Cloud session baseline poll

**Platform-conditional:** cloud/headless sessions (`CLAUDE_CODE_REMOTE=true`) have no push-channel capability. They use `gh` CLI polling as the only PR-activity source.

**If `CLAUDE_CODE_REMOTE=true` (cloud session):**

Establish a baseline poll: `gh pr checks <N>` + the three comment-surface fetches (per-iteration checklist steps C1-C3) every 60-90s in a blocking loop until all readiness gates pass.

**If local CLI session (`CLAUDE_CODE_REMOTE` not set or `false`):** skip this section. Event delivery is handled by the push-channel primary path (§3.0.05) when available, otherwise by the Monitor watch (§3.0.1).

## 3.0.05 Push-channel primary path (local CLI sessions, optional)

**Preferred over §3.0.1 Monitor watch — when your environment provides it.** Some environments ship a GitHub-events push channel: an MCP server paired with a webhook forwarder (e.g. the `cli/gh-webhook` gh extension) that delivers `check_run` / `workflow_run` / `pull_request*` / `issue_comment` events straight into the active session — zero idle polling, ~0 request cost between events.

**Activation gate — verify, never assume:**

1. Confirm the channel's MCP server is registered in this session (its status tool responds).
2. Verify its delivery pipeline is healthy per the channel's own docs (broker/forwarder process alive, subscriber connected to the LIVE broker — a stale subscriber whose connection looks "open" against a dead or replaced broker is indistinguishable from a healthy one without a health cross-check; when the channel exposes a broker address, cross-check it against the live process before trusting it).
3. Arm the channel's PR filter for `<N>` so events scope to the monitored PR.

**If all checks pass → channel mode active:**

- Skip §3.0.1 Monitor-watch arming entirely
- Process channel event arrivals per §3.1 (each event triggers a single iteration; zero polling between events)
- Continue to honor §3.0.5 loop-aware self-termination — channel mode does not change merge gating

**If the environment has no such channel, or any check fails and can't be remediated → fall through to §3.0.1 Monitor watch** with a one-line note: `Push notifications unavailable — using Monitor tool (30s poll).`

## 3.0.1 Auto-watch setup (Monitor tool)

**Every monitor invocation MUST ensure a session-persistent event watch exists.** Runs immediately after 3.0.0 — before terminal state checks, CI polling, and comment processing.

1. Resolve PR identity: `PR_NUMBER=$(gh pr view --json number -q '.number' | tr -d '\r')`, `OWNER=$(gh repo view --json owner -q .owner.login)`, `REPO=$(gh repo view --json name -q .name)`
2. Check if a Monitor watch is already running for this PR: `TaskList` and look for a task whose description contains `PR #$PR_NUMBER CI + comments`
3. **If a matching task exists** → skip (watch already active). Proceed to 3.0.5
4. **If no matching task exists** → arm the watch:

   ```text
   Monitor(
     description: "PR #<N> CI + comments",
     persistent: true,
     command: <poll script below>
   )
   ```

   The poll script (inline in the `command` parameter):

   ```bash
   PR_NUMBER=<N>
   OWNER=$(gh repo view --json owner -q .owner.login)
   REPO=$(gh repo view --json name -q .name)
   prev_checks=""
   last_comment_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

   while true; do
     # Terminal state check — exit watch if PR closed/merged
     state=$(gh pr view "$PR_NUMBER" --json state -q '.state' 2>/dev/null | tr -d '\r')
     if [ "$state" = "MERGED" ] || [ "$state" = "CLOSED" ]; then
       echo "PR #$PR_NUMBER $state — watch complete"
       exit 0
     fi

     # CI check-run changes (emit on any new terminal bucket)
     cur_checks=$(gh pr checks "$PR_NUMBER" --json name,bucket \
       --jq '.[] | select(.bucket != "pending") | "\(.name): \(.bucket)"' \
       2>/dev/null | tr -d '\r' | sort || true)
     if [ "$cur_checks" != "$prev_checks" ]; then
       # gh pr checks --json bucket values are: pass|fail|pending|skipping|cancel
       # (per the gh manual) — match those, not check-run conclusion strings.
       comm -13 <(echo "$prev_checks") <(echo "$cur_checks") | \
         grep --line-buffered -E ': (pass|fail|skipping|cancel)$' \
         || true
       prev_checks="$cur_checks"
     fi

     # New comments — ALL THREE review surfaces (issue-level, inline
     # review comments, review bodies). Watching only issues/comments
     # misses inline findings posted with no CI state change.
     # Advance the watermark ONLY when every fetch succeeded — a transient
     # gh failure would otherwise skip past comments that arrived during
     # the failed poll window and never emit them.
     now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
     fetch_ok=1
     if out=$(gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments?since=$last_comment_ts" \
       --jq '.[] | "COMMENT \(.user.login): \(.body[:80])"' 2>/dev/null); then
       printf '%s\n' "$out" | tr -d '\r' | grep --line-buffered . || true
     else fetch_ok=0; fi
     if out=$(gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments?since=$last_comment_ts" \
       --jq '.[] | "INLINE-COMMENT \(.user.login): \(.body[:80])"' 2>/dev/null); then
       printf '%s\n' "$out" | tr -d '\r' | grep --line-buffered . || true
     else fetch_ok=0; fi
     # Reviews API has no `since` param — filter client-side on submitted_at
     if out=$(gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" \
       --jq ".[] | select(.submitted_at > \"$last_comment_ts\") | \"REVIEW \(.user.login) [\(.state)]: \(.body[:80])\"" 2>/dev/null); then
       printf '%s\n' "$out" | tr -d '\r' | grep --line-buffered . || true
     else fetch_ok=0; fi
     [ "$fetch_ok" -eq 1 ] && last_comment_ts="$now"

     sleep 30
   done
   ```

   Capture the returned task id. Report: `Monitor watch armed (task <id>, PR #<N>). Fires on CI check completion and new comments. Stop with TaskStop <id> or end session.`

5. Proceed with the current monitoring iteration normally

**Why Monitor over fixed-interval cron:** a cron fires every N minutes regardless of PR activity. Monitor fires only when the filter emits — typically 5-15 times per PR lifecycle. Zero request cost during idle periods.

**Re-arm after `--resume`:** Monitor is session-scoped and does NOT restore on `--resume`. On any `/pull-request monitor` invocation in a new or resumed session, the §3.0.1 idempotency check (step 2) detects no watch and re-arms automatically.

## 3.0.5 Loop-aware monitoring (self-termination support)

When `/pull-request monitor` runs in a loop (either auto-created by 3.0.1 or user-created via `/loop`), each iteration should be lightweight and self-terminating. Runs **after** 3.0.1 on every iteration.

**Terminal state pre-check (MANDATORY first action on every iteration):**

```bash
gh pr view <pr_number> --json state -q '.state'
```

| State | Action |
|-------|--------|
| `OPEN` | Proceed to 3.1 monitoring loop as normal |
| `MERGED` | Output final report (see below), self-terminate the loop |
| `CLOSED` | Output final report (see below), self-terminate the loop |

**Readiness-pass check (OPEN PRs only):** if the previous iteration already presented "All readiness gates passed. Recommend merge." and no new activity has occurred since (no new check-run completions, no new comments, no new pushes), self-terminate the loop using the same protocol below. Continued polling after readiness-pass is a no-op — the user has all information needed to merge. If a new push occurs later, the next `/pull-request monitor` invocation re-creates the loop via 3.0.1.

**Self-termination protocol** (when PR is MERGED or CLOSED):

1. Output a brief completion message:

   ```text
   PR #N — MERGED. Monitoring complete. Stopping watch.
   ```

2. Call `TaskList` to find the Monitor watch task for this PR (description contains `PR #<N> CI + comments`)
3. If found, call `TaskStop <task_id>` to kill the background watch process
4. If no matching task found (manual invocation, watch already stopped): skip steps 2-3, just output the completion message

**Minimal output for no-change iterations** — when the Monitor watch emits nothing and there are no new CI state changes or comments since the last check, output a single status line:

```
PR #N monitoring: OPEN | CI: 3/8 complete | Comments: 0 new | Next check in ~2m
```

Keeps context cost low (~50 tokens per iteration) instead of a full monitoring report.

## 3.0.6 Multi-PR scan (after readiness-pass, merge, or close)

When current-PR monitoring ends (readiness gates pass, PR merged, or PR closed), scan for other open PRs needing attention before going idle:

```bash
gh pr list --state open --json number,title,headRefName,statusCheckRollup \
  --jq '.[] | "\(.number) \(.headRefName) \(.title)"'
```

For each open PR found, report a one-line status:

```text
Other open PRs:
  #101 feat/add-auth — 2 failing checks, 1 unresolved comment
  #103 fix/null-check — all checks green, awaiting review
```

**Constraint: Monitor watches are branch-locked.** Monitor MUST run in the session that owns the branch (§3.5). Scanning is READ-ONLY — you cannot arm a Monitor watch for a PR on a different branch from this worktree. Report status and suggest: *"Switch to the worktree for `<branch>` to monitor PR #N."*

**When NO other open PRs found:** report `No other open PRs need attention.` and let the session idle.

**DO NOT just report status and ask.** Monitor's job is to DO the work — evaluate comments (explore → research → classify), react, reply, fix VALID findings, and push. Status reporting without action defeats the entire purpose of autonomous monitoring. The only time to pause for user input is at explicit decision gates (CI fix proposals with multiple viable approaches, merge confirmation). "Want me to start evaluating?" is NEVER a valid question — the answer is always yes. Execute the full 3.1-3.4 workflow on every iteration with state changes.

## 3.1 Monitoring loop (per-push)

**PR number**: resolve once at phase entry via `gh pr view --json number -q '.number'` (or `gh pr view "$(git branch --show-current)" --json number -q '.number'` if multiple PRs are open against this checkout). Capture into a shell var and pass explicitly to every subsequent `gh pr checks` / `gh pr view` call within this phase.

After each push, run this loop until convergence (**every** check in a terminal state + all comments addressed):

1. **Mergeable pre-check (MANDATORY before polling)** — `gh pr view <N> --json mergeable,mergeStateStatus` FIRST. If `mergeable == "CONFLICTING"`, GitHub will NOT trigger workflows — integrate the default branch, resolve conflicts, force-push with lease, and restart the loop. Only proceed to CI polling when `mergeable == "MERGEABLE"`. **Never blame the platform for missing CI runs before checking this.**
2. **Poll CI** — `gh pr checks <N>` every 30s (the standard monitor cadence), max 15 minutes per cycle. **Wait for ALL checks to reach a terminal state** (pass/fail/skipped) before suggesting merge — no exceptions, regardless of PR type. Never merge while any check is still pending or in_progress
3. **Check for new comments** — on each poll, also fetch new review comments (`gh api repos/<owner>/<repo>/pulls/<N>/comments --paginate`)
4. **Process comments immediately** — if a bot comments while CI is still running, start evaluating/researching that comment now. Don't wait for CI
5. **On CI failure** — route to 3.2 (research-driven fix)
6. **On new comment** — route to 3.3 (evaluate + respond)
7. **After any fix push** — restart the loop (new push = new monitoring cycle)

Compare triggered workflows against the expected set from Phase 2.5. Flag mismatches.

**When ANY check shows `fail` — ALWAYS read actual logs before classifying.** Use the prioritized fetch chain — `gh run view --log-failed` is the LAST resort because it truncates at the CLI display layer (~4MB cap, cli/cli #11059, #10551, #7771, #7642). The REST API path returns complete logs every time:

```bash
# Tier 1 — Annotations API (path/line/level/title/message — fix-location data)
# Sometimes alone is enough to classify (lint failures, type errors)
bash "${CLAUDE_PLUGIN_ROOT}/skills/pull-request/scripts/fetch-annotations.sh" <pr-number> --failed

# Tier 2 — Full failure ZIP via direct gh api (complete, untruncated). When the
# ${user_config.fetch_logs_max_bytes} option is a number other than the 52428800
# default (not empty, not a literal unexpanded token), append
# --max-bytes ${user_config.fetch_logs_max_bytes}
bash "${CLAUDE_PLUGIN_ROOT}/skills/pull-request/scripts/fetch-failed-logs.sh" <run-id>

# Tier 3 — LAST RESORT interactive eyeball (TRUNCATES on large logs)
gh run view <run-id> --log-failed 2>&1 | grep '##\[error\]'
```

**CRITICAL: Do NOT use `grep -i "error\|fail\|..."` on CI logs.** It produces false matches from cleanup steps, variable names, and incidental output (e.g., "Bad credentials" from a token cleanup step when the real error is a workflow validation failure). GitHub Actions marks real errors with `##[error]` annotations — grep for those first. Only fall back to broader searches if `##[error]` returns nothing.

**Stop at the first complete picture.** Tier 1 annotations are usually sufficient for "what failed in this job?". Escalate to the Tier 2 full ZIP only when annotations don't pinpoint the cause.

### Inline vs subagent dispatch decision

Monitor uses two execution paths for log work — inline in the main session for fast classification, and a CI-log-audit subagent (when your environment provides one) for verbose audits. Choose based on uncertainty + token budget:

| Situation | Path | Why |
|---|---|---|
| Single failing check with a clear `##[error]` marker | **inline** Tier 1 → Tier 2 | The annotations + full-ZIP path is ~3-5K tokens; the agent needs the result NOW for the next action. Subagent overhead buys nothing |
| Default `fetch-failed-logs.sh <run-id>` (errors+warnings) | **inline** | Same as above |
| `--raw` mode (full ZIP dump) | **subagent** (or read selectively) | 50-500K tokens — pollutes main context with content the agent only needs to grep through |
| `--audit` mode (groups + timing + suspicious patterns) | **subagent** | Verbose multi-section output |
| "Why did this PR pass when something looks off?" | **subagent** | Cross-job mask detection, perf-vs-baseline comparison, annotation-gap analysis |

**Why not a subagent for everything:** spawning a subagent for a single-response classification task is an anti-pattern — the default mode's 3-5K-token output IS the answer the agent needs to act on. A subagent justifies its cost only when (a) verbose output protects main context, (b) persistent memory pays off, or (c) parallel work is happening. No audit subagent available → do the audit inline with the bundled script's `--audit` flags.

**Never guess at failure causes.** Common always-on-review workflow failures and their log signatures:

| Log signature | Meaning | Action |
|--------------|---------|--------|
| `Workflow validation failed` on an OIDC-based review action | PR modifies the workflow file — OIDC requires the file to match the default branch | Informational — expected when the PR touches that workflow |
| Usage/quota exhaustion messages (e.g. `out of extra usage`) | The review bot's subscription limit | Informational — report accurately, wait for reset or merge without the second review |
| `error_max_turns` or similar truncation | Reviewer ran out of turns before completing | Informational — the review may be incomplete; check whether a comment was posted |
| OIDC / authentication errors | Token-exchange failure | Informational — often intermittent; retry or classify |
| Actual code/tool errors | Real failure | Investigate |

Report the **exact error message** from logs — not a classification label.

## 3.1.5 Security scan evaluation (MANDATORY)

**Security scan results are ALWAYS blocking — they must be evaluated before merge, regardless of PR type.** Applies to any actor performing security scanning — identify them by check-run names containing "security", "guardian", "CodeQL", "Snyk", "Dependabot", or similar, and by bot comments about secrets or vulnerabilities.

**Discovery, not hardcoding:** security tools change over time. The principle: any check run or bot comment reporting a security finding triggers mandatory triage. Don't skip a finding because the tool isn't in a hardcoded list.

For each security finding:

1. **Read the full PR comment** — scanners post finding details (secret type, file, commit SHA)
2. **Read the check-run details** — `gh pr checks <pr_number> --json name,state,bucket`
3. **Classify each finding:**
   - **True positive** (actual secret leaked / real vulnerability) → BLOCK merge. Remove the secret, rotate credentials, then push a fix. Route through the 3.2 research-driven fix cycle
   - **False positive** (code examples, test fixtures, documentation) → document the rationale, and note that the repo owner should dismiss it in the scanning tool's UI/dashboard or its ignore config
   - **Not applicable** → document why
4. **Every finding must have an explicit classification** — no unclassified findings before merge

**When a security check run shows `FAILURE`:** that does NOT mean the PR is broken — it means the scanner found something needing evaluation. The failure is the *trigger* for triage, not an automatic merge block. After classification, include the disposition in the readiness verdict (Gate 3 in [readiness.md](readiness.md)).

## 3.2 CI failure resolution (RESEARCH-GATED)

**Rule: no edit without research.** For each failed check:

1. **Read full failure context (MANDATORY)** — the prioritized chain in §3.1 above (annotations → full ZIP → last-resort CLI view). Never broad keyword grep
2. **Explore (MANDATORY)** — read source files, check similar code, review the project's own rules, check `git log`
3. **Research (MANDATORY — HARD GATE)** — research the specific error in the exact framework/version, via your environment's research skill when one exists, otherwise direct doc lookups. Require multi-source consensus (aim for 3 sources). Non-optional
4. **Present the proposed fix with evidence** — error, root cause, proposed fix, sources with URLs, confidence level (HIGH/MEDIUM/LOW). If LOW, escalate. If MEDIUM, present trade-offs
5. **Implement** (only after 1-4) — make the change, re-run the project's build/test/lint gate, commit, push
6. **Loop restarts** — new push triggers 3.1 again. Track iteration count

**Stale branch recovery** — if CI fails because the branch is out of date with the default branch (merge conflicts, "branch is not up to date" errors, or tests failing due to default-branch-only changes): integrate (merge or rebase per the project's convention and the branch's own history), resolve conflicts conservatively, force-push with lease, restart the monitor loop from 3.1. Distinct from code failures — no research gate for the integration itself, only for conflicts requiring intent judgment.

**Escalation guard** — after **3 fix iterations**, STOP. Present a history table. The root cause may be environmental.

## 3.3 PR comment evaluation (WORKFLOW-GATED)

**Fetch all comments deterministically** via the bundled script — never select API surfaces by agent judgment:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/fetch-all-pr-comments.sh" <pr-number>
```

Output: a JSON array sorted by `created_at`. Each object carries `type` (`general` | `review` | `inline`), `author`, `body`, `path`, `line`, `id`. The script hits all 3 GitHub API surfaces (issue-level comments, review-level comments, inline review comments) — no surface can be accidentally skipped.

Every comment from an AI reviewer or human reviewer gets the **full workflow treatment** — not a quick glance and a thumbs-up. Review-bot findings trigger urgency bias ("respond fast") and confidence illusion ("this looks right, skip verification"). Both are traps — bot findings have a demonstrated error rate, and the workflow gate exists precisely because "obvious" fixes can be wrong.

### 3.3.1 Phase A: Evaluate ALL comments (batch)

Process every comment before fixing any. Produces a complete picture of what needs attention.

For **every substantive comment from every participant** (bot accounts with the `[bot]` suffix, human reviewers, AND the PR author's own comments — skip only LGTM/empty/emoji-only):

**Finding extraction for multi-finding comments:** AI review summaries often pack multiple findings into a single comment — markdown tables, numbered severity items, multi-paragraph analyses. Extract each finding as a separate work item. One comment with N findings = N individual evaluate cycles below. Reply with a per-finding classification table, not one blanket reply. See [review-discipline.md](../../../reference/review-discipline.md) §2 for extraction rules (including the mandatory ≥3-finding subagent dispatch).

1. **Explore** — read the referenced file/line, understand the surrounding code, check related files. Don't evaluate a comment about line 42 without understanding lines 1-100
2. **Research** — verify the specific technical claim against official docs (via a research skill when available). No assumptions, no "this looks right." The sequence is: explore → research → classify. Never: read → classify
3. **Classify** with evidence:
   - **VALID (fix now)** — research confirms the finding. Document: what's wrong, why, what the fix is
   - **VALID (defer)** — research confirms but the fix is out of scope for this PR. File it in your work-item tracker with evidence and the PR link
   - **INCORRECT** — research disproves the finding. Document: why the comment is wrong, with sources
   - **UNCERTAIN** — research inconclusive. Escalate to the user

   **"Non-blocking" / "optional" / "nice-to-have" does NOT mean "ignore".** These modifiers describe merge-blocking status — not whether the finding is worth acting on. When research confirms a finding is valid: small + directly related → VALID (fix now), include in this PR; larger or tangential → VALID (defer) + tracked work item. **Never merge past a confirmed-valid finding with neither a fix nor a tracked issue.** The choice is always "fix now or ticket it".
4. **React to the specific comment** via `gh api` reactions (`+1` VALID, `-1` INCORRECT, `eyes` UNCERTAIN). For **bot accounts** (login ends in `[bot]`): react autonomously. Mixed-finding comments: `+1` if ANY VALID. For **human reviewers**: pause for user approval before reacting. **Verify the reaction posted** via a GET on the same endpoint filtered by your login — the POST can silently fail (rate limit, permission)
5. **Reply with evidence** — every comment gets a direct reply with research backing. Use the consuming project's bot-identity wrapper for these writes when it has one; plain `gh` otherwise. **Route by comment source — REQUIRED, not interchangeable:** **inline review comments** (diff-anchored, `pulls/comments`) MUST reply THREADED → `gh api repos/{owner}/{repo}/pulls/<pr_number>/comments/{comment_id}/replies -f body='...'` so the reply lands under the source thread — NEVER a detached issue comment. **General PR comments** (`issues/comments`, no thread) → post a new issue-level comment with thread context in the body. **Review-level comments** (`pulls/reviews`, no thread) → post a new issue-level comment addressing the review. Answering an inline finding with a detached issue comment orphans the reply from the thread the reviewer tracks — a routing error

**After evaluating ALL comments**, present a classification table:

```markdown
| # | Reviewer | Comment | Classification | Evidence |
|---|----------|---------|---------------|----------|
| 1 | claude[bot] | "Missing null check on line 42" | INCORRECT — parameter is non-nullable by type | [sources] |
| 2 | chatgpt-codex-connector[bot] | "Race condition in handler" | VALID (fix now) — confirmed by research | [sources] |
| 3 | human-reviewer | "Consider extracting to helper" | VALID (defer) — refactor, not bug | Tracked work item |
```

### 3.3.2 Phase B: Fix ALL valid findings (batch, then single push)

After all comments are evaluated and responded to, implement all VALID (fix now) fixes in a single batch:

1. **For each VALID (fix now) finding**, follow the full workflow: explore the fix context, verify the *fix* approach (not just the finding), implement, re-run the project's build/test gate after each fix
2. **Stage all fixes together** — `git add <specific-files>` for each changed file
3. **Single commit** — one commit addressing all review comments: `fix: address PR review findings`
4. **Single push** — all fixes go up in one push, triggering one new monitoring cycle

**Why batch?** Each push restarts the monitoring loop (3.1). Fixing comments one-by-one with individual pushes creates N monitoring cycles instead of 1. Batch fixes, push once, then re-monitor.

### 3.3.3 Phase C: Re-monitor (loop restarts)

After the push:

1. The monitoring loop (3.1) restarts automatically — new push = new cycle
2. CI runs against the updated code
3. **Request re-review from comment-only actors** — if a bot posted findings that were fixed, request a fresh review so the bot can validate the fixes:
   - If the bot's trigger is **"on every push"**: it will re-review automatically — just wait
   - If the bot's trigger is **manual/smart**: post a comment with its trigger phrase (e.g. `@codex review`) to request a re-review. Don't assume it will re-fire on its own
4. Security scans re-run
5. **Repeat from 3.3.1** if new substantive comments arrive
6. Continue until no new comments arrive and all readiness gates pass

**This is the convergence loop:** evaluate → respond → fix → push → re-monitor → repeat until clear. The monitoring report (3.4) is only produced when no more comments need attention and the full readiness checklist passes.

### 3.3.4 Comment evaluation gotchas

- **NEVER react or classify before researching.** No thumbs-up, no thumbs-down, no "VALID" or "INCORRECT" label until exploration and research complete. Not even if a prior cycle researched the same pattern — each finding gets its own verification. The sequence is always: explore → research → classify → react → reply
- **Zero false positives in classification.** An INCORRECT classification that's wrong is worse than a VALID classification that's wrong — the first dismisses a real issue, the second just does extra work. When in doubt, classify as UNCERTAIN and escalate
- **Don't trust AI reviewer confidence.** A bot saying "critical bug" with high confidence doesn't make it critical. Research first, classify second
- **Don't fix what research says is wrong.** If research disproves a comment, reply with evidence and react with thumbs-down. Don't implement a "fix" for a non-issue just because a bot said so
- **Verify empirically when possible.** For claims about CLI behavior, API responses, or tool output, run the actual command and check. Empirical evidence > documentation > prior research > intuition
- **Escalation guard** — after **3 evaluate-fix-push cycles** with the same reviewer posting new comments, STOP. The reviewer may be generating noise, or there may be a fundamental disagreement. Escalate to the user
- **Codex signals via emoji reactions, not comments.** `chatgpt-codex-connector[bot]` uses emoji reactions on the PR: 👍 = no findings, approved; 👀 = still reviewing. A thumbs-up reaction with no posted comments means Codex reviewed and found nothing — treat as approval. Don't wait for a comment that won't arrive
- **Codex may not auto-fire on PR creation.** If its commit status stays `PENDING` with no emoji reaction on the PR body after ~3 minutes, it likely didn't trigger. Post a PR comment with `@codex review` to trigger manually; check reactions on that trigger comment specifically
- **NEVER select API surfaces by judgment — use the script.** `gh pr view --json comments,reviews` MISSES inline review comments. Always invoke the bundled `fetch-all-pr-comments.sh`, which deterministically hits all 3 surfaces. Observed failure mode: an agent chose `gh pr view --json comments,reviews`, missed 2 valid inline findings, and declared "no comments to address"
- **Never mark a comment addressed without verifiable evidence on GitHub.** Model memory of "I replied" or "I pushed the fix" is not evidence — compaction can lose that state between iterations. Re-query GitHub to verify: reaction exists, reply exists, commit pushed, follow-up posted, bot-authored thread resolved (inline only; human/own excluded). "Done" = GitHub shows evidence. See [review-discipline.md](../../../reference/review-discipline.md) §3 verification gates
- **Resolve BOT-authored inline threads once dispositioned; never human or own.** Once EVERY finding in an inline review comment opened by a bot reviewer carries an eligible disposition — a D6 fix pushed and cited by the D7 follow-up, a `VALID (defer)` grounded per D4.6 with the item id cited, or `INCORRECT` with counter-evidence posted — resolve that thread (D7.5, author- and classification-conditional). One dispositioned finding never makes a multi-finding thread eligible: resolving drops its remaining comments from the readiness count, so an unaddressed finding inside it would vanish. A single `UNCERTAIN` escalates and holds the whole thread open. **A `VALID (defer)` never clears the gate for a merge this same session performs:** route it to an independent adjudicating context, or leave the thread unresolved and do not merge (`review-discipline.md`, "Who authorizes a resolution that ships no fix"). Leave HUMAN-authored threads for the human to close; never resolve your own. Detect bot at resolution time via GraphQL `author.__typename == "Bot"` (GraphQL login omits the `[bot]` suffix REST shows). Open bot-thread count is a visible signal to reviewers — leaving bot threads unresolved after fixing undermines the audit trail
- **Filter your own prior replies during rescan.** Comments from your own posting identity matching the classification-table pattern (`| # | Finding | Classification |`) are NOT findings — they are prior replies. Skip them during finding extraction. See [review-discipline.md](../../../reference/review-discipline.md) §1 step 1

## 3.4 Final monitoring report (readiness-gated)

**Do NOT declare convergence until the full [readiness checklist](readiness.md) passes.** Run all 6 gates from that file before presenting the monitoring report. Hard requirement — no "close enough" for merge readiness.

**The readiness checklist includes a 2-minute cooldown** after the last check-run completion or comment arrival. If a new comment or check result arrives during cooldown, restart the cooldown.

When all readiness gates pass:

```markdown
## PR Monitoring Complete — All Readiness Gates Passed

**PR:** #N — title
**Check runs:** X passed, Y skipped, Z failed-informational
**Security:** [scanner] evaluated — N findings classified
**Comments:** X from N reviewers — Y fixed, Z deferred, W incorrect
**Cooldown:** 2+ min since last activity
**Fix iterations:** N
**Failures classified:**
- `<check>`: FAILURE — [exact reason from logs]
**All readiness gates passed. Recommend merge.**
```

**After presenting the readiness report, self-terminate the Monitor watch** (same protocol as 3.0.5). Continued watching after readiness-pass adds no value. If a new push occurs after readiness-pass, the next `/pull-request monitor` invocation re-arms via 3.0.1.

**If any gate fails**, present which gates failed and what action is needed. Never suggest merge with open gates — even in `full` mode.

## 3.5 Monitor integration

The monitor phase automatically arms a session-persistent background watch via §3.0.1. The user does NOT need to invoke `/loop` manually — the watch is self-configuring and event-driven.

**Where to run it — the same session that owns the branch.**

Monitor MUST run in the session that created the PR. Not a preference — a constraint:

1. Monitor writes to the PR branch (pushes CI fixes, rebases, posts comments)
2. Writing requires being checked out on that branch
3. Git enforces one-branch-per-worktree — no second session can check out the same branch
4. Therefore: monitor runs in the session that owns the branch

```text
Session A: feat/feature-x → create PR → /pull-request monitor (arms watch) → keep working or idle
Session B: feat/feature-y → different branch, different worktree → code the next thing
```

Watch notifications arrive between turns. If you're mid-response on a complex task, the notification queues until your turn completes.

**For read-only status checks from any session:** use `/pull-request status` — a read-only action that only calls `gh` commands. Safe from any terminal, any time, no branch checkout required.

**Key behaviors:**

- **Self-termination on merge/close/readiness-pass** — the poll script exits on MERGED/CLOSED; `TaskStop` also fires from monitoring logic
- **Zero cost during idle periods** — Monitor fires only when the filter emits
- **Full monitoring on state changes** — when a check run completes or a new comment lands, the emitted line wakes the model and the full 3.1-3.4 logic runs
- **Session-scoped** — the watch terminates when the session exits; no orphaned background processes. It does not restore on `--resume` — §3.0.1's idempotency check re-arms it
- **Manual cancel** — "stop the PR monitor" or `TaskStop <id>`

**Cloud sessions (`CLAUDE_CODE_REMOTE=true`):** §3.0.0's baseline poll handles event delivery via `gh`; the Monitor tool is not needed — check `CLAUDE_CODE_REMOTE` before arming.

**Legacy `/loop` pattern:** `/loop 2m /pull-request monitor` still works but costs a full model turn per interval. Monitor is preferred for active CLI sessions; `/loop` remains a manual override if Monitor is unavailable.
