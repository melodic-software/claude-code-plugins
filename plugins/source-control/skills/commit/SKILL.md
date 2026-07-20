---
name: commit
description: "Create a git commit with a subject matching the resolved convention (layered `source-control.md` config → project convention → Conventional Commits default), a Claude Co-Authored-By trailer, and surgical staging (never `git add -A`), feeding the message to git via Bash heredoc. Use when: 'commit this', 'make a commit', 'commit with message <hint>' — not for push, branch creation, or PR creation (use /pull-request)."
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

1. **The layered `source-control.md` convention config** — user-global, tracked team, and gitignored personal overlay, merged per key by [reference/config-resolution.md](../../reference/config-resolution.md). Resolve all three layers before using any value; a value from one layer alone is not the effective config. When any layer declares one, the effective `subject_pattern` (and `type_list`, when Conventional-Commits-shaped) is authoritative. Before pre-checking, expand `subject_pattern`: the literal keyword `Conventional Commits` expands to the anchored pattern in step 3 below; anything else is already a single anchored regex and is used as-is.
2. **The consuming project's own `CLAUDE.md`, `AGENTS.md`, rules, or commit-msg hook** — if the effective merged config declares no `subject_pattern` (absent from every layer, which includes the case where layers exist but only contribute other keys) but the project declares (or enforces via lefthook, husky, commitlint, or a plain `.git/hooks/`) a different convention, follow that instead. (Existing behavior — unchanged.)
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

When the project enforces its convention with a commit-msg git hook (lefthook, husky, commitlint, plain `.git/hooks/`), that hook is the authoritative gate regardless of which rung above resolved the pattern; this skill's pre-check exists to fast-fail client-side before the hook round-trip. When no layer resolves a `subject_pattern` and nothing is inferable from the project's own files, point the user at `/source-control:setup` to persist a convention instead of re-inferring one every commit.

## Task

1. Survey working tree (`git status`, `git diff --cached --stat`) to confirm what's staged.
2. Stage the intended files, but first check each path against four pre-existing conditions — *before* this step touches anything:
   - **Already-staged deletion.** `git diff --cached --name-status -- <path>` reports `D` (e.g. from a prior `git rm --cached <path>`). A deletion staged this way can leave a file present in the worktree (untracked or otherwise), so `git diff --stat -- <path>` reads empty and would not flag it as a partial-staging split — but a blanket `git add <path>` would re-add the file and silently clear the intended deletion. Skip any path already staged as `D` entirely; never `git add` over it.
   - **Staged rename, old side.** `git diff --cached --name-status -- <path>` reports an `R<score> <old> <new>` entry whose `<old>` falls under `<path>` — including when `<path>` is a directory containing that old pathname. A staged rename can leave an untracked replacement file sitting at the old pathname; that replacement is invisible to `git diff --stat -- <path>` (untracked files are never reported by `git diff`), so it slips past both the deletion check above and the partial-staging-split check below. A blanket `git add <path>` (or `git add <dir>`) then stages that replacement as a new add, turning the intended rename into an add-plus-modify. Skip the old side of any staged `R` entry entirely; never `git add` over it.
   - **Untracked files under a directory path.** When `<path>` is a directory, neither `git diff --cached --name-status -- <path>` nor `git diff --stat -- <path>` reports untracked files sitting under it — `git diff` only ever compares tracked/staged content. A blanket `git add <path>` on a directory stages every untracked file underneath it too, sweeping in secrets, build artifacts, or other unrelated new files the user never approved. Before staging a directory path, check `git status --porcelain -- <path>` for `??` entries; if any exist, stop and surface them to the user instead of blanket-adding the directory — enumerate the specific intended files instead.
   - **Partial-staging split.** `git diff --cached --stat -- <path>` non-empty AND `git diff --stat -- <path>` also non-empty. A path already in that state has hunks the user deliberately left unstaged, so leave it as-is rather than running `git add <path>` over it — a blanket add would sweep those unstaged hunks in too.

   Run `git add <path>...` only for paths not already staged as `D`, not the old side of a staged `R`, not a directory path with untracked files under it, and not already in a partial-staging split.
3. Run the format-before-push check below against the files just staged for this commit (not the full staged set — see the pathspec note in that check), if a local formatter/linter is discoverable, re-staging any fixes.
4. Run the exec-bit check below on any newly-added file — **after** step 3, not before: a formatter re-stage in step 3 reads the worktree file mode, so setting the exec bit any earlier would be silently undone by that later `git add`.
5. Draft a subject + optional body, scoped to the staged diff, shaped to satisfy the active subject convention (default: the Conventional Commits pattern above).
6. Pre-check the subject against the pattern (fast-fail before invoking git).
7. Invoke `git commit -F -` via the Bash tool, heredoc-piped, adding `--trailer` for `Co-Authored-By` per the trailer template below only when the resolved `trailer_policy` calls for one (default: yes; skip or substitute per an explicit resolved `trailer_policy` of `none` or a different trailer).
8. Surface the resulting commit SHA + subject to the user.

## Canonical bash form

Use the **Bash tool**, not the PowerShell tool. Bash heredoc is the canonical form across all platforms (Git Bash, Linux, macOS).

```bash
# --trailer line below applies only when the resolved trailer_policy calls for one
# (default: yes). trailer_policy "none" -> drop the --trailer line entirely.
# trailer_policy naming a different template -> substitute that template's text.
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

There is no environment variable that auto-fills these — the trailer is part of the message body sent to `git commit`, not git config. Hardcoding stale values is worse than asking; the trailer becomes a git-history claim about which model / context authored the change. If any config layer declares a `trailer_policy`, follow the resolved value exactly: a policy of `none` means omit `--trailer` from the `git commit` invocation entirely (do not append an empty or default trailer), and a policy naming a different template means substitute that template in place of the one above. Otherwise, if the consuming project's conventions specify a different attribution trailer (or none), follow those instead of the default.

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

For every newly-added file (not previously tracked) whose first line is a shebang (`#!`), confirm both the worktree permission bits and the index recorded it as executable — not the index alone. `git update-index --chmod=+x` only overrides the index entry; it leaves the worktree file's actual mode untouched. A worktree/index mismatch causes three separate failure modes: `git status` reports a mode-only diff immediately after commit, a later `git add <path>` re-reads the still-`0644` worktree mode and reverts the index back to `100644`, and the pathspec-limited commit form below (`git commit -- <path>`, `--only` mode) records the **worktree** mode rather than the index — so an index-only fix still ships a non-executable blob. Set the worktree bit first, then the index, so both agree before either the plain or pathspec commit form runs.

**Skip symlinks first.** Check the staged mode via `git ls-files --stage -- <path>` before probing for a shebang at all. A symlink is staged as mode `120000`, not `100644`/`100755`; git tracks the symlink's own mode, not the target's, so exec-bit semantics don't apply to it. Following the link to read or `chmod` the target would operate on a file that may sit outside the repo entirely, and `git update-index --chmod=+x` fails outright on a `120000` entry. Only proceed to the shebang probe for paths staged as `100644` or `100755`:

```bash
for f in <newly-added paths>; do
  mode=$(git ls-files --stage -- "$f" | cut -d' ' -f1)
  case "$mode" in 100644|100755) ;; *) continue ;; esac  # skip symlinks (120000) and other non-regular modes
  head -c 2 -- "$f" | grep -q '^#!' || continue
  [ "$mode" = "100755" ] && [ -x "$f" ] && continue
  chmod +x -- "$f"
  git update-index --chmod=+x -- "$f"
done
```

Scope this to files newly added in the current change set, not a full-repo sweep. Already-tracked files that were already executable, files without a shebang, and symlinks need no action.

## Pathspec-limited commits (dirty shared index)

When the index already holds staged files OUTSIDE this commit's scope — concurrent Claude Code sessions on the same branch, pre-existing mixed WIP — a bare `git commit` would sweep them all in. Instead, limit the commit by pathspec:

```bash
# Same trailer_policy conditionality as the canonical form above: drop --trailer
# entirely when trailer_policy is "none"; substitute a named alternate template.
git commit -F - --cleanup=verbatim \
  --trailer "<Co-Authored-By trailer>" \
  -- <path> [<path>...] <<'EOF'
<subject>

<body>
EOF
```

Semantics (per `git-commit(1)` default `--only` mode): the commit records the **working-tree content** of the named paths, disregarding what is staged for all OTHER paths — concurrent-session staged work stays staged, untouched. A path with no `HEAD` entry that was never `git add`ed still errors out (`pathspec '<path>' did not match any file(s) known to git`) — pathspec alone never picks up a genuinely untracked file.

**A path staged as a deletion is a different case, and it fails silently instead of erroring.** `git rm --cached <path>` (the "Already-staged deletion" case in step 2) removes the path from the index but leaves it on disk, so `git status` shows it as both `D` (cached) and `??` (untracked) at once. Because the path still has a `HEAD` entry, `--only` mode *does* match it — but it reads the **working-tree content**, not the cached `D` status, finds the file still present, and re-adds it unchanged. The staged deletion is silently discarded instead of being committed alongside the commit's other paths. Verified empirically: with the file still on disk, `git commit -- <D-status path> <other paths>` commits that path unchanged (the deletion never happens); with the file absent from disk too (a plain `git rm <path>`, or `git rm --cached` followed by an on-disk `rm`), the same command correctly records the deletion — `--only` mode's worktree read only produces the right answer when the worktree already matches the deletion.

**Safety preconditions — all required before offering this path:**

- Every named path is fully this commit's work — no overlap with another session's in-flight scope (when unsure which session owns a file, ask).
- For each named path, working tree == intended content (pathspec commits the worktree version, silently superseding any different staged version of that same path) — **except** a path staged as `D` whose file is still on disk, which needs the hide/commit/restore sequence below instead of satisfying this precondition directly.
- Verify scope with `git diff --cached --stat -- <pathspec>` and surface that stat in the review gate — the user greenlights exactly what the pathspec captures.
- A directory pathspec (`-- path/to/dir/`) is acceptable only after confirming via `git status --porcelain -- <dir>` that nothing under it belongs to another scope; otherwise enumerate files.

### Preserving a staged deletion in a pathspec commit

For every named path whose `git diff --cached --name-status -- <path>` reports `D`, **or the old side of an `R` rename** (`R<score> <old> <new>` — the `<old>` field), check whether that path is still present on disk (the `git rm --cached` case above, or a rename whose old pathname was recreated — verified empirically: `git commit -- dir/` after `git mv dir/old dir/new` with an ignored `dir/old` present records `M dir/old` plus `A dir/new`, losing the rename's deletion half); expand any directory pathspec to its member files first — via `git diff --cached --name-status -- <dir>`, not the `--name-only` expansion the format-before-push check uses: `--name-only` reports only a rename's new side (`dir/new`), never the old side (`R100 dir/old dir/new` only appears in `--name-status` output), so a `--name-only` expansion here would silently drop every rename old-side before this loop ever sees it. If a path is still present, the default `--only` read would silently drop the deletion per Semantics. Check disk presence directly — an ignored old-side replacement never shows up in `git status --porcelain`, so the directory-scope check in Safety preconditions above cannot catch it. Root cause is that `--only` mode has no flag to commit a path's cached state instead of its worktree state, so the fix is to make the worktree briefly match the already-staged deletion (D) or rename (R old-side) — not to delete the file outright, since `git rm --cached` means the user wants to stop tracking it while keeping the local copy, and a rename's old side simply shouldn't exist there once the commit lands.

Arm the restore trap **before** the hide loop runs, not after — a later path's hide-target collision must still restore an earlier path's already-hidden file, so `hidden` and the trap have to be live from the first iteration. Every probe of a hide path uses `-e ... -o -L ...`, not `-e` alone: if the hidden original was a symlink whose target is missing, `-e` on the moved `.__commit_hide__` path is false (it only follows the link and checks the target), so an `-e`-only test would leave that dangling symlink un-restored on exit and would miss it as a pre-existing collision too. The pre-hide collision check also queries the index (`git ls-files --error-unmatch`), not just the disk: a hide path that is a tracked file currently absent from disk or staged for deletion passes a disk-only check, and the `mv` would then land the hidden original on a still-tracked pathname that the same pathspec commit silently records as a modification.

Build the candidate list with `-z` (NUL-delimited), not plain `--name-status`: a bare newline-split read is unsafe for paths containing spaces or newlines, and a rename's status field carries a variable similarity score (`R087`, `R100`, ...), so match the `R` prefix rather than a literal `R100`.

```bash
hidden=()
restore_hidden() {
  for f in "${hidden[@]}"; do
    [ -e "$f.__commit_hide__" -o -L "$f.__commit_hide__" ] && mv -- "$f.__commit_hide__" "$f"
  done
}
trap restore_hidden EXIT

hide_candidates=()
while IFS= read -r -d '' status; do
  case "$status" in
    D)
      IFS= read -r -d '' path
      hide_candidates+=("$path")
      ;;
    R*)
      IFS= read -r -d '' old
      IFS= read -r -d '' _new  # new side isn't this loop's concern, just consume it
      hide_candidates+=("$old")
      ;;
    *)
      IFS= read -r -d '' _path  # A/M/etc. — consume and discard
      ;;
  esac
done < <(git diff --cached --name-status -z -- <path>)

for f in "${hide_candidates[@]}"; do
  [ -e "$f" -o -L "$f" ] || continue  # only disk-present candidates need hiding
  hide="$f.__commit_hide__"
  if [ -e "$hide" -o -L "$hide" ] || git ls-files --error-unmatch -- "$hide" >/dev/null 2>&1; then
    echo "refusing to hide $f: $hide already exists" >&2
    exit 1
  fi
  mv -- "$f" "$hide"
  hidden+=("$f")
done

# Same trailer_policy conditionality as the canonical form above: drop --trailer
# entirely when trailer_policy is "none"; substitute a named alternate template.
git commit -F - --cleanup=verbatim \
  --trailer "<Co-Authored-By trailer>" \
  -- <path> [<path>...] <<'EOF'
<subject>

<body>
EOF
```

The `trap ... EXIT` restores the file on every exit path — commit success, a rejecting commit-msg hook, or any other error — so the hide never outlives this one commit invocation. Verified empirically against a rejecting commit-msg hook: the trap still restores the file and the `D` stays staged for a retry. If a `<path>.__commit_hide__` collision is detected before hiding starts, stop and surface it instead of overwriting an unrelated file — do not guess which one the user meant.

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
