# Design resolution — boris-routines-adoption

outcome: early-exit
tier: B (light design)
date: 2026-08-15

## Why the gate exits early

The work introduces no new type system and no new contract shape. Its two contract-bearing
deliverables both sit on surfaces that already exist and are already specified:

- The **findings-file schema is a verbatim existing contract** —
  `plugins/review/skills/fanout/context/default-mode.md:50-79`, titled "Findings-file shape (stable
  contract — the fix action consumes it)". A detector conforms to it; it does not design it.
- The **guardrail derivation is contract-owned mapping rules** —
  `plugins/autonomy/reference/routines.md:88-146`. A catalog row derives its class through those
  rules, never by hand, so no row is a design decision.

The Brief (`../PLAN.md` `## Brief`) already fixes goal, constraints, acceptance criteria, tiers, and
the out-of-scope set. What remained was sequencing plus two shape choices, sketched below.

## Sketch 1 — multi-producer coexistence

The consumer reads one file and merges nothing (`fix-pass-mode.md:3,7`). The resolved shape extends
that consumer rather than adding a component beside it:

```text
consumed(branch) = union of source-findings: over every fix-pass-record
                   whose branch: equals <current-branch> exactly

locate(branch) ->
  R = { f in <memory_dir>/reviews/<branch-slug>/*.md
        | f.frontmatter.type == 'review-findings'
        AND f.frontmatter.branch == <current-branch>
        AND f NOT IN consumed(branch) }
  merge(R) presence-only: collapse rows sharing identical Location AND identical Finding text;
            everything else stays a distinct row, producer named in Surface(s)
```

Two properties this depends on, neither of which holds today:

- **The record must become unconditional.** `fix-pass-mode.md:76` writes it **only** under `--yes` in
  a non-interactive session — "Interactive and headless-stop paths write no record". The Brief's solo
  shape is the interactive path, so a timestamp bound anchored on the record is a no-op there and the
  merge set would grow without limit. Phase 1 therefore changes the record from an
  unwatched-apply review surface into a **consumption ledger** written on every apply path; its
  review-surface role becomes additive rather than defining.
- **The dedup key must be narrower than Stage 3's.** `findings-normalization.md:77` places dedup at
  "Stage 3 Sonnet (semantic merge)" and `:66` orders it to "**Minimize FALSE-MERGE over
  FALSE-SPLIT** — a false merge silently drops a real issue… When in doubt, do NOT merge." The fix
  action runs no LLM stage, so it cannot evaluate that key. Presence-only matching is the largest
  key the consumer can actually compute; the ±3-line bucket would merge two distinct defects at
  `foo.ts:42` and `foo.ts:44` and drop one producer's remediation — reintroducing, inside the fix,
  exactly the hidden-findings failure Phase 1 exists to close.

Degenerate cases: `R` empty keeps today's clean STOP path; `|R| == 1` reduces to today's behavior
exactly, which is the migration's safety property.

Coverage fields are unioned, not picked: `## Surfaces` merges with each producer named, and each
consumed file's `tier:` is reported rather than one winning. `default-mode.md:77` declares those
required "to keep the report honest about coverage", so collapsing them would move the
green-with-hidden-findings class up one layer instead of closing it.

## Sketch 2 — detector finding fields

A detector emits the existing schema. Its own contribution is the two fields the schema leaves to
the producer, which the owner doc will govern:

| Field | Detector obligation |
|---|---|
| `Tier` | machine-computed from a declared rule/threshold, never derived from prose by an LLM |
| `Confidence` | `high` when verified at the call site; **omitted** otherwise — never `low`, which ranks below absent |
| `Location` | `file:line`, repo-relative — line-less findings bucket coarser and false-merge |
| `Finding` / `Action` | cell-escaped — a literal pipe is written backslash-pipe, newlines become spaces |

## Threads deliberately not opened here

- **Per-repo capability detection** carries its own exploration need and an independent commit
  boundary. It is flagged for sub-topic promotion in the plan rather than designed inline.
- **Repo-scope plugin declaration** is blocked on spike
  [#2660](https://github.com/melodic-software/claude-code-plugins/issues/2660); the documented
  fallback needs no design.
