# Gather-block composition record

The owner record for one harness claim that many skills in this marketplace repeat: a skill's
whole pre-compute block reaches the shell as a single invocation, so a git-bearing block is one
compound git command and a worktree-isolated session refuses it. Cite this heading instead of
restating the claim.

## The pre-compute block runs as one shell invocation

**Claim.** Claude Code submits the commands in a skill's `## Pre-computed context` block to the
shell as one invocation rather than one call per line. A block that carries a git command
therefore reads to a worktree-isolated session as a compound command containing git, which that
session's isolation check refuses. Git reads a skill needs on every run belong in separate body
calls, one command per call, where each is screened on its own.

**Basis.** Three sources, none of which alone settles it:

- [Extend Claude with skills](https://code.claude.com/docs/en/skills) documents the injection
  mechanism, the inline and fenced `!` forms, the shell each runs under, and the abort on failure.
  It does not state how a block's commands are grouped into invocations, so the composition itself
  is not a documented fact.
- [Worktrees](https://code.claude.com/docs/en/worktrees#how-claude-code-enforces-isolation)
  documents the refusal that makes the composition matter. An isolated session screens a command's
  working directory and any git redirect into the main checkout, and "Claude Code also blocks a
  command it can't verify stays inside the worktree." The check fails closed, so a command it
  cannot verify is refused whether or not it would have reached the main checkout.
- `scripts/check-skill-precompute-compose.sh` in this repository is the gate that encodes the
  observed behavior. It refuses a skill whose pre-compute block holds a git command together with
  more than one injection line, which is the shape that breaks only in isolated agents while
  continuous integration stays green.

**Verified.** 2026-09-06, against Claude Code 2.1.263 and the two pages named above as fetched
that day.

**Recheck trigger.** Any of these: the skills page gains or loses a statement about how a block's
commands are submitted to the shell; the worktrees page stops carrying the fail-closed sentence
quoted above; a release note names skill shell injection or worktree isolation; or
`check-skill-precompute-compose.sh` stops refusing the git-plus-multiple-lines shape.

**Scope.** The composition claim is the load-bearing half. The isolation half is documented
upstream and stands on the worktrees page alone.
