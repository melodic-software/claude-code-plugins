# Gather-block composition record

Owner doc for one harness claim that many skills in this marketplace repeat: a skill's whole
pre-compute block reaches the shell as a single invocation, so a git-bearing block is one compound
git command and a worktree-isolated session refuses it. Cite this heading instead of restating the
claim.

The record of which Bash shapes a worktree-isolated session accepts at body time and in subagents
is owned by `/source-control:worktree`, under "Accepted command shapes for body-time and subagent
Bash".

## The gather-block rule text has one home

[`block.md`](block.md) is the one home of the rule text a skill's `## Repository context. Gather
first` section carries: run each listed command as its own Bash call and send them all in parallel
in one message. [`scripts/sync-gather-block.py`](../../../scripts/sync-gather-block.py) writes it
between the `BEGIN GENERATED: gather-block` and `END GENERATED: gather-block` markers in every
`plugins/*/skills/*/SKILL.md` that carries them, and CI runs it with `--check`. A skill opts in by
carrying the markers, so they are the consumer list. The commands stay outside the markers, since
each skill gathers its own. Edit `block.md`, then run the script; never hand-edit a generated block.
A skill whose body reads none of the gathered values carries no gather section at all.

## The pre-compute block runs as one shell invocation

**Claim.** Claude Code submits the commands in a skill's `## Pre-computed context` block to the
shell as one invocation rather than one call per line. A block that carries a git command
therefore reads to a worktree-isolated session as a compound command containing git, which that
session's isolation check refuses. Git reads a skill needs on every run belong in separate body
calls, one command per call, where each is screened on its own.

**Basis.** Three sources, none of which alone settles it:

- [Skills: inject dynamic context](https://code.claude.com/docs/en/skills#inject-dynamic-context)
  documents the injection mechanism. It does not state how a block's commands are grouped into
  invocations, so the composition itself is not a documented fact.
- Worktree isolation. **Pointer**: when checking which command shapes a worktree-isolated session
  refuses, fetch
  [Worktrees: how Claude Code enforces isolation](https://code.claude.com/docs/en/worktrees#how-claude-code-enforces-isolation)
  and
  [Errors: command blocked by the worktree isolation checks](https://code.claude.com/docs/en/errors#command-blocked-by-the-worktree-isolation-checks)
  live.
- [`scripts/check-skill-precompute-compose.sh`](../../../scripts/check-skill-precompute-compose.sh)
  in this repository is the gate that encodes the observed behavior. It refuses a skill whose
  pre-compute block holds a git command together with more than one injection line, which is the
  shape that breaks only in isolated agents while continuous integration stays green.

**Verified.** The composition half, 2026-09-06, against Claude Code 2.1.263 and the skills page.

**Recheck trigger.** Any of these: the skills page gains or loses a statement about how a block's
commands are submitted to the shell; a release note names skill shell injection or worktree
isolation; or `check-skill-precompute-compose.sh` stops refusing the git-plus-multiple-lines shape.

**Scope.** The composition claim is the half this record has to defend. The isolation half is documented
upstream and stands on the worktrees page alone.
