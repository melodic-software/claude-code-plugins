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

- [Skills: inject dynamic context](https://code.claude.com/docs/en/skills#inject-dynamic-context)
  documents the injection mechanism. It does not state how a block's commands are grouped into
  invocations, so the composition itself is not a documented fact.
- [Worktrees: how Claude Code enforces isolation](https://code.claude.com/docs/en/worktrees#how-claude-code-enforces-isolation)
  documents the checks an isolated session applies. The one this record rests on is the
  command-shape check, which is scoped to git: a `$` expansion that never runs git is not that
  check. **Pointer:** that section. **As of:** 2026-10-11. **Recheck trigger:** a re-fetch of that
  section that drops the command-shape check or stops scoping it to git.
- `scripts/check-skill-precompute-compose.sh` in this repository is the gate that encodes the
  observed behavior. It refuses a skill whose pre-compute block holds a git command together with
  more than one injection line, which is the shape that breaks only in isolated agents while
  continuous integration stays green.

**Verified.** The composition half, 2026-09-06, against Claude Code 2.1.263 and the skills page.
The isolation half, 2026-10-11, against the worktrees section named above.

**Recheck trigger.** Any of these: the skills page gains or loses a statement about how a block's
commands are submitted to the shell; the worktrees page drops the command-shape check or stops
scoping it to git; a release note names skill shell injection or worktree isolation;
or `check-skill-precompute-compose.sh` stops refusing the git-plus-multiple-lines shape.

**Scope.** The composition claim is the load-bearing half. The isolation half is documented
upstream and stands on the worktrees page alone.

## Accepted command shapes for body-time and subagent Bash

The owner record for which Bash shapes a worktree-isolated session runs without a retry. It covers
every Bash call in the session, a skill's body steps and each subagent it spawns, not only a
pre-compute block. A worker brief that sends a subagent into an isolated session points here
instead of restating the shapes.

**Accepted.** One plain command per call, with a literal absolute path and no `$` expansion. Give
each git read its own call. Read a file with the Read tool rather than `sed`, `cat` or `head` over
a path held in a variable.

**Refused, by layer.** Each class below comes from Claude Code's built-in isolation guard. None of
the refusal texts ("cannot be shown not to be git", "computed at runtime") appears in this
repository's hooks.

| Class | Rewrite | Basis |
| --- | --- | --- |
| A command the guard cannot show keeps any git inside the worktree: `${!name}`, `${ command; }`, a command name computed at runtime, syntax it cannot parse | Split into plain, separate commands and spell each value literally | Command shape check on the worktrees page; errors page "Command blocked by the worktree isolation checks" |
| A compound command with a path word the guard reads as git, such as `github` in a ghq path (`~/repos/github.com/...`) or a slice path ending in `git` | Run it as one plain call | Owner decision on #5673, from one machine's hook list; the slice-path probe in `plugins/discovery/reference/parent-contract.md` allowed the same path as one plain command. The upstream pages do not document path-word matching |
| `eval` as a command word | Stop and give the user the exact command to run | `/evals:plugin-eval`; upstream watch in #5696 |

**Not settled.** The pre-compute record says Claude Code 2.1.257 stopped refusing a `$VAR` read
that never touches git. A 2026-09-30 refusal of `sed -n ... $F`, with `F` a scratchpad file,
contradicts it, and no probe from an isolated session on the current release has reconciled the
two. Keep `$` out of worker commands until one does.

**Basis.** The worktrees page "How Claude Code enforces isolation" (the command shape check, which
covers subagents and background sessions) and the errors page section named above, both read
2026-10-17. **Recheck trigger.** Either section changes the expansions it names or the scope of the
check, or a probe from an isolated session runs `sed -n 1,5p` on a `$F` scratchpad path.
