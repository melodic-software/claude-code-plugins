---
name: setup
description: "Configure the source-control plugin. check (read-only): report the effective commit-subject / PR-title convention merged across its user-global, team, and personal-overlay layers, and the babysit-prs userConfig surface (effective config, branch-protection posture, Windows long paths). apply: interview the repo and write the convention config to a chosen layer, and walk the sanctioned babysit reconfigure paths. Use when: 'set up source-control', 'configure commit convention', 'source-control setup', 'what commit format does this repo use', 'set my personal commit convention', 'override the team convention locally', 'configure babysit', 'check babysit config', or /commit, /pull-request, or /babysit-prs report missing configuration. Actions: check (read-only verification, default) | apply (write the convention config; document the babysit config paths). Re-runnable and safe."
argument-hint: "check | apply [layer=user|team|local] [subject_pattern=<anchored-regex | 'Conventional Commits'>]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Inspect and configure the source-control plugin per the uniform setup contract: `check` reports the
effective configuration, `apply` writes it. Two configuration surfaces:

1. The commit-subject / PR-title convention config, layered across a user-global file, the tracked
   team file, and a gitignored personal overlay and merged per key by
   [../../reference/config-resolution.md](../../reference/config-resolution.md) — resolved first by
   `/source-control:commit` and `/source-control:pull-request` before they fall back to inference or
   the bundled Conventional Commits default. Conventional Commits is genuinely optional — some orgs
   gate on ticket-prefixed subjects (`WEB-123: description`) — so the plugin ships a sensible
   default, not a hardcoded requirement.
2. The `/source-control:babysit-prs` native `userConfig` surface (not a tracked repo file).

Idempotent: re-running reads the existing configuration and offers updates rather than overwriting
blind. The plugin ships a working zero-config default (Conventional Commits / inference for the
convention; the safe babysit tier over your own PRs), so an unconfigured surface is **INFO**, never
FAIL.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
remediation. When `apply` carries a `subject_pattern=` argument it writes the convention
non-interactively; with no arguments in an interactive session it runs the convention interview
below. `layer=` selects which config layer `apply` writes, defaulting to the tracked team file.

## `check` (read-only)

Report a PASS/FAIL/INFO table across both surfaces; modify nothing.

### Convention config

Anchor at the repo root: resolve `REPO_ROOT` once — `${CLAUDE_PROJECT_DIR}` when set, otherwise
`git rev-parse --show-toplevel` — and use that literal resolved path for every repo-relative read
below, never a cwd-relative path (invoked from a nested directory, a cwd-relative path would inspect
the wrong file). Re-resolve `REPO_ROOT` at the top of every self-contained Bash call — a fresh shell
does not carry a prior call's variables.

Read all three layers, then report **one effective-configuration table** — a row per key, its
resolved value, and which layer supplied it — followed by a per-layer presence line. Never present a
single layer's value as the effective convention; a reader who cannot see which layer won cannot
tell why `/commit` behaves as it does.

```text
key                 value                       won by
subject_pattern     ^[A-Z]+-\d+: .+             team
pr_title_pattern    Same as subject_pattern      team
trailer_policy      none                         local overlay
pr_body_attribution none                         local overlay
```

Per-layer verdicts:

- **User-global** (`~/.claude/source-control.md`): present → report which keys it contributes;
  absent → INFO. It is outside the repo, so no git check applies to it.
- **Team** (`REPO_ROOT/.claude/source-control.md`): present → PASS. **FAIL** when excluded by
  `.gitignore` — teammates would never receive the shared convention; report the matching rule.
  Absent → INFO, remediable by `apply`.
- **Local overlay** (`REPO_ROOT/.claude/source-control.local.md`): PASS only when an ignore rule
  matches it **and** it is not in the index. Two distinct failures hide behind one symptom and need
  different remediations, so probe them separately — see the two-probe form under `apply`. Absent →
  INFO, which is the common case.

**FAIL** when the *effective* `subject_pattern` is not machine-checkable — it must be either the
literal keyword `Conventional Commits` or an anchored regex (`^…`-style); a plain-language
description cannot be evaluated by `/commit` or `/pull-request`. Name the layer that supplied the
offending value.

With **all three layers absent**: INFO — no declared convention; `/commit` and `/pull-request` infer
from the repo's own `CLAUDE.md`/rules/commit-msg hook, then fall back to the bundled Conventional
Commits default. The remediation is `apply` to persist a convention.

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

**Pick the target layer first.** `layer=` selects it; `team` is the default when the argument is
absent, since a convention is a team artifact until someone says otherwise.

| `layer=` | Target path | For |
|---|---|---|
| `user` | `~/.claude/source-control.md` | the operator's own preference across every repo |
| `team` (default) | `REPO_ROOT/.claude/source-control.md` | the shared, tracked convention |
| `local` | `REPO_ROOT/.claude/source-control.local.md` | a personal deviation from team policy here |

Infer the layer rather than asking when the request names one — "my personal convention" / "on this
machine" is `local`, "for all my repos" is `user`, "our convention" is `team` — but state which
layer you picked before writing, since writing to the wrong one either fails to reach teammates or
commits a personal preference to shared history.

When the invocation carries a `subject_pattern=` argument, write non-interactively: use it as
`subject_pattern` (the literal `Conventional Commits` keyword, which resolves to the bundled 11-type
anchored pattern and enables `type_list`, or an anchored regex), and set `pr_title_pattern` to the
same. Reject a `subject_pattern` that is not machine-checkable (a plain-language value) with the same
message `check` gives, rather than persisting it.

**A non-interactive write is an update, not a fresh file.** The target layer is rewritten in place, so
read it first and carry through every *independent* key the invocation did not ask to change. An
argument naming `subject_pattern` says nothing about `trailer_policy`; dropping an existing
`trailer_policy: none` because the new invocation did not mention it changes commit behavior the user
never asked to change. Only a key the invocation explicitly sets may be replaced, and only a key the
user explicitly clears may be removed.

**Keys derived from a changed key are recomputed, not carried.** `type_list` and `pr_title_pattern`
are functions of `subject_pattern`, so preserving them across a `subject_pattern` change produces a
config that contradicts itself. Replacing a Conventional-Commits pattern with a custom regex drops
`type_list` entirely — a custom pattern has no type vocabulary, and a stale
`build, chore, ci, …` list beside `^[A-Z]+-\d+: .+` would have `/commit` pre-check against a
vocabulary the pattern does not use. Moving the other way re-adds the bundled 11-type list.
`pr_title_pattern` follows the same rule unless the user set it to a value independent of
`subject_pattern`, which is carried through like any other independent key.

**Writing an overlay layer — `user` or `local` — resolve the layers below first and omit any
*requested* key already equal to that merge.** A non-interactive argument is not evidence of a genuine
deviation: `apply layer=local subject_pattern=X` against a team file that already declares `X` would
otherwise pin `X` locally, so a later team change would be silently ignored on this machine — the
exact failure per-key override exists to prevent. This applies to the requested keys only; it never
licenses dropping an unrelated key the overlay already carries. When every requested key already holds
and the overlay would otherwise be empty, write nothing and say so rather than materializing an empty
file.

With no argument in an interactive session, run the interview:

0. **Anchor at the repo root** exactly as `check` does — resolve `REPO_ROOT` once and reuse the
   literal resolved path for every read, write, and git command below; re-resolve it at the top of
   every self-contained Bash call.
1. **Read the current config first** — all three layers, not just the target. Present the effective
   merge and which layer supplies each key; the interview proposes changes against that baseline and
   overwrites nothing without confirmation. Writing an overlay layer, carry only the keys that
   genuinely differ from the merge below it: an overlay that restates every key silently pins values
   the base layer should still own, which is the failure mode per-key override exists to avoid.
2. **Infer before asking.** Gate this on the resolved value, not on file presence: infer whenever the
   **effective merged `subject_pattern` is unresolved**, which includes the case where layers exist
   but contribute only other keys. Skipping inference because some file exists would recommend the
   bundled default over a `commit-msg` hook that demands ticket-prefixed subjects. Look for an
   existing declared or enforced convention, surfacing which signal produced the candidate:
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
     regex, express the alternatives as alternation inside one anchored regex
     (`^(?:feat|fix): .+|^[A-Z]+-\d+: .+`), or fall back to the Conventional Commits default; do not
     persist a free-text `subject_pattern`, and never persist a list — `subject_pattern` is exactly
     one value, because nothing here defines how a list would serialize or match.
4. **Settle the remaining fields**, recommendation first:
   - **`pr_title_pattern`** — usually identical to `subject_pattern` (squash-merge repos set the PR
     title as the squash commit's subject). Ask only if the user wants them to differ; otherwise
     write the deferral marker exactly as `` Same as `subject_pattern`. `` — capital S, backticked key,
     trailing period. That literal is what the resolution contract recognizes and expands against the
     effective `subject_pattern`; any other casing or punctuation is read as a pattern in its own
     right and pre-checked as a regex.
   - **`trailer_policy`** (optional) — whether commits should carry a `Co-Authored-By:` (or other)
     attribution trailer, and its exact template. Recommend keeping `/commit`'s default unless the
     user states otherwise. Omit this section entirely if the repo has no trailer convention.
   - **`pr_body_attribution`** (optional) — the attribution line `/pull-request create` appends to the
     PR body, the PR-body analogue of `trailer_policy` and gated separately (a consumer setting
     `trailer_policy: none` still keeps the PR-body line unless this is also set). Recommend keeping the
     default `🤖 Generated with [Claude Code]…` line unless the user wants a custom line or `none` to
     omit it. Omit this section entirely to keep the default.
5. **Write the config.** Materialize the target layer's path with these sections:

   ```markdown
   # source-control configuration

   Read by the source-control Claude Code plugin (and, where installed, the guardrails
   commit-convention gate). Without those plugins this file is inert — safe to ignore.
   It is a drafting aid for plugin users, not team-wide enforcement: tool-agnostic
   enforcement for every committer (plugin or not) is a commit-msg hook or CI check.

   Commit-subject / PR-title convention for the source-control plugin, resolved by
   `/source-control:commit` and `/source-control:pull-request` before they infer from the repo's own
   CLAUDE.md/rules/commit-msg hook or fall back to the bundled Conventional Commits default.
   Re-run `/source-control:setup` to change these values.

   ## subject_pattern

   <the literal keyword `Conventional Commits`, or exactly one anchored regex — always
   machine-checkable, never a list and never a plain-language description>

   ## type_list

   <only present when subject_pattern is Conventional-Commits-shaped — omit this section entirely for
   a custom pattern with no type vocabulary>

   ## pr_title_pattern

   <the pattern, or "Same as `subject_pattern`.">

   ## trailer_policy

   <only present if the repo has a trailer convention>

   ## pr_body_attribution

   <only present if the repo overrides the default PR-body attribution line — a custom line, or
   `none` to omit it>
   ```

   Drop any section with no content rather than leaving it empty. Writing a non-`team` layer, add one
   line under the heading naming which layer this file is and that it overrides per key — the file
   sits next to (or looks identical to) the team file, and the next reader has no other signal.

   The self-describing preamble above the first `##` heading exists for the reader who does NOT run
   these plugins — the team file lands in shared history, and a teammate opening it deserves to know
   it binds nothing on its own. It is part of the template, not an append: a reconfiguration run
   rewrites the whole header block in place, never stacks a second copy. Prose above the first H2 is
   inert to every consumer by construction — the enforcement resolver reads only the first non-empty
   body line under a `## <key>` heading (`lib/resolve-convention-pattern.sh` parse contract), and the
   drafting read is per-H2-key — so the preamble can never change a resolved value.

6. **Verify the write, per layer.** The post-write check inverts between layers and there is no
   shared shortcut: the team file must be tracked, the local overlay must be ignored, and the
   user-global file is not in a repository at all. Run the wrong one and the skill reports success
   over exactly the failure it exists to catch.

   - **`layer=user`** — `~/.claude/source-control.md` is outside `REPO_ROOT`. Run no git command
     against it: `git check-ignore` and `git status` on a path outside the worktree are meaningless
     here, and a home directory that happens to be its own repository would produce a confidently
     wrong verdict. Confirm the file exists with the intended content and report the path. It takes
     effect immediately in the next session; nothing is staged or committed.
   - **`layer=local`** — `REPO_ROOT/.claude/source-control.local.md` **must** be both ignore-matched
     and untracked, and those are two independent probes. Bare `git check-ignore` consults the index
     and reports nothing for a file that is already tracked, because gitignore rules do not apply to
     tracked files — so "no rule exists" and "a rule exists but the file was committed anyway" are
     indistinguishable from its output alone, and they need opposite remediations. Never stage the
     overlay in either case.
   - **`layer=team`** — `REPO_ROOT/.claude/source-control.md` must be tracked and staged. Verify it
     is actually staged before reporting success; neither `git check-ignore -v` nor
     `git ls-files --error-unmatch` proves this alone. `git check-ignore -v` only reports a matching
     `.gitignore` pattern, staying silent for both a properly tracked file and a plain untracked one.
     `git ls-files --error-unmatch` only proves the path is *somewhere* in the index: on a
     reconfiguration run (the file already existed and this step just rewrote it), the path was
     already tracked, so that check exits 0 even though the new content is still an unstaged
     working-tree modification.

   For `layer=team`, run these as one Bash tool call so `REPO_ROOT` only needs resolving once:

   ```bash
   REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"
   # `git check-ignore -v` exits 0 (and prints the matching rule) only when a .gitignore pattern
   # excludes the file; it exits non-zero with no output otherwise. Branch on the exit code — do
   # NOT fall through to add/diff on a match: `git add` would silently refuse the ignored path, and
   # `git diff --quiet` on an ignored untracked file exits 0 trivially, so the sequence would report
   # false success with nothing actually staged for teammates.
   if IGNORE_MATCH="$(git check-ignore -v "$REPO_ROOT/.claude/source-control.md")"; then
     echo "STOP: .claude/source-control.md is excluded by .gitignore: $IGNORE_MATCH" >&2
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

   For `layer=local`, run both probes and branch on the pair:

   ```bash
   REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}"
   OVERLAY=".claude/source-control.local.md"
   # --no-index answers "does a matching ignore rule exist?" on its own terms. Without it, git
   # consults the index first and reports nothing for an already-tracked file, conflating a missing
   # rule with a rule that exists but was overridden by a past commit.
   IGNORE_MATCH="$(git -C "$REPO_ROOT" check-ignore --no-index -v -- "$OVERLAY")" && HAS_RULE=1 || HAS_RULE=0
   # An ignore rule does not untrack an already-committed file, so ask the index separately.
   TRACKED="$(git -C "$REPO_ROOT" ls-files -- "$OVERLAY")"
   # Exit non-zero on either FAIL, exactly as the team guard does. The overlay was written at step 5,
   # so proceeding here would report an effective merge over a personal file that is still shareable —
   # visible to `git status` (no rule) or already in team history (tracked). Halt until it is fixed.
   if [ "$HAS_RULE" -eq 1 ] && [ -z "$TRACKED" ]; then
     echo "OK: personal overlay is ignored and untracked: $IGNORE_MATCH"
   elif [ -n "$TRACKED" ]; then
     echo "FAIL: $OVERLAY is tracked; untrack it with: git rm --cached $OVERLAY" >&2
     exit 1
   else
     echo "FAIL: no ignore rule matches $OVERLAY; add .claude/*.local.* to .gitignore" >&2
     exit 1
   fi
   ```

   The tracked branch takes precedence in the report: adding the `.gitignore` line to an
   already-committed overlay changes nothing, so recommending it there sends the user in a circle.

   Either guard stopping the sequence (non-zero exit) halts the apply — do not report success or
   proceed to step 7. For the team guard (`IGNORE_MATCH` reported), tell the user the matching
   `.gitignore` pattern and ask them to either fix `.gitignore` so `.claude/source-control.md` is no
   longer excluded, or persist the convention to a different layer. For the `layer=local` guard,
   surface the failure's own remediation — the `.claude/*.local.*` ignore line for a missing rule, or
   `git rm --cached` for an already-tracked overlay — so the personal overlay does not linger in a
   shareable state. Re-run this step once the state is fixed.

   This skill stages but does not commit — `git status --porcelain` legitimately keeps printing an
   index (`X`) column of `A` or `M` with a blank worktree column for a staged-but-uncommitted file,
   so success does **not** require porcelain to be fully empty, only that no *unstaged* changes
   remain. Prompt the user to commit the team file, since it is team-shared and must be committed to
   take effect. Only report success once both checks pass: not ignored, and no unstaged changes
   remain.

7. **Report the new effective merge**, not just what was written. A `layer=user` write can be
   overridden by an existing team file, and a `layer=team` write can be overridden by an existing
   local overlay — a user who is told only "wrote `subject_pattern`" and then sees `/commit` use a
   different pattern has been misled by the success message.

   For a `team` write, the report also states plainly what the file is and is not: a drafting aid
   (plus CC-layer enforcement input) for teammates who run these plugins, inert for everyone else —
   NOT team-wide enforcement. Committers without the plugin are bound only by a commit-msg hook or CI
   check; when the team wants that, point at the guardrails plugin's opt-in commit-msg hook or the
   repo's own hook manager rather than implying this file enforces anything by itself.

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

A convention config file at the chosen layer (when `apply` wrote one), plus the resulting effective
merge with the winning layer per key, a one-paragraph summary of where the convention came from
(inferred or user-declared), and — for babysit — the `check` probe report and the reconfigure path
used. `check` alone reports the effective configuration across both surfaces and changes nothing.

## What this skill does NOT do

- Make a commit or open a PR — that's `/source-control:commit` and `/source-control:pull-request`.
- Enforce the convention at commit time — a project's own `commit-msg` hook (when one exists) remains
  the authoritative gate; this config only tells the plugin's skills what shape to draft and
  pre-check against.
- Write the consumer's `.gitignore`. The personal overlay needs `.claude/*.local.*` ignored; this
  skill recommends the line and leaves the edit to the consumer.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs` — the convention lives in the
  consumer's own config layers; babysit settings live in Claude-Code-owned `userConfig`,
  reconfigured only through the two paths above.
