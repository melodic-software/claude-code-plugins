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

# Resolve the FETCH remote that hosts the default branch via the shared resolver
# (scripts/resolve-remote.sh): the current branch's configured remote
# (branch.<name>.remote), else `origin`, else the sole OTHER configured remote
# when exactly one exists — never a hardcoded `origin`, so a repo cloned with a
# different remote name (`git clone -o vendor`) still resolves. A local-only
# upstream (`.`) is treated as unset. Two or more non-origin candidates with
# neither branch.<name>.remote nor `origin` set is ambiguous and the resolver
# fails loudly rather than silently picking one. The §2.4.1 push step calls the
# same resolver with `--push`, which prepends Git's push precedence
# (branch.<name>.pushRemote / remote.pushDefault) so a triangular fork flow —
# fetch from `upstream`, push to the fork — resolves each side correctly instead
# of pushing to the fetch remote.
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

Before building PR body, parse branch for the primary (numeric GitHub) issue number and prompt for any additional closures. Keyword line is injected at top of body in §2.4.1.

By default the parser uses the built-in `<type>/<N>-<slug>` (and `routine-issue-<N>`) convention:

```bash
ISSUE_NUM=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/pull-request/scripts/parse-branch-issue.sh" 2>/dev/null || true)
```

If SKILL.md's "Branch-to-issue grammar" surface shows a configured `branch_issue_pattern` (a real ERE, not the literal `${user_config…}` token — this reference file is Read raw, so the value is resolved there, never here), pass it as a **single-quoted** second positional; the empty first argument keeps the branch-name default (`git branch --show-current`). Single-quoting shields ERE metacharacters like the `$` end-anchor from the shell:

```bash
ISSUE_NUM=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/pull-request/scripts/parse-branch-issue.sh" "" '<branch-issue-pattern>' 2>/dev/null || true)
```

Fill `<branch-issue-pattern>` with the resolved ERE. Its last capture group must resolve to the numeric GitHub issue number (a non-numeric capture — e.g. a bare Jira key — is looked up below, found absent, and dropped to the no-closure path); configure a scheme that captures the number wherever it sits, e.g. `^[^/]+/([0-9]+)-` for `alice/1234-slug` or `-([0-9]+)$` for `feat/add-widget-1234`.

```bash
CLOSES_LINE=""
REFS_LINES=""  # newline-separated `Refs #Y — <why>` lines, populated by the multi-issue or
                # orphan-PR prompts below; never a closing keyword — see §2.4.1 for routing.
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

Append each accepted `Closes #X` line to `${CLOSES_LINE}` (newline-separated); collect each accepted `Refs #Y` line into `${REFS_LINES}` instead, never onto the closing-keyword line — §2.4.1 routes `${REFS_LINES}` into a `## Related` section (required by resolved config, or emitted ad hoc when non-empty and not required — see §2.4.1's section-scaffold resolution). GitHub accepts one keyword per issue, comma- or newline-separated.

**Branch lacks issue number (orphan PR — drift sweep, hotfix, refactor):** prompt with two options:

1. `Closes #<N>` — provide a number to auto-close on merge
2. `No related issue: <reason>` — orphan PR, no linkage

To reference an issue this PR does **not** close, collect a `Refs #N — <why>` line into `${REFS_LINES}` (§2.4.1), not the closing-keyword line: a bare `Refs #N` satisfies neither the §2.4.2 pre-create gate nor the real `pr-issue-linkage` validator's closing-keyword half, so such a PR still picks one of the two options above.

Persist chosen line(s) into `${CLOSES_LINE}`. NEVER wrap a closing keyword in an HTML comment — `<!-- Closes #N -->` is parsed as a valid keyword and will auto-close the issue on merge. Fenced code blocks ARE inert, so example snippets are safe.

### 2.4.1 Push and assemble PR body

```bash
# Push via push-branch.sh, which resolves the push and fetch/rebase remotes
# independently (resolve-remote.sh --push vs plain) and sets upstream (`-u`)
# ONLY for a branch with NO existing upstream — branch.<name>.remote AND
# branch.<name>.merge both unset — whose fetch and push resolve to the same
# remote (a fresh feature branch's first push). `git push -u` rewrites the
# branch's whole upstream — both keys — so any existing upstream (a real remote,
# a deliberate local-only `.`, or a merge ref set with the remote defaulting to
# `origin`) is preserved by a plain push instead. This closes two silent
# corruptions: a triangular fork (push a fork via pushRemote/pushDefault, fetch
# `origin`/`upstream`) no longer repoints the fetch remote to the fork, and a
# branch with any configured tracking no longer has its merge ref overwritten.
# See the script header for the full rationale.
bash "${CLAUDE_PLUGIN_ROOT}/skills/pull-request/scripts/push-branch.sh" || exit 1
```

Derive PR title from the commit subject, shaped to satisfy the resolved subject/title convention (the ladder in [SKILL.md](../SKILL.md): layered `source-control.md` config → project convention → Conventional Commits default). Build body with `${CLOSES_LINE}` at top, followed by the resolved section scaffold and a config-gated attribution line.

**Resolve the required section scaffold first.** Read `pr_body_required_sections` across the three `source-control.md` layers per [../../../reference/config-resolution.md](../../../reference/config-resolution.md) (per-key override — a winning layer's list is taken whole, never merged with an earlier layer's). Absent everywhere → the bundled portable default, `Summary` and `Test plan` only (no `Related` — see [`docs/conventions/pr-body-convention/README.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/pr-body-convention/README.md) for why the portable default excludes it). The literal keyword `none` resolves to **zero required sections** — the winning layer's `none` overrides a lower layer's list the same way a list would (a resolved value, never an absence; parallel to `trailer_policy`/`pr_body_attribution`), the template below emits no scaffold blocks, and the §2.4.2.2 gate has nothing to require. Track which file/layer supplied the effective list — the §2.4.2 gate cites it verbatim on failure.

```bash
# REQUIRED_SECTIONS: resolved at the model level from the three source-control.md layers'
# `## pr_body_required_sections` bullet lists (one heading per `- ` line), per-key whole-list
# override. Shown here with the portable default; a resolved config layer replaces both the
# array and the source string wholesale.
REQUIRED_SECTIONS=("Summary" "Test plan")
REQUIRED_SECTIONS_SOURCE="plugin default (no source-control.md layer sets pr_body_required_sections)"
# When a layer resolves the key, e.g.:
#   REQUIRED_SECTIONS=("Summary" "Test plan" "Related")
#   REQUIRED_SECTIONS_SOURCE="<repo-root>/.claude/source-control.md, ## pr_body_required_sections (team layer)"
# When the winning layer declares the literal keyword `none` (no required sections):
#   REQUIRED_SECTIONS=()
#   REQUIRED_SECTIONS_SOURCE="<repo-root>/.claude/source-control.md, ## pr_body_required_sections (team layer, none)"
```

Build one `## <heading>` block per entry in `${REQUIRED_SECTIONS[@]}`, real content in each — never
literal placeholder text. `Related` uses `${REFS_LINES}` (collected in §2.4.0) when non-empty, else the
established default `N/A` — this resolution is the SAME regardless of whether `Related` reached the
scaffold via `${REQUIRED_SECTIONS[@]}` (configured) or the ad hoc append below (not configured, but
genuine refs exist): there is exactly one place `Related`'s content is decided, never two. `Test plan`
gets its established default (verification steps actually taken) when nothing more specific applies;
any other heading (including a repo-declared custom one) gets content matching what that heading names,
the same way `Summary` already does. If `${REFS_LINES}` is non-empty and `Related` is **not** in
`${REQUIRED_SECTIONS[@]}`, still append a `## Related` section carrying those lines — real
user-supplied content is never dropped — but do **not** add it to `${REQUIRED_SECTIONS[@]}`: an ad hoc
`Related` section is present only because it has real content, and the §2.4.2 gate must never come to
require a section the resolved config does not list. Under a resolved `none` the loop below builds an
empty `TEMPLATE`, and the assembled body carries only the closing-keyword line, any ad hoc `## Related`
(the real-refs rule above applies unchanged — `none` suppresses the *required* scaffold, never
user-supplied content), and the §2.4.3 attribution line.

```bash
# One content resolver, reused whether Related is required or ad hoc — the single place
# that decides what goes under any heading, so the two paths can never disagree.
content_for_section() {
  case "$1" in
    Related) [[ -n "$REFS_LINES" ]] && printf '%s' "$REFS_LINES" || printf 'N/A' ;;
    *) printf '<real content for %s>' "$1" ;;  # model fills real content before executing
  esac
}

# Quoted heredoc segments — inert; nothing inside expands. Safe even if a heading's
# real content contains $vars or $(cmds).
TEMPLATE=""
for section in "${REQUIRED_SECTIONS[@]}"; do
  TEMPLATE+="## ${section}"$'\n\n'"$(content_for_section "$section")"$'\n\n'
done
if [[ -n "$REFS_LINES" ]] && ! printf '%s\n' "${REQUIRED_SECTIONS[@]}" | grep -qx "Related"; then
  TEMPLATE+="## Related"$'\n\n'"$(content_for_section "Related")"$'\n\n'
fi

# Resolve the PR-body attribution line from the `pr_body_attribution` key across
# the three source-control.md layers (../../../reference/config-resolution.md), the
# same seam `/commit`'s `trailer_policy` uses for the commit trailer. Absent → the
# default line (current behavior — existing consumers are unaffected); a value of
# `none` → omit the line; any other value → that literal line. Resolve the effective
# value at the model level and bake it in as literal text below; do NOT reference it
# as an unexpanded shell var inside a quoted heredoc segment (it would emit
# `${ATTRIBUTION}` verbatim), and do NOT switch to an unquoted `<<EOF` to force
# expansion — that would re-evaluate the whole body and reopen the injection hole
# this section is built to close.
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

# Concat CLOSES_LINE in front of TEMPLATE via bash parameter expansion. Parameter
# expansion of "${VAR}" does NOT re-evaluate the expanded value — if CLOSES_LINE or
# REFS_LINES contains literal "$(rm -rf ~)" (e.g. user typed it into the orphan-PR
# or multi-issue prompt), it stays a literal string and is never executed. This is
# the defense against shell injection through user-supplied prompt input.
#
# ATTRIBUTION is deliberately NOT appended here. §2.4.2.2's required-section gate
# scans from each "## <heading>" to the next "## " heading OR end of body — if
# ATTRIBUTION were already part of $BODY, an empty LAST required section's scan
# would run off the end of the template and into the attribution footer, which is
# non-whitespace text with no "## " prefix, and the gate would misread it as that
# section's real content (defeating the emptiness check for exactly the last
# section). Keeping the footer out of $BODY until after §2.4.2 passes closes that
# hole structurally, rather than teaching the gate to special-case a footer shape.
BODY=""
[[ -n "$CLOSES_LINE" ]] && BODY="${CLOSES_LINE}"$'\n\n'
BODY+="$TEMPLATE"
```

**Why quoted heredoc segments + concat (not a single `<<EOF`):** unquoted heredoc `<<EOF` evaluates `$(...)`, `${...}`, and `` `...` `` *inside the body content itself* (POSIX heredoc semantics — `<<EOF` is treated as if double-quoted). If `${CLOSES_LINE}` or `${REFS_LINES}` ever contains shell-meta from interactive prompt input, an unquoted heredoc would execute it. Quoted heredoc content is inert; splicing `${CLOSES_LINE}` and the per-section content via parameter expansion + concat keeps all of it as literal text.

`gh pr create --body` fully overrides `.github/PULL_REQUEST_TEMPLATE.md` (cli/cli #10751) — body assembly above is the canonical path for skill-driven PRs; the template is the web-UI backstop. When the consuming project ships a PR template, mirror its section shape in the assembled body (or, better, express it as the project's own `pr_body_required_sections` — see [`docs/conventions/pr-body-convention/README.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/pr-body-convention/README.md)).

**Linkage scaffolds — always emitted, independent of the section scaffold.** The closing-keyword line and the section scaffold are two separate mechanisms that happen to compose on the same body:

- **Closing-keyword line** (`${CLOSES_LINE}` at top): always populated by §2.4.0 (branch-derived `Closes #N`, the multi-issue prompt, or the orphan-PR opt-out) and asserted by the §2.4.2 gate before create — a required, always-present scaffold, not a conditional decoration, and entirely independent of `pr_body_required_sections`.
- **`## Related` section**: present when `Related` is in the resolved `${REQUIRED_SECTIONS[@]}` (defaults to the literal `N/A`, replaced by `${REFS_LINES}` when genuinely related-but-not-closed references exist — sibling PRs, ADRs, decision-log entries), or ad hoc when `${REFS_LINES}` is non-empty even though `Related` is not required. Absent in the portable default (no config) with no genuine refs to carry. The issue this PR *closes* belongs on the closing-keyword line, not here, in every case.

A `Refs #N` line links an issue without closing it and never belongs on the closing-keyword line: it satisfies the closing-keyword half of **neither** the §2.4.2 pre-create gate nor the real `pr-issue-linkage` validator — only a real closing keyword or a literal `No linked issue` / `No related issue:` phrase does. When the branch resolves a real `Closes #N` (the common path) both halves pass; a PR that closes nothing needs a `No related issue:` line to clear the gate.

### 2.4.2 Pre-create gate

Before invoking `gh pr create`, run two independent checks against assembled `$BODY`: the closing-keyword check (unchanged, existing mechanism) and the required-section check (new, generic — reads `pr_body_required_sections`, never a hardcoded section list). Both must pass.

#### 2.4.2.1 Verify closing-keyword line

Grep assembled `$BODY` for a valid closing keyword OR an opt-out marker. Catches branches where §2.4.0 fell through (issue-existence check failed without orphan-PR prompt running, user dismissed the prompt, `$CLOSES_LINE` is empty) and prevents shipping a PR with no linkage signal.

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

#### 2.4.2.2 Verify required sections (config-driven)

For every heading in `${REQUIRED_SECTIONS[@]}` (resolved in §2.4.1 from `pr_body_required_sections`, or the portable default), confirm a `## <heading>` section exists in `$BODY` **and** its body is non-empty. This is a generic mechanism — it verifies whatever the resolved config lists, never a section name baked into this skill. A resolved `none` (§2.4.1) leaves `${REQUIRED_SECTIONS[@]}` empty, so this check passes with nothing to verify — the §2.4.2.1 closing-keyword check is independent and still runs. Deferred beyond presence + non-empty (per [`docs/conventions/pr-body-convention/README.md`](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/pr-body-convention/README.md)): placeholder-text detection (`TBD`/`TODO`/a restated heading) and per-section min-content rules — `standards#173`.

```bash
MISSING_SECTIONS=()
for section in "${REQUIRED_SECTIONS[@]}"; do
  # Everything after "## <section>" up to the next "## " heading or end of body.
  # Fence- and comment-aware: heading matches only count outside a fenced code block
  # ("```"/"~~~") AND outside an HTML comment (<!-- ... -->, single- or multi-line) —
  # a Summary that documents a template containing a literal "## Related" inside a
  # code sample, or a body carrying a commented-out draft section, must never
  # satisfy the Related requirement GitHub itself renders as absent.
  #
  # Fences and comments are NOT symmetric once inside the found section: a fence
  # delimiter there is real, RENDERED content and stays in the captured body (a
  # section whose own genuine content includes a code block is still captured
  # correctly) — but a comment is never rendered at all, so comment text is
  # never counted as content, even inside a found section. An *inline* comment
  # is stripped as a SPAN, not a whole line, though: "Ran smoke tests <!-- done
  # --><!-- todo -->" keeps "Ran smoke tests " (GitHub still renders the text
  # outside the comment) rather than dropping the entire line the way a
  # comment-only line correctly does. A fence or comment already open when a
  # line starts consumes that line's meaning entirely before any NEW fence or
  # comment on the same line is considered — GFM parses both literally with no
  # nested markup, so a "<!--" inside an open fence, or a "```" inside an open
  # comment, is never a real comment/fence start.
  SECTION_BODY=$(printf '%s\n' "$BODY" | awk -v h="## ${section}" '
  function strip_comment_span(line,    out, idx) {
    # Removes every "<!-- ... -->" span from `line`, keeping visible text
    # before/after/between spans on the same line; updates the global
    # in_comment state when a span does not close on this line (a multi-line
    # comment). A comment-only line returns "".
    out = ""
    while (1) {
      if (in_comment) {
        idx = index(line, "-->")
        if (idx == 0) { return out }
        line = substr(line, idx + 3)
        in_comment = 0
      } else {
        idx = index(line, "<!--")
        if (idx == 0) { return out line }
        out = out substr(line, 1, idx - 1)
        line = substr(line, idx + 4)
        in_comment = 1
      }
    }
  }
  {
    # Fence detection matches GFM (https://github.github.com/gfm/#fenced-code-blocks):
    # up to 3 leading spaces, then 3+ of the SAME fence character (backtick or
    # tilde) — a fence indented inside a list item is still recognized, and a
    # ``` opener is closed only by another ``` line, never by a ~~~ line (and
    # vice versa). Exact opener/closer run-length parity (a further GFM nicety)
    # is not tracked — this scan only needs "is this line inside a fence", not
    # faithful code-block rendering.
    stripped = $0
    sub(/^ {0,3}/, "", stripped)
    fence_char = ""
    if (stripped ~ /^```/) fence_char = "`"
    else if (stripped ~ /^~~~/) fence_char = "~"

    # An already-open fence or comment takes absolute priority (see the block
    # comment above) — checked before anything else, including the heading and
    # exit-boundary tests below.
    if (in_fence) {
      if (fence_char == open_char) in_fence = 0
      if (found) print
      next
    }
    if (in_comment) {
      visible = strip_comment_span($0)
      if (found && visible != "") print visible
      next
    }

    # Heading and exit-boundary checks run on the RAW line, never a
    # comment-stripped one: a real ATX heading (or the next one, ending this
    # section) must start the line itself, so a "##"-shaped fragment freed by
    # stripping a same-line comment could never be a real heading GitHub would
    # render as one. Checking the raw line here also means a heading carrying
    # a trailing inline comment ("## Related <!-- draft -->") is still
    # correctly read as a real exit boundary, not misrouted into the
    # comment-open branch below.
    if (!found && $0 == h) { found = 1; next }
    if (found && $0 ~ /^## /) { exit }

    if (fence_char != "") { in_fence = 1; open_char = fence_char; if (found) print; next }
    if ($0 ~ /<!--/) {
      visible = strip_comment_span($0)
      if (found && visible != "") print visible
      next
    }
    if (found) print
  }
  ')
  if [[ -z "$(printf '%s' "$SECTION_BODY" | tr -d '[:space:]')" ]]; then
    MISSING_SECTIONS+=("$section")
  fi
done

if [[ ${#MISSING_SECTIONS[@]} -gt 0 ]]; then
  echo "⚠ PR body is missing required section(s): ${MISSING_SECTIONS[*]}" >&2
  echo "  Required sections resolved from: ${REQUIRED_SECTIONS_SOURCE}" >&2
  echo "  Add each missing '## <heading>' with real content, then re-run create." >&2
  echo "  Aborting PR creation. (Silent proceed would ship a body that fails the same check downstream.)" >&2
  exit 1
fi
```

The message names the exact missing heading(s) and the resolved config source (§2.4.1's `${REQUIRED_SECTIONS_SOURCE}` — the winning layer's file path, or the plugin default when no layer sets the key), so an actor who never saw the convention learns where it lives from the failure itself.

### 2.4.3 Create PR

Append `${ATTRIBUTION}` (resolved in §2.4.1) to `$BODY` only now, after both §2.4.2 gates have
passed against the attribution-free body — never earlier, per §2.4.1's note on why the footer stays
out of the gated content:

```bash
# Splice outside any heredoc, same inertness rationale as §2.4.1's CLOSES_LINE/TEMPLATE
# concat: parameter expansion never re-evaluates a `$`-bearing configured ATTRIBUTION value.
[[ -n "$ATTRIBUTION" ]] && BODY+=$'\n\n'"$ATTRIBUTION"

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

## 2.7 `create --pushed` — PR-only entry for an orchestrated flow

`create --pushed --worktree <path>` opens the PR when the branch is **already committed and pushed** — the orchestrated case where a dispatched worker did the edits, commit, and push inside its own out-of-tree worktree and returned that worktree's path (`/work-items:work`, `#572`). The invoking orchestrator is typically **out-of-tree** (its session sits on the default branch or elsewhere), so this mode runs neither the commit/push half of the normal `create` path nor trusts the session cwd.

**Ignore the pre-computed context.** [SKILL.md](../SKILL.md)'s `!`-substituted frontmatter (`git branch --show-current`, `git diff --name-only HEAD`, working-tree status) reflects the **session cwd**, which for an out-of-tree orchestrator is the wrong branch and diff — and a `!`-substituted line cannot be `git -C`-redirected. Under `--pushed`, re-resolve everything from the target worktree instead:

```bash
WT="<path>"                                   # from --worktree
BRANCH=$(git -C "$WT" branch --show-current)
```

**Preconditions (assert, never redo).** The worker's contract is to commit, push, and be current with the default branch before returning; verify rather than repeat:

- **Clean tree:** `git -C "$WT" status --porcelain` empty — else STOP (the worker returned with uncommitted work).
- **Pushed to the remote at HEAD:** confirm the branch's remote tip equals local HEAD **without relying on `@{u}`** — a worker that pushed with `git push origin <branch>` (no `-u`) has no upstream configured, so `git log @{u}..` would exit 128 on a branch that is in fact fully pushed. Resolve the fetch remote and compare the refs directly:

  ```bash
  # Resolve the PUSH remote (the destination the worker pushed to) via the shared
  # resolver in --push mode, run FROM the worktree so it reads $BRANCH's config —
  # never a hardcoded `origin`, so a `git clone -o vendor` or a triangular fork
  # flow (fetch upstream, push fork) verifies the ref at the right destination.
  REMOTE=$( cd "$WT" && bash "${CLAUDE_PLUGIN_ROOT}/skills/pull-request/scripts/resolve-remote.sh" --push ) || exit 1
  git -C "$WT" fetch -q "$REMOTE" "$BRANCH"
  [ "$(git -C "$WT" rev-parse HEAD)" = "$(git -C "$WT" rev-parse FETCH_HEAD)" ] \
    || { echo 'worker branch is not fully pushed to the remote' >&2; exit 1; }
  ```

  else STOP (the worker returned without pushing HEAD).

**Sub-steps relative to the normal `create` path:**

- **§2.1 / §2.3 (branch-name prompts, stage + commit):** skipped — the worker already committed; the preconditions above replace them.
- **§2.2 (rebase onto the default branch):** skipped — bringing the branch current is the worker's pre-return responsibility, and residual staleness is caught by `gh pr view --json mergeable` and CI in Phase 3. The out-of-tree orchestrator cannot rebase a branch it is not on with a clean tree, so it never owns this step.
- **§2.4.1 (push):** skipped — replaced by the unpushed-commits assertion above.
- **§2.4.0 (`Closes #N`), §2.4.1 (body assembly), §2.4.2 (pre-create gates):** run unchanged, except every `git`/diff read is anchored with `git -C "$WT"` and the branch is `$BRANCH`, never the session branch. In §2.4.0 this means passing `$BRANCH` as `parse-branch-issue.sh`'s explicit first positional (`parse-branch-issue.sh "$BRANCH" ['<branch-issue-pattern>']`) — the script defaults to `git branch --show-current` **in its own process**, which an out-of-tree orchestrator cannot redirect with `git -C`, so leaving it implicit would parse `Closes #N` from the orchestrator's own branch and silently drop the linkage.
- **§2.4.3 (create):** `gh pr create` MUST pass `--head "$BRANCH"` explicitly, since the invoker is not on the branch:

  ```bash
  PR_URL=$(gh pr create --head "$BRANCH" --title "<type>: <description>" --body "$BODY")
  ```

- **§2.5 / §2.6:** unchanged — record expected workflows, report the PR URL + number, and stop.

This mode is create-only: it never merges, and (like standalone `create`) it hands monitoring off to `/pull-request monitor` / `/pull-request full` or, in the orchestrated lane, back to the calling orchestrator.
