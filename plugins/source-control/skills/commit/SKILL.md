---
name: commit
description: "Create a git commit with a subject matching the resolved convention (`.claude/source-control.md` → project convention → Conventional Commits default), a Claude Co-Authored-By trailer, and surgical staging (never `git add -A`), feeding the message to git via Bash heredoc. Use when: 'commit this', 'make a commit', 'commit with message <hint>' — not for push, branch creation, or PR creation (use /pull-request)."
argument-hint: "[message-hint]"
user-invocable: true
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Staged: !`git diff --cached --stat 2>/dev/null | tail -1 || echo "nothing staged"`
Unstaged: !`git status --short 2>/dev/null | head -20 || echo "clean"`
Recent commits: !`git log --oneline -5 2>/dev/null || echo "no commits"`

## Purpose

Encapsulates the canonical mechanic for building a commit message that honors a Conventional Commits subject convention, appending a `Co-Authored-By:` trailer, and feeding the result to `git commit` via stdin — without these failure modes:

- **PowerShell here-string syntax (`@'...'@`) inside a Bash tool call** produces `unexpected EOF` and triggers fallback to writing the message to `.git/<TEMP>.txt`. `.git/` is git's internal directory; scratch files there collide with `COMMIT_EDITMSG` and other internals.
- **`git commit -m "<multi-line>"`** flattens newlines unpredictably across shells.
- **`git add -A` / `git add .`** stages secrets, build artifacts, unrelated edits — the convention is surgical staging.

The subject convention (WHAT shape a subject must take) resolves via a ladder, checked in order:

1. **`.claude/source-control.md`** — if the consuming repo has this tracked config (written by `/source-control:setup`), its declared `subject_pattern` (and `type_list`, when Conventional-Commits-shaped) is authoritative.
2. **The consuming project's own `CLAUDE.md`, rules, or commit-msg hook** — if no config file exists but the project declares (or enforces via lefthook, husky, commitlint, or a plain `.git/hooks/`) a different convention, follow that instead. (Existing behavior — unchanged.)
3. **Conventional Commits (11-type vocabulary)** — the default when neither of the above is present. Every subject must match this anchored pattern:

```text
^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+
```

Compliant examples:

- `feat(auth): add OAuth login flow`
- `fix(api): handle null user in /me endpoint`
- `docs: clarify rebase guidance`
- `refactor(skills)!: rename /simplify to /code-review`

The 11 types — `build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test` — come from the Conventional Commits spec, the Angular convention, commitlint's `@commitlint/config-conventional` source, and `amannn/action-semantic-pull-request`'s default `types` list; all four agree on this exact set. `security` is **not** a Conventional Commits type in any of them — never add it.

When the project enforces its convention with a commit-msg git hook (lefthook, husky, commitlint, plain `.git/hooks/`), that hook is the authoritative gate regardless of which rung above resolved the pattern; this skill's pre-check exists to fast-fail client-side before the hook round-trip. When no config exists and nothing is inferable from the project's own files, point the user at `/source-control:setup` to persist a convention instead of re-inferring one every commit.

## Task

1. Survey working tree (`git status`, `git diff --cached --stat`) to confirm what's staged.
2. Draft a subject + optional body, scoped to the staged diff, shaped to satisfy the active subject convention (default: the Conventional Commits pattern above).
3. Pre-check the subject against the pattern (fast-fail before invoking git).
4. Invoke `git commit -F -` via the Bash tool, heredoc-piped, with `--trailer` for `Co-Authored-By` per the trailer template below.
5. Surface the resulting commit SHA + subject to the user.

## Canonical bash form

Use the **Bash tool**, not the PowerShell tool. Bash heredoc is the canonical form across all platforms (Git Bash, Linux, macOS).

```bash
git commit -F - --cleanup=verbatim \
  --trailer "<Co-Authored-By trailer, placeholders filled>" \
  <<'EOF'
<subject — shaped to satisfy the active subject convention>

<body — wrap at ~72 cols, blank line between paragraphs>
EOF
```

The `--trailer` argument body is this template:

```text
Co-Authored-By: Claude <model> (<context>) <noreply@anthropic.com>
```

Fill the `<model>` / `<context>` placeholders from session knowledge before passing the string to `--trailer` (see "Trailer model + context lookup" below).

PowerShell here-string is shown only for reference — `git commit -F - <message-via-stdin>` with `@'...'@` would work in a pure PowerShell tool call, but **never mix syntaxes inside one tool invocation**. A PowerShell `@'...'@` block inside a Bash tool call leaves the bash parser unable to terminate the heredoc.

**Hard rules:**

- Invoke via the **Bash tool**.
- Heredoc delimiter is single-quoted: `<<'EOF' ... EOF`. Single quotes prevent `$variable` and backtick interpolation inside the message.
- `--cleanup=verbatim` preserves the message exactly — no auto-stripping of comments or whitespace.
- Never write the message to `.git/<TEMP>.txt`. If a real file is unavoidable, use `mktemp`.
- Never mix Bash heredoc with PowerShell `@'...'@` inside one invocation.

## Pre-check

Before invoking `git commit`, regex-match the drafted subject against the active convention's pattern (default: the Conventional Commits pattern above).

On mismatch, surface the convention name and the compliant examples as actionable guidance, and ask for a compliant subject before invoking git. The pre-check is shape-only; the project's `commit-msg` git hook (when one exists) is the authoritative gate at commit time. The pre-check exists to save the hook-startup floor when the drafted subject is obviously wrong, plus to give the user a fast actionable error rather than an opaque hook failure.

## Trailer model + context lookup

The trailer body is `Co-Authored-By: Claude <model> (<context>) <noreply@anthropic.com>`. Fill the `<model>` and `<context>` placeholders from your own knowledge of the running session — e.g. model = `Opus 4.8` or `Fable 5`, context = `1M context`. If uncertain, invoke `/usage` to confirm before committing.

There is no environment variable that auto-fills these — the trailer is part of the message body sent to `git commit`, not git config. Hardcoding stale values is worse than asking; the trailer becomes a git-history claim about which model / context authored the change. If `.claude/source-control.md` declares a `trailer_policy`, follow it; otherwise, if the consuming project's conventions specify a different attribution trailer (or none), follow those.

## Unrelated uncommitted changes

If the working tree contains unstaged or untracked files that fall outside this commit's scope, classify each before staging per `/pull-request create` (its unrelated-changes classification: include / stash / separate-commit / discard). Do not duplicate that classification here; invoke `/pull-request create` to surface it to the user.

## Staging discipline

Always `git add <specific-files>`, never `git add -A` or `git add .`. The risk is including secrets, build artifacts, or unrelated changes that the user did not approve for this commit. If multiple files are intentionally part of the commit, stage them by explicit list, not by wildcard.

## Pathspec-limited commits (dirty shared index)

When the index already holds staged files OUTSIDE this commit's scope — concurrent Claude Code sessions on the same branch, pre-existing mixed WIP — a bare `git commit` would sweep them all in. Instead, limit the commit by pathspec:

```bash
git commit -F - --cleanup=verbatim \
  --trailer "<Co-Authored-By trailer>" \
  -- <path> [<path>...] <<'EOF'
<subject>

<body>
EOF
```

Semantics (per `git-commit(1)` default `--only` mode): the commit records the **working-tree content** of the named paths, disregarding what is staged for all OTHER paths — concurrent-session staged work stays staged, untouched. Untracked files still need `git add` first; pathspec alone never picks them up.

**Safety preconditions — all required before offering this path:**

- Every named path is fully this commit's work — no overlap with another session's in-flight scope (when unsure which session owns a file, ask).
- For each named path, working tree == intended content (pathspec commits the worktree version, silently superseding any different staged version of that same path).
- Verify scope with `git diff --cached --stat -- <pathspec>` and surface that stat in the review gate — the user greenlights exactly what the pathspec captures.
- A directory pathspec (`-- path/to/dir/`) is acceptable only after confirming via `git status --porcelain -- <dir>` that nothing under it belongs to another scope; otherwise enumerate files.

Default remains the plain index commit; reach for the pathspec form only when the index is verifiably shared/dirty.

## Composition policy

This skill is the single source of truth for the commit mechanic. Other skills should compose `/commit` by natural-language reference rather than invoking `git commit` directly — direct calls bypass the pre-check, trailer logic, and surgical-staging discipline this skill exists to enforce.

Workflow skills without explicit commit semantics should report status at phase boundaries and let the user or the next workflow stage decide commit timing; a skill with commit semantics in its documented contract (e.g. `/pull-request create`) composes this one.

## What this skill does NOT do

- **No `git push`** — that's `/pull-request create`.
- **No branch creation** — that's the project's branch-naming / branch-protection mechanisms (or `/worktree create`).
- **No PR body composition** — that's `/pull-request create`.
- **No `git merge` / `gh pr merge`** — that's `/pull-request merge`.
- **No rebase** — that's `/pull-request create`.
- **No `--no-verify` or hook bypass** — if the project's `commit-msg` hook rejects the message, surface the error and re-draft; never bypass.
