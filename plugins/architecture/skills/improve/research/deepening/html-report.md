# HTML Report Format

The deepening review is one HTML page that `node "<plugin-root>/scripts/build-view.mjs" deepening --record <record.json>` builds from the report record below. The skill writes the record, never the page's markup. The builder writes the page to one private path under the OS temp directory and prints it; the path is handed back for the user to open, so the file outlives the invocation.

The page is built on this plugin's chrome reference, [reference/html-chrome.html](../../../../reference/html-chrome.html): its palette, type stacks, light and dark schemes, theme toggle and accessibility floor. The page darkens the chrome's light-scheme muted gray so that every label and caption, small text included, keeps at least 4.5:1 contrast on its background in both schemes. Two libraries come from jsDelivr at exact versions: `mermaid` 12.3.0 for graph diagrams and `@tailwindcss/browser` 4.3.5. The content security policy names each file, never the CDN's origin:

```text
default-src 'none'; script-src 'unsafe-inline' https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4.3.5/dist/index.global.js https://cdn.jsdelivr.net/npm/mermaid@12.3.0/dist/mermaid.min.js; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'
```

As of 2026-11-15 both versions were the latest on the npm registry and rendered together under this policy in headless Chromium. Recheck trigger: either package publishes a new major version, or a security advisory names a pinned one; change the pins and both `integrity` hashes in `scripts/deepening-report.mjs` and this file together and build the test record again. The hashes are the base64 sha256 of each pinned file, checked against the files themselves on 2026-11-21: Tailwind `sha256-LQdTYZ03u0RSdhuHT/xq5kKengUesm9ExayDxzYvx7E=`, Mermaid `sha256-M234A9h6OLcKAec25mbI92AdLOQvXkfI+v5dchB0uaM=`.

**Security.** Every record string is untrusted: paths, glossary terms, ADR excerpts, the repo name, module labels. The builder escapes each into element text, generates the Mermaid source itself, runs Mermaid with `securityLevel: "strict"` and HTML labels off, and refuses to write a page that fails its validator (exactly the two library tags, each carrying `crossorigin="anonymous"` and the `integrity` hash of its exact file so a changed file at the pinned URL does not run, and the one checked-in inline script, no other script, no event-handler attribute, only fragment links). A Mermaid label keeps only letters, digits, spaces and `_ . / : -`: Mermaid reads a label after the browser has undone the escaping, so escaping alone does not hold there, and the builder rejects any other character rather than strip it. Probe: headless Chromium against the pinned Mermaid version, a flowchart label holding an escaped `<img>` tag; with HTML labels on the tag became an element, with them off it did not.

**When the CDN cannot be reached** the page still reads: the chrome's rules and the page's own style lay it out, each Mermaid panel shows its graph as a text list (`exporters.py → ledger register`, with a leak or pointer named in words) in place of its source, and the hand-built diagrams draw as they are.

## Report record

One JSON object. Every listed field is required unless marked optional, every text is non-empty, and any other key fails the build with exit 1 and a message naming the candidate and field.

| Field | Holds |
|---|---|
| `schema_version` | `1` |
| `repo` | the repository name |
| `scope` | the paths Phase 1 scanned, as the scope step chose them |
| `commit` | the scanned commit's SHA (`git rev-parse HEAD`), 7 to 40 lowercase hex digits |
| `date` | `YYYY-MM-DD` |
| `verification` | the resolved verification level line, starting with `off`, `light`, `standard` or `strict` |
| `counts` | the evidence counts, each a number with its noun; `[]` when none (see Header) |
| `top` | the `id` of the top recommendation |
| `top_why` | one sentence saying why it comes first |
| `candidates` | one object per candidate, below |
| `kept` | optional: one `{title, reason, files}` per finding whose conclusion is to leave the code as it is (deepening.md, Phase 2); `reason` is one sentence |

Each candidate:

| Field | Holds |
|---|---|
| `id` | `[a-z0-9-]{1,32}`, unique; the card's anchor |
| `title` | a few words naming the deepening, such as "Fold the invoice export steps into one module" |
| `recommendation` | `Strong`, `Worth exploring` or `Speculative` |
| `category` | `in-process`, `local-substitutable`, `ports-and-adapters` or `mock` |
| `problem` | the artifact's `problem`, one sentence |
| `solution` | the artifact's `solution`, one sentence naming a change; a finding that proposes none goes in `kept` instead |
| `wins` | the artifact's `wins`, one entry per gain (see Wins) |
| `verified` | `reproduced`, `corrected: <one clause>` (no semicolon: the builder refuses one) or `unverified` |
| `files` | one entry per path, written in full |
| `diagram` | `{ "before": <panel>, "after": <panel> }` (see Diagram patterns) |
| `depends_on` | optional: the `id` of the candidate that must be done first |
| `adr` | optional: the recorded decision the candidate touches, one sentence |

## Page order

1. **Header**: the repo name; the date, scope and commit; then on separate lines the evidence counts, the candidate tally per badge, and the verification level with what it checked. A key follows, collapsed by default so the top recommendation stays near the top, with one short line per item the page uses and none it does not: each drawing style (deep box, plain box, solid gray arrow for a call or read, dotted gray arrow for a pointer, rust arrow for a leak, and the box, stack and nesting patterns), each badge (Strong defines the deletion test and the two-adapter rule it rests on), each dependency category, each win term, and each Verified value. The builder writes the key from the record; the definitions follow [vocabulary.md](../../../../reference/vocabulary.md), [dependencies.md](dependencies.md) and the acceptance heuristics in [deepening.md](../../actions/deepening.md).
2. **Reader**: below the header, a sidebar lists every candidate beside one card at a time. Below 900 px wide the sidebar sits above the card.
   - **Sidebar**: one group per badge, `Strong`, then `Worth exploring`, then `Speculative`, each headed with its count; a badge with no candidates is left out. The top recommendation leads its group and carries a "Top recommendation" mark. Each item shows the short id (the `id` in capitals, such as `S1`) and title, the badge, the Verified word and the solution, and opens that candidate's card. Every candidate is listed, with no cap, pagination or collapse: a reader who ran the scan needs every candidate.
   - **Card pane**: the page opens on the top recommendation's card, with `top_why` and a "Built on it" list above it that the builder derives from `depends_on`: each candidate that depends on it, directly or through another. `top_why` gives the reason and leaves the names to that list. Previous and next buttons above and below the card step through the sidebar's order, with the card's position (`3 of 23`). The selected card is in the page address, so the back button and a shared link return to it. Every card is in the page, hidden until selected.
   - **Diagrams**: clicking a before or after diagram, or its Enlarge button, opens it enlarged in an overlay that closes on Esc, a click outside it, or its Close button.
3. **Looked at, no change**, when `kept` holds any: each finding's title, reason and files, with no badge and no card, opened from a link at the end of the sidebar and from the header's candidate line, which carries its count.

## Header

Each evidence count comes from a `shallow-signal` or `runtime-claim` that Phase 1.5 reproduced, and is the number the reproduction found, not the scan's: call sites that go through the shallow interface, copies of one function, tests that cover the area. Keep up to four. A count nothing reproduced is left out; when the verification level skipped Phase 1.5, or no reproduced claim carries a number, `counts` is `[]` and the page has no counts line.

## Candidate card

The card holds these parts in this order and nothing else: short id and title, badges (recommendation and dependency category), problem, solution, the before and after diagram, wins, the Verified line, files, then depends-on and the recorded decision when present, and last a link back to the candidate list. A candidate that will not read without a paragraph has a drawing that leaves out the relation the paragraph would explain; add that relation to the diagram data.

**Wins.** Each entry is `<term>: <gain>`, the term one of the eight in [vocabulary.md](../../../../reference/vocabulary.md) and the gain at most six words, such as `locality: a rounding fix, one file` or `leverage: twelve callers, one interface`. Write at least one `leverage` or `locality` win; the builder refuses a card with neither. A gain written as "more maintainable" fails the wording rule below; restate it as the leverage or locality it stands for.

**Verified.** `reproduced` when Phase 1.5 reproduced the candidate's signal or claim as stated, `corrected: <one clause>` when it held only after a correction (the clause says what changed), `unverified` when nothing was reproduced, including every candidate under a `light` or `off` level. The full notes stay in the artifact's `verification-notes`, never on the card.

## Diagram patterns

Each side of a diagram is one panel, `before` the current state and `after` the deepened one. Pick per side whichever pattern shows the problem best, and vary them across one report so the cards do not all look alike. Every panel takes an optional `caption`, which states what the drawing shows: a count in the caption matches the nodes or edges drawn.

| `pattern` | Shows | Fields |
|---|---|---|
| `graph` | which module calls which, and where it leaks; the builder writes it as a Mermaid flowchart | `nodes`: `{id, label, deep?}`, `edges` (optional): `{from, to, label?, dashed?, leak?}`, `direction` (optional): `LR` or `TB`. A `dashed` edge is a pointer (one file refers the reader to another, with no call) and is drawn dotted; a `leak` edge is drawn rust; a `deep` node dark; labels follow the Mermaid label rule. A graph with no edges is drawn as plain boxes side by side, without Mermaid |
| `stack` | shallowness spread over layers | `layers`: one row per layer a call passes through; one row alone is drawn as the deep module |
| `collapse` | calls that should become internal | `calls`: nested on the before side; with `module`, the calls drawn faded inside that one deep box |

Each Mermaid panel takes the width its drawing needs, up to the card's width: two narrow panels sit side by side, a wide one takes the card's full width. A node label wraps only between words, at 260 px. Below 600 px wide a drawing keeps its own size and the panel scrolls sideways, so its text never shrinks below reading size. Every diagram sits on white paper in both themes, so a deep box reads the same in a hand-drawn panel and a Mermaid one, and labels keep the case they were written in. The text list each Mermaid panel carries stays in the page for screen readers when the drawing renders.

## Wording

Name things only with the [vocabulary.md](../../../../reference/vocabulary.md) terms and their derived forms:

| Write | Never write in its place |
|---|---|
| module | component, service, unit, layer, wrapper |
| interface | API, signature |
| seam | boundary |
| implementation, depth, deep, shallow, adapter, leverage, locality | (no synonym) |

Each sentence opens with the claim. Lines in the intended style:

- "Seam justified: the mail port has an SMTP adapter in production and a recording adapter in tests."
- "Leak: tax rounding happens in three callers instead of inside `TaxCalculator`."
- "`InvoiceExport` is shallow; its seven methods take as long to learn as the code behind them."
