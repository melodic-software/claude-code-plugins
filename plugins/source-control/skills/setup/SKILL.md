---
name: setup
description: "Configure the source-control plugin. check (read-only): report the effective commit-subject / PR-title convention (tracked .claude/source-control.md) and the babysit-prs userConfig surface (effective config, branch-protection posture, Windows long paths). apply: interview the repo and write the convention config, and walk the sanctioned babysit reconfigure paths. Use when: 'set up source-control', 'configure commit convention', 'source-control setup', 'what commit format does this repo use', 'configure babysit', 'check babysit config', or /commit, /pull-request, or /babysit-prs report missing configuration. Actions: check (read-only verification, default) | apply (write the convention config; document the babysit config paths). Re-runnable and safe."
argument-hint: "check | apply [subject_pattern=<anchored-regex | 'Conventional Commits'>]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Inspect and configure the source-control plugin per the uniform setup contract: `check` reports the
effective configuration, `apply` writes it. Two configuration surfaces:

1. The tracked commit-subject / PR-title convention at
   `${CLAUDE_PROJECT_DIR}/.claude/source-control.md`, resolved first by `/source-control:commit` and
   `/source-control:pull-request` before they fall back to inference or the bundled Conventional
   Commits default. Conventional Commits is genuinely optional — some orgs gate on ticket-prefixed
   subjects (`WEB-123: description`) — so the plugin ships a sensible default, not a hardcoded
   requirement.
2. The `/source-control:babysit-prs` native `userConfig` surface (not a tracked repo file).

Idempotent: re-running reads the existing configuration and offers updates rather than overwriting
blind. The plugin ships a working zero-config default (Conventional Commits / inference for the
convention; the safe babysit tier over your own PRs), so an unconfigured surface is **INFO**, never
FAIL.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
remediation. When `apply` carries a `subject_pattern=` argument it writes the convention
non-interactively; with no arguments in an interactive session it runs the convention interview
below.

## `check` (read-only)

Report a PASS/FAIL/INFO table across both surfaces; modify nothing.

### Convention config

Anchor at the repo root: resolve `REPO_ROOT` once — `${CLAUDE_PROJECT_DIR}` when set, otherwise
`git rev-parse --show-toplevel` — and use that literal resolved path for every read below, never a
cwd-relative path (invoked from a nested directory, a cwd-relative path would inspect the wrong
`.claude/source-control.md`). Re-resolve `REPO_ROOT` at the top of every self-contained Bash call —
a fresh shell does not carry a prior call's variables.

- **Present** (`REPO_ROOT/.claude/source-control.md` exists): load it and report the effective
  convention (`subject_pattern`, `type_list` if present, `pr_title_pattern`, `trailer_policy` if
  present). **FAIL** when `subject_pattern` is not machine-checkable — it must be either the literal
  keyword `Conventional Commits` or an anchored regex (`^…`-style); a plain-language description
  cannot be evaluated by `/commit` or `/pull-request`. **FAIL** when the file is excluded by
  `.gitignore` (teammates would never receive the shared convention) — report the matching rule.
  Otherwise PASS.
- **Absent**: INFO — no tracked convention; `/commit` and `/pull-request` infer from the repo's own
  `CLAUDE.md`/rules/commit-msg hook, then fall back to the bundled Conventional Commits default. The
  remediation is `apply` to persist a convention.

### Babysit config

1. **Effective configuration.** Report every babysit `userConfig` key with its resolved value or its
   inference when unset. The authoritative render is the effective-configuration block that loads
   with `/source-control:babysit-prs` (its `help` mode prints it without taking any other action); a
   surviving literal `${user_config.…}` placeholder there means the key is unset. For each unset key
   state what will be inferred at run time — `babysit_watched_owners` → the current repo's owner,
   `babysit_self_logins` → none (your `gh api user --jq .login` login is always used, extras only add
   to it), `babysit_default_tier` → `safe`, `babysit_merge_method` → repo convention then squash, the
   review-trigger keys → module dormant, `babysit_worktree_root` → the plugin data dir's
   `worktrees/` subdirectory. Unset keys are INFO (documented defaults), not FAIL.
2. **Branch-protection posture across watched repos.** For each watched owner (or the current repo's
   owner when `babysit_watched_owners` is unset), enumerate the repos babysit would touch — repos
   with open PRs authored by the self logins, via
   `gh search prs --state open --author @me --owner <owner> --json repository` — and for each, read
   the default branch's effective rules (`gh api repos/<owner>/<repo>/rules/branches/<default-branch>`,
   falling back to `gh api repos/<owner>/<repo>/branches/<default-branch>/protection` for classic
   protection). Flag every repo reporting zero required reviews AND zero required status contexts as
   **unprotected**: the merge gate refuses gate-proven merges there for non-self authors
   (`--allow-unprotected` is the deliberate override), so an unprotected repo in an autopilot fleet
   deserves a protection rule, not an override.
3. **Windows long-path support for the worktree root.** On Windows, worktrees under the (possibly
   deep) worktree root can exceed 260 characters. Probe `git config --get core.longpaths` and the OS
   policy (registry value `LongPathsEnabled` under
   `HKLM\SYSTEM\CurrentControlSet\Control\FileSystem`); report each as enabled/disabled with the
   remediation (`git config --global core.longpaths true`; the OS value needs an elevated change, so
   report it — never attempt it). Skip this probe silently on non-Windows.

## `apply` (idempotent)

Run `check` first. Then write the convention (surface 1) and walk the sanctioned babysit
reconfigure paths (surface 2).

### Convention config

When the invocation carries a `subject_pattern=` argument, write non-interactively: use it as
`subject_pattern` (the literal `Conventional Commits` keyword, which resolves to the bundled 11-type
anchored pattern and enables `type_list`, or an anchored regex), set `pr_title_pattern` to the same,
and omit `trailer_policy`. Reject a `subject_pattern` that is not machine-checkable (a plain-language
value) with the same message `check` gives, rather than persisting it. With no argument in an
interactive session, run the interview:

0. **Anchor at the repo root** exactly as `check` does — resolve `REPO_ROOT` once and reuse the
   literal resolved path for every read, write, and git command below; re-resolve it at the top of
   every self-contained Bash call.
1. **Read the current config first.** If `REPO_ROOT/.claude/source-control.md` exists, present its
   summary; the interview proposes changes against that baseline and overwrites nothing without
   confirmation.
2. **Infer before asking.** With no config file, look for an existing declared or enforced
   convention, surfacing which signal produced the candidate:
   - The repo's own `CLAUDE.md`, `AGENTS.md`, or `.claude/rules` — prose stating a commit-message or
     PR-title convention.
   - A commit-msg git hook — `lefthook.yml` (`commit-msg` entry), `.husky/commit-msg`,
     `commitlint.config.*` / `.commitlintrc*` (and whether it extends
     `@commitlint/config-conventional` or declares custom rules), or a plain Git-managed `commit-msg`
     hook. Resolve the hooks directory with `git rev-parse --git-path hooks` rather than assuming
     `.git/hooks` — in a linked worktree `.git` is a file, not a directory, and the hooks directory
     (or a `core.hooksPath` override) can live elsewhere.
   - Recent history — `git log --format=%s -50` (subjects only, no abbreviated commit hash —
     `git log --oneline` prefixes every subject with one and will break anchored matching) for a
     stable, repeating subject shape (e.g. every subject matches `^[A-Z]+-\d+: .+`, or every subject
     is already Conventional-Commits-shaped).
   Present the inferred candidate as the recommendation, naming its source. If nothing is inferable,
   say so plainly and move to the interview with the bundled default as the recommendation.
3. **Interview, one decision at a time, recommendation first.** Ask: "What commit-subject / PR-title
   convention does this repo use?"
   - **RECOMMENDED: Conventional Commits**, 11-type vocabulary —
     `build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test` — confirmed via the
     Conventional Commits spec, the Angular convention, commitlint's `@commitlint/config-conventional`
     source, and `amannn/action-semantic-pull-request`'s default `types` list. All four agree on this
     exact set; `security` is **not** a Conventional Commits type in any of them — never offer or
     accept it as a bundled type.
   - **Alternative: a custom pattern** — e.g. a ticket-prefix regex like `^[A-Z]+-\d+: .+` for orgs
     that don't use Conventional Commits at all. If step 2 inferred a custom pattern, present it as
     the recommendation instead.
   Let the user accept, edit, or supply something else. Do not invent a convention the repo gives no
   signal for and the user doesn't state.
   - **`subject_pattern` must always end up machine-checkable**: either the literal keyword
     `Conventional Commits`, or a single anchored regex (`^…$`-style, anchored at the start at
     minimum) that `/commit` and `/pull-request` can evaluate directly. If the user describes their
     convention in prose, translate it into an anchored regex yourself and confirm the translation
     before persisting — never write the prose. If a convention genuinely cannot be expressed as one
     regex, ask the user to restate it as an anchored regex (or a short any-of list), or fall back to
     the Conventional Commits default; do not persist a free-text `subject_pattern`.
4. **Settle the remaining fields**, recommendation first:
   - **`pr_title_pattern`** — usually identical to `subject_pattern` (squash-merge repos set the PR
     title as the squash commit's subject). Ask only if the user wants them to differ; otherwise
     record "same as `subject_pattern`".
   - **`trailer_policy`** (optional) — whether commits should carry a `Co-Authored-By:` (or other)
     attribution trailer, and its exact template. Recommend keeping `/commit`'s default unless the
     user states otherwise. Omit this section entirely if the repo has no trailer convention.
5. **Write the config.** Materialize `REPO_ROOT/.claude/source-control.md` with these sections:

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

   Drop any section with no content rather than leaving it empty. Then verify the file is actually
   staged before reporting success — neither `git check-ignore -v` nor `git ls-files --error-unmatch`
   proves this alone. `git check-ignore -v` only reports a matching `.gitignore` pattern, staying
   silent for both a properly tracked file and a plain untracked one. `git ls-files --error-unmatch`
   only proves the path is *somewhere* in the index: on a reconfiguration run (the file already
   existed and this step just rewrote it), the path was already tracked, so that check exits 0 even
   though the new content is still an unstaged working-tree modification.

   Run these as one Bash tool call so `REPO_ROOT` only needs resolving once for the whole sequence:

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
   `.claude/source-control.md` is no longer excluded, or choose a different tracked location, then
   re-run this step.

   This skill stages but does not commit — `git status --porcelain` legitimately keeps printing an
   index (`X`) column of `A` or `M` with a blank worktree column for a staged-but-uncommitted file,
   so success does **not** require porcelain to be fully empty, only that no *unstaged* changes
   remain. Prompt the user to commit, since this file is team-shared and must be committed to take
   effect. Only report success once both checks pass: not ignored, and no unstaged changes remain.

### Babysit config

`/source-control:babysit-prs` is configured through the plugin's native `userConfig`, which Claude
Code owns (`pluginConfigs`) — this skill never hand-edits it. It documents and walks the two
sanctioned paths:

- **Interactive:** `/plugin configure source-control` (or the `/plugin` dialog → source-control →
  configure), any time — Claude Code prompts per key using the manifest's types and defaults.
- **Headless / CI:** `--config` only applies on a fresh install (ignored once installed), so
  reconfiguring headless means `claude plugin uninstall source-control` then reinstalling with the
  new values: `claude plugin install source-control@<marketplace> --config KEY=VALUE` (repeatable per
  key). Multi-value keys (`babysit_watched_owners`, `babysit_self_logins`, `babysit_review_bot_logins`,
  `babysit_extra_bot_logins`) are supplied comma-joined.

Reconfiguring `userConfig` does not reach the already-running session — after either path, the new
values become visible only in a fresh session. Do not re-run the babysit `check` in the same session
expecting the change and report a false failure; instead report "reconfigured; verify with `check` in
a fresh session".

## Output

A tracked `.claude/source-control.md` in the consuming repo (when `apply` wrote the convention), plus
a one-paragraph summary of the convention and which source it came from (inferred or user-declared),
and — for babysit — the `check` probe report and the reconfigure path used. `check` alone reports the
effective configuration across both surfaces and changes nothing.

## What this skill does NOT do

- Make a commit or open a PR — that's `/source-control:commit` and `/source-control:pull-request`.
- Enforce the convention at commit time — a project's own `commit-msg` hook (when one exists) remains
  the authoritative gate; this config only tells the plugin's skills what shape to draft and
  pre-check against.
- Write machine-local state, the plugin cache, Claude Code user settings, or `pluginConfigs` — the
  convention lives in the consumer's tracked `.claude/source-control.md`; babysit settings live in
  Claude-Code-owned `userConfig`, reconfigured only through the two paths above.
