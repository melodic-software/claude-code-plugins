# Design resolution — finding-your-unknowns-integration

outcome: early-exit

Tier C under /planning:plan's design-significance gate. This effort introduces no new
types, modules, package topology, or data models: every change is markdown contract text
in existing skill bodies, evals.json expectation strings, per-plugin CHANGELOG/version
metadata, and new reference documentation under docs/. The one structural artifact (the
F1 reference doc) follows an existing precedent shape (top-level SCREAMING-KEBAB doc with
a Contents TOC, per docs/PLUGIN-PHILOSOPHY.md), so no design exploration is warranted.

Type sketch: none needed — no executable surface changes. The only parsed-schema surfaces
in reach (the `### Phase N` heading/tag vocabulary; check-open-questions.sh's 5-field
register rows) are explicitly frozen by the signed contract (signoff-sheet Part G rule 4 /
D37): the plan adds prose around them and never renames them.

Design-tier decisions were resolved upstream by the signed decision chain: interview
rounds 1-3, evidence pass, dual validators, devils-advocate, final validators, operator
sign-off (../signoff-sheet.md, 2026-09-01).
