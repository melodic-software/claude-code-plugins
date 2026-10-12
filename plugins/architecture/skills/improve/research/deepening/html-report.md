# HTML Report Format

Deepening review rendered as self-contained HTML in the OS temp directory: one file created through the platform's temp API, resolved deterministically rather than by branching on an injected scratchpad path or `CLAUDE_JOB_DIR`. The path is handed back for the user to open, so the file is never deleted before returning; it outlives the invocation, which is why one run writes exactly one file.

**Security baseline.** The report holds to the rendered-views security baseline as stated in Phase 2 of [../../actions/deepening.md](../../actions/deepening.md). Two additions are specific to this report:

- The untrusted data is every repository-derived string: paths, glossary terms, ADR excerpts, repo names, module labels, the `{{repo name}}` in the scaffold's `<title>`, and any other string taken from the scanned repository. Each is escaped before it lands in element text or an attribute.
- Diagrams are inline SVG shapes and text only, with no `<script>` element inside the SVG: SVG script runs like any page script.

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
      .deep { background: var(--slate); color: var(--ivory); }
    </style>
  </head>
  <body>
    <main>
      <header>...</header>
      <section id="candidates">
        <section class="band" id="band-strong"><h2>Strong</h2>...</section>
        <section class="band" id="band-explore"><h2>Worth exploring</h2>...</section>
        <section class="band" id="band-speculative"><h2>Speculative</h2>...</section>
      </section>
      <section id="top-recommendation">...</section>
    </main>
  </body>
</html>
```

## Header

The header holds the repo name, the date, and a one-line legend: a dark, heavy-bordered box is a
deep module, a plain box is any other module, a dashed line is a seam, and a rust-colored arrow is
leakage. The candidates follow at once, with no opening paragraph.

## Candidate card

One `<article>` per candidate, holding these parts in this order:

- **Title**: a few words naming the deepening, such as "Fold the invoice export steps into one module"
- **Badge row**: the recommendation strength (`Strong` uses `.badge-strong`, olive; `Worth exploring` uses `.badge-explore`, amber; `Speculative` uses `.badge-speculative`, muted grey) and the dependency category shown as a tag (`in-process`, `local-substitutable`, `ports & adapters`, `mock`)
- **Files**: one path per line in `var(--mono)`, one step smaller than the body text
- **Before / After diagram**: the two states in adjacent columns; patterns below
- **Problem**: a single sentence
- **Solution**: a single sentence
- **Wins**: one gain per bullet, short enough to take in at a glance, each named with a vocabulary term, for example "locality: a rounding fix now touches one file", "leverage: twelve call sites share one interface", "interface: four entry points become one"
- **ADR callout**, when one applies: a box tinted amber

A card carries nothing beyond these parts. A candidate that will not read without a paragraph has a
drawing that leaves out the relation the paragraph would explain; add that relation to the drawing.

## Badge bands

Cards sit in one band per recommendation badge, in badge order: `Strong`, then `Worth exploring`, then `Speculative`. A band with no cards is left out. Banding applies at every candidate count, with no cap, no pagination, and no `<details>` or other collapse around a band or a card: a reader who ran the scan needs every candidate, and the band already tells them how far each claim can be trusted.

## Diagram patterns

Choose per candidate whichever pattern shows its problem best, and use several across one report
so the cards do not all look alike. Draw with inline SVG or hand-built HTML/CSS; a diagram runtime
such as Mermaid is not allowed.

Every pattern puts the current state in the left column and the deepened state in the right.

| Pattern | Shows | Drawing |
|---|---|---|
| Call flow | a request passing through a chain of small modules | boxes joined by arrows; leakage edges take `stroke: var(--rust)`, deep modules the `.deep` class |
| Round-trip sequence | fewer seam crossings, such as five round-trips cut to one | one vertical lifeline per module, numbered arrows in call order; the two arrow counts carry the comparison |
| Layer stack | shallowness spread over layers | one fixed-height row with a heavy left border per layer a call passes through: six thin rows on the left, one tall row named for the merged responsibility on the right |
| Size bars | an interface nearly as large as its implementation | an interface bar and an implementation bar per module: similar heights on the left (shallow), a short bar over a tall one on the right (deep) |
| Collapsed call tree | calls that should become internal | the call tree as nested boxes on the left; on the right the same tree inside one box, its calls faded |
| Boxes and arrows by hand | a deep module that has to look heavy | bordered `<div>`s and inline SVG arrows, ending in one thick-bordered box with greyed internals, a weight no diagram runtime draws |

A call-flow panel starts like this:

```html
<div class="panel">
  <svg viewBox="0 0 400 120" width="100%" height="120" aria-label="call flow">
    <rect x="10" y="40" width="80" height="40" rx="4" fill="var(--gray-150)" stroke="var(--gray-300)"/>
    <text x="50" y="65" text-anchor="middle" font-size="10">InvoiceController</text>
    <!-- arrows, additional boxes, leak styling -->
  </svg>
</div>
```

## Top recommendation section

A single, larger card: the candidate's name, a sentence saying why it comes first, and an in-page link
to the full card.

## Style guidance

- Self-containment per the baseline: styles and SVG are inline, nothing is fetched
- Size: diagrams stay near 320px high, so a card's two columns are visible without scrolling
- Labels: module names inside a diagram are set small, in capitals, with extra letter spacing
- Color: rust marks leakage and amber marks warnings; apart from those, one palette accent (clay or olive)
- Overall feel: a magazine page with room around each card, not an operations dashboard

## Wording

Name things only with the [vocabulary.md](vocabulary.md) terms and their derived forms:

| Write | Never write in its place |
|---|---|
| module | component, service, unit, layer, wrapper |
| interface | API, signature |
| seam | boundary |
| implementation, depth, deep, shallow, adapter, leverage, locality | (no synonym) |

Each finding is its own sentence and opens with the claim. Lines in the intended style:

- "Seam justified: the mail port has an SMTP adapter in production and a recording adapter in tests."
- "Leak: tax rounding happens in three callers instead of inside `TaxCalculator`."
- "`InvoiceExport` is shallow; its seven methods take as long to learn as the code behind them."
- "After deepening, callers learn `quote(order)` and the tests target it alone."

A win written as "more maintainable" or "nicer structure" fails this rule; restate it as the
leverage or locality gain it stands for.
