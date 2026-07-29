---
name: explore-directions
description: "Builds throwaway UI variations — several radically different visual layouts on one route, switchable from a floating control bar — to answer 'what should this look like' before committing to a design. Use when: 'mock up a UI', 'try a few designs', 'what should this page look like', 'show me options for this dashboard', 'try a different layout for the settings screen', 'prototype this screen', 'explore design options'. Runs on your real stack by default (real header, real data, real density) or as a self-contained HTML mockup; you flip between variants, pick one (or steal bits from each), and throw the rest away. Not for logic or state questions — use /prototype:pressure-test for those."
argument-hint: "[scope] (e.g., /prototype:explore-directions settings page)"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(git branch:*)", "Bash(git status:*)", "Bash(head:*)", "Bash(echo:*)", "Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/detect-ecosystems.sh:*)"]
shell: bash
metadata:
  workflow-stage: plan
  summary: Throwaway UI variations answering what should this look like
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Working tree status: !`git status --porcelain 2>/dev/null | head -10 || echo "clean"`
Project ecosystems: !`bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-ecosystems.sh" 2>/dev/null || echo "none detected"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Generate **several radically different visual variations** on a single route, switchable from a
floating control bar. The user flips between variants in the browser, picks one (or steals bits
from each), then throws the rest away.

The shared throwaway rules, the auto-invoke gate, and how to capture the answer live in
[`${CLAUDE_PLUGIN_ROOT}/context/discipline.md`](../../context/discipline.md) — read it before you
start. This file covers only the UI facet.

If the question is about logic/state rather than appearance — wrong facet. Use `/prototype:pressure-test`.

## When this is the right shape

- "What should this page look like?"
- "Show me a few options for this dashboard."
- "Try a different layout for the settings screen."
- Any time the user would otherwise spend a day picking between vague mockups in their head

## Two sub-shapes — prefer A

UI prototypes are easier to judge against the rest of the app — real header, real sidebar, real
data, real density. Default to sub-shape A whenever a plausible existing page exists.

Two substrates back these variants — the **real stack** (default) and a **self-contained HTML
mockup**. Both run the same variant-comparison process below; only the substrate swaps. Pick by
intent, not by mount target:

- **Existing page** (or a new thing that naturally lives inside one) → real-stack **sub-shape A**
  (the default).
- **No existing page, want it judged in the real app** — real components, real density, needs the
  app plus a dev server → real-stack **sub-shape B**.
- **No existing page, want the fastest standalone feel** — no app or dev server running, no app
  yet, or a non-dev exploring → the **HTML mockup substrate** (below).
- **Explicit override wins both ways** — ask for a real-stack page or an HTML mockup directly and
  that beats the default routing.

The HTML mockup is a sibling of sub-shape B: both answer "no existing page," split only by whether
you want the variant judged inside the real app or as the fastest throwaway standalone. It is not a
second axis layered over A and B.

### Sub-shape A — adjustment to existing page (preferred)

The route already exists. Variants are rendered on the same route, gated by a `?variant=` URL param
(or framework equivalent). Existing data fetching, params, and auth stay — only the rendered
subtree swaps.

If you're prototyping something that doesn't have a page yet but WOULD naturally live inside one (a
new dashboard section, a new card on settings, a new step in an existing flow) — still sub-shape A.
Mount variants inside the host page.

### Sub-shape B — new page (last resort)

Only when the thing being prototyped has no existing page to live inside — an entirely new
top-level surface, or a flow that can't embed anywhere sensible.

Create a throwaway route following the project's existing routing convention. Name it obviously as
a prototype (include "prototype" in the path or filename). Same `?variant=` pattern.

Before committing to B — is there really no existing page this could embed in? An empty route hides
design problems a populated one would expose.

## HTML mockup substrate

When the intent selector routes here — no app or dev server, no app yet, or a non-dev exploring —
the variants live in one self-contained `file://` HTML page with synthetic data and an in-page
switcher. Same variant-comparison process as the real stack; the substrate is the only thing that
changes. Assemble one per task (there is no canned template to copy):

1. **N variant containers** — one block per variant, all in the single page.
2. **An in-memory switcher** — `file://` has no routing, so there is no `?variant=` URL; toggle
   container visibility in memory instead. Give it a floating control bar with left/right arrows
   and keyboard nav, modeled on the real-stack switcher in step 4 below.
3. **A copy-out terminator** — a small control that lifts the winning-variant key plus notes back
   out as text you can paste into your durable answer.

Constraints:

- **Synthetic data only.** A throwaway prototype binds synthetic data, never real or captured
  values.
- **No remote fetch by construction.** Vendor everything inline so the page opens straight from
  `file://` — no external scripts, fonts, or data fetches. Enforce this rather than trusting it:
  emit a restrictive CSP meta tag in the page `<head>` so the browser blocks any remote resource —
  `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:">`.
  Inline `<style>` and inline `<script>` stay allowed (the in-page switcher needs inline script);
  only remote origins — CDNs, web fonts, `fetch`/XHR — are forbidden.
- **Ephemeral placement.** Generate the mockup via the platform's temp primitive — never a tracked
  path and never inside the repo. On Unix/Linux/Git Bash, create a private run directory and write
  the page inside it, echoing the directory in the same call —
  `d=$(mktemp -d "${TMPDIR:-/tmp}/explore-directions-XXXXXX"); echo "$d"` — then writing to
  `<echoed dir>/explore-directions.html`. Echo it because shell state does not survive between Bash
  calls: the directory name is random, so an unechoed path is unrecoverable in the call that writes
  the file. Carrying the temp root in the positional template is the one
  `mktemp` form GNU and BSD/macOS accept identically (`--tmpdir` is absent on BSD, `-t` is
  deprecated on GNU), and the directory carries the `.html` name without depending on `mktemp`
  accepting a suffix after the `XXXXXX`. On Windows, a user-scoped temp under
  `%LOCALAPPDATA%\Temp`. One file per run. The path is handed to the user to open from `file://`,
  so do not delete it — it must still be readable when they open it.
- **Markdown captures the answer.** Copy the winning-variant key and notes into your durable
  answer (per the shared discipline); the HTML is throwaway.

## Process

### 1. State the question and pick N

Default to **3 variants**. More than 5 stops being radically different and starts being noise — cap
there.

Write the plan in one line: "Three variants of the settings page, switchable via `?variant=`, on
the existing `/settings` route."

### 2. Generate radically different variants

Each variant must respect:

- The page's purpose and available data
- The project's component library / styling system
- A clear exported component name (`VariantA`, `VariantB`, `VariantC`)

**Variants must be structurally different** — different layout, different information hierarchy,
different primary affordance. Not just different colors. Three slightly-tweaked card grids isn't a
UI prototype, it's wallpaper. If two drafts come out too similar, redo one with an explicit
constraint ("do not use a card grid").

### 3. Wire them together

A single switcher component on the route. Framework-idiomatic routing — use the `?variant=` param
or equivalent. For sub-shape A, keep all existing data fetching above the switcher; only the
rendered subtree changes per variant.

### 4. Build the floating switcher

A small fixed-position bar at bottom-center with:

- **Left/right arrows** — cycle between variants (wrap around)
- **Variant label** — current key + descriptive name if exported
- **Keyboard nav** — arrow keys cycle (don't intercept when an input/textarea is focused)

Requirements:

- Update the URL param on switch (shareable, reload-stable)
- Visually distinct from the page being evaluated (high-contrast pill, subtle shadow)
- Hidden in production builds — gate on an environment check
- Single shared component so both sub-shapes reuse it

### 5. Hand it over

Surface the URL and variant keys. Interesting feedback is usually "I want the header from B with
the sidebar from C" — that's the actual design discovered.

### 6. Capture the answer and clean up

Per the shared discipline — record which variant won and why.

- **Sub-shape A** — delete losing variants and the switcher; fold the winner into the existing page.
- **Sub-shape B** — promote the winner to a real route; delete the throwaway route and switcher.
- **HTML mockup substrate** — discard the mockup file once the winning-variant key and notes are
  captured; nothing tracked is left behind.

Don't leave variant components or the switcher lying around. They rot fast.

## Anti-patterns

- **Variants differing only in color or copy.** That's a tweak, not a prototype. Real variants
  disagree about structure.
- **Sharing too much code between variants.** A shared `<Header>` is fine; a shared `<Layout>`
  defeats the point. Each variant should be free to throw out the layout.
- **Wiring variants to real mutations.** Read-only prototypes are fine. Stub mutations — the
  question is "what should this look like", not "does the backend work".
- **Promoting a prototype directly to production.** Variant code was written under prototype
  constraints (no tests, minimal error handling). Rewrite properly when folding in.
