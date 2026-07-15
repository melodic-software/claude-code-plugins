---
name: commit
description: "Create a git commit with a Conventional Commits subject, a Claude Co-Authored-By trailer, and surgical staging (never `git add -A`), feeding the message to git via Bash heredoc. Use when: 'commit this', 'make a commit', 'commit with message <hint>' — not for push, branch creation, or PR creation (use /pull-request)."
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

The default subject convention (WHAT shape a subject must take) is **Conventional Commits (11-type vocabulary)**. Every subject must match this anchored pattern:

```text
^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+
```

Compliant examples:

- `feat(auth): add OAuth login flow`
- `fix(api): handle null user in /me endpoint`
- `docs: clarify rebase guidance`
- `refactor(skills)!: rename /simplify to /code-review`

**Consumer convention wins.** If the consuming project's own `CLAUDE.md`, rules, or commit-msg hook declare a different message convention, follow that instead — this skill's pattern is the default, not an override. When the project enforces its convention with a commit-msg git hook (lefthook, husky, commitlint, plain `.git/hooks/`), that hook is the authoritative gate; this skill's pre-check exists to fast-fail client-side before the hook round-trip.

## Task

1. Survey working tree (`git status`, `git diff --cached --stat`) to confirm what's staged.
2. Stage the intended files, but first check each for a pre-existing partial-staging split (`git diff --cached --stat -- <path>` non-empty AND `git diff --stat -- <path>` also non-empty, checked *before* this step touches anything): a path already in that state has hunks the user deliberately left unstaged, so leave it as-is rather than running `git add <path>` over it — a blanket add would sweep those unstaged hunks in too. Run `git add <path>...` only for paths not already in a partial-staging split.
3. Run the format-before-push check below against the files just staged for this commit (not the full staged set — see the pathspec note in that check), if a local formatter/linter is discoverable, re-staging any fixes.
4. Run the exec-bit check below on any newly-added file — **after** step 3, not before: a formatter re-stage in step 3 reads the worktree file mode, so setting the exec bit any earlier would be silently undone by that later `git add`.
5. Draft a subject + optional body, scoped to the staged diff, shaped to satisfy the active subject convention (default: the Conventional Commits pattern above).
6. Pre-check the subject against the pattern (fast-fail before invoking git).
7. Invoke `git commit -F -` via the Bash tool, heredoc-piped, with `--trailer` for `Co-Authored-By` per the trailer template below.
8. Surface the resulting commit SHA + subject to the user.

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

There is no environment variable that auto-fills these — the trailer is part of the message body sent to `git commit`, not git config. Hardcoding stale values is worse than asking; the trailer becomes a git-history claim about which model / context authored the change. If the consuming project's conventions specify a different attribution trailer (or none), follow those.

## Unrelated uncommitted changes

If the working tree contains unstaged or untracked files that fall outside this commit's scope, classify each before staging per `/pull-request create` (its unrelated-changes classification: include / stash / separate-commit / discard). Do not duplicate that classification here; invoke `/pull-request create` to surface it to the user.

## Staging discipline

Always `git add <specific-files>`, never `git add -A` or `git add .`. The risk is including secrets, build artifacts, or unrelated changes that the user did not approve for this commit. If multiple files are intentionally part of the commit, stage them by explicit list, not by wildcard — and skip the partial-staging split per step 2 above.

Immediately after staging, run the format-before-push check and then the exec-bit check below, in that order — catch what CI would otherwise catch on the push round-trip.

## Format-before-push check

Before drafting the commit message, check whether the consuming repo already has a formatter or linter configured, and run it against the paths just staged for **this commit** — never the whole index — catching issues locally that CI would otherwise catch after a push:

- `package.json` `scripts.format` / `scripts.lint` (`npm run format`, `npm run lint`)
- `biome.json` / `biome.jsonc` (`biome check --write`, scoped to the changed paths)
- A `Makefile` `format` or `lint` target
- `.editorconfig` paired with an installed `editorconfig-checker`
- Any other formatter/linter config already at the repo root (`.prettierrc`, `rustfmt.toml`, `.golangci.yml`, a markdown-lint config, etc.), run with its matching CLI

Scope every invocation to the explicit path list from step 2 (`<path>...`), the same list a pathspec-limited commit would use below — never a bare/whole-repo invocation of the formatter. When the index also holds staged work outside this commit's scope (see Pathspec-limited commits below), a whole-index run would mutate or block on paths this commit doesn't own; the explicit path list is what keeps the check inside this commit's boundary. Run only what's already configured and discoverable in the consuming repo — never install or invent a formatter for this step. If nothing is discoverable, skip this step silently; don't block the commit on tooling that doesn't exist.

**Expand directory pathspecs before filtering.** The path list from step 2 can itself be a directory pathspec (`-- path/to/dir/`, per the Pathspec-limited commits section below) rather than individual files. A directory handed straight to a formatter is not "one file" the filter below can evaluate — most formatters treat a directory argument as a recursive target and walk everything under it, not just this commit's staged files, and an exists/status check silently no-ops against a directory (it always "exists" and carries no cached status of its own). Before any filtering, expand every directory entry in the path list into its actual staged files via `git diff --cached --name-only -- <dir>`, then run the filtering below against that expanded, file-only list.

**Filter to existing, formatter-supported files before invoking.** The staged path list (after directory expansion above) can include a path this commit deletes or renames away from, or a path of a type the tool doesn't format at all (a binary asset, an extension outside the tool's supported set). Passing those straight through can make the tool exit non-zero even though CI would never have formatted them either — Prettier, for example, exits with an error on a missing path or an extension it doesn't recognize unless told otherwise. Filter in two ordered stages, not one on-disk check alone:

1. **Cached-status stage first.** Drop paths whose `git diff --cached --name-status` entry is `D` (a staged deletion) or the old side of an `R` rename, using that **cached/staged** status — never an on-disk existence check as a proxy for "this path is deleted." `git rm --cached <path>` stages a deletion while leaving the file present in the working tree; an existence check alone would miss that case and the formatter/re-stage flow would silently turn the intended deletion back into a tracked, formatted file.
2. **Worktree-existence stage second**, applied only to what stage 1 didn't drop. A path staged as `A`/`M`/the new side of an `R` can still have no file on disk (e.g. removed from the working tree without staging that removal) — it's still present in the index and not a deletion by cached status, but the formatter has nothing to read, so drop it here rather than letting the tool fail on a missing path.

When the tool supports it, also pass its ignore-unknown mode (e.g., Prettier's `--ignore-unknown` / `-u`, or `--no-error-on-unmatched-pattern` for an unmatched pattern) for paths of an unsupported type, instead of hand-rolling an extension allowlist. If filtering leaves no paths for a given tool, skip that tool's invocation silently — there is nothing for it to check.

**Package-script and Makefile path-scoping are not automatic.** `npm run <script> -- <paths>` only narrows the run when the underlying command is itself written to accept trailing path arguments. Many `scripts.format` / `scripts.lint` entries hardcode a broad target already (`"format": "prettier --write ."`, `"lint": "eslint ."`); appending paths after an already-hardcoded `.` does not replace it, so the script still sweeps the whole repo despite the paths you passed. `make format` / `make lint` has the same gap for a different reason: Make has no trailing-path-argument convention — appended words after the target name are parsed as *additional targets*, not arguments to the `format` recipe, so a conventional `format: prettier --write .` target still sweeps the whole repo regardless of what you append. Before relying on either, read the actual command the script or recipe runs: only pass paths through when that command has no hardcoded target of its own (or is documented to accept path args). Otherwise, skip the package script / Make target and invoke the underlying CLI directly with the explicit path list instead, using the repo's already-installed binary — never `npx <tool>` or `npm exec <tool>`, which can silently fetch an unpinned latest version from the registry when the package isn't already installed, violating the "never install or invent a formatter" rule above. Prefer the project-local no-install path (`node_modules/.bin/prettier --write <path>...`, `node_modules/.bin/eslint <path>...`, or the equivalent for the ecosystem in play), or a version pinned by the repo's own lockfile/manifest. If no locally-installed binary is discoverable, skip this step silently rather than reaching for an unpinned fetch.

**Preserve partial staged selections when re-staging.** Before running the formatter, snapshot which of the paths already have a partial-staging split — `git diff --stat -- <path>` non-empty (unstaged changes exist) at the same time `git diff --cached --stat -- <path>` is also non-empty (staged changes exist) — captured from the state **before** the formatter runs, not after. A path with no pre-formatter unstaged diff is safe to blanket `git add <path>` once the formatter finishes, even though that now produces a worktree diff: the only worktree change is the formatter's own edit, so re-staging it is the intended "stage file, run formatter, re-stage its fix" flow. A path that already had a pre-formatter split means the user deliberately left some hunks unstaged; running a formatter over that file mixes its edits into the same worktree copy the user only partially wants staged, so stop and surface it to the user instead of silently re-staging the whole file.

## Exec-bit check

Run this **after** the format-before-push check above, not before: setting the exec bit any earlier would be silently undone once the format check's re-stage runs `git add` again. Running the exec-bit check last makes it the final mutation for the affected paths.

For every newly-added file (not previously tracked) whose first line is a shebang (`#!`), confirm both the worktree permission bits and the index recorded it as executable — not the index alone. `git update-index --chmod=+x` only overrides the index entry; it leaves the worktree file's actual mode untouched. A worktree/index mismatch causes three separate failure modes: `git status` reports a mode-only diff immediately after commit, a later `git add <path>` re-reads the still-`0644` worktree mode and reverts the index back to `100644`, and the pathspec-limited commit form below (`git commit -- <path>`, `--only` mode) records the **worktree** mode rather than the index — so an index-only fix still ships a non-executable blob. Set the worktree bit first, then the index, so both agree before either the plain or pathspec commit form runs:

```bash
for f in <newly-added paths>; do
  head -c 2 -- "$f" | grep -q '^#!' || continue
  git ls-files --stage -- "$f" | grep -q '^100755' && [ -x "$f" ] && continue
  chmod +x -- "$f"
  git update-index --chmod=+x -- "$f"
done
```

Scope this to files newly added in the current change set, not a full-repo sweep. Already-tracked files that were already executable, and files without a shebang, need no action.

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
