# Durable-state gather — the shared probe set

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
never an abort. These probes colour a report; they are not gates.

## Why these are gathered at run time, never pre-computed

A worktree-isolated agent **refuses any command carrying a `$`-expansion**, which made these skills
fail at load — in `handoff`'s case, in exactly the isolated sessions that most need a save-point.
Keep `$`-expansion out of the pre-compute block
(melodic-software/claude-code-plugins#1687).

Bare `$HOME` is the one form observed to survive that guard; anything else, including `${HOME}`, is
refused. Prefer a probe that needs no expansion at all.

## The probes

Each consumer names the subset it takes. Where a probe is parameterised, the consumer states the
value it uses — the differences below are deliberate and load-bearing, not drift to normalise.

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
| `continue-in-background` | yes | yes | yes | `-5` | — |
| `find-handoff` | yes | yes | — | — | — |
| `handoff` | yes | yes | yes | `-5` | — |
| `orient` | yes | yes | yes | **`-8`** | — |
| `retro` | yes | yes | yes | `-5` | yes |
| `running-retro` | yes | yes | yes | `-5` | — |
| `workflow` | — | yes | yes | `-5` | — |

`orient`'s deeper log is intentional: it synthesises a situation report and reads further back than
a skill that only stamps a save-point.

## What this block is NOT

**It is never a gate.** `continue-in-background` makes this explicit and the rule generalises: its
dirty-tree check at delivery step 1 runs its **own** commands and reads a git failure as a reason
*not* to launch. Never carry this block's shrug — or its non-`-uall` `git status` output — into a
decision that must fail closed. A probe set whose contract is "carry on when it fails" cannot also
be the thing that stops you.
