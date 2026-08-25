# HTML Report Format

Deepening review rendered as self-contained HTML in the ephemeral tier — one file created through the platform's temp API, resolved deterministically rather than by branching on an injected scratchpad path or `CLAUDE_JOB_DIR`. The path is handed back for the user to open, so the file is never deleted before returning; it outlives the invocation, which is why one run writes exactly one file. Inline styles only — no CDN, no remote runtime, no remote fetch (a report that fetches remote assets is a privacy and supply-chain hazard and breaks when opened offline). Diagrams use inline SVG shapes and text only — no `<script>` elements inside SVG (SVG script executes like any page script and defeats the no-remote-runtime guarantee).

**Escape all codebase-derived text** before writing the report. Paths, glossary terms, ADR excerpts, repo names, module labels, and any other string taken from the scanned repository must be HTML-escaped (`&`, `<`, `>`, `"`, `'`) before embedding in element text or attributes. Never paste attacker-controlled markup verbatim into the HTML file.

## Scaffold

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Deepening review — {{repo name}}</title>
    <style>
      :root {
        --clay: #D97757;
        --ivory: #FAF9F5;
        --slate: #141413;
        --oat: #E3DACC;
        --olive: #788C5D;
        --rust: #B04A3F;
        --gray-700: #3D3D3A;
        --gray-500: #87867F;
        --gray-300: #D1CFC5;
        --gray-150: #F0EEE6;
        --sans: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
        --mono: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
        --radius-panel: 12px;
        --radius-row: 8px;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        padding: 2rem 1.5rem;
        background: var(--ivory);
        color: var(--slate);
        font-family: var(--sans);
        line-height: 1.6;
      }
      main { max-width: 720px; margin: 0 auto; }
      h1, h2, h3 { line-height: 1.15; color: var(--slate); }
      code, pre, .mono { font-family: var(--mono); }
      .muted { color: var(--gray-500); }
      .panel {
        background: var(--gray-150);
        border: 1px solid var(--gray-300);
        border-radius: var(--radius-panel);
        padding: 1.25rem;
      }
      .badge-strong { color: var(--olive); }
      .badge-explore { color: #b45309; }
      .badge-speculative { color: var(--gray-500); }
      .seam { stroke-dasharray: 4 4; }
      .leak { stroke: var(--rust); }
      .deep { background: linear-gradient(135deg, #0f172a, #1e293b); }
    </style>
  </head>
  <body>
    <main>
      <header>...</header>
      <section id="candidates">...</section>
      <section id="top-recommendation">...</section>
    </main>
  </body>
</html>
```

## Header

Repo name, date, compact legend: solid box = module, dashed line = seam, red arrow = leakage, thick dark box = deep module. No intro paragraph — straight into candidates.

## Candidate card

Each candidate is one `<article>`:

- **Title** — short, names the deepening ("Collapse the Order intake pipeline")
- **Badge row** — recommendation strength (`Strong` = emerald, `Worth exploring` = amber, `Speculative` = slate) + dependency category tag (`in-process`, `local-substitutable`, `ports & adapters`, `mock`)
- **Files** — monospaced list, `font-mono text-sm`
- **Before / After diagram** — two columns, side by side. See patterns below
- **Problem** — one sentence
- **Solution** — one sentence
- **Wins** — bullets, ≤6 words each. Use vocabulary terms: "locality: bugs concentrate in one module", "leverage: one interface, N call sites", "interface shrinks; implementation absorbs the wrappers"
- **ADR callout** (if applicable) — amber-tinted box

No paragraphs of explanation. If diagram needs a paragraph, redraw it.

## Diagram patterns

Pick pattern that fits. Mix them — variety is the point. No Mermaid or other remote runtime — use inline SVG or hand-built HTML/CSS only.

### Flowchart (inline SVG or hand-built boxes)

Use when point is "X calls Y calls Z, look at the mess." Style leakage edges with `stroke: var(--rust)` and deep modules with the `.deep` class.

```html
<div class="panel">
  <svg viewBox="0 0 400 120" width="100%" height="120" aria-label="call flow">
    <rect x="10" y="40" width="80" height="40" rx="4" fill="var(--gray-150)" stroke="var(--gray-300)"/>
    <text x="50" y="65" text-anchor="middle" font-size="10">OrderHandler</text>
    <!-- arrows, additional boxes, leak styling -->
  </svg>
</div>
```

### Hand-built boxes-and-arrows

Modules as `<div>`s with borders. Arrows as inline SVG. Use when "after" diagram should feel like one thick-bordered deep module with greyed-out internals — Mermaid won't render that weight.

### Cross-section (layered shallowness)

Stack horizontal bands (`h-12 border-l-4`) showing layers a call passes through. Before: 6 thin layers. After: 1 thick band with consolidated responsibility.

### Mass diagram (interface as wide as implementation)

Two rectangles per module — interface surface area + implementation. Before: interface nearly as tall as implementation (shallow). After: interface short, implementation tall (deep).

### Call-graph collapse

Before: tree of function calls as nested boxes. After: same tree collapsed into one box, internal calls faded inside.

## Style guidance

- Lean editorial, not corporate-dashboard. Generous whitespace
- Color sparingly: one accent (emerald or indigo) + red for leakage + amber for warnings
- Diagrams ~320px tall so before/after fits side-by-side without scrolling
- `text-xs uppercase tracking-wider` for module labels inside diagrams
- Inline styles and inline SVG only — no CDN, no remote scripts

## Top recommendation section

One larger card. Candidate name, one sentence why, anchor link to its card.

## Tone

Use exactly: module, interface, implementation, depth, deep, shallow, seam, adapter, leverage, locality.

Never substitute: component, service, unit (for module); API, signature (for interface); boundary (for seam); layer, wrapper (for module).

No hedging, no throat-clearing, no "it's worth noting that..."

Phrasings that fit the style:

- "Order intake module is shallow — interface nearly matches the implementation."
- "Pricing leaks across the seam."
- "Deepen: one interface, one place to test."
- "Two adapters justify the seam: HTTP in prod, in-memory in tests."

Wins bullets name the gain in glossary terms. Never "easier to maintain" or "cleaner code" — those terms are not in the vocabulary. Sequence diagrams work well for "before: 6 round-trips; after: 1."
