---
type: llm
---

The repository is a small JavaScript library. Its only export is `buildToc(markdown, options)` in `src/index.js`; `src/parse.js` (heading parsing, code fences, setext headings), `src/slug.js` (slug de-duplication) and `src/tree.js` (nesting and rendering) are imported only by `src/index.js`, and the tests call only `buildToc`.

PASS if every one of these holds:

1. The reply states that the scan found no deepening candidate (or no shallow module worth deepening) in this repository.
2. The reply presents no module as a recommended candidate: no card or numbered candidate with a Strong or Worth exploring badge, and no proposed new interface for `buildToc` or its helpers.
3. Any module the reply mentions is described accurately (for example, `buildToc` as one small interface over the helpers), not as a shallow pass-through.

FAIL if the reply lists one or more candidates to deepen, proposes merging, exporting or wrapping the helpers as a recommended change, calls a helper a shallow module, or ends by asking which candidate to explore when it named none.
