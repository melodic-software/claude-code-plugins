# Phase 2: Create (commit + push + PR)

## 2.1 Pre-flight

1. **Prep completed?** Prep produces no state file — its outputs (verified findings + clean verify-gate results) live in conversation context. If neither has been run this session, suggest `/pull-request prep` first; in `full` mode this phase is preceded by prep automatically. Skip the review prompt for docs-only PRs (Phase 1.1 skips review/simplify).
2. **Changes exist?** `git status --porcelain` must show changes or commits ahead of remote.
3. **Not on the default branch?** If on it, suggest a branch/worktree.
4. **Branch naming?** If the branch name doesn't fit the project's convention (common default: `<type>/<kebab-description>`; Claude Code's auto-created worktree branches may be named `worktree-*`), rename before push: `git branch -m <old> <type>/<description>`. Derive `<type>` from commit content (feat/fix/chore/etc.) and `<description>` from the commit subject. If no commits exist yet (empty branch), prompt the user for a branch name — auto-derivation has no input without commits. Present the rename for awareness, not approval.
5. **Worktreeinclude file sync?** If in a worktree, check for modified gitignored files that won't survive worktree removal. These files were copied at worktree creation via `.worktreeinclude` — changes made during the session exist only in the worktree and will be lost on cleanup.

   **Detection:**

   ```bash
   # Am I in a worktree?
   GIT_COMMON=$(git rev-parse --git-common-dir 2>/dev/null)
   GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
   if [[ "$GIT_COMMON" != "$GIT_DIR" ]]; then
     MAIN_ROOT=$(git worktree list | head -1 | awk '{print $1}')
     # Read .worktreeinclude patterns (one per line, .gitignore syntax)
     while IFS= read -r pattern; do
       [[ -z "$pattern" || "$pattern" == \#* ]] && continue
       # For each matching file, diff worktree vs main. An unmatched glob
       # stays literal — skip it (no phantom CHANGED for absent files).
       for f in $pattern; do
         [[ -f "$f" ]] || continue
         if [[ -f "$MAIN_ROOT/$f" ]]; then
           diff -q "$f" "$MAIN_ROOT/$f" >/dev/null 2>&1 || echo "CHANGED: $f"
         else
           echo "CHANGED: $f"
         fi
       done
     done < .worktreeinclude
   fi
   ```

   **If differences found:**

   1. Show diff for each changed file (`diff --unified "$MAIN_ROOT/$f" "$f"`)
   2. Show active worktrees (`git worktree list`) — if >1 worktree exists beyond main, warn: *"Other active worktrees have their own copies of this file. Overwriting main's copy won't affect existing worktrees but will affect future ones."*
   3. Present options per file:
      - **Copy to main** — overwrite main's copy with worktree's version. Safe for cosmetic changes (reordering), new additions, or when this is the only active session
      - **Skip** — proceed without syncing. User accepts that worktree changes will be lost on cleanup
   4. If user chooses "copy to main": `cp "$f" "$MAIN_ROOT/$f"`

   **Why here (not WorktreeRemove hook):** this is the last intentional checkpoint where user is engaged and can inspect a diff. WorktreeRemove hooks cannot block removal or prompt — a silent copy could overwrite concurrent session changes. One mechanism per concern.

   **Skip conditions:** not in a worktree, no `.worktreeinclude` file exists, no differences found.

## 2.2 Rebase onto the latest default branch

Ensure the branch is current with the default branch before pushing. Prevents merge conflicts and stale-branch CI failures.

**Ordering — rebase needs a clean tree.** `git rebase` refuses to run with unstaged changes (`error: cannot rebase: You have unstaged changes.`). On the normal `create` path the PR changes are still uncommitted when this phase starts — in that case run 2.3 (classify unrelated changes + stage + commit) FIRST, then return here and integrate before the 2.4 push. Run 2.2 in the listed order only when the tree is already clean (all work committed).

```bash
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
git fetch origin "$DEFAULT_BRANCH"
MERGE_BASE=$(git merge-base HEAD "origin/$DEFAULT_BRANCH")
ORIGIN_DEFAULT=$(git rev-parse "origin/$DEFAULT_BRANCH")

if [ "$MERGE_BASE" != "$ORIGIN_DEFAULT" ]; then
  BEHIND=$(git rev-list --count HEAD.."origin/$DEFAULT_BRANCH")
  echo "Branch is $BEHIND commit(s) behind origin/$DEFAULT_BRANCH. Rebasing..."
  git rebase "origin/$DEFAULT_BRANCH"
fi
```

**Prefer `git merge origin/$DEFAULT_BRANCH` over rebase when the branch already contains a merge commit** (`git log --merges origin/$DEFAULT_BRANCH..HEAD` non-empty) — replaying pre-merge commits produces avoidable conflict slogs, and under squash-merge linear branch history buys nothing.

**If conflicts occur:** resolve conservatively — take both sides where independent, pause and present to the user whenever intent is unclear. `git rebase --abort` / `git merge --abort` when resolution needs judgment you don't have.

**Skip conditions:** branch has zero commits ahead (nothing to rebase), or merge-base already equals `origin/$DEFAULT_BRANCH` (branch is current).

## 2.3 Stage and commit

### 2.3.1 Unrelated uncommitted changes check (MANDATORY)

Before staging, run `git status --porcelain` and classify every modified/untracked file as either **PR-related** or **unrelated**. Unrelated changes are files modified during the session that don't belong in this PR — pre-existing edits from other sessions, hook auto-fixes, exploratory changes, or work from a different task.

**Why this matters:** After merge, branch gets deleted. Uncommitted changes on that branch are lost forever — `git reflog` cannot recover uncommitted edits, only commits. `git stash` survives branch deletion (stashes stored in `.git/refs/stash`, not tied to branches), but only if stash is created before checkout/deletion.

**If unrelated uncommitted changes exist**, present them and offer options:

| Option | When to use | Command |
|--------|-------------|---------|
| **Include in PR** | Changes are small, related enough, and won't pollute the PR | Stage them with the PR files |
| **Stash** | Changes should be preserved but don't belong in this PR | `git stash push -u -m "unrelated: <description>" -- <files>` |
| **Separate commit** | Changes are valuable and self-contained — commit on this branch as a separate commit (squash merge collapses anyway) | `git add <files> && git commit -m "chore: <description>"` |
| **Discard** | Changes are throwaway (build artifacts, experimental edits) | `git checkout -- <files>` |

**Default recommendation:** stash with a descriptive message. Use `-u` to include untracked files — without it, `git stash push -- <files>` silently skips untracked files (`pathspec did not match`). Stashes persist across branch switches and deletion, and `git stash list` shows them from any branch. User can `git stash pop` after switching to a new branch.

**Never silently ignore uncommitted changes.** Agent must either include them, stash them, or get explicit user confirmation to discard. Silent data loss is the worst outcome.

### 2.3.2 Stage and commit PR changes

Stage specific files (never `git add -A`). Then invoke `/commit` (this plugin's sibling skill) for the commit step — it handles message drafting, the Conventional Commits regex pre-check, the `Co-Authored-By` trailer, and the canonical bash heredoc form. **Wait for user approval on the proposed commit message inside `/commit`.** Do NOT bypass `/commit` by invoking `git commit` directly from this phase — the canonical bash mechanic + trailer + sanity-check are encapsulated there.

**When NOT to delegate:** if `/commit` is unavailable (e.g. skill discovery broken), inline the same heredoc form (`git commit -F - --cleanup=verbatim <<'EOF' ... EOF`) and proceed — but note the fallback to the user.

## 2.4 Push, create PR, and persist PR number

### 2.4.0 Resolve linked issue(s)

Before building PR body, parse branch for primary issue number and prompt for any additional closures. Keyword line is injected at top of body in §2.4.1.

```bash
ISSUE_NUM=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/pull-request/scripts/parse-branch-issue.sh" 2>/dev/null || true)
CLOSES_LINE=""
if [[ -n "$ISSUE_NUM" ]]; then
  # Validate issue exists in current repo BEFORE shipping `Closes #N`.
  # GitHub auto-close only fires when the issue exists, lives in this repo,
  # and is open at merge time. A typo'd branch like
  # `feat/99999-foo` would otherwise ship a misleading `Closes #99999` line.
  ISSUE_STATE=$(gh issue view "$ISSUE_NUM" --json state --jq '.state' 2>/dev/null || true)
  if [[ "$ISSUE_STATE" == "OPEN" ]]; then
    CLOSES_LINE="Closes #${ISSUE_NUM}"
  else
    echo "⚠ Branch suggests Closes #${ISSUE_NUM}, but that issue is missing or not open in this repo. Falling back to interactive prompt." >&2
    ISSUE_NUM=""   # fall through to orphan-PR 3-option prompt below
  fi
fi
# If still empty, the orphan-PR prompt populates CLOSES_LINE below.
```

**Single-issue branch:** parser returns `N` from `<type>/<N>-<slug>` (and `chore/routine-issue-<N>-<slug>` for cloud routines). When `gh issue view` confirms the issue exists and its state is `OPEN`, `${CLOSES_LINE}` becomes `Closes #N`. If the issue is missing, closed, or otherwise not open, the flow falls through to the orphan-PR prompt — never ship a stale or unverified keyword.

**Multi-issue PR (same branch closes 2+ issues):** after primary line is set, ask user inline:

> *"This PR closes #N. Any other issues to close on merge? List them one per line (`Closes #X`), use `Refs #Y` to link without closing, or `no` to skip."*

Append each accepted line to `${CLOSES_LINE}` (newline-separated). GitHub accepts one keyword per issue, comma- or newline-separated.

**Branch lacks issue number (orphan PR — drift sweep, hotfix, refactor):** prompt with three options:

1. `Closes #<N>` — provide a number to auto-close on merge
2. `Refs #<N>` — link without closing
3. `No related issue: <reason>` — orphan PR, no linkage

Persist chosen line(s) into `${CLOSES_LINE}`. NEVER wrap a closing keyword in an HTML comment — `<!-- Closes #N -->` is parsed as a valid keyword and will auto-close the issue on merge. Fenced code blocks ARE inert, so example snippets are safe.

### 2.4.1 Push and assemble PR body

```bash
git push -u origin <branch-name>
```

Derive PR title from the commit subject, shaped to satisfy the resolved subject/title convention (SKILL.md §"PR title format" ladder: `.claude/source-control.md` → project convention → Conventional Commits default). Build body with `${CLOSES_LINE}` at top, followed by Summary + Test plan + Claude Code attribution:

```bash
# Quoted heredoc — body template is inert; nothing inside expands.
# Safe even if surrounding template prose contains $vars or $(cmds).
TEMPLATE=$(cat <<'EOF'
## Summary
...

## Test plan
- ...

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)

# Concat CLOSES_LINE in front of TEMPLATE via bash parameter expansion.
# Parameter expansion of "${VAR}" does NOT re-evaluate the expanded value
# — if CLOSES_LINE contains literal "$(rm -rf ~)" (e.g. user typed it into
# the orphan-PR or multi-issue prompt), it stays a literal string and is
# never executed. This is the defense against shell injection through
# user-supplied prompt input.
BODY=""
[[ -n "$CLOSES_LINE" ]] && BODY="${CLOSES_LINE}"$'\n\n'
BODY+="$TEMPLATE"
```

**Why quoted heredoc + concat (not `<<EOF`):** unquoted heredoc `<<EOF` evaluates `$(...)`, `${...}`, and `` `...` `` *inside the body content itself* (POSIX heredoc semantics — `<<EOF` is treated as if double-quoted). If `${CLOSES_LINE}` ever contains shell-meta from interactive prompt input, an unquoted heredoc would execute it. Quoted `<<'EOF'` is inert; splicing `${CLOSES_LINE}` via parameter expansion + concat keeps user input as literal text.

`gh pr create --body` fully overrides `.github/PULL_REQUEST_TEMPLATE.md` (cli/cli #10751) — body assembly above is the canonical path for skill-driven PRs; the template is the web-UI backstop. When the consuming project ships a PR template, mirror its section shape in the assembled body.

### 2.4.2 Verify closing-keyword line (pre-create gate)

Before invoking `gh pr create`, grep assembled `$BODY` for a valid closing keyword OR an opt-out marker. Catches branches where §2.4.0 fell through (issue-existence check failed without orphan-PR prompt running, user dismissed the prompt, `$CLOSES_LINE` is empty) and prevents shipping a PR with no linkage signal.

```bash
# Case-insensitive — covers ALL 9 valid keywords (close/closes/closed/fix/
# fixes/fixed/resolve/resolves/resolved) with optional colon, per GitHub's
# linked-issues docs. The 3-keyword shortcut (Closes|Fixes|Resolves)
# misses 6 valid forms GitHub auto-close honors.
KEYWORD_REGEX='^(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved):? #[0-9]+'
OPTOUT_REGEX='^(Refs #[0-9]+|No related issue:)'

if printf '%s\n' "$BODY" | grep -iE "$KEYWORD_REGEX" >/dev/null; then
  :  # closing keyword present — gate passes
elif printf '%s\n' "$BODY" | grep -E "$OPTOUT_REGEX" >/dev/null; then
  :  # explicit opt-out present — gate passes
else
  # No closing keyword AND no opt-out marker. §2.4.0's orphan-PR prompt
  # should have populated one. If we reach here, either the prompt was
  # skipped or `$CLOSES_LINE` is empty.
  echo "⚠ PR body lacks a closing keyword (Closes/Fixes/Resolves #N, case-insensitive, optional colon) AND no opt-out marker (Refs #N / No related issue:)." >&2
  echo "  Re-run §2.4.0's orphan-PR prompt to choose: Closes #N | Refs #N | No related issue: <reason>" >&2
  echo "  Aborting PR creation. (Silent proceed would orphan the PR from any tracked issue.)" >&2
  exit 1
fi
```

When user explicitly selected `Refs #<N>` or `No related issue: <reason>` in §2.4.0, gate passes silently — opt-out is a legitimate path for refactors, drift sweeps, and hotfixes. Gate exists to catch the case where §2.4.0 fell through without populating `$CLOSES_LINE`.

### 2.4.3 Create PR

```bash
# Identity: plain `gh` (the human PR author) by default. If the consuming
# project's conventions route automation writes through a bot identity
# wrapper, follow those for comments/reactions — PR creation itself is
# normally authored by the human account.
# No reviewers are auto-requested by default — `gh pr create` runs without
# `--reviewer`. Reviews come from whatever AI reviewers the repo wires up
# and any humans who opt in.
# Title shape: whatever the resolved subject/title convention requires
# (Conventional Commits default shown; a custom .claude/source-control.md
# pattern or the project's own convention overrides this).
PR_URL=$(gh pr create --title "<type>: <description>" --body "$BODY")

# Extract PR number from URL (gh pr create outputs the URL on success).
# This number is the source of truth for the rest of this phase — pass it
# explicitly to every subsequent gh call.
PR_NUMBER=$(basename "$PR_URL")
```

PR identity (number + URL) is queried live from `gh pr view --json number,url` whenever a later phase needs it. We do not persist it to a state file — `gh` is authoritative source.

**All subsequent phases MUST use `<pr_number>` explicitly** — never bare `gh pr view` / `gh pr checks` / `gh pr merge` without PR number argument.

## 2.5 Record expected CI workflows

Classify changed files → predict expected workflows by reading the repo's own `.github/workflows/` triggers (path filters, `on:` events). Typical shape:

| File patterns | Expected workflow (example) |
|---------------|-------------------|
| Language sources (`*.cs`, `*.py`, `*.ts`, …) | that ecosystem's CI workflow |
| Shell scripts | shell lint workflow |
| Any PR | always-on workflows (AI review, CI gateway) |

Record the expected set for comparison in Phase 3.

## 2.6 Report and stop

Report the PR URL, captured `<pr_number>`, and recorded list of expected CI workflows. End Phase 2 there. Monitor (Phase 3), if needed, is invoked explicitly via `/pull-request monitor` or `/pull-request full`.
