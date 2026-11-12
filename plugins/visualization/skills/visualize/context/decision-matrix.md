# Visualization decision matrix: grounded catalog

The form and surface facts behind the `visualize` skill's Step 2 (pick the form)
and Step 3 (pick the medium). The skill owns the decision *logic*; this spoke owns
the *facts* it decides over: the rendering surfaces, the diagram families, and the
zero-dependency chart paths, each grounded in the sources at the end. Re-verify
against those sources before relying on a time-sensitive detail; the platform moves.

## Rendering surfaces

### Inline terminal (Claude Code CLI)

- Renders GitHub-flavored markdown: headings, lists, **tables**, fenced code
  blocks (with syntax highlighting), blockquotes, and links. The exact rendered
  construct set is not officially enumerated; tables and fenced code are the
  dependable structural visuals.
- A ` ```mermaid ` fence is shown as **source text, not a rendered diagram**. Treat
  the terminal mermaid path as portable *source* the user can render elsewhere,
  never as an inline picture.
- Inline raster images in the terminal are undocumented; do not rely on them.

### Published Artifact

- Renders a self-contained **HTML** or **Markdown** page.
- **Mermaid renders natively** in both a ` ```mermaid ` markdown fence and an HTML
  `<pre class="mermaid">` block.
- **Bundled mermaid runtime** (probed behavior; no docs page names the runtime):
  the publish path injects its own mermaid build into the page. Read its version
  from the installed binary with the probe below before relying on one.
  - **Pointer**: probe: `grep -a '/_runtime/mermaid-'` over the installed Claude Code
    binary, recorded in
    <https://github.com/melodic-software/claude-code-plugins/pull/3729#issuecomment-5546567555>.
  - **As of**: 2026-09-04
  - **Recheck trigger**: the artifacts page or the changelog names the runtime, a
    mermaid-family rendering failure is reported, or this plugin releases.
- **Content-Security-Policy**: the published page's CSP decides which external
  hosts it may load from. This plugin's policy is stricter: inline all CSS and JS
  and embed images as `data:` URIs, so a page never depends on a network call,
  even to a host the CSP allows. The rendered page also has a size cap, so large
  embedded images can fail a publish.
  - **Pointer**: when a question turns on which external hosts the CSP allows or
    on the page-size cap, fetch
    [Artifacts: Page constraints](https://code.claude.com/docs/en/artifacts#page-constraints)
    live.
- **Theme-aware** (light/dark), **responsive**, and **favicon required**: this
  plugin builds every published page to these three rules, and follows the Artifact
  tool's own description in the session where it asks for more. An artifact-design
  capability, when installed, owns the craft on top of them.
- **Connector-backed live data**: a published page can call declared MCP
  connectors at view time, showing current data rather than a build-time snapshot.
  The CSP decision above still holds: the page makes no data call of its own. Who
  the calls run as, what a viewer must approve, how such a page may be shared, the
  version floor and the organization control are the upstream page's to state.
  Before recommending a connector-backed page the person will share, read those
  live and tell the person what a viewer without the connection will see.
  - **Pointer**: when choosing or sharing a connector-backed page, fetch
    [Artifacts: Pull live data with MCP connectors](https://code.claude.com/docs/en/artifacts#pull-live-data-with-mcp-connectors)
    (including its "How connector calls work for viewers" subsection) and
    [Control connector calls from artifacts](https://code.claude.com/docs/en/artifacts#control-connector-calls-from-artifacts)
    live.

### Availability gating (why the surface is often absent)

Publishing an Artifact is gated, and the conditions are read live from the pointer
below, never from this file. When the surface is absent, this skill **writes a
local HTML file** instead.

- **Pointer**: when deciding whether the published-Artifact tier can be offered,
  fetch [Artifacts: Availability](https://code.claude.com/docs/en/artifacts#availability)
  live.

**Delivery tiers** are the medium registry's fallback chain (`lib/view-registry.mjs`), richest
first, each step down more available. The local HTML file is the always-available rich tier and
the one that never leaves the machine.

The local HTML file is **not** under the artifact CSP (it is a file, not a
published page), so it *can* embed scripts inline, but it gets **no runtime for
free**, and it must stay self-contained (the README promises no network calls), so
any script is embedded, never loaded from a remote host. In particular a published
Artifact renders mermaid natively, whereas a local HTML file renders a mermaid
diagram only if the page embeds a mermaid renderer inline; a bare `mermaid` block in
a plain file stays unrendered.

### MCP App canvas (connected canvas server)

A canvas server's tools return an MCP App, an interactive view for the host to render. Which hosts
render one, Claude Code included, is read live from the pointer below. Our rule: in the Claude Code
terminal the skill draws locally; on Claude Desktop or claude.ai it may draw on a connected canvas,
under the `hosted_canvas` setting. A `diagram_target` of `excalidraw` or `tldraw` asks for that canvas
and never widens this rule: where it would not draw, the skill falls back to `auto`.

- **Pointer**: when deciding whether this session's surface renders a canvas, fetch
  [Add an interactive UI to your MCP server: See the UI render in Claude](https://claude.com/docs/connectors/building/mcp-apps/quickstart#see-the-ui-render-in-claude)
  live.

This plugin bundles no canvas server. A person who wants one can install an official server at user
level; each repository's README says how and which variants run locally or remotely:

- Excalidraw: <https://github.com/excalidraw/excalidraw-mcp>
- tldraw: `apps/mcp-app` in <https://github.com/tldraw/tldraw>

## Form catalog

### Mermaid diagram families

Thirteen families are stable in mainline mermaid and form the safe default set for
artifact rendering. The platform does not document the bundled renderer's version
(it is read from the binary; see the Published Artifact record above), so treat
per-family support as presumed-safe rather than guaranteed:

| Family | Use it for |
|---|---|
| `flowchart` | Processes, decisions, general node-edge relationships |
| `sequence` | Interactions/messages between participants over time |
| `class` | Types, fields, and their relationships (UML class) |
| `state` | State machines and transitions |
| `er` | Entity-relationship data models |
| `gantt` | Schedules and task timelines with durations |
| `pie` | Part-to-whole proportions (few slices) |
| `gitGraph` | Branch/commit/merge history |
| `mindmap` | Hierarchical idea/topic breakdowns |
| `timeline` | Chronological events on a single axis |
| `quadrantChart` | Items placed on two axes (four quadrants) |
| `requirement` | Requirements and their verification relationships |
| `journey` | User-journey steps with satisfaction scores |

The newest "fire-icon" families (for example `sankey`, `xychart`, `kanban`,
`radar`, `treemap`) are present upstream in the bundled mermaid version; their rendering in
the artifact viewer is **UNVERIFIED**. Prefer a stable family, or verify a newer
one empirically on a throwaway artifact before relying on it.

### Tables

A markdown table renders in both the terminal and a page. It is the cheapest form,
and the one native to genuinely tabular data (rows of attributes across items),
needing no rendering surface beyond GFM.

### Charts (quantitative data)

This plugin loads **no external chart library** on a page, even from a host the
artifact CSP allows (see the Content-Security-Policy entry above): the plugin's
policy is no network calls, so the paths are zero-dependency:

- **On a page:** hand-authored inline **SVG + CSS** primitives (bars, lines,
  scatter, area, stat tiles). The *craft* of palette, scales, marks, and
  accessibility is a chart-craft/dataviz capability's concern; route to it when
  installed.
- **In the terminal:** Unicode-on-monospace approximations inside a code fence.
  Bar rows (`█▉▊…`) and sparklines (`▁▂▃▄▅▆▇█`) suit small, at-a-glance quantities.

### ASCII / Unicode art

Box-drawing characters, directory trees, and small structural sketches render
crisply in a monospace terminal code fence, a zero-dependency structural picture
that needs no page surface. A directory tree here is a structure sketch; a file
tree that carries one line of responsibility per entry is the code-shape form
below.

### Code-shape sketches

Fenced text forms for code: pseudocode, a call tree, a component tree with file
paths, a shallow file tree with per-entry responsibilities, types and signatures,
a diff-shaped delta over any of those, and the whole block as the fallback. They
render in any GFM surface, need no page, and take the same medium selection as
every other form, except that a pull-request diff, fetched content, or another
repository's files are never rendered to HTML until this lane is wired through the
rendered-views escape helper (the convention's security baseline). One example per form
lives in `code-shapes.md` beside this file.

### Rich page (composite / interactive / large)

A rich page can carry a composite dashboard, an interactive view, a large
multi-part layout, or a truly graphical result the terminal cannot represent. It is
delivered on whichever page medium the resolver settles, per the delivery tiers above.

### Design canvas (bundled `design` skill, presence-gated preview)

A hand-tweakable visual layout for UI mockups, screen flows, landing pages and
posters, which the person edits after Claude drafts it. It rides the
published-Artifact surface, so every Artifact gate above applies, **plus** the
skill's own gates, which are read live from the pointer below, as is how the
person edits and exports it.

- **Pointer**: when offering `/design` or answering what it produces or requires,
  fetch [Artifacts: Draft a design canvas](https://code.claude.com/docs/en/artifacts#draft-a-design-canvas)
  and its parent
  [Start from a Slides, Design, or Docs template](https://code.claude.com/docs/en/artifacts#start-from-a-slides-design-or-docs-template)
  live; for removing a bundled skill by settings, fetch
  [`disableBundledSkills`](https://code.claude.com/docs/en/settings-reference#disablebundledskills)
  and [`skillOverrides`](https://code.claude.com/docs/en/settings-reference#skilloverrides).

**Reserved for the person to run** (probed behavior): our binary extraction of
v2.1.285 reads the `design` registration as model-invocation-disabled and
user-invocable, so the model never lists or invokes it and the person runs
`/design`. A local skill named `design` can collide with the bundled one; which
skill wins a shared name is read live from
[Skills: Resolve skills that share a name](https://code.claude.com/docs/en/skills#resolve-skills-that-share-a-name).

- **Pointer**: probe: the `design` records in `docs/native-surfaces/records.json`.
- **As of**: 2026-09-30
- **Recheck trigger**: a release makes the `design` registration model-invocable,
  changes its description (the identity string the offer quotes), changes its
  gating, or splits or merges its registrations.

The model cannot check presence: a model-invocation-disabled skill never enters
its listing. So the skill renders its own page either way and offers the person a
conditional sentence ("If /design is available in your session ..."), which the
person checks against their own session. User invocation of `/design` survives
the model-invocation gate. The model sees only part of the identity question: a
`design` entry in its own skill listing can only be a shadowing local skill, so
the offer is withheld and the shadowing named, but a local `design` skill that
disables model invocation shadows the command while staying hidden. So every
offer asks the person to confirm `/design`'s description reads "Make a new
Design artifact from a brief" before running it for a canvas.

The identity string the offer quotes, and the finding that `/design` is a
user-only design-Artifact creator rather than the claude.ai/design hub (whose text
belongs to the separate `ClaudeDesign` tool), come from the same probe: the
2026-09-29 extraction and the 2026-09-30 targeted string search of v2.1.285, both
held in the `design` records of `docs/native-surfaces/records.json` (as of
2026-10-11; recheck when those records add a probe of a later version or change
the identity string).

The design-sync family's registry disposition (defer, observed-only) also lives in
`docs/native-surfaces/records.json` (its `design-sync` records), which keeps the
v2.1.263 registration evidence as history (as of 2026-10-11; recheck when a release note first names a
design-family surface, or those records change disposition).

## Third-party visualization plugins

Depend on **none** today. The curated first-party marketplace ships no
visualization plugin. The community candidates are each disqualified on a trust or
fit ground:

- `antvis/mcp-server-chart`: egresses chart data to a third-party cloud by
  default.
- `veelenga/claude-mermaid`: a solo-author MCP server (local render), a
  code-execution trust surface.
- `careerhackeralex/visualize`: a solo-author HTML-viz skill that pulls chart
  libraries from hosts outside the artifact allowlist, and this plugin's policy is
  no network calls in any case.

Until a credible option exists the skill relies only on native rendering surfaces
and the presence-gated craft capabilities. The revisit trigger for a self-hostable,
egress-free server (a self-hosted AntV deployment being the current candidate) is
owned by the plugin README's future-change section.

## Sources and verification

Gathered by a research fan-out over official documentation; re-fetch before relying on a
time-sensitive detail.

- Terminal Markdown rendering (code-block syntax highlighting, hyperlinks): the page documents the
  syntax-highlighting toggle and clickable issue references, but no general statement about
  rendered Markdown or its construct set (tables, headings, lists, links), which stays undocumented.
  - **Pointer**: for syntax highlighting, fetch
    [Interactive mode: Theme and display](https://code.claude.com/docs/en/interactive-mode#theme-and-display)
    (the `Ctrl+T` row, which works inside the `/theme` picker); for clickable issue references,
    fetch
    [Issue reference links](https://code.claude.com/docs/en/interactive-mode#issue-reference-links)
    live.
- Mermaid emitted as source, not terminal-rendered: no official page documents
  terminal mermaid rendering, and the shipped binary showed no terminal-side
  renderer.
  - **Pointer**: absence checked in
    `https://code.claude.com/docs/en/interactive-mode.md` and
    `https://code.claude.com/docs/en/fullscreen.md` (both fetched whole, zero
    occurrences) and in the `llms-full.txt` docs corpus (one hit, an output-style
    example, not a rendering statement); probe: a string search for `mermaid` over
    the installed Claude Code binary, every hit on the artifact publish path,
    recorded in
    <https://github.com/melodic-software/claude-code-plugins/pull/3729#issuecomment-5546567555>.
    Open issues: anthropics/claude-code#14375 requests terminal rendering; #52517
    reports Claude Desktop's Claude Code tab showing a mermaid fence as raw source.
  - **As of**: 2026-09-04
  - **Recheck trigger**: a changelog entry or either page names terminal diagram
    rendering, or #14375 closes.
- Artifact CSP, page size, source file types, availability gating and
  connector-backed live data: each is read live from the pointer in its own entry
  under [Published Artifact](#published-artifact) and
  [Availability gating](#availability-gating-why-the-surface-is-often-absent).
- Artifact native mermaid, favicon requirement, theme-awareness
  (`prefers-color-scheme` / `data-theme`), and responsive rules: the Artifact
  tool's own description in the session (no public docs section covers them).
- Mermaid diagram families: `https://mermaid.js.org/intro/` and the stable
  sidebar at `https://mermaid.js.org/syntax/flowchart.html`.
- Plugin manifest `userConfig` fixed-value fields, which this plugin's options use:
  - **Pointer**: when adding or changing a fixed-value option, fetch
    [Plugins reference: Limit a field to fixed options](https://code.claude.com/docs/en/plugins/manifest-reference#limit-a-field-to-fixed-options)
    live.
- Third-party survey: `https://code.claude.com/docs/en/plugins/install`, the
  community catalog at
  `https://raw.githubusercontent.com/anthropics/claude-plugins-community/main/.claude-plugin/marketplace.json`,
  and the candidate repos `antvis/mcp-server-chart`, `veelenga/claude-mermaid`,
  `careerhackeralex/visualize` on GitHub.

UNVERIFIED / low-confidence (flagged, not asserted):

- Terminal rendering of a mermaid fence as a *diagram*: verified only as source
  text; treated as source, never as an inline picture.
- Inline terminal raster images: undocumented.
- Rendering of the newest "fire-icon" mermaid families in the artifact viewer
  (present upstream in the bundled version; see the Published Artifact record): verify
  empirically before use.
- Public sharing of an artifact is reported to fail for pages containing mermaid
  blocks, SVG `data:` URIs, or AVIF images (anthropics/claude-code#79824, #81410 a
  sibling); the mechanism is unconfirmed; private and org sharing are unaffected.
- Third-party repo maintenance signals (last-commit dates, exact star counts) and
  the AntV egress claim (from its README, not empirically exercised).
