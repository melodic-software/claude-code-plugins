# Adopt the "Finding Your Unknowns" corpus as judgment-preserving contract deltas

- Status: accepted
- Date: 2026-09-01

## Context

A practitioner corpus on artifact-first development — Thariq Shihipar's "A field guide to
Claude Fable 5: Finding your unknowns" (Anthropic blog, 2026-07-06), its X-article
methodology substrate "The Unreasonable Effectiveness of HTML", and a 20-demo example
collection — was ingested as 17 verified digest slices (byte-exact quoting, dual
verification) and worked through a full decision chain: a relentless interview, a
read-only evidence pass grading every named-skill collision, dual fresh-context
validators, external research grounding seven practice areas in primary sources,
blindspot/brainstorm/devils-advocate passes, and a signed single-sheet decision surface.
The working material lived in the branch's contract slice and prunes with it per the
topic-docs convention; the shipping PR (#3592) carries the full plan and verification
record, and the corpus itself is the primary source a future auditor reads.

The corpus's own author warns against exactly the move a plugin marketplace is tempted to
make — turning the material into generator skills — and the marketplace's instruction
economy separately requires observed, repeated stumble evidence before any standing
instruction lands. Genuine alternatives existed: adopt the techniques as new skills,
adopt them as standing instructions, or reject codification entirely.

## Decision

Absorb the corpus behind a per-row evidence-gate classification, with the author's
anti-premature-codification warning treated as a binding constraint:

- CONTRACT / POLICY / CONVENTION rows land now as team conventions adopted at the
  sign-off, as additive lines in the owning skills' bodies with same-commit eval
  expectations, never as generator skills.
- BEHAVIORAL rows never land as standing instructions: they ship as doc lines in
  `docs/FINDING-YOUR-UNKNOWNS.md` plus tracked eval candidates (#3589), awaiting
  observed-stumble evidence.
- `docs/FINDING-YOUR-UNKNOWNS.md` is the graduated reference and the owner doc for the
  reply-affordance and export-button conventions (registry rows point at it,
  owner-doc-first); it quotes the warning byte-faithfully under a stated fair-quotation
  basis.
- Quiz-as-merge-gate reroutes to `verification:confirm`'s existing gate (one mechanism
  per concern); the external-reference port gate is scoped to sources of truth outside
  the repo's tree via the corrector method's declared-step-delta seam; the deviation log
  ships opt-in with a recorded registry trigger (a second plugin reading `DEVIATIONS.md`
  graduates it to an owner doc).
- The corpus's context-engineering companion routes to the incumbent effort recorded in
  [ADR 0004](0004-rightsize-instruction-surfaces-by-incumbent-first-arbitration.md)
  rather than a parallel lane; its three candidate inputs are tracked on the issue
  tracker since that effort's contract slice has graduated.

## Consequences

Eight plugins gained contract lines and minor version bumps (discovery, education,
verification, prototype, planning, discipline, session-flow, implementation), each with
evals extended in the same commit. Two conventions are in force with named conformance
surfaces. Deferred sub-decisions carry recorded triggers on the tracker (#3590 buy-in
skill extension behind demand evidence; #3591 register-schema flag, tweak-likelihood
flip, deviation-log registry row, digest-pipeline hardening). Reversal is possible but
priced: each convention names its conformance surfaces, and the eval expectations
outlive any instruction ablation, which is what makes a future deletion round provable.
