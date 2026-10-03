---
description: "When the built-in ClaudeDesign tool resolves in this session and the person names, links, or asks for work in an existing claude.ai/design project, prefer it for that project; this skill for rendering its own output. Decide the best visual form and medium for what is in the conversation right now, then render it. Use when asked to visualize, diagram, chart, draw, sketch, or render something, or which visual form fits it best. Infers the target, picks a form (a mermaid diagram, a markdown table, a hand-authored SVG/CSS chart, ASCII/Unicode art, code-shape sketches, or a rich rendered page) and a medium (inline terminal, a local HTML file, or a published Artifact), and asks only when the target is ambiguous and no form was named. Routes chart craft and artifact-design fundamentals to those capabilities when installed. Not for polishing a specific chart's colors/axes (a chart-craft/dataviz capability owns that) or restating dense text in plainer words (a comprehension/digest concern)."
argument-hint: "[terminal|file|artifact]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Pick the best visual form for what is in the conversation and render it
---

# Visualize

## Purpose

On demand, at any point in a conversation, decide **what** is most worth showing
visually and **how** to show it, then render it. This skill is a **form + medium
router**: it makes two decisions, the form and the medium, and produces the
output.

## When this fires, and when it does not

- **Fires** when the user asks to see something visually: "visualize this",
  "diagram this", "chart this", "render this as …", "show me …", or a bare
  `/visualization:visualize`.
- **Not chart craft.** Making a specific chart read well, including palette, marks,
  axes, legend, and dark-mode contrast, is a chart-craft/dataviz capability's job. This
  skill decides *that a chart is the right form* and routes the craft out.
- **Not comprehension digest.** Restating a wall of dense text in plainer words,
  or restructuring it for understanding, is a different concern. This skill is
  form-driven (render the content as a visual), not comprehension-driven.

## What you produce

Two decisions, then the rendered output:

1. **Form**. The kind of visual the content wants (Step 2).
2. **Medium**. Where it is delivered (Step 3).

## Step 1: Infer the target

Read where the conversation stands and identify the single thing most worth
showing: a process just described, a set of options compared, a trend in some
numbers, a structure being designed. Usually one target dominates. If two or more
are equally plausible and the user named no form, that is genuine ambiguity.
Carry it to Step 4. Otherwise proceed with the dominant target. Read the chat
history first: the thing just discussed, pasted, or changed is usually the
target, and a shape already shown earlier in the conversation is usually what a
follow-up question is about.

## Step 2: Pick the form

Match the *shape* of the content to a form. The full catalog lives in
[`context/decision-matrix.md`](context/decision-matrix.md): every mermaid
diagram family and when each fits, the zero-dependency chart primitives, and the
rendering-surface facts these rest on. The summary:

| Content shape | Form |
|---|---|
| Flow, process, hierarchy, sequence, state, relationships, timeline | a **mermaid diagram** (pick the family per the catalog) |
| Attributes or options compared across items | a **markdown table** |
| Quantities: trend, distribution, proportion, ranking | a **chart**. Route the craft to a chart-craft/dataviz capability |
| Small structural sketch, box layout, a directory tree as structure | **ASCII / Unicode art** |
| Logic described in prose, or an algorithm before it is written | **pseudocode** (a code-shape sketch) |
| A call path through named functions: orchestration, control flow, a backend-shaped problem | a **call tree** (a code-shape sketch) |
| A UI's component tree, with the state hooks and module boundaries that matter | a **component tree** with file paths (a code-shape sketch) |
| Where things live, or the scope of a refactor | a **shallow file tree**, one line of responsibility per entry (a code-shape sketch) |
| The shape of code before any of it exists | **types and signatures** (a code-shape sketch) |
| What changes, when the surrounding shape is already in the conversation | a **diff-shaped delta** over any of the shapes above (a code-shape sketch) |
| Mostly new code, or a copyable target shape, when no sketch is smaller than the code | **the whole block**, the fallback among the code-shape sketches |
| A composite, interactive, or large multi-part view; an infographic; a short slide deck | a **rich rendered page** |
| A visual layout the user would rather tweak by hand: a UI mockup, screen flow, poster, banner, one-pager | a **rich rendered page**, with the **design canvas** (`/design`, the bundled `design` skill, which the person runs) offered alongside it |

**Code-shape sketches** are fenced text: they render in any GFM surface and need
no page. Tie-break against the mermaid row: when the content is code (named
functions, files, components, types), prefer a code-shape row; when it is a
process, sequence, or state in the domain, prefer a mermaid family. Pseudocode
never paraphrases pasted code when a structural form answers the question. Pick
the smallest view that makes the key point clear, place it beside the short
text it supports, keep only the calls, files, props, states, and boundaries the
question needs, and use one form, sometimes several, rarely all. One example per
form lives in [`context/code-shapes.md`](context/code-shapes.md); its paths and
identifiers are placeholders.

When the form is a chart and a chart-craft/dataviz capability is installed, invoke
it for the craft (form heuristic, palette, mark specs); when it is not installed,
fall back to a simple, honest default (a labeled bar/line as inline SVG on a
page, or a Unicode bar/sparkline in the terminal) and say the craft capability was
unavailable.

When the form is a hand-tweakable visual layout, render this skill's rich page
(or the local file or terminal form Step 3's medium pins) and offer the person the
design canvas. The canvas is the bundled `design` skill, which is reserved for the
person to run: the model never invokes it. It exists only on the published-Artifact
tier, so the offer is also gated on Step 3's medium selection: when an explicit
`terminal`/`file` argument or the configured preference pins delivery on-machine
("never published"), do not offer it. Where the medium permits publishing, offer
it as an explicit alternative, never a silent default: the canvas is a published,
persistent Artifact (default-private, shareable with teammates at the person's
choice; edited in a desktop browser with edits saved automatically, each artboard
exportable as PNG or PDF), where this skill's page paths are throwaway or
plain-static. The Boundary section below carries the sentence to offer and its gate
basis; the canvas surface facts and their verified-on/recheck record live in the
catalog spoke.

## Step 3: Pick the medium

There are three delivery tiers, in ascending richness: **inline terminal → local
HTML file → published Artifact**. Selection layers, first hit wins:

1. **Explicit argument**. A `terminal` / `file` / `artifact` argument forces the tier. With
   no argument, the rungs below decide. The argument picks only the medium; name a form in the
   request itself.
2. **Configured preference**. `${user_config.medium}`. Claude Code text-substitutes
   the configured value into this line; if it still shows the literal
   `${user_config.medium}` token, is empty, or is `auto` (the default), the option
   defers and the next rung resolves. `terminal`, `file`, and `artifact` force
   that tier; any other value is reported and treated as `auto`.
3. **Cascade preference**. The `rendered-views` cascade surface, read only when
   rungs 1-2 are unset: anchor at the repo root (`${CLAUDE_PROJECT_DIR}` when
   set, else `git rev-parse --show-toplevel`), then read whichever of
   `~/.claude/rendered-views.md`, `<root>/.claude/rendered-views.md`, and
   `<root>/.claude/rendered-views.local.md` exist, in that order. The last
   layer that states a `medium:` value wins (per-key override), with the same
   recognized values as rung 2. Verify layer state before honoring a value,
   per the cascade contract's per-layer verdicts: a team layer that is not
   tracked is a hard stop (teammates would never receive it), an overlay that
   is staged or not gitignored is a failure to report (a personal deviation
   could reach history), and the user-global layer takes no git verdict at
   all. Name the winning layer when reporting the
   choice; on a malformed layer, say so and resolve as if that layer were
   absent. All layers absent simply falls through (per
   `docs/conventions/rendered-views/README.md` in the marketplace repository).
4. **Auto**. Decide by the form and its weight: terminal for small, static,
   text-representable output (tables, ASCII, short code, a `mermaid` source fence);
   a rich page for a composite, interactive, large, or truly graphical result
   (rendered diagrams, real charts, dashboards).

**Surface gate: the rich page is a capability that can be absent.** A published
Artifact is heavily gated (plan, sign-in, provider, and version constraints; off
in SDK / CI / MCP contexts). See the catalog. So when a page is warranted:
publish an Artifact only if that surface is available; otherwise write a
self-contained local HTML file and open it; if neither page surface is available,
degrade **visibly** to the best terminal form with a one-line notice. Never assume
the Artifact surface exists. The `file` preference deliberately stays on the
machine (never published); `artifact` prefers publishing but degrades the same way.

**Code-shape sketches take this same ladder** (under auto they stay in the
terminal, per rung 4; `file`, `artifact`, and the configured preference are
honored for them as for any form), with one exception: a pull-request diff,
fetched content, or another repository's files are never rendered to HTML until
this lane is wired through the rendered-views escape helper. That exception overrides rung 1 and the
preference; when a page was asked for, say in one line why it was not produced.

**Page chrome.** When authoring a rich page, take the palette, type stacks,
radii, and accessibility floor (link/focus contrast tokens, color-scheme and
reduced-motion behavior) from this plugin's bundled chrome reference,
`${CLAUDE_PLUGIN_ROOT}/reference/html-chrome.html`, rather than inventing a
look per page. The chrome does not settle layout habits, so name the ones to leave
out: italic accent words in headings, numbered "01 / 02 / 03" section labels,
pill-shaped buttons or badges, and a hero banner above the content, plus any style
the user names. When the user dislikes a choice in the rendered page, add it to
that list for the rest of the session and render again. A general "avoid a generic
look" only swaps one default for another.

**Local-file placement.** Write the local HTML file via the platform's temp
primitive, never into the consumer's repository tree. On Unix/Linux/Git Bash,
create a private run directory and echo it in the same call,
`d=$(mktemp -d "${TMPDIR:-/tmp}/visualize-XXXXXX"); echo "$d"`, then write the
page to `<echoed dir>/visualize.html`. Echo it because shell state does not
survive between Bash calls: the directory name is random, so an unechoed path is
unrecoverable in the call that writes the file. Carry the temp root in the positional template, the one form GNU and BSD `mktemp` accept identically, since `-p`/`--tmpdir`/`-t` differ between the dialects and a bare relative template silently creates the file in the **current directory**, the consumer's repository. Keep the `XXXXXX` placeholders **trailing**. BSD `mktemp` (macOS) substitutes only trailing Xs, so an extension after them is not portable.
That is why the page takes a fixed name inside the generated directory rather
than a `visualize-XXXXXX.html` template, which macOS cannot create at all. On Windows,
a user-scoped temp under
`%LOCALAPPDATA%\Temp`. One file per run. The path is handed back to the user, so
do not delete it. It must still be readable when they open it. Open it for the
user (`start <path>` on Windows, `open <path>` on macOS, `xdg-open <path>` on
Linux) and report the absolute path.

A **mermaid diagram** is the sharp case: it renders natively only on a published
Artifact. A local HTML file renders it only if the page **embeds** a mermaid
renderer inline. Keep the file self-contained; never load a renderer from the
network, which breaks offline use and, for `file` or otherwise sensitive output,
would expose the page to a third party. A plain file with a bare `mermaid` block
does not render. So if no mermaid-capable surface is reachable and no trusted
renderer can be embedded, deliver the mermaid **source** fence in the terminal and
say it is unrendered. Never open a page that shows source instead of the promised
picture.

Parse every mermaid block before it is emitted, whatever the medium. Write each diagram to a
`.mmd` file (or use the markdown file holding the ` ```mermaid ` fence) and run:

```bash
node "${CLAUDE_PLUGIN_ROOT}/lib/mermaid-gate.mjs" [--svg-dir "<dir>"] <file>...
```

Stdout is one JSON report; each block has `file`, `line`, `status` (`ok` or `error`) and `render`
(`svg` or `source`). Exit 1 means a block failed to parse. For a local file, pass `--svg-dir` and
embed the SVG a block names in place of the fence. For an Artifact, omit `--svg-dir`: the Artifact
renders mermaid natively and needs the parse only.

- `status: error`: do not write the page. Report the block's `file`, `line` and `error`, fix the
  diagram, run the gate again.
- `render: source`: keep the mermaid source and print the block's `reason` beside it. Never call
  such a page rendered.
- Without `mmdc` the parse is a structural check (unknown diagram type, unterminated quote,
  unbalanced flowchart brackets), so say an `ok` does not prove every syntax error is absent.
- The gate uses `mmdc` only at the minimum version in `prerequisites.json` or newer, found on PATH
  or at `node_modules/.bin/mmdc` under the working directory. An older one is treated as absent.
  A failure that is not a parse error (no Chrome) falls back to source with the failure as the
  reason. Pointer: <https://github.com/mermaid-js/mermaid-cli/releases>. As of 2026-10-03.
  Recheck when the Artifact runtime's Mermaid version (see `context/decision-matrix.md`) moves to
  a different major.
- Check the prerequisites with
  `node "${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.mjs" check "${CLAUDE_PLUGIN_ROOT}" --data-dir "${CLAUDE_PLUGIN_DATA}"`.

Honor a preference without overproducing: `artifact` still renders a trivial
three-row table inline, and `terminal` degrades a rich form to its best terminal
approximation with a visible note rather than dropping detail silently.

## Step 4: Ask only on genuine ambiguity

Two things can be ambiguous independently: **what** to show (the target) and
**which form**. Ask the user **one** question, with a RECOMMENDED default listed
first, when either is genuinely ambiguous:

- **Target ambiguity**. Several equally plausible things to show. Ask which, *even
  if a form was named*: naming "diagram this" fixes the *how*, not the *what*.
- **Form ambiguity**. The target is clear, no form was named, and two forms fit it
  about equally. Ask which form. The common case is pasted code with little
  conversational context: when two or more code-shape forms fit it about equally,
  ask one question listing those two to four forms, the recommended one first,
  and render nothing until the answer. When one form clearly dominates (a
  comparison is a table, a series is a chart, a where-does-this-live question is
  a file tree), render it without asking.

The pasted-code case honors `${user_config.thin_context_prompt}`. Claude Code
text-substitutes the configured value into this line; if it still shows the
literal `${user_config.thin_context_prompt}` token or is empty, the option is
unset and `auto` applies. `auto` is the behavior above; `always` offers the
ranked menu on any bare code paste; `never` renders the recommended form without
asking. Any other value is reported and treated as `auto`.

When neither is ambiguous, meaning a dominant target and a clear best form, proceed with
the matrix's pick: good defaults, no nagging. A specified form or medium is honored
and simply removes that axis from any question, with one carve-out: Step 3's
terminal-only exception for a pull-request diff, fetched content, or another
repository's files overrides a requested `file` or `artifact` medium. Never
interrogate form by form; one question, then render.

## Step 5: Render

- **Terminal** renders GitHub-flavored markdown: tables, fenced code, blockquotes,
  ASCII/Unicode. A ` ```mermaid ` block in the terminal is shown as **source, not a
  rendered diagram**, so emit it as portable source the user can render elsewhere,
  and prefer a page when the *rendered* diagram is the point.
- **A rich page** follows the Artifact tool's own contract and, when an
  artifact-design capability is installed, its guidance. The page-contract facts
  live once in [`context/decision-matrix.md`](context/decision-matrix.md). When the subject is a
  product UI, match that product's own colors, type, spacing, and components rather than the
  plugin chrome; use real labels and data; support desktop and mobile.
- Report what you produced and, for a page, its path or link.

## Gotchas

- **Terminal mermaid is source, not a picture.** If the user wants to *see* the
  rendered diagram and no page surface is available, say so. Do not imply the
  fence renders inline.
- **Do not overproduce a page.** A three-row comparison is a table; forcing it into
  an Artifact is worse, not richer. Match richness to the content.
- **The Artifact surface is often unavailable.** Gate on it; never let a missing
  surface become a silent failure. Degrade visibly to a local file or terminal.
- **Craft is not this skill's job.** If you find yourself writing palette or axis
  guidance, stop and route to the chart-craft capability instead.
- **A newer mermaid family may not render** in the bundled artifact renderer
  (the 13 stable families are safe; the newest set is unverified. See the
  catalog). Prefer a stable family, or verify before relying on a new one.

## Boundary

An **interactive parameter explorer whose output returns as a prompt** (controls
beside a live preview with a copy-out prompt, the "playground" shape) is not a form
this skill renders. When the first-party `playground` plugin is installed, route the
request to its `playground` skill, or to the `playgrounds` wrapper's `/playgrounds:use`
when that wrapper is enabled, which also owns the install uplift and cloud delivery
guidance. When neither is enabled, say the capability exists as an installable
plugin and continue with this skill's closest static form (a rich page without the
round-trip controls), never a hand-built imitation of the explorer.

The **design canvas** is the bundled `design` skill, a native surface this skill overlaps on
hand-tweakable layouts, so a request for a mockup or a one-pager can mean either:

- **`design` (bundled skill)**: drafts artboards on one canvas, published as a persistent,
  shareable Claude Design Artifact under the person's account that they edit in a desktop browser. It is reserved for the
  person to run; the model does not invoke it.
- **This skill (marketplace plugin)**: picks the form and medium and renders a throwaway or
  plain-static page.

**Routing:** when the form is a hand-tweakable layout and Step 3's medium permits publishing,
render this skill's page and tell the person: If /design is available in your session (gate
basis: the verification record below), you can run it instead of or alongside this skill for a
hand-editable design canvas. A local skill named `design` at any level silently shadows the
bundled command, and the bundled one never appears in your skill listing, so a `design` entry in
that listing is a shadowing local skill: do not make the offer, and tell the person a local
`design` skill shadows the bundled canvas command. A local `design` skill that disables model
invocation shadows it too and is hidden from you, so every offer adds that `/design`'s description
should read "Make a new Design artifact from a brief"; anything else is a local skill, not the
canvas, and not to be run for it.

**Mutation gate:** the canvas publishes a persistent Artifact under the person's account, so it is
never a silent default and nothing tracked in a repository references it. This skill never runs it.

**Verification record, `design`.** Claim: the bundled `design` skill registers as
model-invocation-disabled, user-invocable, and gated, and settings can remove it
(`disableBundledSkills`, or a `skillOverrides` entry naming `design`). Basis: a binary extraction
of Claude Code 2.1.285 on 2026-09-29 (the `design` registration reads `model_invocable` false,
`user_invocable` true, `gated` true); the `disableBundledSkills` and `skillOverrides` rows on
<https://code.claude.com/docs/en/settings-reference>, fetched that day. As of 2026-09-29.
Recheck when a release makes the `design` registration model-invocable, changes its description
(the identity string the offer quotes), changes its gating, or splits or merges its
registrations. The remaining surface facts live in the catalog spoke's
design canvas section ([context/decision-matrix.md](context/decision-matrix.md)).

A request to draw a layout or a deck can name a Claude Design project the person already has, and
then it means that project, not a new render:

- **`ClaudeDesign` (built-in tool)**: lists the person's claude.ai/design projects and reads and
  writes files in an existing one (list, get a project, write, copy, and plan writes). The model
  calls it by name. It does not create a new Design artifact; that is the bundled `design` skill
  above, which the person runs.
- **This skill (marketplace plugin)**: picks the form and medium and renders its own output.

**Routing:** when the person names or links an existing claude.ai/design project, or asks for the
work to go into one, and the `ClaudeDesign` tool resolves in this session, use that tool for the
project's files. Otherwise this skill renders its own output as today. The tool is the project's
editor; this skill is the form and medium router.

**Mutation gate:** a `ClaudeDesign` write changes a project the person's team shares. Write only
to the project the person named, and only after they asked for the change. A first write asks the
person for a one-time project approval, or goes through the tool's plan step; the tool refuses
writes in a subagent, in a non-interactive session, and in plan mode without that plan step, so
report the refusal and never retry around it. The four-part records live in
[context/claude-design-tool.md](context/claude-design-tool.md).

## What this skill does NOT do

- **Does not teach chart craft**. Palette, axes, marks route to a chart-craft/dataviz capability.
- **Does not teach artifact-design fundamentals**. Those route to an artifact-design capability and the Artifact tool's contract.
- **Does not restate rendering-surface facts**. They live once in the catalog spoke.
- **Does not digest or re-explain dense text**. That is a comprehension concern, not a form concern.
- **Does not explain a topic from zero prior knowledge**. A one-idea-per-diagram picture explainer that assumes the reader knows nothing is `education:eli5` (if enabled). This skill picks a form for what is already in the conversation.
- **Does not render a pull-request diff, fetched content, or another repository's files to HTML** until this lane is wired through the rendered-views escape helper. Those stay terminal fences.
- **Does not publish an Artifact when that surface is absent or when the preference is `file`**. It degrades to a local file or terminal.
