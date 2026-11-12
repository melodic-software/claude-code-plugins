---
description: "When the built-in ClaudeDesign tool resolves in this session and the person names, links, or asks for work in an existing claude.ai/design project, prefer it for that project; this skill for rendering its own output. Decide the best visual form and medium for what is in the conversation right now, then render it. Use when asked to visualize, diagram, chart, draw, sketch, or render something, or which visual form fits it best. Infers the target, picks a form (a mermaid diagram, a markdown table, a hand-authored SVG/CSS chart, ASCII/Unicode art, code-shape sketches, or a rich rendered page) and a medium through the shared medium resolver, and asks only when the target is ambiguous and no form was named. Routes chart craft and artifact-design fundamentals to those capabilities when installed. Not for polishing a specific chart's colors/axes (a chart-craft/dataviz capability owns that) or restating dense text in plainer words (a comprehension/digest concern)."
argument-hint: "[<medium>] [--unattended]"
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
| A composite, interactive, or large multi-part view; an infographic | a **rich rendered page** |
| A slide deck | hand off to `/visualization:present`, which builds it from the account's Slides Artifact type |
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

A diagram that will be committed to the repository (a doc, ADR or README) is Mermaid source, over
any canvas or page, so it diffs and reviews as text.

When the form is a chart and a chart-craft/dataviz capability is installed, invoke
it for the craft (form heuristic, palette, mark specs); when it is not installed,
fall back to a simple, honest default (a labeled bar/line as inline SVG on a
page, or a Unicode bar/sparkline in the terminal) and say the craft capability was
unavailable.

When the form hand-authors CSS or SVG styling outside the page chrome (Step 3) and `/user-interface:write-css` is installed, use it to write that CSS, since it applies the project's design system and conventions first; without it, write the CSS here. The page chrome stays governed by the bundled chrome reference either way.

When the form is a hand-tweakable visual layout, render this skill's rich page
(or the form Step 3's resolved medium calls for) and offer the person the
design canvas. The canvas is the bundled `design` skill, which is reserved for the
person to run: the model never invokes it. It exists only on the published-Artifact
tier, so the offer is also gated on Step 3's medium selection: when the resolved
medium keeps delivery on the machine (its `publishes` is false), do not offer it.
Where the medium permits publishing, offer it as an explicit alternative, never a
silent default: the canvas is a published, persistent Artifact the person edits
and shares (how, per the pointer in
[the catalog's design canvas section](context/decision-matrix.md#design-canvas-bundled-design-skill-presence-gated-preview)), where
this skill's page paths are throwaway or plain-static. The Boundary section below carries the sentence to offer and its gate
basis; the canvas surface facts and their verified-on/recheck record live in the
catalog spoke.

## Step 3: Pick the medium

The media are the medium registry's fallback chain (`lib/view-registry.mjs`), richest
first; the resolver steps a medium down that chain until this session can reach it. Selection
layers, first hit wins:

1. **Explicit argument**. A medium named as the argument forces it. With no argument, the layers
   below decide. The argument picks only the medium; name a form in the request itself.
   `--unattended`, anywhere in the arguments, is neither a medium nor part of the target: it is the
   caller declaring that nobody is present. Take it out first, then read the rest.
2. **Resolved preference**. Run the shared medium resolver, adding `--argument <medium>`,
   `<medium>` being the argument's word, when there is one. `<option>` is this plugin's `medium`
   option, `${user_config.medium}`; pass `""` when that reads empty or as an unsubstituted
   placeholder. Read each option value from this text; never put a `${user_config.*}` string in a
   shell command.

   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/lib/view-settings.mjs" resolve --lane visualization:visualize --option "<option>" [--argument <medium>]
   ```

   It prints one JSON line, then the report line naming the medium and what decided it, then any
   notice; print those lines as they stand. It weighs the argument, this plugin's `medium` option
   and the repository's rendered-views convention files, and never publishes on a team file's
   say-so; do not read or weigh those files yourself. Exit 2 means the argument named no medium:
   say so in one line and run it again without `--argument`. With a `medium` set, deliver by the
   JSON's `page` and `publishes`: `page` false renders in the terminal; `publishes` true publishes
   the page, under the surface gate below; otherwise the page is a local HTML file. A `medium` of
   `null` means no setting decided, so layer 3 resolves. When `node` is missing, say so in one line
   and let layer 3 decide.
3. **Auto**. Decide by the form and its weight: no page for small, static,
   text-representable output (tables, ASCII, short code, a `mermaid` source fence);
   a rich page for a composite, interactive, large, or truly graphical result
   (rendered diagrams, real charts, dashboards).

Whichever layer decides, name it in the output: the resolver's report line, or "shipped
default" for auto.

**Surface gate: the rich page is a capability that can be absent.** A published
Artifact is gated;
[the catalog's availability entry](context/decision-matrix.md#availability-gating-why-the-surface-is-often-absent)
points at the live conditions. So when a page is warranted:
publish an Artifact only if that surface is available; otherwise write a
self-contained local HTML file and open it; if neither page surface is available,
degrade **visibly** to the best terminal form with a one-line notice. Never assume
the Artifact surface exists. A medium that does not publish keeps the page on the
machine; a publishing one prefers publishing but degrades the same way.

**Canvas server.** A canvas server is an MCP server whose tools draw a diagram in an interactive
view, such as an Excalidraw or tldraw server; detect one by the session's MCP tool names. In the
Claude Code terminal, never draw there: use the forms above, a Mermaid or ASCII fence inline or a
local page. On a surface that renders MCP Apps, with a canvas server connected, you may draw there
instead of a page, except for a diagram that will be committed (Step 2). A canvas stands in only
for a page, so a resolved medium with no page (`page` false) draws none, and one that keeps delivery
on the machine (`publishes` false) uses a local server only, as under `deny` below. The surface facts behind
this rule, and the optional servers a person can install, are in
[the catalog's canvas section](context/decision-matrix.md#mcp-app-canvas-connected-canvas-server).

Before drawing on a canvas, resolve `hosted_canvas` (`allow` or `deny`) from three layers: the
option `${user_config.hosted_canvas}` (empty, or still an unsubstituted placeholder, is unset);
the `hosted_canvas` key of the repository's `docs/conventions/visualization.yaml`; and the same key
of the personal override `docs/conventions/visualization.local.yaml`. Read the two files only when
the repository root (`CLAUDE_PROJECT_DIR`, else `git rev-parse --show-toplevel`) is inside a git
working tree and is neither `$HOME` nor an ancestor of it; a missing file or key leaves that layer
unset. Read the team file twice, from the working tree and from the default branch's committed copy,
so a branch cannot drop the team's `deny`. For the second read, take the branch name from
`git -C <root> ls-remote --symref origin HEAD`, fetch it with
`git -C <root> fetch --quiet origin +refs/heads/<branch>:refs/remotes/origin/<branch>` (a failed
fetch falls back to the last fetched copy), resolve
`git -C <root> rev-parse --verify --quiet refs/remotes/origin/<branch>^{commit}`, then
`git -C <root> show <sha>:docs/conventions/visualization.yaml`. A file absent at that commit leaves
the layer unset. When the read cannot run (no origin answers, it names no default branch, or the
ref never resolves), say so in one line naming the step that failed and count the team layer as
`deny` for this run. A value other than `allow` or `deny` is named with its option or file, the key and
the value, and that layer is dropped. `deny` from any layer wins, so a tracked file can never undo
one person's `deny`; otherwise the value is `allow`, the default. Print one line with the value and the layer
that set it, for example `hosted_canvas: deny (docs/conventions/visualization.yaml)`,
`hosted_canvas: deny (default-branch read failed: origin names no default branch)` or
`hosted_canvas: allow (plugin default)`.

With `deny`, send no diagram content to a hosted canvas server, one reached over the network; a
local server, one that draws on this machine without sending the content on, stays allowed. Neither
tool names nor an MCP configuration prove that (a process started locally can forward to a remote
service), so count a server as local only when the person says in this session that it is;
otherwise treat it as hosted and render locally.

**Diagram target.** When the form is a diagram, resolve `diagram_target` (`auto`, `terminal`,
`local-page`, `excalidraw` or `tldraw`) from the option `${user_config.diagram_target}` (empty, or an
unsubstituted placeholder, is unset), then the `diagram_target` key of
`docs/conventions/visualization.yaml`, then the same key of `visualization.local.yaml`, each later
layer winning, else `auto`. Read the two files from the working tree only, under the same root rule
as `hosted_canvas`; a value outside the five is named with its option or file, key and value, and
that layer is dropped. Print one line with the value and its layer, such as
`diagram_target: excalidraw (docs/conventions/visualization.local.yaml)`. `auto` is the behavior
above. Run layer 2 first: a medium it resolves (the person's own setting) wins over any other value,
which then decides where the diagram goes only when layer 2 resolves none, in place of layer 3. A
layer 2 that cannot run resolves none. When
a resolved medium overrides it, say so in one line, such as
`diagram_target: local-page overridden by medium terminal`. An explicit
medium argument still wins, and the committed-diagram rule (Step 2), the pull-request diff exception below
and the mermaid gate still apply. `terminal` draws an inline fence, `local-page` a local HTML file,
and `excalidraw` or `tldraw` that canvas server, only where the canvas rule above would draw on it.
When the chosen target is unavailable (no such server connected, a surface that does not render
it, or `hosted_canvas` forbids it), use `auto` and print this exact one-line form, never only a
prose explanation:
`diagram_target: excalidraw unavailable (no excalidraw server connected); using auto`.

**Code-shape sketches take these same layers** (under auto they build no page, per
layer 3; an argument or resolved medium is honored for them as for any form), with
one exception: a pull-request diff, fetched content, or another repository's files
are never rendered to HTML until this lane is wired through the rendered-views escape helper. That exception overrides layer 1 and the
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
page to `<echoed dir>/visualize.html`. Echo it in that call: the directory name
is random, so an unechoed path is unrecoverable in the call that writes the file
(what carries between Bash calls:
[Tools reference, "What persists between commands"](https://code.claude.com/docs/en/tools-reference#what-persists-between-commands)).
Carry the temp root in the positional template, the one form GNU and BSD `mktemp` accept identically, since `-p`/`--tmpdir`/`-t` differ between the dialects and a bare relative template silently creates the file in the **current directory**, the consumer's repository. Keep the `XXXXXX` placeholders **trailing**. BSD `mktemp` (macOS) substitutes only trailing Xs, so an extension after them is not portable.
That is why the page takes a fixed name inside the generated directory rather
than a `visualize-XXXXXX.html` template, which macOS cannot create at all. On Windows,
a user-scoped temp under
`%LOCALAPPDATA%\Temp`. One file per run. The path is handed back to the user, so
do not delete it. It must still be readable when they open it. Open it for the
user (`start <path>` on Windows, `open <path>` on macOS, `xdg-open <path>` on
Linux) and report the absolute path.

A **mermaid diagram** is the sharp case. A local HTML file renders it only if the
page **embeds** a mermaid renderer inline. What a published Artifact page may load
is in [Artifacts: Page constraints](https://code.claude.com/docs/en/artifacts#page-constraints).
Keep the file self-contained; never load a renderer from the network, which breaks offline use and, for output kept local or otherwise sensitive,
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
embed the SVG a block names in place of the fence. For an Artifact, omit `--svg-dir` and run the parse
only (why: [the catalog's Published Artifact entry](context/decision-matrix.md#published-artifact)).

- `status: error`: do not write the page. Report the block's `file`, `line` and `error`, fix the
  diagram, run the gate again.
- `render: source`: keep the mermaid source and print the block's `reason` beside it. Never call
  such a page rendered.
- Without `mmdc` the parse is a structural check (unknown diagram type, unterminated quote,
  unbalanced flowchart brackets), so say an `ok` does not prove every syntax error is absent.
- The gate uses `mmdc` only at the minimum version in `prerequisites.json` or newer, found on PATH
  or at `node_modules/.bin/mmdc` under the working directory. An older one is treated as absent.
  A failure that is not a parse error (no Chrome) falls back to source with the failure as the
  reason. Pointer: <https://github.com/mermaid-js/mermaid-cli/releases>. Recheck when the
  Artifact runtime's Mermaid version (see `context/decision-matrix.md`) moves to a different major.
- Check the prerequisites with
  `node "${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.mjs" check "${CLAUDE_PLUGIN_ROOT}" --data-dir "${CLAUDE_PLUGIN_DATA}"`.

Honor a preference without overproducing: a publishing medium still renders a trivial
three-row table inline, and a medium with no page degrades a rich form to its best
terminal approximation with a visible note rather than dropping detail silently.

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

The pasted-code case honors `${user_config.thin_context_prompt}`. Read an empty
value, or one that still reads as an unsubstituted `${user_config…}` placeholder,
as unset, and apply `auto` (how a saved option reaches skill content:
[Reference a saved value](https://code.claude.com/docs/en/plugins/manifest-reference#reference-a-saved-value)).
`auto` is the behavior above; `always` offers the
ranked menu on any bare code paste; `never` renders the recommended form without
asking. Any other value is reported and treated as `auto`.

When neither is ambiguous, meaning a dominant target and a clear best form, proceed with
the matrix's pick: good defaults, no nagging. A specified form or medium is honored
and simply removes that axis from any question, with one carve-out: Step 3's
terminal-only exception for a pull-request diff, fetched content, or another
repository's files overrides a requested medium that shows a page. Never
interrogate form by form; one question, then render.

## Step 5: Render

- **Terminal**: use markdown tables, fenced code, blockquotes, and ASCII/Unicode.
  Emit a ` ```mermaid ` block as portable source the user can render elsewhere,
  and prefer a page when the *rendered* diagram is the point.
- **A rich page** follows the Artifact tool's own contract and, when an
  artifact-design capability is installed, its guidance. The page-contract facts
  live once in [`context/decision-matrix.md`](context/decision-matrix.md). When the subject is a
  product UI, match that product's own colors, type, spacing, and components rather than the
  plugin chrome; use real labels and data; support desktop and mobile.
- Report what you produced and, for a page, its path or link.

## Next

/visualization:present

It turns the material into a slide deck when the request is for slides rather than one visual.

## Gotchas

- **Terminal mermaid is source, not a picture.** If the user wants to *see* the
  rendered diagram and no page surface is available, say so. Do not imply the
  fence renders inline.
- **Do not overproduce a page.** A three-row comparison is a table; forcing it into
  an Artifact is worse, not richer. Match richness to the content.
- **The Artifact surface is often unavailable.** Gate on it; never let a missing
  surface become a silent failure. Degrade visibly down the fallback chain.
- **Canvas tools in the tool list are not a reason to use them.** In the Claude Code terminal,
  render locally even when an Excalidraw or tldraw server is connected (Step 3).
- **Craft is not this skill's job.** If you find yourself writing palette or axis
  guidance, stop and route to the chart-craft capability instead.
- **Prefer a mermaid family known to render** on an Artifact page, or verify a
  newer one before relying on it. The catalog's
  [Mermaid diagram families](context/decision-matrix.md#mermaid-diagram-families)
  records which families were checked, and Step 3's Page constraints pointer
  says what a page may load.

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

- **`design` (bundled skill)**: drafts artboards on one canvas the person keeps and edits
  (what it publishes and where it is edited:
  [Artifacts: Draft a design canvas](https://code.claude.com/docs/en/artifacts#draft-a-design-canvas)).
  It is reserved for the person to run; the model does not invoke it.
- **This skill (marketplace plugin)**: picks the form and medium and renders a throwaway or
  plain-static page.

**Routing:** when the form is a hand-tweakable layout and Step 3's medium permits publishing,
render this skill's page and tell the person: If /design is available in your session (gate
basis: the verification record below), you can run it instead of or alongside this skill for a
hand-editable design canvas. Treat a `design` entry in your skill listing as a local skill
shadowing the bundled command (how same-name skills resolve:
[Skills, "Resolve skills that share a name"](https://code.claude.com/docs/en/skills#resolve-skills-that-share-a-name)):
do not make the offer, and tell the person a local
`design` skill shadows the bundled canvas command. A local `design` skill that disables model
invocation shadows it too and is hidden from you, so every offer adds that `/design`'s description
should read "Make a new Design artifact from a brief"; anything else is a local skill, not the
canvas, and not to be run for it. When the caller passes `--unattended`,
record the `/design` suggestion in the run's output and do not ask the person; without that
flag, tell the person as above.

**Mutation gate:** the canvas publishes a persistent Artifact under the person's account, so it is
never a silent default and nothing tracked in a repository references it. This skill never runs it.

**Verification record, `design`.** Our binary extraction of Claude Code 2.1.285 reads the
bundled `design` registration as model-invocation-disabled, user-invocable and gated, which is
why this skill only ever offers it. Settings can remove it; which settings, and how, are read from
the pointers in the catalog spoke's design canvas section
([context/decision-matrix.md](context/decision-matrix.md#design-canvas-bundled-design-skill-presence-gated-preview)),
which owns the remaining surface facts.

- **Pointer**: probe: the `design` records in `docs/native-surfaces/records.json`.
- **As of**: 2026-09-29
- **Recheck trigger**: a release makes the `design` registration model-invocable, changes its
  description (the identity string the offer quotes), changes its gating, or splits or merges its
  registrations.

A request to draw a layout or a deck can name a Claude Design project the person already has, and
then it means that project, not a new render:

- **`ClaudeDesign` (built-in tool)**: the editor for a claude.ai/design project the person
  already has; the model calls it by name. A new Design artifact comes from the bundled `design`
  skill above, which the person runs
  ([Artifacts: Draft a design canvas](https://code.claude.com/docs/en/artifacts#draft-a-design-canvas)).
- **This skill (marketplace plugin)**: picks the form and medium and renders its own output.

**Routing:** when the person names or links an existing claude.ai/design project, or asks for the
work to go into one, and the `ClaudeDesign` tool resolves in this session, use that tool for the
project's files. Otherwise this skill renders its own output as today. The tool is the project's
editor; this skill is the form and medium router.

**Mutation gate:** a `ClaudeDesign` write changes a project the person's team shares. Write only
to the project the person named, and only after they asked for the change. When the tool asks for
an approval or refuses a write, report it and never retry around it. The approval and refusal
cases are probed behavior recorded in
[context/claude-design-tool.md](context/claude-design-tool.md#the-built-in-claudedesign-tool-verification-record).

## What this skill does NOT do

- **Does not teach chart craft**. Palette, axes, marks route to a chart-craft/dataviz capability.
- **Does not teach artifact-design fundamentals**. Those route to an artifact-design capability and the Artifact tool's contract.
- **Does not restate rendering-surface facts**. They live once in the catalog spoke.
- **Does not digest or re-explain dense text**. That is a comprehension concern, not a form concern.
- **Does not explain a topic from scratch**. A one-idea-per-diagram picture explainer of a concept or codebase topic, ELI5 included, is `education:illustrate` (if enabled). This skill picks a form for what is already in the conversation.
- **Does not render a pull-request diff, fetched content, or another repository's files to HTML** until this lane is wired through the rendered-views escape helper. Those stay terminal fences.
- **Does not publish an Artifact when that surface is absent or the resolved medium does not publish**. It steps down the fallback chain.
- **Does not ship or install a canvas server**. It uses one the person connected, under Step 3's canvas rule.
