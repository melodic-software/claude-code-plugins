# L2 progressive disclosure: `L-docs-topics`

57 files, 0 `T2`, all `HUMAN`. Surface: `docs/topics/**`, excluding this sweep's own
`docs/topics/docs-hygiene-repo-sweep/`.

Totals: T1=12, T2=0, T3=2.

Every file is `T3`, so `oversize` cannot fire and nothing here carries a session cost. The topic
tree already uses the repo's topic-docs hub-and-spoke convention correctly: each topic has a
`PLAN.md` or `index.md` hub and a `design/` spoke directory, and the reachability pass found no
orphan under any topic hub except the one noted below.

## Split lane

**No findings.** The largest files are working records of completed efforts, not instruction
surfaces, and splitting a finished record buys nothing. `docs/topics/context-engineering-claude-5/PLAN.md`
at 1,167 lines is a single topic's plan and its size is the topic's size.

## Structure lane

### `missing-toc` (Tier 1)

12 files above 300 lines with no table of contents.

| Path | Lines |
|---|---|
| `docs/topics/context-engineering-claude-5/PLAN.md` | 1,167 |
| `docs/topics/context-engineering-claude-5/design/rerun-contract.md` | 1,031 |
| `docs/topics/context-engineering-claude-5/design/checks-and-sweep.md` | 932 |
| `docs/topics/fable-field-guide-audit/dispositions.md` | 894 |
| `docs/topics/context-engineering-claude-5/design/proportionality-gate.md` | 752 |
| `docs/topics/plugin-audit-port/PLAN.md` | 679 |
| `docs/topics/autonomy-ignition/PLAN.md` | 396 |
| `docs/topics/fresh-eyes-checkpoint-audit/PLAN.md` | 391 |
| `docs/topics/context-engineering-claude-5/design/official-corroboration.md` | 364 |
| `docs/topics/ai-adoption-ladder/design/design-threads.md` | 338 |
| `docs/topics/loop-engineering-codification/PLAN.md` | 333 |
| `docs/topics/ladder-climb-roadmap/PLAN.md` | 327 |

The four `context-engineering-claude-5` files are the concentration: 3,882 lines across a hub and
three design spokes, and the hub cites the spokes by section so a reader enters each one looking
for a named part.

Remediation, all twelve: insert a `## Contents` anchor list under the H1, matching
`plugins/docs-hygiene/skills/audit-progressive-disclosure/context/tier-model.md:3-9`. For
`PLAN.md` files, put the list after the Brief and before the Plan, so a partial read still sees
the brief first.

### `blind-pointer` (Tier 3, awareness only)

`docs/topics/ai-adoption-ladder/design/design-threads.md` cites its nine sibling evidence files by
bare filename with no link and no read condition.

`docs/topics/ai-adoption-ladder/design/design-threads.md:60`:

> `Evidence: RESEARCH-sandbox-bar.md (vendor primary falsified original L1-floor proposal:`

and `:218`:

> `RESEARCH-telemetry-unification.md (primary-sourced; falsification pass demoted "semconv`

The topic hub `docs/topics/ai-adoption-ladder/index.md:9` names the files only as a class:

```text
(closed). Design slice: `design/` (design-threads.md is the contract record; RESEARCH-*.md are
the evidence base;
```

so no individual `RESEARCH-*.md` is reachable by pointer from the hub, and the nine bare-name
citations in `design-threads.md` are the only route.

Awareness only, no treatment: `index.md:20` records all seven work packages as DELIVERED and the
topic slices as pruned. This is a closed effort's evidence base, not a live instruction surface,
and rewriting nine citations in an archived record is maintenance without a reader. Recorded so
the same shape is caught in a live topic.

### `missing-toc`, 100 to 300 lines (Tier 3, awareness only)

32 files, including all 14 `docs/topics/fable-field-guide-audit/findings/S*.md`. No treatment.

## Cross-lane observations

- `docs/topics/context-engineering-claude-5/design/article-sections.md:25` records a prior
  unreachable-file measurement for this repo and names three files. This lane independently
  reproduced two of the three (`plugins/ai-briefing/skills/generate/context/execution-flow.md`
  and `plugins/implementation/skills/implement/context/gotchas.md`), which is a useful
  corroboration for whoever owns the third.
- Several topic directories hold only a `PLAN.md` and a `design/design-resolution.md` of 15 to 83
  lines. Whether a 15-line resolution file earns its own file over a section in the PLAN is an L1
  question.
