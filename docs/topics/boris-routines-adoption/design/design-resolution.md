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
locate(branch) ->
  R = { f in <memory_dir>/reviews/<branch-slug>/*.md
        | f.frontmatter.type == 'review-findings'
        AND f.frontmatter.branch == <current-branch>
        AND f.filename-timestamp > newest(fix-pass-record).filename-timestamp }
  merge(R) by the Stage-3 dedup key: normalized path + ±3-line bucket
```

- The staleness bound reuses the `type: fix-pass-record` marker already written at
  `fix-pass-mode.md:76-93`, so no new artifact and no locking convention is introduced.
- `R` empty keeps today's clean STOP path.
- `|R| == 1` reduces to today's behavior exactly, which is the migration's safety property.

## Sketch 2 — detector finding fields

A detector emits the existing schema. Its own contribution is the two fields the schema leaves to
the producer, which the owner doc will govern:

| Field | Detector obligation |
|---|---|
| `Tier` | machine-computed from a declared rule/threshold, never derived from prose by an LLM |
| `Confidence` | `high` when verified at the call site; **omitted** otherwise — never `low`, which ranks below absent |
| `Location` | `file:line`, repo-relative — line-less findings bucket coarser and false-merge |
| `Finding` / `Action` | cell-escaped: literal `|` as `\|`, newlines as spaces |

## Threads deliberately not opened here

- **Per-repo capability detection** carries its own exploration need and an independent commit
  boundary. It is flagged for sub-topic promotion in the plan rather than designed inline.
- **Repo-scope plugin declaration** is blocked on spike
  [#2660](https://github.com/melodic-software/claude-code-plugins/issues/2660); the documented
  fallback needs no design.
