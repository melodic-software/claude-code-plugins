# Durable-state gather: the shared probe set

Owner doc for the small set of read-only probes session-flow skills run before they do anything
else. Seven skills carried a near-identical copy of this block; `discipline:point-dont-copy` pins
the duplication threshold at two, so the text lives here and each consumer cites it and names the
probes it takes.

Consumers: `continue-in-background`, `find-handoff`, `handoff`, `orient`, `retro`, `running-retro`,
`workflow`. A skill that needs durable state and is not on that list should route to
`/session-flow:orient` rather than adding an eighth copy.

## Two standing rules

**Collect with individual Bash calls, one command per call.** Not a compound command, not a
pre-compute block.

**Treat any failure as an unknown value and carry on.** A probe that cannot run yields "unknown",
never an abort. These probes color a report; they are not gates.

## Why these are gathered at run time, never pre-computed

A `$`-expansion in a pre-compute line made these skills fail at load, in `handoff`'s case in
exactly the isolated sessions that most need a save-point. Keep `$`-expansion out of the
pre-compute block (melodic-software/claude-code-plugins#1687). The accepted and refused shapes for
worktree-isolated Bash are owned by `/source-control:worktree`, under "Accepted command shapes for
body-time and subagent Bash".

That heading holds the bare `$HOME` exception and cites this file for its basis. The observation:
a bare `$HOME` is the one variable seen to pass the guard in every position. Other names are
unsettled, and any braced form, including `${HOME}`, is refused. Prefer a probe that needs no
expansion at all.

- **Pointer**: the pass and refuse table in
  [melodic-software/claude-code-plugins#1687, "Final state of the rule"](https://github.com/melodic-software/claude-code-plugins/issues/1687#issuecomment-5086783455),
  which supersedes the thread's earlier "bare `$HOME` only" comments.
- **As of**: 2026-10-11
- **Recheck trigger**: a release note changes how worktree-isolated agents treat `$`-expansion,
  or a pre-compute block using `$HOME` fails to load.

## The probes

Each consumer names the subset it takes. Where a probe is parameterised, the consumer states the
value it uses. The differences below are deliberate, not drift to normalize.

| Probe | Command | Notes |
|---|---|---|
| `session-id` | `printenv CLAUDE_CODE_SESSION_ID` | Identifies the session for ledger and save-point naming |
| `branch` | `git branch --show-current` | The only probe every consumer takes |
| `status` | `git status --porcelain` | Read **at most the first 20 entries**. Note this is *not* `-uall` |
| `recent-commits` | `git log --oneline -<N>` | `N` is the consumer's choice; see the table below |
| `changed-files` | `git diff --name-only HEAD` | Staged and unstaged together |

### Who takes what

| Consumer | session-id | branch | status | recent-commits | changed-files |
|---|---|---|---|---|---|
| `continue-in-background` | yes | yes | yes | `-5` | no |
| `find-handoff` | yes | yes | no | no | no |
| `handoff` | yes | yes | yes | `-5` | no |
| `orient` | yes | yes | yes | **`-8`** | no |
| `retro` | yes | yes | yes | `-5` | yes |
| `running-retro` | yes | yes | yes | `-5` | no |
| `workflow` | no | yes | yes | `-5` | no |

`orient`'s deeper log is intentional: it synthesizes a situation report and reads further back than
a skill that only stamps a save-point.

## What this block is NOT

**It is never a gate.** `continue-in-background` makes this explicit and the rule generalizes: its
dirty-tree check at delivery step 1 runs its **own** commands and reads a git failure as a reason
*not* to launch. Never carry this block's shrug, or its non-`-uall` `git status` output, into a
decision that must fail closed. A probe set whose contract is "carry on when it fails" cannot also
be the thing that stops you.
