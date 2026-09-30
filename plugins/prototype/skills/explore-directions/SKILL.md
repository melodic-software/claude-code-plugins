---
description: "Builds throwaway UI variations, several radically different layouts on one route switchable from a floating bar, to answer 'what should this look like' before committing to a design. Use when the question is what a page, screen, or dashboard should look like, or for design options to compare: 'mock up a UI', 'what should this page look like', 'try a different layout'. Runs on the real stack by default (real header, data, and density) or as a self-contained HTML mockup; the user flips between variants, keeps one or bits of each, and discards the rest. Logic or state questions: /prototype:pressure-test. Not for an interactive parameter explorer whose output returns as a prompt: that is the first-party playground skill, routed via /playgrounds:use where the upstream playground plugin is installed from its marketplace."
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

Generate **several radically different visual variations** on a single route, switchable from a
floating control bar. The user flips between variants in the browser, picks one (or steals bits
from each), then throws the rest away.

The shared throwaway rules, the auto-invoke gate, and how to capture the answer live in
[`${CLAUDE_PLUGIN_ROOT}/context/discipline.md`](../../context/discipline.md). Read it before you
start. This file covers only the UI facet.

If the question is about logic/state rather than appearance. Wrong facet. Invoke `/prototype:pressure-test` via the Skill tool.

## When this is the right shape

- "What should this page look like?"
- "Show me a few options for this dashboard."
- "Try a different layout for the settings screen."
- Any time the user would otherwise spend a day picking between vague mockups in their head

## Two sub-shapes. Prefer A

UI prototypes are easier to judge against the rest of the app. Real header, real sidebar, real
data, real density. Default to sub-shape A whenever a plausible existing page exists.

Two substrates back these variants, the **real stack** (default) and a **self-contained HTML
mockup**. Both run the same variant-comparison process below; only the substrate swaps. Pick by
intent, not by mount target:

- **Existing page** (or a new thing that naturally lives inside one) → real-stack **sub-shape A**
  (the default).
- **No existing page, want it judged in the real app**. Real components, real density, needs the
  app plus a dev server → real-stack **sub-shape B**.
- **No existing page, want the fastest standalone feel**. No app or dev server running, no app
  yet, or a non-dev exploring → the **HTML mockup substrate** (below).
- **Explicit override wins both ways**. Ask for a real-stack page or an HTML mockup directly and
  that beats the default routing.

The HTML mockup is a sibling of sub-shape B: both answer "no existing page," split only by whether
you want the variant judged inside the real app or as the fastest throwaway standalone.

### Sub-shape A. Adjustment to existing page (preferred)

The route already exists. Variants are rendered on the same route, gated by a `?variant=` URL param
(or framework equivalent). Existing data fetching, params, and auth stay. Only the rendered
subtree swaps.

If you're prototyping something that doesn't have a page yet but WOULD naturally live inside one (a
new dashboard section, a new card on settings, a new step in an existing flow). Still sub-shape A.
Mount variants inside the host page.

### Sub-shape B. New page (last resort)

Only when the thing being prototyped has no existing page to live inside, an entirely new
top-level surface, or a flow that can't embed anywhere sensible.

Create a throwaway route following the project's existing routing convention. Name it obviously as
a prototype (include "prototype" in the path or filename). Same `?variant=` pattern.

Before committing to B, is there really no existing page this could embed in? An empty route hides
design problems a populated one would expose.

## HTML mockup substrate

When the intent selector routes here, no app or dev server, no app yet, or a non-dev exploring,
the variants live in one self-contained `file://` HTML page with synthetic data and an in-page
switcher. Assemble one per task (there is no canned template to copy):

1. **N variant containers**. One block per variant, all in the single page.
2. **An in-memory switcher**. `file://` has no routing, so there is no `?variant=` URL; toggle
   container visibility in memory instead. Give it a floating control bar with left/right arrows
   and keyboard nav, modeled on the real-stack switcher in step 4 below.
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
  the file. Carry the temp root in the positional template, the one form GNU and BSD `mktemp` accept identically, since `-p`/`--tmpdir`/`-t` differ between the dialects and a bare relative template silently creates the file in the **current directory**, the consumer's repository. Keep the `XXXXXX` placeholders **trailing**. BSD `mktemp` (macOS) substitutes only trailing Xs, so an extension after them is not portable (per `docs/conventions/topic-docs/README.md` "The ephemeral tier" in the marketplace repository).
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
  declaration is what produces variety. Also name the defaults no variant may fall back on: a
  cream or off-white background, italic accent words in headings, numbered "01 / 02 / 03"
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

### 1. State the question and pick N

Default to **3 variants**. More than 5 stops being radically different and starts being noise. Cap
there.

Write the plan in one line: "Three variants of the settings page, switchable via `?variant=`, on
the existing `/settings` route."

### 2. Generate radically different variants

Each variant must respect:

- The page's purpose and available data
- The project's component library / styling system
- A clear exported component name (`VariantA`, `VariantB`, `VariantC`)

**Variants must be structurally different and visually distinct**. Different layout, different
information hierarchy, different primary affordance; a recolor alone is not a variant. Three
slightly-tweaked card grids isn't a UI prototype, it's wallpaper. <!-- ai-slop-ignore: deliberate voice; the contrast is the operative point --> Structure is the floor, not the
whole exercise: on the real stack the project's styling system carries the visual axis, and where
it leaves room (and always on the HTML mockup substrate) each variant also declares its own visual
direction rather than sharing one default aesthetic. If two drafts come out too similar, redo one
with an explicit constraint ("do not use a card grid").

### 3. Wire them together

A single switcher component on the route. Framework-idiomatic routing. Use the `?variant=` param
or equivalent. For sub-shape A, keep all existing data fetching above the switcher; only the
rendered subtree changes per variant.

### 4. Build the floating switcher

A small fixed-position bar at bottom-center with:

- **Left/right arrows**. Cycle between variants (wrap around)
- **Variant label**. Current key + descriptive name if exported
- **Keyboard nav**. Arrow keys cycle (don't intercept when an input/textarea is focused)

Requirements:

- Update the URL param on switch (shareable, reload-stable)
- Visually distinct from the page being evaluated (high-contrast pill, subtle shadow)
- Hidden in production builds. Gate on an environment check
- Single shared component so both sub-shapes reuse it

### 5. Hand it over

Surface the URL and variant keys. Interesting feedback is usually "I want the header from B with
the sidebar from C". That's the actual design discovered. Close the handover with a
machine-legible reply template the user fills, so their reaction comes back as the next prompt
rather than prose to re-parse (on the mockup substrate this is what the copy-out terminator
lifts):

```text
direction: <winning variant key, or "graft">
steal: <piece> from <variant>   (repeat per piece)
skip: <piece or variant> because <one line>
next-target: <what to explore or build next>
```

### 6. Capture the answer and clean up

Per the shared discipline. Record which variant won and why, and record the directions that lost
with their reasons. Capture at single-decision granularity: each named piece (a header, a
hierarchy choice, a primary affordance) gets its own steal/skip/adapt entry, so grafts compose
across variants instead of collapsing into one "variant B, mostly" note. When the verdict is a
graft rather than a single winner, say which piece came from where **and what the discarded parts
held that the graft deliberately left behind**. The deletions below are irreversible: whatever is
not written down now is gone.

- **Sub-shape A**. Delete losing variants and the switcher; fold the winner into the existing page.
- **Sub-shape B**. Promote the winner to a real route; delete the throwaway route and switcher.
- **HTML mockup substrate**. Discard the mockup file once the winning-variant key and notes are
  captured; nothing tracked is left behind.
- **Design canvas**, when the user ran `/design`. Capture the winning-variant key and notes the
  same way; then ask whether the user wants the canvas kept (it persists under their account) or cleared. Nothing tracked
  references it either way.

Don't leave variant components or the switcher lying around. They rot fast.

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
shape.

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
release makes the `design` registration model-invocable, changes its gating, or splits or merges
its registrations.

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
imitation. Keep "what should this page look like" here.

**Mutation gate.** A playground writes its own page; this skill never builds one on its behalf.

**Availability is never assumed.** The plugin is present only where it is installed from its
marketplace; this section states what to do when it resolves, never that it is present. The
four-part records live in [reference/native-playground.md](reference/native-playground.md).

## Next

- A direction wins and is folded in: `/planning:plan`.
- The open question is logic or state rather than appearance: `/prototype:pressure-test`.

## Anti-patterns

- **Variants differing only in color or copy.** That's a tweak, not a prototype. Real variants
  disagree about structure, and then differ visually on top of it, not instead of it.
- **Sharing too much code between variants.** A shared `<Header>` is fine; a shared `<Layout>`
  defeats the point. Each variant should be free to throw out the layout.
- **Wiring variants to real mutations.** Read-only prototypes are fine. Stub mutations. The
  question is "what should this look like", not "does the backend work".
- **Promoting a prototype directly to production.** Variant code was written under prototype
  constraints (no tests, minimal error handling). Rewrite properly when folding in.
