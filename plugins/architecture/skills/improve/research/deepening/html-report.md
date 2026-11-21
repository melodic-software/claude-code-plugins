# HTML Report Format

The deepening review is one HTML page that `node "<plugin-root>/scripts/build-view.mjs" deepening --record <record.json>` builds from the report record below. The skill writes the record, never the page's markup. The builder writes the page to one private path under the OS temp directory and prints it; the path is handed back for the user to open, so the file outlives the invocation.

The page is built on this plugin's chrome reference, [reference/html-chrome.html](../../../../reference/html-chrome.html): its palette, type stacks, light and dark schemes, theme toggle and accessibility floor. Two libraries come from jsDelivr at exact versions: `mermaid` 12.3.0 for graph diagrams and `@tailwindcss/browser` 4.3.5. The content security policy names each file, never the CDN's origin:

```text
default-src 'none'; script-src 'unsafe-inline' https://cdn.jsdelivr.net/npm/@tailwindcss/browser@4.3.5/dist/index.global.js https://cdn.jsdelivr.net/npm/mermaid@12.3.0/dist/mermaid.min.js; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'
```

As of 2026-11-15 both versions were the latest on the npm registry and rendered together under this policy in headless Chromium. Recheck trigger: either package publishes a new major version, or a security advisory names a pinned one; change the pins in `scripts/deepening-report.mjs` and this file together and build the test record again.

**Security.** Every record string is untrusted: paths, glossary terms, ADR excerpts, the repo name, module labels. The builder escapes each into element text, generates the Mermaid source itself, runs Mermaid with `securityLevel: "strict"` and HTML labels off, and refuses to write a page that fails its validator (exactly the two library tags and the one checked-in inline script, no other script, no event-handler attribute, only fragment links). A Mermaid label keeps only letters, digits, spaces and `_ . / : -`: Mermaid reads a label after the browser has undone the escaping, so escaping alone does not hold there, and the builder rejects any other character rather than strip it. Probe: headless Chromium against the pinned Mermaid version, a flowchart label holding an escaped `<img>` tag; with HTML labels on the tag became an element, with them off it did not.

**When the CDN cannot be reached** the page still reads: the chrome's rules and the page's own style lay it out, each Mermaid block shows its source, and the hand-built diagrams draw as they are.

## Report record

One JSON object. Every listed field is required unless marked optional, every text is non-empty, and any other key fails the build with exit 1 and a message naming the candidate and field.

| Field | Holds |
|---|---|
| `schema_version` | `1` |
| `repo` | the repository name |
| `date` | `YYYY-MM-DD` |
| `verification` | the resolved verification level |
| `counts` | the evidence counts, each a number with its noun; `[]` when none (see Header) |
| `top` | the `id` of the top recommendation |
| `top_why` | one sentence saying why it comes first |
| `candidates` | one object per candidate, below |

Each candidate:

| Field | Holds |
|---|---|
| `id` | `[a-z0-9-]{1,32}`, unique; the card's anchor |
| `title` | a few words naming the deepening, such as "Fold the invoice export steps into one module" |
| `recommendation` | `Strong`, `Worth exploring` or `Speculative` |
| `category` | `in-process`, `local-substitutable`, `ports-and-adapters` or `mock` |
| `problem` | the artifact's `problem`, one sentence |
| `solution` | the artifact's `solution`, one sentence |
| `wins` | the artifact's `wins`, one entry per gain (see Wins) |
| `verified` | `reproduced`, `corrected: <one clause>` or `unverified` |
| `files` | one entry per path, written in full |
| `diagram` | `{ "before": <panel>, "after": <panel> }` (see Diagram patterns) |
| `depends_on` | optional: the `id` of the candidate that must be done first |
| `adr` | optional: the recorded decision the candidate touches, one sentence |

## Page order

1. **Header**: the repo name, the date and a one-line legend (a dark, heavy-bordered box is a deep module, a plain box is any other module, a dashed line is a seam, a rust-colored arrow is leakage), then on separate lines the evidence counts, the candidate tally per badge and the verification level.
2. **Top recommendation**: the candidate's title linked to its card, and `top_why`.
3. **Index**: every candidate as a row with its title linked to its card, its badge and its solution.
4. **Cards** in one band per badge, `Strong`, then `Worth exploring`, then `Speculative`. A band with no cards is left out. Banding applies at every count, with no cap, pagination or collapse: a reader who ran the scan needs every candidate, and the band already tells them how far each claim can be trusted.

## Header

Each evidence count comes from a `shallow-signal` or `runtime-claim` that Phase 1.5 reproduced, and is the number the reproduction found, not the scan's: call sites that go through the shallow interface, copies of one function, tests that cover the area. Keep up to four. A count nothing reproduced is left out; when the verification level skipped Phase 1.5, or no reproduced claim carries a number, `counts` is `[]` and the page has no counts line.

## Candidate card

The card holds these parts in this order and nothing else: title and badges (recommendation and dependency category), problem, solution, the before and after diagram, wins, the Verified line, files, then depends-on and the recorded decision when present. A candidate that will not read without a paragraph has a drawing that leaves out the relation the paragraph would explain; add that relation to the diagram data.

**Wins.** Each entry is `<term>: <gain>`, the term one of the eight in [vocabulary.md](../../../../reference/vocabulary.md) and the gain at most six words, such as `locality: a rounding fix, one file` or `leverage: twelve callers, one interface`. Write at least one `leverage` and one `locality` win. A gain written as "more maintainable" fails the wording rule below; restate it as the leverage or locality it stands for.

**Verified.** `reproduced` when Phase 1.5 reproduced the candidate's signal or claim as stated, `corrected: <one clause>` when it held only after a correction (the clause says what changed), `unverified` when nothing was reproduced, including every candidate under a `light` or `off` level. The full notes stay in the artifact's `verification-notes`, never on the card.

## Diagram patterns

Each side of a diagram is one panel, `before` the current state and `after` the deepened one. Pick per side whichever pattern shows the problem best, and vary them across one report so the cards do not all look alike. Every panel takes an optional `caption`.

| `pattern` | Shows | Fields |
|---|---|---|
| `graph` | which module calls which, and where it leaks; the builder writes it as a Mermaid flowchart | `nodes`: `{id, label, deep?}`, `edges` (optional): `{from, to, label?, dashed?, leak?}`, `direction` (optional): `LR` or `TB`. A `leak` edge is drawn rust, a `deep` node dark; labels follow the Mermaid label rule |
| `stack` | shallowness spread over layers | `layers`: one row per layer a call passes through; one row alone is drawn as the deep module |
| `bars` | an interface nearly as large as its implementation | `modules`: `{label, interface, implementation}`, each size a whole number from 0 to 10 |
| `collapse` | calls that should become internal | `calls`: nested on the before side; with `module`, the calls drawn faded inside that one deep box |

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
