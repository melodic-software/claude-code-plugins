---
name: logic
description: "Builds a throwaway interactive terminal app to pressure-test business logic, a state machine, a data model, or an API surface before committing to it. Use when: 'does this state machine handle X then Y', 'sanity-check this data model', 'feel out the API', 'prototype this logic', 'does this reducer handle the edge case', 'is this data shape right' — any question answered by driving state by hand and watching it change. Produces a portable pure logic module (liftable into production) behind a disposable TUI shell, and captures the validated answer in a durable note. Not for visual or design questions — use /prototype:ui for those."
argument-hint: "[scope] (e.g., /prototype:logic scheduling state machine)"
user-invocable: true
disable-model-invocation: false
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Working tree status: !`git status --porcelain 2>/dev/null | head -10 || echo "clean"`
Project ecosystems: !`ls *.slnx *.sln package.json pyproject.toml Cargo.toml go.mod 2>/dev/null || echo "none detected"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

An interactive terminal app driving a state model by hand. Use when the question is about
**business logic, state transitions, or data shape** — things that look reasonable on paper but
only feel wrong once pushed through real cases.

The shared throwaway rules, the auto-invoke gate, and how to capture the answer live in
[`${CLAUDE_PLUGIN_ROOT}/context/discipline.md`](../../context/discipline.md) — read it before you
start. This file covers only the logic facet.

If the question is "what should this look like" — wrong facet. Use `/prototype:ui`.

## When this is the right shape

- "Does this state machine handle the edge case where X then Y?"
- "Does this data model represent the case where...?"
- "What should the API surface look like before writing it?"
- Anything where pressing buttons and watching state change reveals the answer

## Process

### 1. State the question

Write down what state model and what question you're prototyping. One paragraph, comment at top of
file. A logic prototype answering the wrong question is pure waste — make the question explicit.

### 2. Pick the language

Use whatever the host project uses. Match existing conventions for tooling — don't add a new
runtime for a prototype.

### 3. Isolate logic in a portable module

Put the logic — the bit answering the question — behind a small, pure interface that could be
lifted into the real codebase later. The TUI around it is throwaway; the logic module should not
be.

Pick the shape that fits the question:

| Shape | When |
|-------|------|
| **Pure reducer** — `(state, action) => state` | Actions are discrete events, state is a single value |
| **State machine** — explicit states and transitions | "Which actions are even legal right now" is part of the question |
| **Pure functions** over a plain data type | No implicit current state — just transformations |
| **Class/module with clear method surface** | Logic genuinely owns ongoing internal state |

Keep it pure: no I/O, no terminal code, no console output for control flow. The TUI imports and
calls into the logic module; nothing flows the other direction.

This is what makes the prototype useful past its own lifetime. When the question's been answered,
the validated module can be lifted into production code — the TUI shell gets deleted.

### 4. Build the smallest TUI that exposes state

On every tick, clear the screen and re-render the whole frame. The user sees one stable view, not
growing scrollback.

Each frame has two parts:

1. **Current state** — pretty-printed, one field per line or formatted output. Bold field names,
   dim less-important context (timestamps, IDs, derived values).
2. **Actions** — listed at bottom: `[a] add item  [d] delete item  [t] tick clock  [q] quit`.

Behavior loop:

1. Initialize state — a single in-memory object. Render the first frame on start.
2. Read one keystroke (or one line), dispatch to a handler that mutates state via the logic module.
3. Re-render the full frame after every action — replace, don't append.
4. Loop until quit.

The whole frame should fit on one screen.

### 5. Make it runnable in one command

Add a script to the project's existing task runner. The user runs the equivalent of
`dotnet run --project <path>` or `pnpm run <name>` — never needs to remember a file path.

If there's no task runner, put the command at the top of a prototype README.

### 6. Hand it over

Give the user the run command. Interesting moments — "wait, that shouldn't be possible" or "huh, I
assumed X would be different" — are bugs in the IDEA. Add new actions as the user requests them.
Prototypes evolve.

### 7. Capture the answer

When done, capture what the prototype taught (per the shared discipline). The logic module behind
the TUI is often worth keeping; the TUI shell is not — lift the validated module into production
and delete the shell.

## Anti-patterns

- **Adding tests.** A prototype needing tests is no longer a prototype.
- **Wiring to a real database.** In-memory store unless the question IS about persistence.
- **Generalizing.** No "what if we wanted to support X later."
- **Blurring logic and TUI.** If the reducer/state machine references console output or terminal
  codes, it's no longer portable. The TUI is a thin shell over a pure module.
- **Shipping the TUI shell to production.** The shell is optimized for hand-driving from a
  terminal. The logic module behind it is the reusable bit.
