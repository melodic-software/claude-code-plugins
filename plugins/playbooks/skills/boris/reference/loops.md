# Loops — Sections 100–103

The ClaudeDevs guide *"Getting started with loops"* (Part 19, July 6, 2026, written by Delba de Oliveira). A **loop** is an agent repeating cycles of work until a stop condition is met; everything from a single prompt to a cloud routine is one. They differ by trigger, stop condition, the primitive that runs them, and the task that fits.

## 100. The Four Loops — A Taxonomy

- **Turn-based** (the agentic loop) — a prompt triggers it; it stops when Claude judges the task done. Short one-off tasks. You hand off **the check**.
- **Goal-based** (`/goal`) — a prompt triggers it; it stops when the goal is met or a turn cap trips. Tasks with verifiable exit criteria. You hand off **the stop condition**.
- **Time-based** (`/loop`, `/schedule`) — a time interval triggers it; it stops when you cancel or the work completes. Recurring work, or reacting to an external system. You hand off **the trigger**.
- **Proactive** — an event or schedule triggers it with no human in real time; each task exits at its goal and the routine runs until you turn it off. Recurring streams of well-defined work. You hand off **the prompt**.

The guide frames these as a progression: each step hands off one more piece of the loop. Not every task needs a complex loop — start with the simplest that fits and use the rest selectively.

## 101. Loops You Drive — Turn-based and Goal-based

- **Turn-based, the agentic loop.** Every prompt is already a loop: gather context, act, check the work, repeat, respond — exiting when Claude judges the task complete or the effort budget runs out. The lever is verification: encode your manual check steps as a `SKILL.md` so Claude verifies its own work end to end, and give it tools to see, measure, and interact. The more quantitative the check, the easier the self-verification. Builds on Section 14.
- **Goal-based, `/goal`.** One turn often isn't enough, and agents do better iterating. `/goal` defines what done looks like so Claude cannot settle for "good enough": each time it tries to stop, an evaluator model checks the condition and sends it back until the goal is met or the turn cap is reached. Deterministic criteria — tests passing, a score threshold — work best. Extends Section 77.

## 102. Autonomous Loops — Time-based and Proactive

- **Time-based, `/loop` and `/schedule`.** For recurring work with changing inputs, or for reacting to an external system. `/loop` re-runs a prompt on an interval on your machine and stops when the machine does; `/schedule` moves it to the cloud as a Routine. Pulls together Sections 31, 43, and 61.
- **Proactive.** The most autonomous shape: event- or schedule-triggered with no human in real time, running in the cloud regardless of your laptop. It is a composition rather than a primitive — `/schedule` to watch for new work, `/goal` plus verification skills to define and check done, dynamic workflows (Sections 80–86) to orchestrate across many items, and auto mode (Sections 42, 68) so it never stops to ask permission.

## 103. Making Loops Good — Quality, Tokens, and Which One When

A loop is only as good as the system around it.

- **Output quality.** Keep the codebase clean, since Claude follows existing patterns; give it a way to verify its own work by encoding "good" as skills; keep docs reachable; use a second agent for review, because fresh context is less biased. When a result misses the bar, encode the fix so every future iteration improves rather than patching the instance.
- **Token usage.** Pick the right primitive and model, define clear stop criteria, pilot before a large run, use scripts for deterministic work, match the interval to how often the watched thing actually changes, and review spend with `/usage`, a bare `/goal`, and `/workflows`.

**Which loop when.** Turn-based when exploring or deciding; goal-based when you know what done looks like; time-based when the work happens on a schedule outside your project; proactive when the work is recurring and well defined. To start, pick one task where you are the bottleneck, hand off exactly one piece, run it, and watch where it stalls or over-reaches.
