---
name: visualize
description: "Decide the best visual FORM and MEDIUM for what is in the conversation right now, then render it. Use when: 'visualize', 'visualize this', 'show me a diagram of this', 'diagram this', 'render this as', 'draw this', 'sketch this', 'make a picture of this', 'what is the best way to show this', 'turn this into a visual'. Infers the target from the conversation, picks a form (a mermaid diagram, a markdown table, a hand-authored SVG/CSS chart, ASCII/Unicode art, or a rich rendered page) and a medium (inline terminal, a local HTML file, or a published Artifact), renders good defaults, and asks ONLY when the target is genuinely ambiguous and no form was named. It ROUTES chart craft and artifact-design fundamentals to those capabilities when installed — it does not teach them. Not for polishing a specific chart's colors/axes (a chart-craft/dataviz capability owns that) or restating dense text in plainer words (a comprehension/digest concern)."
argument-hint: "[terminal|file|artifact] — omit to auto-decide; name a form in the request itself"
user-invocable: true
---

# Visualize

## Purpose

On demand, at any point in a conversation, decide **what** is most worth showing
visually and **how** to show it, then render it. This skill is a **form + medium
router**: it makes two decisions — the form and the medium — and produces the
output. It is not a craft teacher. The craft of a good chart, and the fundamentals
of a good rich page, are owned by other capabilities; this skill routes to them
and never restates them.

## When this fires — and when it does not

- **Fires** when the user asks to see something visually: "visualize this",
  "diagram this", "chart this", "render this as …", "show me …", or a bare
  `/visualize`.
- **Not chart craft.** Making a specific chart read well — palette, marks, axes,
  legend, dark-mode contrast — is a chart-craft/dataviz capability's job. This
  skill decides *that a chart is the right form* and routes the craft out.
- **Not comprehension digest.** Restating a wall of dense text in plainer words,
  or restructuring it for understanding, is a different concern. This skill is
  form-driven (render the content as a visual), not comprehension-driven.

## What you produce

Two decisions, then the rendered output:

1. **Form** — the kind of visual the content wants (Step 2).
2. **Medium** — where it is delivered (Step 3).

## Step 1 — Infer the target

Read where the conversation stands and identify the single thing most worth
showing — a process just described, a set of options compared, a trend in some
numbers, a structure being designed. Usually one target dominates. If two or more
are equally plausible and the user named no form, that is genuine ambiguity —
carry it to Step 4. Otherwise proceed with the dominant target.

## Step 2 — Pick the form

Match the *shape* of the content to a form. The full catalog — every mermaid
diagram family and when each fits, the zero-dependency chart primitives, and the
rendering-surface facts these rest on — lives in
[`context/decision-matrix.md`](context/decision-matrix.md); the summary:

| Content shape | Form |
|---|---|
| Flow, process, hierarchy, sequence, state, relationships, timeline | a **mermaid diagram** (pick the family per the catalog) |
| Attributes or options compared across items | a **markdown table** |
| Quantities: trend, distribution, proportion, ranking | a **chart** — route the craft to a chart-craft/dataviz capability |
| Small structural sketch, directory tree, box layout | **ASCII / Unicode art** |
| A composite, interactive, or large multi-part view | a **rich rendered page** |

When the form is a chart and a chart-craft/dataviz capability is installed, invoke
it for the craft (form heuristic, palette, mark specs); when it is not installed,
fall back to a simple, honest default (a labelled bar/line as inline SVG on a
page, or a Unicode bar/sparkline in the terminal) and say the craft capability was
unavailable. Never restate its craft here.

## Step 3 — Pick the medium

There are three delivery tiers, in ascending richness: **inline terminal → local
HTML file → published Artifact**. Selection layers, first hit wins:

1. **Explicit argument** — a `terminal` / `file` / `artifact` argument forces the tier.
2. **Configured preference** — `${user_config.medium}` (`auto`, `terminal`,
   `file`, or `artifact`; an unrecognized value is reported and treated as `auto`).
3. **Auto** — decide by the form and its weight: terminal for small, static,
   text-representable output (tables, ASCII, short code, a `mermaid` source fence);
   a rich page for a composite, interactive, large, or truly graphical result
   (rendered diagrams, real charts, dashboards).

**Surface gate — the rich page is a capability that can be absent.** A published
Artifact is heavily gated (plan, sign-in, provider, and version constraints; off
in SDK / CI / MCP contexts) — see the catalog. So when a page is warranted:
publish an Artifact only if that surface is available; otherwise write a
self-contained local HTML file and open it; if neither page surface is available,
degrade **visibly** to the best terminal form with a one-line notice. Never assume
the Artifact surface exists. The `file` preference deliberately stays on the
machine (never published); `artifact` prefers publishing but degrades the same way.

Honor a preference without overproducing: `artifact` still renders a trivial
three-row table inline, and `terminal` degrades a rich form to its best terminal
approximation with a visible note rather than dropping detail silently.

## Step 4 — Ask only on genuine ambiguity

Two things can be ambiguous independently — **what** to show (the target) and
**which form**. Ask the user **one** question, with a RECOMMENDED default listed
first, when either is genuinely ambiguous:

- **Target ambiguity** — several equally plausible things to show. Ask which, *even
  if a form was named*: naming "diagram this" fixes the *how*, not the *what*.
- **Form ambiguity** — the target is clear, no form was named, and two forms fit it
  about equally. Ask which form.

When neither is ambiguous — a dominant target and a clear best form — proceed with
the matrix's pick: good defaults, no nagging. A specified form or medium is always
honored and simply removes that axis from any question.

## Step 5 — Render

- **Terminal** renders GitHub-flavored markdown — tables, fenced code, blockquotes,
  ASCII/Unicode. A ` ```mermaid ` block in the terminal is shown as **source, not a
  rendered diagram**, so emit it as portable source the user can render elsewhere,
  and prefer a page when the *rendered* diagram is the point.
- **A rich page** follows the Artifact tool's own contract and, when an
  artifact-design capability is installed, its guidance. The page-contract facts
  live once in [`context/decision-matrix.md`](context/decision-matrix.md) — do not
  restate them here.
- Report what you produced and, for a page, its path or link.

## Gotchas

- **Terminal mermaid is source, not a picture.** If the user wants to *see* the
  rendered diagram and no page surface is available, say so — do not imply the
  fence renders inline.
- **Do not overproduce a page.** A three-row comparison is a table; forcing it into
  an Artifact is worse, not richer. Match richness to the content.
- **The Artifact surface is often unavailable.** Gate on it; never let a missing
  surface become a silent failure — degrade visibly to a local file or terminal.
- **Craft is not this skill's job.** If you find yourself writing palette or axis
  guidance, stop and route to the chart-craft capability instead.
- **A newer mermaid family may not render** in the bundled artifact renderer
  (the 13 stable families are safe; the newest set is unverified — see the
  catalog). Prefer a stable family, or verify before relying on a new one.

## What this skill does NOT do

- **Does not teach chart craft** — palette, axes, marks route to a chart-craft/dataviz capability.
- **Does not teach artifact-design fundamentals** — those route to an artifact-design capability and the Artifact tool's contract.
- **Does not restate rendering-surface facts** — they live once in the catalog spoke.
- **Does not digest or re-explain dense text** — that is a comprehension concern, not a form concern.
- **Does not publish an Artifact when that surface is absent or when the preference is `file`** — it degrades to a local file or terminal.
