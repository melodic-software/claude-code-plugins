# Repository-context probes: why each one is shaped as it is

Detail behind the `## Repository context. Gather first` section in [SKILL.md](../SKILL.md). The
hub keeps the commands, the probe list and the combination table; this file keeps the reasons.

## The two pipes in the git calls

**The two pipes are the bound and belong in the command.** A read-time cap ("read only the summary
line") comes too late for whatever the command has already returned inline; `head` and `tail`
truncate before the result exists. What a result returns inline, and when it arrives as a saved file
instead, is [Tools reference § Output limits](https://code.claude.com/docs/en/tools-reference#output-limits).
These are ordinary body Bash calls, not pre-compute, so the one-invocation composition that applies
to the `## Pre-computed context` block does not apply here.

## Why probes 2 and 3 omit `--exclude-standard`

Probes 2 and 3 deliberately omit `--exclude-standard`, so a gitignored file is still listed: the
personal override is expected to be gitignored, and an untracked team file has to be *seen* before it
can be reported as untracked.

## Why probe 2 exists, and what a nonzero exit means

A single `--error-unmatch` call cannot separate the last two rows; it exits nonzero for both. That
is the whole reason probe 2 exists.

**A nonzero exit from probe 1 is a result, not a failure**. It answers the question, and probe 2
resolves which answer it is. The unknown-value rule is narrower than that: only a probe that could
not run at all (git unavailable, not a repository) yields an unknown value to carry on past. Never
fold `present but UNTRACKED` into "unknown". They mean opposite things, and treating the untracked
case as unknown is exactly what readmits a file the resolution rules exclude.

## Why the git lines stay out of pre-compute

Keep the repository-context git lines out of `## Pre-computed context`, so the skill stays
invocable from inside a worktree. The composition record is the
[gather-block convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/gather-block/README.md#the-pre-compute-block-runs-as-one-shell-invocation).

- **Pointer**: when an isolated session refuses a git command, fetch
  [How Claude Code enforces isolation](https://code.claude.com/docs/en/worktrees#how-claude-code-enforces-isolation)
  live.

## Why every probe anchors at `:/`

**Every repo-scoped probe anchors at the repository root**, via the `:/` magic pathspec, never at
the session's current directory. A session started in a subdirectory would otherwise look for
`<cwd>/.claude/` and report both repo-scoped layers absent. Silently dropping the team convention
and `trailer_policy`, and producing a commit with the wrong subject shape or attribution. Never
substitute a resolved root path into a probe instead: a repository root containing `$(…)`, a
backtick, or a double quote is *not* made safe by wrapping the substituted text in double quotes
(the substitution still evaluates, or the quote terminates the argument), and `:/` never
substitutes the root at all. This matches the root-resolution requirement
[`config-resolution.md`](../../../reference/config-resolution.md)
already states for resolution itself; the probes must not disagree with it. `exec-bit-check.sh`
anchors itself the same way.
