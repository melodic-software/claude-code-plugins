# Run the orchestrator on the session model, Opus by default

- Status: accepted
- Date: 2026-11-12
- Refs: owner decision of 2026-11-12 (Rethinking Claude Code best practices, Q6, Q16, Q24)

## Context

Three surfaces said which model coordinates a multi-agent run, each on its own basis:
`plugins/multi-agent/reference/defaults.yaml` (orchestrator `model: inherit`, basis judgment),
the loop-lane contract's model tiers (`docs/contracts/loop-lane/README.md`, Opus "Orchestrator by
default"), and the owner's user instructions (Anthropic found Fable in Opus's orchestrator place
cost more for about the same score).

Anthropic's cost guide measured that case directly: Fable 5.2 as orchestrator in Opus 5.5's place
cost more and scored about the same
([Optimizing for cost and intelligence, orchestrator strategy](https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence#orchestrator-strategy-delegate-bulk-work)).
The model-choice guide's worked example is an Opus 5.5 lead over Sonnet 5.5 workers
([Which Claude model should you build with?](https://claude.dev/blog/which-claude-model-should-you-build-with)),
and Claude Code Projects default both the coordinator and its threads to Opus.

Dissent: Lydia Hallie's talk "Rethinking Claude Code Best Practices"
([video](https://www.youtube.com/watch?v=vlfCjWuv4es)) puts a Fable lead over Opus threads. No
documented default states that split, and the measurement above does not support it as a default.

## Decision

1. The orchestrator of an interactive session or a multi-agent run is the session model
   (`inherit`).
2. Opus is the default session model for that work; Fable is chosen for ambitious, open-ended or
   long-horizon work where Opus falls short.
3. This record is the one source for those two points; `defaults.yaml` and the loop-lane contract
   cite it.

Out of scope: the loop lanes' frontier ("Fable") rung, which another decision owns; this record
does not change it.

Rejected: a Fable orchestrator over Opus workers wherever Fable is available (the talk), for the
measured cost with no score gain; leaving three surfaces with three bases; running a routing eval
first, which is the route to take only to move the default off Opus.

## Consequences

- No running behavior changes: `inherit` and the strong-tier default were already in force.
- A later change to the orchestrator default edits this record and the two citations together.

## Revisit triggers

- A new model release, or a change to the cost guide's orchestrator strategy section.
- A routing eval in this repository that shows a Fable lead beating an Opus lead on our tasks.
