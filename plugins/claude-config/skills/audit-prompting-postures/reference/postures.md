# Posture catalog

Ten postures. Each row: the applicability predicate (which component purposes it binds), what
counts as present, and the guide pointer that owns the recommended wording. Pointers only —
wording is fetched live per SKILL.md Phase A; the recheck trigger for every row is a change to its
cited section.

Guide root: <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices>
(sections cited by heading). Model subpages cited by page + heading where a row needs one.

## Purpose classification vocabulary

Classify each component by what its body has the model DO (multiple or none):

- **orchestrating** — spawns or coordinates subagents/workers/teams
- **code-changing** — edits code, implements, refactors, fixes
- **codebase-answering** — answers questions about existing code
- **long-running** — states or invites autonomous/unattended/multi-hour operation
- **destructive-capable** — can delete, reset, force-push, publish, or mutate shared state
- **context-surfacing** — displays token budgets, context occupancy, or remaining-window figures
- **multi-window** — spans sessions/windows via saved state, handoffs, or resumability
- **parallelism-steering** — instructs when/how to parallelize tool calls
- **user-gated** — interactive flow with genuine decision gates only the user can answer

## Postures

### P1 — Delegation criteria and caps

- **Predicate:** orchestrating.
- **Present when:** the component states when delegation is and is not warranted, or caps
  spawn/concurrency deterministically. Either satisfies.
- **Pointer:** main page, "Subagent orchestration"; Opus 5 subpage, "Controlling subagent
  spawning"; Opus 4.8 subpage, "Controlling subagent spawning".

### P2 — Minimal-scope guardrail

- **Predicate:** code-changing.
- **Present when:** the component bounds scope to what was asked (no unrequested features,
  abstractions, defensive code, or cleanup beyond the task).
- **Pointer:** main page, "Overeagerness"; Fable 5 subpage, "Consider all effort levels"
  (anti-overengineering block).

### P3 — Anti-test-gaming guardrail

- **Predicate:** code-changing AND the flow involves making tests pass.
- **Present when:** the component states that the fix targets production code and general
  correctness, not the test's assertion or the specific test inputs.
- **Pointer:** main page, "Avoid focusing on passing tests and hardcoding".

### P4 — Investigate-before-answering grounding

- **Predicate:** codebase-answering.
- **Present when:** the component requires reading the referenced code before claiming anything
  about it.
- **Pointer:** main page, "Minimizing hallucinations in agentic coding".

### P5 — Progress-claim grounding

- **Predicate:** long-running.
- **Present when:** the component ties progress/status claims to tool-result evidence and requires
  naming unverified work as unverified.
- **Pointer:** Fable 5 subpage, "Ground progress claims during long runs".

### P6 — Autonomy or checkpoint posture

- **Predicate:** long-running (autonomy posture) or user-gated (checkpoint posture). A
  report-only flow ending at a human gate is NOT-APPLICABLE (see SKILL.md Gotchas).
- **Present when:** an autonomous component tells the model not to stall on questions mid-run and
  when a turn may end; an interactive one names the gates worth stopping at.
- **Pointer:** Fable 5 subpage, "Rare cases of early stopping" (autonomous) and "Strong
  instruction following" (checkpoint block).

### P7 — Destructive-action confirmation

- **Predicate:** destructive-capable.
- **Present when:** hard-to-reverse, shared-system, or destructive actions require confirmation or
  an equivalent mechanical gate, and obstacles must not be shortcut destructively. A deny-by-
  default hook or script gate satisfies this without any prose.
- **Pointer:** main page, "Balancing autonomy and safety".

### P8 — Context-budget reassurance

- **Predicate:** context-surfacing.
- **Present when:** the surfaced figure is accompanied by do-not-wrap-up-early framing (or the
  component deliberately avoids surfacing raw countdowns at all — the stronger form).
- **Pointer:** main page, "Context awareness and multiwindow workflows"; Fable 5 subpage, "Rare
  cases of context-budget concern".

### P9 — Multi-window state guidance

- **Predicate:** multi-window.
- **Present when:** the component prescribes durable structured state (files/git) and how a fresh
  window re-grounds, rather than relying on conversational memory.
- **Pointer:** main page, "Workflows across multiple context windows" and "State management best
  practices".

### P10 — Parallel-tool-call steering

- **Predicate:** parallelism-steering.
- **Present when:** the steering distinguishes independent calls (parallelize) from dependent ones
  (sequence, never placeholder-guess parameters).
- **Pointer:** main page, "Optimize parallel tool calling".
