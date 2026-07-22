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
  self-contained), HTML+Markdown types, and availability gating —
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
