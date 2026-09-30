# Loops: Sections 100–103

The ClaudeDevs guide *"Getting started with loops"* (Part 19, July 6, 2026, written by Delba de Oliveira). A **loop** is an agent repeating cycles of work until a stop condition is met; everything from a single prompt to a cloud routine is one. They differ by trigger, stop condition, the primitive that runs them, and the task that fits.

## 100. The Four Loops: A Taxonomy

- **Turn-based** (the agentic loop): a prompt triggers it; it stops when Claude judges the task done. Short one-off tasks. You hand off **the check**.
- **Goal-based** (`/goal`): a prompt triggers it; it stops when the goal is met or a turn cap trips. Tasks with verifiable exit criteria. You hand off **the stop condition**.
- **Time-based** (`/loop`, `/schedule`): a time interval triggers it; it stops when you cancel or the work completes. Recurring work, or reacting to an external system. You hand off **the trigger**.
- **Proactive**: an event or schedule triggers it with no human in real time; each task exits at its goal and the routine runs until you turn it off. Recurring streams of well-defined work. You hand off **the prompt**.

The guide frames these as a progression: each step hands off one more piece of the loop. Not every task needs a complex loop. Start with the simplest that fits and use the rest selectively.
