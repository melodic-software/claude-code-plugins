# Design-handoff gate ledger

Two runs of `/planning:design-handoff` against `design-threads.md`, both read off the artifact
thread by thread. 14 threads (no T8).

Gate criteria: **RESOLVED** (deciding rationale recorded) · **directional** (direction agreed AND
remaining detail carries a research tag) · **TAGGED-DEFERRED** (explicit tag naming the external
investigation). Unresolved AND untagged → FAIL.

## Run 2 — 2026-08-15, after the delegated resolution round — **PASS**

The user delegated the outstanding decisions ("proceed as you think is best") after run 1's report;
each was resolved by adopting the recommendation already recorded in the artifact, with the
delegation provenance noted in every status line.

| Thread | Verdict | Resolution |
|---|---|---|
| T1 adapter-home | RESOLVED | (a) `extraction/adapters/`; correctness rationale |
| T2a description-rewrite | RESOLVED | Ship widened description, `xlsx` shape, tokens retained |
| T2b skill-rename | RESOLVED | (a) rename to `video-digest`; pin `name:`; breaking-change terms bind the PLAN |
| A1 epic-dir/queue | RESOLVED / TAGGED-DEFERRED | (i) resolved 2026-08-14; (ii) deferred with trigger |
| A2 config/env namespace | RESOLVED | (c) env rename + compatibility read; sixth env var named; adapter-namespacing TAGGED-DEFERRED with trigger |
| T3 contract-shape + dispatch | RESOLVED | Static host-keyed registry; type lane = step zero; priority-scale trigger recorded |
| T4 adapter-method-set | RESOLVED | 5 required methods + declared attributes; stage 2 collapses to shared (7 → 6) |
| T5 transcript-posture | directional | Strategy seam; YT `captions`, X `captions+repair` / `asr`-on-absent; (iv) rejected; three `[T5-ASR-*]` tags |
| T6 multi-media-posture | RESOLVED | Uniform 0..N; D-A = text-only digest with provenance |
| T7 spoke-topology | RESOLVED | (a) `reference/sources/`; explicit conditional routing table mandatory |
| T9 test-seam-posture | RESOLVED | Shared conformance suite, closed-by-default capabilities, X golden fixture |
| T10 x-read-coupling | RESOLVED | Optional agent-lane `/x:read`; sub-decision (ii) adapter canonicalization |
| T11 error-taxonomy | RESOLVED | Four distinct types; per-adapter pattern table; cookie fallback gated on login-required only |
| T12 select-caption managed? | RESOLVED | Not managed (sync-manifest check) |

## Run 1 — 2026-08-15, initial — **FAIL** (3 pass / 11 fail)

Failing: T1, T2a, T2b, A2, T3, T4, T5, T7, T9, T10, T11. Passing: A1, T6, T12.

Root cause of the discrepancy with the prior session's handoff (which reported only T5
outstanding): **research-gate-passed was conflated with thread-resolved** — T3, T7, and T11
recorded "research RETURNED / gate-passed" while their status lines stayed OPEN. Four research
returns were never converted into recorded decisions. A2 was a silent gap the handoff never named.

Method note for future handoffs: a completion criterion phrased as "every thread RESOLVED" must be
checked against the artifact's status lines, not against whether the supporting research landed.
