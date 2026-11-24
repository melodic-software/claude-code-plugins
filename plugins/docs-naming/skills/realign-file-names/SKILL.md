---
description: "Apply a file-name rename plan one file at a time, one human acceptance each: git mv, rewrite only the reference shapes each citing file's tier allows, rebuild generated records, and sweep for stragglers. Refuses a blanket yes, a range, a glob, and 'all'. Use when: 'apply the rename plan', 'apply FN-...', 'do the docs renames', 'rename these files', 'execute the file-name findings', 'accept that rename'. Needs a plan from docs-naming:audit-file-names; never commits."
argument-hint: "[FN-xxxxxxxx ...] [--repo <repo> ...]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/apply-rename.sh:*)", "Bash(git branch --show-current:*)", "Bash(git status --porcelain:*)", "Bash(git rev-parse:*)", "Bash(git diff --name-status:*)", "Bash(git grep:*)", "Read", "Skill"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Apply a file-name rename plan, one acceptance per file
---

## Repository context. Gather first

<!-- BEGIN GENERATED: gather-block. Edit docs/conventions/gather-block/block.md, then run scripts/sync-gather-block.py -->
Run each command below as its own Bash call, all sent together in one message ([worktree isolation](https://code.claude.com/docs/en/worktrees#how-claude-code-enforces-isolation)).
Keep any bound in the command's own pipe ([output limits](https://code.claude.com/docs/en/tools-reference#output-limits)).
Unless this section says otherwise, treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as body calls, never `## Pre-computed context` lines ([gather-block convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/gather-block/README.md#the-pre-compute-block-runs-as-one-shell-invocation)).
<!-- END GENERATED: gather-block -->

- Current branch, `git branch --show-current`
- Working tree status (empty = clean), `git status --porcelain | head -20`
- Repository root, `git rev-parse --show-toplevel`

## Purpose

`/docs-naming:audit-file-names` decided what should be renamed and what each
citation of it may become. This skill is the hand that does it, and the gate
that keeps a human in front of every one.

A rename is not one edit. It is a tracked move plus a rewrite of every reference
the tier rules allow, across files nobody opened, with a generated record and a
frozen changelog somewhere in the set. That is exactly the shape of change an
operator approves in bulk and regrets in review. So the unit here is one file,
and the acceptance is one file's worth.

## Read these before applying anything

| Read | For |
|---|---|
| [`context/apply-recipe.md`](context/apply-recipe.md) | the present-apply-sweep-verify loop, and what a decline offers |
| [`../../context/file-name-findings.md`](../../context/file-name-findings.md) | where the plan lives, the record's fields, its status arc, and why `applying` resumes |
| [`../audit-file-names/context/tiers.md`](../audit-file-names/context/tiers.md) | the form table to print before each acceptance |

## One acceptance is one finding

Each explicit `FN-xxxxxxxx` in the argument is one acceptance. Nothing else is.

**Refuse out loud, then re-present the current finding**, when the operator
offers a range (`FN-a through FN-d`), a glob, a count (`the first five`), `all`,
`everything`, `the rest`, `yes to all`, or a bare `go ahead` standing in for the
set. Say what was refused and why: a blanket yes is one decision standing in for
many, and the rename this skill is about to make is the one the operator has not
read yet.

Refusing is not a stall. Present the current finding again, in full, and ask for
it alone. An operator who genuinely wants twelve renames gives twelve answers,
and each one is cheap because the presentation is already on screen.

This is a gate on the acceptance, not on the operator. A finding they already
accepted is applied without asking a second time. It is still presented first, the
recipe's step 1 in full, before `apply-rename.sh` runs; only the question is skipped.

## Find the plan, and check it belongs here

Read the artifact from the home `../../context/file-name-findings.md` "Where it
lives" defines. A plan looked for anywhere else is reported as "no plan found"
for a plan that exists.

The artifact's `branch:` frontmatter proves which branch it belongs to, not the
directory it sits in. A mismatch against the current branch is a refusal with
"re-audit here" as the remedy; the script checks the same thing and exits 1.

`head:` is recorded and never checked. A consumer commits between accepted
renames, so an equality test on it would block the walk after the first one.

## Over several repositories

With no target form, the run applies this checkout's plan, as it always has. A
target form selects the repositories an audit over several of them planned,
resolved as
[`${CLAUDE_PLUGIN_ROOT}/reference/target-scope.md`](../../reference/target-scope.md)
"Target forms" and "Resolving repositories" say. What differs here:

- **An acceptance names its repository.** One id can name a file in each
  repository, so an acceptance is `owner/name FN-xxxxxxxx`. With more than one
  repository in scope, a bare id is a question, not an acceptance: ask which
  repository it means.
- **Apply in the audit's worktree.** The plan is checkout-local, so it is not in
  the clone a repository resolves to. The audit keeps one worktree per
  repository, on the branch `docs-naming/file-names`: select the entry on that
  branch in `git -C <root> worktree list --porcelain`, never another worktree of
  the clone, and pass it as `--root`. A repository with no worktree on that
  branch, or no plan in it, is reported as "no plan found" and skipped.
- **One repository at a time.** Finish one repository's findings and its closing
  pass before the next starts. Its renames stay uncommitted in that worktree, per
  "Writes stay per repository".

## Run the loop

For each accepted finding, in the order the operator accepted them, walk
[`context/apply-recipe.md`](context/apply-recipe.md) top to bottom: present,
apply, sweep for stragglers, verify. Do not reorder it and do not batch a step
across findings, particularly the sweep: a straggler found after four renames
cannot be attributed to one of them.

The sweep covers the reference forms the plan did not classify. If
`docs-hygiene` is enabled it runs `/docs-hygiene:rename-references` (if enabled); without
it, the recipe's own sweep over the tracked files does the same job.

Report the script's five output rows as it wrote them. `DRIFTED` above zero is
surfaced with the sites it named, not folded into a total.

Every `apply-rename.sh` call, the recipe's included, takes `--user-config` with
this plugin's `file_names` option, `${user_config.file_names}`, as one
single-quoted argument (escape any single quote in it). An empty value or the
literal `${user_config.…}` placeholder means unset.

- **Pointer**: when checking where a saved option value reaches, fetch
  [plugins manifest reference § Reference a saved value](https://code.claude.com/docs/en/plugins/manifest-reference#reference-a-saved-value)
  live.

When a run of several findings ends, run the closing pass once:

```bash
${CLAUDE_SKILL_DIR}/scripts/apply-rename.sh --regenerate-only --root <repo> --user-config '<option>'
```

A generated record is rebuilt per finding only when the plan recorded a site
inside it, so the last rename of a run can leave a derived sample or index
stale. This settles that, and is a no-op on a tree already current.

## Completion criteria

The run is done when every accepted finding reads `- **Status:** applied`, the
tree carries one `R` line per applied pair with no changed path outside those
records' site tables, the orphan sweep has run for every applied or `applying`
pair, and the working tree is left uncommitted for the operator to review.

A finding the operator declined reads `declined`, and the durable
`exempt_paths` entry was offered and not taken. A finding whose file moved under
the plan reads `blocked`, and the re-audit that settles it has been named.

## What this skill does NOT do

- **Commit, stage beyond what `git mv` stages, push, or open a PR.** The diff is
  left for the operator to read. A rename sweep is exactly the change that
  should be reviewed before it is recorded.
- **Bump a version or write a changelog entry.** A renamed file inside a
  versioned unit usually needs both (or a changelog fragment, where the project
  releases from fragments); that is the consuming project's release
  convention, done by hand, and this skill says so rather than guessing at it.
- **Re-derive a form, a tier, or an action.** The plan's record is the
  instruction set. A judgment made here would be a second opinion the operator
  never saw.
- **Edit a `review` site.** An ambiguous bare stem is escalated with its line and
  left alone, whatever the operator says about the finding as a whole.
- **Hand-edit a site the apply skipped, even on request.** A frozen-tier site stays as
  written because its tier's declared form says so; changing that form is the operator's
  configuration decision. A `review` site is shown with its file and line for the operator
  to edit. Decline each such request separately, in plain words, and still apply the
  accepted finding.
- **Edit a generated file.** Its declared command rebuilds it.
- **Re-audit, or patch a stale plan.** A plan whose tree moved under it is
  re-audited by the sibling.
- **Accept a finding on the operator's behalf**, including one whose apply it
  just refused.

## Related

- Tree drifted or finding blocked: /docs-naming:audit-file-names.
- Enforce the rule going forward: /docs-naming:generate-file-name-gate.
- Ad-hoc reference sweep outside a plan: /docs-hygiene:rename-references.

## Gotchas

- **A blanket yes is the failure this skill exists to prevent.** The cost of
  refusing one is a sentence; the cost of taking one is a diff nobody read
  across files nobody opened.
- **The drift guard is per site, not per file.** In any real doc tree the
  renamed files cite each other, so applying the first finding edits a file the
  second names. A file-level hash would block every rename after the first.
- **Existence is asked of the git index, never the filesystem.** On a
  case-insensitive checkout `[[ -e docs/foo.md ]]` is true while only
  `docs/Foo.md` exists, so a filesystem test refuses every case-only rename on
  exactly the platforms the rule protects.
- **An interrupted run resumes; it is not a drifted tree.** An old path that is
  gone while the new path is present and the record reads `applying` is a
  half-finished apply. Re-run the same id.
- **`DRIFTED` is not a smaller `EDITED`.** It means the recorded line no longer
  carries the old name, so the audit's decision no longer describes that site.
  Re-audit; do not hand-edit the sites the script declined to touch.
- **A bare stem is rewritten anchored, a basename is not.** The audit only
  records a bare-stem site where the surrounding characters are not name
  characters; an unanchored apply would reach inside a longer name and point it
  at a file nobody renamed.
- **The closing `--regenerate-only` pass is not optional.** Skipping it leaves
  the last renamed file stale inside a generated record, which is the one change
  a reviewer will not see.
- **Run it against the tree you mean.** `--root` takes the checkout; inside a
  second worktree, pass it, or run from that worktree.
