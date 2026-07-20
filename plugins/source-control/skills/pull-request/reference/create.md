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
     # .worktreeinclude lives at the repo root and its globs are root-relative —
     # run from the worktree toplevel, not wherever the session happens to be.
     cd "$(git rev-parse --show-toplevel)" || return
     MAIN_ROOT=$(git worktree list | head -1 | awk '{print $1}')
     # Read .worktreeinclude patterns (one per line, .gitignore syntax)
     while IFS= read -r pattern; do
       [[ -z "$pattern" || "$pattern" == \#* ]] && continue
       # Worktree side: modified or new files. An unmatched glob stays
       # literal — skip it (no phantom CHANGED for absent files).
       for f in $pattern; do
         [[ -f "$f" ]] || continue
         if [[ -f "$MAIN_ROOT/$f" ]]; then
           diff -q "$f" "$MAIN_ROOT/$f" >/dev/null 2>&1 || echo "CHANGED: $f"
         else
           echo "CHANGED (new): $f"
         fi
       done
       # Main side: a carried file deleted in the worktree no longer expands
       # locally — expand from MAIN_ROOT too. ABSENT is ambiguous: the file may
       # have been deleted here, or never copied at all (manual `git worktree
       # add`, or a worktree created before .worktreeinclude existed).
       for m in "$MAIN_ROOT"/$pattern; do
         [[ -f "$m" ]] || continue
         f="${m#"$MAIN_ROOT"/}"
         [[ -f "$f" ]] || echo "ABSENT here (deleted, or never carried): $f"
       done
     done < .worktreeinclude
   fi
   ```

   **If differences found:**

   1. Show diff for each changed file (`diff --unified "$MAIN_ROOT/$f" "$f"`; for a `(new)` file
      diff against `/dev/null` — main has no copy yet; for an `ABSENT` file show main's copy)
   2. Show active worktrees (`git worktree list`) — if >1 worktree exists beyond main, warn: *"Other active worktrees have their own copies of this file. Overwriting main's copy won't affect existing worktrees but will affect future ones."*
   3. Present options per file:
      - **Copy to main** — overwrite main's copy with worktree's version. Safe for cosmetic changes (reordering), new additions, or when this is the only active session
      - **Skip** — proceed without syncing. User accepts that worktree changes will be lost on cleanup
      - For an `ABSENT` file only: **Remove from main** — offered only if the user confirms the file was deliberately deleted in this worktree this session. ABSENT is ambiguous (a manual or pre-`.worktreeinclude` worktree never received the copy), so default to **Skip**; never remove main's copy without that explicit confirmation
   4. If user chooses "copy to main": `mkdir -p "$(dirname "$MAIN_ROOT/$f")" && cp "$f" "$MAIN_ROOT/$f"` (a new topic slug has no parent directory in main yet); confirmed deliberate deletion: `rm "$MAIN_ROOT/$f"`

   **Why here (not WorktreeRemove hook):** this is the last intentional checkpoint where user is engaged and can inspect a diff. WorktreeRemove hooks cannot block removal or prompt — a silent copy could overwrite concurrent session changes. One mechanism per concern.

   **Skip conditions:** not in a worktree, no `.worktreeinclude` file exists, no differences found.

## 2.2 Rebase onto the latest default branch

Ensure the branch is current with the default branch before pushing. Prevents merge conflicts and stale-branch CI failures.

**Ordering — rebase needs a clean tree.** `git rebase` refuses to run with unstaged changes (`error: cannot rebase: You have unstaged changes.`). On the normal `create` path the PR changes are still uncommitted when this phase starts — in that case run 2.3 (classify unrelated changes + stage + commit) FIRST, then return here and integrate before the 2.4 push. Run 2.2 in the listed order only when the tree is already clean (all work committed).

```bash
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)

# Resolve the remote that hosts the default branch via the shared resolver
# (scripts/resolve-remote.sh, also used by the §2.4.1 push step): the current
# branch's configured remote (branch.<name>.remote), else `origin`, else the
# sole OTHER configured remote when exactly one exists — never a hardcoded
# `origin`, so a repo cloned with a different remote name (`git clone -o vendor`)
# still resolves. A local-only upstream (`.`) is treated as unset. Two or more
# non-origin candidates with neither branch.<name>.remote nor `origin` set is
# ambiguous and the resolver fails loudly rather than silently picking one.
# (Out of scope: a triangular fork flow that fetches a separate `upstream`
# while pushing to a fork — branch.<name>.remote tracks the push remote, not
# upstream; see §2.4.1 and the return-payload note.)
REMOTE=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/pull-request/scripts/resolve-remote.sh") || exit 1

git fetch "$REMOTE" "$DEFAULT_BRANCH"
MERGE_BASE=$(git merge-base HEAD "$REMOTE/$DEFAULT_BRANCH")
REMOTE_DEFAULT=$(git rev-parse "$REMOTE/$DEFAULT_BRANCH")

if [ "$MERGE_BASE" != "$REMOTE_DEFAULT" ]; then
  BEHIND=$(git rev-list --count HEAD.."$REMOTE/$DEFAULT_BRANCH")
  echo "Branch is $BEHIND commit(s) behind $REMOTE/$DEFAULT_BRANCH. Rebasing..."
  git rebase "$REMOTE/$DEFAULT_BRANCH"
fi
```

**Prefer `git merge $REMOTE/$DEFAULT_BRANCH` over rebase when the branch already contains a merge commit** (`git log --merges $REMOTE/$DEFAULT_BRANCH..HEAD` non-empty) — replaying pre-merge commits produces avoidable conflict slogs, and under squash-merge linear branch history buys nothing.

**If conflicts occur:** resolve conservatively — take both sides where independent, pause and present to the user whenever intent is unclear. `git rebase --abort` / `git merge --abort` when resolution needs judgment you don't have.

**Skip conditions:** branch has zero commits ahead (nothing to rebase), or merge-base already equals `$REMOTE/$DEFAULT_BRANCH` (branch is current).

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
    ISSUE_NUM=""   # fall through to orphan-PR 2-option prompt below
  fi
fi
# If still empty, the orphan-PR prompt populates CLOSES_LINE below.
```

**Single-issue branch:** parser returns `N` from `<type>/<N>-<slug>` (and `chore/routine-issue-<N>-<slug>` for cloud routines). When `gh issue view` confirms the issue exists and its state is `OPEN`, `${CLOSES_LINE}` becomes `Closes #N`. If the issue is missing, closed, or otherwise not open, the flow falls through to the orphan-PR prompt — never ship a stale or unverified keyword.

**Multi-issue PR (same branch closes 2+ issues):** after primary line is set, ask user inline:

> *"This PR closes #N. Any other issues to close on merge? List them one per line (`Closes #X`), use `Refs #Y` to link without closing, or `no` to skip."*

Append each accepted `Closes #X` line to `${CLOSES_LINE}` (newline-separated); route each `Refs #Y` line into the `## Related` section instead (§2.4.1, replacing its `N/A`), never onto the closing-keyword line — the same rule the orphan-PR and `## Related` guidance below apply to every non-closing reference. GitHub accepts one keyword per issue, comma- or newline-separated.

**Branch lacks issue number (orphan PR — drift sweep, hotfix, refactor):** prompt with two options:

1. `Closes #<N>` — provide a number to auto-close on merge
2. `No related issue: <reason>` — orphan PR, no linkage

To reference an issue this PR does **not** close, put a `Refs #N — <why>` line in the `## Related` section (§2.4.1), not on the closing-keyword line: a bare `Refs #N` satisfies neither the §2.4.2 pre-create gate nor the real `pr-issue-linkage` validator's closing-keyword half, so such a PR still picks one of the two options above.

Persist chosen line(s) into `${CLOSES_LINE}`. NEVER wrap a closing keyword in an HTML comment — `<!-- Closes #N -->` is parsed as a valid keyword and will auto-close the issue on merge. Fenced code blocks ARE inert, so example snippets are safe.

### 2.4.1 Push and assemble PR body

```bash
# Push to the same remote §2.2 resolved (branch.<name>.remote, else `origin`,
# else the sole other configured remote), via the shared resolver — a fork
# may be named `origin`, `fork`, or anything else, and a repo cloned with a
# non-origin sole remote (`git clone -o vendor`) must push there too, not
# `origin`. A fresh feature branch has no branch.<name>.remote yet, so the
# common first push resolves to `origin` exactly as before when `origin`
# exists; `-u` sets upstream so later pushes need no remote argument. Two or
# more non-origin candidates with no `origin` set fails loudly (see §2.2)
# rather than pushing to an arbitrary remote.
PUSH_REMOTE=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/pull-request/scripts/resolve-remote.sh") || exit 1
git push -u "$PUSH_REMOTE" "$(git branch --show-current)"
```

Derive PR title from the commit subject, shaped to satisfy the resolved subject/title convention (the ladder in [SKILL.md](../SKILL.md): layered `source-control.md` config → project convention → Conventional Commits default). Build body with `${CLOSES_LINE}` at top, followed by Summary + Test plan + a `## Related` section + a config-gated attribution line:

```bash
# Quoted heredoc — body template is inert; nothing inside expands.
# Safe even if surrounding template prose contains $vars or $(cmds).
TEMPLATE=$(cat <<'EOF'
## Summary
...

## Test plan
- ...

## Related
N/A
EOF
)

# Resolve the PR-body attribution line from the `pr_body_attribution` key across
# the three source-control.md layers (../../reference/config-resolution.md), the
# same seam `/commit`'s `trailer_policy` uses for the commit trailer. Absent → the
# default line (current behavior — existing consumers are unaffected); a value of
# `none` → omit the line; any other value → that literal line. Resolve the effective
# value at the model level and bake it in as literal text below; do NOT reference it
# as an unexpanded shell var inside the quoted heredoc (a quoted heredoc emits
# `${ATTRIBUTION}` verbatim), and do NOT switch the heredoc to unquoted `<<EOF` to
# force expansion — that would re-evaluate the whole body and reopen the injection
# hole this section is built to close.
ATTRIBUTION='🤖 Generated with [Claude Code](https://claude.com/claude-code)'  # key absent → default
# pr_body_attribution: none         -> ATTRIBUTION=""            (omit the line)
# pr_body_attribution: <custom text> -> ATTRIBUTION='<that text>'  (SINGLE-quoted, NEVER
#                                       double-quoted: bash command-substitutes $(…) inside a
#                                       double-quoted assignment RHS at assignment time, so a
#                                       $()-bearing custom value would execute here — single-
#                                       quoting keeps it inert at the assignment site. Escape any
#                                       literal single quote as '\'' — e.g. ATTRIBUTION='it'\''s ok'.
#                                       The concat below is also inert, but assignment is the
#                                       first line of defense.)

# Concat CLOSES_LINE in front of TEMPLATE and ATTRIBUTION after it, via bash
# parameter expansion. Parameter expansion of "${VAR}" does NOT re-evaluate the
# expanded value — if CLOSES_LINE contains literal "$(rm -rf ~)" (e.g. user typed
# it into the orphan-PR or multi-issue prompt), or ATTRIBUTION carries a configured
# `$`-bearing custom line, it stays a literal string and is never executed. This is
# the defense against shell injection through user-supplied prompt input and
# configured text.
BODY=""
[[ -n "$CLOSES_LINE" ]] && BODY="${CLOSES_LINE}"$'\n\n'
BODY+="$TEMPLATE"
[[ -n "$ATTRIBUTION" ]] && BODY+=$'\n\n'"$ATTRIBUTION"
```

**Why quoted heredoc + concat (not `<<EOF`):** unquoted heredoc `<<EOF` evaluates `$(...)`, `${...}`, and `` `...` `` *inside the body content itself* (POSIX heredoc semantics — `<<EOF` is treated as if double-quoted). If `${CLOSES_LINE}` ever contains shell-meta from interactive prompt input, or `${ATTRIBUTION}` carries a configured custom line, an unquoted heredoc would execute it. Quoted `<<'EOF'` is inert; splicing `${CLOSES_LINE}` and `${ATTRIBUTION}` via parameter expansion + concat keeps both as literal text. The attribution line is deliberately spliced *outside* the heredoc rather than embedded inside it so that a `pr_body_attribution` value resolved from config never re-enters shell evaluation.

`gh pr create --body` fully overrides `.github/PULL_REQUEST_TEMPLATE.md` (cli/cli #10751) — body assembly above is the canonical path for skill-driven PRs; the template is the web-UI backstop. When the consuming project ships a PR template, mirror its section shape in the assembled body.

**Linkage scaffolds — always emitted.** Two scaffolds mirror the two-part contract a `pr-issue-linkage`-style gate enforces (a non-empty `## Related` section AND a native GitHub closing keyword or `No related issue:` opt-out), so a skill-driven PR clears that gate on first push instead of burning a red-CI round-trip:

- **Closing-keyword line** (`${CLOSES_LINE}` at top): always populated by §2.4.0 (branch-derived `Closes #N`, the multi-issue prompt, or the orphan-PR opt-out) and asserted by the §2.4.2 gate before create — a required, always-present scaffold, not a conditional decoration.
- **`## Related` section**: defaults to the literal `N/A` so the section is non-empty by default. Replace `N/A` with genuinely related-but-not-closed references — sibling PRs, ADRs, or decision-log entries (`Refs #N — <why>`, matching the repo's own `## Related` convention) — whenever they exist; leave `N/A` only when nothing else applies. The issue this PR *closes* belongs on the closing-keyword line, not here.

A `Refs #N` line links an issue without closing it and belongs in the `## Related` section, never on the closing-keyword line: it satisfies the closing-keyword half of **neither** the §2.4.2 pre-create gate nor the real `pr-issue-linkage` validator — only a real closing keyword or a literal `No linked issue` / `No related issue:` phrase does. When the branch resolves a real `Closes #N` (the common path) both halves pass; a PR that closes nothing needs a `No related issue:` line to clear the gate.

### 2.4.2 Verify closing-keyword line (pre-create gate)

Before invoking `gh pr create`, grep assembled `$BODY` for a valid closing keyword OR an opt-out marker. Catches branches where §2.4.0 fell through (issue-existence check failed without orphan-PR prompt running, user dismissed the prompt, `$CLOSES_LINE` is empty) and prevents shipping a PR with no linkage signal.

```bash
# Case-insensitive — covers ALL 9 valid keywords (close/closes/closed/fix/
# fixes/fixed/resolve/resolves/resolved) with optional colon, per GitHub's
# linked-issues docs. The 3-keyword shortcut (Closes|Fixes|Resolves)
# misses 6 valid forms GitHub auto-close honors.
KEYWORD_REGEX='^(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved):? #[0-9]+'
# Only `No related issue:` — a bare `Refs #N` links without closing and does NOT
# satisfy the real pr-issue-linkage validator's closing-keyword half, so accepting
# it here would clear a body the CI gate then rejects.
OPTOUT_REGEX='^No related issue:'

if printf '%s\n' "$BODY" | grep -iE "$KEYWORD_REGEX" >/dev/null; then
  :  # closing keyword present — gate passes
elif printf '%s\n' "$BODY" | grep -E "$OPTOUT_REGEX" >/dev/null; then
  :  # explicit opt-out present — gate passes
else
  # No closing keyword AND no opt-out marker. §2.4.0's orphan-PR prompt
  # should have populated one. If we reach here, either the prompt was
  # skipped or `$CLOSES_LINE` is empty.
  echo "⚠ PR body lacks a closing keyword (Closes/Fixes/Resolves #N, case-insensitive, optional colon) AND no opt-out marker (No related issue:)." >&2
  echo "  Re-run §2.4.0's orphan-PR prompt to choose: Closes #N | No related issue: <reason>" >&2
  echo "  Aborting PR creation. (Silent proceed would orphan the PR from any tracked issue.)" >&2
  exit 1
fi
```

When user explicitly selected `No related issue: <reason>` in §2.4.0, the gate passes silently — the opt-out is a legitimate path for refactors, drift sweeps, and hotfixes. Gate exists to catch the case where §2.4.0 fell through without populating `$CLOSES_LINE`.

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
# (Conventional Commits default shown; a custom resolved pr_title_pattern
# or the project's own convention overrides this).
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
