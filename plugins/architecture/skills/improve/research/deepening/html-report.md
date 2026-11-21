# HTML Report Format

Deepening review rendered as one HTML file in the OS temp directory: created through the platform's temp API, resolved deterministically rather than by branching on an injected scratchpad path or `CLAUDE_JOB_DIR`. The path is handed back for the user to open, so the file is never deleted before returning; it outlives the invocation, which is why one run writes exactly one file.

The page is built on this plugin's bundled chrome reference, [reference/html-chrome.html](../../../../reference/html-chrome.html): its palette, type stacks, light and dark schemes, theme toggle and accessibility floor. Two libraries come from a CDN: Tailwind for layout and Mermaid for graph-shaped diagrams. Hand-built divs and inline SVG draw the rest. Use both kinds in one report; a report drawn only with Mermaid looks generic.

**Security baseline.** The report holds to the rendered-views security baseline as stated in Phase 2 of [../../actions/deepening.md](../../actions/deepening.md). Three additions are specific to this report:

- The untrusted data is every repository-derived string: paths, glossary terms, ADR excerpts, repo names, module labels, the `{{repo name}}` in the scaffold's `<title>`, and any other string taken from the scanned repository. Each is escaped before it lands in element text or an attribute.
- Hand-built diagrams are inline SVG shapes and text only, with no `<script>` element inside the SVG: SVG script runs like any page script.
- A repository-derived string inside a Mermaid block keeps only letters, digits, spaces and `_ . / : -`, sits inside a quoted label (`A["src/orders/handler.ts"]`), and is then escaped like any other text. Mermaid reads a label after the browser has undone the escaping, so escaping alone does not hold there. Mermaid runs with `securityLevel: "strict"` and HTML labels off, as the scaffold sets them. Probe: headless Chromium against the pinned Mermaid version, a flowchart label holding an escaped `<img>` tag; with HTML labels on the tag became an element, with them off it did not.

## Scaffold

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4.3.5/dist/index.global.js https://cdn.jsdelivr.net/npm/mermaid@12.3.0/dist/mermaid.min.js; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Deepening review: {{repo name}}</title>
    <style>
      /* CHROME: every rule of the chrome reference's <style> block, copied verbatim. */

      /* Report layer: only what the chrome and Tailwind do not cover. */
      :root { --rust: #B04A3F; --amber: #B45309; }
      body { max-width: 1040px; }
      .badge { border-left: 4px solid var(--muted); padding-left: .5rem; }
      .badge-strong { border-color: var(--olive); }
      .badge-explore { border-color: var(--amber); }
      .badge-speculative { border-color: var(--muted); }
      .seam { stroke-dasharray: 4 4; }
      .leak { stroke: var(--rust); }
      .deep { background: var(--fg); color: var(--bg); }
      .paper { background: var(--white); color: var(--slate); }
    </style>
    <script src="https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4.3.5/dist/index.global.js" integrity="sha256-LQdTYZ03u0RSdhuHT/xq5kKengUesm9ExayDxzYvx7E=" crossorigin="anonymous"></script>
    <script src="https://cdn.jsdelivr.net/npm/mermaid@12.3.0/dist/mermaid.min.js" integrity="sha256-M234A9h6OLcKAec25mbI92AdLOQvXkfI+v5dchB0uaM=" crossorigin="anonymous"></script>
  </head>
  <body>
    <!-- CHROME: the theme toggle (the .rv-bar element), copied verbatim. -->
    <main class="space-y-12">
      <header>...</header>
      <section id="candidates" class="space-y-10">
        <section class="band space-y-8" id="band-strong"><h2>Strong</h2>...</section>
        <section class="band space-y-8" id="band-explore"><h2>Worth exploring</h2>...</section>
        <section class="band space-y-8" id="band-speculative"><h2>Speculative</h2>...</section>
      </section>
      <section id="top-recommendation">...</section>
    </main>
    <!-- CHROME: the toggle's inline script, copied verbatim. -->
    <script>
      if (window.mermaid) {
        mermaid.initialize({ startOnLoad: true, theme: "neutral", securityLevel: "strict", htmlLabels: false, flowchart: { htmlLabels: false } });
      }
    </script>
  </body>
</html>
```

Read the chrome reference and put its three parts where the `CHROME` comments stand. The comment box is left out: a report is read, not answered.

The two library versions are exact, and each URL appears twice: in the policy and on its `<script>` tag. The policy names each file, never the CDN's origin. Each `<script>` tag carries `crossorigin="anonymous"` and the `integrity` hash of its exact file, so a changed file at the pinned URL does not run; both hashes are the base64 sha256 jsDelivr's data API lists for that file (`https://data.jsdelivr.com/v1/packages/npm/<package>@<version>?structure=flat`), read 2026-11-21. As of 2026-11-15: `mermaid` 12.3.0 and `@tailwindcss/browser` 4.3.5, the latest on the npm registry, rendered together under this policy in headless Chromium. Recheck trigger: either package publishes a new major version, or a security advisory names a pinned one; change all four URLs and both hashes together and render the scaffold again.

**When the CDN cannot be reached** the page still reads: the chrome's own rules style the text, each Mermaid block shows its source in its `<pre>`, and the hand-built diagrams draw as they are. So nothing in a card may depend on a library to be legible: no content hidden until a script runs, and no diagram whose only form is a Mermaid block the reader could not follow as text.

## Header

The header holds the repo name, the date, and a one-line legend: a dark, heavy-bordered box is a
deep module, a plain box is any other module, a dashed line is a seam, and a rust-colored arrow is
leakage.

Under the legend sits one line of evidence counts, up to four, each a number with its noun: call
sites that go through the shallow interface, copies of one function, tests that cover the area.
Every count comes from a `shallow-signal` or `runtime-claim` that Phase 1.5 reproduced, and is the
number the reproduction found, not the scan's. A count nothing reproduced is left out; when the
verification level skipped Phase 1.5, or no reproduced claim carries a number, there is no counts
line.

The candidates follow at once, with no opening paragraph.

## Candidate card

One `<article>` per candidate, holding these parts in this order:

- **Title**: a few words naming the deepening, such as "Fold the invoice export steps into one module"
- **Badge row**: the recommendation strength (`Strong` uses `.badge-strong`, olive; `Worth exploring` uses `.badge-explore`, amber; `Speculative` uses `.badge-speculative`, muted gray), each `.badge` with its word in the text color, and the dependency category shown as a tag (`in-process`, `local-substitutable`, `ports & adapters`, `mock`)
- **Files**: one path per line in `var(--mono)`, one step smaller than the body text
- **Before / After diagram**: the two states in adjacent columns; patterns below
- **Problem**: a single sentence
- **Solution**: a single sentence
- **Wins**: one gain per bullet, short enough to take in at a glance, each named with a vocabulary term, for example "locality: a rounding fix now touches one file", "leverage: twelve call sites share one interface", "interface: four entry points become one"
- **ADR callout**, when one applies: a box with an amber border
- **Depends on**, when the candidate needs another one done first: one line naming that candidate, linked to its card

A card carries nothing beyond these parts. A candidate that will not read without a paragraph has a
drawing that leaves out the relation the paragraph would explain; add that relation to the drawing.

## Badge bands

Cards sit in one band per recommendation badge, in badge order: `Strong`, then `Worth exploring`, then `Speculative`. A band with no cards is left out. Banding applies at every candidate count, with no cap, no pagination, and no `<details>` or other collapse around a band or a card: a reader who ran the scan needs every candidate, and the band already tells them how far each claim can be trusted.

## Diagram patterns

Choose per candidate whichever pattern shows its problem best, and use several across one report
so the cards do not all look alike. Every pattern puts the current state in the left column and
the deepened state in the right; the two columns may use different patterns, such as a Mermaid
graph of the tangle on the left and one hand-built deep module on the right.

| Pattern | Shows | Drawing |
|---|---|---|
| Mermaid graph | which module calls which, and where it leaks | a Mermaid `flowchart`; a `linkStyle` line gives each leakage edge the rust stroke, by the edge's position in the block counted from 0, and a `classDef` gives the deep module a dark fill |
| Mermaid sequence | fewer seam crossings, such as five round-trips cut to one | a Mermaid `sequenceDiagram` per column; the two arrow counts carry the comparison |
| Boxes and arrows by hand | a deep module that has to look heavy | bordered `<div>`s and inline SVG arrows, ending in one thick-bordered `.deep` box with grayed internals, a weight Mermaid does not draw |
| Layer stack | shallowness spread over layers | one fixed-height row with a heavy left border per layer a call passes through: six thin rows on the left, one tall row named for the merged responsibility on the right |
| Size bars | an interface nearly as large as its implementation | an interface bar and an implementation bar per module: similar heights on the left (shallow), a short bar over a tall one on the right (deep) |
| Collapsed call tree | calls that should become internal | the call tree as nested boxes on the left; on the right the same tree inside one box, its calls faded |

A Mermaid block sits in a `.paper` card, which stays light in both schemes: Mermaid sets its
colors once when the page loads, and the toggle can change the scheme afterwards.

```html
<div class="paper rounded-lg border border-(--gray-300) p-4">
  <pre class="mermaid">
flowchart LR
  A["InvoiceController"] --> B["InvoiceChecker"]
  B --> C["InvoiceStore"]
  C -. leak .-> D["TaxClient"]
  linkStyle 2 stroke:#B04A3F,stroke-width:2px;
  </pre>
</div>
```

A hand-built panel takes its colors from the chrome's tokens, so it follows the scheme:

```html
<div class="rounded-lg border border-(--gray-300) bg-(--panel) p-4">
  <svg viewBox="0 0 400 120" width="100%" height="120" aria-label="call flow">
    <rect x="10" y="40" width="80" height="40" rx="4" fill="var(--bg)" stroke="var(--muted)"/>
    <text x="50" y="65" text-anchor="middle" font-size="10" fill="var(--fg)">InvoiceController</text>
    <!-- arrows, additional boxes, leak styling -->
  </svg>
</div>
```

## Top recommendation section

A single, larger card: the candidate's name, a sentence saying why it comes first, and an in-page link
to the full card.

## Style guidance

- Layout: Tailwind utilities for grid, spacing, borders and type size; the chrome's rules win where both set a property
- Color: only the chrome's tokens, written as `bg-(--panel)`, `text-(--muted)`, `border-(--gray-300)` or `var(--token)` in SVG; never a Tailwind palette class such as `bg-stone-50`, which does not follow the theme toggle. Rust marks leakage and amber marks warnings; apart from those, one palette accent (clay or olive), never as the only signal
- Scripts: the two libraries, the toggle's script and the Mermaid start call in the scaffold; nothing else, and no interaction beyond the toggle
- Size: diagrams stay near 320px high, so a card's two columns are visible without scrolling
- Labels: module names inside a hand-built diagram are set small, in capitals, with extra letter spacing
- Overall feel: a magazine page with room around each card, not an operations dashboard

## Wording

Name things only with the [vocabulary.md](../../../../reference/vocabulary.md) terms and their derived forms:

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
