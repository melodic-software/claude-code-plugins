---
name: commit
description: "Create a git commit with a subject matching the resolved convention (layered `source-control.md` config → project convention → Conventional Commits default), a Claude Co-Authored-By trailer, and surgical staging (never `git add -A`), feeding the message to git via Bash heredoc. Use when: 'commit this', 'make a commit', 'commit with message <hint>' — not for push, branch creation, or PR creation (use /pull-request)."
argument-hint: "[message-hint]"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Exec-bit backstop: !`bash "${CLAUDE_PLUGIN_ROOT}/skills/commit/scripts/exec-bit-check.sh" --probe 2>/dev/null || echo "unavailable — run the check manually"`
Config layer (user-global): !`test -f "$HOME/.claude/source-control.md" && echo present || echo absent`

## Repository context — gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch — `git branch --show-current`
- Staged — `git diff --cached --stat`
- Unstaged — `git status --short`
- Recent commits — `git log --oneline -5`

Then resolve the two repo-scoped config layers, in this order and as separate calls:

1. `git rev-parse --show-toplevel` — run this **first** and substitute the literal path it prints
   into the next two commands. Never re-derive the root inline inside another command.
2. Tracked team layer — `git -C <root> ls-files --error-unmatch .claude/source-control.md`. Exit 0
   means present **and tracked**. A file sitting at that path that this command does not report is
   `present but UNTRACKED`, and is deliberately not a config layer.
3. Personal overlay — `test -f <root>/.claude/source-control.local.md`.

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. All of the
above moved out of pre-compute in #1619 — the harness composes the block into one shell invocation
and a worktree-isolated agent refuses a git-bearing compound command; the two config-layer one-liners
were themselves compound, which is why they are decomposed here rather than moved across intact. Do
not fold them back.

**These are snapshots taken when they run, not substitutes for the checks.** The exec-bit
line only sees what was already staged when the skill loaded; anything staged in step 2 below is
invisible to it, so step 4 re-runs the script for real. The config-layer probes report **presence**,
not merged content — read the layers that are present and merge them per key. A tracked-team layer
reported `present but UNTRACKED` is deliberately not a layer: resolution requires the team file to
be git-tracked, so an untracked or gitignored file at that well-known path must not drive the
convention.

**Every probe anchors at the repository root** (`git rev-parse --show-toplevel`), never at the
session's current directory. A session started in a subdirectory would otherwise look for
`<cwd>/.claude/` and report both repo-scoped layers absent — silently dropping the team convention
and `trailer_policy`, and producing a commit with the wrong subject shape or attribution. This
matches the root-resolution requirement
[`${CLAUDE_PLUGIN_ROOT}/reference/config-resolution.md`](../../reference/config-resolution.md)
already states for resolution itself; the probes must not disagree with it. `exec-bit-check.sh`
anchors itself the same way.

## Per-commit checklist

Run this list **for every commit**, including the second and tenth commit of a session. These are
commands, not remembered facts — steps 3–5 are the ones a long session silently stops performing.

1. **Resolve** the convention + `trailer_policy` across all three config layers (once per session
   is enough; re-resolve if a layer changed).
2. **Stage** surgically by explicit path, after checking the four pre-existing conditions below.
3. **Format** — run the discoverable formatter scoped to this commit's paths, re-stage its fixes.
4. **Exec-bit** — run `exec-bit-check.sh --fix -- <this commit's paths>`, AFTER step 3.
5. **Pre-check** the drafted subject against the resolved pattern before invoking git.
6. **Commit** via the Bash tool: `git commit -F -` heredoc-piped, `--trailer` per `trailer_policy`.
7. **Report** the resulting SHA + subject to the user.

## Purpose

Encapsulates the canonical mechanic for building a commit message that honors a subject convention,
appending a `Co-Authored-By:` trailer, and feeding the result to `git commit` via stdin — without
these failure modes:

- **PowerShell here-string syntax (`@'...'@`) inside a Bash tool call** produces `unexpected EOF` and
  triggers fallback to writing the message to `.git/<TEMP>.txt`. `.git/` is git's internal directory;
  scratch files there collide with `COMMIT_EDITMSG` and other internals.
- **`git commit -m "<multi-line>"`** flattens newlines unpredictably across shells.
- **`git add -A` / `git add .`** stages secrets, build artifacts, unrelated edits — the convention is
  surgical staging.

## Subject convention ladder

The subject convention (WHAT shape a subject must take) resolves via a ladder, checked in order:

1. **The layered `source-control.md` convention config** — user-global, tracked team, and gitignored
   personal overlay, merged per key by
   [`${CLAUDE_PLUGIN_ROOT}/reference/config-resolution.md`](../../reference/config-resolution.md).
   Resolve all three layers before using any value; a value from one layer alone is not the effective
   config. When any layer declares one, the effective `subject_pattern` (and `type_list`, when
   Conventional-Commits-shaped) is authoritative. Before pre-checking, expand `subject_pattern`: the
   literal keyword `Conventional Commits` expands to the anchored pattern in step 3 below; anything
   else is already a single anchored regex and is used as-is.
2. **The consuming project's own `CLAUDE.md`, `AGENTS.md`, rules, or commit-msg hook** — if the
   effective merged config declares no `subject_pattern` (absent from every layer, which includes the
   case where layers exist but only contribute other keys) but the project declares (or enforces via
   lefthook, husky, commitlint, or a plain `.git/hooks/`) a different convention, follow that instead.
3. **Conventional Commits (11-type vocabulary)** — the default when neither of the above is present.
   Every subject must match this anchored pattern:

```text
^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?!?: .+
```

Compliant examples:

- `feat(auth): add OAuth login flow`
- `fix(api): handle null user in /me endpoint`
- `docs: clarify rebase guidance`
- `refactor(skills)!: rename /simplify to /code-review`

The 11 types — `build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test` — come from
the Conventional Commits spec, the Angular convention, commitlint's `@commitlint/config-conventional`
source, and `amannn/action-semantic-pull-request`'s default `types` list; all four agree on this exact
set. `security` is **not** a Conventional Commits type in any of them — never add it.

When the project enforces its convention with a commit-msg git hook, that hook is the authoritative
gate regardless of which rung above resolved the pattern; this skill's pre-check exists to fast-fail
client-side before the hook round-trip. When no layer resolves a `subject_pattern` and nothing is
inferable from the project's own files, point the user at `/source-control:setup` to persist a
convention instead of re-inferring one every commit.

## Task

1. Survey working tree (`git status`, `git diff --cached --stat`) to confirm what's staged.
2. Stage the intended files — but first check each path against these four pre-existing conditions,
   *before* this step touches anything. Each is a state `git add` silently overwrites rather than
   errors on, and in three of the four `git diff --stat` reads empty, so the obvious check misses it.
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
4. Run the exec-bit check — **after** step 3, not before: a formatter re-stage in step 3 reads the
   worktree file mode, so setting the exec bit any earlier would be silently undone by that later
   `git add`.

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/commit/scripts/exec-bit-check.sh" --fix -- <path>...
   ```

   The script reports and fixes every newly-added file whose staged blob starts with a shebang while
   its staged mode is `100644`, setting the worktree bit and the index entry in the order that
   survives a later `git add`. **The pathspec is required** — `--fix` refuses an unscoped run
   (exit 2) rather than sweeping mode changes across another session's staged work; pass `--all`
   only to opt into a deliberate whole-index sweep. Rationale, cross-platform caveats, and the
   manual fallback live in [reference/exec-bit.md](reference/exec-bit.md).
5. Draft a subject + optional body, scoped to the staged diff, shaped to satisfy the active subject
   convention (default: the Conventional Commits pattern above).
6. Pre-check the subject against the pattern (fast-fail before invoking git).
7. Invoke `git commit -F -` via the Bash tool, heredoc-piped, adding `--trailer` per the trailer
   template below only when the resolved `trailer_policy` calls for one.
8. Surface the resulting commit SHA + subject to the user.

## Canonical bash form

Use the **Bash tool**, not the PowerShell tool. Bash heredoc is the canonical form across all
platforms (Git Bash, Linux, macOS).

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

PowerShell here-string is shown only for reference — `git commit -F - <message-via-stdin>` with
`@'...'@` would work in a pure PowerShell tool call, but **never mix syntaxes inside one tool
invocation**. A PowerShell `@'...'@` block inside a Bash tool call leaves the bash parser unable to
terminate the heredoc.

**Hard rules:**

- Invoke via the **Bash tool**.
- Heredoc delimiter is single-quoted: `<<'EOF' ... EOF`. Single quotes prevent `$variable` and
  backtick interpolation inside the message.
- `--cleanup=verbatim` preserves the message exactly — no auto-stripping of comments or whitespace.
- Never write the message to `.git/<TEMP>.txt`. If a real file is unavoidable, use `mktemp`.
- Never mix Bash heredoc with PowerShell `@'...'@` inside one invocation.

For a dirty shared index (concurrent sessions, pre-existing mixed WIP), the pathspec-limited form
and its staged-deletion hazards live in [reference/pathspec-commits.md](reference/pathspec-commits.md).
Default remains the plain index commit.

**The exec bit does not survive the pathspec form under `core.filemode=false`** (the Windows
default). `--only` records the working-tree mode, and with filemode off git cannot see the
`chmod +x`, so a correctly-set `100755` index entry is rebuilt as `100644`. Verified both
directions: the plain index commit preserves `100755`; the pathspec commit loses it. If this
commit includes a newly-added shebang file the exec-bit check corrected, commit that path with the
**plain index form** (splitting the commit if the rest needs a pathspec), and confirm with
`git ls-tree HEAD -- <path>` rather than trusting the index. Full detail and the two workarounds
that were tested and failed are in the spoke.

## Pre-check

Before invoking `git commit`, regex-match the drafted subject against the active convention's pattern
(default: the Conventional Commits pattern above).

On mismatch, surface the convention name and the compliant examples as actionable guidance, and ask
for a compliant subject before invoking git. The pre-check is shape-only; the project's `commit-msg`
git hook (when one exists) is the authoritative gate at commit time. The pre-check exists to save the
hook-startup floor when the drafted subject is obviously wrong, plus to give the user a fast
actionable error rather than an opaque hook failure.

## Trailer resolution

The default template is:

```text
Co-Authored-By: Claude <model> <noreply@anthropic.com>
```

**The `<model>` placeholder is filled from your own knowledge of the running session** (e.g.
`Opus 4.8`, `Fable 5`). If uncertain, invoke `/usage` to confirm before committing. There is no
environment variable that auto-fills it — the trailer is part of the message body sent to
`git commit`, not git config.

**An optional context clause** — `Co-Authored-By: Claude <model> (<context>) <noreply@anthropic.com>`,
e.g. `(1M context)` — may be added when the context window is a genuinely distinguishing fact about
the session and is known with confidence. It is **not** required, and its absence is not a defect.
Earlier versions of this skill mandated it; the mandate was removed because it matched neither the
harness's own injected guidance nor the observed practice in consuming repositories, so it was a
default that was silently ignored rather than followed.

### Which authority wins

Four sources can specify a trailer. Resolve in this order:

1. **A resolved `trailer_policy`** from any config layer — authoritative. `none` means omit
   `--trailer` from the `git commit` invocation entirely (do not append an empty or default
   trailer); a value naming a different template means substitute that template exactly. `none` and
   absence are different states.
2. **The consuming project's own conventions** (`CLAUDE.md`, `AGENTS.md`, rules) — if they specify a
   different attribution trailer, or none, follow those.
3. **Harness-injected commit guidance.** The Claude Code harness may inject its own commit
   instruction into the session, naming a `Co-Authored-By` trailer. Adopt its **shape** — this is why
   the context clause above is optional rather than mandatory — but **never copy its literal text**.
   Observed first-hand: that injected guidance can carry a **hardcoded model name that does not match
   the running session** (a `Fable 5` trailer injected into an Opus 5 session). Copying it verbatim
   writes a false provenance claim into durable git history, which is precisely the harm this
   template exists to avoid. Always fill `<model>` from actual session knowledge.
4. **This skill's default**, above.

Rung 3 is the rung earlier versions of this skill omitted entirely: the harness guidance is neither a
config layer nor a project convention, so a session receiving both it and this skill had no stated
tiebreak and silently followed whichever it saw last.

**Key spelling.** This skill emits `Co-Authored-By`. Git preserves a trailer key's case verbatim
(`git interpret-trailers` does not normalize it, and no `trailer.*` config here changes that), so
both `Co-Authored-By` and the also-common `Co-authored-by` persist exactly as written. This skill
does not rewrite an existing repository's spelling; whether to standardize on one is a consumer
convention question, expressible as a `trailer_policy` template.

## Unrelated uncommitted changes

If the working tree contains unstaged or untracked files that fall outside this commit's scope,
classify each before staging per `/pull-request create` (its unrelated-changes classification:
include / stash / separate-commit / discard). Do not duplicate that classification here; invoke
`/pull-request create` to surface it to the user.

## Staging discipline

Always `git add <specific-files>`, never `git add -A` or `git add .`. The risk is including secrets,
build artifacts, or unrelated changes that the user did not approve for this commit. If multiple
files are intentionally part of the commit, stage them by explicit list, not by wildcard — and skip
the partial-staging split per step 2 above.

Immediately after staging, run the format-before-push check and then the exec-bit check, in that
order — catch what CI would otherwise catch on the push round-trip.

## Composition policy

This skill is the single source of truth for the commit mechanic. Other skills should compose
`/commit` rather than invoking `git commit` directly — direct calls bypass the pre-check, trailer
logic, and surgical-staging discipline this skill exists to enforce.

**"Compose" means one of exactly two things, and a composing skill must name which:**

- **Re-invoke `/commit`** for the commit. This is the default and the only form that re-renders this
  skill's full content. Prefer it whenever the commit is a discrete step a user could have asked for.
- **Run the per-commit checklist above yourself**, per commit, as commands. Permitted for a workflow
  skill making many commits in one flow, where re-invocation per commit is disproportionate.

What is **not** composition is treating this skill as a convention absorbed once and thereafter
remembered. The mechanic that decays is not the shape of the commit message — that is reinforced
every commit — it is the ordered per-commit *checks*: the formatter run, the exec-bit fix, the
subject pre-check. Those produce no visible signal when skipped, so a session that has stopped
running them looks identical to one that has not, until CI says otherwise. That is the observed
failure this policy exists to prevent, not a hypothetical one.

Two properties make step 4 the cheap re-anchor for the checklist form: it is a command with an exit
code rather than a paragraph to recall, and the pre-computed probe at the top of this file surfaces
its finding before anything else is read.

Workflow skills without explicit commit semantics should report status at phase boundaries and let
the user or the next workflow stage decide commit timing; a skill with commit semantics in its
documented contract (e.g. `/pull-request create`) composes this one.

## Recorded deviations

- **Model invocation stays enabled** (`disable-model-invocation: false`, declared explicitly rather
  than left to the default). The fleet archetype for a `/commit`-shaped skill is
  `disable-model-invocation: true` — user-invoked only. This skill deliberately deviates because its
  composition design requires the model to reach it: a workflow skill that composes the commit
  mechanic cannot do so if the model may not load it. Compensating controls: surgical staging (never
  `git add -A`), the subject pre-check before any git invocation, no hook bypass, and a
  user-visible SHA + subject report after every commit.

## What this skill does NOT do

- **No `git push`** — that's `/pull-request create`.
- **No branch creation** — that's the project's branch-naming / branch-protection mechanisms (or
  `/worktree create`).
- **No PR body composition** — that's `/pull-request create`.
- **No `git merge` / `gh pr merge`** — that's `/pull-request merge`.
- **No rebase** — that's `/pull-request create`.
- **No `--no-verify` or hook bypass** — if the project's `commit-msg` hook rejects the message,
  surface the error and re-draft; never bypass.

## Reference index — load on demand

| File | Load when |
|------|-----------|
| [reference/staging-preconditions.md](reference/staging-preconditions.md) | A step-2 precondition fired and the right action is not obvious, or judging whether a new condition belongs in the set. |
| [reference/format-check.md](reference/format-check.md) | Running step 3 — formatter discovery, path scoping, the two-stage filter, partial-staging preservation. |
| [reference/exec-bit.md](reference/exec-bit.md) | Understanding or hand-running step 4 — why both the worktree bit and the index, `core.filemode` caveats, manual fallback. |
| [reference/pathspec-commits.md](reference/pathspec-commits.md) | The index holds staged work outside this commit's scope — pathspec `--only` semantics and the staged-deletion hide/restore sequence. |
| [`${CLAUDE_PLUGIN_ROOT}/reference/config-resolution.md`](../../reference/config-resolution.md) | Resolving or merging the three config layers, or interpreting a key's `none`-vs-absent state. |
