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

## 2026-08-15 — Phase 5: two granted fence extensions (env-table miss + acceptance-grep reach)

- **Auth-lane env reads (behavioral):** the PLAN's six-var table named
  `acquisition/build-yt-dlp-args.js` as the read site for the yt-dlp cookie vars, but
  `acquisition/acquire-yt-dlp-auth.js` also reads two of them via the exported constants.
  Renaming without routing those reads through `resolveEnvWithLegacy` silently broke the
  auth-fallback lane for legacy-only users (proven by three failing tests before the fix:
  the fallback loop fired 6 spawns instead of 1). Fence extended to those two expressions +
  the co-located test; the warn-once set is keyed per legacy name process-wide so
  builder+auth reads cannot double-warn.
- **Fixture literals (mechanical):** the acceptance grep for `youtube-{frames,sheets,extraction}-`
  literals reaches four test files whose production sources were outside the enumerated
  fence (`lib/temp-session-paths.test.js`, `watch/detect-recoverable-bootstrap.test.js`,
  `watch/snapshot-bootstrap.test.js`, `watch/sanitize-slice-temp-paths.test.js`). Literal-only
  renames granted (applied by a scoped `sed` global replace; content verified by grep + full
  suite).
- **New P7 inventory row (from the staged-literal audit):** `setup-deps.mjs`
  `.youtube-extraction.stamp` install stamp is invisible to the `youtube-digest` sweep and was
  absent from the P7 inventory — added there (rename alongside the npm package rename; costs
  one harmless dependency reinstall).

## 2026-08-15 — Phase 2: contract grew two review-driven declarations

Security review (two independent reviewers; the cross-checked SSRF finding was CRITICAL) drove
two additive contract attributes not in the PLAN's Phase 1 attribute list:

- **`allowedExtractors` (required, string|null):** yt-dlp's link-post delegation (upstream
  #9715) meant the probe pass fetched an attacker-chosen outbound URL — cookie-bearing —
  before the provenance guard could read the result. The fix restricts every spawn (probe,
  media, queue preflight) with `--use-extractors` from an adapter declaration; X declares
  `twitter.*` (family verified live: twitter, :amplify, :broadcast, :card, :shortener,
  :spaces), YouTube declares null. A refused delegation (`ERROR: No suitable extractor found
  for URL <url>` — the live-verified refusal shape) is parsed into the well-formed 0-result
  with the blocked link in provenance; a foreign info JSON on disk is now a hard failure.
- **`mediaOptional` capability (closed-by-default):** maps to `--ignore-no-formats-error` in
  BOTH acquire and preflight arg builders, so a valid 0-video X post enqueues metadata-only
  and digests text-only end-to-end (T6 D-A), removing the queue-vs-watch asymmetry. YouTube
  unchanged.

Also from review, recorded here: X fatal patterns gained `/Media #\d+ is not a video/` and
sibling `/Video #\d+ is unavailable/` (deterministic index-selected conditions, not in the
PLAN's three observed literals — additive, same permanence class); the self-referential
`/X acquisition degraded/` retryable pattern was removed (an adapter table describes source
stderr only).

**Deferred with trigger:** the 429 `countsMissing` heuristic classifies a permanently-degraded
post retryable on every attempt. Today no queue-level retry consumes adapter retryable
patterns, so no loop exists. Trigger: any future queue-retry lane adopting adapter patterns
must add an attempt cap or degraded-accept path (doc note lives on the detector).

## 2026-08-15 — Phase 0: `@satisfies` standardization had no applicable sites

The only contract-bearing `@type` object literal in either tree is `utils.js:111` (Node stdlib
`ParseArgsOptionsConfig`, frozen course-digest lane). The `@satisfies` convention lands with
Phase 1's contract authorship instead of a retrofit.
