# Action: `start`

Claim an issue by assigning yourself and adding the `status:claimed` label.

## Usage

```
start <number or text match>
```

## Workflow

1. **Resolve the issue.** If a number is given, use it directly. If text is given, search (read — bare `gh`):

```bash
gh issue list --search "<text>" --state open --json number,title,assignees,labels --limit 10 | tr -d '\r'
```

If multiple matches, present them and ask the user to clarify. If exactly one match, proceed.

1. **Pre-check.** Verify the issue isn't already claimed or held (read — bare `gh`):

```bash
gh issue view <N> --json assignees,labels --jq '{assignees: [.assignees[].login], claimed: [.labels[].name] | any(. == "status:claimed"), considering: [.labels[].name] | any(. == "status:considering")}' | tr -d '\r'
```

If assignees are non-empty OR has `status:claimed`/`status:considering` label, warn: "Issue #N is already claimed/held by {assignee}. Proceed anyway? (yes / pick different)"

1. **Hold.** Place a temporary hold before claiming (writes):

```bash
gh issue edit <N> --add-label "status:considering"
gh issue comment <N> --body "<!-- hold:$(hostname):$(date +%s) -->
⏳ **Considering** — held by agent session
- **Host:** $(hostname)
- **Worktree:** $(git rev-parse --show-toplevel 2>/dev/null | xargs basename)
- **Branch:** $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')
- **Time:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

1. **Verify hold.** Check for concurrent holds (see `work.md` step 4 for the full conflict resolution protocol using comment ID ordering). If another agent holds with a lower comment ID, release your hold and warn the user.

1. **Promote to claim.** The `--add-assignee "@me"` edit MUST run on the session identity (never a shared bot identity) so the post-claim collision check keeps working:

```bash
# Replace considering with claimed, add assignee, release hold comment via PATCH (preserves audit trail)
gh issue edit <N> --remove-label "status:considering" --add-label "status:claimed" --add-assignee "@me"
gh api --method PATCH "repos/{owner}/{repo}/issues/comments/<HOLD_COMMENT_ID>" -f body="⏸ **Released** — hold lifted (reason: claim-promotion)"
gh issue comment <N> --body "🔒 **Claimed** by agent session
- **Host:** $(hostname)
- **Worktree:** $(git rev-parse --show-toplevel 2>/dev/null | xargs basename)
- **Branch:** $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')
- **User:** $(gh api user --jq .login 2>/dev/null || echo 'unknown')
- **Time:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

1. **Post-claim verification** — relies on distinct claimant identities, hence the session-identity `--add-assignee "@me"` above:

```bash
gh issue view <N> --json assignees --jq '[.assignees[].login]' | tr -d '\r'
```

If multiple assignees detected, the later claimant releases — remove ONLY your own assignee, never the issue-wide `status:claimed` label the winner still holds — and picks next.

1. **Confirm:** "Claimed **#N**: {title}. Ready to work — follow the project's development workflow."

1. **Suggest branch name.** Propose a branch that carries the issue number so PR tooling can auto-inject `Closes #N` from the branch parse. Emit the command for the user; never switch branches without explicit authorization.

   **Derive `<type>`** from issue labels by Conventional Commits priority — `feat > fix > refactor > docs > chore > test > build > perf`. First match wins; strip `type:` prefix. Default to `chore` if no `type:*` label present.

   **Derive `<slug>`** from issue title: lowercase, replace non-alphanumeric runs with `-`, trim leading/trailing `-`, cap 40 chars.

   **Existing-branch check first** (skip prompt if branch already correct):

   ```bash
   BRANCH="$(git branch --show-current 2>/dev/null || true)"
   CURRENT_N=""
   if [[ "$BRANCH" =~ ^[a-z]+/(routine-issue-)?([0-9]+)- ]]; then
     CURRENT_N="${BASH_REMATCH[2]}"
   fi
   ```

   - **`CURRENT_N` == claimed `<N>`** → acknowledge: "Already on `<current-branch>` — branch matches claimed #N. No rename needed." Skip prompt. Done.
   - **`CURRENT_N` is a different number** → multi-claim 3-option (below).
   - **`CURRENT_N` empty** (no number on current branch) → present bare suggestion: "Suggest branch `<type>/<N>-<slug>`. Switch? (yes / no)". On `yes`, emit `git checkout -b <type>/<N>-<slug> origin/<default-branch>` for the user. On `no`, continue on the current branch — PR tooling can prompt for the closing keyword at PR time instead.

   **Multi-claim 3-option** — when on `<other-type>/<OTHER>-<other-slug>` and just claimed #N (different issue):

   1. **Switch to `<type>/<N>-<slug>`** — WARN: uncommitted work on the current branch must be committed or stashed first (never stash a shared branch's work without confirming). Emit `git checkout -b <type>/<N>-<slug> origin/<default-branch>` for the user.
   2. **Stay on current branch and cover both in one PR** — inject `Closes #<OTHER>` + `Closes #<N>` into the PR body at PR time.
   3. **Skip** — decide later; continue on the current branch without rename.

## Notes

- In GitHub Actions context, replace `@me` with `$GITHUB_ACTOR`
- The hold→verify→claim protocol uses optimistic locking via GitHub comment IDs (monotonically increasing, server-assigned). Lowest comment ID wins ties
- If collision detected post-claim (two assignees), the second agent releases and picks next
- Stale holds (`status:considering` >15min) are detected by the `audit` action
