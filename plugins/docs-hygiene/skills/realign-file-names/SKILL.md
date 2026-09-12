---
description: "Execute a file-name rename plan one file at a time, behind one human acceptance each: moves the file with git mv, rewrites only the reference shapes the citing file's tier allows, leaves frozen and ambiguous sites listed and untouched, rebuilds generated records by their declared command, and sweeps for stragglers per pair. Refuses a blanket yes, a range, a glob, and 'all'. Use when: 'apply the rename plan', 'apply FN-...', 'do the docs renames', 'rename these files', 'execute the file-name findings', 'accept that rename'. Requires a plan from docs-hygiene:audit-file-names; never commits, never bumps a version."
argument-hint: "[FN-xxxxxxxx ...]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/apply-rename.sh:*)", "Bash(git branch --show-current:*)", "Bash(git status --porcelain:*)", "Bash(git rev-parse:*)", "Bash(git diff --name-status:*)", "Read", "Skill"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Apply a file-name rename plan, one acceptance per file
---

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never
combined into a single invocation:

- Current branch, `git branch --show-current`
- Working tree status (empty = clean), `git status --porcelain | head -20`
- Repository root, `git rev-parse --show-toplevel`

The pipe is the bound and belongs in the command. A read-time cap bounds
nothing: the Bash tool returns the command's complete output into context before
there is anything to decide about.

Treat a failure as an unknown value and carry on.

## Purpose

`/docs-hygiene:audit-file-names` decided what should be renamed and what each
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
| [`../../context/file-name-findings.md`](../../context/file-name-findings.md) | the record's fields, its status arc, and why `applying` resumes |
| [`../audit-file-names/context/tiers.md`](../audit-file-names/context/tiers.md) | the form table to print before each acceptance |
| [`../../reference/topic-docs.md`](../../reference/topic-docs.md) | where the plan lives, and the rung order that resolves it |

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
accepted is applied without asking a second time.

## Find the plan, and check it belongs here

Resolve the artifact's home through the plugin's topic-docs binding. Never
compose the documented default's shape yourself: a consumer whose memory root is
configured elsewhere gets "no plan found" for a plan that exists.

The artifact's `branch:` frontmatter proves which branch it belongs to, not the
directory it sits in. A mismatch against the current branch is a refusal with
"re-audit here" as the remedy; the script checks the same thing and exits 1.

`head:` is recorded and never checked. A consumer commits between accepted
renames, so an equality test on it would block the walk after the first one.

## Run the loop

For each accepted finding, in the order the operator accepted them, walk
[`context/apply-recipe.md`](context/apply-recipe.md) top to bottom: present,
apply, sweep for stragglers, verify. Do not reorder it and do not batch a step
across findings, particularly the sweep: a straggler found after four renames
cannot be attributed to one of them.

Report the script's five output rows as it wrote them. `DRIFTED` above zero is
surfaced with the sites it named, not folded into a total.

When a run of several findings ends, run the closing pass once:

```bash
${CLAUDE_SKILL_DIR}/scripts/apply-rename.sh --regenerate-only --root <repo>
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
  versioned unit usually needs both; that is the consuming project's release
  convention, done by hand, and this skill says so rather than guessing at it.
- **Re-derive a form, a tier, or an action.** The plan's record is the
  instruction set. A judgment made here would be a second opinion the operator
  never saw.
- **Edit a `review` site.** An ambiguous bare stem is escalated with its line and
  left alone, whatever the operator says about the finding as a whole.
- **Edit a generated file.** Its declared command rebuilds it.
- **Re-audit, or patch a stale plan.** A plan whose tree moved under it is
  re-audited by the sibling.
- **Accept a finding on the operator's behalf**, including one whose apply it
  just refused.

## Next

`/docs-hygiene:rename-references audit orphans <old> to <new>`

Per applied pair, for the reference forms the plan's sweep does not classify.

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
