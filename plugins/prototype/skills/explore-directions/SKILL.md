---
description: "When the built-in ClaudeDesign tool resolves in this session and the person names, links, or asks for work in an existing claude.ai/design project, prefer it for that project; this skill for throwaway variants. Builds throwaway UI variations, a few structurally different layouts (three by default) behind one route, toggled from a floating switcher, to answer 'what should this look like' before committing to a design. Use when the question is what a page, screen, or dashboard should look like, or for design options to compare: 'mock up a UI', 'how should this screen be laid out', 'show me layout options'. Runs on the real stack by default or as a self-contained HTML mockup; the user keeps one variant or bits of each. Logic or state questions: /prototype:pressure-test. Not for an interactive parameter explorer whose output returns as a prompt: that is the first-party playground skill, routed via /playgrounds:use where the upstream playground plugin is installed from its marketplace."
argument-hint: "[scope]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(git branch:*)", "Bash(git status:*)", "Bash(head:*)", "Bash(echo:*)", "Bash(${CLAUDE_SKILL_DIR}/scripts/detect-ecosystems.sh:*)"]
shell: bash
metadata:
  workflow-stage: plan
  summary: Throwaway UI variations answering what should this look like
---

**Arguments.** `[scope]`. e.g., /prototype:explore-directions settings page

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

The output is a recorded decision about one screen's layout, made by a user who has clicked
through working candidates rather than sketches. The candidates are mounted in the app itself (or
in a local mockup) with a switcher attached; the verdict may combine parts of several of them, and
once it is written down, all candidate code is deleted.

The examples in this file follow one case: the `/shipments` page of an order-tracking app, where
the team cannot agree on how to show parcels in transit.

Read [`${CLAUDE_PLUGIN_ROOT}/context/discipline.md`](../../context/discipline.md) first. It holds
the rules every prototype follows, the auto-invoke gate, and where the answer gets written down.
This file adds only what is specific to the UI facet.

A question about behavior (a reducer, a transition, the shape of the data) is a logic/state
question, not an appearance question, and belongs to the other facet: invoke
`/prototype:pressure-test` via the Skill tool instead.

## Signs this skill fits

| Sign | Example ask |
|---|---|
| Nobody can picture the screen yet | "How should `/shipments` show delayed parcels?" |
| Several layouts look plausible and discussion will not settle it | "One dense table, or a card per parcel?" |
| A new piece needs a home inside a page that exists | "Where would a returns panel sit on `/shipments`?" |
| The team keeps arguing from sketches nobody has built | "We discussed this in two meetings and still disagree." |

## Where the variants live

Choose a host before drafting anything. This table is the intent selector the rest of the file
refers to: the question decides the row, not whichever mount point is easiest. A direct request
for a real-stack page or for an HTML mockup overrides it in either direction.

| Host | Choose it when | How the variants are mounted | When the exercise ends |
|---|---|---|---|
| **Sub-shape A** (default) | A page already exists, or the new piece would sit inside one (a panel, a card, one step of a flow) | Inside that page, selected by a `?variant=` query parameter or the framework's equivalent. The page keeps its data loading, route parameters and auth; only the subtree under test changes | Merge the winning variant into the page; remove the switcher and every losing variant |
| **Sub-shape B** (last resort) | The candidate-page check below found nothing, as for a carrier sign-up wizard in an area the app does not have yet | A new route, placed and named under the discipline's "Marked as disposable from the start" rule, with the same `?variant=` selection | Turn the winning variant into a real route; remove the switcher along with the throwaway route |
| **HTML mockup substrate** | No page to host it and speed matters more than realism: no app or dev server running, no app yet, or someone who is not a developer exploring | One local `file://` page, described in the next section | Discard the file once the winning key and notes are written down; nothing tracked is left |
| **Design canvas** (the user runs it) | The user took the `/design` offer described below | Artboards on a published canvas | Write down the winning key and notes the same way, then ask whether the user wants the canvas kept (it persists under their account) or cleared; nothing tracked points at it either way |

**Candidate-page check.** Before choosing B, list every existing page the piece could be added to
and say why each one fails. For a returns panel the list is `/shipments`, the order detail page
and the account page. The check matters because a parcel card that
looks roomy on a bare route can push the order summary off screen on the real `/shipments`, with
its header, its filters and forty parcels in transit.

Sub-shape B and the mockup substrate cover the same situation, no page to host the work. B costs
a running app and buys a judgment made inside it; the mockup gives up that realism for a page that
opens with nothing running.

## HTML mockup substrate

When the intent selector picks this row, the variants live in one self-contained `file://` HTML
page with synthetic data and an in-page switcher. Assemble one per task (there is no canned
template to copy):

1. **N variant containers**. One block per variant, all in the single page.
2. **An in-memory switcher**. `file://` has no routing, so there is no `?variant=` URL; toggle
   container visibility in memory instead. Build its floating bar, buttons and keyboard handling
   to the real-stack switcher table in step 3 below.
3. **A copy-out terminator**, a small control that lifts the winning-variant key plus notes back
   out as text you can paste into your durable answer.

Constraints:

- **Synthetic data only.** A throwaway prototype binds synthetic data, never real or captured
  values.
- **Same data across variants.** All variants bind one identical data set; the data is the
  control variable, so the only thing that differs between variants is the design. On the real
  stack, sub-shape A's shared fetching above the switcher already enforces this; on the mockup
  substrate, define the synthetic set once and have every variant render it.
- **No remote fetch by construction.** Vendor everything inline so the page opens straight from
  `file://`. No external scripts, fonts, or data fetches. Enforce this rather than trusting it:
  emit a restrictive CSP meta tag in the page `<head>` so the browser blocks any remote resource:
  `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:">`.
  Inline `<style>` and inline `<script>` stay allowed (the in-page switcher needs inline script);
  only remote origins, CDNs, web fonts, `fetch`/XHR, are forbidden.
- **Ephemeral placement.** Generate the mockup via the platform's temp primitive, never a tracked
  path and never inside the repo. On Unix/Linux/Git Bash, create a private run directory and write
  the page inside it, echoing the directory in the same call:
  `d=$(mktemp -d "${TMPDIR:-/tmp}/explore-directions-XXXXXX"); echo "$d"`, then writing to
  `<echoed dir>/explore-directions.html`. Echo it because shell state does not survive between Bash
  calls: the directory name is random, so an unechoed path is unrecoverable in the call that writes
  the file. Carry the temp root in the positional template, the one form GNU and BSD `mktemp` accept identically, since `-p`/`--tmpdir`/`-t` differ between the dialects and a bare relative template silently creates the file in the **current directory**, the consumer's repository. Keep the `XXXXXX` placeholders **trailing**. BSD `mktemp` (macOS) substitutes only trailing Xs, so an extension after them is not portable.
  That is why the page takes a fixed name inside the generated directory rather than an
  `explore-directions-XXXXXX.html` template, which macOS cannot create at all. On Windows,
  a user-scoped temp under
  `%LOCALAPPDATA%\Temp`. One file per run. The path is handed to the user to open from `file://`,
  so do not delete it. It must still be readable when they open it.
- **Markdown captures the answer.** Copy the winning-variant key and notes into your durable
  answer (per the shared discipline); the HTML is throwaway.
- **Each variant declares its visual direction.** The mockup has no project styling system to
  inherit, so with no declared direction every variant renders in one default house aesthetic.
  Before writing a variant, state its direction. Background hex, accent hex, typeface, one-line
  rationale, and make it differ from its siblings on that axis as well as structurally. Generic
  steering ("make it clean") only swaps one fixed palette for another; a concrete per-variant
  declaration is what produces variety. Also name the defaults no variant may fall back on:
  italic accent words in headings, numbered "01 / 02 / 03"
  section labels, monospace labels, and pill-shaped buttons, plus any the user names. When a
  `skip:` line in the handover rejects a visual choice, add it to that list before the next
  round.

### Design-canvas alternative (bundled `design` skill, run by the person)

When the intent selector lands on the HTML mockup substrate, tell the user before building that
the design canvas is an alternative they can run themselves, using the suggest sentence in the
Boundary section below. The bundled `design` skill is reserved for the person to run; this skill
never invokes it and never switches silently. The HTML mockup stays the default and is built
either way:

- **HTML mockup (default)**, the throwaway `file://` page above; nothing persists.
- **Design canvas**, run by the user as `/design <scope>`: it drafts the variants as artboards on
  one canvas, published as a Claude Design Artifact. Name the lifecycle difference in the offer:
  the canvas is a published, persistent Artifact. Default-private, shareable with teammates at
  the user's choice. Unlike the throwaway local mockup, losing variants persist on it unless the
  user deletes or re-seeds the canvas. The user edits artboard elements in a desktop browser,
  edits save automatically, and each artboard exports as PNG or PDF.

The capture discipline is unchanged either way: record the winning-variant key and notes in
your durable answer; the canvas may live on under the user's account, but nothing tracked in
the repo references it. The surface facts and their verified-on record live in
[reference/bundled-design.md](reference/bundled-design.md).

## Process

### 1. Write the plan

Before any code, record the plan as one line naming the route, the host and the keys, for example:
"Plan: `/shipments`, sub-shape A, variants A to C selected by `?variant=`." The count is **3
variants** unless the user asks for another number, and never more than 5: past five, new variants
repeat earlier ones instead of disagreeing with them.

**Optional reference pass.** It applies only while nothing fixes the look: no direction from the
user and no host page under sub-shape A. Then, before step 2, ask whether the user wants one. If
yes, collect a handful of comparable screens (other products doing the same job, plus the app's own
nearest screens) and reduce them to two to four candidate directions, each named by its layout,
density, color and type. The variants in step 2 follow the directions the user keeps; with the pass
declined, step 2 starts as usual.

### 2. Draft the variants

Sort every design choice into what must change between variants and what must not:

| Choice | Between variants | `/shipments` example |
|---|---|---|
| Layout: how the regions are arranged | Must differ | A: one full-width table. B: a column of parcel cards. C: a map with a side list |
| Information hierarchy: what the eye reads first | Must differ | A: status. B: expected delivery date. C: current location |
| Primary affordance: the main thing to do | Must differ | A: select several and export. B: open one parcel. C: filter by region |
| Visual direction | Must differ wherever the project's styling system leaves room, and always on the HTML mockup substrate; each variant declares its own direction instead of sharing one default look | A: muted grays. B: the brand blue. C: high-contrast map tiles |
| The job the page does and the records it can reach | Identical | Every variant shows the same in-transit parcels for the same customer |
| Component library and styling system | Identical | All three use the app's own table, card and map components |

Every variant is required to be structurally different and visually distinct. When two drafts
agree on the three structural "must differ" rows, they are one design shown twice, however
different their colors or wording; structure comes first and the visual direction sits on top. Rewrite one of the
pair under an explicit ban, such as "no table".

### 3. Build the switcher

Add one switcher component to the page at that route, using the framework's own routing and the
`?variant=` parameter or its equivalent. Under sub-shape A, all data loading stays above the switcher, so every
variant receives the same records and only the subtree under test changes.

The switcher is a small floating bar, fixed at the bottom center of the viewport:

| Part | Requirement |
|---|---|
| URL | Each step rewrites `?variant=`, so a reload or a shared link opens the same variant |
| Keyboard | Left and right arrow keys step through the variants, except while a text input or textarea has focus |
| Buttons | Previous and next; both ends wrap around, so after the last variant comes the first and before the first comes the last |
| Label | The current key, plus a descriptive name if exported (`B · parcel cards`); export each variant component under a name built from its key (`VariantB` for key B) |
| Reuse | One shared component that sub-shape A and sub-shape B both mount |
| Production | Never rendered in a production build; an environment check gates it |
| Look | Built from none of the app's own colors or components (black on yellow over a blue-and-white `/shipments`), so no reviewer judges it as part of a variant |

### 4. Hand it over

The handover message has four parts, in this order:

1. **Where to look.** The route URL, and under it one line per variant: its key and, when
   evidence was captured, its screenshot path.
2. **Evidence per variant.** With `/playwright:playwright` among the available skills, load each
   variant in it, use its main control once (open the menu, submit the form, change the tab), and
   capture a screenshot; the handover pairs every variant key with its screenshot path. Without
   that skill, the handover says no screenshots exist.
3. **Tradeoffs and a pick to start from.** Give every variant one line of strengths and one of
   costs, and close with the variant you would choose and why. That choice is advice: the reply
   template still decides, and no variant is folded in before the user answers it.
4. **The reply template** below, machine-legible, for the user to fill, so the answer comes back
   as the next prompt in a form that needs no re-reading (on the mockup substrate, the copy-out
   terminator lifts it).

The template has repeatable `steal` lines and a `graft` direction because a mixed verdict is a
complete answer, not an indecisive one. On `/shipments` it might read `direction: graft`, then
`steal: delivery-date cards from B` and `steal: map layout from C`.

```text
direction: <winning variant key, or "graft">
steal: <piece> from <variant>   (repeat per piece)
skip: <piece or variant> because <one line>
next-target: <what to explore or build next>
```

### 5. Record the answer, then delete

Per the shared discipline. Record which variant won and why, and record the directions that lost
with their reasons. Capture at single-decision granularity: each named piece (a header, a
hierarchy choice, a primary affordance) gets its own steal/skip/adapt entry, so grafts compose
across variants instead of collapsing into one "variant B, mostly" note. When the verdict is a
graft rather than a single winner, say which piece came from where **and what the discarded parts
held that the graft deliberately left behind**.

Then carry out the "When the exercise ends" column of the intent selector for the host you used.
Those deletions are irreversible: whatever is not written down first is gone. Delete the switcher and
every variant file in the same change that merges the winner; code left behind gets imported by
mistake and falls out of date.

## Boundary, the bundled `design` skill

One native Claude Code surface drafts layouts as this skill does, and the two get conflated when
the intent selector lands on the HTML mockup substrate:

- **`design` (bundled skill)**: drafts artboards on one canvas and publishes the canvas as a
  Claude Design Artifact: persistent, shareable, edited in a desktop browser with edits saved
  automatically. It is reserved for the person
  to run as `/design`; the model does not invoke it.
- **This skill (marketplace plugin).** Throwaway variants on the real stack or as a local HTML
  mockup, switchable from a control bar; only the winning-variant key survives.

**Routing.** The HTML mockup stays the default and is built either way. Before building, tell the
user: If /design is available in your session (gate basis: the verification record below), you
can run `/design <scope>` instead of or alongside this skill for a hand-editable design canvas.
State the lifecycle difference with it; the design-canvas subsection above carries the offer
shape. A local skill named `design` at any level silently shadows the bundled command, and the
bundled one never appears in your skill listing, so a `design` entry in that listing is a
shadowing local skill: do not make the offer, and tell the user a local `design` skill shadows the
bundled canvas command. A local `design` skill that disables model invocation shadows it too and
is hidden from you, so every offer adds that `/design`'s description should read "Make a new
Design artifact from a brief"; anything else is a local skill, not the canvas, and not to be run
for it.

**Mutation gate.** The canvas persists under the user's account. This skill never runs it, never
publishes on its own initiative, and never references the canvas from anything tracked in the
repository; the capture discipline records the winning key and notes only.

**Verification record, `design`.** Claim: the bundled `design` skill registers as
model-invocation-disabled, user-invocable, and gated, and settings can remove it
(`disableBundledSkills`, or a `skillOverrides` entry naming `design`). Basis: a binary extraction
of Claude Code 2.1.285 on 2026-09-29 (the `design` registration reads `model_invocable` false,
`user_invocable` true, `gated` true); the `disableBundledSkills` and `skillOverrides` rows on
<https://code.claude.com/docs/en/settings-reference>, fetched that day; the canvas gates per
[reference/bundled-design.md](reference/bundled-design.md). As of 2026-09-29. Recheck when a
release makes the `design` registration model-invocable, changes its description (the identity
string the offer quotes), changes its gating, or splits or merges its registrations.

## Boundary, the built-in `ClaudeDesign` tool

A request to mock up a page can name a Claude Design project the person already has, and then it
means that project, not a new mockup:

- **`ClaudeDesign` (built-in tool)**: lists the person's claude.ai/design projects and reads and
  writes files in an existing one (list, get a project, write, copy, and plan writes). The model
  calls it by name. It does not create a new Design artifact; that is the bundled `design` skill
  above, which the person runs.
- **This skill (marketplace plugin).** Throwaway variants on the real stack or as a local HTML
  mockup; only the winning-variant key survives.

**Routing.** When the person names or links an existing claude.ai/design project, or asks for the
work to go into one, and the `ClaudeDesign` tool resolves in this session, use that tool for the
project's files. Otherwise this skill builds its variants as today. The tool is the project's
editor; this skill is the throwaway comparison.

**Mutation gate.** A `ClaudeDesign` write changes a project the person's team shares. Write only
to the project the person named, and only after they asked for the change. A first write asks the
person for a one-time project approval, or goes through the tool's plan step; the tool refuses
writes in a subagent, in a non-interactive session, and in plan mode without that plan step, so
report the refusal and never retry around it. The four-part records live in
[reference/claude-design-tool.md](reference/claude-design-tool.md).

## Boundary, the marketplace `playground` plugin

Both produce a browser page with controls that change what is shown, so an ask to "try options
visually" can mean either:

- **`playground` (marketplace plugin, first-party, from `anthropics/claude-plugins-official`).** Its
  `playground` skill builds an interactive parameter explorer: controls on one side, a live preview
  on the other, and a prompt at the bottom with a copy button. The output returns to the
  conversation as a prompt.
- **This skill (marketplace plugin).** Switchable UI variants of the user's own project (real
  header, data, and routes, or a local mockup); the winning-variant key is kept and the rest is
  thrown away.

**Routing.** When the ask is to explore a parameter space and hand back a prompt, route it to the
`playground` skill when that plugin is installed, or to `/playgrounds:use` when that wrapper is
installed. When neither is, say the capability exists as an installable plugin and do not build an
imitation. Keep questions about how the user's own screen should be laid out here.

**Mutation gate.** A playground writes its own page; this skill never builds one on its behalf.

**Availability is never assumed.** The plugin is present only where it is installed from its
marketplace; this section states what to do when it resolves, never that it is present. The
four-part records live in [reference/native-playground.md](reference/native-playground.md).

## Next

- A direction wins and is folded in: `/planning:plan`.
- The open question is logic or state rather than appearance: `/prototype:pressure-test`.

## Anti-patterns

Ordered from the costliest outcome on `/shipments` down:

| What goes wrong | What it costs | Prevent it |
|---|---|---|
| B's "Cancel shipment" button calls the live API while the team clicks through the review | A customer's real parcel is cancelled | Point every write (cancel, reroute, refund) at a stub, so the variants are read-only |
| The chosen variant is merged as written | Prototype code with no tests and minimal error handling reaches customers and fails on the first carrier timeout | Rebuild the chosen design to production standards as part of folding it in |
| A gets five sample parcels while B renders the live list of two hundred | B is judged on volume rather than on its layout | Load the records once, above the switcher, and pass the same set to every variant |
| The variants cannot differ: one parcel table recolored three times, or three variants forced into one shared frame with a fixed sidebar and column grid | There is nothing to choose between | Settle the step 2 must-differ rows first, and let each variant own its whole arrangement; share only small parts such as the page header |
