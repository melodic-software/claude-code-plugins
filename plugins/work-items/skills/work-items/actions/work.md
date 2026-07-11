# Action: `work`

Auto-select one issue and execute it, following the consuming project's development workflow.

## Usage

```
work
```

## Selection Priority

`work` evaluates these tiers top-down, only falling through to the next tier when the current one yields no candidates. Tiers flagged last-resort are skipped if any prior tier already yielded a candidate. Recurring tiers (1 and 4) apply only when the consuming repo has a `.github/recurring-schedule.json`.

1. **Due recurring items** — schedule items where `next_due <= today`, sorted by `next_due`. Schedule commitments take precedence over category flags; picking a recurring item early shifts its subsequent cadence and undermines the recurrence guarantee.

2. **Non-recurring guardrails items** — issues labeled `category:guardrails` (when the repo uses that category), search `no:assignee -label:status:claimed -label:status:considering -label:recurring`. Force multipliers — each one completed makes ALL future autonomous work more reliable. Within this tier, prefer: enforcement mechanisms (CI/CD gates, architecture tests, hooks) > tool validation > research/planning.

3. **Highest-impact non-recurring unassigned items** — search `no:assignee -label:status:claimed -label:status:considering -label:recurring sort:created-asc`. Scan remaining open issues WITHOUT the recurring label. Select based on: items that unblock others, items in smaller categories, shorter well-scoped items over sprawling research epics.

4. **Recurring items not yet due** (last-resort) — schedule items where `next_due > today`, sorted by `next_due`. LAST RESORT only, when tiers 1–3 are empty. Picking a recurring item before its `next_due` shifts the cadence forward — avoid unless nothing else is available. Prefer items closest to `next_due` (least cadence disruption).

## Workflow

### Step 1: Find candidates

For each tier in the Selection Priority list above, emit the corresponding query. Translation:

- Recurring-schedule tiers →

  ```bash
  # Root the path at the project root — a relative path breaks when invoked from a subdirectory.
  SCHEDULE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.github/recurring-schedule.json"
  cat "$SCHEDULE" | jq --arg today "$(date +%Y-%m-%d)" \
    '[.items[] | select(.next_due != null and .next_due <where_expr> $today)] | sort_by(.next_due)'
  ```

  where `<where_expr>` is `<=` (current/overdue) or `>` (not-yet-due) per the tier.

- Issue-list tiers (read — bare `gh`):

  ```bash
  gh issue list \
    ${LABEL:+--label "$LABEL"} \
    --search "$SEARCH" \
    --state open \
    --json number,title,labels,assignees \
    --limit 20 \
    | tr -d '\r'
  ```

  where `LABEL` and `SEARCH` come from the tier's label filter and search expression.

Tiers flagged last-resort are skipped if any prior tier yielded a candidate.

### Step 2: Cross-reference with open issues

For tier 1 and tier 4 (recurring candidates), cross-reference against open issues — the consuming repo's recurring-issues automation may have already created an issue (read — bare `gh`):

```bash
gh issue list --label "recurring" --state open --json number,title --limit 100 | tr -d '\r'
```

Match by title prefix `[Maintenance] {schedule item title}`.

**Due-recurring tier (`next_due <= today`):** if no open issue exists, create one before claiming — issue only, using the `[Maintenance] {title}` prefix plus the `recurring` and `cadence:{cadence}` labels. Do NOT route through `add --recurring`: the item already exists in the schedule, and that flow would append a duplicate schedule entry. These items are actionable now — dead-ending without an issue to hold would strand work.

**Last-resort recurring tier (`next_due > today`):** recurring automation typically only creates issues when `next_due <= today`, so there is usually no open issue to hold. Since picking early shifts the cadence and undermines the recurrence guarantee, **skip last-resort candidates that have no open issue and advance to the next candidate**. Only hold/claim a last-resort item when an open issue already exists (e.g., created manually ahead of cadence). If every last-resort candidate is skipped for lack of an issue, report "no actionable work" to the user rather than forcing one into existence.

### Step 3: Hold (immediate — before presenting)

Place a hold on the candidate to prevent concurrent agents from selecting it. This MUST happen before presenting to the user. First run in a repo: ensure the protocol's status labels exist — the hold write fails on an unknown label:

```bash
EXISTING=$(gh label list --limit 200 --json name --jq '.[].name' | tr -d '\r')
grep -qxF "status:considering" <<<"$EXISTING" || gh label create "status:considering" --description "Held by an agent evaluating the item"
grep -qxF "status:claimed" <<<"$EXISTING" || gh label create "status:claimed" --description "Claimed by a work session"
```

Then hold (writes):

```bash
# Add considering label
gh issue edit <N> --add-label "status:considering"

# Add hold comment with session metadata for identification and ordering
gh issue comment <N> --body "<!-- hold:$(hostname):$(date +%s) -->
⏳ **Considering** — held by agent session
- **Host:** $(hostname)
- **Worktree:** $(git rev-parse --show-toplevel 2>/dev/null | xargs basename)
- **Branch:** $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')
- **Time:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

### Step 4: Verify hold (conflict detection)

Check whether another agent also placed a hold concurrently. GitHub comment IDs are monotonically increasing — lowest ID wins ties (read — bare `gh`):

```bash
# List all hold comments on this issue
gh api "repos/{owner}/{repo}/issues/<N>/comments" --jq '[.[] | select(.body | startswith("<!-- hold:")) | {id, user: .user.login, created_at}] | sort_by(.id)' | tr -d '\r'
```

**Conflict resolution:**

- **One hold comment (yours):** proceed to step 5
- **Multiple hold comments:** compare comment IDs. If yours is the **lowest ID**, you win — proceed. If not:
  1. Release your hold comment via PATCH (preserves audit trail): `gh api --method PATCH "repos/{owner}/{repo}/issues/comments/<YOUR_COMMENT_ID>" -f body="⏸ **Released** — hold lifted (reason: conflict)"`
  2. Remove the label (only if no other holds remain): `gh issue edit <N> --remove-label "status:considering"`
  3. Pick the next candidate from step 1 (skip this issue)

Also verify no concurrent claim happened during your hold (read — bare `gh`):

```bash
gh issue view <N> --json assignees,labels --jq '{assignees: [.assignees[].login], claimed: [.labels[].name] | any(. == "status:claimed")}' | tr -d '\r'
```

If already claimed or assigned, release your hold and pick next.

### Step 5: Staleness pre-check

Before presenting the item, verify it's still actionable:

- If the issue references a file to modify: check if the file exists and the issue is still relevant
- If the issue references a test to add: check if similar tests already exist
- If stale (work already done): release the hold (PATCH the hold comment to released state with reason: `stale`, remove label), close the issue with a comment, and pick the next one

### Step 6: Present and confirm

```
**Auto-selected (<tier name>):** #42 Fix <thing>
Labels: type:fix, category:<name>, area:<name>

Proceed with this item? (yes / pick different / skip)
```

**On "pick different" or "skip":** release the hold before proceeding:

```bash
# Release hold comment via PATCH (preserves audit trail)
gh api --method PATCH "repos/{owner}/{repo}/issues/comments/<HOLD_COMMENT_ID>" -f body="⏸ **Released** — hold lifted (reason: user-skip)"
# Remove considering label
gh issue edit <N> --remove-label "status:considering"
```

### Step 7: Claim and execute

On user confirmation ("yes"):

1. **Promote hold to claim.** The `--add-assignee "@me"` edit MUST run on the session identity (never a shared bot identity) — the post-claim collision check below needs distinct claimant identities; routing every claim through one bot account would silently defeat it:

```bash
# Replace considering with claimed, add assignee
gh issue edit <N> --remove-label "status:considering" --add-label "status:claimed" --add-assignee "@me"

# Release the hold comment via PATCH (preserves audit trail) and add a claim comment with full session metadata
gh api --method PATCH "repos/{owner}/{repo}/issues/comments/<HOLD_COMMENT_ID>" -f body="⏸ **Released** — hold lifted (reason: claim-promotion)"
gh issue comment <N> --body "🔒 **Claimed** by agent session
- **Host:** $(hostname)
- **Worktree:** $(git rev-parse --show-toplevel 2>/dev/null | xargs basename)
- **Branch:** $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')
- **User:** $(gh api user --jq .login 2>/dev/null || echo 'unknown')
- **Time:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

1. **Post-claim verification** (defense in depth) — relies on distinct claimant identities in the assignee set:

```bash
# Verify you're the sole assignee
gh issue view <N> --json assignees --jq '[.assignees[].login]' | tr -d '\r'
```

If multiple assignees detected, the later claimant releases — remove ONLY your own assignee (`--remove-assignee`), never the issue-wide `status:claimed` label, which the winning claimant still holds — then pick next.

1. **Suggest branch name.** Propose `<type>/<N>-<slug>` so PR tooling can auto-inject `Closes #N` from the branch parse. Same protocol as `start.md` "Workflow" final step (Suggest branch name) — type derivation by Conventional Commits priority, slug from title (kebab-case, 40-char cap), existing-branch detection, multi-claim 3-option (switch / stay+cover-both / skip). See `start.md` for the full logic. Emit `git checkout -b ...` for the user unless the session has explicit branching authorization.

1. **Execute the project's development workflow.** When the consuming project defines a workflow (a workflow skill, a CLAUDE.md workflow section, or team convention), follow every step of it — no shortcuts, no skipping research, no surface-level execution; read the project's rules for the item's domain first. When no workflow is defined, follow the generic sequence: explore → plan → implement → test → review → PR.

1. **On completion:** run the `done` action (one-off items) or `recheck` action (recurring items).

## Bug Investigation Rule

Reproduce the reported failure FIRST. Never close a bug issue without either reproducing and fixing it, or proving via git history why the reporter saw the failure and why it no longer applies.
