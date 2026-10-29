# Gather-block composition record

Owner doc for one harness claim that many skills in this marketplace repeat: a skill's whole
pre-compute block reaches the shell as a single invocation, so a git-bearing block is one compound
git command and a worktree-isolated session refuses it. Cite this heading instead of restating the
claim.

The record of which Bash shapes a worktree-isolated session accepts at body time and in subagents
is owned by `/source-control:worktree`, under "Accepted command shapes for body-time and subagent
Bash".

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
- [Worktrees: how Claude Code enforces isolation](https://code.claude.com/docs/en/worktrees#how-claude-code-enforces-isolation)
  documents the checks an isolated session applies. The one this record rests on is the
  command-shape check.
  [Errors: command blocked by the worktree isolation checks](https://code.claude.com/docs/en/errors#command-blocked-by-the-worktree-isolation-checks)
  lists the refusal reasons, including which expansions are refused in a command that never names
  git. **Pointer:** both sections. **As of:** 2026-10-17. **Recheck trigger:** a re-fetch of
  either section that drops the command-shape check or changes the expansions it names.
- [`scripts/check-skill-precompute-compose.sh`](../../../scripts/check-skill-precompute-compose.sh)
  in this repository is the gate that encodes the observed behavior. It refuses a skill whose
  pre-compute block holds a git command together with more than one injection line, which is the
  shape that breaks only in isolated agents while continuous integration stays green.

**Verified.** The composition half, 2026-09-06, against Claude Code 2.1.263 and the skills page.
The isolation half, 2026-10-11, against the worktrees section named above.

**Recheck trigger.** Any of these: the skills page gains or loses a statement about how a block's
commands are submitted to the shell; the worktrees page drops the command-shape check or stops
scoping it to git; a release note names skill shell injection or worktree isolation;
or `check-skill-precompute-compose.sh` stops refusing the git-plus-multiple-lines shape.

**Scope.** The composition claim is the load-bearing half. The isolation half is documented
upstream and stands on the worktrees page alone.
