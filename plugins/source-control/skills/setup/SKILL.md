---
name: setup
description: "Configure the source-control plugin's commit-subject / PR-title convention for this repository: interview the user, infer from the repo's own CLAUDE.md/rules/commit-msg hook/git log first, and write the tracked .claude/source-control.md config. Use when: 'set up source-control', 'configure commit convention', 'source-control setup', 'what commit format does this repo use', or /commit or /pull-request report no declared convention. Re-runnable — safe to invoke again to reconfigure."
argument-hint: "(no arguments — interactive interview)"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Write (or update) the consuming repo's tracked commit-subject / PR-title convention at
`${CLAUDE_PROJECT_DIR}/.claude/source-control.md` so `/source-control:commit` and
`/source-control:pull-request` resolve it deterministically instead of falling back to Conventional
Commits by default every run. Conventional Commits is genuinely optional — some orgs gate on
ticket-prefixed subjects (`WEB-123: description`) instead — so the plugin ships a sensible default, not
a hardcoded requirement. Idempotent: re-running reads the existing config and offers updates rather than
overwriting blind.

## Task

Apply the convention-resolution ladder — config present → use it and offer updates; absent → infer
from the repo and persist what the user accepts; cannot infer → ask and offer to persist; else the
safe default (Conventional Commits).

0. **Anchor at the repo root before any read, write, or git command below.** Resolve it once: use
   `${CLAUDE_PROJECT_DIR}` when set, otherwise run `git rev-parse --show-toplevel` and take its output.
   Call the result `REPO_ROOT` and reuse that literal resolved path — never the bare
   `${CLAUDE_PROJECT_DIR}` reference — for every path below, never a path relative to the current
   working directory. A Read/Write tool call needs a literal path, not a shell variable, and a separate
   Bash tool call starts a fresh shell with none of a prior call's variables, so re-resolve (or re-inline
   the same `${CLAUDE_PROJECT_DIR}` fallback) `REPO_ROOT` at the top of every self-contained Bash
   invocation in this skill run rather than assuming it persists across tool calls. Invoked from a nested
   directory, a cwd-relative path would read and write the wrong `.claude/source-control.md`, and a
   later `/commit` or `/pull-request` run from the repo root would miss the persisted convention.
1. **Read the current config first.** If `REPO_ROOT/.claude/source-control.md` exists, load
   it and present a short summary (`subject_pattern`, `type_list` if present, `pr_title_pattern`,
   `trailer_policy` if present). The interview proposes changes against that baseline; nothing is
   overwritten without the user confirming.
2. **Infer before asking.** With no config file, look for an existing declared or enforced convention,
   in this order, and surface which signal produced the candidate:
   - The repo's own `CLAUDE.md`, `AGENTS.md`, or `.claude/rules` — prose stating a commit-message or
     PR-title convention.
   - A commit-msg git hook — `lefthook.yml` (`commit-msg` entry), `.husky/commit-msg`,
     `commitlint.config.*` / `.commitlintrc*` (and whether it extends
     `@commitlint/config-conventional` or declares custom rules), or a plain Git-managed
     `commit-msg` hook. Resolve the hooks directory with `git rev-parse --git-path hooks`
     rather than assuming `.git/hooks` — in a linked worktree `.git` is a file, not a
     directory, and the hooks directory (or a `core.hooksPath` override) can live elsewhere;
     `git rev-parse --git-path hooks` resolves it correctly in both cases.
   - Recent history — `git log --format=%s -50` (or more; subjects only, no abbreviated commit hash —
     `git log --oneline` prefixes every subject with one and will break anchored matching) for a
     stable, repeating subject shape (e.g. every subject matches `^[A-Z]+-\d+: .+`, or every subject is
     already Conventional-Commits-shaped).
   Present the inferred candidate as the recommendation, naming the source it came from. If nothing is
   inferable, say so plainly and move to the interview with the bundled default as the recommendation.
3. **Interview, one decision at a time, recommendation first.** Ask: "What commit-subject / PR-title
   convention does this repo use?"
   - **RECOMMENDED: Conventional Commits**, 11-type vocabulary —
     `build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test` — confirmed via the
     Conventional Commits spec, the Angular convention, commitlint's `@commitlint/config-conventional`
     source, and `amannn/action-semantic-pull-request`'s default `types` list. All four agree on this
     exact set; `security` is **not** a Conventional Commits type in any of them — never offer or accept
     it as a bundled type.
   - **Alternative: a custom pattern** — e.g. a ticket-prefix regex like `^[A-Z]+-\d+: .+` for orgs that
     don't use Conventional Commits at all. If step 2 inferred a custom pattern, present it as the
     recommendation instead of Conventional Commits.
   Let the user accept the recommendation, edit it, or supply something else entirely. Do not invent a
   convention the repo gives no signal for and the user doesn't state.
   - **`subject_pattern` must always end up machine-checkable**: either the literal keyword
     `Conventional Commits` (which resolves to the bundled 11-type anchored pattern and enables
     `type_list`), or a single anchored regex (`^...$`-style, anchored at the start at minimum) that
     `/commit` and `/pull-request` can evaluate directly. If the user describes their convention in
     prose (e.g. "ticket number then a colon then a summary"), translate it into an anchored regex
     yourself and confirm the translation with the user before persisting — never write the prose
     description itself. If a convention genuinely cannot be expressed as one regex, ask the user to
     restate it as an anchored regex (or a short list of anchored regexes, any-of), or fall back to the
     Conventional Commits default; do not persist a free-text/plain-language `subject_pattern`.
4. **Settle the remaining fields**, recommendation first:
   - **`pr_title_pattern`** — usually identical to `subject_pattern` (squash-merge repos set the PR
     title as the squash commit's subject, so the same gate applies to both). Ask only if the user
     wants the two to differ; otherwise record "same as `subject_pattern`".
   - **`trailer_policy`** (optional) — whether commits should carry a `Co-Authored-By:` (or other)
     attribution trailer, and its exact template. Recommend keeping `/commit`'s default
     (`Co-Authored-By: Claude <model> (<context>) <noreply@anthropic.com>`) unless the user states
     otherwise. Omit this section entirely if the repo has no trailer convention.
5. **Write the config.** Materialize `REPO_ROOT/.claude/source-control.md` with these
   sections:

   ```markdown
   # source-control configuration

   Tracked commit-subject / PR-title convention for the source-control plugin. `/source-control:commit`
   and `/source-control:pull-request` resolve this file first, before inferring from the repo's own
   CLAUDE.md/rules/commit-msg hook or falling back to the bundled Conventional Commits default.
   Re-run `/source-control:setup` to change these values.

   ## subject_pattern

   <the literal keyword `Conventional Commits`, or a single anchored regex (or an any-of list of
   anchored regexes) — always machine-checkable, never a plain-language description>

   ## type_list

   <only present when subject_pattern is Conventional-Commits-shaped — omit this section entirely for
   a custom pattern with no type vocabulary>

   ## pr_title_pattern

   <the pattern, or "Same as `subject_pattern`.">

   ## trailer_policy

   <only present if the repo has a trailer convention>
   ```

   Drop any section with no content (`type_list` for a non-Conventional-Commits pattern;
   `trailer_policy` when there is no trailer convention) rather than leaving it empty. Then verify the
   file is actually staged before reporting success — neither `git check-ignore -v` nor
   `git ls-files --error-unmatch` prove this by itself. `git check-ignore -v` only reports a matching
   `.gitignore` pattern, staying silent for both a properly tracked file and a plain untracked one.
   `git ls-files --error-unmatch` only proves the path is *somewhere* in the index: on a
   reconfiguration run (the file already existed and this step just rewrote it), the path was already
   tracked before the rewrite, so that check exits 0 even though the new content is still an unstaged
   working-tree modification — success would be reported while the updated convention stays local and
   uncommitted.

   Run these as one Bash tool call so `REPO_ROOT` only needs resolving once for the whole sequence (per
   step 0 — a later, separate Bash call would start a fresh shell and must re-resolve it):

   ```bash
   REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"
   # `git check-ignore -v` exits 0 (and prints the matching rule) only when a .gitignore pattern
   # excludes the file; it exits non-zero with no output otherwise. Branch on the exit code — do
   # NOT fall through to add/diff on a match: `git add` would silently refuse the ignored path, and
   # `git diff --quiet` on an ignored untracked file exits 0 trivially, so the sequence would report
   # false success with nothing actually staged for teammates.
   if IGNORE_MATCH="$(git check-ignore -v "$REPO_ROOT/.claude/source-control.md")"; then
     echo "STOP: .claude/source-control.md is excluded by .gitignore: $IGNORE_MATCH"
     exit 1
   fi
   # With no ignore match, read the two-character XY status: `??` (untracked) or a non-blank
   # worktree (Y) column — a letter such as `M` in the second position, as in `XM`, `MM`, etc. —
   # means the just-written content is not yet staged.
   git -C "$REPO_ROOT" status --porcelain -- .claude/source-control.md
   # If unstaged (per the check above), stage it. This covers both the fresh-file case and the
   # reconfiguration case (an already-tracked file whose rewritten content hadn't been staged yet),
   # unlike an index-presence check alone.
   git -C "$REPO_ROOT" add .claude/source-control.md
   # Confirm nothing is left unstaged (exit 0 = worktree matches the index).
   git -C "$REPO_ROOT" diff --quiet -- .claude/source-control.md
   ```

   If the guard stops the sequence (non-zero exit, `IGNORE_MATCH` reported), do not report success:
   tell the user the matching `.gitignore` pattern and ask them to either fix `.gitignore` so
   `.claude/source-control.md` is no longer excluded, or choose a different tracked location for the
   shared config, then re-run this step.

   This skill stages but does not commit — `git status --porcelain` legitimately keeps printing an
   index (`X`) column of `A` or `M` with a blank worktree column for a staged-but-uncommitted file, so
   success does **not** require porcelain to be fully empty, only that no *unstaged* changes remain.
   Prompt the user to commit, since this file is team-shared and must be committed to take effect. Only
   report success once both checks pass: not ignored, and no unstaged changes remain for the path.

## Output

A tracked `.claude/source-control.md` in the consuming repo, plus a one-paragraph summary of the
convention written (and which source it came from — inferred, or user-declared) and how to re-run this
setup to reconfigure.

## What this skill does NOT do

- Make a commit or open a PR — that's `/source-control:commit` and `/source-control:pull-request`.
- Enforce the convention at commit time — a project's own `commit-msg` hook (when one exists) remains
  the authoritative gate; this config only tells the plugin's skills what shape to draft and pre-check
  against.
- Write machine-local state — configuration lives in the consumer's tracked `.claude/source-control.md`,
  never in the plugin directory or a plugin data directory.
