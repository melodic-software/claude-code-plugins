# Off-thread work — inventory kinds and the inspect-real-state invariant

Shared by the session-flow skills that reason about work running outside the
main thread. This file owns two things every one of them needs identically —
**what counts as off-thread work**, and **the rule that its state is read, never
assumed**. Each citing skill adds only its own action on top: `keep-going`
resumes it, `orient` reports it at a glance, and the retire/reconcile skill
prunes the finished. This file owns neither the action nor the autonomy gate —
those differ per skill (different blast radii) and stay in each `SKILL.md`.

## What counts as off-thread work

Work running outside the current thread — enumerate whatever mechanisms the
current harness exposes:

- background tasks and background shell commands;
- monitors;
- scheduled / cron tasks;
- dynamic workflows;
- spawned subagents.

Treat that list as **examples of the kinds** to look for, not a fixed
catalogue. The tool surface evolves; the specific tools that hold off-thread
work change over time. Inventory what exists now, not only the mechanisms named
here.

## Inspect real state — never assume

For each item, read its **actual** state from the source of truth: task output,
subagent transcript, monitor status, journals, shell logs. Do not infer "it
probably finished" or "it probably died" — the artifact is the only thing that
tells you which. Every status claim a citing skill makes is grounded in a fresh
read of the real artifact, not a remembered or inferred one.

This is the floor. A skill that must judge liveness before acting — is a
slow-looking job progressing or hung — layers its own richer active-verification
protocol on top (see `keep-going`'s "Active-verification protocol"); this file
establishes only that the judgement starts from the real artifact.
