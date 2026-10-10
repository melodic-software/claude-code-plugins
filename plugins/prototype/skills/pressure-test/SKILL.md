---
description: "Builds a throwaway interactive terminal app to pressure-test business logic, a state machine, a data model, or an API surface before committing to it. Use when nobody can say yet what a set of rules does with an awkward sequence of events or an odd record, and stepping through it by hand would show: 'what happens if a refund arrives after the order ships', 'is this transition allowed from that status', 'will this schema fit our odd records', 'which arguments should this call take', 'prototype this reducer'. Produces a portable pure logic module (liftable into production) behind a disposable shell, a terminal app by default, or a self-contained HTML demo that someone outside engineering operates by clicking buttons when no terminal fits. Captures the validated answer in a durable note. Not for visual or design questions. Use /prototype:explore-directions for those."
argument-hint: "[scope]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(git branch:*)", "Bash(git status:*)", "Bash(head:*)", "Bash(echo:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/detect-ecosystems.sh:*)"]
shell: bash
metadata:
  workflow-stage: plan
  summary: Throwaway terminal app or shareable HTML demo pressure-testing logic or a data model
---

**Arguments.** `[scope]`. e.g., /prototype:pressure-test scheduling state machine

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch, `git branch --show-current`
- Working tree status (empty = clean), `git status --porcelain | head -10`

The pipe is the bound and belongs in the command. A read-time cap ("read only the first 10 entries")
bounds nothing: the Bash tool returns the command's complete output into context before there is
anything to decide about.

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
separate body Bash calls rather than pre-compute lines: the harness runs a skill's whole pre-compute
block as one shell invocation, and a worktree-isolated session refuses a compound command that
contains git.

## Pre-computed context

Project ecosystems: !`${CLAUDE_SKILL_DIR}/scripts/detect-ecosystems.sh 2>/dev/null || echo "none detected"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

This skill checks a set of rules by running them. It puts the logic in question into a small pure
module, wraps that module in a disposable shell a person drives one action at a time, and shows
the whole state after every action. The shell is a terminal app by default, or one HTML file for
a driver who does not use a terminal.

The examples in this file follow one case: a library's loan rules. A copy can be on the shelf, on
loan, overdue or reserved, and the events are borrow, renew, return, reserve and a day passing. A
rule such as "a loan can be renewed twice" fits on one line and still says nothing about the
patron waiting on a reservation for that copy; the gap appears when someone renews such a copy and
reads the resulting state.

Read [`${CLAUDE_PLUGIN_ROOT}/context/discipline.md`](../../context/discipline.md) first. It holds
the rules every prototype follows, the auto-invoke gate, and where the answer gets written down.
This file adds only what is specific to the logic facet.

A question about how a screen should look ("what should this look like") is a visual/appearance
question, not a logic/state question, and belongs to the other facet: invoke
`/prototype:explore-directions` via the Skill tool instead.

## Does the question need a running model?

Use this skill when acting on a running model would settle the question sooner than reading code or
arguing about it. In the loans case:

| What is in doubt | Loans example | Use this skill? |
|---|---|---|
| How the rules treat events in an awkward order, including the ones they should refuse | A reserved copy comes back late and its borrower then tries to renew it | Yes |
| Whether the record shape can hold a case the library really has | One patron borrows two copies of the same title | Yes |
| What the calls should take and return | Renew by loan id or by copy id | Yes; the module's interface is the draft |
| What today's code already does | Does the current `renew()` check reservations? | No; read the code |

## Two shells. TUI default

Two disposable shells can front the same portable logic module (step 2 below), the **terminal
app** (the default) and a **self-contained HTML demo**. Both run the same process; only the shell
swaps. Route by audience:

- **The driver is a developer with a terminal** → the TUI (the default below).
- **The driver works outside engineering** (design, product, or the business side) and will press
  the buttons, or **no terminal fits the handoff** → the HTML demo shell (next section): one file,
  nothing to install, opened by double-click.
- **Explicit override wins both ways**. Ask for a TUI or an HTML demo directly and that beats
  the default routing.

## HTML demo shell

When the audience routing selects it, the shell is one self-contained `file://` HTML page. This
shell takes the place of step 3 below; every other step holds (in step 4, the run command is the
page's `file://` path). The step 2 module goes into the page unchanged as its own inline
`<script>` block, and step 2's one-way dependency rule applies to the page exactly as it does to
a terminal shell.

The person driving the page does not read code, so the page speaks the library's language: buttons
say "Renew loan", fields say "Days overdue" with a value beside them, and nothing shows `RENEW`,
`state.loans[0].due` or a JSON dump. The page has these regions, top to bottom:

| Region | What the driver does there (loans case) |
|---|---|
| Header | Reads the title and the step 1 question in one sentence |
| State panel and free-play buttons | Presses Borrow, Renew, Return, Reserve or Next day in any order, at any time, and watches the copy's status, due date, reservation holder and fine change after each press |
| Guided walkthroughs | Runs scripted scenarios. Each opens on the same fresh library, says in a sentence what to watch, and lists its presses in order. Include one the rules must refuse (borrowing a copy someone else reserved), one awkward case (renewing on the due date) and one ordinary run (borrow, then return on time) |
| Validation answer set | The questions this demo exists to answer, each as a forced choice with a small authored option set, every option naming its cost in plain language (what picking it gives up), plus a free-text escape hatch for the answer the options missed. The driver's picks are the demo's real output; pair the set with a copy-out control that lifts the filled answers back out as text to paste into the session |
| Fake-data disclosure footer | One visible line stating the page is synthetic end to end, that nothing on it reads from or writes to the real app, and, when decided, where the real wiring lives (or will live) and behind which flag; when integration is not yet decided, or no flag is planned, the footer says so explicitly rather than inventing production details. The driver is not reading code; the footer is what keeps a convincing mock from being mistaken for the wired feature |

Constraints (the same set as explore-directions' HTML mockup substrate):

- **Synthetic data only.** A throwaway prototype binds synthetic data, never real or captured
  values.
- **No remote fetch by construction.** Vendor everything inline so the page opens straight from
  `file://`. No external scripts, fonts, or data fetches. Enforce this rather than trusting it:
  emit a restrictive CSP meta tag in the page `<head>` so the browser blocks any remote resource:
  `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:">`.
  Inline `<style>` and inline `<script>` stay allowed (the logic module and the button handlers
  need inline script); only remote origins, CDNs, web fonts, `fetch`/XHR, are forbidden.
- **Ephemeral placement.** Generate the page via the platform's temp primitive, never a tracked
  path and never inside the repo. On Unix/Linux/Git Bash, create a private run directory and
  write the page inside it, echoing the directory in the same call:
  `d=$(mktemp -d "${TMPDIR:-/tmp}/pressure-test-XXXXXX"); echo "$d"`, then write to
  `<echoed dir>/pressure-test.html`. Echo it because shell state does not survive between Bash
  calls. Keep the temp root in the positional template with the `XXXXXX` trailing, and give the
  page a fixed name inside the generated directory, the mktemp dialect traps behind those two
  rules (GNU vs BSD `-p`/`-t` divergence, trailing-X-only substitution on BSD/macOS) are unpacked
  in [`explore-directions`](../explore-directions/SKILL.md)'s HTML mockup substrate section; the
  same rules apply verbatim here. On Windows, a user-scoped temp under `%LOCALAPPDATA%\Temp`. One
  file per run. The path is handed to the user to open from `file://`, so do not delete it. It
  must still be readable when they open it.
- **Markdown captures the answer.** Copy what the demo taught into your durable answer (per the
  shared discipline), then discard the page like any other shell, the validated logic module is
  the only artifact that outlives the prototype (lifted into production per step 5).

## Process

### 1. Write the question down

For the loans case the paragraph reads: "State model: one copy's loan record. Question: can the
current borrower renew a copy that someone else has reserved, and if so, what happens to the
reservation?" Write a paragraph like that before any code, as the opening comment of the module
file (for the HTML demo shell, also in the page header). Without it, the build drifts toward
whatever question is easiest to answer.

### 2. Build the logic module

Write it in the host project's language with its existing tooling; a prototype never brings in a
new runtime.

Decide what belongs on each side of the split before writing either side:

| | Module | Shell (TUI or HTML page) |
|---|---|---|
| After the answer is recorded | Committed to production unchanged | Deleted |
| Loans contents | The loan record, the borrow/renew/return/reserve rules, the fine | Key or click handling, drawing the state, the sample patrons |
| Allowed inside | Plain values in, plain values out | Terminal codes, DOM access, printing, reading input |
| Imports | Nothing from the shell | The module (the one-way dependency rule) |

Before the shell exists, search the module for terminal codes, DOM access, I/O and any console
output that decides a branch, and read its import list. A hit on either means the module cannot
be committed unchanged.

Then pick the module's form by asking who holds the loan state between two calls:

| Who holds it | Form | Loans example |
|---|---|---|
| Nobody; each call computes from its arguments | Separate pure functions over plain values | `fineFor(daysLate)` |
| The caller, who passes it in each time | One function from the current record and an event to the next record. When the doubt is which events a status refuses, give it an explicit table of statuses and the events each accepts, which makes it a state machine | `next(loan, "renew")`; `overdue` accepts `return`, refuses `renew` |
| The module itself | An object with a few methods, used only when the caller cannot reasonably carry the state | a `Ledger` with `borrow()` and `history()` |

### 3. Build the TUI shell

(Terminal default. When the audience routing selected the HTML demo shell, that section replaces
this step.)

Redraw the whole screen after every action: clear it and print the full frame again, so the user
watches one view change in place instead of a log growing down the terminal. The frame fits on one
screen and has two parts:

1. **State**, one field per line, with field names in bold and secondary details (timestamps, ids,
   computed values) dimmed.
2. **Keys**, listed at the bottom: `[b] borrow  [w] renew  [r] return  [d] next day  [q] quit`.

The loop: create the state as one in-memory value and draw the first frame; read one key (or one
line); pass it to a handler that updates the state through the logic module; draw the full frame
again, replacing the old one; repeat until quit.

Make it start with one command. Add an entry to the project's existing task runner, so the user
types the equivalent of `pnpm run loans-proto` or `dotnet run --project <path>` and never has to
remember a file path. With no task runner, write the command at the top of a prototype README.

### 4. Hand it over

Give the user the run command (for the HTML demo shell, the page's `file://` path; open the page
for them or pass them the file).

Sort each remark the user makes while driving into one of two piles:

- **A finding about the rules.** Write down the presses that led to it, in order, and the state
  the user expected instead. For the loans case: borrow, reserve as a second patron, renew; the
  renewal went through and the user expected a refusal. These lists feed step 5.
- **A state the prototype cannot reach yet**, such as a reservation that lapses unclaimed. Add the
  event to the module, give it a key or button in the shell, and hand the prototype back.

### 5. Capture the answer

Write down what the prototype showed, per the shared discipline. For the HTML demo shell, carry
the filled validation answer set into the durable answer verbatim: the chosen option per question,
with the cost the driver accepted, is the record of what was actually decided. Then move the
validated module into production and delete the shell, terminal app or page alike; the module is
often worth keeping, the shell never is.

## Next

- The model holds and it settles a type, contract, or boundary: `/planning:design`, to record it.
- The model holds and no design question is open: `/planning:plan`, which schedules the logic module's lift.
- The prototype invalidates the model: `/planning:design`.

## Anti-patterns

| Mistake | Why it fails | Instead |
|---|---|---|
| Shell code inside the module | A `renew()` that prints to the terminal or reads a form field runs only inside that one shell, so it cannot be copied into production | Let `renew()` take a loan and return a loan; the shell, TUI or page, does all printing and reading around it |
| Connecting the real database | Every click becomes a real write to the loans table, and storage was not the thing under test | Hold the loans in a plain in-process map that disappears on exit, unless persistence is the question itself |
| Writing a test suite for the prototype | The renewal rules are meant to change after each answer the driver gives; once it needs a test suite it has stopped being a prototype, and tests would freeze rules still being decided, and the effort belongs to the module that survives | Write tests for the module once it is lifted into production |
| Building for cases nobody asked about | Interlibrary loans or e-books added "for later" blur the answer to the one question asked | Answer the step 1 question and stop |
| A build step, bundler, framework or server behind the HTML demo shell | The librarian who drives the demo gets a file by email and has no toolchain; a page that must be built or served never opens for them | One HTML file with every script and style inlined |
| Shipping the shell | The loan screen hard-codes sample patrons and skips every failure case, so the library would run on demo scaffolding | Ship the module; delete the shell |
