---
description: "When the bundled commit skill or built-in commit-push-pr command resolves in this session, prefer the first only when none of this skill's contract (convention, trailer, surgical staging, pre-checks) is wanted and the second to commit, push, and open a PR at once; this skill for every other commit. Create a git commit with a subject matching the resolved convention (layered `source-control.md` config → project convention → Conventional Commits default), a Claude Co-authored-by trailer, and surgical staging (never `git add -A`), feeding the message to git via Bash heredoc. Use when: 'commit this', 'make a commit', 'commit with message HINT', not for push, branch creation, or PR creation (use /pull-request)."
argument-hint: "[message-hint]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: implement
  summary: Commit with the resolved convention and surgical staging
---

## Pre-computed context

Exec-bit backstop: !`bash "${CLAUDE_PLUGIN_ROOT}/skills/commit/scripts/exec-bit-check.sh" --probe 2>/dev/null || echo "unavailable — run the check manually"`
Config layer (user-global): !`test -f "$HOME/.claude/source-control.md" && echo present || echo absent`

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined:

- Current branch, `git branch --show-current`
- Staged, `git diff --cached --stat | tail -1`
- Unstaged, `git status --short | head -20`
- Recent commits, `git log --oneline -5`

**The two pipes are the bound and belong in the command.** The Bash tool returns a command's
full output into context, so a read-time cap ("read only the summary line") bounds nothing; `head`
and `tail` truncate before the result exists. These are ordinary body Bash calls, so the
one-invocation composition of the `## Pre-computed context` block does not apply.

Before the layer probes, classify the config root with `bash "${CLAUDE_PLUGIN_ROOT}/lib/config-root.sh" classify`. For `home` or `non-repo`, report team and overlay as not applicable, skip the three probes, and read user-global only ([../../reference/config-resolution.md](../../reference/config-resolution.md), "The three layers").

The team value of the convention keys (`subject_pattern`, `type_list`, `trailer_policy`) comes from
`docs/conventions/source-control.yaml`. Read it first, when git-tracked
(`git ls-files --error-unmatch -- ":/docs/conventions/source-control.yaml"`), through
`bash "${CLAUDE_PLUGIN_ROOT}/lib/convention-key.sh" layer "$ROOT" <key>`, which prints `yaml`,
`legacy-md` or `none` for a key; `value` and `list` print the YAML's value. A key the YAML carries is
authoritative for the team layer; only a key it lacks is read from the legacy markdown layers below,
the compatibility read kept for one release. Report which layer supplied each value.

Then resolve the repo-scoped legacy markdown layers (the compatibility read) as separate calls. Each
uses git's magic pathspec `:/`, which resolves against the top of the working tree, so these work
from any subdirectory with no root substituted in. **Quote the pathspec**: the leading `:` is
pathspec magic, and quoting keeps the shell from reinterpreting it.

1. Legacy team layer, trackedness.
   `git ls-files --error-unmatch -- ":/.claude/source-control.md"`
2. Legacy team layer, existence.
   `git ls-files --cached --others -- ":/.claude/source-control.md"`
3. Personal overlay, existence.
   `git ls-files --cached --others -- ":/.claude/source-control.local.md"`

Probes 2 and 3 omit `--exclude-standard`, so a gitignored file is still listed: the personal
overlay is expected to be gitignored, and an untracked team file must be *seen* to be reported as
untracked.

**Combine probes 1 and 2 in that order**: trackedness first, existence consulted only when
trackedness comes back nonzero. They are not independent readings:

| Trackedness (1) | Existence (2) | Team-layer state |
|---|---|---|
| exit 0 | not consulted | `present (tracked)`, this is a config layer |
| nonzero | non-empty output | `present but UNTRACKED`, deliberately **not** a config layer |
| nonzero | empty output | `absent` |

A single `--error-unmatch` call exits nonzero for both of the last two rows; probe 2 exists to
separate them.

**A nonzero exit from probe 1 is a result, not a failure**; probe 2 resolves which answer it is.
Only a probe that could not run at all (git unavailable, not a repository) yields an unknown value
to carry on past. Never fold `present but UNTRACKED` into "unknown": they mean opposite things, and
treating the untracked case as unknown readmits a file the resolution rules exclude.

Keep the git lines above out of `## Pre-computed context`: the harness composes that block into one
shell invocation, and a worktree-isolated agent refuses a git-bearing compound command it cannot
statically verify.

**These are snapshots taken when they run, not substitutes for the checks.** The exec-bit line sees
only what was staged when the skill loaded, not what step 2 stages, so step 4 re-runs the script.
The config-layer probes report **presence**, not merged content: read the present layers and merge
them per key. A team layer reported `present but UNTRACKED` is not a layer: resolution requires the
team file to be git-tracked, so an untracked or gitignored file at that path must not drive the
convention.

**Every repo-scoped probe anchors at the repository root**, via the `:/` magic pathspec, never at
the session's current directory. A session started in a subdirectory would otherwise look for
`<cwd>/.claude/`, report both repo-scoped layers absent, silently drop the team convention and
`trailer_policy`, and commit with the wrong subject shape or attribution. Never substitute a
resolved root path into a probe: a root containing `$(…)`, a backtick, or a double quote is *not*
made safe by double-quoting the substituted text (the substitution still evaluates, or the quote
terminates the argument), and `:/` never substitutes the root at all. This matches the
root-resolution requirement in
[`${CLAUDE_PLUGIN_ROOT}/reference/config-resolution.md`](../../reference/config-resolution.md); the
probes must not disagree with it. `exec-bit-check.sh` anchors itself the same way.

## Per-commit checklist

Run this list **for every commit**, including the second and tenth of a session, as commands, not
remembered facts. Steps 3–5 are the ones a long session silently stops performing.

1. **Resolve** the convention + `trailer_policy` across all three config layers (once per session
   is enough; re-resolve if a layer changed).
2. **Stage** surgically by explicit path, after checking the four pre-existing conditions below.
3. **Format**, run the discoverable formatter scoped to this commit's paths, re-stage its fixes.
4. **Exec-bit**, run `exec-bit-check.sh --fix -- <this commit's paths>`, AFTER step 3.
5. **Pre-check** the drafted subject against the resolved pattern before invoking git.
6. **Fragments**, in a repository with a `fragment-plugins.txt` list under `scripts/`, pipe the drafted message to
   `write-changelog-fragments.sh` and stage the paths it prints (Task step 7).
7. **Commit** via the Bash tool: `git commit -F -` heredoc-piped, `--trailer` per `trailer_policy`.
8. **Report** the resulting SHA + subject to the user.

## Purpose

Builds a commit message that honors a subject convention, appends a `Co-authored-by:` trailer, and
feeds it to `git commit` via stdin, without these failure modes:

- **PowerShell here-string syntax (`@'...'@`) inside a Bash tool call** produces `unexpected EOF` and
  triggers fallback to writing the message to `.git/<TEMP>.txt`. Scratch files in `.git/`, git's
  internal directory, collide with `COMMIT_EDITMSG` and other internals.
- **`git commit -m "<multi-line>"`** flattens newlines unpredictably across shells.
- **`git add -A` / `git add .`** stages secrets, build artifacts and unrelated edits; stage
  surgically instead.

## Subject convention ladder

The subject convention (WHAT shape a subject must take) resolves via a ladder, checked in order:

1. **The layered source-control convention config**. User-global, tracked team
   (`docs/conventions/source-control.yaml`, then the legacy `source-control.md` for a key the YAML
   lacks), and gitignored personal overlay, merged per key by
   [`${CLAUDE_PLUGIN_ROOT}/reference/config-resolution.md`](../../reference/config-resolution.md).
   Resolve all three layers before using any value; one layer alone is not the effective config.
   When any layer declares one, the effective `subject_pattern` (and `type_list`, when
   Conventional-Commits-shaped) is authoritative. Before pre-checking, expand `subject_pattern`: the
   literal keyword `Conventional Commits` expands to the anchored pattern in step 3 below; anything
   else is already a single anchored regex, used as-is.
2. **The consuming project's own `CLAUDE.md`, `AGENTS.md`, rules, or commit-msg hook**: if the
   merged config declares no `subject_pattern` (absent from every layer, including when layers exist
   but contribute only other keys) and the project declares (or enforces via lefthook, husky,
   commitlint, or a plain `.git/hooks/`) a different convention, follow that.
3. **Conventional Commits (11-type vocabulary)**, the default when neither of the above is present.
   Every subject must match this anchored pattern:

```text
^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+
```

Compliant examples:

- `feat(auth): add OAuth login flow`
- `fix(api): handle null user in /me endpoint`
- `docs: clarify rebase guidance`
- `refactor(skills)!: rename /simplify to /code-review`

The 11 types, `build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test`, are the set
the Conventional Commits spec, the Angular convention, commitlint's `@commitlint/config-conventional`
source, and `amannn/action-semantic-pull-request`'s default `types` list all agree on. `security` is
**not** a Conventional Commits type in any of them; never add it.

A project's commit-msg git hook is the authoritative gate whichever rung resolved the pattern; this
skill's pre-check only fast-fails client-side before the hook round-trip. When no layer resolves a
`subject_pattern` and nothing is inferable from the project's own files, point the user at
`/source-control:setup` to persist a convention instead of re-inferring one every commit.

## Task

1. Survey working tree (`git status`, `git diff --cached --stat`) to confirm what's staged.
2. Stage the intended files, but first check each path against these four pre-existing conditions,
   *before* this step touches anything. `git add` silently overwrites each state rather than
   erroring, and in three of the four `git diff --stat` reads empty, so the obvious check misses it.
   Rationale for each is in [reference/staging-preconditions.md](reference/staging-preconditions.md).

   | Condition | Detect with | Action |
   |---|---|---|
   | Already-staged deletion | `git diff --cached --name-status -- <path>` reports `D` | Skip the path entirely; never `git add` over it |
   | Staged rename, old side | same command reports `R<score> <old> <new>` whose `<old>` falls under `<path>` | Skip the old side entirely; never `git add` over it |
   | Untracked files under a directory path | `git status --porcelain -- <path>` shows `??` entries | Stop and surface them; enumerate the intended files instead of adding the directory |
   | Partial-staging split | `git diff --cached --stat -- <path>` **and** `git diff --stat -- <path>` both non-empty | Leave as-is; a blanket add sweeps in hunks the user deliberately left unstaged |

   Run `git add <path>...` only for paths in none of those four states.
3. Run the [format-before-push check](reference/format-check.md) against the files just staged for
   this commit (not the full staged set), re-staging any fixes.
4. Run the exec-bit check **after** step 3: a formatter re-stage reads the worktree file mode, so an
   exec bit set earlier would be silently undone by that later `git add`.

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/commit/scripts/exec-bit-check.sh" --fix -- <path>...
   ```

   The script reports and fixes every newly-added file whose staged blob starts with a shebang while
   its staged mode is `100644`, setting the worktree bit and the index entry in the order that
   survives a later `git add`. **The pathspec is required**: `--fix` refuses an unscoped run
   (exit 2) rather than sweep mode changes across another session's staged work; pass `--all` only
   for a deliberate whole-index sweep. Rationale, cross-platform caveats, and the manual fallback
   are in [reference/exec-bit.md](reference/exec-bit.md).
5. Draft a subject + optional body, scoped to the staged diff, shaped to satisfy the active subject
   convention (default: the Conventional Commits pattern above).
6. Pre-check the subject against the pattern (fast-fail before invoking git).
7. Write changelog fragments when the repository releases plugins from them, shown by a
   `fragment-plugins.txt` list in its `scripts/` directory. Pipe the drafted message (subject, blank
   line, body) to the script from the repository root and `git add` each path it prints, so the
   fragments land in this commit:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/write-changelog-fragments.sh" <<'EOF'
   <the drafted message>
   EOF
   ```

   For each listed plugin the staged change touches, it writes the fragment in place of the hand
   version bump and CHANGELOG entry, through the repository's own `new-changelog-fragment.sh`.
   The bump comes from the Conventional Commits type: `feat` minor; `fix` and `perf` patch;
   `build`, `chore`, `ci`, `docs`, `refactor`, `style` and `test` none; `!` or a `BREAKING CHANGE`
   footer major. The subject and body go under `### Added` (`feat`), `### Fixed` (`fix`) or
   `### Changed` (anything else), and a `none` fragment gets one line saying why no release is
   needed. A later releasing-type commit on the branch adds its entry to the branch's fragment and
   only raises the bump. On exit 2 for a subject it cannot map, rerun with
   `--level major|minor|patch|none`. Without the list, or for a plugin the list does not name, it
   writes nothing, and the repository's own release record (a version bump plus CHANGELOG entry)
   still applies.
8. Invoke `git commit -F -` via the Bash tool, heredoc-piped, adding `--trailer` per the trailer
   template below only when the resolved `trailer_policy` calls for one.
9. Surface the resulting commit SHA + subject to the user.

## Canonical bash form

Use the **Bash tool**, not the PowerShell tool. Bash heredoc is the canonical form on all platforms
(Git Bash, Linux, macOS).

```bash
# --trailer line below applies only when the resolved trailer_policy calls for one
# (default: yes). trailer_policy "none" -> drop the --trailer line entirely.
# trailer_policy naming a different template -> substitute that template's text.
git commit -F - --cleanup=verbatim \
  --trailer "<Co-authored-by trailer, placeholders filled>" \
  <<'EOF'
<subject — shaped to satisfy the active subject convention>

<body — wrap at ~72 cols, blank line between paragraphs>
EOF
```

`git commit -F - <message-via-stdin>` with a PowerShell `@'...'@` here-string works in a pure
PowerShell tool call, but **never mix syntaxes inside one tool invocation**: a `@'...'@` block inside
a Bash tool call leaves the bash parser unable to terminate the heredoc.

**Hard rules:**

- Invoke via the **Bash tool**.
- Heredoc delimiter is single-quoted: `<<'EOF' ... EOF`. Single quotes prevent `$variable` and
  backtick interpolation inside the message.
- `--cleanup=verbatim` preserves the message exactly, no auto-stripping of comments or whitespace.
- Never write the message to `.git/<TEMP>.txt`. If a real file is unavoidable, use `mktemp`.
- Never mix Bash heredoc with PowerShell `@'...'@` inside one invocation.

For a dirty shared index (concurrent sessions, pre-existing mixed WIP), the pathspec-limited form
and its staged-deletion hazards are in [reference/pathspec-commits.md](reference/pathspec-commits.md).
The default stays the plain index commit.

**The exec bit does not survive the pathspec form under `core.filemode=false`** (the Windows
default). `--only` records the working-tree mode, and with filemode off git cannot see the
`chmod +x`, so a correct `100755` index entry is rebuilt as `100644`; the plain index commit
preserves `100755`. If this commit includes a newly-added shebang file the exec-bit check
corrected, commit that path with the **plain index form** (splitting the commit if the rest needs a
pathspec), and confirm with `git ls-tree HEAD -- <path>` rather than trusting the index. Detail and
two failed workarounds are in [reference/pathspec-commits.md](reference/pathspec-commits.md).

## Pre-check

Before invoking `git commit`, regex-match the drafted subject against the active convention's pattern
(default: the Conventional Commits pattern above).

On mismatch, surface the convention name and the compliant examples, and ask for a compliant
subject before invoking git. The pre-check is shape-only; the project's `commit-msg` git hook (when
one exists) is the authoritative gate. The pre-check saves the hook startup on an obviously wrong
subject and gives a fast, actionable error instead of an opaque hook failure.

## Trailer resolution

The default template is:

```text
Co-authored-by: Claude <model> <noreply@anthropic.com>
```

**The `<model>` placeholder is filled from your own knowledge of the running session**: the model
family and version the harness reports for this session (the value `/usage` shows). If uncertain,
invoke `/usage` to confirm before committing. No environment variable auto-fills it; the trailer is
part of the message body sent to `git commit`, not git config.

**An optional context clause**, `Co-authored-by: Claude <model> (<context>) <noreply@anthropic.com>`,
e.g. `(1M context)`, may be added when the context window is a distinguishing fact about the
session and known with confidence. It is **not** required; its absence is not a defect.

### Which authority wins

Four sources can specify a trailer. Resolve in this order:

1. **A resolved `trailer_policy`** from any config layer. Authoritative. `none` means omit
   `--trailer` from the `git commit` invocation entirely (do not append an empty or default
   trailer); a value naming a different template means substitute that template exactly. `none` and
   absence are different states.
2. **The consuming project's own conventions** (`CLAUDE.md`, `AGENTS.md`, rules), if they specify a
   different attribution trailer, or none, follow those.
3. **Harness-injected commit guidance.** The Claude Code harness may inject its own commit
   instruction naming a `Co-Authored-By` trailer. Adopt its **shape** (why the context clause above
   is optional), but **never copy its literal text**: it can carry a **hardcoded model name that
   does not match the running session**, and copying it writes a false provenance claim into
   durable git history. Always fill `<model>` from actual session
   knowledge. A mod can rewrite or blank that guidance before you see it: its `attribution.text`
   hook receives the commit trailer (`kind: commit`) and the PR footer (`kind: pr`) as the engine
   composed them and returns the text the model reads instead. So absent or unusual injected
   guidance says nothing about the project's wishes; sources 1 and 2 still decide. (Claim: the
   event and its kinds. Basis:
   [mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
   "Prompts and what Claude reads", `attribution.text` row, fetched 2026-10-01, and the
   `AttributionTextKind` type in the built-in `plugin-authoring` skill's `claude-code.d.ts` for
   Claude Code 2.1.287. As of: 2026-10-01. Recheck: the row or the type changes.)
4. **This skill's default**, above.

**Key spelling.** This skill emits `Co-authored-by`, the spelling GitHub's documentation uses
exclusively and GitHub itself writes when appending co-author trailers to a squash-merge message.
GitHub's attribution is not case-sensitive in practice (a `Co-Authored-By:` trailer resolves its
co-author in the GraphQL `Commit.authors` connection just the same; the docs do not state case
sensitivity either way), so this is a consistency choice: branch commits and forge-written squash
merges agree. Git preserves a trailer key's case verbatim (`git interpret-trailers` does not
normalize it, and no `trailer.*` config here changes that), so existing history keeps its spelling;
this skill never rewrites it. A consumer who wants a different spelling sets a `trailer_policy`
template.

## Unrelated uncommitted changes

If the working tree holds unstaged or untracked files outside this commit's scope, classify each
before staging per `/source-control:pull-request create` (its unrelated-changes classification:
include / stash / separate-commit / discard). Do not duplicate that classification here; invoke
`/source-control:pull-request create` to surface it to the user.

## Staging discipline

Always `git add <specific-files>`, never `git add -A` or `git add .`: those can include secrets,
build artifacts, or unrelated changes the user did not approve for this commit. Stage multiple files
by explicit list, not wildcard, and skip the partial-staging split per step 2 above.

Immediately after staging, run the format-before-push check and then the exec-bit check, in that
order, to catch what CI would otherwise catch on the push round-trip.

## Composition policy

This skill is the single source of truth for the commit mechanic. Other skills compose
`/source-control:commit` rather than invoking `git commit` directly, which bypasses the pre-check,
trailer logic, and surgical staging.

**"Compose" means one of exactly two things, and a composing skill must name which:**

- **Re-invoke `/source-control:commit`** for the commit. This is the default and the only form that re-renders this
  skill's full content. Prefer it whenever the commit is a discrete step a user could have asked for.
- **Run the per-commit checklist above yourself**, per commit, as commands. Permitted for a workflow
  skill making many commits in one flow, where re-invocation per commit is disproportionate.

Treating this skill as a convention absorbed once and then remembered is **not** composition. The
message shape is reinforced every commit; what decays is the ordered per-commit *checks*: the
formatter run, the exec-bit fix, the subject pre-check. Skipping them gives no visible signal, so a
session that stopped running them looks identical to one that has not, until CI fails.

Step 4 is the cheap re-anchor for the checklist form: it is a command with an exit code rather than
a paragraph to recall, and the pre-computed probe at the top of this file surfaces its finding
first.

Workflow skills without explicit commit semantics should report status at phase boundaries and let
the user or the next workflow stage decide commit timing; a skill with commit semantics in its
documented contract (e.g. `/source-control:pull-request create`) composes this one.

## Recorded deviations

- **Model invocation stays enabled** (`disable-model-invocation: false`, declared explicitly). The
  fleet archetype for a `/source-control:commit`-shaped skill is `disable-model-invocation: true`,
  user-invoked only. This skill deviates because a workflow skill that composes the commit mechanic
  cannot do so if the model may not load it. Compensating controls: surgical staging (never
  `git add -A`), the subject pre-check before any git invocation, no hook bypass, and a
  user-visible SHA + subject report after every commit.

## Boundary, native Claude Code surfaces

Claude Code bundles a skill of the same name whose description tells the model to use it whenever
it is about to commit, so the two compete for every commit. A built-in command also commits as its
first step.

- **`commit` (bundled skill)**: a generic commit workflow; it gathers git context and applies
  Claude Code's own message style, staging rules, and attribution. The model and the person can
  both invoke it.
- **`/commit-push-pr` (built-in command)**: commits, pushes, and opens a PR in one prompt-driven
  step. The model and the person can both invoke it.
- **This skill (marketplace plugin).** Resolves the repository's subject convention through the
  ladder above (layered `source-control.md` config, the project's own convention, the Conventional
  Commits default), resolves `trailer_policy`, stages surgically against the four preconditions,
  and reruns the format, exec-bit, and subject pre-check steps on every commit.

**Routing.** Prefer this skill whenever it resolves and the repository carries a commit
convention, a `source-control.md` layer is present, or a workflow composes `/source-control:commit`.
When the bundled `commit` skill resolves in this session, prefer it only for a plain commit where
none of this skill's contract is wanted. A request to commit, and nothing more, stays here even
when `/commit-push-pr` resolves: that command also pushes and opens a PR, which
`/source-control:pull-request` owns.

**Mutation gate.** All three create commits, and `/commit-push-pr` also pushes. Pick one per
commit and never run two for the same change. This skill never chains into the bundled `commit`
or `/commit-push-pr` on its own behalf.

**Availability is never assumed.** The bundled skill is gated, and `disableBundledSkills` or a
`skillOverrides` entry hides it; this section states what to do when a surface resolves, never
that it is present. The four-part records live in [reference/native-commit.md](reference/native-commit.md).

## What this skill does NOT do

- **No `git push`**, that's `/source-control:pull-request create`.
- **No branch creation**, that's the project's branch-naming / branch-protection mechanisms (or
  `/source-control:worktree create`).
- **No PR body composition**, that's `/source-control:pull-request create`.
- **No `git merge` or forge merge**, that's `/source-control:pull-request merge`.
- **No rebase**, that's `/source-control:pull-request create`.
- **No `--no-verify` or hook bypass**, if the project's `commit-msg` hook rejects the message,
  surface the error and re-draft; never bypass.

## Spoke paths

The `reference/` files write this skill's directory as `<skill-dir>`, which is
`${CLAUDE_SKILL_DIR}`. Substitute that path before running a command or writing it into a brief:
those files arrive through the Read tool as plain bytes, so a `${…}` token would reach the Bash tool
unsubstituted, and its environment has no `CLAUDE_SKILL_DIR`. Basis: the plugins reference,
<https://code.claude.com/docs/en/plugins/manifest-reference#where-each-variable-resolves>, verified
2026-10-07; recheck when that table adds supporting files to where a `${…}` reference resolves.

## Next

`/source-control:pull-request create`. Its precondition is a branch carrying the work to ship.

## Reference index. Load on demand

| File | Load when |
|------|-----------|
| [reference/staging-preconditions.md](reference/staging-preconditions.md) | A step-2 precondition fired and the right action is not obvious, or judging whether a new condition belongs in the set. |
| [reference/format-check.md](reference/format-check.md) | Running step 3, formatter discovery, path scoping, the two-stage filter, partial-staging preservation. |
| [reference/exec-bit.md](reference/exec-bit.md) | Understanding or hand-running step 4, why both the worktree bit and the index, `core.filemode` caveats, manual fallback. |
| [reference/pathspec-commits.md](reference/pathspec-commits.md) | The index holds staged work outside this commit's scope. Pathspec `--only` semantics and the staged-deletion hide/restore sequence. |
| [`${CLAUDE_PLUGIN_ROOT}/reference/config-resolution.md`](../../reference/config-resolution.md) | Resolving or merging the three config layers, or interpreting a key's `none`-vs-absent state. |
