# Deviations log — source-agnostic video digest

Autonomous-run deviation ledger per the dispatch discipline: Moderate divergences resolved with
the conservative option are logged here at deviation time and reviewed at PR time.

## 2026-08-15 — Phase 0: strict tier pinned off (planned: bare `checkJs` flip)

- **Planned:** flip `checkJs: false → true` in both extraction tsconfigs; fix surfaced diagnostics.
- **Wrong premise:** TypeScript 6.0 defaults `strict` to `true`; neither tsconfig declared it, so
  the flip alone dragged in the full strict tier (408 diagnostics course-digest, 135 youtube-digest).
  Full strict is unreachable inside the phase fence: 48 TS7016 diagnostics trace to the vendored
  `@melodic/video-digestion`, whose only root-cause fix is typing the vendor package
  (`plugins/knowledge/vendor/**`, outside scope); the alternatives are a blanket `any` module stub
  (a suppression in declaration form) or hand-copied upstream declarations.
- **Done instead:** both lanes pin `checkJs: true`, `strict: false`, `strictNullChecks: true`, and
  extend `include` with `**/*.mjs`. `strict` pinned explicitly (caret-ranged `typescript` could move
  the default again); `strictNullChecks` re-enabled deliberately because Phase 1's result envelope
  and four-type error taxonomy are discriminated unions, which the checker silently stops narrowing
  without it (proof: `acquire.js:328` errored without the flag).
- **Blast radius:** type-lane only; zero runtime change (course 91/91, youtube 270/270 vitest green).
  Success criterion 3 ("tsc --noEmit green with checkJs: true") holds as written.
- **Follow-up:** full-strict adoption deferred; trigger = typing or replacing the vendored package.

## 2026-08-15 — Phase 0 sanity-command precision fix

The suppression grep as written in PLAN Phase 0 (`grep -rn … plugins/knowledge/skills/*/extraction`)
matches 116 third-party rows under `node_modules` once deps are installed. Equivalent intent,
corrected form: `git grep -n -e '@ts-ignore' -e '@ts-expect-error' -- 'plugins/knowledge/skills/*/extraction'`
→ 0 rows (tracked source only). Later phases use the `git grep` form.

## 2026-08-15 — Phase 1 remediation: dispatch seam lives in registry.js, not acquire.js

PLAN Phase 1 wrote "`acquire.js` routes source-id + acquisition through the registry/adapter".
The review round found the resulting `acquire.js → registry → youtube.js → acquire.js` static
cycle to be an initialization hazard (empirically verified: entry-order-dependent TDZ throw),
held together only by an unstated nothing-dereferences-adapter-at-module-eval invariant. Fix:
`extractVideoId` moved into the YouTube adapter (its URL grammar) and the `acquireMedia`
dispatch moved into `adapters/registry.js`; `acquire.js` no longer imports the registry, the
graph is acyclic, and the registry consistency check runs at plain module init. Same intent
(all acquisition routes through the adapter seam), sharper seam location. Landed `5020fd4a`.

## 2026-08-15 — Phase 0: `@satisfies` standardization had no applicable sites

The only contract-bearing `@type` object literal in either tree is `utils.js:111` (Node stdlib
`ParseArgsOptionsConfig`, frozen course-digest lane). The `@satisfies` convention lands with
Phase 1's contract authorship instead of a retrofit.
