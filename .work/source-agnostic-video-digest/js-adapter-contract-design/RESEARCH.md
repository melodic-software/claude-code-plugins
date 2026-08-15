# JS adapter contract design — research index

## Task restatement

Current (2026) best practice for expressing and enforcing a plugin/adapter contract in plain ESM
JavaScript with JSDoc types and vitest — no TypeScript source, no classes. Five sub-questions:
(a) runtime duck-type validation vs JSDoc + `checkJs` vs a shared conformance suite, and what each
catches that the others do not; (b) how to express optional contract methods and their absent-method
default behaviour so the fallback is discoverable rather than implicit in the caller; (c) dispatch —
static registry map vs per-adapter match predicate, including ambiguity, ordering, and fail-closed
behaviour on unknown input; (d) contract evolution — widening a required method's signature or adding
a required method without breaking existing adapters; (e) whether "the contract prescribes WHAT
adapters produce, not HOW" holds up, and the recognized failure mode when a contract leaks the
incumbent implementation's shape into the interface.

Standing instruction from the dispatch: do not anchor on the in-repo precedent (an 88-line contract
whose method set assumes a Playwright `page`) if a better shape exists.

## Section abstracts

- **enforcement-lanes** — Runtime duck-typing, JSDoc+checkJs, and a shared conformance suite catch
  disjoint defect classes; only the suite catches a wrong-behaviour adapter, and this repo's type
  lane is switched off.
- **optional-and-capabilities** — Four mature systems converge on documenting absent-method behaviour
  at the member itself ("if omitted, X"); the defect was never the caller's `if`, it was the
  undocumented `else`, and a method whose honest default is throw is a required method in disguise.
- **dispatch** — Mature systems layer both models — classify input to a key, then look up an
  enumerated registry; yt-dlp's ordering is incidental rather than declared, and the repo's
  interpolated-import dispatch is simultaneously a type-safety and a path-traversal defect that one
  change fixes.
- **evolution** — No surveyed system versions its plugin contract — the contract version IS the
  host's major version; object-vs-positional is the wrong axis (requiredness is the variable), and
  having no external adapter authors removes the need for compatibility machinery but none of the
  need for clarity machinery.
- **design-rule** — The WHAT-not-HOW rule holds directionally but is too strong; the defensible line
  is that a contract may constrain host-owned protocol, never adapter-owned acquisition technology,
  and the failure mode's citable name is Parnas 1972, not "leaky abstraction".

## Section → file

| Section | File | Sub-question |
| --- | --- | --- |
| enforcement-lanes | `RESEARCH-enforcement-lanes.md` | (a) |
| optional-and-capabilities | `RESEARCH-optional-and-capabilities.md` | (b) |
| dispatch | `RESEARCH-dispatch.md` | (c) |
| evolution | `RESEARCH-evolution.md` | (d) |
| design-rule | `RESEARCH-design-rule.md` | (e) |

## Local empirical probes

Run by the topic agent (not delegated), against a scratch project outside the repository mirroring
the extraction `tsconfig.json`, using TypeScript **6.0.3** — the version `package.json` pins:

- `checkJs: false` + a `@type`-annotated object literal with a **missing required method** and an
  **excess property** → `EXIT=0`, zero diagnostics.
- Identical files, `checkJs: true` → `TS2741` (missing) and `TS2353` (excess).
- A method declared with **fewer parameters** than the typedef → no error under either setting.
- `@satisfies` on the same literal → `TS1360` (missing) and `TS2353` (excess); it is available in the
  pinned TypeScript and catches both at the definition site.

Vitest **4.1.10**: a non-`.test.js` module exporting `describeAdapterContract(label, makeAdapter,
caps)` that calls `describe`/`it`, imported by each adapter's test file — works, with correct
per-file attribution and `it.skipIf` rendering optional capabilities as visible skips. The
deliberately-bad adapter in the probe has every required member, correct arity and correct declared
types — it passes the type lane clean — and fails the suite for rejecting where the contract says
return a failure `Result`.

## Next-stage handoff

### Settled

1. **The type lane is inert in this repo.** `checkJs: false` in both extraction `tsconfig.json`
   files, and **zero** `// @ts-check` directives across 25 course-digest + 67 youtube-digest + all
   vendor `.js` files. CI runs `tsc --noEmit` in both lanes and passes — green because it checks
   nothing in the JSDoc contract. Every JSDoc-dependent recommendation below is inert until this
   changes, which makes it the first move.
2. **Only a conformance suite catches wrong behaviour** — wrong return shape, wrong error-signalling,
   wrong absent-method fallback. Demonstrated, not argued.
3. **Dispatch should classify input → key, then look up an enumerated registry.** This is what yt-dlp
   actually does, and it fixes the `any`-typed import and the traversal seam in one change.
4. **Fail closed on unknown input.** yt-dlp's fail-open `GenericIE` is a real best-effort scraper;
   this pipeline has no such thing, and a wrong-adapter digest fails plausibly rather than visibly.
5. **Do not add an `apiVersion` field.** Zero of ~15 surveyed systems have one, and with no external
   adapter authors it buys nothing.
6. **Name the failure mode Parnas 1972**, not "leaky abstraction" — Spolsky's law is a runtime
   phenomenon and imports an inevitability excuse.
7. **The precedent contract is mixed, not uniformly leaked** — `deriveLandingUrl` and
   `buildLessonUrl` are already technology-neutral. Three signatures need re-deriving, not five.

### Recommended order

Turn the type lane on → enumerate adapters in a static registry → re-derive signatures off `page` →
write the conformance suite → `DEFAULTS`/`defineAdapter` for optional members.

### Open decisions

1. **Does `defineAdapter` throw on a missing required method?** (b) says yes; (a) says that is
   near-redundant once the adapter set is closed and type-checked in the same CI run. Reconcilable
   only after the type lane is on — until then (a)'s precondition is unmet and the throw is
   load-bearing. RECOMMENDED: keep the throw; it is ~10 lines and converts a deep `TypeError` into an
   attributable message.
2. **Ambiguity policy at small N.** No surveyed exhibit hard-errors on multiple matches, and
   webpack's `oneOf` is a counter-precedent. RECOMMENDED anyway at N=3: evaluate all predicates and
   throw on >1 match, plus a CI test asserting exactly one match per fixture URL — yt-dlp pays for
   first-match-wins with ~70 hand-written `suitable()` overrides and no test guarding them.
3. **Where classification lives** — host-owned classifier vs per-adapter predicate. RECOMMENDED:
   host-owned while all adapters are first-party; the crossover is governance (contributors who
   cannot edit the host), not adapter count.

### Not researched

- Whether the second source's own acquisition tool imposes constraints the contract must accommodate
  (owned by the ingestion/ASR sibling topic, not this one).
- Performance characteristics of any dispatch model — no exhibit was profiled and no claim here rests
  on speed.
- Whether the repo's Biome configuration would flag `@ts-nocheck` if the type lane were enabled
  (`@typescript-eslint/ban-ts-comment` is the ESLint rule cited in lane (a); the repo uses Biome, and
  I did not verify a Biome equivalent).
