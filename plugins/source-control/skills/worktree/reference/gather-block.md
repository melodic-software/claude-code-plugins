# Gather-block composition record

The claim that a skill's whole pre-compute block reaches the shell as a single invocation is
recorded in a repository convention; the first section below points there. The second section is the owner
record for the Bash shapes a worktree-isolated session accepts.

## The pre-compute block runs as one shell invocation

The record (claim, basis, as-of date and recheck trigger) lives in the
[gather-block convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/gather-block/README.md#the-pre-compute-block-runs-as-one-shell-invocation),
"The pre-compute block runs as one shell invocation". Cite it there.

## Accepted command shapes for body-time and subagent Bash

The owner record for which Bash shapes a worktree-isolated session runs without a retry. It covers
every Bash call in the session (a skill's body steps and each subagent it spawns), not only a
pre-compute block. A worker brief that sends a subagent into an isolated session points here
instead of restating the shapes.

**Accepted.** One plain command per call, with a literal absolute path and no `$` expansion other
than a bare `$HOME`, which the guard accepts per the observation
`/session-flow:handoff` records for its run-time gather. Give
each git read its own call. Read a file with the Read tool rather than `sed`, `cat` or `head` over
a path held in a variable.

**Refused.** The first and third classes come from Claude Code's built-in isolation guard;
the second is attributed to it by owner decision (see its basis). None of the refusal texts quoted
in #5673 appears in this repository's hooks.

| Class | Rewrite | Basis |
| --- | --- | --- |
| A command whose text the guard cannot verify keeps any git inside the worktree; the errors section lists the shapes | Split into plain, separate commands and spell each value literally | [Worktrees: command shape](https://code.claude.com/docs/en/worktrees#how-claude-code-enforces-isolation); [Errors: command blocked by the worktree isolation checks](https://code.claude.com/docs/en/errors#command-blocked-by-the-worktree-isolation-checks) |
| A compound command with a path word the guard reads as git, such as `github` in a ghq path (`~/repos/github.com/...`) or a slice path ending in `git` | Run it as one plain call | Owner decision on #5673, from one machine's hook list; the slice-path probe in #6067 allowed the same path as one plain command. The upstream pages do not document path-word matching |
| `eval` as a command word | Stop and give the user the exact command to run | `/evals:plugin-eval`; upstream watch in #5696 |

**Not settled.** The pre-compute record says Claude Code 2.1.257 stopped refusing a `$VAR` read
that never touches git. The #5673 report of a 2026-09-30 refusal of `sed -n ... $F`, with `F` a scratchpad file,
may contradict it; the report names no Claude Code release or full command, so it could predate the
fix or have set `F` in the same compound command. No probe from an isolated session on the current release has reconciled the
two. Keep `$` other than a bare `$HOME` out of worker commands until one does.

**Basis.** The two upstream sections linked in the table, both read 2026-10-17, and, for the bare
`$HOME` exception, the observation `/session-flow:handoff` records for its run-time gather (as of
2026-10-11, citing melodic-software/claude-code-plugins#1687). **Recheck trigger.** Either section
changes the expansions it names or the scope of the check, a release note changes how
worktree-isolated agents treat `$`-expansion, or a probe from an isolated session runs
`sed -n 1,5p` on a `$F` scratchpad path.
