---
description: "Builds a throwaway interactive terminal app to pressure-test business logic, a state machine, a data model, or an API surface before committing to it. Use when: 'does this state machine handle X then Y', 'sanity-check this data model', 'feel out the API', 'prototype this logic', 'does this reducer handle the edge case', 'is this data shape right' — any question answered by driving state by hand and watching it change. Produces a portable pure logic module (liftable into production) behind a disposable shell — a terminal app by default, or a self-contained HTML demo a non-developer can drive by clicking buttons when no terminal fits. Captures the validated answer in a durable note. Not for visual or design questions — use /prototype:explore-directions for those."
argument-hint: "[scope] (e.g., /prototype:pressure-test scheduling state machine)"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(git branch:*)", "Bash(git status:*)", "Bash(head:*)", "Bash(echo:*)", "Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/detect-ecosystems.sh:*)"]
shell: bash
metadata:
  workflow-stage: plan
  summary: Throwaway terminal app or shareable HTML demo pressure-testing logic or a data model
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Working tree status: !`git status --porcelain 2>/dev/null | head -10 || echo "clean"`
Project ecosystems: !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-ecosystems.sh" 2>/dev/null || echo "none detected"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

A disposable interactive shell driving a state model by hand — a terminal app by default, a
shareable HTML demo when the audience calls for it. Use when the question is about
**business logic, state transitions, or data shape** — things that look reasonable on paper but
only feel wrong once pushed through real cases.

The shared throwaway rules, the auto-invoke gate, and how to capture the answer live in
[`${CLAUDE_PLUGIN_ROOT}/context/discipline.md`](../../context/discipline.md) — read it before you
start. This file covers only the logic facet.

If the question is "what should this look like" — wrong facet. Use `/prototype:explore-directions`.

## When this is the right shape

- "Does this state machine handle the edge case where X then Y?"
- "Does this data model represent the case where...?"
- "What should the API surface look like before writing it?"
- Anything where pressing buttons and watching state change reveals the answer

## Two shells — TUI default

Two disposable shells can front the same portable logic module (step 3 below) — the **terminal
app** (the default) and a **self-contained HTML demo**. Both run the same process; only the shell
swaps. Route by audience:

- **The driver is a developer with a terminal** → the TUI (the default below).
- **The driver is a non-developer** — a designer, PM, or domain expert pressing the buttons — or
  **no terminal fits the handoff** → the HTML demo shell (next section): one file, nothing to
  install, opened by double-click.
- **Explicit override wins both ways** — ask for a TUI or an HTML demo directly and that beats
  the default routing.

## HTML demo shell

When the audience routing selects it, the shell is one self-contained `file://` HTML page over the
same pure logic module — the module lives in a single inline `<script>` block written so it could
be lifted out unchanged; the page calls into it, and nothing flows the other direction. It
replaces steps 4–5 below; the rest of the process holds (in step 6, the run command is the page's
`file://` path).

Lay the page out top to bottom, in **domain language** — every button and field reads like the
business, not the reducer, because the driver is not reading code:

1. **Title and one-line explanation** — the question from step 1, visible on the page.
2. **State panel** — the full relevant state as a readable labelled panel (not a raw JSON dump),
   re-rendered after every click so the change is visible.
3. **Free-play buttons** — one button per action, always available, so the driver can poke at the
   model in any order.
4. **Guided walkthroughs** — a few scenarios worth demonstrating: the happy path, a tricky edge
   case, an attempt at something that should be illegal. Each is a short plain-language
   description plus the ordered buttons to press; starting a walkthrough **resets to a known
   initial state** so the scenario runs the same way every time.

Constraints (the same set as explore-directions' HTML mockup substrate):

- **Synthetic data only.** A throwaway prototype binds synthetic data, never real or captured
  values.
- **No remote fetch by construction.** Vendor everything inline so the page opens straight from
  `file://` — no external scripts, fonts, or data fetches. Enforce this rather than trusting it:
  emit a restrictive CSP meta tag in the page `<head>` so the browser blocks any remote resource —
  `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:">`.
  Inline `<style>` and inline `<script>` stay allowed (the logic module and the button handlers
  need inline script); only remote origins — CDNs, web fonts, `fetch`/XHR — are forbidden.
- **Ephemeral placement.** Generate the page via the platform's temp primitive — never a tracked
  path and never inside the repo. On Unix/Linux/Git Bash, create a private run directory and
  write the page inside it, echoing the directory in the same call —
  `d=$(mktemp -d "${TMPDIR:-/tmp}/pressure-test-XXXXXX"); echo "$d"` — then write to
  `<echoed dir>/pressure-test.html`. Echo it because shell state does not survive between Bash
  calls. Keep the temp root in the positional template with the `XXXXXX` trailing, and give the
  page a fixed name inside the generated directory — the mktemp dialect traps behind those two
  rules (GNU vs BSD `-p`/`-t` divergence, trailing-X-only substitution on BSD/macOS) are unpacked
  in [`explore-directions`](../explore-directions/SKILL.md)'s HTML mockup substrate section; the
  same rules apply verbatim here. On Windows, a user-scoped temp under `%LOCALAPPDATA%\Temp`. One
  file per run. The path is handed to the user to open from `file://`, so do not delete it — it
  must still be readable when they open it.
- **Markdown captures the answer.** Copy what the demo taught into your durable answer (per the
  shared discipline), then discard the page like any other shell — the validated logic module is
  the only artifact that outlives the prototype (lifted into production per step 7).

## Process

### 1. State the question

Write down what state model and what question you're prototyping. One paragraph, comment at top of
file. A logic prototype answering the wrong question is pure waste — make the question explicit.

### 2. Pick the language

Use whatever the host project uses. Match existing conventions for tooling — don't add a new
runtime for a prototype.

### 3. Isolate logic in a portable module

Put the logic — the bit answering the question — behind a small, pure interface that could be
lifted into the real codebase later. The shell around it (TUI or HTML page) is throwaway; the
logic module should not be.

Pick the shape that fits the question:

| Shape | When |
|-------|------|
| **Pure reducer** — `(state, action) => state` | Actions are discrete events, state is a single value |
| **State machine** — explicit states and transitions | "Which actions are even legal right now" is part of the question |
| **Pure functions** over a plain data type | No implicit current state — just transformations |
| **Class/module with clear method surface** | Logic genuinely owns ongoing internal state |

Keep it pure: no I/O, no terminal code, no DOM access, no console output for control flow. The
shell imports and calls into the logic module; nothing flows the other direction.

This is what makes the prototype useful past its own lifetime. When the question's been answered,
the validated module can be lifted into production code — the shell gets deleted.

### 4. Build the smallest TUI that exposes state

(TUI default. When the audience routing selected the HTML demo shell, that section replaces this
step and step 5.)

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

Give the user the run command (for the HTML demo shell, the page's `file://` path — send them the
file or open it for them). Interesting moments — "wait, that shouldn't be possible" or "huh, I
assumed X would be different" — are bugs in the IDEA. Add new actions as the user requests them.
Prototypes evolve.

### 7. Capture the answer

When done, capture what the prototype taught (per the shared discipline). The logic module behind
the shell is often worth keeping; the shell — TUI or HTML page — is not: lift the validated
module into production and delete the shell.

## Anti-patterns

- **Adding tests.** A prototype needing tests is no longer a prototype.
- **Wiring to a real database.** In-memory store unless the question IS about persistence.
- **Generalizing.** No "what if we wanted to support X later."
- **Blurring logic and shell.** If the reducer/state machine references console output, terminal
  codes, or the DOM, it's no longer portable. The shell (TUI or page) is a thin layer over a pure
  module.
- **Shipping the shell to production.** The shell — TUI or HTML page — is optimized for
  hand-driving. The logic module behind it is the reusable bit.
- **Reaching for a framework, bundler, or server in the HTML demo shell.** One file the driver
  double-clicks; a dev server defeats "nothing to install".
