# Visualization decision matrix — grounded catalog

The form and surface facts behind the `visualize` skill's Step 2 (pick the form)
and Step 3 (pick the medium). The skill owns the decision *logic*; this spoke owns
the *facts* it decides over — the rendering surfaces, the diagram families, and the
zero-dependency chart paths — each grounded in the sources at the end. Re-verify
against those sources before relying on a time-sensitive detail; the platform moves.

## Rendering surfaces

### Inline terminal (Claude Code CLI)

- Renders GitHub-flavored markdown: headings, lists, **tables**, fenced code
  blocks (with syntax highlighting), blockquotes, and links. The exact rendered
  construct set is not officially enumerated; tables and fenced code are the
  dependable structural visuals.
- A ` ```mermaid ` fence is shown as **source text, not a rendered diagram**. Treat
  the terminal mermaid path as portable *source* the user can render elsewhere —
  never as an inline picture.
- Inline raster images in the terminal are undocumented; do not rely on them.

### Published Artifact

- Renders a self-contained **HTML** or **Markdown** page.
- **Mermaid renders natively** — both a ` ```mermaid ` markdown fence and an HTML
  `<pre class="mermaid">` block.
- **Strict Content-Security-Policy**: every external host is blocked — no CDN
  scripts, stylesheets, fonts, remote images, or `fetch`/XHR/WebSocket. Inline all
  CSS and JS; embed images as `data:` URIs. There is a page-size cap (~16 MiB).
- **Theme-aware** (light/dark), **responsive**, and **favicon required** — this is
  the Artifact tool's own contract; an artifact-design capability, when installed,
  owns the craft on top of it.
- **Connector-backed live data** (Claude Code v2.1.209+): a published page can
  call declared MCP connectors at view time, showing current data rather than a
  build-time snapshot. The CSP above still holds — the page itself makes no
  network call; it hands each call to claude.ai. Calls run through each viewer's
  own connector account after that viewer approves; a connector-backed page can
  never be shared to a public link; and on Team/Enterprise an org Owner toggle
  ("Enable artifact connectors") gates the capability.

### Availability gating (why the surface is often absent)

Publishing an Artifact is heavily gated. It is unavailable when any of these hold,
and the official fallback is to **write a local HTML file** instead:

- a paid plan and an active claude.ai sign-in are required;
- the first-party Anthropic API only — not Bedrock or Vertex — and blocked under
  CMEK / HIPAA / ZDR configurations;
- a minimum Claude Code version;
- off in SDK, CI/Action, and MCP execution contexts;
- disabled by `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`.

**Delivery tiers**, ascending richness and descending availability:
**inline terminal → local HTML file → published Artifact.** The local HTML file is
the always-available rich tier and the one that never leaves the machine.

The local HTML file is **not** under the artifact CSP (it is a file, not a
published page), so it *can* embed scripts inline — but it gets **no runtime for
free**, and it must stay self-contained (the README promises no network calls), so
any script is embedded, never loaded from a remote host. In particular a published
Artifact renders mermaid natively, whereas a local HTML file renders a mermaid
diagram only if the page embeds a mermaid renderer inline; a bare `mermaid` block in
a plain file stays unrendered.

## Form catalog

### Mermaid diagram families

Thirteen families are stable in mainline mermaid and form the safe default set for
artifact rendering. The bundled renderer's version is undocumented (see below), so
treat per-family support as presumed-safe rather than guaranteed:

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
`radar`, `treemap`) are **UNVERIFIED** in the bundled artifact renderer — the
bundled mermaid version is undocumented. Prefer a stable family, or verify a newer
one empirically on a throwaway artifact before relying on it.

### Tables

A markdown table renders in both the terminal and a page — the cheapest form, and
the one native to genuinely tabular data (rows of attributes across items), needing
no rendering surface beyond GFM.

### Charts (quantitative data)

There is **no external chart library** on a page — the CSP blocks every CDN. The
zero-dependency paths are:

- **On a page:** hand-authored inline **SVG + CSS** primitives (bars, lines,
  scatter, area, stat tiles). The *craft* — palette, scales, marks, accessibility
  — is a chart-craft/dataviz capability's concern; route to it when installed.
- **In the terminal:** Unicode-on-monospace approximations inside a code fence —
  bar rows (`█▉▊…`) and sparklines (`▁▂▃▄▅▆▇█`) — for small, at-a-glance quantities.

### ASCII / Unicode art

Box-drawing characters, directory trees, and small structural sketches render
crisply in a monospace terminal code fence — a zero-dependency structural picture
that needs no page surface.

### Rich page (composite / interactive / large)

A rich page can carry a composite dashboard, an interactive view, a large
multi-part layout, or a truly graphical result the terminal cannot represent. It is
delivered per the delivery tiers above (local HTML file or published Artifact).

### Design canvas (bundled `design` skill — presence-gated preview)

A hand-tweakable visual layout — UI mockups and screen flows, landing pages,
posters/flyers/one-pagers, memos as one flowing artboard — drafted as `.dc.html`
artboards on one pan/zoom canvas and published as an Artifact running the Claude
Design canvas editor. Where saving is enabled for the viewer's account the canvas
is hand-editable (click-to-select, properties panel, inline text, undo/redo) and
Save publishes a new version; otherwise it is view-plus-PNG/PDF-export. It rides
the published-Artifact surface, so every Artifact gate above applies, **plus** the
skill's own gates:

- an early **research preview**: enabled by a server-side rollout flag that
  defaults off, first-party context only, and an Artifact tool that supports
  `capabilities` — two same-version clients can differ;
- removable by settings (`disableBundledSkills`, or `skillOverrides` naming
  `design`) and absent on non-first-party platforms (Bedrock / GCP / Foundry /
  AWS) and in headless SDK/CI/MCP contexts;
- **model-invocable where enabled** (no model-invocation gate in its
  registration), so the skill can be invoked by name — bare `design`; no
  namespace exists for bundled skills. A local skill named `design` at any level
  silently overrides the bundled one.

The honest presence check is whether `design` appears in the current session's
skill list. Absent → the rich-page paths above cover the ground (and `/design`
must not be suggested — that user has no such command). Listed-but-refused → user
invocation of `/design` survives invocability gates.

> Verified 2026-08-18 against the shipped v2.1.234 client (registration and gating
> extracted from the binary; independently re-verified by two fresh-context
> validators) and <https://code.claude.com/docs/en/skills>. The skill is unnamed
> in the Claude Code changelog and docs as of that date, so **no version floor is
> statable**. Recheck when a release changelog or the commands reference first
> names the design canvas skill, or when bundled-skill invocability changes.

## Third-party visualization plugins

Depend on **none** today. The curated first-party marketplace ships no
visualization plugin. The community candidates are each disqualified on a trust or
fit ground:

- `antvis/mcp-server-chart` — egresses chart data to a third-party cloud by
  default.
- `veelenga/claude-mermaid` — a solo-author MCP server (local render), a
  code-execution trust surface.
- `careerhackeralex/visualize` — a solo-author HTML-viz skill that pulls chart
  libraries from a CDN, which the artifact CSP blocks outright.

Until a credible option exists the skill relies only on native rendering surfaces
and the presence-gated craft capabilities. The revisit trigger for a self-hostable,
egress-free server (a self-hosted AntV deployment being the current candidate) is
owned by the plugin README's future-change section.

## Sources and verification

Verified 2026-07-22 via a research fan-out over official documentation; re-fetch
before relying on a time-sensitive detail.

- Terminal Markdown rendering (code-block syntax highlighting, hyperlinks) —
  `https://code.claude.com/docs/en/interactive-mode.md`.
- Mermaid emitted as source, not terminal-rendered —
  `https://code.claude.com/docs/en/output-styles.md`.
- Artifact CSP (no external requests, inline CSS/JS, `data:` images, ~16 MiB,
  self-contained), HTML+Markdown types, availability gating, and connector-backed
  live data (verified 2026-08-04) —
  `https://code.claude.com/docs/en/artifacts`.
- Artifact native mermaid, favicon requirement, theme-awareness
  (`prefers-color-scheme` / `data-theme`), and responsive rules — the Artifact
  tool's own live contract (this session; not restated on the public artifacts
  page).
- Mermaid diagram families — `https://mermaid.js.org/intro/` and the stable
  sidebar at `https://mermaid.js.org/syntax/flowchart.html`.
- Plugin manifest / `userConfig` schema (no native enum type) —
  `https://code.claude.com/docs/en/plugins-reference` (fetched this session).
- Third-party survey — `https://code.claude.com/docs/en/discover-plugins`, the
  community catalog at
  `https://raw.githubusercontent.com/anthropics/claude-plugins-community/main/.claude-plugin/marketplace.json`,
  and the candidate repos `antvis/mcp-server-chart`, `veelenga/claude-mermaid`,
  `careerhackeralex/visualize` on GitHub.

UNVERIFIED / low-confidence (flagged, not asserted):

- Terminal rendering of a mermaid fence as a *diagram* — verified only as source
  text; treated as source, never as an inline picture.
- Inline terminal raster images — undocumented.
- The mermaid version bundled by the Artifact renderer (undocumented; the current
  mermaid *release* is not necessarily what Artifacts bundle) and the newest
  "fire-icon" families in that renderer — verify empirically before use.
- Third-party repo maintenance signals (last-commit dates, exact star counts) and
  the AntV egress claim (from its README, not empirically exercised).
